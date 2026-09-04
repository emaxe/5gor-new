class_name Hud
extends CanvasLayer
## Главный игровой интерфейс (HUD). Развёрнут по углам: центр экрана и
## горизонт остаются свободны для обзора дороги (см. docs/plans/init/plan.md,
## этап 14). Оверлеи (тосты, виньетка, баннер, титр смены) — на Tween, ноль
## ручных таймеров в _process.

const ToastStackScript = preload("res://ui/hud/toast_stack.gd")

const ACHIEVEMENT_DURATION := 2.8
const SHIFT_INTRO_DURATION := 2.0
const STREAK_BADGE_DURATION := 2.5
const CASH_POP_DURATION := 1.0
const CASH_POP_RISE := 40.0  # px за весь CASH_POP_DURATION

## Троттлинг тяжёлых опросов мира (приборка/карточка заказа/кнопка
## взаимодействия) — 15 Гц вместо покадрового (plan.md:190, :559-560).
## Спидометр и стрелка GPS остаются покадровыми — их дёрганность на 15 Гц
## заметна на глаз при разгоне/повороте.
const SLOW_STEP := 1.0 / 15.0

var world: Node3D

var _root: Control

var _pod_left: PanelContainer
var _money_lbl: Label
var _rating_lbl: Label
var _wanted_lbl: Label
var _combo_lbl: Label
var _nm_lbl: Label

var _pod_right: PanelContainer
var _time_lbl: Label
var _weather_lbl: Label
var _slot_lbl: Label

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
var _speech_tween: Tween

var _toast_stack: ToastStackScript

var _ach_banner: PanelContainer
var _ach_title_lbl: Label
var _ach_desc_lbl: Label
var _ach_tween: Tween

var _vignette: ColorRect
var _vignette_tween: Tween

var _popup_layer: Control

var _shift_intro: ColorRect
var _shift_intro_lbl: Label

var _combo_tween: Tween
var _nm_tween: Tween

var _ui_ready := false
var _menu_hidden := false
var _hud_minimal := false

var _slow_t := 0.0
var _last_sp := -999
var _last_fuel := -999.0
var _last_hp := -999.0
var _last_dirt_state := -1
var _prompt_visible_cache := false
var _prompt_text_cache := ""


func _ready() -> void:
	layer = 100
	_build_ui()
	_connect_signals()
	_apply_hud_prefs()


func setup(w: Node3D) -> void:
	world = w
	if _minimap != null:
		_minimap.world = w
	_update_slot_indicator()


## Сводит две причины скрытия HUD (главное меню, режим &"hidden" в опциях)
## в один флаг — раньше main_menu.gd писал visible напрямую и затирал
## режим "скрыт" при возврате в игру.
func set_menu_hidden(hidden: bool) -> void:
	_menu_hidden = hidden
	_apply_visibility()


func _apply_visibility() -> void:
	visible = not _menu_hidden and Prefs.hud_mode != &"hidden"
	set_process(visible)


func _connect_signals() -> void:
	if not Bus.money_changed.is_connected(_on_money_changed):
		Bus.money_changed.connect(_on_money_changed)
	if not Bus.rating_changed.is_connected(_on_rating_changed):
		Bus.rating_changed.connect(_on_rating_changed)
	if not Bus.wanted_changed.is_connected(_on_wanted_changed):
		Bus.wanted_changed.connect(_on_wanted_changed)
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
	if not Bus.settings_applied.is_connected(_on_settings_applied):
		Bus.settings_applied.connect(_on_settings_applied)


func _process(delta: float) -> void:
	if not _ui_ready:
		return
	_update_dashboard_speed()
	_update_nav_arrow()

	_slow_t += delta
	if _slow_t < SLOW_STEP:
		return
	_slow_t = 0.0

	_update_dashboard_slow()
	_update_order_card()
	_update_nav_distance()
	_update_prompt_button()


