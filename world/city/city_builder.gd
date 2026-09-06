class_name CityBuilder
extends Node3D
## Фаза C генерации: планы и меши превращаются в узлы сцены.
##
## Всё повторяющееся уходит в MultiMeshInstance3D с общим палитровым
## материалом: деревьев, фонарей, урн и зебр в городе сотни, а draw call
## у каждого типа один. Уникальная геометрия (земля, дороги, здания,
## рельеф) режется на чанки, чтобы работал frustum culling.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

## Слои под разные задачи, чтобы лучи камеры и физики не цепляли лишнего.
const LAYER_WORLD := 1

var field: CityField
## Граф улиц Пятигорска — первичный источник истины о дорогах. Из него живут
## полотно, кварталы, трафик, пешеходы, светофоры и разметка.
var roads: CityGraph
var topology: PyatigorskTopology
var blocks: CityBlocks
var graph: PedGraph
var signals: NodeSignalController
var signal_plan: NodeSignalPlan
var bridges: BridgeGeometry
var plan: CityPlan

var _multimesh_nodes: Array[MultiMeshInstance3D] = []
var _chunk_nodes: Array[MeshInstance3D] = []
## Линзы светофоров: индекс инстанса по стойке (`NodeSignalPlan.lens_index`).
var _lens_mm: MultiMesh


## Полная сборка города. world_seed — живой Game.world_seed (сейв/новая игра),
## а не balance.world_seed напрямую: BalanceData read-only, а сид должен
## меняться между слотами (см. Game.world_seed). Возвращает сводку для лога
## и тестов.
##
## Порядок фаз задан зависимостями: топология -> граф -> (пешеходная сеть,
## светофоры, кварталы, полотно) -> разметка -> план пропса -> меши.
## Топология сама не зависит ни от чего, кроме рельефа поля, и `world_seed`
## на неё не влияет вовсе — это контент, а не генерация.
func build(balance: BalanceData, districts: DistrictCatalog, world_seed: int) -> Dictionary:
	var t_plan := Time.get_ticks_usec()
	field = CityField.new(balance)
	topology = PyatigorskTopology.new()
	roads = topology.build(field)
	# С этого момента «на дороге ли» и «что под колёсами» поле отвечает по
	# графу: у машины игрока, пешего игрока и полиции источник один.
	field.attach_roads(roads)

	# Мешер полотна строится ДО пешеходного графа: он владеет ответом на
	# «есть ли на этой стороне улицы место под тротуар», и пешеходный граф
	# берёт этот ответ, а не считает свой (`PedGraph._side_has_walk_room`).
	var road_mesh := RoadMesh.new(roads, field)
	graph = PedGraph.on_graph(roads, topology.signal_nodes, field.sidewalk,
		road_mesh.walk_room_flags())
	signals = NodeSignalController.build(roads, topology.signal_nodes,
		topology.wave_front_nodes)
	signal_plan = NodeSignalPlan.build(roads, signals)

	blocks = CityBlocks.new()
	blocks.build(roads, topology.node_district, topology.landmark_node)

	var markings := RoadMarkings.new(roads, road_mesh, topology.signal_nodes,
		graph.crossings)
	bridges = BridgeGeometry.new(roads, field)

	plan = CityPlanner.new(field, roads, blocks, topology.node_district,
		districts).plan(world_seed, markings.crossings, signal_plan,
		topology.landmark_node)
	var t_mesh := Time.get_ticks_usec()

	var mesher := CityMesher.new(field, plan)
	var ground := mesher.build_ground(road_mesh, bridges)
	var terrain := mesher.build_terrain()
	var chunks := mesher.build_building_chunks()
	var t_nodes := Time.get_ticks_usec()

	_add_mesh(ground, "Ground")
	_add_mesh(terrain, "Terrain")
	for key: Vector2i in chunks:
		_add_mesh(chunks[key], "Block_%d_%d" % [key.x, key.y])
	_build_props()
	_build_signals()
	_build_markings(markings)

	var t_end := Time.get_ticks_usec()
	return {
		"plan_us": t_mesh - t_plan,
		"mesh_us": t_nodes - t_mesh,
		"nodes_us": t_end - t_nodes,
		"total_us": t_end - t_plan,
		"chunks": chunks.size(),
		"multimeshes": _multimesh_nodes.size(),
		"mesh_nodes": _chunk_nodes.size(),
		"draw_estimate": _chunk_nodes.size() + _multimesh_nodes.size(),
		"nodes": roads.node_count(),
		"edges": roads.edge_count(),
		"blocks": blocks.count(),
	}


func _add_mesh(mesh: ArrayMesh, node_name: String) -> MeshInstance3D:
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = PALETTE_MAT
	add_child(mi)
	_chunk_nodes.append(mi)
	return mi


## Один MultiMesh на тип пропса. use_colors даёт вариацию оттенка без
## дублирования материала — прямой аналог setColorAt из оригинала.
func _add_multimesh(mesh: ArrayMesh, transforms: Array[Transform3D],
		colors: PackedColorArray, node_name: String,
		shadows: bool = false) -> MultiMeshInstance3D:
	if mesh == null or transforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = PALETTE_MAT
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_multimesh_nodes.append(mmi)
	return mmi


