class_name SfxRecipeData
extends RefCounted
## Числа для ~30 SFX-рецептов, порт функций SfxLibrary.* (audiosfx.js) плюс
## несколько триггеров зацикленных слоёв (audioloops.js) и один переход радио.
##
## Оригинал хранит эти числа буквально в теле функций, а не в вынесенных
## top-level константах — `tools/dump_data.mjs` их достать не может (см.
## комментарий в `tools/import_json.gd:_import_sfx`), поэтому они перенесены
## сюда вручную по отчёту сверки с audiosfx.js/audioloops.js. Многослойные
## эффекты оригинала (несколько одновременных/последовательных `tone()` в
## одном методе) — несколько `SfxRecipeLayer` с своим `start_offset`.
##
## Параметризованные по уровню/типу эффекты оригинала (horn(type),
## policeEscape(level), ...) запечены как несколько дискретных рецептов —
## AudioDirector выбирает нужный по входному параметру во время игры вместо
## пересинтеза на лету.

const Wave = SfxRecipe.Wave
const Filter = SfxRecipe.Filter


static func build_all() -> Array[SfxRecipe]:
	var out: Array[SfxRecipe] = []
	out.append_array(_horns())
	out.append_array(_crashes())
	out.append_array(_cash())
	out.append(_pickup())
	out.append(_speak())
	out.append(_fail())
	out.append(_ped_hit())
	out.append(_thud())
	out.append(_stall())
	out.append(_click())
	out.append(_refuel())
	out.append(_bird())
	out.append(_race_go())
	out.append(_edge_bump())
	out.append(_near_miss())
	out.append_array(_police_escape())
	out.append_array(_near_miss_streak())
	out.append_array(_combo_milestone())
	out.append(_door_close())
	out.append(_door_open())
	out.append(_engine_start())
	out.append(_handbrake())
	out.append_array(_voices())
	out.append(_day_night_chime())
	out.append(_thunder())
	out.append(_shift_end())
	out.append(_order_timer_beep())
	out.append(_siren_police())
	out.append(_siren_ambulance())
	out.append(_achievement_fanfare())
	out.append(_footstep())
	out.append(_radio_static())
	out.append(_fuel_warning())
	out.append(_suspension_bump())
	out.append(_rattle_clang())
	return out


# --- Хелперы -------------------------------------------------------------

static func _tone(wave: int, f0: float, f1: float, dur: float, gain: float,
		offset: float = 0.0, exponential: bool = true) -> SfxRecipeLayer:
	var l := SfxRecipeLayer.new()
	l.wave = wave
	l.freq_start = f0
	l.freq_end = f1
	l.freq_exponential = exponential
	l.duration = dur
	l.start_offset = offset
	l.attack = minf(0.015, dur * 0.3)
	l.decay = maxf(dur - l.attack, 0.001)
	l.sustain = 0.0
	l.release = 0.001
	l.gain = gain
	return l


static func _noise(dur: float, gain: float, cutoff: float, offset: float = 0.0,
		filter: int = Filter.LOWPASS, resonance: float = 1.0) -> SfxRecipeLayer:
	var l := SfxRecipeLayer.new()
	l.wave = Wave.NOISE
	l.duration = dur
	l.start_offset = offset
	l.attack = 0.0
	l.decay = dur
	l.sustain = 0.0
	l.release = 0.0
	l.gain = gain
	l.filter = filter
	l.cutoff_start = cutoff
	l.cutoff_end = cutoff
	l.resonance = resonance
	return l


static func _dur_of(layers: Array[SfxRecipeLayer]) -> float:
	var d := 0.0
	for l in layers:
		d = maxf(d, l.start_offset + l.duration)
	return d


static func _recipe(id: StringName, bus: StringName, layers: Array[SfxRecipeLayer],
		budget_tag: StringName = &"", cooldown_tag: StringName = &"",
		variants: int = 1, spread: float = 1.0) -> SfxRecipe:
	var r := SfxRecipe.new()
	r.id = id
	r.bus = bus
	r.layers = layers
	r.duration = _dur_of(layers)
	r.budget_tag = budget_tag
	r.cooldown_tag = cooldown_tag
	r.variants = variants
	r.variant_pitch_spread = spread
	return r


# --- horn() — audiosfx.js:12-71 -------------------------------------------