# --- Создание элементов интерфейса -------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_pods()
	_build_order_card()
	_build_nav_compass()
	_build_minimap()
	_build_dashboard()
	_build_prompt_button()
	_build_speech_bubble()
	_build_toast_stack()
	_build_achievement_banner()
	_build_popup_layer()
	_build_vignette()
	_build_shift_intro()

	_ui_ready = true


## Плашка слева сверху: деньги, рейтинг, розыск, счётчики серий.
func _build_pods() -> void:
	_pod_left = PanelContainer.new()
	_pod_left.name = "PodLeft"
	_pod_left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_pod_left.offset_left = 16
	_pod_left.offset_top = 12
	_pod_left.offset_right = 256
	_pod_left.offset_bottom = 76
	_pod_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pod_left.add_theme_stylebox_override("panel", HudStyle.pod_style())
	_root.add_child(_pod_left)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	_pod_left.add_child(vbox)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 14)
	vbox.add_child(row1)
	_money_lbl = _create_stat_label("💵 0 ₽", UiTheme.COLOR_MONEY_GREEN, 18)
	row1.add_child(_money_lbl)
	_rating_lbl = _create_stat_label("★ 0.0", UiTheme.COLOR_TAXI_YELLOW, 15)
	row1.add_child(_rating_lbl)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	vbox.add_child(row2)
	_wanted_lbl = _create_stat_label("", UiTheme.COLOR_TAXI_YELLOW, 13)
	_wanted_lbl.visible = false
	row2.add_child(_wanted_lbl)
	_combo_lbl = _create_stat_label("", HudStyle.COLOR_REWARD, 13)
	_combo_lbl.visible = false
	row2.add_child(_combo_lbl)
	_nm_lbl = _create_stat_label("", HudStyle.COLOR_REWARD, 13)
	_nm_lbl.visible = false
	row2.add_child(_nm_lbl)

	## Плашка справа сверху: время, погода, слот сохранения.
	_pod_right = PanelContainer.new()
	_pod_right.name = "PodRight"
	_pod_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pod_right.offset_left = -236
	_pod_right.offset_top = 12
	_pod_right.offset_right = -16
	_pod_right.offset_bottom = 76
	_pod_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pod_right.add_theme_stylebox_override("panel", HudStyle.pod_style())
	_root.add_child(_pod_right)

	var rvbox := VBoxContainer.new()
	rvbox.alignment = BoxContainer.ALIGNMENT_CENTER
	rvbox.add_theme_constant_override("separation", 3)
	_pod_right.add_child(rvbox)

	_time_lbl = _create_stat_label("🕒 09:00 (День 1)", UiTheme.COLOR_TEXT_PRIMARY, 14)
	_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rvbox.add_child(_time_lbl)

	var rrow2 := HBoxContainer.new()
	rrow2.alignment = BoxContainer.ALIGNMENT_END
	rrow2.add_theme_constant_override("separation", 10)
	rvbox.add_child(rrow2)
	_weather_lbl = _create_stat_label("☀ Ясно", UiTheme.COLOR_TEXT_MUTED, 12)
	rrow2.add_child(_weather_lbl)
	# Индикатор активного слота — полезен, когда игрок переключается между
	# слотами через главное меню и хочет видеть, какой сейчас прогресс.
	_slot_lbl = _create_stat_label("", UiTheme.COLOR_TEXT_MUTED, 12)
	rrow2.add_child(_slot_lbl)


