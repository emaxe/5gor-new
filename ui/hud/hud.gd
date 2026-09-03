class_name Hud
extends CanvasLayer
## Главный игровой интерфейс (HUD).

const ToastQueueScript = preload("res://ui/hud/toast_queue.gd")

const TOAST_DURATION := 3.2
const ACHIEVEMENT_DURATION := 2.8
const VIGNETTE_DECAY := 1.6  # альфа/сек
const POPUP_DURATION := 1.0
const POPUP_RISE := 40.0  # px за весь POPUP_DURATION
const SHIFT_INTRO_DURATION := 2.0

var world: Node3D

var _top_panel: PanelContainer
var _money_lbl: Label
var _rating_lbl: Label
var _time_lbl: Label
var _weather_lbl: Label

var _order_card: PanelContainer
var _order_avatar_lbl: Label
var _order_title_lbl: Label
var _order_dest_lbl: Label
var _order_pay_lbl: Label
var _order_timer_bar: ProgressBar
var _order_mood_lbl: Label

var _dash_panel: PanelContainer
var _speed_lbl: Label
var _fuel_bar: ProgressBar
var _damage_bar: ProgressBar
var _dirt_lbl: Label

var _minimap: Control
var _nav_wrap: Control
var _nav_arrow: NavArrowIcon
var _nav_dist_lbl: Label
var _prompt_btn: Button
var _speech_bubble: PanelContainer
var _speech_text: Label
var _speech_speaker: Label
var _speech_timer: float = 0.0

var _toast_stack: VBoxContainer
var _toast_queue: ToastQueueScript
var _toast_nodes: Dictionary = {}  # int id -> {panel, timer}

var _ach_banner: PanelContainer
var _ach_title_lbl: Label
var _ach_desc_lbl: Label
var _ach_timer := 0.0

var _vignette: ColorRect
var _vignette_alpha := 0.0

var _popup_layer: Control
var _popups: Array[Dictionary] = []  # {lbl, timer}

var _shift_intro: ColorRect
var _shift_intro_lbl: Label
var _shift_intro_timer := 0.0

var _ui_ready := false

var _last_sp := -999
var _last_fuel := -999.0
var _last_hp := -999.0
var _last_dirt_state := -1



func _ready() -> void:
	layer = 100
	_toast_queue = ToastQueueScript.new(3)
	_build_ui()
	_connect_signals()


func setup(w: Node3D) -> void:
	world = w
	if _minimap != null:
		_minimap.world = w



func _connect_signals() -> void:
	if not Bus.money_changed.is_connected(_on_money_changed):
		Bus.money_changed.connect(_on_money_changed)
	if not Bus.rating_changed.is_connected(_on_rating_changed):
		Bus.rating_changed.connect(_on_rating_changed)
	if not Bus.time_changed.is_connected(_on_time_changed):
		Bus.time_changed.connect(_on_time_changed)
	if not Bus.weather_changed.is_connected(_on_weather_changed):
		Bus.weather_changed.connect(_on_weather_changed)
	if not Bus.order_event.is_connected(_on_order_event):
		Bus.order_event.connect(_on_order_event)
	if not Bus.notify.is_connected(_on_notify):
		Bus.notify.connect(_on_notify)
	if not Bus.achievement_unlocked.is_connected(_on_achievement_unlocked):
		Bus.achievement_unlocked.connect(_on_achievement_unlocked)
	if not Bus.player_crashed.is_connected(_on_player_crashed):
		Bus.player_crashed.connect(_on_player_crashed)
	if not Bus.juice_event.is_connected(_on_juice_event):
		Bus.juice_event.connect(_on_juice_event)



func _process(delta: float) -> void:
	if not _ui_ready:
		return
	_update_dashboard(delta)
	_update_order_card(delta)
	_update_nav()
	_update_speech_bubble(delta)
	_update_prompt_button()
	_update_toasts(delta)
	_update_achievement_banner(delta)
	_update_vignette(delta)
	_update_popups(delta)
	_update_shift_intro(delta)