static func _horns() -> Array[SfxRecipe]:
	var out: Array[SfxRecipe] = []
	# player — единственный 4-слойный: 2 пилы на большую терцию + 2 суб-баса.
	out.append(_recipe(&"horn_player", &"SFX", [
		_tone(Wave.SAW, 293.66, 293.66, 0.65, 0.16),
		_tone(Wave.SAW, 369.99, 369.99, 0.65, 0.14),
		_tone(Wave.SINE, 146.83, 146.83, 0.65, 0.22),
		_tone(Wave.SINE, 73.415, 73.415, 0.65, 0.15),
	], &"horn", &"horn"))
	out.append(_recipe(&"horn_truck", &"SFX", [
		_tone(Wave.SAW, 185.0, 185.0, 0.6, 0.18),
		_tone(Wave.SAW, 233.0, 233.0, 0.6, 0.15),
		_tone(Wave.SINE, 92.5, 92.5, 0.6, 0.22),
	], &"horn", &"horn"))
	out.append(_recipe(&"horn_suv", &"SFX", [
		_tone(Wave.SAW, 330.0, 330.0, 0.45, 0.14),
		_tone(Wave.SQUARE, 415.0, 415.0, 0.45, 0.12),
		_tone(Wave.SINE, 165.0, 165.0, 0.45, 0.15),
	], &"horn", &"horn"))
	out.append(_recipe(&"horn_classic", &"SFX", [
		_tone(Wave.SAW, 370.0, 370.0, 0.45, 0.14),
		_tone(Wave.SAW, 293.66, 293.66, 0.45, 0.14),
		_tone(Wave.SINE, 146.83, 146.83, 0.45, 0.12),
	], &"horn", &"horn"))
	out.append(_recipe(&"horn_sedan", &"SFX", [
		_tone(Wave.SAW, 415.0, 415.0, 0.45, 0.13),
		_tone(Wave.SQUARE, 330.0, 330.0, 0.45, 0.11),
		_tone(Wave.SINE, 165.0, 165.0, 0.45, 0.10),
	], &"horn", &"horn"))
	return out


# --- crash(impact) — audiosfx.js:73-81, 3 дискретных тира по k=impact/30 ---

static func _crash_tier(id: StringName, k: float) -> SfxRecipe:
	return _recipe(id, &"SFX", [
		_noise(0.3 + k * 0.3, 0.4 + k * 0.4, 350.0 + k * 800.0),
		_tone(Wave.SINE, 70.0, 35.0, 0.4, 0.35 + k * 0.25),
		_tone(Wave.SAW, 160.0, 50.0, 0.25, 0.15 + k * 0.15),
	], &"crash", &"crash")


static func _crashes() -> Array[SfxRecipe]:
	return [_crash_tier(&"crash_light", 0.15), _crash_tier(&"crash_medium", 0.5),
		_crash_tier(&"crash_heavy", 0.85)]


# --- cash(amount) — audiosfx.js:83-90, n монет = clamp(1+|amount|/120, 2, 6) --

static func _cash_tier(id: StringName, n: int) -> SfxRecipe:
	var layers: Array[SfxRecipeLayer] = []
	for i in n:
		layers.append(_tone(Wave.TRIANGLE, 1046.5 + i * 180.0, 1318.5, 0.1, 0.14, i * 0.09))
	return _recipe(id, &"SFX", layers)


static func _cash() -> Array[SfxRecipe]:
	return [_cash_tier(&"cash_small", 2), _cash_tier(&"cash_medium", 4),
		_cash_tier(&"cash_large", 6)]


# --- остальные одноразовые --------------------------------------------------

static func _pickup() -> SfxRecipe:
	return _recipe(&"pickup", &"SFX", [
		_tone(Wave.SINE, 523.25, 523.25, 0.12, 0.16),
		_tone(Wave.SINE, 659.25, 659.25, 0.12, 0.16, 0.08),
		_tone(Wave.TRIANGLE, 783.99, 783.99, 0.14, 0.16, 0.16),
	])


static func _speak() -> SfxRecipe:
	return _recipe(&"speak", &"SFX", [
		_tone(Wave.SINE, 480.0, 480.0, 0.12, 0.15),
		_tone(Wave.SINE, 640.0, 640.0, 0.12, 0.15, 0.05),
	])


static func _fail() -> SfxRecipe:
	return _recipe(&"fail", &"SFX", [
		_tone(Wave.SAW, 293.66, 220.0, 0.22, 0.15),
		_tone(Wave.SAW, 220.0, 140.0, 0.35, 0.15, 0.18),
	])


static func _ped_hit() -> SfxRecipe:
	return _recipe(&"ped_hit", &"SFX", [
		_noise(0.35, 0.4, 450.0),
		_tone(Wave.SINE, 130.0, 60.0, 0.35, 0.25),
	], &"ped", &"ped_hit")


