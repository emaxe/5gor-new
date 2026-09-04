class_name RadioSequencer
extends RefCounted
## Секвенсор радиостанций. Порт audiomusic.js: там на каждую станцию —
## литеральные CHORDS_*/BASS_*/MELODY_* массивы, зашитые в код; здесь вместо
## них генератор паттерна по данным станции (RadioStationData.scale_steps/
## instruments/drum_density/texture) — решение уже заложено при переносе
## станций в tools/import_json.gd (см. комментарий _import_audio).
##
## Тайминг — по накопленному реальному времени (`_elapsed`), а не по
## аккумуляции дельт кадра: индекс шага не может отстать от реального времени
## даже при просадках FPS, что и даёт эффект lookahead-планировщика оригинала
## (setTimeout-цикл с lookahead 0.03с поверх ctx.currentTime) без прямого
## доступа к сэмпл-точному будущему времени микшера, которого нет в
## высокоуровневом Godot Audio API.

const STEPS_PER_BAR := 16

var _player: AudioStreamPlayer
var _playback: AudioStreamPlaybackPolyphonic
var _lp: AudioEffectLowPassFilter

var _station: RadioStationData
var _bank: Dictionary[StringName, AudioStreamWAV] = {}
var _bank_cache: Dictionary[StringName, Dictionary] = {}

var _is_night := false
var _step_dur := 0.5
var _elapsed := 0.0
var _next_step := 0.0
var _step_index := 0
var _active := false
var _rng := RandomNumberGenerator.new()

## Кроссфейд станции: 0 idle, 1 fade-out(0.12с), 2 тишина(0.18с), 3 fade-in(0.2с).
## Суммарно ~0.5с — порт _playStatic()/fadeGain-автоматизации (audiomusic.js:83-133).
var _switch_phase := 0
var _switch_timer := 0.0
var _pending_station: RadioStationData
var _pending_off := true

## Приглушение по дистанции камеры/дождю/скорости/пешему режиму
## (_applyRadioFilter, audiomusic.js:139-211).
var _cam_dist := 9.5
var _is_ped := false
var _raining := false
var _high_speed := false
var _lp_current := 6500.0


func setup(player: AudioStreamPlayer, lowpass: AudioEffectLowPassFilter) -> void:
	_player = player
	_lp = lowpass
	_player.bus = "Music"
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 32
	_player.stream = poly
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamPlaybackPolyphonic


## null — «радио выключено» (переход в тишину тем же кроссфейдом).
func switch_to(station: RadioStationData) -> void:
	if station == _station and _switch_phase == 0 and (_active or station == null):
		return
	_pending_station = station
	_pending_off = station == null
	_switch_phase = 1
	_switch_timer = 0.0


func set_hour(hour: float) -> void:
	# RadioEngine.setHour: ночь 22:00-06:00 (унифицировано с локальным порогом
	# day/night chime — в оригинале эти два места расходились на 20:00/22:00,
	# сознательно не переносим расхождение).
	var night := hour >= 22.0 or hour < 6.0
	if night != _is_night:
		_is_night = night
		_apply_bpm()


func set_camera_state(distance: float, is_ped: bool) -> void:
	_cam_dist = distance
	_is_ped = is_ped


func set_rain(raining: bool) -> void:
	_raining = raining


func set_speed(speed: float, max_speed: float) -> void:
	_high_speed = absf(speed) > maxf(max_speed, 1.0) * 0.65


func tick(delta: float) -> void:
	var fade := _update_switch(delta)
	_apply_radio_filter(delta, fade)
	if not _active or _station == null:
		return
	_elapsed += delta
	while _elapsed >= _next_step:
		_do_step()
		_next_step += _step_dur


func _apply_bpm() -> void:
	if _station == null:
		return
	var bpm := _station.bpm * (0.94 if _is_night else 1.0)
	_step_dur = (60.0 / bpm) / 4.0


