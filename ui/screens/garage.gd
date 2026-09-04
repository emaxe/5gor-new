class_name GarageScreen
extends CanvasLayer
## Гараж (этап 15 MVP): владение/покупка/переключение машин + апгрейды с
## реальным списанием денег и применением к физике (Game.garage,
## gameplay/economy/garage.gd). Без вкладки «обслуживание» и «тюнинга» —
## CarRuntime.tuning пока ничем не читается, показывать его в UI нечего.

const UiTheme = preload("res://ui/theme/ui_theme.gd")

signal closed

var _root: Control
var _money_lbl: Label
var _cars_vbox: VBoxContainer
var _upgrades_vbox: VBoxContainer


func _ready() -> void:
	layer = 110
	_build_ui()
	visible = false


func show_screen() -> void:
	visible = true
	_refresh()


func hide_screen() -> void:
	visible = false


func _refresh() -> void:
	_money_lbl.text = "💵 %d ₽ · ⭐ %.1f" % [Game.money, Game.rating]
	_refresh_cars()
	_refresh_upgrades()


# --- Вкладка «Машины» --------------------------------------------------------

func _refresh_cars() -> void:
	for child in _cars_vbox.get_children():
		child.queue_free()
	if Db.cars == null:
		return
	for car_id: StringName in Db.cars.ids():
		_cars_vbox.add_child(_build_car_row(car_id))


func _build_car_row(car_id: StringName) -> PanelContainer:
	var data: CarData = Db.cars.get_car(car_id)
	var owned: bool = Game.garage.owns(car_id)
	var active: bool = Game.garage.active_car_id == car_id

	var row := PanelContainer.new()
	var border := UiTheme.COLOR_TAXI_YELLOW if active else (UiTheme.COLOR_MONEY_GREEN if owned else UiTheme.COLOR_BORDER)
	row.add_theme_stylebox_override("panel", UiTheme.panel_style(8, border, UiTheme.COLOR_BG_PANEL))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var title := Label.new()
	var status := " (активна)" if active else (" (в парке)" if owned else "")
	title.text = "%s%s" % [tr(data.display_name), status]
	title.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW if active else UiTheme.COLOR_TEXT_PRIMARY)
	title.add_theme_font_size_override("font_size", 15)
	info_vbox.add_child(title)

	var desc := Label.new()
	if owned:
		desc.text = tr(data.description)
	else:
		desc.text = "Цена: %d ₽ · нужен рейтинг ⭐ %d" % [data.price, data.unlock_rating]
	desc.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	desc.add_theme_font_size_override("font_size", 12)
	info_vbox.add_child(desc)

	var btn := Button.new()
	if active:
		btn.text = "Активна"
		btn.disabled = true
	elif owned:
		btn.text = "Выбрать"
	else:
		btn.text = "Купить"
	btn.add_theme_stylebox_override("normal", UiTheme.button_primary_style(&"normal") if not active else UiTheme.button_secondary_style(&"normal"))
	btn.add_theme_stylebox_override("hover", UiTheme.button_primary_style(&"hover") if not active else UiTheme.button_secondary_style(&"hover"))
	btn.add_theme_color_override("font_color", Color("#111115") if not active else UiTheme.COLOR_TEXT_MUTED)
	btn.pressed.connect(func() -> void:
		if owned:
			_select_car(car_id)
		else:
			Game.garage.buy_car(car_id)
			_refresh()
	)
	hbox.add_child(btn)

	return row


## Переключение живой машины — то же самое пересобирание, что и смена
## машины через PlayerCar.setup() (комментарий там же: «смена машины —
## правка радиуса в одном месте»).
func _select_car(car_id: StringName) -> void:
	Game.garage.set_active(car_id)
	var w: World = Dir.world
	if w != null and w.player != null and w.city != null:
		w.player.runtime.upgrade_levels = Game.garage.upgrade_levels_for(car_id)
		w.player.setup(Db.cars.get_car(car_id), Db.upgrades, w.city.field)
	_refresh()


# --- Вкладка «Апгрейды» (для активной машины) --------------------------------