static func _thud() -> SfxRecipe:
	return _recipe(&"thud", &"SFX", [
		_noise(0.2, 0.4, 300.0),
		_tone(Wave.SINE, 90.0, 40.0, 0.2, 0.3),
	], &"ped", &"thud")


static func _stall() -> SfxRecipe:
	return _recipe(&"stall", &"SFX", [
		_tone(Wave.SAW, 110.0, 35.0, 0.5, 0.14),
		_noise(0.06, 0.12, 900.0, 0.05),
		_noise(0.06, 0.12, 900.0, 0.18),
		_noise(0.06, 0.12, 900.0, 0.31),
	])


static func _click() -> SfxRecipe:
	return _recipe(&"click", &"UI", [
		_tone(Wave.TRIANGLE, 587.33, 587.33, 0.05, 0.09),
	], &"click", &"click")


static func _refuel() -> SfxRecipe:
	return _recipe(&"refuel", &"SFX", [
		_noise(2.6, 0.05, 300.0),
		_tone(Wave.SAW, 261.63, 880.0, 0.15, 0.07, 2.5),
		_tone(Wave.TRIANGLE, 1400.0, 1400.0, 0.05, 0.08, 2.75),
	])


## Частота в оригинале — random(1900..3100), здесь баллистика 4 вариантов
## AudioStreamRandomizer вместо синтеза на лету.
static func _bird() -> SfxRecipe:
	return _recipe(&"bird", &"Ambient", [
		_tone(Wave.SINE, 2400.0, 2400.0, 0.08, 0.03),
		_tone(Wave.SINE, 2112.0, 2112.0, 0.07, 0.025, 0.09),
	], &"", &"", 4, 8.6)


static func _race_go() -> SfxRecipe:
	return _recipe(&"race_go", &"SFX", [
		_tone(Wave.SQUARE, 523.25, 523.25, 0.14, 0.15),
		_tone(Wave.SQUARE, 659.25, 659.25, 0.18, 0.15, 0.18),
		_tone(Wave.SQUARE, 783.99, 783.99, 0.28, 0.15, 0.36),
	])


static func _edge_bump() -> SfxRecipe:
	return _recipe(&"edge_bump", &"SFX", [
		_noise(0.15, 0.25, 500.0),
		_tone(Wave.SINE, 70.0, 70.0, 0.15, 0.2),
	])


static func _near_miss() -> SfxRecipe:
	return _recipe(&"near_miss", &"SFX", [
		_noise(0.14, 0.2, 800.0),
		_tone(Wave.SINE, 550.0, 280.0, 0.14, 0.12),
	])


# --- policeEscape(level)/nearMissStreak(level)/comboMilestone(level) ------
# Все три — арпеджио вверх той же формы с разными коэффициентами по уровню
# 1..3 (audiosfx.js:189-231). level>=3 добавляет четвёртый слой (saw, октава).

static func _police_escape() -> Array[SfxRecipe]:
	var out: Array[SfxRecipe] = []
	for level in [1, 2, 3]:
		var g: float = 0.14 + level * 0.03
		var base: float = 440.0 + level * 60.0
		var layers: Array[SfxRecipeLayer] = [
			_tone(Wave.TRIANGLE, base, base * 1.3, 0.10, g),
			_tone(Wave.TRIANGLE, base * 1.25, base * 1.5, 0.10, g * 0.9, 0.06),
			_tone(Wave.SINE, base * 1.5, base * 1.7, 0.14, g * 0.85, 0.12),
			_noise(0.12, g * 0.4, 1200.0),
		]
		if level >= 3:
			layers.append(_tone(Wave.SAW, base * 2.0, base * 1.9, 0.16, g * 0.5, 0.18))
		out.append(_recipe(StringName("police_escape_%d" % level), &"SFX", layers))
	return out


static func _near_miss_streak() -> Array[SfxRecipe]:
	var out: Array[SfxRecipe] = []
	for level in [1, 2, 3]:
		var g: float = 0.14 + level * 0.03
		var base_freq: float = 520.0 + level * 160.0
		var layers: Array[SfxRecipeLayer] = [
			_noise(0.16, g, 900.0 + level * 250.0),
			_tone(Wave.TRIANGLE, base_freq, base_freq * 0.7, 0.15, g),
			_tone(Wave.SINE, base_freq * 1.5, base_freq * 1.1, 0.12, g * 0.85, 0.04),
		]
		if level >= 3:
			layers.append(_tone(Wave.SAW, base_freq * 2.0, base_freq * 1.3, 0.18, g * 0.6, 0.08))
		out.append(_recipe(StringName("near_miss_streak_%d" % level), &"SFX", layers))
	return out


