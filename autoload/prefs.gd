extends Node
## Prefs — настройки и их применение. Хранятся в user://settings.cfg отдельно
## от игровых слотов, чтобы удаление слота не сбрасывало громкость и графику.

const PATH := "user://settings.cfg"
const VERSION := 1

## Порт AU_DEFAULT_VOL (audiocore.js:5).
const DEFAULT_VOLUMES := {
	&"Master": 0.10,
	&"Music": 0.20,
	&"SFX": 0.30,
	&"Engine": 0.15,
	&"Ambient": 0.25,
	&"UI": 0.30,
	&"Voice": 0.40,
}

var sound_on := true
var music_on := true
var volumes: Dictionary = DEFAULT_VOLUMES.duplicate()
var radio_station: StringName = &"pyatigorsk"

var gfx_preset: StringName = &"high"
## Ручные оверрайды поверх пресета; любая правка переводит пресет в &"custom".
var gfx_overrides: Dictionary = {}

## Внешность водителя. Порт save.driver.
var driver := {
	&"belly": false,
	&"cap": true,
	&"shirt_color": Color(0.16, 0.28, 0.50),
	&"pants_color": Color(0.16, 0.16, 0.23),
	&"skin_color": Color(0.96, 0.82, 0.69),
	&"hair_color": Color(0.10, 0.10, 0.10),
}

var locale := "ru"
## Темп смены: 0.5 / 1.0 / 2.0.
var shift_speed := 1.0

## Режим игрового HUD: &"full" | &"minimal" | &"hidden".
var hud_mode: StringName = &"full"
## Множитель непрозрачности фонов HUD-плашек.
var hud_opacity := 1.0

var _volume_save_timer: SceneTreeTimer = null


func _ready() -> void:
	load_prefs()
	apply_audio()
	TranslationServer.set_locale(locale)


func load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	sound_on = cfg.get_value("audio", "sound_on", sound_on)
	music_on = cfg.get_value("audio", "music_on", music_on)
	radio_station = StringName(cfg.get_value("audio", "radio", String(radio_station)))
	for bus_name: StringName in DEFAULT_VOLUMES:
		volumes[bus_name] = cfg.get_value("audio", "vol_" + String(bus_name),
			DEFAULT_VOLUMES[bus_name])
	gfx_preset = StringName(cfg.get_value("gfx", "preset", String(gfx_preset)))
	gfx_overrides = cfg.get_value("gfx", "overrides", {})
	for k: StringName in driver:
		driver[k] = cfg.get_value("driver", String(k), driver[k])
	locale = cfg.get_value("misc", "locale", locale)
	shift_speed = cfg.get_value("misc", "shift_speed", shift_speed)
	hud_mode = StringName(cfg.get_value("hud", "mode", String(hud_mode)))
	hud_opacity = cfg.get_value("hud", "opacity", hud_opacity)
	_load_input_map(cfg)


func save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", VERSION)
	cfg.set_value("audio", "sound_on", sound_on)
	cfg.set_value("audio", "music_on", music_on)
	cfg.set_value("audio", "radio", String(radio_station))
	for bus_name: StringName in volumes:
		cfg.set_value("audio", "vol_" + String(bus_name), volumes[bus_name])
	cfg.set_value("gfx", "preset", String(gfx_preset))
	cfg.set_value("gfx", "overrides", gfx_overrides)
	for k: StringName in driver:
		cfg.set_value("driver", String(k), driver[k])
	cfg.set_value("misc", "locale", locale)
	cfg.set_value("misc", "shift_speed", shift_speed)
	cfg.set_value("hud", "mode", String(hud_mode))
	cfg.set_value("hud", "opacity", hud_opacity)
	_save_input_map(cfg)
	cfg.save(PATH)


## Громкость шины 0..1. Сохранение отложено на 0.8 с — иначе протаскивание
## слайдера пишет файл десятки раз в секунду (порт debounce из game.js:781).
func set_volume(bus_name: StringName, value: float) -> void:
	volumes[bus_name] = clampf(value, 0.0, 1.0)
	_apply_bus(bus_name)
	_debounce_save()


func apply_audio() -> void:
	for bus_name: StringName in volumes:
		_apply_bus(bus_name)
	Bus.settings_applied.emit(&"audio")


## Hud слушает settings_applied(&"hud") и перечитывает hud_mode/hud_opacity —
## вызывается сразу при правке в SettingsScreen, без ожидания hide_screen().
func apply_hud() -> void:
	Bus.settings_applied.emit(&"hud")


func _apply_bus(bus_name: StringName) -> void:
	var idx := AudioServer.get_bus_index(String(bus_name))
	if idx < 0:
		return
	var v: float = volumes.get(bus_name, 0.0)
	var muted := not sound_on or (bus_name == &"Music" and not music_on)
	AudioServer.set_bus_mute(idx, muted)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))


func _debounce_save() -> void:
	if _volume_save_timer != null and _volume_save_timer.time_left > 0.0:
		return
	_volume_save_timer = get_tree().create_timer(0.8)
	_volume_save_timer.timeout.connect(save_prefs, CONNECT_ONE_SHOT)


func _save_input_map(cfg: ConfigFile) -> void:
	var remapped := {}
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		var events: Array = []
		for e in InputMap.action_get_events(action):
			# InputEvent — Object, а не структура: обычный var_to_bytes()
			# сериализует объекты только ссылкой на instance ID (12 байт,
			# без keycode/button_index/axis), а не их данными — нужен
			# явный _with_objects, иначе bytes_to_var() в _load_input_map()
			# ниже не восстановит из этого ни одного валидного InputEvent.
			events.append(var_to_bytes_with_objects(e))
		remapped[String(action)] = events
	cfg.set_value("input", "actions", remapped)


func _load_input_map(cfg: ConfigFile) -> void:
	var remapped: Dictionary = cfg.get_value("input", "actions", {})
	for action_name: String in remapped:
		var action := StringName(action_name)
		if not InputMap.has_action(action):
			continue
		var events: Array[InputEvent] = []
		for packed: PackedByteArray in remapped[action_name]:
			var e: Variant = bytes_to_var_with_objects(packed)
			if e is InputEvent:
				events.append(e)
		# Пусто — или действие сохранили без единого события, или это файл
		# со старого сломанного _save_input_map() (см. комментарий выше:
		# события распадались в bytes_to_var() и раньше сюда не долетали
		# вообще ни одного). Не стираем InputMap.action_erase_events() из
		# project.godot вслепую — иначе газ/руль/тормоз остаются без единой
		# привязки навсегда, пока файл настроек не удалят руками.
		if events.is_empty():
			continue
		InputMap.action_erase_events(action)
		for e in events:
			InputMap.action_add_event(action, e)
