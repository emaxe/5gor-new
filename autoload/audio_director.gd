extends Node
## Audio — шины, пул SFX-голосов с бюджетом/кулдауном, зацикленные слои
## машины (двигатель/шины/ветер/тормоза/дребезг), радио, даккинг.
## Порт audiocore.js/audiosfx.js/audioloops.js/audiomusic.js/audio.js.
##
## Шины создаются здесь программно в _ready(), а не через
## project.godot/default_bus_layout — так гарантируется, что они существуют
## ДО того, как Prefs (следующий автолоад) применит громкости из настроек;
## раньше `Prefs._apply_bus()` тихо становился no-op на несуществующих шинах.

## Бюджеты/кулдауны голосов (порт AU_BUDGET/AU_COOLDOWN, audiocore.js:6-7) —
## см. VoiceAllocator.

const BUS_LIST: Array[StringName] = [&"Music", &"SFX", &"Engine", &"Ambient", &"UI", &"Voice"]
const SFX_POOL_SIZE := 24
## Размер пула 3D-голосов для звуков с позицией (гудки трафика, сирены,
## шаги пешеходов). Один источник живёт в AudioStreamPlayer3D, когда
## воспроизведение кончается — возвращается в пул. Размер пула ограничивает
## одновременное число звучащих 3D-эффектов; при превышении самые старые
## подрезаются.
const SFX_3D_POOL_SIZE := 16
const LOOP_SMOOTH := 0.18
const RAIN_SMOOTH := 0.05


class _Voice extends RefCounted:
	var player: AudioStreamPlayer
	var budget_tag: StringName = &""
	var in_use := false


class _Voice3D extends RefCounted:
	var player: AudioStreamPlayer3D
	var budget_tag: StringName = &""
	var in_use := false


var _alloc := VoiceAllocator.new()
var _pool: Array[_Voice] = []
var _pool_3d: Array[_Voice3D] = []

var _engine_players: Array[AudioStreamPlayer] = []
var _tire_road: AudioStreamPlayer
var _tire_offroad: AudioStreamPlayer
var _skid: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _brake_noise: AudioStreamPlayer
var _brake_tone: AudioStreamPlayer
var _rattle: AudioStreamPlayer
var _city_ambient: AudioStreamPlayer
var _rain: AudioStreamPlayer

var _music_lp: AudioEffectLowPassFilter
var _radio_player: AudioStreamPlayer
var _radio := RadioSequencer.new()

var _engine_car_type: StringName = &""
var _engine_band_cache: Dictionary[StringName, Array] = {}

# --- Публикуется update_vehicle(), читается в _physics_process --------------
var _v_speed := 0.0
var _v_throttle := 0.0
var _v_brake := 0.0
var _v_slip := 0.0
var _v_on_road := true
var _v_max_speed := 40.0
var _v_running := true
var _v_fuel_frac := 1.0
var _v_damage := 0.0

var _rpm := 0.0
var _tire_road_gain := 0.0
var _tire_offroad_gain := 0.0
var _skid_gain := 0.0
var _wind_gain := 0.0
var _brake_noise_gain := 0.0
var _brake_tone_gain := 0.0
var _rattle_gain := 0.0
var _rain_gain := 0.0
var _rain_target := 0.0

var _fuel_warn_timer := 0.0
var _rattle_clang_timer := 0.0
var _bump_cooldown := 0.0
var _prev_ground_y := 0.0
var _has_ground := false

var _current_state: StringName = &""
var _was_night := false
## Гейт для update_vehicle: пока игрок не за рулём, циклы машины гасятся —
## иначе холостой ход шёл бы фоном из любой точки мира (engine_dead()
## отражает только топливо/поломку, не «зажигание выключено»).
var _in_car := false