# --- Создание элементов интерфейса -------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 1. Верхняя панель (Деньги, Рейтинг, Время, Погода)
	_top_panel = PanelContainer.new()
	_top_panel.name = "TopPanel"
	_top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_panel.offset_left = 20
	_top_panel.offset_right = -20
	_top_panel.offset_top = 16
	_top_panel.offset_bottom = 64
	_top_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(10, UiTheme.COLOR_BORDER, UiTheme.COLOR_BG_PANEL))
	root.add_child(_top_panel)

	var top_box := HBoxContainer.new()
	top_box.alignment = BoxContainer.ALIGNMENT_CENTER
	top_box.add_theme_constant_override("separation", 32)
	_top_panel.add_child(top_box)

	_money_lbl = _create_stat_label("💵 0 ₽", UiTheme.COLOR_MONEY_GREEN, 20)
	top_box.add_child(_money_lbl)

	_rating_lbl = _create_stat_label("⭐ 0.0", UiTheme.COLOR_TAXI_YELLOW, 20)
	top_box.add_child(_rating_lbl)

	_time_lbl = _create_stat_label("🕒 09:00 (День 1)", UiTheme.COLOR_TEXT_PRIMARY, 18)
	top_box.add_child(_time_lbl)

	_weather_lbl = _create_stat_label("☀️ Ясно", UiTheme.COLOR_INFO_BLUE, 18)
	top_box.add_child(_weather_lbl)

	# 2. Карточка заказа (Слева сверху)
	_order_card = PanelContainer.new()
	_order_card.name = "OrderCard"
	_order_card.offset_left = 20
	_order_card.offset_top = 76
	_order_card.offset_right = 320
	_order_card.offset_bottom = 210
	_order_card.add_theme_stylebox_override("panel", UiTheme.panel_style(10, UiTheme.COLOR_TAXI_YELLOW, UiTheme.COLOR_BG_PANEL))
	_order_card.visible = false
	root.add_child(_order_card)

	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 6)
	_order_card.add_child(card_vbox)

	var client_hbox := HBoxContainer.new()
	_order_avatar_lbl = Label.new()
	_order_avatar_lbl.text = "👨‍💼"
	_order_avatar_lbl.add_theme_font_size_override("font_size", 24)
	client_hbox.add_child(_order_avatar_lbl)

	_order_title_lbl = Label.new()
	_order_title_lbl.text = "Заказ такси"
	_order_title_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	_order_title_lbl.add_theme_font_size_override("font_size", 16)
	client_hbox.add_child(_order_title_lbl)
	card_vbox.add_child(client_hbox)

	_order_dest_lbl = Label.new()
	_order_dest_lbl.text = "Цель: Санаторий «Лесной»"
	_order_dest_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_PRIMARY)
	_order_dest_lbl.add_theme_font_size_override("font_size", 14)
	card_vbox.add_child(_order_dest_lbl)

	var pay_hbox := HBoxContainer.new()
	_order_pay_lbl = Label.new()
	_order_pay_lbl.text = "Оплата: 1 200 ₽"
	_order_pay_lbl.add_theme_color_override("font_color", UiTheme.COLOR_MONEY_GREEN)
	_order_pay_lbl.add_theme_font_size_override("font_size", 15)
	pay_hbox.add_child(_order_pay_lbl)

	_order_mood_lbl = Label.new()
	_order_mood_lbl.text = " 😊 Комфортно"
	_order_mood_lbl.add_theme_color_override("font_color", UiTheme.COLOR_INFO_BLUE)
	_order_mood_lbl.add_theme_font_size_override("font_size", 13)
	pay_hbox.add_child(_order_mood_lbl)
	card_vbox.add_child(pay_hbox)

	_order_timer_bar = ProgressBar.new()
	_order_timer_bar.custom_minimum_size = Vector2(0, 10)
	_order_timer_bar.show_percentage = false
	_order_timer_bar.value = 100
	card_vbox.add_child(_order_timer_bar)

	# 2b. GPS-навигатор (круглая плашка по центру сверху) — этап 13
	_nav_wrap = Control.new()
	_nav_wrap.name = "NavWrap"
	_nav_wrap.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_nav_wrap.offset_left = -32
	_nav_wrap.offset_right = 32
	_nav_wrap.offset_top = 12
	_nav_wrap.offset_bottom = 96
	_nav_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nav_wrap.visible = false
	root.add_child(_nav_wrap)

	var nav_circle := PanelContainer.new()
	nav_circle.name = "NavCircle"
	nav_circle.set_anchors_preset(Control.PRESET_TOP_WIDE)
	nav_circle.offset_top = 0
	nav_circle.offset_bottom = 64
	var nav_style := StyleBoxFlat.new()
	nav_style.bg_color = Color(0.04, 0.055, 0.08, 0.35)
	nav_style.border_color = Color(1.0, 1.0, 1.0, 0.10)
	nav_style.set_border_width_all(1)
	nav_style.set_corner_radius_all(32)
	nav_circle.add_theme_stylebox_override("panel", nav_style)
	_nav_wrap.add_child(nav_circle)

	var nav_arrow_script: GDScript = load("res://ui/hud/widgets/nav_arrow.gd")
	_nav_arrow = nav_arrow_script.new()
	_nav_arrow.name = "NavArrow"
	nav_circle.add_child(_nav_arrow)

	_nav_dist_lbl = Label.new()
	_nav_dist_lbl.name = "NavDist"
	_nav_dist_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_nav_dist_lbl.offset_top = 68
	_nav_dist_lbl.offset_bottom = 88
	_nav_dist_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nav_dist_lbl.add_theme_font_size_override("font_size", 11)
	_nav_dist_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_PRIMARY)
	_nav_wrap.add_child(_nav_dist_lbl)

	# 3. Миникарта (Слева снизу)
	var minimap_panel := PanelContainer.new()
	minimap_panel.name = "MinimapPanel"
	minimap_panel.offset_left = 20
	minimap_panel.offset_top = -220
	minimap_panel.offset_right = 220
	minimap_panel.offset_bottom = -20
	minimap_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	minimap_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	root.add_child(minimap_panel)

	var minimap_script: GDScript = load("res://ui/minimap/minimap.gd")
	if minimap_script != null:
		_minimap = minimap_script.new()
		_minimap.name = "Minimap"
		_minimap.custom_minimum_size = Vector2(200, 200)
		minimap_panel.add_child(_minimap)


	# 4. Приборная панель (Справа снизу)
	_dash_panel = PanelContainer.new()
	_dash_panel.name = "Dashboard"
	_dash_panel.offset_left = -260
	_dash_panel.offset_top = -180
	_dash_panel.offset_right = -20
	_dash_panel.offset_bottom = -20
	_dash_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dash_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(12, UiTheme.COLOR_BORDER, UiTheme.COLOR_BG_PANEL))
	root.add_child(_dash_panel)

	var dash_vbox := VBoxContainer.new()
	dash_vbox.add_theme_constant_override("separation", 6)
	_dash_panel.add_child(dash_vbox)

	_speed_lbl = Label.new()
	_speed_lbl.text = "000 КМ/Ч"
	_speed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	_speed_lbl.add_theme_font_size_override("font_size", 28)
	dash_vbox.add_child(_speed_lbl)

	# Топливо
	var fuel_box := HBoxContainer.new()
	var f_icon := Label.new()
	f_icon.text = "⛽ Топливо:"
	f_icon.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	f_icon.add_theme_font_size_override("font_size", 13)
	fuel_box.add_child(f_icon)
	_fuel_bar = ProgressBar.new()
	_fuel_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fuel_bar.custom_minimum_size = Vector2(0, 12)
	_fuel_bar.show_percentage = false
	_fuel_bar.value = 100
	fuel_box.add_child(_fuel_bar)
	dash_vbox.add_child(fuel_box)

	# Состояние / Урон
	var dmg_box := HBoxContainer.new()
	var d_icon := Label.new()
	d_icon.text = "🛠️ Прочность:"
	d_icon.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	d_icon.add_theme_font_size_override("font_size", 13)
	dmg_box.add_child(d_icon)
	_damage_bar = ProgressBar.new()
	_damage_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_damage_bar.custom_minimum_size = Vector2(0, 12)
	_damage_bar.show_percentage = false
	_damage_bar.value = 100
	dmg_box.add_child(_damage_bar)
	dash_vbox.add_child(dmg_box)

	_dirt_lbl = Label.new()
	_dirt_lbl.text = "Кузов: Чистый"
	_dirt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dirt_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	_dirt_lbl.add_theme_font_size_override("font_size", 12)
	dash_vbox.add_child(_dirt_lbl)

	# 5. Кнопка контекстного действия (Внизу по центру)
	_prompt_btn = Button.new()
	_prompt_btn.name = "PromptButton"
	_prompt_btn.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt_btn.offset_left = 320
	_prompt_btn.offset_right = -320
	_prompt_btn.offset_top = -75
	_prompt_btn.offset_bottom = -25
	_prompt_btn.add_theme_stylebox_override("normal", UiTheme.button_primary_style(&"normal"))
	_prompt_btn.add_theme_stylebox_override("hover", UiTheme.button_primary_style(&"hover"))
	_prompt_btn.add_theme_stylebox_override("pressed", UiTheme.button_primary_style(&"pressed"))
	_prompt_btn.add_theme_color_override("font_color", Color("#111115"))
	_prompt_btn.add_theme_font_size_override("font_size", 16)
	_prompt_btn.text = "[E] Посадить пассажира"
	_prompt_btn.visible = false
	_prompt_btn.pressed.connect(_on_prompt_pressed)
	root.add_child(_prompt_btn)

	# 6. Речевое облако диалога (По центру сверху)
	_speech_bubble = PanelContainer.new()
	_speech_bubble.name = "SpeechBubble"
	_speech_bubble.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_speech_bubble.offset_left = -260
	_speech_bubble.offset_right = 260
	_speech_bubble.offset_top = 80
	_speech_bubble.offset_bottom = 160
	_speech_bubble.add_theme_stylebox_override("panel", UiTheme.panel_style(12, UiTheme.COLOR_INFO_BLUE, UiTheme.COLOR_BG_PANEL_SOLID))
	_speech_bubble.visible = false
	root.add_child(_speech_bubble)

	var speech_vbox := VBoxContainer.new()
	_speech_speaker = Label.new()
	_speech_speaker.text = "Пассажир"
	_speech_speaker.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	_speech_speaker.add_theme_font_size_override("font_size", 14)
	speech_vbox.add_child(_speech_speaker)

	_speech_text = Label.new()
	_speech_text.text = "«Здравствуйте, шеф! Едем к Провалу!»"
	_speech_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech_text.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_PRIMARY)
	_speech_text.add_theme_font_size_override("font_size", 15)
	speech_vbox.add_child(_speech_text)
	_speech_bubble.add_child(speech_vbox)

	# 7. Стек тостов (до 3 одновременно) — по центру сверху
	_toast_stack = VBoxContainer.new()
	_toast_stack.name = "ToastStack"
	_toast_stack.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_stack.offset_left = -220
	_toast_stack.offset_right = 220
	_toast_stack.offset_top = 170
	_toast_stack.offset_bottom = 302
	_toast_stack.add_theme_constant_override("separation", 6)
	_toast_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_stack)

	# 8. Баннер достижения — под стеком тостов
	_ach_banner = PanelContainer.new()
	_ach_banner.name = "AchievementBanner"
	_ach_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_ach_banner.offset_left = -220
	_ach_banner.offset_right = 220
	_ach_banner.offset_top = 310
	_ach_banner.offset_bottom = 372
	_ach_banner.add_theme_stylebox_override("panel", UiTheme.panel_style(12, UiTheme.COLOR_TAXI_YELLOW, UiTheme.COLOR_BG_PANEL_SOLID))
	_ach_banner.visible = false
	root.add_child(_ach_banner)

	var ach_vbox := VBoxContainer.new()
	_ach_banner.add_child(ach_vbox)

	_ach_title_lbl = Label.new()
	_ach_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ach_title_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	_ach_title_lbl.add_theme_font_size_override("font_size", 16)
	ach_vbox.add_child(_ach_title_lbl)

	_ach_desc_lbl = Label.new()
	_ach_desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ach_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ach_desc_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	_ach_desc_lbl.add_theme_font_size_override("font_size", 12)
	ach_vbox.add_child(_ach_desc_lbl)

	# 9. Всплывашки награды (cash-pop/drift-pop) — над приборной панелью
	_popup_layer = Control.new()
	_popup_layer.name = "PopupLayer"
	_popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_popup_layer)

	# 10. Виньетка аварии — красная вспышка на весь экран
	_vignette = ColorRect.new()
	_vignette.name = "CrashVignette"
	_vignette.color = Color(UiTheme.COLOR_DANGER_RED.r, UiTheme.COLOR_DANGER_RED.g, UiTheme.COLOR_DANGER_RED.b, 0.0)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_vignette)

	# 11. Чёрный fade с титром смены — самый верхний слой
	_shift_intro = ColorRect.new()
	_shift_intro.name = "ShiftIntro"
	_shift_intro.color = Color(0, 0, 0, 0)
	_shift_intro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shift_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shift_intro.visible = false
	root.add_child(_shift_intro)

	_shift_intro_lbl = Label.new()
	_shift_intro_lbl.set_anchors_preset(Control.PRESET_CENTER)
	_shift_intro_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shift_intro_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	_shift_intro_lbl.add_theme_font_size_override("font_size", 32)
	_shift_intro.add_child(_shift_intro_lbl)

	_ui_ready = true