func _build_order_card() -> void:
	_order_card = PanelContainer.new()
	_order_card.name = "OrderCard"
	_order_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_order_card.offset_left = 16
	_order_card.offset_top = 60
	_order_card.offset_right = 292
	_order_card.offset_bottom = 176
	_order_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_order_card.add_theme_stylebox_override("panel", HudStyle.pod_style(10))
	_order_card.visible = false
	_root.add_child(_order_card)

	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 5)
	_order_card.add_child(card_vbox)

	var client_hbox := HBoxContainer.new()
	client_hbox.add_theme_constant_override("separation", 6)
	_order_avatar_lbl = Label.new()
	_order_avatar_lbl.text = "👨‍💼"
	_order_avatar_lbl.add_theme_font_size_override("font_size", 18)
	client_hbox.add_child(_order_avatar_lbl)

	_order_title_lbl = Label.new()
	_order_title_lbl.text = "Заказ такси"
	_order_title_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	_order_title_lbl.add_theme_font_size_override("font_size", 14)
	client_hbox.add_child(_order_title_lbl)
	card_vbox.add_child(client_hbox)

	_order_dest_lbl = Label.new()
	_order_dest_lbl.text = "Цель: Санаторий «Лесной»"
	_order_dest_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_order_dest_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_PRIMARY)
	_order_dest_lbl.add_theme_font_size_override("font_size", 13)
	card_vbox.add_child(_order_dest_lbl)

	var pay_hbox := HBoxContainer.new()
	pay_hbox.add_theme_constant_override("separation", 8)
	_order_pay_lbl = Label.new()
	_order_pay_lbl.text = "Оплата: 1 200 ₽"
	_order_pay_lbl.add_theme_color_override("font_color", UiTheme.COLOR_MONEY_GREEN)
	_order_pay_lbl.add_theme_font_size_override("font_size", 13)
	pay_hbox.add_child(_order_pay_lbl)

	_order_mood_lbl = Label.new()
	_order_mood_lbl.text = "😊"
	_order_mood_lbl.add_theme_color_override("font_color", UiTheme.COLOR_INFO_BLUE)
	_order_mood_lbl.add_theme_font_size_override("font_size", 13)
	pay_hbox.add_child(_order_mood_lbl)
	card_vbox.add_child(pay_hbox)

	_order_timer_bar = ProgressBar.new()
	_order_timer_bar.custom_minimum_size = Vector2(0, 6)
	_order_timer_bar.show_percentage = false
	_order_timer_bar.value = 100
	card_vbox.add_child(_order_timer_bar)


## Круглая плашка GPS-навигатора — по центру сверху, там теперь пусто.
func _build_nav_compass() -> void:
	_nav_wrap = Control.new()
	_nav_wrap.name = "NavWrap"
	_nav_wrap.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_nav_wrap.offset_left = -28
	_nav_wrap.offset_top = 8
	_nav_wrap.offset_right = 28
	_nav_wrap.offset_bottom = 84
	_nav_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nav_wrap.visible = false
	_root.add_child(_nav_wrap)

	var nav_circle := PanelContainer.new()
	nav_circle.name = "NavCircle"
	nav_circle.set_anchors_preset(Control.PRESET_TOP_WIDE)
	nav_circle.offset_top = 0
	nav_circle.offset_bottom = 56
	nav_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nav_style := StyleBoxFlat.new()
	nav_style.bg_color = Color(0.04, 0.055, 0.08, 0.28)
	nav_style.border_color = Color(1.0, 1.0, 1.0, 0.10)
	nav_style.set_border_width_all(1)
	nav_style.set_corner_radius_all(28)
	nav_circle.add_theme_stylebox_override("panel", nav_style)
	_nav_wrap.add_child(nav_circle)

	var nav_arrow_script: GDScript = load("res://ui/hud/widgets/nav_arrow.gd")
	_nav_arrow = nav_arrow_script.new()
	_nav_arrow.name = "NavArrow"
	nav_circle.add_child(_nav_arrow)

	_nav_dist_lbl = Label.new()
	_nav_dist_lbl.name = "NavDist"
	_nav_dist_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_nav_dist_lbl.offset_top = 60
	_nav_dist_lbl.offset_bottom = 80
	_nav_dist_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nav_dist_lbl.add_theme_font_size_override("font_size", 11)
	_nav_dist_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_PRIMARY)
	_nav_wrap.add_child(_nav_dist_lbl)


