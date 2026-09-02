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
var graph: PedGraph
var plan: CityPlan
var lights: TrafficLightController

var _multimesh_nodes: Array[MultiMeshInstance3D] = []
var _chunk_nodes: Array[MeshInstance3D] = []
## Линзы светофоров: индекс инстанса по (перекрёсток, ось, секция).
var _lens_mm: MultiMesh
var _lens_index: Dictionary[int, int] = {}


## Полная сборка города. Возвращает сводку для лога и тестов.
func build(balance: BalanceData, districts: DistrictCatalog) -> Dictionary:
	var t_plan := Time.get_ticks_usec()
	field = CityField.new(balance)
	graph = PedGraph.new(field)
	lights = TrafficLightController.new(field)
	plan = CityPlanner.new(field, graph, districts).plan(balance.world_seed)
	var t_mesh := Time.get_ticks_usec()

	var mesher := CityMesher.new(field, plan)
	var ground := mesher.build_ground()
	var terrain := mesher.build_terrain()
	var chunks := mesher.build_building_chunks()
	var t_nodes := Time.get_ticks_usec()

	_add_mesh(ground, "Ground")
	_add_mesh(terrain, "Terrain")
	for key: Vector2i in chunks:
		_add_mesh(chunks[key], "Block_%d_%d" % [key.x, key.y])
	_build_props()
	_build_signals()
	_build_road_markings()
	_build_crosswalks()

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
func _build_signals() -> void:
	var posts: Array[Transform3D] = []
	for i in plan.signal_pos.size():
		posts.append(Transform3D(
			Basis.from_euler(Vector3(0.0, plan.signal_yaw[i], 0.0)), plan.signal_pos[i]))
	_add_multimesh(PropMeshes.signal_post(), posts, PackedColorArray(), "SignalPosts")

	var lenses: Array[Transform3D] = []
	var colors := PackedColorArray()
	_lens_index.clear()
	for i in plan.signal_pos.size():
		var basis := Basis.from_euler(Vector3(0.0, plan.signal_yaw[i], 0.0))
		for section in 3:
			# Секции сверху вниз: красная, жёлтая, зелёная.
			var local := Vector3(0.0, 4.7 - section * 0.5, 0.41)
			lenses.append(Transform3D(basis, plan.signal_pos[i] + basis * local))
			colors.append(_lens_color(section, false))
		_lens_index[i] = (i * 3)
	var mmi := _add_multimesh(PropMeshes.signal_lens(), lenses, colors, "SignalLenses")
	if mmi != null:
		_lens_mm = mmi.multimesh


## Осевая разметка и стоп-линии. Штрихи не рисуются в зоне перекрёстка —
## там разметка прерывается, как на настоящей дороге.
func _build_road_markings() -> void:
	const DASH_STEP := 6.4
	const INTERSECTION_CLEAR := 10.0
	var y := CityMesher.Y_MARKING
	var span := 248.0
	var dashes: Array[Transform3D] = []
	var along_z := Basis.IDENTITY
	var along_x := Basis.from_euler(Vector3(0.0, PI * 0.5, 0.0))

	for c in field.road_axes:
		var v := -span
		while v <= span:
			if not _near_intersection(v, INTERSECTION_CLEAR):
				dashes.append(Transform3D(along_z, Vector3(c, y, v)))
				dashes.append(Transform3D(along_x, Vector3(v, y, c)))
			v += DASH_STEP
	_add_multimesh(PropMeshes.road_dash(), dashes, PackedColorArray(), "RoadDashes")

	# Стоп-линии перед регулируемыми перекрёстками.
	var stops: Array[Transform3D] = []
	for i in PedGraph.AXES:
		for j in PedGraph.AXES:
			if not PedGraph.is_signalized(i, j):
				continue
			var cx := field.road_axes[i]
			var cz := field.road_axes[j]
			for s: float in [-1.0, 1.0]:
				# На своей половине полотна, перед зеброй.
				stops.append(Transform3D(along_x.scaled(Vector3(1.0, 1.0, 24.0)),
					Vector3(cx - s * field.road_half * 0.5, y, cz + s * 10.5)))
				stops.append(Transform3D(along_z.scaled(Vector3(1.0, 1.0, 24.0)),
					Vector3(cx + s * 10.5, y, cz + s * field.road_half * 0.5)))
	_add_multimesh(PropMeshes.road_dash(), stops, PackedColorArray(), "StopLines")


## Попадает ли координата вдоль дороги в зону перекрёстка.
func _near_intersection(v: float, clearance: float) -> bool:
	for c in field.road_axes:
		if absf(v - c) < clearance:
			return true
	return false


func _build_crosswalks() -> void:
	# Зебра — шесть полос; собирается из списка переходов графа, поэтому
	# разметка не может разъехаться с логикой ПДД.
	var stripes: Array[Transform3D] = []
	for i in plan.crosswalk_pos.size():
		var yaw := plan.crosswalk_yaw[i]
		var basis := Basis.from_euler(Vector3(0.0, yaw, 0.0))
		var center := plan.crosswalk_pos[i]
		center.y = CityMesher.Y_MARKING
		for k in 6:
			var offset := (k - 2.5) * 1.1
			stripes.append(Transform3D(basis, center + basis * Vector3(offset, 0.0, 0.0)))
	_add_multimesh(PropMeshes.zebra_stripe(), stripes, PackedColorArray(), "Crosswalks")


## Перекраска линз по текущей фазе. Вызывается менеджером мира не каждый
## кадр, а только когда фаза действительно сменилась.
func refresh_signal_lenses() -> void:
	if _lens_mm == null:
		return
	for i in plan.signal_pos.size():
		var isec: int = plan.signal_intersection[i]
		@warning_ignore("integer_division")
		var gi: int = isec / PedGraph.AXES
		var lit := lights.lamp_index(gi, plan.signal_axis[i])
		var base: int = _lens_index[i]
		for section in 3:
			_lens_mm.set_instance_color(base + section,
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