static func _combo_milestone() -> Array[SfxRecipe]:
	var out: Array[SfxRecipe] = []
	for level in [1, 2, 3]:
		var g: float = 0.12 + level * 0.03
		var base: float = 440.0 + level * 80.0
		var layers: Array[SfxRecipeLayer] = [
			_tone(Wave.TRIANGLE, base, base * 1.3, 0.10, g),
			_tone(Wave.TRIANGLE, base * 1.25, base * 1.5, 0.10, g * 0.9, 0.06),
			_tone(Wave.SINE, base * 1.5, base * 1.7, 0.14, g * 0.85, 0.12),
		]
		if level >= 3:
			layers.append(_tone(Wave.SAW, base * 2.0, base * 1.9, 0.16, g * 0.5, 0.18))
		out.append(_recipe(StringName("combo_milestone_%d" % level), &"SFX", layers))
	return out


static func _door_close() -> SfxRecipe:
	return _recipe(&"door_close", &"SFX", [
		_noise(0.02, 0.15, 3000.0),
		_tone(Wave.SINE, 130.0, 80.0, 0.12, 0.2, 0.01),
		_tone(Wave.TRIANGLE, 220.0, 220.0, 0.08, 0.08, 0.02),
	])


static func _door_open() -> SfxRecipe:
	return _recipe(&"door_open", &"SFX", [
		_tone(Wave.SAW, 190.0, 110.0, 0.25, 0.06),
		_noise(0.03, 0.08, 2000.0, 0.24),
	])


static func _engine_start() -> SfxRecipe:
	return _recipe(&"engine_start", &"SFX", [
		_noise(0.5, 0.08, 500.0),
		_tone(Wave.SQUARE, 42.0, 50.0, 0.5, 0.1),
		_tone(Wave.SAW, 48.0, 46.0, 0.25, 0.12, 0.55),
	])


static func _handbrake() -> SfxRecipe:
	return _recipe(&"handbrake", &"SFX", [
		_noise(0.02, 0.08, 3500.0, 0.0),
		_noise(0.02, 0.08, 3500.0, 0.032),
		_noise(0.02, 0.08, 3500.0, 0.064),
		_noise(0.02, 0.08, 3500.0, 0.096),
	])


# --- spatialSpeak(type) — audiosfx.js:266-355, 5 тембров -------------------
# Общий фильтр lowpass над суммой осцилляторов эквивалентен фильтру на каждом
# слое отдельно (линейность фильтра), поэтому cutoff_* задан на каждом слое.

static func _voice(id: StringName, layers: Array[SfxRecipeLayer],
		cutoff_start: float = 0.0, cutoff_end: float = 0.0) -> SfxRecipe:
	if cutoff_start > 0.0:
		for l in layers:
			l.filter = Filter.LOWPASS
			l.cutoff_start = cutoff_start
			l.cutoff_end = cutoff_end
	return _recipe(id, &"Voice", layers, &"voice")


static func _voices() -> Array[SfxRecipe]:
	return [
		_voice(&"voice_angry", [
			_tone(Wave.SAW, 110.0, 160.0, 0.1, 0.26, 0.0, false),
			_tone(Wave.SAW, 160.0, 95.0, 0.18, 0.26, 0.1, false),
			_tone(Wave.SQUARE, 85.0, 130.0, 0.1, 0.2, 0.0, false),
			_tone(Wave.SQUARE, 130.0, 75.0, 0.18, 0.2, 0.1, false),
		], 450.0, 350.0),
		_voice(&"voice_scream", [
			_tone(Wave.TRIANGLE, 480.0, 820.0, 0.12, 0.22),
			_tone(Wave.TRIANGLE, 820.0, 350.0, 0.16, 0.22, 0.12),
		]),
		_voice(&"voice_greeting", [
			_tone(Wave.SINE, 440.0, 440.0, 0.12, 0.12),
			_tone(Wave.SINE, 554.0, 554.0, 0.12, 0.12, 0.06),
			_tone(Wave.SINE, 659.0, 659.0, 0.12, 0.12, 0.12),
		]),
		_voice(&"voice_shock", [
			_tone(Wave.SINE, 620.0, 320.0, 0.2, 0.15),
			_tone(Wave.SINE, 320.0, 540.0, 0.18, 0.15, 0.2),
		]),
		_voice(&"voice_default", [
			_tone(Wave.SINE, 340.0, 540.0, 0.09, 0.14),
			_tone(Wave.SINE, 540.0, 420.0, 0.09, 0.14, 0.09),
		]),
	]


