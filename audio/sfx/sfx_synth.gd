class_name SfxSynth
extends RefCounted
## Синтез SfxRecipe -> AudioStreamWAV. Порт tone()/noiseBurst() (audiocore.js):
## там AudioParam-автоматизация в реальном времени, здесь та же огибающая/свип
## частоты/фильтр разворачиваются в буфер сэмплов один раз при запекании.
##
## Детерминировано: шум генерируется RandomNumberGenerator, засеянным хэшем
## id рецепта + индексов слоя/варианта — один и тот же рецепт всегда даёт
## побитово одинаковый WAV (нужно для теста детерминизма).

const SAMPLE_RATE := 44100


## Состояние резонансного SVF-фильтра (Chamberlin) — создаётся заново на
## каждый рендер слоя, никогда не хранится на Resource (SfxRecipeLayer
## read-only и переиспользуется между вызовами, см. правило проекта).
class _Svf extends RefCounted:
	var low := 0.0
	var band := 0.0
	var high := 0.0

	func step(input: float, cutoff_hz: float, q: float) -> void:
		var f := clampf(2.0 * sin(PI * cutoff_hz / SAMPLE_RATE), 0.0, 1.0)
		var q_inv := 1.0 / maxf(q, 0.1)
		low += f * band
		high = input - low - q_inv * band
		band += f * high


## Запекает один вариант рецепта. variant_count/variant_index задают детюн
## по SfxRecipe.variant_pitch_spread (см. _variant_pitch_mult).
static func synthesize(recipe: SfxRecipe, variant_index: int, variant_count: int) -> AudioStreamWAV:
	var mix := render(recipe, variant_index, variant_count)
	return pack_samples(mix, recipe.gain, recipe.looping)


## Сводит слои рецепта в сырые float-сэмплы без упаковки в WAV — нужно
## отдельным потребителям (например LoopSynth), которым требуется
## пост-обработка (амплитудная модуляция) до упаковки.
static func render(recipe: SfxRecipe, variant_index: int, variant_count: int) -> PackedFloat32Array:
	var pitch_mult := _variant_pitch_mult(recipe, variant_index, variant_count)
	var total_dur := recipe.duration
	for layer: SfxRecipeLayer in recipe.layers:
		total_dur = maxf(total_dur, layer.start_offset + layer.duration)
	var n := maxi(1, int(ceil(total_dur * SAMPLE_RATE)))
	var mix := PackedFloat32Array()
	mix.resize(n)

	for li in recipe.layers.size():
		_render_layer(mix, recipe.layers[li], recipe.id, li, variant_index, pitch_mult)
	return mix


static func _variant_pitch_mult(recipe: SfxRecipe, variant_index: int, variant_count: int) -> float:
	if variant_count <= 1:
		return 1.0
	var frac: float = float(variant_index) / float(variant_count - 1) - 0.5
	var semitones := frac * recipe.variant_pitch_spread
	return pow(2.0, semitones / 12.0)


static func _render_layer(mix: PackedFloat32Array, layer: SfxRecipeLayer, recipe_id: StringName,
		layer_index: int, variant_index: int, pitch_mult: float) -> void:
	var start_sample := int(round(layer.start_offset * SAMPLE_RATE))
	var n_layer := maxi(1, int(ceil(layer.duration * SAMPLE_RATE)))
	var wave: int = layer.wave
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d|%d" % [String(recipe_id), layer_index, variant_index])
	var svf := _Svf.new() if layer.filter != SfxRecipe.Filter.NONE else null

	var phase := 0.0
	for i in n_layer:
		var t := float(i) / SAMPLE_RATE
		var p := clampf(t / maxf(layer.duration, 0.0001), 0.0, 1.0)
		var env := _envelope(t, layer.attack, layer.decay, layer.sustain, layer.release, layer.duration)
		var sample := 0.0
		if wave == SfxRecipe.Wave.NOISE:
			sample = rng.randf_range(-1.0, 1.0)
		else:
			var f0 := layer.freq_start * pitch_mult
			var f1 := layer.freq_end * pitch_mult
			var freq := _sweep(f0, f1, p, layer.freq_exponential)
			phase += freq / SAMPLE_RATE
			sample = _oscillate(wave, phase)
		if svf != null:
			var cutoff := lerpf(layer.cutoff_start, layer.cutoff_end, p)
			svf.step(sample, cutoff, layer.resonance)
			sample = svf.low if layer.filter == SfxRecipe.Filter.LOWPASS \
				else (svf.high if layer.filter == SfxRecipe.Filter.HIGHPASS else svf.band)
		var idx := start_sample + i
		if idx >= 0 and idx < mix.size():
			mix[idx] += sample * env * layer.gain


static func _sweep(f0: float, f1: float, p: float, exponential: bool) -> float:
	if exponential and f0 > 0.0 and f1 > 0.0:
		return f0 * pow(f1 / f0, p)
	return lerpf(f0, f1, p)


static func _oscillate(wave: int, phase: float) -> float:
	var ph := fposmod(phase, 1.0)
	match wave:
		SfxRecipe.Wave.SINE:
			return sin(TAU * ph)
		SfxRecipe.Wave.SAW:
			return 2.0 * ph - 1.0
		SfxRecipe.Wave.SQUARE:
			return 1.0 if ph < 0.5 else -1.0
		SfxRecipe.Wave.TRIANGLE:
			return 4.0 * absf(ph - 0.5) - 1.0
		_:
			return 0.0


## Порт упрощённой огибающей tone()/noiseBurst(): атака линейная, декей и
## релиз — экспоненциальный ramp (WebAudio exponentialRampToValueAtTime),
## sustain — плато между ними (у большинства портированных эффектов = 0).
static func _envelope(t: float, attack: float, decay: float, sustain: float,
		release: float, total: float) -> float:
	if t < attack:
		return t / maxf(attack, 0.0001)
	var decay_end := attack + decay
	if t < decay_end:
		var p: float = (t - attack) / maxf(decay, 0.0001)
		return _exp_ramp(1.0, sustain, p)
	var release_start := maxf(decay_end, total - release)
	if t < release_start:
		return sustain
	if t < total:
		var p: float = (t - release_start) / maxf(total - release_start, 0.0001)
		return _exp_ramp(sustain, 0.0, p)
	return 0.0


static func _exp_ramp(a: float, b: float, p: float) -> float:
	var aa := maxf(a, 0.0001)
	var bb := maxf(b, 0.0001)
	return aa * pow(bb / aa, p)


static func pack_samples(mix: PackedFloat32Array, gain: float, looping: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(mix.size() * 2)
	for i in mix.size():
		var v := clampf(mix[i] * gain, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(round(v * 32767.0)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = mix.size()
	return stream
