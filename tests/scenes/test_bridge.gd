extends Node3D
## Полигон путепровода у вокзала: пролёт, опоры, перила и улица под ними.
##
## Строится ровно тот участок графа, который нужен для проверки глазами:
## всё в радиусе RADIUS от середины пролёта. Полотно улиц и насыпь пандусов
## здесь — контекст снимка, а не производственная геометрия: общий мешер
## дорог по рёбрам появится этапом 4, и задваивать его нельзя.
##
## Ракурсы через `-- --view N`:
##   0 сбоку вдоль улицы внизу (дека, опоры, клиренс), 1 три четверти сверху,
##   2 профиль пандуса, 3 проезд под мостом с уровня водителя.

## Радиус выборки рёбер вокруг пролёта, м.
const RADIUS := 130.0
## Полотно кладётся чуть выше земли — та же щель, что у CityMesher.Y_ROAD.
const ROAD_LIFT := 0.06
## Габарит машины для масштаба (как у припаркованных, city_collision.gd:57).
const CAR_SIZE := Vector3(2.0, 1.5, 4.6)
const COLOR_CAR := Color("#c2503f")
## Насыпь под пандусом: земляной откос вместо провала под полотном.
const COLOR_EMBANKMENT := Color("#7d7466")

var field: CityField
var graph: CityGraph
var bridge: BridgeGeometry


func _ready() -> void:
	field = CityField.new(Db.balance)
	graph = PyatigorskTopology.new().build(field)
	bridge = BridgeGeometry.new(graph, field)

	var b := MeshBuilder.new()
	b.plane_xz(Vector3(_mid().x, -0.02, _mid().z), Vector2(700.0, 700.0),
		CityMesher.COLOR_GRASS)
	_roads(b)
	bridge.build_mesh(b)
	_cars(b)
	_emit(b)

	_place_camera()
	print("пролёт: %.1f м, плит %d, опор %d (пропущено над полотном %d)"
		% [graph.edge_length(_deck()), bridge.deck_count(), bridge.pier_count(),
			bridge.piers_over_road])


func _emit(b: MeshBuilder) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = preload("res://fx/materials/mat_palette.tres")
	add_child(mi)


func _roads(b: MeshBuilder) -> void:
	var mid := _mid()
	for e in graph.edge_count():
		if e == _deck():
			continue # полотно деки строит сам BridgeGeometry
		var pts := graph.edge_polyline(e)
		if Vector2(pts[0].x, pts[0].z).distance_to(Vector2(mid.x, mid.z)) > RADIUS:
			continue
		b.ribbon(pts, graph.edge_width(e), CityMesher.COLOR_ROAD, ROAD_LIFT)
		if graph.edge_kind(e) == CityGraph.EdgeKind.RAMP:
			_embankment(b, pts, graph.edge_width(e))


## Откос насыпи под пандусом: две боковые стенки от земли до кромки полотна.
## Порядок вершин (низ-начало, низ-конец, верх-конец, верх-начало) даёт
## нормаль по направлению dir x UP, то есть наружу правой стенки; левая
## обходится в обратную сторону.
func _embankment(b: MeshBuilder, pts: PackedVector3Array, width: float) -> void:
	for k in range(1, pts.size()):
		var p0 := pts[k - 1]
		var p1 := pts[k]
		var dir := (p1 - p0)
		dir.y = 0.0
		if dir.length_squared() < 1e-6:
			continue
		var off := dir.normalized().cross(Vector3.UP) * width * 0.5
		for s: float in [-1.0, 1.0]:
			var a := p0 + off * s
			var c := p1 + off * s
			var a0 := Vector3(a.x, field.height_at(a.x, a.z), a.z)
			var c0 := Vector3(c.x, field.height_at(c.x, c.z), c.z)
			if s > 0.0:
				b.quad(a0, c0, c, a, COLOR_EMBANKMENT)
			else:
				b.quad(c0, a0, a, c, COLOR_EMBANKMENT)

	# Заглушка торца насыпи со стороны моста
	if pts.size() >= 2:
		for is_end in [false, true]:
			var idx := pts.size() - 1 if is_end else 0
			var next_idx := pts.size() - 2 if is_end else 1
			var p := pts[idx]
			var seg_dir := (p - pts[next_idx]) if is_end else (pts[next_idx] - p)
			seg_dir.y = 0.0
			if seg_dir.length_squared() < 1e-6:
				continue
			var rise := p.y - field.height_at(p.x, p.z)
			if rise <= 0.5:
				continue
			var off := seg_dir.normalized().cross(Vector3.UP) * width * 0.5
			var r := p + off
			var l := p - off
			var r0 := Vector3(r.x, field.height_at(r.x, r.z), r.z)
			var l0 := Vector3(l.x, field.height_at(l.x, l.z), l.z)
			if is_end:
				b.quad(l0, l, r, r0, COLOR_EMBANKMENT)
			else:
				b.quad(r0, r, l, l0, COLOR_EMBANKMENT)