func _create_stat_label(default_text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = default_text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l


func _update_dashboard(_delta: float) -> void:
	if world == null or world.player == null:
		return
	var car: PlayerCar = world.player
	var sp: int = roundi(car.speed_kmh())
	if sp != _last_sp:
		_last_sp = sp
		_speed_lbl.text = "%03d КМ/Ч" % sp

	var fuel: float = car.runtime.fuel_ratio() * 100.0
	if absf(fuel - _last_fuel) > 0.1:
		_last_fuel = fuel
		_fuel_bar.value = fuel

	var hp: float = clampf((1.0 - car.runtime.damage / 100.0) * 100.0, 0.0, 100.0)
	if absf(hp - _last_hp) > 0.1:
		_last_hp = hp
		_damage_bar.value = hp

	var dirt_state: int = 2 if car.runtime.dirt > 0.6 else (1 if car.runtime.dirt > 0.3 else 0)
	if dirt_state != _last_dirt_state:
		_last_dirt_state = dirt_state
		if dirt_state == 2:
			_dirt_lbl.text = "Кузов: Очень грязный! 🧽"
			_dirt_lbl.add_theme_color_override("font_color", UiTheme.COLOR_DANGER_RED)
		elif dirt_state == 1:
			_dirt_lbl.text = "Кузов: Запылился"
			_dirt_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
		else:
			_dirt_lbl.text = "Кузов: Чистый ✨"
			_dirt_lbl.add_theme_color_override("font_color", UiTheme.COLOR_MONEY_GREEN)


func _update_order_card(_delta: float) -> void:
	if world == null or world.orders == null:
		_order_card.visible = false
		return

	var act: RefCounted = world.orders.active_order
	if act != null:
		_order_card.visible = true
		_order_avatar_lbl.text = act.client_avatar
		_order_title_lbl.text = act.title
		var drop: Dictionary = act.current_drop()
		_order_dest_lbl.text = "Цель: %s" % drop.get("name", "Пункт назначения")
		_order_pay_lbl.text = "Оплата: ~%d ₽" % act.est_pay

		if act.time_limit > 0.0:
			_order_timer_bar.visible = true
			_order_timer_bar.value = clampf((act.timer / act.time_limit) * 100.0, 0.0, 100.0)
		else:
			_order_timer_bar.visible = false

		if world.player != null:
			var car: PlayerCar = world.player
			var st: float = car.runtime.style
			if st > 0.8:
				_order_mood_lbl.text = "🤩 В восторге!"
			elif st > 0.6:
				_order_mood_lbl.text = "😊 Комфортно"
			elif st > 0.4:
				_order_mood_lbl.text = "😐 Терпимо"
			else:
				_order_mood_lbl.text = "😨 Укачивает!"
	else:
		_order_card.visible = false


## Стрелка-навигатор: указывает на следующую точку GPS-маршрута (не на
## конечную цель) — порт ui.js:400-425. Скрыта, пока у GPS нет цели
## (нет заказа и топлива хватает).
func _update_nav() -> void:
	if world == null or world.gps == null or not world.gps.has_target():
		_nav_wrap.visible = false
		return

	var pos: Vector2
	var heading: float
	if world.in_car and world.player != null:
		pos = Vector2(world.player.global_position.x, world.player.global_position.z)
		heading = world.player.motion.heading
	elif world.player_ped != null:
		pos = Vector2(world.player_ped.global_position.x, world.player_ped.global_position.z)
		heading = world.player_ped.logic.heading
	else:
		_nav_wrap.visible = false
		return

	_nav_wrap.visible = true
	var gps: GpsRouter = world.gps
	_nav_arrow.rotation = GpsRouter.arrow_angle(pos, heading, gps.next_waypoint())

	var is_fuel := gps.target_type == &"fuel"
	_nav_arrow.arrow_color = Color("#2ecc40") if is_fuel else UiTheme.COLOR_INFO_BLUE
	var dist := roundi(gps.remaining_distance())
	_nav_dist_lbl.text = ("%d м ⛽" % dist) if is_fuel else ("%d м" % dist)


func _update_speech_bubble(delta: float) -> void:
	if _speech_timer > 0.0:
		_speech_timer -= delta
		if _speech_timer <= 0.0:
			_speech_bubble.visible = false


func _update_prompt_button() -> void:
	if world == null or world.player == null or world.orders == null:
		_prompt_btn.visible = false
		return

	var car: PlayerCar = world.player
	var ppos := Vector2(car.global_position.x, car.global_position.z)

	# 1. Проверяем возможность высадки пассажира
	if world.orders.active_order != null:
		var target: Vector2 = world.orders.active_order.current_target_pos()
		if ppos.distance_to(target) <= 8.0:
			_prompt_btn.visible = true
			_prompt_btn.text = "[E] Завершить поездку / Высадить"
			return

	# 2. Проверяем возможность посадки клиента
	for o in world.orders.open_orders:
		if ppos.distance_to(o.pickup_pos) <= 8.0:
			_prompt_btn.visible = true
			_prompt_btn.text = "[E] Принять заказ: %s (~%d ₽)" % [o.title, o.est_pay]
			return

	_prompt_btn.visible = false



func _on_prompt_pressed() -> void:
	if world == null:
		return
	var ev := InputEventAction.new()
	ev.action = &"interact"
	ev.pressed = true
	Input.parse_input_event(ev)


# --- Обработчики сигналов ----------------------------------------------------

func _on_money_changed(value: int, _delta: int) -> void:
	_money_lbl.text = "💵 %d ₽" % value


func _on_rating_changed(value: float) -> void:
	_rating_lbl.text = "⭐ %.1f" % value


func _on_time_changed(hour: float, day: int, _is_night: bool) -> void:
	var h := int(hour)
	var m := int((hour - h) * 60.0)
	_time_lbl.text = "🕒 %02d:%02d (День %d)" % [h, m, day]


func _on_weather_changed(id: StringName) -> void:
	match id:
		&"rain": _weather_lbl.text = "🌧️ Дождь"
		&"fog": _weather_lbl.text = "🌫️ Туман"
		_: _weather_lbl.text = "☀️ Ясно"


func _on_order_event(kind: StringName, _order_id: int, _data: Dictionary) -> void:
	match kind:
		&"spawned":
			show_toast("Новый заказ в городе!", UiTheme.COLOR_TAXI_YELLOW)
		&"accepted":
			show_toast("Пассажир в салоне, следуйте по навигатору!", UiTheme.COLOR_INFO_BLUE)
		&"completed":
			show_toast("Поездка завершена!", UiTheme.COLOR_MONEY_GREEN)


func _on_notify(kind: StringName, text: String, data: Dictionary) -> void:
	match kind:
		&"toast":
			var col: Color = data.get("color", UiTheme.COLOR_TAXI_YELLOW)
			show_toast(text, col)
		&"dialogue":
			var speaker: String = data.get("speaker", "Пассажир")
			var avatar: String = data.get("avatar", "👨‍💼")
			show_speech("%s %s" % [avatar, speaker], text)


## До TOAST_MAX (см. ToastQueue) тостов одновременно — при переполнении
## самый старый снимается сразу, а не ждёт своего таймера.
func show_toast(text: String, color: Color = UiTheme.COLOR_TAXI_YELLOW) -> void:
	if not _ui_ready:
		return
	var result: Array = _toast_queue.push()
	var id: int = result[0]
	var evicted_id: int = result[1]
	if evicted_id != -1 and _toast_nodes.has(evicted_id):
		var evicted: Dictionary = _toast_nodes[evicted_id]
		(evicted["panel"] as Node).queue_free()
		_toast_nodes.erase(evicted_id)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(8, UiTheme.COLOR_TAXI_YELLOW, UiTheme.COLOR_BG_PANEL_SOLID))
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", color)
	panel.add_child(lbl)
	_toast_stack.add_child(panel)
	_toast_nodes[id] = {"panel": panel, "timer": TOAST_DURATION}


