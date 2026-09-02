extends Node
## Точка входа. Сама сцена пустая: всё содержимое подгружает Dir,
## поэтому у main.tscn нет зависимостей и он стартует мгновенно.

func _ready() -> void:
	if "--selftest" in OS.get_cmdline_user_args():
		_selftest()
		return
	# Экраны меню приходят на этапе 9; пока запуск сразу поднимает мир,
	# чтобы проект показывал город, а не пустую сцену.
	await Dir.load_world(self)
	if "--autodrive" in OS.get_cmdline_user_args():
		await _autodrive()
	_maybe_screenshot()


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
