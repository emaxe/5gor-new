class_name SettingsScreen
extends CanvasLayer
## Настройки: звук, громкость по шинам, радиостанция, пресет графики,
## кастомизация водителя. Вся начинка уже живёт в Prefs (звук/громкости/
## радио/графика/водитель персистятся и применяются там) — экран только
## читает и пишет её поля.
##
## 8 параметров графики оригинала здесь сведены к выбору готового пресета
## (Db.gfx, 3 штуки) — поштучные оверрайды (Prefs.gfx_overrides) пока не
## имеют механизма применения и остаются на будущее.

const UiTheme = preload("res://ui/theme/ui_theme.gd")

signal closed

var _root: Control
var _sound_check: CheckBox
var _music_check: CheckBox
var _radio_lbl: Label
var _gfx_option: OptionButton
var _hud_mode_option: OptionButton
var _hud_opacity_slider: HSlider
var _belly_check: CheckBox
var _cap_check: CheckBox
var _volume_sliders: Dictionary[StringName, HSlider] = {}
var _driver_swatches: Dictionary[StringName, ColorPickerButton] = {}


func _ready() -> void:
	layer = 110
	_build_ui()
	visible = false


func show_screen() -> void:
	visible = true
	_refresh()


func hide_screen() -> void:
	visible = false
	Prefs.save_prefs()


func _refresh() -> void:
	_sound_check.button_pressed = Prefs.sound_on
	_music_check.button_pressed = Prefs.music_on
	_update_radio_label()
	for bus_name: StringName in _volume_sliders:
		_volume_sliders[bus_name].value = Prefs.volumes.get(bus_name, 0.0)
	_select_gfx_option(Prefs.gfx_preset)
	_select_hud_mode_option(Prefs.hud_mode)
	_hud_opacity_slider.value = Prefs.hud_opacity
	_belly_check.button_pressed = Prefs.driver.get(&"belly", false)
	_cap_check.button_pressed = Prefs.driver.get(&"cap", true)
	for key: StringName in _driver_swatches:
		_driver_swatches[key].color = Prefs.driver.get(key, Color.WHITE)


func _update_radio_label() -> void:
	var station: RadioStationData = Db.stations.get_station(Prefs.radio_station) if Db.stations != null else null
	_radio_lbl.text = "📻 %s" % (tr(station.display_name) if station != null else "—")


func _select_gfx_option(id: StringName) -> void:
	for i in _gfx_option.item_count:
		if _gfx_option.get_item_metadata(i) == id:
			_gfx_option.select(i)
			return


func _select_hud_mode_option(id: StringName) -> void:
	for i in _hud_mode_option.item_count:
		if _hud_mode_option.get_item_metadata(i) == id:
			_hud_mode_option.select(i)
			return


func _on_sound_toggled(pressed: bool) -> void:
	Prefs.sound_on = pressed
	Prefs.apply_audio()


func _on_music_toggled(pressed: bool) -> void:
	Prefs.music_on = pressed
	Prefs.apply_audio()


func _on_radio_next() -> void:
	Prefs.radio_station = Db.stations.next_station(Prefs.radio_station)
	_update_radio_label()


func _on_volume_changed(bus_name: StringName, value: float) -> void:
	Prefs.set_volume(bus_name, value)


func _on_gfx_selected(index: int) -> void:
	var id: StringName = _gfx_option.get_item_metadata(index)
	Prefs.gfx_preset = id
	if Dir.world != null and Dir.world.sky != null:
		Dir.world.sky.apply_preset(Db.gfx.get_preset(id))


func _on_hud_mode_selected(index: int) -> void:
	var id: StringName = _hud_mode_option.get_item_metadata(index)
	Prefs.hud_mode = id
	Prefs.apply_hud()


func _on_hud_opacity_changed(value: float) -> void:
	Prefs.hud_opacity = value
	Prefs.apply_hud()


func _on_driver_bool_toggled(key: StringName, pressed: bool) -> void:
	Prefs.driver[key] = pressed


func _on_driver_color_changed(key: StringName, color: Color) -> void:
	Prefs.driver[key] = color


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
	panel.offset_left = -280
	panel.offset_right = 280
	panel.offset_top = -300
	panel.offset_bottom = 300
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(14, UiTheme.COLOR_TAXI_YELLOW, UiTheme.COLOR_BG_PANEL_SOLID))
	_root.add_child(panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 12)
	panel.add_child(outer_vbox)

	var header := HBoxContainer.new()
	outer_vbox.add_child(header)

	var title := Label.new()
	title.text = "⚙️ НАСТРОЙКИ"
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

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 16)
	scroll.add_child(content)

	_build_sound_section(content)
	_build_volume_section(content)
	_build_gfx_section(content)
	_build_hud_section(content)
	_build_driver_section(content)


func _section_header(text: String, parent: VBoxContainer) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	lbl.add_theme_font_size_override("font_size", 14)
	parent.add_child(lbl)