func show_speech(speaker: String, text: String) -> void:
	if not _ui_ready:
		return
	_speech_speaker.text = speaker
	_speech_text.text = "«%s»" % text
	_speech_bubble.visible = true
	_speech_timer = 4.5


func _update_toasts(delta: float) -> void:
	for id in _toast_nodes.keys().duplicate():
		var entry: Dictionary = _toast_nodes[id]
		var timer: float = entry["timer"] - delta
		if timer <= 0.0:
			(entry["panel"] as Node).queue_free()
			_toast_nodes.erase(id)
			_toast_queue.remove(id)
		else:
			entry["timer"] = timer


func _on_achievement_unlocked(id: StringName) -> void:
	if not _ui_ready or Db.achievements == null:
		return
	var a: AchievementData = Db.achievements.get_achievement(id)
	if a == null:
		return
	_ach_title_lbl.text = "🏆 %s" % tr(a.display_name)
	_ach_desc_lbl.text = tr(a.description)
	_ach_banner.visible = true
	_ach_timer = ACHIEVEMENT_DURATION


func _update_achievement_banner(delta: float) -> void:
	if _ach_timer <= 0.0:
		return
	_ach_timer -= delta
	if _ach_timer <= 0.0:
		_ach_banner.visible = false


## Красная вспышка, сила пропорциональна импульсу удара (crash.gd передаёт
## то же impact, что уходит в ChaseCamera.shake()).
func _on_player_crashed(impact: float, _victim: StringName) -> void:
	if not _ui_ready:
		return
	_vignette_alpha = clampf(impact / 50.0, 0.12, 0.6)


