extends GdUnitTestSuite
## Порт mulberry32 обязан совпадать с JS побитово — иначе планировка города
## разойдётся с эталоном оригинала. Значения сняты запуском mulberry32
## из utils.js:252 в Node.js.

const REF_20260805 := [
	0.014530243119, 0.485228995560, 0.878767023096, 0.497210506117,
	0.158103644848, 0.619230722310, 0.926034719683, 0.248749567894,
	0.434734403854, 0.905496905325, 0.011840685736, 0.364754169015,
]

const REF_SEED_1 := [
	0.627073940588, 0.002735721180, 0.527447039960,
	0.981050967472, 0.968377898214, 0.281103502959,
]

const EPS := 1e-11


func test_matches_js_reference_world_seed() -> void:
	var rng := SeededRng.new(20260805)
	for i in REF_20260805.size():
		assert_float(rng.next()).is_equal_approx(REF_20260805[i], EPS)


func test_matches_js_reference_seed_one() -> void:
	var rng := SeededRng.new(1)
	for i in REF_SEED_1.size():
		assert_float(rng.next()).is_equal_approx(REF_SEED_1[i], EPS)


func test_output_range() -> void:
	var rng := SeededRng.new(42)
	for i in 5000:
		var v := rng.next()
		assert_float(v).is_between(0.0, 1.0)


func test_state_roundtrip_reproduces_sequence() -> void:
	var rng := SeededRng.new(777)
	for i in 10:
		rng.next()
	var state := rng.get_state()
	var expected: Array[float] = []
	for i in 5:
		expected.append(rng.next())

	var restored := SeededRng.new(0)
	restored.set_state(state)
	for i in 5:
		assert_float(restored.next()).is_equal(expected[i])


func test_same_seed_same_sequence() -> void:
	var a := SeededRng.new(20260805)
	var b := SeededRng.new(20260805)
	for i in 100:
		assert_float(a.next()).is_equal(b.next())


func test_fork_diverges_from_parent() -> void:
	var parent := SeededRng.new(20260805)
	var child := parent.fork(1)
	var other := parent.fork(2)
	# Форк не должен повторять родителя и не должен совпадать с другим форком —
	# иначе добавление объектов в одну фазу генерации сдвинет остальные.
	assert_float(child.next()).is_not_equal(parent.next())
	assert_float(child.next()).is_not_equal(other.next())


func test_randi_below_covers_range() -> void:
	var rng := SeededRng.new(5)
	var seen := {}
	for i in 2000:
		var v := rng.randi_below(6)
		assert_int(v).is_between(0, 5)
		seen[v] = true
	assert_int(seen.size()).is_equal(6)


func test_pick_weighted_respects_weights() -> void:
	var rng := SeededRng.new(9)
	var values: Array = ["a", "b"]
	var weights := PackedFloat32Array([9.0, 1.0])
	var count_a := 0
	for i in 4000:
		if rng.pick_weighted(values, weights) == "a":
			count_a += 1
	# Ожидание 90%; допускаем разброс выборки.
	assert_int(count_a).is_between(3400, 3800)
