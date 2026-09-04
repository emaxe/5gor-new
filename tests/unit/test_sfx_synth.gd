extends GdUnitTestSuite
## Синтез SFX (audio/sfx/sfx_synth.gd) — детерминизм, длительность, отсутствие
## клиппинга. Порт tone()/noiseBurst() (audiosfx.js): числовая сверка с
## оригиналом здесь — это проверка формы огибающей/свипа, а не точных чисел
## аудиосэмплов (тех в оригинале не существует, там процедурный граф узлов).

const EPS := 1e-6


## 16 бит = 2 байта на сэмпл — деление всегда точное (data.size() чётный).
func _sample_count(wav: AudioStreamWAV) -> int:
	@warning_ignore("integer_division")
	return wav.data.size() / 2


func _one_layer_recipe(id: StringName, wave: int) -> SfxRecipe:
	var l := SfxRecipeLayer.new()
	l.wave = wave
	l.freq_start = 440.0
	l.freq_end = 220.0
	l.duration = 0.2
	l.attack = 0.01
	l.decay = 0.18
	l.sustain = 0.0
	l.release = 0.01
	l.gain = 0.5
	var r := SfxRecipe.new()
	r.id = id
	r.duration = 0.2
	r.layers = [l]
	return r


func test_synthesis_is_deterministic() -> void:
	var r := _one_layer_recipe(&"test_tone", SfxRecipe.Wave.SINE)
	var a := SfxSynth.synthesize(r, 0, 1)
	var b := SfxSynth.synthesize(r, 0, 1)
	assert_that(a.data).is_equal(b.data)


func test_noise_layer_is_deterministic_per_recipe_id() -> void:
	var r1 := _one_layer_recipe(&"noise_a", SfxRecipe.Wave.NOISE)
	var r2 := _one_layer_recipe(&"noise_a", SfxRecipe.Wave.NOISE)
	var a := SfxSynth.synthesize(r1, 0, 1)
	var b := SfxSynth.synthesize(r2, 0, 1)
	assert_that(a.data).is_equal(b.data)


func test_different_recipe_id_gives_different_noise() -> void:
	var r1 := _one_layer_recipe(&"noise_x", SfxRecipe.Wave.NOISE)
	var r2 := _one_layer_recipe(&"noise_y", SfxRecipe.Wave.NOISE)
	var a := SfxSynth.synthesize(r1, 0, 1)
	var b := SfxSynth.synthesize(r2, 0, 1)
	assert_that(a.data).is_not_equal(b.data)


func test_duration_matches_sample_rate() -> void:
	var r := _one_layer_recipe(&"dur_test", SfxRecipe.Wave.SINE)
	var wav := SfxSynth.synthesize(r, 0, 1)
	var expected_samples := int(ceil(0.2 * SfxSynth.SAMPLE_RATE))
	var actual_samples := _sample_count(wav)
	assert_int(actual_samples).is_equal(expected_samples)
	assert_int(wav.mix_rate).is_equal(SfxSynth.SAMPLE_RATE)


func test_multi_layer_extends_total_duration() -> void:
	var early := SfxRecipeLayer.new()
	early.wave = SfxRecipe.Wave.SINE
	early.freq_start = 300.0
	early.freq_end = 300.0
	early.duration = 0.1
	early.attack = 0.01
	early.decay = 0.09
	early.gain = 0.3

	var late := SfxRecipeLayer.new()
	late.wave = SfxRecipe.Wave.SINE
	late.freq_start = 500.0
	late.freq_end = 500.0
	late.duration = 0.1
	late.start_offset = 0.5
	late.attack = 0.01
	late.decay = 0.09
	late.gain = 0.3

	var r := SfxRecipe.new()
	r.id = &"multi"
	r.duration = 0.1
	r.layers = [early, late]

	var wav := SfxSynth.synthesize(r, 0, 1)
	# Второй слой начинается на 0.5с и длится 0.1с -> общая длина 0.6с,
	# а не 0.1с из recipe.duration (тот описывает только «объявленную» длину).
	var expected_samples := int(ceil(0.6 * SfxSynth.SAMPLE_RATE))
	var actual_samples := _sample_count(wav)
	assert_int(actual_samples).is_equal(expected_samples)


func test_output_never_clips_16_bit_range() -> void:
	# Три слоя суммируются в один и тот же участок буфера — суммарный gain
	# 0.9 (0.3 на слой), проверяем, что упаковка не переполняет int16.
	var layers: Array[SfxRecipeLayer] = []
	for i in 3:
		var l := SfxRecipeLayer.new()
		l.wave = SfxRecipe.Wave.SINE
		l.freq_start = 200.0 + i * 50.0
		l.freq_end = 200.0 + i * 50.0
		l.duration = 0.1
		l.attack = 0.0
		l.decay = 0.0
		l.sustain = 1.0
		l.release = 0.0
		l.gain = 0.9
		layers.append(l)
	var r := SfxRecipe.new()
	r.id = &"loud"
	r.duration = 0.1
	r.layers = layers
	r.gain = 1.0

	var wav := SfxSynth.synthesize(r, 0, 1)
	for i in _sample_count(wav):
		var s := wav.data.decode_s16(i * 2)
		assert_int(s).is_greater_equal(-32768)
		assert_int(s).is_less_equal(32767)


func test_looping_stream_sets_loop_points() -> void:
	var l := SfxRecipeLayer.new()
	l.wave = SfxRecipe.Wave.SINE
	l.freq_start = 100.0
	l.freq_end = 100.0
	l.duration = 0.05
	l.attack = 0.0
	l.decay = 0.0
	l.sustain = 1.0
	l.release = 0.0
	l.gain = 0.5
	var r := SfxRecipe.new()
	r.id = &"loop_test"
	r.duration = 0.05
	r.looping = true
	r.layers = [l]

	var wav := SfxSynth.synthesize(r, 0, 1)
	assert_int(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(wav.loop_end).is_equal(_sample_count(wav))


func test_variant_pitch_spread_shifts_frequency() -> void:
	var l := SfxRecipeLayer.new()
	l.wave = SfxRecipe.Wave.SINE
	l.freq_start = 440.0
	l.freq_end = 440.0
	l.duration = 0.05
	l.attack = 0.0
	l.decay = 0.0
	l.sustain = 1.0
	l.release = 0.0
	l.gain = 0.8
	var r := SfxRecipe.new()
	r.id = &"variant_test"
	r.duration = 0.05
	r.layers = [l]
	r.variants = 3
	r.variant_pitch_spread = 12.0 # целая октава между крайними вариантами

	var low := SfxSynth.synthesize(r, 0, 3)
	var high := SfxSynth.synthesize(r, 2, 3)
	# Октава выше -> вдвое короче период -> примерно вдвое больше пересечений нуля.
	var zc_low := _zero_crossings(low)
	var zc_high := _zero_crossings(high)
	assert_float(float(zc_high) / float(zc_low)).is_between(1.7, 2.3)


func _zero_crossings(wav: AudioStreamWAV) -> int:
	var n := _sample_count(wav)
	var count := 0
	var prev := wav.data.decode_s16(0)
	for i in range(1, n):
		var cur := wav.data.decode_s16(i * 2)
		if (prev < 0 and cur >= 0) or (prev >= 0 and cur < 0):
			count += 1
		prev = cur
	return count