func _refresh_upgrades() -> void:
	for child in _upgrades_vbox.get_children():
		child.queue_free()
	if Db.upgrades == null:
		return
	var car_id: StringName = Game.garage.active_car_id
	for upgrade_id: StringName in Db.upgrades.ids():
		_upgrades_vbox.add_child(_build_upgrade_row(car_id, upgrade_id))


func _build_upgrade_row(car_id: StringName, upgrade_id: StringName) -> PanelContainer:
	var upgrade: UpgradeData = Db.upgrades.get_upgrade(upgrade_id)
	var level: int = Game.garage.upgrade_level(car_id, upgrade_id)
	var cost := upgrade.cost_at(level)
	var maxed := cost < 0

	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UiTheme.panel_style(8, UiTheme.COLOR_BORDER, UiTheme.COLOR_BG_PANEL))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var title := Label.new()
	title.text = "%s (%d/%d)" % [tr(upgrade.display_name), level, upgrade.max_level]
	title.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_PRIMARY)
	title.add_theme_font_size_override("font_size", 15)
	info_vbox.add_child(title)

	var desc := Label.new()
	desc.text = tr(upgrade.description) if not maxed else "Максимальный уровень"
	desc.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	desc.add_theme_font_size_override("font_size", 12)
	info_vbox.add_child(desc)

	var btn := Button.new()
	btn.text = "МАКС" if maxed else "%d ₽" % cost
	btn.disabled = maxed
	if not maxed:
		btn.add_theme_stylebox_override("normal", UiTheme.button_primary_style(&"normal"))
		btn.add_theme_stylebox_override("hover", UiTheme.button_primary_style(&"hover"))
		btn.add_theme_color_override("font_color", Color("#111115"))
		btn.pressed.connect(func() -> void:
			_buy_upgrade(car_id, upgrade_id)
		)
	hbox.add_child(btn)

	return row


func _buy_upgrade(car_id: StringName, upgrade_id: StringName) -> void:
	if not Game.garage.buy_upgrade(car_id, upgrade_id):
		return
	var w: World = Dir.world
	if w != null and w.player != null and w.player.runtime.car_id == car_id:
		w.player.runtime.upgrade_levels = Game.garage.upgrade_levels_for(car_id)
		w.player.runtime.setup(Db.cars.get_car(car_id), Db.upgrades)
	_refresh()


# --- Каркас экрана ------------------------------------------------------------

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
	panel.offset_top = -300
	panel.offset_bottom = 300
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(14, UiTheme.COLOR_TAXI_YELLOW, UiTheme.COLOR_BG_PANEL_SOLID))
	_root.add_child(panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(outer_vbox)

	var header := HBoxContainer.new()
	outer_vbox.add_child(header)

	var title := Label.new()
	title.text = "🔧 ГАРАЖ"
	title.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	title.add_theme_font_size_override("font_size", 20)
	header.add_child(title)

	_money_lbl = Label.new()
	_money_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_money_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_lbl.add_theme_color_override("font_color", UiTheme.COLOR_MONEY_GREEN)
	_money_lbl.add_theme_font_size_override("font_size", 15)
	header.add_child(_money_lbl)

	var btn_close := Button.new()
	btn_close.text = "✕"
	btn_close.add_theme_stylebox_override("normal", UiTheme.button_secondary_style(&"normal"))
	btn_close.add_theme_stylebox_override("hover", UiTheme.button_secondary_style(&"hover"))
	btn_close.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_PRIMARY)
	btn_close.pressed.connect(func() -> void:
		closed.emit()
	)
	header.add_child(btn_close)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(tabs)

	var cars_scroll := ScrollContainer.new()
	cars_scroll.name = "Машины"
	tabs.add_child(cars_scroll)
	_cars_vbox = VBoxContainer.new()
	_cars_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cars_vbox.add_theme_constant_override("separation", 6)
	cars_scroll.add_child(_cars_vbox)

	var upgrades_scroll := ScrollContainer.new()
	upgrades_scroll.name = "Апгрейды"
	tabs.add_child(upgrades_scroll)
	_upgrades_vbox = VBoxContainer.new()
	_upgrades_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrades_vbox.add_theme_constant_override("separation", 6)
	upgrades_scroll.add_child(_upgrades_vbox)
