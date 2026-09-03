class_name PauseMenu
extends CanvasLayer
## Экран игрового меню паузы.

const UiTheme = preload("res://ui/theme/ui_theme.gd")

signal resume_requested
signal end_shift_requested
signal main_menu_requested

var _root: Control
var _earned_lbl: Label
var _orders_lbl: Label
var _km_lbl: Label


func _ready() -> void:
	layer = 110
	_build_ui()
	visible = false


func show_screen() -> void:
	visible = true
	get_tree().paused = true
	_update_stats()


func hide_screen() -> void:
	visible = false
	get_tree().paused = false


func _update_stats() -> void:
	var earned: int = Game.shift_stats.get("earned", 0)
	var orders_done: int = Game.shift_stats.get("orders", 0)
	var km: float = Game.shift_stats.get("km", 0.0)
	_earned_lbl.text = "Заработано: %d ₽" % earned
	_orders_lbl.text = "Заказов сдано: %d" % orders_done
	_km_lbl.text = "Пройдено: %.1f км" % km


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Полупрозрачный темный фон
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.05, 0.08, 0.82)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	# Центральная карточка паузы
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -190
	panel.offset_right = 190
	panel.offset_top = -240
	panel.offset_bottom = 240
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(14, UiTheme.COLOR_TAXI_YELLOW, UiTheme.COLOR_BG_PANEL_SOLID))
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	# Сводка за смену
	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 6)
	vbox.add_child(stats_box)

	_earned_lbl = _create_stat_lbl("Заработано: 0 ₽", UiTheme.COLOR_MONEY_GREEN)
	stats_box.add_child(_earned_lbl)
	_orders_lbl = _create_stat_lbl("Заказов сдано: 0", UiTheme.COLOR_TEXT_PRIMARY)
	stats_box.add_child(_orders_lbl)
	_km_lbl = _create_stat_lbl("Пройдено: 0.0 км", UiTheme.COLOR_TEXT_MUTED)
	stats_box.add_child(_km_lbl)

	# Кнопки управления
	var btn_resume := _create_btn("Продолжить", UiTheme.button_primary_style(&"normal"), Color("#111115"))
	btn_resume.pressed.connect(func() -> void:
		resume_requested.emit()
	)
	vbox.add_child(btn_resume)

	var btn_end := _create_btn("Завершить смену", UiTheme.button_secondary_style(&"normal"), UiTheme.COLOR_TEXT_PRIMARY)
	btn_end.pressed.connect(func() -> void:
		end_shift_requested.emit()
	)
	vbox.add_child(btn_end)

	var btn_menu := _create_btn("В главное меню", UiTheme.button_secondary_style(&"normal"), UiTheme.COLOR_DANGER_RED)
	btn_menu.pressed.connect(func() -> void:
		main_menu_requested.emit()
	)
	vbox.add_child(btn_menu)


func _create_stat_lbl(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 15)
	return l


func _create_btn(text: String, style: StyleBox, font_color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_stylebox_override("normal", style)
	b.add_theme_stylebox_override("hover", style)
	b.add_theme_stylebox_override("pressed", style)
	b.add_theme_color_override("font_color", font_color)
	b.add_theme_font_size_override("font_size", 16)
	b.custom_minimum_size = Vector2(0, 44)
	return b
