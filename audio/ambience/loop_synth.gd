class_name LoopSynth
extends RefCounted
## Запекает статические (не зависящие от типа машины) зацикленные слои:
## визг шин, качение по дороге/бездорожью, ветер, тормоза, дребезг повреждения,
## городской эмбиент, дождь. Порт audioloops.js — в оригинале громкость/фильтр
## этих слоёв непрерывно автоматизируются по скорости/slip/повреждению; здесь
## запекается фиксированный тембр, а громкость/`pitch_scale` крутит
## AudioDirector в рантайме (без пересинтеза каждый кадр).

const LEN_SHORT := 1.0
const LEN_MED := 1.5


static func bake(id: StringName) -> AudioStreamWAV:
	match id:
		&"skid":
			# updateSkid: bandpass ~950Гц Q2 (audioloops.js:89-97).
			return _noise_loop(LEN_MED, SfxRecipe.Filter.BANDPASS, 950.0, 2.0)
		&"tire_road":
			# updateTyre: bandpass ~400Гц Q0.7, дорога (audioloops.js:99-134).
			return _noise_loop(LEN_MED, SfxRecipe.Filter.BANDPASS, 400.0, 0.7)
		&"tire_offroad":
			# updateTyre: bandpass ~1400Гц Q1.2, бездорожье.
			return _noise_loop(LEN_MED, SfxRecipe.Filter.BANDPASS, 1400.0, 1.2)
		&"wind":
			# updateWind: highpass 380Гц (audioloops.js:136-159).
			return _noise_loop(LEN_MED, SfxRecipe.Filter.HIGHPASS, 380.0, 0.7)
		&"brake_noise":
			# updateBrake: bandpass 2400Гц Q9 — узкий резонансный визг.
			return _noise_loop(LEN_SHORT, SfxRecipe.Filter.BANDPASS, 2400.0, 9.0)
		&"brake_tone":
			return _tone_loop(1650.0)
		&"rattle":
			return _rattle_loop()
		&"city_ambient":
			# Городской гул: lowpass 350Гц, гейн постоянный (audioloops.js:249-261).
			return _noise_loop(3.0, SfxRecipe.Filter.LOWPASS, 350.0, 0.7)
		&"rain":
			# highpass 1100Гц (audioloops.js:263-276).
			return _noise_loop(LEN_MED, SfxRecipe.Filter.HIGHPASS, 1100.0, 0.7)
		_:
			push_warning("LoopSynth: неизвестный id %s" % id)
			return null


static func _noise_loop(seconds: float, filter: int, cutoff: float, q: float) -> AudioStreamWAV:
	var recipe := SfxRecipe.new()
	recipe.looping = true
	recipe.duration = seconds
	var layer := SfxRecipeLayer.new()
	layer.wave = SfxRecipe.Wave.NOISE
	layer.duration = seconds
	layer.attack = 0.0
	layer.decay = 0.0
	layer.sustain = 1.0
	layer.release = 0.0
	layer.gain = 1.0
	layer.filter = filter
	layer.cutoff_start = cutoff
	layer.cutoff_end = cutoff
	layer.resonance = q
	recipe.layers = [layer]
	return SfxSynth.synthesize(recipe, 0, 1)


## Тон постоянной частоты, длина лупа выровнена на целое число периодов —
## иначе на стыке слышен щелчок (тот же приём, что и в EngineSynth).
static func _tone_loop(freq: float) -> AudioStreamWAV:
	var period := 1.0 / maxf(freq, 1.0)
	var loops_n := maxi(1, int(round(LEN_SHORT / period)))
	var dur := period * loops_n
	var recipe := SfxRecipe.new()
	recipe.looping = true
	recipe.duration = dur
	var layer := SfxRecipeLayer.new()
	layer.wave = SfxRecipe.Wave.SINE
	layer.freq_start = freq
	layer.freq_end = freq
	layer.duration = dur
	layer.attack = 0.0
	layer.decay = 0.0
	layer.sustain = 1.0
	layer.release = 0.0
	layer.gain = 1.0
	recipe.layers = [layer]
	return SfxSynth.synthesize(recipe, 0, 1)


## Дребезг от урона: квадратная несущая 62Гц, амплитудно-модулированная
## синус-LFO 8.5Гц, дальше bandpass 900Гц Q3 (audioloops.js:186-219).
## AM — поэлементное перемножение, additive-микс SfxSynth его не выражает,
## поэтому буферы несущей и LFO сводятся вручную до упаковки в WAV.
static func _rattle_loop() -> AudioStreamWAV:
	const CARRIER_HZ := 62.0
	const LFO_HZ := 8.5
	var period := 1.0 / CARRIER_HZ
	var cycles := maxi(1, int(round(LEN_SHORT * CARRIER_HZ)))
	var dur := period * cycles
	# Длительность также должна укладывать целое число периодов LFO, иначе
	# модуляция обрывается на стыке слышимым щелчком громкости.
	var lfo_cycles := maxi(1, int(round(dur * LFO_HZ)))
	dur = lfo_cycles / LFO_HZ

	var carrier := _flat_layer(SfxRecipe.Wave.SQUARE, CARRIER_HZ, dur, SfxRecipe.Filter.BANDPASS, 900.0, 3.0)
	var lfo := _flat_layer(SfxRecipe.Wave.SINE, LFO_HZ, dur, SfxRecipe.Filter.NONE, 0.0, 0.0)
	var carrier_buf := SfxSynth.render(_single(carrier, dur), 0, 1)
	var lfo_buf := SfxSynth.render(_single(lfo, dur), 0, 1)

	var out := PackedFloat32Array()
	out.resize(carrier_buf.size())
	for i in out.size():
		out[i] = carrier_buf[i] * (0.5 + 0.5 * lfo_buf[i])
	return SfxSynth.pack_samples(out, 1.0, true)


static func _flat_layer(wave: int, freq: float, dur: float, filter: int, cutoff: float, q: float) -> SfxRecipeLayer:
	var l := SfxRecipeLayer.new()
	l.wave = wave
	l.freq_start = freq
	l.freq_end = freq
	l.duration = dur
	l.attack = 0.0
	l.decay = 0.0
	l.sustain = 1.0
	l.release = 0.0
	l.gain = 1.0
	l.filter = filter
	l.cutoff_start = cutoff
	l.cutoff_end = cutoff
	l.resonance = maxf(q, 0.1)
	return l


static func _single(layer: SfxRecipeLayer, dur: float) -> SfxRecipe:
	var r := SfxRecipe.new()
	r.duration = dur
	r.layers = [layer]
	return r
