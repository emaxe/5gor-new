extends Node3D
## Полигон полотна: `RoadMesh` по всей топологии Пятигорска плюс разметка.
##
## Строится весь город целиком, а не участок — так снимок заодно проверяет,
## что мешер не спотыкается ни на одном из 66 узлов и 94 рёбер. Камера
## переставляется по `-- --view N`:
##   0 перекрёсток 4 подходов (Кирова x Калинина),
##   1 перекрёсток 3 подходов (Т-образный узел на Кирова),
##   2 перекрёсток 5 подходов (Кирова x Лермонтова x переулок к Гроту),
##   3 кольцо привокзальной площади (3 въезда),
##   4 изогнутая улица (бульвар Гагарина),
##   5 насыпь под пандусом путепровода,
##   6 серпантин на Машук,
##   7 общий план центра.

## Размер подстилающей плоскости земли, м — как у `CityMesher.GROUND_SIZE`.
const GROUND := 1700.0

var field: CityField
var topo: PyatigorskTopology
var graph: CityGraph
var roads: RoadMesh
var markings: RoadMarkings


func _ready() -> void:
	field = CityField.new(Db.balance)
	topo = PyatigorskTopology.new()
	graph = topo.build(field)

	var started := Time.get_ticks_usec()
	roads = RoadMesh.new(graph, field)
	var b := MeshBuilder.new()
	b.plane_xz(Vector3(0.0, CityMesher.Y_GROUND, 0.0),
		Vector2(GROUND, GROUND), CityMesher.COLOR_GRASS)
	roads.build_mesh(b)
	BridgeGeometry.new(graph, field).build_mesh(b)
	var mesh := b.commit()
	var elapsed := (Time.get_ticks_usec() - started) / 1000.0
	_emit(mesh)

	# Рельеф Машука — тот же меш, что в живой игре: без него серпантин и
	# Верхняя Машукская дорога висят над пустотой.
	_emit(CityMesher.new(field, null).build_terrain())

	markings = RoadMarkings.new(graph, roads, topo.signal_nodes)
	_multimesh(PropMeshes.road_dash(), markings.dashes, "RoadDashes")
	_multimesh(PropMeshes.road_dash(), markings.stop_lines, "StopLines")
	_multimesh(PropMeshes.zebra_stripe(), markings.zebra, "Crosswalks")

	_place_camera()
	print("полотно города: %.1f мс, штрихов %d, зебр %d"
		% [elapsed, markings.dashes.size(), markings.crossings.size()])


func _emit(mesh: ArrayMesh) -> void:
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = preload("res://fx/materials/mat_palette.tres")
	add_child(mi)


func _multimesh(mesh: ArrayMesh, xforms: Array[Transform3D], name_: String) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = name_
	mmi.material_override = preload("res://fx/materials/mat_palette.tres")
	add_child(mmi)


func _node_at(id: StringName) -> Vector3:
	return graph.node_position(topo.landmark_node.get(id, 0))


func _place_camera() -> void:
	var cam := $Camera3D as Camera3D
	var idx := 0
	var args := OS.get_cmdline_user_args()
	var i := args.find("--view")
	if i >= 0 and i + 1 < args.size():
		idx = args[i + 1].to_int()
	# `--at x,z,h` — свободный ракурс строго сверху для разбора дефектов.
	var at := args.find("--at")
	if at >= 0 and at + 1 < args.size():
		var p := args[at + 1].split(",")
		var target := Vector3(p[0].to_float(), 0.0, p[1].to_float())
		cam.position = target + Vector3(0.0, p[2].to_float(), 0.0)
		# Строго вниз, экранный низ — в сторону +Z: так снимок читается как
		# план города, а не как случайно повёрнутая проекция.
		cam.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		return
	match idx:
		1: # три подхода: Т-образный узел Кирова x Дзержинского
			_look(Vector3(64.0, 1.0, -46.0), Vector3(16.0, 13.0, 22.0))
		2: # Цветник — пять подходов
			_look(Vector3(-32.0, 1.0, 18.0), Vector3(22.0, 19.0, 30.0))
		3: # привокзальное кольцо
			_look(Vector3(160.0, 1.0, 96.0), Vector3(34.0, 34.0, 44.0))
		4: # бульвар Гагарина — кривая улица
			_look(Vector3(-92.0, 1.0, -114.0), Vector3(40.0, 34.0, 26.0))
		5: # пандус путепровода: насыпь сбоку, почти с уровня земли
			_look(Vector3(117.0, 3.0, 222.0), Vector3(34.0, 12.0, -22.0))
		6: # серпантин на Машук
			_look(Vector3(10.0, 40.0, -360.0), Vector3(130.0, 90.0, 90.0))
		7: # общий план центра
			_look(Vector3(20.0, 0.0, 10.0), Vector3(120.0, 190.0, 130.0))
		_: # Кирова x Калинина — четыре подхода
			_look(Vector3(24.0, 1.0, 22.0), Vector3(20.0, 15.0, 26.0))


func _look(target: Vector3, offset: Vector3) -> void:
	var cam := $Camera3D as Camera3D
	cam.position = target + offset
	cam.look_at(target, Vector3.UP)