func _build_minimap() -> void:
	var minimap_panel := PanelContainer.new()
	minimap_panel.name = "MinimapPanel"
	minimap_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	minimap_panel.offset_left = 16
	minimap_panel.offset_top = -196
	minimap_panel.offset_right = 196
	minimap_panel.offset_bottom = -16
	minimap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_root.add_child(minimap_panel)

	var minimap_script: GDScript = load("res://ui/minimap/minimap.gd")
	if minimap_script != null:
		_minimap = minimap_script.new()
		_minimap.name = "Minimap"
		_minimap.custom_minimum_size = Vector2(180, 180)
		minimap_panel.add_child(_minimap)


func _build_dashboard() -> void:
	_dash_panel = PanelContainer.new()
	_dash_panel.name = "Dashboard"
	_dash_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dash_panel.offset_left = -228
	_dash_panel.offset_top = -132
	_dash_panel.offset_right = -16
	_dash_panel.offset_bottom = -16
	_dash_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dash_panel.add_theme_stylebox_override("panel", HudStyle.pod_style(12))
	_root.add_child(_dash_panel)

	var dash_vbox := VBoxContainer.new()
	dash_vbox.add_theme_constant_override("separation", 5)
	_dash_panel.add_child(dash_vbox)

	_speed_lbl = Label.new()
	_speed_lbl.text = "000 КМ/Ч"
	_speed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	_speed_lbl.add_theme_font_size_override("font_size", 24)
	dash_vbox.add_child(_speed_lbl)

	var fuel_box := HBoxContainer.new()
	fuel_box.add_theme_constant_override("separation", 6)
	var f_icon := Label.new()
	f_icon.text = "⛽"
	f_icon.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	f_icon.add_theme_font_size_override("font_size", 12)
	fuel_box.add_child(f_icon)
	_fuel_bar = ProgressBar.new()
	_fuel_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fuel_bar.custom_minimum_size = Vector2(0, 8)
	_fuel_bar.show_percentage = false
	_fuel_bar.value = 100
	fuel_box.add_child(_fuel_bar)
	dash_vbox.add_child(fuel_box)

	var dmg_box := HBoxContainer.new()
	dmg_box.add_theme_constant_override("separation", 6)
	var d_icon := Label.new()
	d_icon.text = "🛠"
	d_icon.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	d_icon.add_theme_font_size_override("font_size", 12)
	dmg_box.add_child(d_icon)
	_damage_bar = ProgressBar.new()
	_damage_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_damage_bar.custom_minimum_size = Vector2(0, 8)
	_damage_bar.show_percentage = false
	_damage_bar.value = 100
	dmg_box.add_child(_damage_bar)
	dash_vbox.add_child(dmg_box)

	_dirt_lbl = Label.new()
	_dirt_lbl.text = "Кузов: Чистый"
	_dirt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dirt_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	_dirt_lbl.add_theme_font_size_override("font_size", 11)
	dash_vbox.add_child(_dirt_lbl)


func _build_prompt_button() -> void:
	_prompt_btn = Button.new()
	_prompt_btn.name = "PromptButton"
	_prompt_btn.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt_btn.offset_left = 380
	_prompt_btn.offset_right = -380
	_prompt_btn.offset_top = -72
	_prompt_btn.offset_bottom = -28
	_prompt_btn.add_theme_stylebox_override("normal", UiTheme.button_primary_style(&"normal"))
	_prompt_btn.add_theme_stylebox_override("hover", UiTheme.button_primary_style(&"hover"))
	_prompt_btn.add_theme_stylebox_override("pressed", UiTheme.button_primary_style(&"pressed"))
	_prompt_btn.add_theme_color_override("font_color", Color("#111115"))
	_prompt_btn.add_theme_font_size_override("font_size", 15)
	_prompt_btn.text = "[E] Посадить пассажира"
	_prompt_btn.visible = false
	_prompt_btn.pressed.connect(_on_prompt_pressed)
	_root.add_child(_prompt_btn)


