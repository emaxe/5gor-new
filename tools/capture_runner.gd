extends Node
## Универсальный съёмщик кадров: инстанцирует сцену, ждёт N кадров, сохраняет
## PNG и выходит. Единственный способ увидеть результат — headless не рендерит.
##
## Запуск:
##   godot --path . tools/capture_runner.tscn -- \
##     --scene res://tests/scenes/test_style.tscn --out /tmp/style.png --frames 40
##
## Дополнительно:
##   --size 1280x720        размер окна
##   --shots a.png,b.png    несколько кадров с интервалом --interval (сек)

var _scene_path := ""
var _out: PackedStringArray = []
var _frames := 30
var _interval := 0.5
var _size := Vector2i(1280, 720)


func _ready() -> void:
	_parse_args()
	if _scene_path.is_empty():
		printerr("не задан --scene")
		get_tree().quit(1)
		return

	DisplayServer.window_set_size(_size)
	get_window().size = _size

	var packed: PackedScene = load(_scene_path)
	if packed == null:
		printerr("не загружена сцена: ", _scene_path)
		get_tree().quit(1)
		return
	add_child(packed.instantiate())

	await _wait_frames(_frames)
	for i in _out.size():
		if i > 0:
			await get_tree().create_timer(_interval).timeout
			await _wait_frames(2)
		_capture(_out[i])
	get_tree().quit(0)


func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _capture(path: String) -> void:
	# Ждём конца кадра, иначе снимок берётся до отрисовки.
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		printerr("не сохранён снимок %s (код %d)" % [path, err])
	else:
		print("снимок: ", path, " ", img.get_width(), "x", img.get_height())


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := args[i]
		var next := args[i + 1] if i + 1 < args.size() else ""
		match a:
			"--scene":
				_scene_path = next
				i += 1
			"--out":
				_out = PackedStringArray([next])
				i += 1
			"--shots":
				_out = next.split(",", false)
				i += 1
			"--frames":
				_frames = next.to_int()
				i += 1
			"--interval":
				_interval = next.to_float()
				i += 1
			"--size":
				var wh := next.split("x")
				if wh.size() == 2:
					_size = Vector2i(wh[0].to_int(), wh[1].to_int())
				i += 1
		i += 1
	if _out.is_empty():
		_out = PackedStringArray(["user://capture.png"])
