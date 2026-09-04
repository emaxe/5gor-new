class_name MainMenu
extends CanvasLayer
## Главное стартовое меню игры с кинематографичной панорамой Пятигорска на фоне.

const UiTheme = preload("res://ui/theme/ui_theme.gd")

## Старт новой игры в выбранном слоте. slot_index: 0..SaveManager.SLOT_COUNT-1
## (см. main.gd:_on_start_game). Решение о пустом/занятом слоте принимает
## слушатель: для пустого слота slot_index — это просто индекс нового слота,
## для занятого — перезапись.
signal start_game_requested(slot_index: int)
## Продолжить слот slot_index. Слушатель должен убедиться, что слот существует,
## прежде чем рендерить мир.
signal continue_requested(slot_index: int)
## Удалить слот slot_index — карточка слота предлагает long-press.
signal slot_delete_requested(slot_index: int)
signal garage_requested
signal settings_requested
signal achievements_requested

const SLOT_LABEL_FMT_SAVE := "▶️  ПРОДОЛЖИТЬ\nДень %d  •  %d ₽"
const SLOT_LABEL_FMT_EMPTY := "🆕  НОВАЯ ИГРА\nСвободный слот"

var _root: Control
var _money_val: Label
var _rating_val: Label
var _day_val: Label
var _notice_lbl: Label
var _notice_timer := 0.0
var _slot_cards: Array[Button] = []
var _btn_quit: Button


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
			Dir.world.hud.set_menu_hidden(true)


func hide_screen() -> void:
	visible = false
	if Dir.world != null:
		Dir.world.camera.is_cinematic_panorama = false
		Dir.world.camera.snap_to_target()
		if Dir.world.hud != null:
			Dir.world.hud.set_menu_hidden(false)


func _update_stats() -> void:
	_money_val.text = "💵 %d ₽" % Game.money
	_rating_val.text = "⭐ %.1f" % Game.rating
	_day_val.text = "🗓️ День %d" % Game.day


## Карточки слотов строятся один раз в _build_ui (число фиксировано — SLOT_COUNT),
## а _refresh_continue() лишь подменяет текст и стиль под актуальное состояние
## слотов. Карточка занятого слота → Продолжить, пустого → Новая игра.
func _refresh_continue() -> void:
	for i in _slot_cards.size():
		var card: Button = _slot_cards[i]
		var summary := SaveManager.slot_summary(i)
		var has_save := not summary.is_empty()
		if has_save:
			card.text = "СЛОТ %d  •  %s" % [i + 1, SLOT_LABEL_FMT_SAVE % [summary["day"], summary["money"]]]
			_apply_card_style(card, true)
		else:
			card.text = "СЛОТ %d  •  %s" % [i + 1, SLOT_LABEL_FMT_EMPTY]
			_apply_card_style(card, false)


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
	var ver: String = ProjectSettings.get_setting("application/config/version", "0.2.0")
	tag.text = "Курортный open-world симулятор  •  v%s" % ver
	tag.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	tag.add_theme_font_size_override("font_size", 13)
	title_vbox.add_child(tag)

	# Кнопки основного меню
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(btn_vbox)

	# Карточки слотов — три штуки (SaveManager.SLOT_COUNT). Каждая
	# визуально является кнопкой, но на деле это либо «продолжить слот N»,
	# либо «новая игра в слоте N» (выбор делает _refresh_continue()).
	# Long-press (mouse/тач) удаляет слот — для занятого, разумеется.
	var slots_label := Label.new()
	slots_label.text = "СЛОТЫ СОХРАНЕНИЯ"
	slots_label.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	slots_label.add_theme_font_size_override("font_size", 12)
	btn_vbox.add_child(slots_label)

	for i in SaveManager.SLOT_COUNT:
		var card := _create_slot_card(i)
		btn_vbox.add_child(card)
		_slot_cards.append(card)

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

	_btn_quit = _create_menu_button("❌  Выход", false)
	_btn_quit.pressed.connect(func() -> void:
		get_tree().quit(0)
	)
	btn_vbox.add_child(_btn_quit)

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


## Карточка слота — крупнее обычной кнопки, вмещает двухстрочный текст.
## На нажатие отдаёт сигнал с индексом слота (continue для занятого,
## start_game для пустого). long_press (mouse, > 0.6 с удержания) удаляет
## слот через slot_delete_requested — для пустого слота нет, ловим в слушателе.
func _create_slot_card(slot_index: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 70)
	b.add_theme_font_size_override("font_size", 14)
	b.clip_text = true
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_card_style(b, false)
	# Button не эмитит long-press сам — таймер стартует по button_down
	# и гасится по button_up, если отпустили раньше порога.
	var hold_timer := Timer.new()
	hold_timer.wait_time = 0.6
	hold_timer.one_shot = true
	b.add_child(hold_timer)
	b.set_meta(&"long_pressed", false)

	b.button_down.connect(func() -> void:
		b.set_meta(&"long_pressed", false)
		hold_timer.start()
	)
	b.button_up.connect(func() -> void:
		hold_timer.stop()
	)
	hold_timer.timeout.connect(func() -> void:
		b.set_meta(&"long_pressed", true)
		var summary := SaveManager.slot_summary(slot_index)
		if not summary.is_empty():
			slot_delete_requested.emit(slot_index)
	)
	b.pressed.connect(func() -> void:
		# pressed всё равно эмитится при отпускании после long-press — гасим,
		# чтобы не сработали start_game/continue поверх удаления слота.
		if b.get_meta(&"long_pressed", false):
			return
		var summary := SaveManager.slot_summary(slot_index)
		if summary.is_empty():
			start_game_requested.emit(slot_index)
		else:
			continue_requested.emit(slot_index)
	)
	return b


## Стиль карточки слота: жёлтый заполненный, если слот занят (продолжить
## акцентно), и нейтральный с жёлтой обводкой, если слот пустой (новая игра
## вторично).
func _apply_card_style(b: Button, is_filled: bool) -> void:
	var style_normal := StyleBoxFlat.new()
	var style_hover := StyleBoxFlat.new()
	var style_pressed := StyleBoxFlat.new()
	if is_filled:
		style_normal.bg_color = UiTheme.COLOR_TAXI_YELLOW
		style_normal.border_color = UiTheme.COLOR_TAXI_HOVER
		style_hover.bg_color = UiTheme.COLOR_TAXI_HOVER
		style_hover.border_color = Color.WHITE
		style_pressed.bg_color = UiTheme.COLOR_TAXI_PRESSED
		style_pressed.border_color = UiTheme.COLOR_TAXI_YELLOW
	else:
		style_normal.bg_color = UiTheme.COLOR_BG_PANEL_SOLID
		style_normal.border_color = UiTheme.COLOR_TAXI_YELLOW
		style_hover.bg_color = Color(0.20, 0.16, 0.05, 1.0)
		style_hover.border_color = UiTheme.COLOR_TAXI_HOVER
		style_pressed.bg_color = Color(0.16, 0.13, 0.04, 1.0)
		style_pressed.border_color = UiTheme.COLOR_TAXI_PRESSED
	for style in [style_normal, style_hover, style_pressed]:
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.content_margin_top = 8
		style.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", style_normal)
	b.add_theme_stylebox_override("hover", style_hover)
	b.add_theme_stylebox_override("pressed", style_pressed)
	b.add_theme_color_override("font_color",
		Color("#111115") if is_filled else UiTheme.COLOR_TEXT_PRIMARY)


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
