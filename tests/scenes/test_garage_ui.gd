extends Node
## Полигон гаража (этап 15): вкладки «Тюнинг» и «Обслуживание» без активного
## мира — Dir.world == null, вкладка «Обслуживание» показывает заглушку,
## это ожидаемо вне заезда.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--in-run" in args:
		_fake_active_run()

	var screen := GarageScreen.new()
	add_child(screen)
	screen.show_screen()

	var i := args.find("--tab")
	if i >= 0 and i + 1 < args.size():
		var tabs := screen.find_children("*", "TabContainer", true, false)
		if not tabs.is_empty():
			(tabs[0] as TabContainer).current_tab = args[i + 1].to_int()


## Имитирует активный заезд ради вкладки «Обслуживание»: реальный World
## слишком дорог (генерация города), достаточно машины с runtime-состоянием.
## World нарочно не добавляется в дерево — иначе World._process() падает на
## отсутствующих sky/city, которых у голого World.new() нет.
func _fake_active_run() -> void:
	var w := World.new()
	w.player = PlayerCar.new()
	w.player.setup(Db.cars.get_car(&"taxi"), Db.upgrades, CityField.new(Db.balance))
	w.player.runtime.damage = 35.0
	w.player.runtime.dirt = 0.6
	w.player.runtime.fuel = 20.0
	Dir.world = w
