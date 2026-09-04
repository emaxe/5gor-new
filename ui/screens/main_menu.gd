class_name MainMenu
extends CanvasLayer
## Главное стартовое меню игры с кинематографичной панорамой Пятигорска на фоне.

const UiTheme = preload("res://ui/theme/ui_theme.gd")

## Новая игра — сбрасывает прогресс (см. main.gd:_on_start_game).
signal start_game_requested
## Продолжить с последнего сохранённого слота (см. main.gd:_on_continue_game).
signal continue_requested
signal garage_requested
signal settings_requested
signal achievements_requested

var _root: Control
var _money_val: Label
var _rating_val: Label
var _day_val: Label
var _notice_lbl: Label
var _notice_timer := 0.0
var _btn_continue: Button
var _btn_new_game: Button


func _ready() -> void:
	layer = 90
	_build_ui()
	_update_stats()
	visible = false


func _process(delta: float) -> void:
	if _notice_timer <= 0.0:
		return
	_notice_timer -= delta
	if _notice_timer <= 0.0:
		_notice_lbl.visible = false


## Экраны гаража/настроек/достижений ещё не построены (этапы 15-16) —
## их кнопки в меню откатываются через Dir.push() и показывают эту
## подсказку вместо HUD-тоста, который здесь всё равно скрыт.
func flash_notice(text: String) -> void:
	_notice_lbl.text = text
	_notice_lbl.visible = true
	_notice_timer = 2.0


## Показывается через Dir.set_state(&"menu") — переводит мир в панорамный
## режим и прячет HUD, как раньше делал main.gd вручную.
func show_screen() -> void:
	visible = true
	_update_stats()
	_refresh_continue()
	if Dir.world != null:
		Dir.world.camera.is_cinematic_panorama = true
		if Dir.world.hud != null:
			Dir.world.hud.visible = false


func hide_screen() -> void:
	visible = false
	if Dir.world != null:
		Dir.world.camera.is_cinematic_panorama = false
		Dir.world.camera.snap_to_target()
		if Dir.world.hud != null:
			Dir.world.hud.visible = true


func _update_stats() -> void:
	_money_val.text = "💵 %d ₽" % Game.money
	_rating_val.text = "⭐ %.1f" % Game.rating
	_day_val.text = "🗓️ День %d" % Game.day