## Две машины для масштаба: одна под декой на улице внизу, вторая на деке.
func _cars(b: MeshBuilder) -> void:
	var mid := _mid()
	var below := graph.query_nearest_edge(Vector3(mid.x, 0.0, mid.z), 40.0)
	var road := graph.hit_point
	var street := _direction(below)
	b.box(road + Vector3(0.0, CAR_SIZE.y * 0.5 + ROAD_LIFT, 0.0), CAR_SIZE,
		COLOR_CAR, Basis.from_euler(Vector3(0.0, atan2(street.x, street.z), 0.0)))
	var deck_dir := _direction(_deck())
	b.box(mid + Vector3(0.0, CAR_SIZE.y * 0.5, 0.0), CAR_SIZE, COLOR_CAR,
		Basis.from_euler(Vector3(0.0, atan2(deck_dir.x, deck_dir.z), 0.0)))


func _deck() -> int:
	for e in graph.edge_count():
		if graph.edge_kind(e) == CityGraph.EdgeKind.BRIDGE:
			return e
	return -1


func _mid() -> Vector3:
	var pts := graph.edge_polyline(_deck())
	return pts[0].lerp(pts[pts.size() - 1], 0.5)


func _direction(edge: int) -> Vector3:
	var pts := graph.edge_polyline(edge)
	var d := pts[pts.size() - 1] - pts[0]
	d.y = 0.0
	return d.normalized()


func _place_camera() -> void:
	var cam := $Camera3D as Camera3D
	var mid := _mid()
	graph.query_nearest_edge(Vector3(mid.x, 0.0, mid.z), 40.0)
	var street := _direction(graph.hit_edge)
	var across := street.cross(Vector3.UP)
	var axis := _direction(_deck())
	var idx := 0
	var args := OS.get_cmdline_user_args()
	var i := args.find("--view")
	if i >= 0 and i + 1 < args.size():
		idx = args[i + 1].to_int()
	match idx:
		1: # три четверти сверху: видна вся развязка с пандусами
			cam.position = mid + across * 70.0 - axis * 45.0 + Vector3(0.0, 42.0, 0.0)
			cam.look_at(mid, Vector3.UP)
		2: # профиль южного пандуса: подъём с земли на ярус 1
			var ramp := mid - axis * 40.0
			cam.position = ramp + axis.cross(Vector3.UP) * 62.0 + Vector3(0.0, 12.0, 0.0)
			cam.look_at(ramp + Vector3(0.0, 2.0, 0.0), Vector3.UP)
		3: # с места водителя под мостом
			cam.position = mid - street * 34.0 + Vector3(0.0, -5.3, 0.0)
			cam.look_at(mid + Vector3(0.0, -4.0, 0.0), Vector3.UP)
		_: # сбоку вдоль улицы внизу: дека, опоры и клиренс над машиной
			cam.position = mid + street * 36.0 + Vector3(0.0, -3.4, 0.0)
			cam.look_at(mid + Vector3(0.0, -3.0, 0.0), Vector3.UP)