func _ready() -> void:
	_ensure_buses()
	_build_pool()
	_build_pool_3d()
	_build_loops()
	_radio_player = AudioStreamPlayer.new()
	add_child(_radio_player)
	_radio.setup(_radio_player, _music_lp)

	Bus.player_crashed.connect(_on_player_crashed)
	Bus.achievement_unlocked.connect(_on_achievement_unlocked)
	Bus.order_event.connect(_on_order_event)
	Bus.juice_event.connect(_on_juice_event)
	Bus.notify.connect(_on_notify)
	Bus.weather_changed.connect(_on_weather_changed)
	Bus.time_changed.connect(_on_time_changed)
	Bus.game_state_changed.connect(_on_game_state_changed)
	Bus.vehicle_mode_changed.connect(_on_vehicle_mode_changed)


# --- Настройка шин -----------------------------------------------------------

func _ensure_buses() -> void:
	for bus_name in BUS_LIST:
		if AudioServer.get_bus_index(String(bus_name)) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, String(bus_name))
			AudioServer.set_bus_send(idx, &"Master")
	_setup_bus_effects()


## Лимитер на Master (порт DynamicsCompressor 20:1, audiocore.js:37-40),
## даккинг речи на Music через AudioEffectCompressor.sidechain (план, п.10),
## лёгкий реверб на Ambient (замена процедурной IR, audiocore.js:59-70).
func _setup_bus_effects() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0 and AudioServer.get_bus_effect_count(master_idx) == 0:
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		limiter.threshold_db = -3.0
		AudioServer.add_bus_effect(master_idx, limiter)

	var music_idx := AudioServer.get_bus_index("Music")
	if music_idx >= 0:
		if AudioServer.get_bus_effect_count(music_idx) == 0:
			_music_lp = AudioEffectLowPassFilter.new()
			_music_lp.cutoff_hz = 6500.0
			AudioServer.add_bus_effect(music_idx, _music_lp)
			var comp := AudioEffectCompressor.new()
			comp.sidechain = &"Voice"
			comp.threshold = -24.0
			comp.ratio = 4.0
			comp.attack_us = 2000.0
			comp.release_ms = 300.0
			comp.gain = 6.0
			AudioServer.add_bus_effect(music_idx, comp)
		else:
			_music_lp = AudioServer.get_bus_effect(music_idx, 0) as AudioEffectLowPassFilter

	var ambient_idx := AudioServer.get_bus_index("Ambient")
	if ambient_idx >= 0 and AudioServer.get_bus_effect_count(ambient_idx) == 0:
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.6
		rev.wet = 0.16
		AudioServer.add_bus_effect(ambient_idx, rev)


# --- Пул одноразовых SFX ------------------------------------------------------

func _build_pool() -> void:
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		var v := _Voice.new()
		v.player = p
		_pool.append(v)
		p.finished.connect(_on_voice_finished.bind(v))


## 3D-пул: те же бюджеты/кулдауны VoiceAllocator, но носитель — Node3D-
	## позиционированный плеер с обратной квадратичной зависимостью
	## (ATTENUATION_INVERSE_DISTANCE) — машина на 80 м уже почти не слышна,
	## что и нужно для уличного звука.
func _build_pool_3d() -> void:
	for i in SFX_3D_POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.max_distance = 80.0
		add_child(p)
		var v := _Voice3D.new()
		v.player = p
		_pool_3d.append(v)
		p.finished.connect(_on_voice_3d_finished.bind(v))


## Порт alloc()+play() (audiocore.js) — бюджет/кулдаун по тегам рецепта,
## голос освобождается по `AudioStreamPlayer.finished` (точнее оригинального
## releaseAfter(ms), см. VoiceAllocator).
func play_sfx(id: StringName, gain_mul: float = 1.0) -> bool:
	var recipe := Db.stations.get_sfx(id)
	if recipe == null:
		push_warning("Audio: неизвестный SFX id %s" % id)
		return false
	var now := Time.get_ticks_msec()
	if not _alloc.try_alloc(recipe.budget_tag, recipe.cooldown_tag, now):
		return false
	var voice := _free_voice()
	if voice == null:
		_alloc.release(recipe.budget_tag) # пул исчерпан — откатываем занятый бюджет
		return false
	voice.in_use = true
	voice.budget_tag = recipe.budget_tag
	voice.player.stream = SfxCache.get_stream(recipe)
	voice.player.bus = recipe.bus
	voice.player.volume_db = linear_to_db(clampf(gain_mul, 0.0001, 4.0))
	voice.player.play()
	return true


