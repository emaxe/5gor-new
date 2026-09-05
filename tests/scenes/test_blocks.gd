extends Node3D
## Полигон кварталов и периметральной застройки по графу (`CityBlocks` +
## `BlockPlanner`).
##
## Полотно улиц здесь — контекст снимка, а не производственная геометрия:
## общий мешер дорог по рёбрам живёт этапом 4, задваивать его нельзя.
## Здания строит настоящий `CityMesher`, поэтому на снимке видно ровно то,
## что попадёт в игру, включая поворот корпусов вдоль улицы.
##
## Ракурсы через `-- --view N`:
##   0 квартал неправильной формы вблизи, 1 он же сверху, 2 весь город
##   сверху, 3 с уровня улицы вдоль фронта.
## Номер квартала — `-- --block N` (по умолчанию самый неправильный).

## Полотно кладётся чуть выше земли — та же щель, что у CityMesher.Y_ROAD.
const ROAD_LIFT := 0.06
## Габарит машины для масштаба (city_collision.gd:66).
const CAR_SIZE := Vector3(2.0, 1.5, 4.6)
const COLOR_CAR := Color("#c2503f")
## Тротуарная полоса вдоль полотна, м.
const WALK := 4.0

var field: CityField
var graph: CityGraph
var blocks: CityBlocks
var plan: CityPlan


func _ready() -> void:
	var balance: BalanceData = Db.balance
	field = CityField.new(balance)
	var topo := PyatigorskTopology.new()
	graph = topo.build(field)
	blocks = CityBlocks.new()
	blocks.build(graph, topo.node_district, topo.landmark_node)

	plan = CityPlan.new()
	plan.seed_value = balance.world_seed
	BlockPlanner.new(blocks, field, Db.districts).plan(
		plan, SeededRng.new(balance.world_seed), topo.landmark_node)

	var b := MeshBuilder.new()
	b.plane_xz(Vector3(0.0, -0.05, 0.0), Vector2(1400.0, 1400.0),
		CityMesher.COLOR_GRASS)
	_roads(b)
	_emit(b.commit())
	for mesh in CityMesher.new(field, plan).build_building_chunks().values():
		_emit(mesh)
	_cars()

	_place_camera()
	print("кварталов %d, зданий %d, показан квартал %d (площадь %.0f м², рёбер %d)"
		% [blocks.count(), plan.building_count(), _focus(),
			blocks.area(_focus()), blocks.boundary_count(_focus())])


func _emit(mesh: ArrayMesh) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = preload("res://fx/materials/mat_palette.tres")
	add_child(mi)


func _roads(b: MeshBuilder) -> void:
	for e in graph.edge_count():
		var pts := graph.edge_polyline(e)
		b.ribbon(pts, graph.edge_width(e) + WALK * 2.0,
			CityMesher.COLOR_SIDEWALK, ROAD_LIFT)
		b.ribbon(pts, graph.edge_width(e), CityMesher.COLOR_ROAD,
			ROAD_LIFT + 0.02)


## Машины на полотне у показанного квартала — масштаб и проверка, что дома
## не выходят на проезжую часть.
func _cars() -> void:
	var b := MeshBuilder.new()
	var block := _focus()
	for k in blocks.boundary_count(block):
		var pts := blocks.boundary_plan(block, k)
		@warning_ignore("integer_division")
		var mid: int = pts.size() / 2 # середина полилинии, дробной точки нет
		if mid < 1:
			continue
		var p := pts[mid]
		var dir := (pts[mid] - pts[mid - 1]).normalized()
		var lane := Vector2(-dir.y, dir.x) * (graph.edge_width(
			blocks.boundary_edge(block, k)) * 0.25)
		b.box(Vector3(p.x + lane.x, CAR_SIZE.y * 0.5 + ROAD_LIFT, p.y + lane.y),
			CAR_SIZE, COLOR_CAR,
			Basis.from_euler(Vector3(0.0, atan2(dir.x, dir.y), 0.0)))
	_emit(b.commit())


## Самый неправильный из застроенных кварталов: больше всего рёбер границы.
## Именно он — аналог «сектора между лучом и кольцом» для этой топологии:
## Пятигорск не радиально-кольцевой, а кварталы неправильной формы даёт дуга
## у подножия Машука.
func _focus() -> int:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--block")
	if i >= 0 and i + 1 < args.size():
		return args[i + 1].to_int()
	var best := 0
	var best_edges := -1
	var built := _buildings_per_block()
	for b in blocks.count():
		if int(built.get(b, 0)) < 3 or blocks.boundary_count(b) <= best_edges:
			continue
		best_edges = blocks.boundary_count(b)
		best = b
	return best


func _buildings_per_block() -> Dictionary[int, int]:
	var out: Dictionary[int, int] = {}
	for i in plan.building_count():
		var b := blocks.block_at(plan.building_center(i))
		out[b] = out.get(b, 0) + 1
	return out


func _place_camera() -> void:
	var cam := $Camera3D as Camera3D
	var block := _focus()
	var c := blocks.centroid(block)
	var mid := Vector3(c.x, 0.0, c.y)
	var span := sqrt(blocks.area(block))
	var idx := 0
	var args := OS.get_cmdline_user_args()
	var i := args.find("--view")
	if i >= 0 and i + 1 < args.size():
		idx = args[i + 1].to_int()
	match idx:
		1: # квартал сверху целиком: видна форма полигона и фронт застройки
			cam.position = mid + Vector3(0.0, span * 1.5, span * 0.9)
			cam.look_at(mid, Vector3.UP)
		2: # весь город: плотность застройки и форма кварталов
			cam.position = Vector3(0.0, 520.0, 340.0)
			cam.look_at(Vector3(0.0, 0.0, -40.0), Vector3.UP)
		3: # с уровня улицы вдоль фронта
			cam.position = mid + Vector3(span * 0.9, 2.2, span * 0.9)
			cam.look_at(mid + Vector3(0.0, 6.0, 0.0), Vector3.UP)
		_: # три четверти с высоты дома: фасады вдоль улицы
			cam.position = mid + Vector3(span * 0.8, span * 0.55, span * 0.8)
			cam.look_at(mid + Vector3(0.0, 4.0, 0.0), Vector3.UP)