## Речевое облако диалога — под карточкой заказа, а не по центру экрана,
## чтобы реплики пассажира группировались с его карточкой.
func _build_speech_bubble() -> void:
	_speech_bubble = PanelContainer.new()
	_speech_bubble.name = "SpeechBubble"
	_speech_bubble.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_speech_bubble.offset_left = 16
	_speech_bubble.offset_top = 184
	_speech_bubble.offset_right = 316
	_speech_bubble.offset_bottom = 256
	_speech_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speech_bubble.add_theme_stylebox_override("panel", HudStyle.pod_style(10))
	_speech_bubble.modulate.a = 0.0
	_speech_bubble.visible = false
	_root.add_child(_speech_bubble)

	var speech_vbox := VBoxContainer.new()
	_speech_speaker = Label.new()
	_speech_speaker.text = "Пассажир"
	_speech_speaker.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	_speech_speaker.add_theme_font_size_override("font_size", 12)
	speech_vbox.add_child(_speech_speaker)

	_speech_text = Label.new()
	_speech_text.text = "«Здравствуйте, шеф! Едем к Провалу!»"
	_speech_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech_text.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_PRIMARY)
	_speech_text.add_theme_font_size_override("font_size", 13)
	speech_vbox.add_child(_speech_text)
	_speech_bubble.add_child(speech_vbox)


## Стек тостов — правый край, растёт снизу вверх над приборкой.
func _build_toast_stack() -> void:
	_toast_stack = ToastStackScript.new()
	_toast_stack.name = "ToastStack"
	_toast_stack.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_toast_stack.offset_left = -360
	_toast_stack.offset_top = -344
	_toast_stack.offset_right = -16
	_toast_stack.offset_bottom = -144
	_root.add_child(_toast_stack)


func _build_achievement_banner() -> void:
	_ach_banner = PanelContainer.new()
	_ach_banner.name = "AchievementBanner"
	_ach_banner.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ach_banner.offset_left = -200
	_ach_banner.offset_top = -152
	_ach_banner.offset_right = 200
	_ach_banner.offset_bottom = -86
	_ach_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ach_banner.pivot_offset = Vector2(200, 33)
	_ach_banner.add_theme_stylebox_override("panel", HudStyle.pod_style(12))
	_ach_banner.modulate.a = 0.0
	_ach_banner.visible = false
	_root.add_child(_ach_banner)

	var ach_vbox := VBoxContainer.new()
	_ach_banner.add_child(ach_vbox)

	_ach_title_lbl = Label.new()
	_ach_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ach_title_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	_ach_title_lbl.add_theme_font_size_override("font_size", 15)
	ach_vbox.add_child(_ach_title_lbl)

	_ach_desc_lbl = Label.new()
	_ach_desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ach_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ach_desc_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TEXT_MUTED)
	_ach_desc_lbl.add_theme_font_size_override("font_size", 12)
	ach_vbox.add_child(_ach_desc_lbl)


## Всплывашка награды cash-pop — под счётчиком денег, а не над приборкой
## (там теперь тосты).
func _build_popup_layer() -> void:
	_popup_layer = Control.new()
	_popup_layer.name = "PopupLayer"
	_popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_popup_layer)


func _build_vignette() -> void:
	_vignette = ColorRect.new()
	_vignette.name = "CrashVignette"
	_vignette.color = Color(UiTheme.COLOR_DANGER_RED.r, UiTheme.COLOR_DANGER_RED.g, UiTheme.COLOR_DANGER_RED.b, 0.0)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_vignette)


func _build_shift_intro() -> void:
	_shift_intro = ColorRect.new()
	_shift_intro.name = "ShiftIntro"
	_shift_intro.color = Color(0, 0, 0, 0)
	_shift_intro.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shift_intro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shift_intro.visible = false
	_root.add_child(_shift_intro)

	_shift_intro_lbl = Label.new()
	_shift_intro_lbl.set_anchors_preset(Control.PRESET_CENTER)
	_shift_intro_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shift_intro_lbl.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	_shift_intro_lbl.add_theme_font_size_override("font_size", 32)
	_shift_intro.add_child(_shift_intro_lbl)