func _free_voice() -> _Voice:
	for v in _pool:
		if not v.in_use:
			return v
	return null


## 3D-вариант play_sfx — позиционирует голос в мире. Те же бюджеты/кулдауны
## по тегу рецепта, тот же пул, но носитель AudioStreamPlayer3D.
## Используется NPC-звуками с привязкой к позиции (гудки трафика, сирены,
## шаги пешеходов, скрип шин). false — пул/бюджет исчерпан.
func play_sfx_3d(id: StringName, position: Vector3, gain_mul: float = 1.0) -> bool:
	var recipe := Db.stations.get_sfx(id)
	if recipe == null:
		push_warning("Audio: неизвестный SFX id %s" % id)
		return false
	var now := Time.get_ticks_msec()
	if not _alloc.try_alloc(recipe.budget_tag, recipe.cooldown_tag, now):
		return false
	var voice := _free_voice_3d()
	if voice == null:
		_alloc.release(recipe.budget_tag)
		return false
	voice.in_use = true
	voice.budget_tag = recipe.budget_tag
	voice.player.global_position = position
	voice.player.stream = SfxCache.get_stream(recipe)
	voice.player.bus = recipe.bus
	voice.player.volume_db = linear_to_db(clampf(gain_mul, 0.0001, 4.0))
	voice.player.play()
	return true


func _free_voice_3d() -> _Voice3D:
	for v in _pool_3d:
		if not v.in_use:
			return v
	return null


func _on_voice_finished(voice: _Voice) -> void:
	voice.in_use = false
	_alloc.release(voice.budget_tag)
	voice.budget_tag = &""


func _on_voice_3d_finished(voice: _Voice3D) -> void:
	voice.in_use = false
	_alloc.release(voice.budget_tag)
	voice.budget_tag = &""


## Порт duck() (audiomusic.js:213-222): ramp к to_gain за 0.05с, держать
## hold_sec, затем ramp обратно к 1 за release_sec. Работает поверх текущей
## громкости шины (в т.ч. поставленной Prefs), не абсолютным присваиванием.
func duck_music(to_gain: float, hold_sec: float, release_sec: float) -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx < 0:
		return
	var base_db := AudioServer.get_bus_volume_db(idx)
	var target_db := base_db + linear_to_db(clampf(to_gain, 0.0001, 1.0))
	var tw := create_tween()
	tw.tween_method(func(db: float) -> void: AudioServer.set_bus_volume_db(idx, db),
		base_db, target_db, 0.05)
	tw.tween_interval(hold_sec)
	tw.tween_method(func(db: float) -> void: AudioServer.set_bus_volume_db(idx, db),
		target_db, base_db, release_sec)


# --- Именованные события (замена параметризованных функций оригинала) -------

## crash(impact): k=clamp(impact/30,0,1) выбирает один из 3 запечённых тиров.
func play_crash(impact: float) -> void:
	var k := clampf(impact / 30.0, 0.0, 1.0)
	if k >= 0.7:
		play_sfx(&"crash_heavy")
	elif k >= 0.35:
		play_sfx(&"crash_medium")
	else:
		play_sfx(&"crash_light")


## cash(amount): n=clamp(1+|amount|/120, 2, 6) монет выбирает один из 3 тиров.
func play_cash(amount: float) -> void:
	var n := clampi(1 + int(absf(amount) / 120.0), 2, 6)
	if n >= 5:
		play_sfx(&"cash_large")
	elif n >= 3:
		play_sfx(&"cash_medium")
	else:
		play_sfx(&"cash_small")


func play_near_miss_streak(level: int) -> void:
	play_sfx(StringName("near_miss_streak_%d" % clampi(level, 1, 3)))


func play_combo_milestone(level: int) -> void:
	play_sfx(StringName("combo_milestone_%d" % clampi(level, 1, 3)))


