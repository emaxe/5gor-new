class_name InstrumentSynth
extends RefCounted
## Банк одноразовых сэмплов инструментов станции. Порт инструментального банка
## Tone.js (audiomusic.js:439-496) — там на каждую ноту создаётся новый синт,
## здесь один сэмпл на инструмент запекается один раз при первом включении
## станции, а конкретная нота получается `pitch_scale` в рантайме
## (RadioSequencer) относительно REFERENCE_HZ.
##
## Барабаны (kick/snare/clap/hat) высоту не меняют — играются как есть.

## Опорная частота, относительно которой считается pitch_scale бас/лид/пэда.
const REFERENCE_HZ := 110.0


## Синтезирует полный банк по списку инструментов станции (RadioStationData
## .instruments). Не кэшируется на диск — из ~7 коротких сэмплов, а спецификация
## требует кэш диска только для одноразовых SFX (план, «Аудио — уточнения»).
static func bake_bank(instruments: PackedStringArray) -> Dictionary:
	var bank: Dictionary[StringName, AudioStreamWAV] = {}
	for name: String in instruments:
		match name:
			"kick":
				bank[&"kick"] = _kick()
			"snare":
				bank[&"snare"] = _snare()
			"clap":
				bank[&"clap"] = _clap()
			"hat":
				bank[&"hat_closed"] = _hat(false)
				bank[&"hat_open"] = _hat(true)
			"bass":
				bank[&"bass"] = _bass()
			"lead":
				bank[&"lead"] = _lead()
			"arp":
				bank[&"arp"] = _lead()
			"pad":
				bank[&"pad"] = _pad()
	return bank


static func _kick() -> AudioStreamWAV:
	var l := SfxRecipeLayer.new()
	l.wave = SfxRecipe.Wave.SINE
	l.freq_start = 150.0
	l.freq_end = 42.0
	l.duration = 0.14
	l.attack = 0.001
	l.decay = 0.13
	l.sustain = 0.0
	l.release = 0.01
	l.gain = 0.95
	return SfxSynth.synthesize(_one(l, 0.14), 0, 1)


static func _snare() -> AudioStreamWAV:
	var l := SfxRecipeLayer.new()
	l.wave = SfxRecipe.Wave.NOISE
	l.duration = 0.12
	l.attack = 0.001
	l.decay = 0.11
	l.sustain = 0.0
	l.release = 0.01
	l.gain = 0.55
	l.filter = SfxRecipe.Filter.BANDPASS
	l.cutoff_start = 1800.0
	l.cutoff_end = 1800.0
	l.resonance = 1.2
	return SfxSynth.synthesize(_one(l, 0.12), 0, 1)


static func _clap() -> AudioStreamWAV:
	var a := SfxRecipeLayer.new()
	a.wave = SfxRecipe.Wave.NOISE
	a.duration = 0.08
	a.attack = 0.001
	a.decay = 0.07
	a.sustain = 0.0
	a.release = 0.01
	a.gain = 0.4
	a.filter = SfxRecipe.Filter.BANDPASS
	a.cutoff_start = 1500.0
	a.cutoff_end = 1500.0
	a.resonance = 1.5

	var b := SfxRecipeLayer.new()
	b.wave = SfxRecipe.Wave.NOISE
	b.start_offset = 0.015
	b.duration = 0.08
	b.attack = 0.001
	b.decay = 0.07
	b.sustain = 0.0
	b.release = 0.01
	b.gain = 0.4
	b.filter = SfxRecipe.Filter.BANDPASS
	b.cutoff_start = 1500.0
	b.cutoff_end = 1500.0
	b.resonance = 1.5

	var recipe := SfxRecipe.new()
	recipe.duration = 0.1
	recipe.layers = [a, b]
	return SfxSynth.synthesize(recipe, 0, 1)


static func _hat(open: bool) -> AudioStreamWAV:
	var l := SfxRecipeLayer.new()
	l.wave = SfxRecipe.Wave.NOISE
	l.duration = 0.14 if open else 0.035
	l.attack = 0.001
	l.decay = l.duration - 0.005
	l.sustain = 0.0
	l.release = 0.005
	l.gain = 0.35 if open else 0.2
	l.filter = SfxRecipe.Filter.HIGHPASS
	l.cutoff_start = 6000.0 if open else 7000.0
	l.cutoff_end = l.cutoff_start
	l.resonance = 0.7
	return SfxSynth.synthesize(_one(l, l.duration), 0, 1)


## MonoSynth(saw) + filterEnv (audiomusic.js: bass). REFERENCE_HZ = нота 0
## полутонов — RadioSequencer ретюнит pitch_scale по ступени лада.
static func _bass() -> AudioStreamWAV:
	var l := SfxRecipeLayer.new()
	l.wave = SfxRecipe.Wave.SAW
	l.freq_start = REFERENCE_HZ
	l.freq_end = REFERENCE_HZ
	l.duration = 0.3
	l.attack = 0.005
	l.decay = 0.2
	l.sustain = 0.1
	l.release = 0.1
	l.gain = 0.7
	l.filter = SfxRecipe.Filter.LOWPASS
	l.cutoff_start = 550.0
	l.cutoff_end = 180.0
	l.resonance = 1.0
	return SfxSynth.synthesize(_one(l, 0.3), 0, 1)


## Synth(triangle) + FeedbackDelay (эхо не переносим — минорный штрих).
## Опорная нота на октаву выше REFERENCE_HZ — мелодический регистр.
static func _lead() -> AudioStreamWAV:
	var l := SfxRecipeLayer.new()
	l.wave = SfxRecipe.Wave.TRIANGLE
	l.freq_start = REFERENCE_HZ * 2.0
	l.freq_end = REFERENCE_HZ * 2.0
	l.duration = 0.3
	l.attack = 0.02
	l.decay = 0.15
	l.sustain = 0.0
	l.release = 0.05
	l.gain = 0.5
	return SfxSynth.synthesize(_one(l, 0.3), 0, 1)


## PolySynth(sine), volume -6dB (audiomusic.js: pad) — длинная сустейн-подушка.
static func _pad() -> AudioStreamWAV:
	var l := SfxRecipeLayer.new()
	l.wave = SfxRecipe.Wave.SINE
	l.freq_start = REFERENCE_HZ
	l.freq_end = REFERENCE_HZ
	l.duration = 2.0
	l.attack = 0.3
	l.decay = 0.2
	l.sustain = 0.6
	l.release = 0.5
	l.gain = 0.35
	return SfxSynth.synthesize(_one(l, 2.0), 0, 1)


static func _one(layer: SfxRecipeLayer, dur: float) -> SfxRecipe:
	var r := SfxRecipe.new()
	r.duration = dur
	r.layers = [layer]
	return r
