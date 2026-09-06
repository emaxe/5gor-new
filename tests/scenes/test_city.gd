extends Node3D
## Полигон генерации города: полная сборка Пятигорска и облёт ключевых точек.
##
## Ракурсы задаются через `-- --view N` съёмщиком кадров. Точки привязаны к
## топологии Пятигорска (`PyatigorskTopology`), а не к осям сетки:
##   0 общий план центра (Кирова x Калинина),
##   1 уровень улицы на проспекте Кирова,
##   2 регулируемый перекрёсток Кирова x Калинина,
##   3 Машук и серпантин,
##   4 вид сверху на планировку,
##   5 путепровод улицы Козлова над улицей Крайнего,
##   6 кольцо Верхнего рынка,
##   7 дуга у подножия Машука и бульвар Гагарина (кривые улицы).
const VIEWS: Array[Dictionary] = [
	{"pos": Vector3(84.0, 46.0, 92.0), "look": Vector3(10.0, 4.0, 10.0)},
	{"pos": Vector3(-6.0, 2.2, 27.0), "look": Vector3(40.0, 2.6, 22.0)},
	{"pos": Vector3(24.0, 14.0, 52.0), "look": Vector3(24.0, 2.0, 22.0)},
	{"pos": Vector3(150.0, 70.0, -230.0), "look": Vector3(20.0, 30.0, -430.0)},
	{"pos": Vector3(0.0, 330.0, 60.0), "look": Vector3(0.0, 0.0, -30.0)},
	{"pos": Vector3(82.0, 120.0, 184.0), "look": Vector3(82.0, 0.0, 183.0)},
	{"pos": Vector3(96.0, 26.0, 34.0), "look": Vector3(96.0, 2.0, -8.0)},
	{"pos": Vector3(-40.0, 60.0, -80.0), "look": Vector3(-70.0, 0.0, -160.0)},
]

var builder: CityBuilder


func _ready() -> void:
	builder = CityBuilder.new()
	builder.name = "City"
	add_child(builder)
	var stats := builder.build(Db.balance, Db.districts, Db.balance.world_seed)
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