## Не вызывается автоматически — PoliceManager.escaped ещё не подключён
## к аудио в этом этапе (см. отчёт), но данные и API уже готовы.
func play_police_escape(level: int) -> void:
	play_sfx(StringName("police_escape_%d" % clampi(level, 1, 3)))


# --- Радио ---------------------------------------------------------------

func set_radio_station(id: StringName) -> void:
	Prefs.radio_station = id
	Prefs.save_prefs()
	if id != &"off":
		play_sfx(&"radio_static")
	_radio.switch_to(null if id == &"off" else Db.stations.get_station(id))


func _cycle_radio_station() -> void:
	set_radio_station(Db.stations.next_station(Prefs.radio_station))


## Дистанция камеры/пеший режим — приглушение и срез фильтра радио
## (_applyRadioFilter, audiomusic.js:139-211). Вызывается из ChaseCamera.
func set_camera_state(distance: float, is_ped: bool) -> void:
	_radio.set_camera_state(distance, is_ped)


# --- Циклы машины: один вызов в физический кадр (порт updateVehicle) --------

## Поля — те, что реально доступны в этом порте (см. отчёт по этапу):
## позиция/heading, дистанция до пешеходов, сирена и NPC-гудки сознательно
## не подключены (нет источника данных без завязки на police/ped-системы,
## задокументировано как отложенное).
func update_vehicle(speed: float, throttle: float, brake: float, slip: float,
		on_road: bool, max_speed: float, car_type: StringName, running: bool,
		fuel_frac: float, damage: float, ground_y: float) -> void:
	_v_speed = speed
	_v_throttle = throttle
	_v_brake = brake
	_v_slip = slip
	_v_on_road = on_road
	_v_max_speed = max_speed
	_v_running = running
	_v_fuel_frac = fuel_frac
	_v_damage = damage
	_radio.set_speed(speed, max_speed)

	if car_type != _engine_car_type:
		_set_engine_profile(car_type)

	# updateSuspension: скачок высоты земли >0.12 за кадр -> удар подвески
	# (audioloops.js:234-247), кулдаун 0.2с decrement в _physics_process.
	if _has_ground and absf(ground_y - _prev_ground_y) > 0.12 and _bump_cooldown <= 0.0:
		play_sfx(&"suspension_bump")
		_bump_cooldown = 0.2
	_prev_ground_y = ground_y
	_has_ground = true


func _set_engine_profile(car_type: StringName) -> void:
	_engine_car_type = car_type
	if not _engine_band_cache.has(car_type):
		var bands: Array[AudioStreamWAV] = []
		for i in EngineSynth.BAND_COUNT:
			bands.append(EngineSynth.bake_band(car_type, i))
		_engine_band_cache[car_type] = bands
	var bands: Array = _engine_band_cache[car_type]
	for i in _engine_players.size():
		_engine_players[i].stream = bands[i] as AudioStreamWAV
		_engine_players[i].play()


func _build_loops() -> void:
	for i in EngineSynth.BAND_COUNT:
		var p := AudioStreamPlayer.new()
		p.bus = "Engine"
		add_child(p)
		_engine_players.append(p)
	_tire_road = _make_loop_player(&"tire_road", "Engine")
	_tire_offroad = _make_loop_player(&"tire_offroad", "Engine")
	_skid = _make_loop_player(&"skid", "SFX")
	_wind = _make_loop_player(&"wind", "Ambient")
	_brake_noise = _make_loop_player(&"brake_noise", "Engine")
	_brake_tone = _make_loop_player(&"brake_tone", "Engine")
	_rattle = _make_loop_player(&"rattle", "Engine")
	_city_ambient = _make_loop_player(&"city_ambient", "Ambient")
	_rain = _make_loop_player(&"rain", "Ambient")
	_city_ambient.volume_db = linear_to_db(0.04) # постоянный гейн (audioloops.js:249-261)


