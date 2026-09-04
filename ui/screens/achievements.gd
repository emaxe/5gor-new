class_name AchievementsScreen
extends CanvasLayer
## Список достижений — статус и прогресс берутся из Game.all_stats() и уже
## протестированных AchievementData.is_met()/progress() (schema/achievement_
## data.gd), без отдельной системы разблокировки (та приходит на этапе 16).

const UiTheme = preload("res://ui/theme/ui_theme.gd")

signal closed

var _root: Control
var _list_vbox: VBoxContainer


func _ready() -> void:
	layer = 110
	_build_ui()
	visible = false


func show_screen() -> void:
	visible = true
	_refresh_list()


func hide_screen() -> void:
	visible = false


func _refresh_list() -> void:
	for child in _list_vbox.get_children():
		child.queue_free()
	if Db.achievements == null:
		return
	var stats := Game.all_stats()
	for a: AchievementData in Db.achievements.items:
		_list_vbox.add_child(_build_row(a, stats))


func _build_row(a: AchievementData, stats: Dictionary) -> PanelContainer:
	var met := a.is_met(stats)
	var row := PanelContainer.new()
	var border := UiTheme.COLOR_MONEY_GREEN if met else UiTheme.COLOR_BORDER
	row.add_theme_stylebox_override("panel", UiTheme.panel_style(8, border, UiTheme.COLOR_BG_PANEL))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	row.add_child(vbox)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vbox.add_child(head)

	# a.icon хранит внутренний ключ (например &"earn_100k"), не эмодзи для
	# показа — иконки по ключу появятся вместе с ассетами достижений.
	var status_icon := "✅" if met else "🏆"
	var title := Label.new()
	title.text = "%s %s" % [status_icon, tr(a.display_name)]
	title.add_theme_color_override("font_color", UiTheme.COLOR_MONEY_GREEN if met else UiTheme.COLOR_TAXI_YELLOW)
	title.add_theme_font_size_override("font_size", 15)
	head.add_child(title)

	var desc := Label.new()
	desc.text = tr(a.description)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	desc.add_theme_font_size_override("font_size", 12)
	vbox.add_child(desc)

	var progress := a.progress(stats)
	if not met and progress >= 0.0:
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 8)
		bar.show_percentage = false
		bar.value = progress * 100.0
		vbox.add_child(bar)

	return row


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.03, 0.05, 0.94)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -320
	panel.offset_right = 320
	panel.offset_top = -280
	panel.offset_bottom = 280
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(14, UiTheme.COLOR_TAXI_YELLOW, UiTheme.COLOR_BG_PANEL_SOLID))
	_root.add_child(panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 12)
	panel.add_child(outer_vbox)

	var header := HBoxContainer.new()
	outer_vbox.add_child(header)

	var title := Label.new()
	title.text = "🏆 ДОСТИЖЕНИЯ"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)

	var btn_close := Button.new()
	btn_close.text = "✕"
	btn_close.add_theme_stylebox_override("normal", UiTheme.button_secondary_style(&"normal"))
	btn_close.add_theme_stylebox_override("hover", UiTheme.button_secondary_style(&"hover"))
	btn_close.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_PRIMARY)
	btn_close.pressed.connect(func() -> void:
		closed.emit()
	)
	header.add_child(btn_close)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_list_vbox)