func _update_switch(delta: float) -> float:
	if _switch_phase == 0:
		return 1.0
	_switch_timer += delta
	match _switch_phase:
		1:
			if _switch_timer >= 0.12:
				_switch_phase = 2
				_switch_timer = 0.0
				_swap_station()
			return 1.0 - clampf(_switch_timer / 0.12, 0.0, 1.0)
		2:
			if _switch_timer >= 0.18:
				_switch_phase = 3
				_switch_timer = 0.0
			return 0.0
		3:
			var p := clampf(_switch_timer / 0.2, 0.0, 1.0)
			if p >= 1.0:
				_switch_phase = 0
			return p
	return 1.0


func _swap_station() -> void:
	_active = not _pending_off
	_station = _pending_station
	_elapsed = 0.0
	_next_step = 0.0
	_step_index = 0
	if _station == null:
		return
	if not _bank_cache.has(_station.id):
		_bank_cache[_station.id] = InstrumentSynth.bake_bank(_station.instruments)
	_bank = _bank_cache[_station.id]
	_apply_bpm()


func _apply_radio_filter(delta: float, fade: float) -> void:
	if _lp == null or _player == null:
		return
	var t := clampf((_cam_dist - 5.0) / (16.0 - 5.0), 0.0, 1.0)
	var max_freq := 4500.0 if _raining else 6500.0
	var target := max_freq - t * (max_freq - 900.0)
	if _high_speed:
		var boost := 3000.0 if _raining else 5500.0
		target += (1.0 - t * 0.7) * boost
	if _is_ped:
		target = minf(target, 2000.0)
	target = clampf(target, 400.0, 14000.0)
	_lp_current = MathUtils.damp(_lp_current, target, 0.2, delta)
	_lp.cutoff_hz = _lp_current
	var gain_mul := clampf((1.0 - t * 0.45) * fade, 0.0001, 1.0)
	_player.volume_db = linear_to_db(gain_mul)


func _do_step() -> void:
	var step := _step_index % STEPS_PER_BAR
	_step_index += 1
	if _station == null:
		return
	var degrees := _station.scale_steps
	if degrees.is_empty():
		return
	var drum_density := _station.drum_density
	var texture := _station.texture
	# Аккорд/степень лада меняется раз в долю (4 шестнадцатых = 1 доля).
	@warning_ignore("integer_division")
	var deg_idx := (step / 4) % degrees.size()
	var semi := degrees[deg_idx]

	if _bank.has(&"kick") and (step % 8 == 0 or (drum_density > 0.6 and step % 8 == 6)):
		_hit(&"kick", 0.0, 0.9)
	if step == 4 or step == STEPS_PER_BAR - 4:
		if _bank.has(&"snare"):
			_hit(&"snare", 0.0, 0.8)
		elif _bank.has(&"clap"):
			_hit(&"clap", 0.0, 0.8)
	if _bank.has(&"hat_closed") and _rng.randf() < drum_density:
		var open := step % 4 == 2 and drum_density > 0.5
		_hit(&"hat_open" if open else &"hat_closed", 0.0, 0.5)
	if _bank.has(&"bass") and step % 4 == 0:
		_hit(&"bass", float(semi), 0.85)
	if _bank.has(&"lead") and step % 2 == 0 and _rng.randf() < texture * 0.5:
		_hit(&"lead", float(degrees[_rng.randi() % degrees.size()]), 0.6)
	if _bank.has(&"arp") and step % 2 == 0:
		@warning_ignore("integer_division")
		var arp_idx := (_step_index / 2) % degrees.size()
		_hit(&"arp", float(degrees[arp_idx]), 0.5)
	if _bank.has(&"pad") and step == 0:
		_hit(&"pad", 0.0, 0.5)


func _hit(name: StringName, semitones: float, volume: float) -> void:
	if _playback == null:
		return
	var stream: AudioStreamWAV = _bank.get(name)
	if stream == null:
		return
	var pitch := pow(2.0, semitones / 12.0)
	_playback.play_stream(stream, 0.0, linear_to_db(volume), pitch, 0, "Music")


func player() -> AudioStreamPlayer:
	return _player
