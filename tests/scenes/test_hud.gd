extends Node
## Полигон HUD (этап 14, переработка раскладки): проверяет угловую раскладку
## и стек тостов на снимке. World нарочно не добавляется в дерево — иначе
## World._process() падает на отсутствующих sky/city (см. test_garage_ui.gd).
##
## Флаги: --mode full|minimal|hidden — режим HUD; --burst — залп из трёх
## тостов разного уровня, демонстрирующий приоритет и стек справа.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()

	var mode_i := args.find("--mode")
	if mode_i >= 0 and mode_i + 1 < args.size():
		Prefs.hud_mode = StringName(args[mode_i + 1])

	var w := _fake_world()

	var hud := Hud.new()
	add_child(hud)
	hud.setup(w)

	# Верхние плашки: деньги/рейтинг/розыск, время/погода/слот.
	Bus.money_changed.emit(480, 480)
	Bus.rating_changed.emit(4.7)
	Bus.wanted_changed.emit(2)
	Bus.time_changed.emit(9.85, 1, false)
	Bus.weather_changed.emit(&"rain")
	SaveManager.current_slot = 2

	Bus.notify.emit(&"dialogue", "Здравствуйте, шеф! Едем к Провалу!",
		{"speaker": "Пассажир", "avatar": "👨‍💼"})

	if Db.achievements != null and not Db.achievements.items.is_empty():
		Bus.achievement_unlocked.emit(Db.achievements.items[0].id)

	if "--burst" in args:
		Bus.notify.emit(&"toast", "Вы сбили пешехода! -300 ₽, рейтинг -15", {"level": &"critical"})
		Bus.notify.emit(&"toast", "🔥 Серия сближений ×2! (+70 ₽)", {"level": &"reward"})
		Bus.notify.emit(&"toast", "⚡ Опасное сближение! +35 ₽", {"level": &"reward"})
		Bus.notify.emit(&"toast", "Новый заказ в городе!", {})


## Активная поездка ради карточки заказа/приборки — реальный World слишком
## дорог (генерация города), достаточно машины и заказа с нужными полями.
func _fake_world() -> World:
	var w := World.new()
	w.player = PlayerCar.new()
	# HUD читает car.global_position (кнопка взаимодействия, GPS) — в
	# отличие от test_garage_ui.gd машину нужно реально добавить в дерево,
	# иначе Node3D.global_position падает вне is_inside_tree().
	add_child(w.player)
	w.player.setup(Db.cars.get_car(&"taxi"), Db.upgrades, CityField.new(Db.balance))
	w.player.place(Vector3.ZERO, 0.0)
	w.player.runtime.fuel = 28.0
	w.player.runtime.damage = 22.0
	w.player.runtime.dirt = 0.45
	w.player.runtime.style = 0.72
	w.player.motion.speed = 18.0
	w.in_car = true

	var order := Order.new()
	order.state = &"active"  # иначе current_target_pos() вернёт pickup_pos (0,0)
	order.client_avatar = "👨‍💼"
	order.title = "Заказ такси"
	order.est_pay = 640
	order.time_limit = 240.0
	order.timer = 150.0
	order.drops = [{"pos": Vector2(120.0, 40.0), "name": "Санаторий «Лесной»", "district": &"kurort"}]

	var orders := OrderManager.new()
	orders.active_order = order
	w.orders = orders

	return w