func _create_stat_label(default_text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = default_text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l


# --- Обновление по кадру / троттлингу ----------------------------------------

func _update_dashboard_speed() -> void:
	if world == null or world.player == null:
		return
	var car: PlayerCar = world.player
	var sp: int = roundi(car.speed_kmh())
	if sp != _last_sp:
		_last_sp = sp
		_speed_lbl.text = "%03d КМ/Ч" % sp


func _update_dashboard_slow() -> void:
	if world == null or world.player == null:
		return
	var car: PlayerCar = world.player

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


func _update_order_card() -> void:
	if _hud_minimal or world == null or world.orders == null:
		_order_card.visible = false
		return

	var act: RefCounted = world.orders.active_order
	if act == null:
		_order_card.visible = false
		return

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
			_order_mood_lbl.text = "🤩"
		elif st > 0.6:
			_order_mood_lbl.text = "😊"
		elif st > 0.4:
			_order_mood_lbl.text = "😐"
		else:
			_order_mood_lbl.text = "😨"


## Стрелка-навигатор поворачивается покадрово (иначе поворот дёргается),
## дистанция обновляется на троттлинге — порт ui.js:400-425.
func _update_nav_arrow() -> void:
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
	_nav_arrow.arrow_color = Color("#2ecc40") if gps.target_type == &"fuel" else UiTheme.COLOR_INFO_BLUE


func _update_nav_distance() -> void:
	if world == null or world.gps == null or not world.gps.has_target():
		return
	var gps: GpsRouter = world.gps
	var dist := roundi(gps.remaining_distance())
	_nav_dist_lbl.text = ("%d м ⛽" % dist) if gps.target_type == &"fuel" else ("%d м" % dist)


## Индикатор активного слота сохранения. Скрыт в главном меню
## (current_slot = -1) — там уже видны карточки слотов. Слот меняется раз
## за сессию, поэтому обновляется по требованию, а не в _process.
func _update_slot_indicator() -> void:
	var idx := SaveManager.current_slot
	if idx < 0:
		_slot_lbl.text = ""
		return
	_slot_lbl.text = "Слот %d/%d" % [idx + 1, SaveManager.SLOT_COUNT]


func _update_prompt_button() -> void:
	if world == null or world.player == null or world.orders == null:
		_set_prompt(false, "")
		return

	var car: PlayerCar = world.player
	var ppos := Vector2(car.global_position.x, car.global_position.z)

	if world.orders.active_order != null:
		var target: Vector2 = world.orders.active_order.current_target_pos()
		if ppos.distance_to(target) <= 8.0:
			_set_prompt(true, "[E] Завершить поездку / Высадить")
			return

	for o in world.orders.open_orders:
		if ppos.distance_to(o.pickup_pos) <= 8.0:
			_set_prompt(true, "[E] Принять заказ: %s (~%d ₽)" % [o.title, o.est_pay])
			return

	_set_prompt(false, "")


## Правит дефект №7 из docs/plans/init/plan.md: раньше кнопка переписывала
## text/visible каждый кадр даже без изменений (до 60 раз/сек в DOM-версии).
func _set_prompt(vis: bool, text: String) -> void:
	if vis == _prompt_visible_cache and text == _prompt_text_cache:
		return
	_prompt_visible_cache = vis
	_prompt_text_cache = text
	_prompt_btn.visible = vis
	if vis:
		_prompt_btn.text = text


func _on_prompt_pressed() -> void:
	if world == null:
		return
	var ev := InputEventAction.new()
	ev.action = &"interact"
	ev.pressed = true
	Input.parse_input_event(ev)


# --- Обработчики сигналов ----------------------------------------------------

func _on_money_changed(value: int, delta: int) -> void:
	_money_lbl.text = "💵 %d ₽" % value
	if delta > 0:
		_spawn_cash_pop("+%d ₽" % delta, UiTheme.COLOR_MONEY_GREEN)


func _on_rating_changed(value: float) -> void:
	_rating_lbl.text = "★ %.1f" % value


func _on_wanted_changed(level: int) -> void:
	if level <= 0:
		_wanted_lbl.visible = false
		return
	_wanted_lbl.visible = true
	_wanted_lbl.text = "🚓 %s" % "★".repeat(level)


func _on_time_changed(hour: float, day: int, _is_night: bool) -> void:
	var h := int(hour)
	var m := int((hour - h) * 60.0)
	_time_lbl.text = "🕒 %02d:%02d (День %d)" % [h, m, day]


func _on_weather_changed(id: StringName) -> void:
	match id:
		&"rain": _weather_lbl.text = "🌧 Дождь"
		&"fog": _weather_lbl.text = "🌫 Туман"
		_: _weather_lbl.text = "☀ Ясно"


## Только &"spawned" — на &"accepted"/&"completed" order_manager уже шлёт
## свои, более информативные тосты через Bus.notify (order_manager.gd:276,
## :380); дублировать их здесь не нужно.
func _on_order_event(kind: StringName, _order_id: int, _data: Dictionary) -> void:
	if kind == &"spawned":
		_toast_stack.push_toast("Новый заказ в городе!", &"info")


func _on_notify(kind: StringName, text: String, data: Dictionary) -> void:
	match kind:
		&"toast":
			var level: StringName = data.get("level", HudStyle.LEVEL_INFO)
			_toast_stack.push_toast(text, level)
		&"dialogue":
			var speaker: String = data.get("speaker", "Пассажир")
			var avatar: String = data.get("avatar", "👨‍💼")
			show_speech("%s %s" % [avatar, speaker], text)


func show_speech(speaker: String, text: String) -> void:
	if not _ui_ready or _hud_minimal:
		return
	_speech_speaker.text = speaker
	_speech_text.text = "«%s»" % text

	if _speech_tween != null and _speech_tween.is_valid():
		_speech_tween.kill()
	_speech_bubble.visible = true
	_speech_tween = create_tween()
	_speech_tween.tween_property(_speech_bubble, "modulate:a", 1.0, 0.2)
	_speech_tween.tween_interval(4.5)
	_speech_tween.tween_property(_speech_bubble, "modulate:a", 0.0, 0.4)
	_speech_tween.tween_callback(func() -> void: _speech_bubble.visible = false)


func _on_achievement_unlocked(id: StringName) -> void:
	if not _ui_ready or Db.achievements == null:
		return
	var a: AchievementData = Db.achievements.get_achievement(id)
	if a == null:
		return
	_ach_title_lbl.text = "🏆 %s" % tr(a.display_name)
	_ach_desc_lbl.text = tr(a.description)

	if _ach_tween != null and _ach_tween.is_valid():
		_ach_tween.kill()
	_ach_banner.visible = true
	_ach_banner.scale = Vector2(0.6, 0.6)
	_ach_tween = create_tween()
	_ach_tween.set_parallel(true)
	_ach_tween.tween_property(_ach_banner, "modulate:a", 1.0, 0.15)
	_ach_tween.tween_property(_ach_banner, "scale", Vector2(1.05, 1.05), 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_ach_tween.chain().tween_property(_ach_banner, "scale", Vector2.ONE, 0.12)
	_ach_tween.chain().tween_interval(ACHIEVEMENT_DURATION)
	_ach_tween.chain().tween_property(_ach_banner, "modulate:a", 0.0, 0.3)
	_ach_tween.chain().tween_callback(func() -> void: _ach_banner.visible = false)


## Красная вспышка, сила пропорциональна импульсу удара (crash.gd передаёт
## то же impact, что уходит в ChaseCamera.shake()).
func _on_player_crashed(impact: float, _victim: StringName) -> void:
	if not _ui_ready:
		return
	var target_alpha := clampf(impact / 50.0, 0.12, 0.6)

	if _vignette_tween != null and _vignette_tween.is_valid():
		_vignette_tween.kill()
	_vignette.color.a = target_alpha
	_vignette_tween = create_tween()
	_vignette_tween.tween_property(_vignette, "color:a", 0.0, target_alpha / 1.6) \
		.set_trans(Tween.TRANS_LINEAR)


## Cash-pop и счётчики серий (🔥 заказы / 💨 сближения) — короткая, не
## навязчивая обратная связь по стилю вождения (drift/perfect_stop/combo/
## near_miss); подробный текст уже несёт тост от того же события.
func _on_juice_event(kind: StringName, data: Dictionary) -> void:
	if not _ui_ready:
		return
	match kind:
		&"combo":
			var streak: int = data.get("streak", 0)
			if streak >= 2:
				_show_streak_badge(_combo_lbl, "🔥 ×%d" % streak, _combo_tween)
		&"near_miss":
			var streak: int = data.get("streak", 0)
			if streak >= 2:
				_show_streak_badge(_nm_lbl, "💨 ×%d" % streak, _nm_tween)


func _show_streak_badge(lbl: Label, text: String, tween: Tween) -> void:
	lbl.text = text
	lbl.visible = true
	if tween != null and tween.is_valid():
		tween.kill()
	var tw := create_tween()
	tw.tween_interval(STREAK_BADGE_DURATION)
	tw.tween_callback(func() -> void: lbl.visible = false)
	if lbl == _combo_lbl:
		_combo_tween = tw
	else:
		_nm_tween = tw


func _spawn_cash_pop(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", color)
	lbl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	lbl.offset_left = 16
	lbl.offset_top = 44
	lbl.offset_right = 216
	lbl.offset_bottom = 66
	_popup_layer.add_child(lbl)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - CASH_POP_RISE, CASH_POP_DURATION)
	tw.tween_property(lbl, "modulate:a", 0.0, CASH_POP_DURATION).set_trans(Tween.TRANS_LINEAR)
	tw.chain().tween_callback(lbl.queue_free)


## Чёрный экран с титром смены при её начале (main.gd._on_start_game) —
## первая половина держит титр, вторая угасает.
func play_shift_intro(day: int) -> void:
	if not _ui_ready:
		return
	_shift_intro_lbl.text = "День %d" % day
	_shift_intro.visible = true
	_shift_intro.color.a = 1.0
	_shift_intro_lbl.modulate.a = 1.0

	var tw := create_tween()
	tw.tween_interval(SHIFT_INTRO_DURATION * 0.5)
	tw.set_parallel(true)
	tw.tween_property(_shift_intro, "color:a", 0.0, SHIFT_INTRO_DURATION * 0.5)
	tw.tween_property(_shift_intro_lbl, "modulate:a", 0.0, SHIFT_INTRO_DURATION * 0.5)
	tw.chain().tween_callback(func() -> void: _shift_intro.visible = false)


# --- Настройка HUD (Prefs) ----------------------------------------------------

func _on_settings_applied(section: StringName) -> void:
	if section == &"hud":
		_apply_hud_prefs()


## &"minimal" прячет украшающую/второстепенную информацию (карточка заказа,
## реплики пассажира, состояние кузова, погода) — остаются деньги, рейтинг,
## розыск, скорость и топливо/прочность, миникарта, компас, тосты (в т.ч.
## &"critical" — провал заказа/ДТП/штраф видны в любом режиме).
func _apply_hud_prefs() -> void:
	if not _ui_ready:
		return
	_apply_visibility()
	_root.modulate.a = Prefs.hud_opacity

	_hud_minimal = Prefs.hud_mode == &"minimal"
	_weather_lbl.visible = not _hud_minimal
	_dirt_lbl.visible = not _hud_minimal
	if _hud_minimal:
		_order_card.visible = false
		if _speech_bubble.visible:
			_speech_bubble.visible = false