func _build_props() -> void:
	# Деревья: два меша (лиственное и хвойное), цвет кроны — на инстанс.
	var decid: Array[Transform3D] = []
	var decid_c := PackedColorArray()
	var pine: Array[Transform3D] = []
	var pine_c := PackedColorArray()
	for i in plan.tree_pos.size():
		var s := plan.tree_scale[i]
		var t := Transform3D(Basis.from_euler(Vector3(0.0, s * 7.3, 0.0))
			.scaled(Vector3(s, s * 1.05, s)), plan.tree_pos[i])
		if plan.tree_kind[i] == 0:
			decid.append(t)
			decid_c.append(plan.tree_color[i])
		else:
			pine.append(t)
			pine_c.append(plan.tree_color[i])
	_add_multimesh(PropMeshes.deciduous_tree(), decid, decid_c, "TreesDeciduous", true)
	_add_multimesh(PropMeshes.pine_tree(), pine, pine_c, "TreesPine", true)

	var bushes: Array[Transform3D] = []
	for i in plan.bush_pos.size():
		var s := plan.bush_scale[i]
		bushes.append(Transform3D(Basis().scaled(Vector3(s, s, s)), plan.bush_pos[i]))
	_add_multimesh(PropMeshes.bush(), bushes,
		_repeat_color(Color("#4a8a42"), bushes.size()), "Bushes")

	var lamps: Array[Transform3D] = []
	for i in plan.lamp_pos.size():
		lamps.append(Transform3D(Basis.from_euler(Vector3(0.0, plan.lamp_yaw[i], 0.0)),
			plan.lamp_pos[i]))
	_add_multimesh(PropMeshes.lamp_post(), lamps, PackedColorArray(), "Lamps")
	_add_multimesh(PropMeshes.lamp_head(), lamps, PackedColorArray(), "LampHeads")

	var bins: Array[Transform3D] = []
	for p in plan.bin_pos:
		bins.append(Transform3D(Basis.IDENTITY, p))
	_add_multimesh(PropMeshes.waste_bin(), bins, PackedColorArray(), "Bins")

	var benches: Array[Transform3D] = []
	for i in plan.bench_pos.size():
		benches.append(Transform3D(
			Basis.from_euler(Vector3(0.0, plan.bench_yaw[i], 0.0)), plan.bench_pos[i]))
	_add_multimesh(PropMeshes.bench(), benches, PackedColorArray(), "Benches")

	# Припаркованные машины: по MultiMesh на силуэт, цвет — на инстанс.
	for kind in 3:
		var cars: Array[Transform3D] = []
		var colors := PackedColorArray()
		for i in plan.parked_pos.size():
			if plan.parked_kind[i] != kind:
				continue
			cars.append(Transform3D(
				Basis.from_euler(Vector3(0.0, plan.parked_yaw[i], 0.0)),
				plan.parked_pos[i]))
			colors.append(plan.parked_color[i])
		_add_multimesh(PropMeshes.parked_car(kind), cars, colors,
			"ParkedCars%d" % kind, true)


## Стойки светофоров и их линзы. Линзы лежат одним MultiMesh; цвет меняется
## записью per-instance, а не обходом узлов.
##
## Стойка привязана к ПОДХОДУ узла, а не к «оси перекрёстка»: у узла степени 3
## или 5 осей не существует. Раскладку задаёт `NodeSignalPlan`, он же и
## переводит (узел, подход, секция) в индекс инстанса.
func _build_signals() -> void:
	var posts: Array[Transform3D] = []
	for i in plan.signal_pos.size():
		posts.append(Transform3D(
			Basis.from_euler(Vector3(0.0, plan.signal_yaw[i], 0.0)), plan.signal_pos[i]))
	_add_multimesh(PropMeshes.signal_post(), posts, PackedColorArray(), "SignalPosts")

	var lenses: Array[Transform3D] = []
	var colors := PackedColorArray()
	for i in plan.signal_pos.size():
		var basis := Basis.from_euler(Vector3(0.0, plan.signal_yaw[i], 0.0))
		for section in NodeSignalPlan.SECTIONS:
			# Секции сверху вниз: красная, жёлтая, зелёная.
			var local := Vector3(0.0, 4.7 - section * 0.5, 0.41)
			lenses.append(Transform3D(basis, plan.signal_pos[i] + basis * local))
			colors.append(_lens_color(section, false))
	var mmi := _add_multimesh(PropMeshes.signal_lens(), lenses, colors, "SignalLenses")
	if mmi != null:
		_lens_mm = mmi.multimesh


## Осевая разметка, стоп-линии и зебры — готовыми трансформами от
## `RoadMarkings`: штрих идёт по полилинии ребра, а не по бесконечной прямой,
## и прерывается перед горловиной узла, а не «в 10 м от координаты оси».
func _build_markings(markings: RoadMarkings) -> void:
	_add_multimesh(PropMeshes.road_dash(), markings.dashes,
		PackedColorArray(), "RoadDashes")
	_add_multimesh(PropMeshes.road_dash(), markings.stop_lines,
		PackedColorArray(), "StopLines")
	_add_multimesh(PropMeshes.zebra_stripe(), markings.zebra,
		PackedColorArray(), "Crosswalks")


## Перекраска линз по текущей фазе. Вызывается менеджером мира не каждый
## кадр, а только когда фаза действительно сменилась.
func refresh_signal_lenses() -> void:
	if _lens_mm == null or signal_plan == null:
		return
	for i in signal_plan.post_count():
		var lit := signals.lamp_index(signal_plan.post_node[i],
			signal_plan.post_approach[i])
		for section in NodeSignalPlan.SECTIONS:
			_lens_mm.set_instance_color(signal_plan.lens_index(i, section),
				_lens_color(section, section == lit))


static func _lens_color(section: int, lit: bool) -> Color:
	match section:
		0:
			return Color("#ff4040") if lit else Color("#3a1010")
		1:
			return Color("#ffb030") if lit else Color("#3a2a10")
		_:
			return Color("#40e040") if lit else Color("#103a10")


static func _repeat_color(c: Color, n: int) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(n)
	out.fill(c)
	return out