## «Продолжить» показывается, только когда есть сохранённый слот — иначе это
## кнопка в никуда. «Новая игра» перепрятывается под неё: слот уже есть,
## явно спрашивать не будем (единственный слот в UI — см. решение об MVP
## в отчёте по этапу 19), но кнопка есть и подписана как перезапись.
func _refresh_continue() -> void:
	var summary := SaveManager.slot_summary(0)
	var has_save := not summary.is_empty()
	_btn_continue.visible = has_save
	if has_save:
		_btn_continue.text = "▶️  ПРОДОЛЖИТЬ (День %d, %d ₽)" % [summary["day"], summary["money"]]
	_btn_new_game.text = "🆕  Новая игра" if has_save else "🚕  НАЧАТЬ СМЕНУ"
	_apply_button_style(_btn_new_game, not has_save)


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Левая панель меню с эффектом градиента
	var menu_card := PanelContainer.new()
	menu_card.name = "MenuCard"
	menu_card.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	menu_card.offset_left = 60
	menu_card.offset_top = 60
	menu_card.offset_right = 440
	menu_card.offset_bottom = -60
	menu_card.add_theme_stylebox_override("panel", UiTheme.panel_style(16, UiTheme.COLOR_TAXI_YELLOW, UiTheme.COLOR_BG_PANEL_SOLID))
	_root.add_child(menu_card)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 18)
	menu_card.add_child(main_vbox)

	# Логотип и заголовок
	var title_vbox := VBoxContainer.new()
	title_vbox.add_theme_constant_override("separation", 2)
	main_vbox.add_child(title_vbox)

	var logo := Label.new()
	logo.text = "5GOR"
	logo.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	logo.add_theme_font_size_override("font_size", 46)
	title_vbox.add_child(logo)

	var sub := Label.new()
	sub.text = "Такси в Пятигорске"
	sub.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_PRIMARY)
	sub.add_theme_font_size_override("font_size", 20)
	title_vbox.add_child(sub)

	var tag := Label.new()
	tag.text = "Курортный open-world симулятор"
	tag.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	tag.add_theme_font_size_override("font_size", 13)
	title_vbox.add_child(tag)

	# Кнопки основного меню
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(btn_vbox)

	_btn_continue = _create_menu_button("▶️  ПРОДОЛЖИТЬ", true)
	_btn_continue.pressed.connect(func() -> void:
		continue_requested.emit()
	)
	_btn_continue.visible = false
	btn_vbox.add_child(_btn_continue)

	_btn_new_game = _create_menu_button("🚕  НАЧАТЬ СМЕНУ", true)
	_btn_new_game.pressed.connect(func() -> void:
		start_game_requested.emit()
	)
	btn_vbox.add_child(_btn_new_game)

	var btn_garage := _create_menu_button("🔧  Гараж и автопарк", false)
	btn_garage.pressed.connect(func() -> void:
		garage_requested.emit()
	)
	btn_vbox.add_child(btn_garage)

	var btn_settings := _create_menu_button("⚙️  Настройки", false)
	btn_settings.pressed.connect(func() -> void:
		settings_requested.emit()
	)
	btn_vbox.add_child(btn_settings)

	var btn_ach := _create_menu_button("🏆  Достижения", false)
	btn_ach.pressed.connect(func() -> void:
		achievements_requested.emit()
	)
	btn_vbox.add_child(btn_ach)

	var btn_quit := _create_menu_button("❌  Выход", false)
	btn_quit.pressed.connect(func() -> void:
		get_tree().quit(0)
	)
	btn_vbox.add_child(btn_quit)

	_notice_lbl = Label.new()
	_notice_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	_notice_lbl.add_theme_font_size_override("font_size", 13)
	_notice_lbl.visible = false
	btn_vbox.add_child(_notice_lbl)

	# Карточка профиля таксиста
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(spacer)

	var profile_panel := PanelContainer.new()
	profile_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(10, UiTheme.COLOR_BORDER, Color(0.10, 0.12, 0.16, 0.90)))
	main_vbox.add_child(profile_panel)

	var prof_vbox := VBoxContainer.new()
	prof_vbox.add_theme_constant_override("separation", 4)
	profile_panel.add_child(prof_vbox)

	var prof_hdr := Label.new()
	prof_hdr.text = "ПРОФИЛЬ ВОДИТЕЛЯ"
	prof_hdr.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	prof_hdr.add_theme_font_size_override("font_size", 12)
	prof_vbox.add_child(prof_hdr)

	var stats_hbox := HBoxContainer.new()
	stats_hbox.add_theme_constant_override("separation", 16)
	prof_vbox.add_child(stats_hbox)

	_money_val = Label.new()
	_money_val.text = "💵 0 ₽"
	_money_val.add_theme_color_override("font_color", UiTheme.COLOR_MONEY_GREEN)
	_money_val.add_theme_font_size_override("font_size", 14)
	stats_hbox.add_child(_money_val)

	_rating_val = Label.new()
	_rating_val.text = "⭐ 0.0"
	_rating_val.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	_rating_val.add_theme_font_size_override("font_size", 14)
	stats_hbox.add_child(_rating_val)

	_day_val = Label.new()
	_day_val.text = "🗓️ День 1"
	_day_val.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_PRIMARY)
	_day_val.add_theme_font_size_override("font_size", 14)
	stats_hbox.add_child(_day_val)


func _create_menu_button(text: String, is_primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(0, 48)
	_apply_button_style(b, is_primary)
	return b


## «Новая игра» — обычно вторичная (акцент на «Продолжить»), но становится
## первичной, когда слота ещё нет и это единственная кнопка запуска —
## _refresh_continue() переключает стиль в рантайме.
func _apply_button_style(b: Button, is_primary: bool) -> void:
	var style := UiTheme.button_primary_style(&"normal") if is_primary else UiTheme.button_secondary_style(&"normal")
	var hover := UiTheme.button_primary_style(&"hover") if is_primary else UiTheme.button_secondary_style(&"hover")
	var pressed := UiTheme.button_primary_style(&"pressed") if is_primary else UiTheme.button_secondary_style(&"pressed")
	var col := Color("#111115") if is_primary else UiTheme.COLOR_TEXT_PRIMARY

	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", col)