func _make_loop_player(id: StringName, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.stream = LoopSynth.bake(id)
	p.volume_db = linear_to_db(0.0001)
	add_child(p)
	p.play()
	return p


func _process(delta: float) -> void:
	if _current_state == &"driving":
		if Input.is_action_just_pressed(&"horn"):
			play_sfx(&"horn_player")
		if Input.is_action_just_pressed(&"handbrake"):
			play_sfx(&"handbrake")
	if Input.is_action_just_pressed(&"radio"):
		_cycle_radio_station()

	_rain_gain = MathUtils.damp(_rain_gain, _rain_target, RAIN_SMOOTH, delta)
	_rain.volume_db = linear_to_db(maxf(_rain_gain, 0.0001))
	_radio.tick(delta)


func _physics_process(delta: float) -> void:
	_bump_cooldown = maxf(0.0, _bump_cooldown - delta)
	if not _in_car:
		_v_speed = 0.0
		_v_throttle = 0.0
		_v_brake = 0.0
		_v_slip = 0.0
		_v_running = false
	_update_engine(delta)
	_update_tire(delta)
	_update_skid(delta)
	_update_wind(delta)
	_update_brake(delta)
	_update_rattle(delta)
	_update_fuel_warning(delta)


func _update_engine(delta: float) -> void:
	if _engine_players.is_empty():
		return
	var target_rpm := 0.0
	if _v_running:
		target_rpm = clampf(0.15 + _v_throttle * 0.55 +
			absf(_v_speed) / maxf(_v_max_speed, 1.0) * 0.3, 0.0, 1.0)
	_rpm = MathUtils.damp(_rpm, target_rpm, 0.2, delta)
	var overall := 0.0
	if _v_running:
		overall = clampf(0.5 + _v_throttle * 0.4 + _rpm * 0.3, 0.0, 1.0)
	var w := _band_weights(_rpm)
	for i in _engine_players.size():
		_engine_players[i].volume_db = linear_to_db(maxf(overall * w[i], 0.0001))


static func _band_weights(rpm: float) -> PackedFloat32Array:
	var w: PackedFloat32Array = [0.0, 0.0, 0.0]
	if rpm < 0.5:
		w[0] = 1.0 - rpm * 2.0
		w[1] = rpm * 2.0
	else:
		w[1] = 1.0 - (rpm - 0.5) * 2.0
		w[2] = (rpm - 0.5) * 2.0
	return w


## updateTyre — audioloops.js:99-134.
func _update_tire(delta: float) -> void:
	var spd := absf(_v_speed)
	var road_gain := minf(0.09, spd * 0.006) if spd > 0.5 else 0.0
	var road_target := road_gain if _v_on_road else road_gain * 0.4
	var offroad_target := 0.0 if _v_on_road else road_gain * 0.8
	_tire_road_gain = MathUtils.damp(_tire_road_gain, road_target, LOOP_SMOOTH, delta)
	_tire_offroad_gain = MathUtils.damp(_tire_offroad_gain, offroad_target, LOOP_SMOOTH, delta)
	_tire_road.volume_db = linear_to_db(maxf(_tire_road_gain, 0.0001))
	_tire_offroad.volume_db = linear_to_db(maxf(_tire_offroad_gain, 0.0001))


## updateSkid — audioloops.js:89-97.
func _update_skid(delta: float) -> void:
	var target := 0.08 * _v_slip if _v_slip > 0.02 else 0.0
	_skid_gain = MathUtils.damp(_skid_gain, target, LOOP_SMOOTH, delta)
	_skid.volume_db = linear_to_db(maxf(_skid_gain, 0.0001))


## updateWind — audioloops.js:136-159 (гейн растёт квадратично по скорости).
func _update_wind(delta: float) -> void:
	var t := clampf(absf(_v_speed) / maxf(_v_max_speed, 1.0), 0.0, 1.0)
	_wind_gain = MathUtils.damp(_wind_gain, t * t * 0.11, LOOP_SMOOTH, delta)
	_wind.volume_db = linear_to_db(maxf(_wind_gain, 0.0001))


## updateBrake — audioloops.js:161-184.
func _update_brake(delta: float) -> void:
	var spd := absf(_v_speed)
	var amt := 0.0
	if _v_brake > 0.5 and spd > 4.0:
		amt = minf(1.0, spd / 12.0) * ((_v_brake - 0.5) * 2.0)
	_brake_noise_gain = MathUtils.damp(_brake_noise_gain, amt * 0.1, LOOP_SMOOTH, delta)
	_brake_tone_gain = MathUtils.damp(_brake_tone_gain, amt * 0.05, LOOP_SMOOTH, delta)
	_brake_noise.volume_db = linear_to_db(maxf(_brake_noise_gain, 0.0001))
	_brake_tone.volume_db = linear_to_db(maxf(_brake_tone_gain, 0.0001))


## updateDamageRattle — audioloops.js:186-219.
func _update_rattle(delta: float) -> void:
	var spd := absf(_v_speed)
	var active := _v_damage > 50.0 and spd > 1.0
	var target := ((_v_damage - 50.0) / 50.0) * minf(1.0, spd / 8.0) * 0.06 if active else 0.0
	_rattle_gain = MathUtils.damp(_rattle_gain, target, LOOP_SMOOTH, delta)
	_rattle.volume_db = linear_to_db(maxf(_rattle_gain, 0.0001))
	if _v_damage > 80.0:
		_rattle_clang_timer -= delta
		if _rattle_clang_timer <= 0.0:
			play_sfx(&"rattle_clang")
			_rattle_clang_timer = randf_range(3.0, 8.0)
	else:
		_rattle_clang_timer = 0.0


## updateFuelWarning — audioloops.js:222-231.
func _update_fuel_warning(delta: float) -> void:
	var interval := 0.0
	if _v_fuel_frac < 0.05:
		interval = 3.0
	elif _v_fuel_frac < 0.12:
		interval = 8.0
	if interval <= 0.0:
		_fuel_warn_timer = 0.0
		return
	_fuel_warn_timer -= delta
	if _fuel_warn_timer <= 0.0:
		play_sfx(&"fuel_warning")
		_fuel_warn_timer = interval


# --- События Bus -------------------------------------------------------------

func _on_player_crashed(impact: float, _victim: StringName) -> void:
	play_crash(impact)
	duck_music(0.25, 0.15, 0.5)


func _on_achievement_unlocked(_id: StringName) -> void:
	play_sfx(&"achievement_fanfare")


func _on_order_event(kind: StringName, _order_id: int, data: Dictionary) -> void:
	match kind:
		&"completed":
			play_cash(float(data.get("total", 60)))
		&"failed", &"expired":
			play_sfx(&"fail")
		&"accepted":
			play_sfx(&"pickup")


func _on_juice_event(kind: StringName, data: Dictionary) -> void:
	match kind:
		&"near_miss":
			play_sfx(&"near_miss")
		&"near_miss_streak":
			play_near_miss_streak(int(data.get("level", 1)))
		&"combo":
			play_combo_milestone(int(data.get("level", 1)))


func _on_notify(kind: StringName, _text: String, data: Dictionary) -> void:
	if kind == &"dialogue":
		play_sfx(&"voice_default")
	elif kind == &"siren":
		var pos_v: Variant = data.get("position")
		if pos_v is Vector3:
			play_sfx_3d(&"siren_police", pos_v)


func _on_weather_changed(id: StringName) -> void:
	var raining := id == &"rain"
	_rain_target = 0.06 if raining else 0.0
	_radio.set_rain(raining)


func _on_time_changed(hour: float, _day: int, is_night: bool) -> void:
	_radio.set_hour(hour)
	if is_night != _was_night:
		_was_night = is_night
		play_sfx(&"day_night_chime")


func _on_game_state_changed(state: StringName) -> void:
	_current_state = state
	if state == &"driving":
		_radio.switch_to(Db.stations.get_station(Prefs.radio_station))
	else:
		_radio.switch_to(null)


func _on_vehicle_mode_changed(in_car: bool) -> void:
	_in_car = in_car
	if in_car:
		play_sfx(&"door_close")
		play_sfx(&"engine_start")
	else:
		play_sfx(&"door_open")