func _update_vignette(delta: float) -> void:
	if _vignette_alpha <= 0.0:
		return
	_vignette_alpha = maxf(0.0, _vignette_alpha - VIGNETTE_DECAY * delta)
	var c := _vignette.color
	c.a = _vignette_alpha
	_vignette.color = c


## Награда из juice_event (drift/perfect_stop/combo/near_miss) — тост уже
## объявляет её текстом, всплывашка добавляет "cash-pop"-акцент над приборкой.
func _on_juice_event(kind: StringName, data: Dictionary) -> void:
	if not _ui_ready:
		return
	var amount: int = roundi(data.get("reward", data.get("bonus_pay", 0.0)))
	if amount <= 0:
		return
	var icon: String = {
		&"drift": "💨", &"perfect_stop": "✨", &"combo": "🔥", &"near_miss": "⚡",
	}.get(kind, "💰")
	_spawn_cash_pop("%s +%d ₽" % [icon, amount])


func _spawn_cash_pop(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", UiTheme.COLOR_MONEY_GREEN)
	lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	lbl.offset_left = -260
	lbl.offset_right = -20
	lbl.offset_top = -210
	lbl.offset_bottom = -190
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_layer.add_child(lbl)
	# Якоря считаются сразу при add_child (не Container-родитель) — можно
	# взять готовую позицию как базовую и потом смещать от неё, а не поверх.
	_popups.append({"lbl": lbl, "timer": POPUP_DURATION, "base_y": lbl.position.y})


func _update_popups(delta: float) -> void:
	var i := _popups.size() - 1
	while i >= 0:
		var entry: Dictionary = _popups[i]
		var timer: float = entry["timer"] - delta
		var lbl: Label = entry["lbl"]
		if timer <= 0.0:
			lbl.queue_free()
			_popups.remove_at(i)
		else:
			entry["timer"] = timer
			var t: float = 1.0 - timer / POPUP_DURATION
			lbl.position.y = entry["base_y"] - POPUP_RISE * t
			var c := lbl.modulate
			c.a = 1.0 - t
			lbl.modulate = c
		i -= 1


## Чёрный экран с титром смены при её начале (main.gd._on_start_game) —
## первая половина держит титр, вторая угасает.
func play_shift_intro(day: int) -> void:
	if not _ui_ready:
		return
	_shift_intro_lbl.text = "День %d" % day
	_shift_intro.visible = true
	_shift_intro_timer = SHIFT_INTRO_DURATION


func _update_shift_intro(delta: float) -> void:
	if _shift_intro_timer <= 0.0:
		return
	_shift_intro_timer -= delta
	var t: float = clampf(_shift_intro_timer / SHIFT_INTRO_DURATION, 0.0, 1.0)
	var alpha: float = 1.0 if t > 0.5 else t / 0.5
	_shift_intro.color = Color(0, 0, 0, alpha)
	_shift_intro_lbl.modulate.a = alpha
	if _shift_intro_timer <= 0.0:
		_shift_intro.visible = false

