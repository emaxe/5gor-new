extends Node3D
## Полигон генерации города: полная сборка Пятигорска и облёт ключевых точек.
##
## Ракурсы задаются через `-- --view N` съёмщиком кадров:
##   0 общий план центра, 1 уровень улицы, 2 перекрёсток со светофором,
##   3 Машук и серпантин, 4 вид сверху на планировку.

const VIEWS: Array[Dictionary] = [
	{"pos": Vector3(70.0, 42.0, 90.0), "look": Vector3(0.0, 4.0, 0.0)},
	{"pos": Vector3(9.5, 2.2, 40.0), "look": Vector3(2.0, 2.0, -20.0)},
	{"pos": Vector3(-52.0, 9.0, -44.0), "look": Vector3(-64.0, 2.0, -64.0)},
	{"pos": Vector3(150.0, 70.0, -230.0), "look": Vector3(20.0, 30.0, -430.0)},
	{"pos": Vector3(0.0, 330.0, 60.0), "look": Vector3(0.0, 0.0, -30.0)},
]

var builder: CityBuilder


func _ready() -> void:
	builder = CityBuilder.new()
	builder.name = "City"
	add_child(builder)
	var stats := builder.build(Db.balance, Db.districts)
	builder.refresh_signal_lenses()
	_place_camera()
	_report(stats)


func _report(stats: Dictionary) -> void:
	print("город собран: план %.1f мс, меши %.1f мс, узлы %.1f мс, всего %.1f мс"
		% [stats["plan_us"] / 1000.0, stats["mesh_us"] / 1000.0,
			stats["nodes_us"] / 1000.0, stats["total_us"] / 1000.0])
	print("  чанков зданий: %d, MultiMesh: %d, всего мешей: %d"
		% [stats["chunks"], stats["multimeshes"], stats["mesh_nodes"]])
	var p := builder.plan
	print("  ", p.summary())


func _place_camera() -> void:
	var cam := $Camera3D as Camera3D
	var idx := 0
	var args := OS.get_cmdline_user_args()
	var i := args.find("--view")
	if i >= 0 and i + 1 < args.size():
		idx = clampi(args[i + 1].to_int(), 0, VIEWS.size() - 1)
	cam.position = VIEWS[idx]["pos"]
	cam.look_at(VIEWS[idx]["look"], Vector3.UP)
