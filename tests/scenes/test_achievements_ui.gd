extends Node
## Полигон экрана достижений (этап 16): проверяет, что статус «выполнено»
## корректно рисуется как для live is_met(), так и для персистентной
## разблокировки (Game.achievements.is_unlocked()) после reset_shift().

func _ready() -> void:
	Game.bump("orders", "total_orders", 1.0) # first_order — live is_met()
	for _p in 10:
		Game.bump("punches", "total_punches", 1.0) # hot_head — только через unlocked
	Game.reset_shift() # имитирует новую смену: shift_punches обнуляется

	var screen := AchievementsScreen.new()
	add_child(screen)
	screen.show_screen()

	var args := OS.get_cmdline_user_args()
	var i := args.find("--find")
	if i >= 0 and i + 1 < args.size():
		await get_tree().process_frame
		var scroll := screen.find_children("*", "ScrollContainer", true, false)[0] as ScrollContainer
		for label in screen.find_children("*", "Label", true, false):
			if args[i + 1] in (label as Label).text:
				scroll.ensure_control_visible(label as Label)
				break