static func _day_night_chime() -> SfxRecipe:
	return _recipe(&"day_night_chime", &"Ambient", [
		_tone(Wave.SINE, 392.0, 392.0, 0.2, 0.12),
		_tone(Wave.SINE, 493.88, 493.88, 0.2, 0.12, 0.22),
		_tone(Wave.SINE, 587.33, 587.33, 0.5, 0.12, 0.44),
	])


static func _thunder() -> SfxRecipe:
	return _recipe(&"thunder", &"SFX", [
		_noise(0.9, 0.22, 400.0),
		_tone(Wave.SINE, 38.0, 30.0, 0.9, 0.18),
	], &"crash", &"crash")


static func _shift_end() -> SfxRecipe:
	return _recipe(&"shift_end", &"UI", [
		_tone(Wave.SINE, 659.25, 659.25, 0.15, 0.15),
		_tone(Wave.SINE, 587.33, 587.33, 0.15, 0.15, 0.15),
		_tone(Wave.SINE, 523.25, 523.25, 0.15, 0.15, 0.3),
		_tone(Wave.SINE, 392.0, 392.0, 0.35, 0.15, 0.45),
	])


## Частота в оригинале растёт 660..990 по оставшимся секундам (10..0) —
## countdown-таймер заказов ещё не подключён к аудио (см. отчёт этапа),
## рецепт запечён на номинальной середине диапазона.
static func _order_timer_beep() -> SfxRecipe:
	return _recipe(&"order_timer_beep", &"UI", [
		_tone(Wave.SINE, 800.0, 800.0, 0.1, 0.07),
	])


static func _siren_police() -> SfxRecipe:
	var layers: Array[SfxRecipeLayer] = []
	for i in 4:
		layers.append(_tone(Wave.SQUARE, 960.0, 680.0, 0.084, 0.11, i * 0.17, false))
	return _recipe(&"siren_police", &"SFX", layers, &"siren")


## Двухтоновый вой (LFO 3.2Гц, 550/950Гц) упрощён до одного плавного свипа —
## ступенчатая LFO-модуляция не переносится 1:1 в двухточечный свип рецепта.
static func _siren_ambulance() -> SfxRecipe:
	return _recipe(&"siren_ambulance", &"SFX", [
		_tone(Wave.SINE, 550.0, 950.0, 1.4, 0.09, 0.0, false),
	], &"siren")


static func _achievement_fanfare() -> SfxRecipe:
	var notes := [261.63, 329.63, 392.0, 523.25]
	var layers: Array[SfxRecipeLayer] = []
	for i in notes.size():
		var f: float = notes[i]
		var off: float = i * 0.12
		layers.append(_tone(Wave.SINE, f, f, 0.13, 0.13, off))
		layers.append(_tone(Wave.TRIANGLE, f * 0.5, f * 0.5, 0.13, 0.065, off))
	layers.append(_tone(Wave.SINE, 523.25, 523.25, 0.4, 0.1, 0.48))
	return _recipe(&"achievement_fanfare", &"UI", layers)


static func _footstep() -> SfxRecipe:
	return _recipe(&"footstep", &"SFX", [
		_noise(0.05, 0.05, 220.0),
	], &"voice", &"step")


## Скретч-переход между радиостанциями (audiomusic.js:83-114) — свип bandpass
## 1500->5500->2000Гц + синус-свип 800->3200->1200Гц, каждый как 2 звена.
static func _radio_static() -> SfxRecipe:
	return _recipe(&"radio_static", &"Music", [
		_noise(0.2, 0.2, 3500.0, 0.0, Filter.BANDPASS, 1.5),
		_noise(0.15, 0.15, 3750.0, 0.2, Filter.BANDPASS, 1.5),
		_tone(Wave.SINE, 800.0, 3200.0, 0.2, 0.05),
		_tone(Wave.SINE, 3200.0, 1200.0, 0.15, 0.05, 0.2),
	])


## updateFuelWarning() — audioloops.js:222-231.
static func _fuel_warning() -> SfxRecipe:
	return _recipe(&"fuel_warning", &"UI", [
		_tone(Wave.SINE, 880.0, 880.0, 0.12, 0.06),
	])


## updateSuspension() — audioloops.js:234-247.
static func _suspension_bump() -> SfxRecipe:
	return _recipe(&"suspension_bump", &"Engine", [
		_noise(0.1, 0.15, 400.0),
		_tone(Wave.SINE, 95.0, 55.0, 0.18, 0.12),
	])


## updateDamageRattle() — металлический лязг при damage>80 (audioloops.js:212-217).
static func _rattle_clang() -> SfxRecipe:
	return _recipe(&"rattle_clang", &"Engine", [
		_noise(0.08, 0.12, 1800.0),
	])