func _build_sound_section(parent: VBoxContainer) -> void:
	_section_header("ЗВУК", parent)

	_sound_check = CheckBox.new()
	_sound_check.text = "Звук включён"
	_sound_check.toggled.connect(_on_sound_toggled)
	parent.add_child(_sound_check)

	_music_check = CheckBox.new()
	_music_check.text = "Музыка включена"
	_music_check.toggled.connect(_on_music_toggled)
	parent.add_child(_music_check)

	var radio_box := HBoxContainer.new()
	radio_box.add_theme_constant_override("separation", 10)
	parent.add_child(radio_box)

	_radio_lbl = Label.new()
	_radio_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_radio_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_PRIMARY)
	radio_box.add_child(_radio_lbl)

	var btn_next := Button.new()
	btn_next.text = "Далее ▶"
	btn_next.add_theme_stylebox_override("normal", UiTheme.button_secondary_style(&"normal"))
	btn_next.add_theme_stylebox_override("hover", UiTheme.button_secondary_style(&"hover"))
	btn_next.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_PRIMARY)
	btn_next.pressed.connect(_on_radio_next)
	radio_box.add_child(btn_next)


func _build_volume_section(parent: VBoxContainer) -> void:
	_section_header("ГРОМКОСТЬ", parent)
	for bus_name: StringName in Prefs.DEFAULT_VOLUMES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		parent.add_child(row)

		var lbl := Label.new()
		lbl.text = String(bus_name)
		lbl.custom_minimum_size = Vector2(90, 0)
		lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
		lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(lbl)

		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(func(v: float) -> void:
			_on_volume_changed(bus_name, v)
		)
		row.add_child(slider)
		_volume_sliders[bus_name] = slider


func _build_gfx_section(parent: VBoxContainer) -> void:
	_section_header("ГРАФИКА", parent)
	_gfx_option = OptionButton.new()
	if Db.gfx != null:
		for preset: GfxPreset in Db.gfx.items:
			_gfx_option.add_item(preset.display_name if not preset.display_name.is_empty() else String(preset.id))
			_gfx_option.set_item_metadata(_gfx_option.item_count - 1, preset.id)
	_gfx_option.item_selected.connect(_on_gfx_selected)
	parent.add_child(_gfx_option)


func _build_hud_section(parent: VBoxContainer) -> void:
	_section_header("ИНТЕРФЕЙС", parent)

	var mode_box := HBoxContainer.new()
	mode_box.add_theme_constant_override("separation", 10)
	parent.add_child(mode_box)

	var mode_lbl := Label.new()
	mode_lbl.text = "Режим HUD"
	mode_lbl.custom_minimum_size = Vector2(90, 0)
	mode_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	mode_lbl.add_theme_font_size_override("font_size", 13)
	mode_box.add_child(mode_lbl)

	_hud_mode_option = OptionButton.new()
	_hud_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var modes := {&"full": "Полный", &"minimal": "Минимальный", &"hidden": "Скрыт"}
	for id: StringName in modes:
		_hud_mode_option.add_item(modes[id])
		_hud_mode_option.set_item_metadata(_hud_mode_option.item_count - 1, id)
	_hud_mode_option.item_selected.connect(_on_hud_mode_selected)
	mode_box.add_child(_hud_mode_option)

	var opacity_box := HBoxContainer.new()
	opacity_box.add_theme_constant_override("separation", 10)
	parent.add_child(opacity_box)

	var opacity_lbl := Label.new()
	opacity_lbl.text = "Прозрачность"
	opacity_lbl.custom_minimum_size = Vector2(90, 0)
	opacity_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	opacity_lbl.add_theme_font_size_override("font_size", 13)
	opacity_box.add_child(opacity_lbl)

	_hud_opacity_slider = HSlider.new()
	_hud_opacity_slider.min_value = 0.4
	_hud_opacity_slider.max_value = 1.0
	_hud_opacity_slider.step = 0.05
	_hud_opacity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud_opacity_slider.value_changed.connect(_on_hud_opacity_changed)
	opacity_box.add_child(_hud_opacity_slider)


func _build_driver_section(parent: VBoxContainer) -> void:
	_section_header("ВОДИТЕЛЬ", parent)

	_belly_check = CheckBox.new()
	_belly_check.text = "Живот"
	_belly_check.toggled.connect(func(p: bool) -> void: _on_driver_bool_toggled(&"belly", p))
	parent.add_child(_belly_check)

	_cap_check = CheckBox.new()
	_cap_check.text = "Кепка"
	_cap_check.toggled.connect(func(p: bool) -> void: _on_driver_bool_toggled(&"cap", p))
	parent.add_child(_cap_check)

	var swatch_box := HBoxContainer.new()
	swatch_box.add_theme_constant_override("separation", 12)
	parent.add_child(swatch_box)

	var swatches := {
		&"shirt_color": "Рубашка",
		&"pants_color": "Штаны",
		&"skin_color": "Кожа",
		&"hair_color": "Волосы",
	}
	for key: StringName in swatches:
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER

		var lbl := Label.new()
		lbl.text = swatches[key]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
		lbl.add_theme_font_size_override("font_size", 11)
		col.add_child(lbl)

		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(48, 32)
		picker.color_changed.connect(func(c: Color) -> void: _on_driver_color_changed(key, c))
		col.add_child(picker)
		_driver_swatches[key] = picker

		swatch_box.add_child(col)
