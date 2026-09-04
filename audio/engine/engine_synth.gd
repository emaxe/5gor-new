class_name EngineSynth
extends RefCounted
## Запекает 3 зацикленных сэмпла двигателя (низкий/средний/высокий RPM) на
## тип машины. Порт LOOP_ENGINE_PROFILES + updateEngine() (audioloops.js) —
## непрерывная параметризация оригинала (несущая=engineBase+rpm*140,
## фильтр=300+rpm*900+throttle*350) заменена тремя опорными точками по RPM:
## в рантайме AudioDirector кроссфейдит их громкость и подстраивает
## `pitch_scale` между полосами — живой пересинтез каждый кадр недопустим
## (план, «Аудио — уточнения», п.10).

## engineBase(Гц), mixSquare, mixTri на тип машины (audioloops.js:9-17).
const PROFILES := {
	&"taxi": {"base": 46.0, "sq": 0.5, "tri": 0.18},
	&"classic": {"base": 45.0, "sq": 0.55, "tri": 0.15},
	&"comfort": {"base": 50.0, "sq": 0.35, "tri": 0.25},
	&"minivan": {"base": 44.0, "sq": 0.3, "tri": 0.32},
	&"business": {"base": 58.0, "sq": 0.22, "tri": 0.35},
	&"sport": {"base": 62.0, "sq": 0.15, "tri": 0.12},
	&"offroad": {"base": 50.0, "sq": 0.4, "tri": 0.28},
}
const DEFAULT_PROFILE := {"base": 46.0, "sq": 0.5, "tri": 0.18}

## Опорные точки RPM (0..1 нормализовано) для трёх зацикленных сэмплов.
const BANDS: PackedFloat32Array = [0.0, 0.5, 1.0]
const BAND_COUNT := 3
const LOOP_SECONDS := 0.5
## updateEngine: cutoff = 300+rpm*900+throttle*350 — throttle усреднён на
## 0.5, реальный throttle в рантайме модулирует громкость, не фильтр.
const REF_THROTTLE := 0.5


static func bake_band(car_type: StringName, band_index: int) -> AudioStreamWAV:
	var prof: Dictionary = PROFILES.get(car_type, DEFAULT_PROFILE)
	var rpm: float = BANDS[band_index]
	var base: float = float(prof["base"]) + rpm * 140.0
	var cutoff: float = 300.0 + rpm * 900.0 + REF_THROTTLE * 350.0
	# Длительность лупа выравнивается на целое число периодов несущей —
	# иначе на стыке слышен щелчок.
	var period := 1.0 / maxf(base, 1.0)
	var loops_n := maxi(1, int(round(LOOP_SECONDS / period)))
	var dur := period * loops_n

	var recipe := SfxRecipe.new()
	recipe.id = StringName("engine_%s_%d" % [String(car_type), band_index])
	recipe.looping = true
	recipe.duration = dur
	var layers: Array[SfxRecipeLayer] = [
		_layer(SfxRecipe.Wave.SAW, base, dur, 1.0),
		_layer(SfxRecipe.Wave.SQUARE, base * 0.5, dur, float(prof["sq"])),
		_layer(SfxRecipe.Wave.TRIANGLE, base * 1.5, dur, float(prof["tri"])),
	]
	for layer in layers:
		layer.filter = SfxRecipe.Filter.LOWPASS
		layer.cutoff_start = cutoff
		layer.cutoff_end = cutoff
		layer.resonance = 2.5
	recipe.layers = layers
	return SfxSynth.synthesize(recipe, 0, 1)


static func _layer(wave: int, freq: float, dur: float, gain: float) -> SfxRecipeLayer:
	var l := SfxRecipeLayer.new()
	l.wave = wave
	l.freq_start = freq
	l.freq_end = freq
	l.duration = dur
	l.attack = 0.0
	l.decay = 0.0
	l.sustain = 1.0
	l.release = 0.0
	l.gain = gain
	return l
