extends Node

const MainMenuScript = preload("res://ui/screens/main_menu.gd")

var _menu: CanvasLayer


func _ready() -> void:
	if "--selftest" in OS.get_cmdline_user_args():
		_selftest()
		return

	await Dir.load_world(self)
	_build_main_menu()

	var args := OS.get_cmdline_user_args()
	if "--benchmark" in args:
		Game.start_shift(1)
		await _benchmark()
		get_tree().quit(0)
		return

	if "--autodrive" in args:
		Game.start_shift(1)
		await _autodrive()
		_maybe_screenshot()
		return

	if "--menu" in args or not ("--no-menu" in args or "--shot" in args):
		_show_main_menu()
	else:
		Game.start_shift(1)

	_maybe_screenshot()


## Строится один раз при загрузке мира и живёт до конца процесса — Dir
## показывает/прячет её через register_screen(&"menu", ...) вместо
## пересоздания при каждом входе в меню.
func _build_main_menu() -> void:
	_menu = MainMenuScript.new()
	_menu.name = "MainMenu"
	add_child(_menu)
	Dir.register_screen(&"menu", _menu)

	_menu.start_game_requested.connect(_on_start_game)
	_menu.garage_requested.connect(func() -> void:
		if not Dir.push(&"garage"):
			_menu.flash_notice("Гараж скоро откроется")
	)
	_menu.settings_requested.connect(func() -> void:
		if not Dir.push(&"settings"):
			_menu.flash_notice("Настройки скоро откроются")
	)
	_menu.achievements_requested.connect(func() -> void:
		if not Dir.push(&"achievements"):
			_menu.flash_notice("Достижения скоро появятся")
	)


func _show_main_menu() -> void:
	if Dir.world == null:
		return
	Dir.set_state(&"menu")


func _on_start_game() -> void:
	Game.start_shift(1)
	Dir.set_state(&"driving")



## Дымовой прогон вождения без участия человека: газ в пол на несколько
## секунд, затем отчёт о пройденном пути и столкновениях.
## Запуск: godot --path . -- --autodrive --shot /tmp/drive.png
func _autodrive() -> void:
	var car: PlayerCar = Dir.world.player
	var start := car.global_position
	# Счётчик в массиве, а не в локальной переменной: лямбда GDScript
	# захватывает локальные значения копией, и `crashes += 1` внутри неё
	# менял бы копию, а не наш счётчик.
	var crashes := [0]
	car.crashed.connect(func(_i: float, _v: StringName) -> void:
		crashes[0] += 1)
	Input.action_press(&"throttle", 1.0)
	var top := 0.0
	for i in 240:
		await get_tree().physics_frame
		top = maxf(top, car.speed_kmh())
	print("автопрогон: путь %.1f м, максимум %.0f км/ч, столкновений %d, топливо %.1f%%"
		% [start.distance_to(car.global_position), top, crashes[0],
			car.runtime.fuel_ratio() * 100.0])

	# Вторая фаза: руль в пол — машина обязана упереться в застройку,
	# а не проехать сквозь дом.
	Input.action_press(&"steer_right", 1.0)
	var before := car.global_position
	for i in 180:
		await get_tree().physics_frame
	Input.action_release(&"steer_right")
	Input.action_release(&"throttle")
	print("съезд с дороги: смещение %.1f м, столкновений %d, урон %.1f%%"
		% [before.distance_to(car.global_position), crashes[0], car.runtime.damage])


## Снимок реального запуска: godot --path . -- --shot /tmp/run.png
## Нужен, потому что headless не рендерит, а проверять картинку на словах нельзя.
func _maybe_screenshot() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shot")
	if i < 0 or i + 1 >= args.size():
		return
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(args[i + 1])
	print("снимок запуска: ", args[i + 1], " (код ", err, ")")
	get_tree().quit(0)


## Замер производительности: godot --path . -- --benchmark
func _benchmark() -> void:
	if Dir.world == null:
		return
	var frames := 300
	var car: PlayerCar = Dir.world.player
	Input.action_press(&"throttle", 1.0)

	var t0 := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
	var t1 := Time.get_ticks_usec()
	Input.action_release(&"throttle")

	var total_ms := (t1 - t0) / 1000.0
	var avg_frame_ms := total_ms / float(frames)
	var fps := float(frames) / (total_ms / 1000.0)
	var w: World = Dir.world
	print("========================================")
	print("BENCHMARK RESULT (%d frames):" % frames)
	print("  Total Time:    %.2f ms" % total_ms)
	print("  Avg Frame:     %.2f ms" % avg_frame_ms)
	print("  FPS:           %.1f" % fps)
	if w != null:
		print("  Subsystem breakdown:")
		print("    Sky:          %.2f ms (%.1f%%)" % [w.prof_sky_us / 1000.0, 100.0 * w.prof_sky_us / (t1 - t0)])
		print("    Lights:       %.2f ms (%.1f%%)" % [w.prof_lights_us / 1000.0, 100.0 * w.prof_lights_us / (t1 - t0)])
		print("    Traffic:      %.2f ms (%.1f%%)" % [w.prof_traffic_us / 1000.0, 100.0 * w.prof_traffic_us / (t1 - t0)])
		print("    Pedestrians:  %.2f ms (%.1f%%)" % [w.prof_pedestrians_us / 1000.0, 100.0 * w.prof_pedestrians_us / (t1 - t0)])
		print("    Orders:       %.2f ms (%.1f%%)" % [w.prof_orders_us / 1000.0, 100.0 * w.prof_orders_us / (t1 - t0)])
	print("  Orphans:       %d" % Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("  Objects:       %d" % Performance.get_monitor(Performance.OBJECT_COUNT))
	print("  Resource Count:%d" % Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	print("  Node Count:    %d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("========================================")



## Быстрая сводка по загруженным данным: godot --headless -- --selftest
func _selftest() -> void:
	print("locale:    ", TranslationServer.get_locale(),
		" -> ", tr("CAR_TAXI_NAME"))
	print("машины:    ", Db.cars.size())
	print("апгрейды:  ", Db.upgrades.items.size())
	print("районы:    ", Db.districts.items.size())
	print("погода:    ", Db.weather.items.size())
	print("заказы:    ", Db.orders.types.size(), " типов, ",
		Db.orders.missions.size(), " миссий")
	print("трафик:    ", Db.traffic.items.size(), " типов")
	print("пешеходы:  ", Db.peds.items.size(), " архетипов")
	print("ачивки:    ", Db.achievements.size())
	print("радио:     ", Db.stations.items.size(), " станций")
	print("гфх:       ", Db.gfx.items.size(), " пресетов")
	print("баланс:    cell=", Db.balance.cell, " деньги=", Db.balance.start_money,
		" трафик=", Db.balance.traffic_count, " пешеходы=", Db.balance.ped_count)
	get_tree().quit(0)

