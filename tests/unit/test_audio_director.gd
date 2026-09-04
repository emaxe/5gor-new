extends GdUnitTestSuite
## Юнит-тест 3D-пула AudioDirector: проверяет API play_sfx_3d(), пул не
## превышает лимита, бюджеты/кулдауны работают как для 2D-варианта, а
## координата корректно ставится на носитель.

const AudioScript = preload("res://autoload/audio_director.gd")


func before_test() -> void:
	# VoiceAllocator живёт внутри Audio как var _alloc — приватное поле
	# из теста напрямую не сбросить. Но мы можем заставить аллокатор
	# забыть кулдауны, вызвав release по всем тегам, что использовались в
	# предыдущем тесте. Делаем это через reflection... или проще: ждём,
	# пока cooldown не истечёт (140 мс для horn). Между тестами в gdUnit4
	# проходит достаточно времени, но не гарантированно. Поэтому
	# тестируем с SFX, у которых cooldown короткий (thud = 90 мс) или
	# тестируем только API play_sfx_3d, не пул под нагрузкой.
	pass


func test_play_sfx_3d_returns_true_for_known_id() -> void:
	var ok := Audio.play_sfx_3d(&"horn_truck", Vector3(10, 0, 20))
	assert_that(ok).is_true()


func test_play_sfx_3d_returns_false_for_unknown_id() -> void:
	var ok := Audio.play_sfx_3d(&"does_not_exist", Vector3.ZERO)
	assert_that(ok).is_false()


func test_3d_pool_does_not_exceed_size_under_load() -> void:
	# Ждём, пока cooldown horn (140 мс) истечёт после предыдущего теста —
	# иначе allocator сразу отказывает всем вызовам.
	await get_tree().create_timer(0.2).timeout
	var successes := 0
	for i in 100:
		if Audio.play_sfx_3d(&"horn_truck", Vector3(float(i), 0, 0)):
			successes += 1
	# Бюджет horn = 3 одновременных — больше трёх не пройдёт, плюс
	# cooldown = 140 мс и тики тестов идут быстрее, чем он истекает. Поэтому
	# ровно 3 (или меньше, если cooldown «съел» предыдущие).
	assert_that(successes).is_less_equal(3)
	assert_that(successes).is_greater_equal(1)


func test_play_sfx_3d_sets_position_on_player() -> void:
	# play_sfx_3d в первой итерации возьмёт первый свободный 3D-голос
	# из пула; у нового носителя позиция совпадает с переданной.
	var target_pos := Vector3(123.5, 1.0, -42.0)
	Audio.play_sfx_3d(&"crash_light", target_pos)
	# Пусть finished сразу не вызовется — ищем в пуле активный voice
	# с этой позицией (тест хрупкий к состоянию пула, но Audio мы
	# контролируем из теста, поэтому допустимо).
	var found := false
	for v in Audio._pool_3d:
		if v.in_use and v.player.global_position.is_equal_approx(target_pos):
			found = true
			break
	assert_that(found).is_true()