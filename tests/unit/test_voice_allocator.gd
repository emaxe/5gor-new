extends GdUnitTestSuite
## Бюджет голосов и кулдауны (audio/core/voice_allocator.gd) — порт
## alloc()/free() (audiocore.js). budget_tag и cooldown_tag разделены нарочно:
## разные звуки могут делить один бюджет, но иметь разные кулдауны.


func test_budget_limits_concurrent_voices_of_same_tag() -> void:
	var a := VoiceAllocator.new()
	# horn budget = 3 — четвёртый одновременный гудок должен получить отказ.
	for i in 3:
		assert_bool(a.try_alloc(&"horn", &"", 0)).is_true()
	assert_bool(a.try_alloc(&"horn", &"", 0)).is_false()
	assert_int(a.voice_count(&"horn")).is_equal(3)


func test_release_frees_budget_slot() -> void:
	var a := VoiceAllocator.new()
	for i in 3:
		a.try_alloc(&"horn", &"", 0)
	a.release(&"horn")
	assert_bool(a.try_alloc(&"horn", &"", 0)).is_true()


func test_different_budget_tags_are_independent() -> void:
	var a := VoiceAllocator.new()
	for i in 3:
		a.try_alloc(&"horn", &"", 0)
	# crash budget = 2, отдельный от horn.
	assert_bool(a.try_alloc(&"crash", &"", 0)).is_true()
	assert_bool(a.try_alloc(&"crash", &"", 0)).is_true()
	assert_bool(a.try_alloc(&"crash", &"", 0)).is_false()


func test_ped_hit_and_thud_share_budget_but_not_cooldown() -> void:
	var a := VoiceAllocator.new()
	# ped budget = 3, ped_hit/thud делят его на двоих (audiocore.js:191-219).
	assert_bool(a.try_alloc(&"ped", &"ped_hit", 0)).is_true()
	assert_bool(a.try_alloc(&"ped", &"thud", 0)).is_true()
	assert_bool(a.try_alloc(&"ped", &"ped_hit", 1000)).is_true()
	assert_int(a.voice_count(&"ped")).is_equal(3)
	assert_bool(a.try_alloc(&"ped", &"thud", 1000)).is_false() # бюджет ped исчерпан


func test_cooldown_blocks_rapid_replay_of_same_tag() -> void:
	var a := VoiceAllocator.new()
	assert_bool(a.try_alloc(&"", &"click", 0)).is_true()
	a.release(&"")
	# click cooldown = 40мс — повтор через 20мс должен получить отказ.
	assert_bool(a.try_alloc(&"", &"click", 20)).is_false()
	assert_bool(a.try_alloc(&"", &"click", 41)).is_true()


func test_total_budget_caps_at_28_regardless_of_tag() -> void:
	var a := VoiceAllocator.new()
	var ok := 0
	# Без budget_tag ограничен только общий потолок TOTAL_BUDGET=28.
	for i in 40:
		if a.try_alloc(&"", &"", i * 1000):
			ok += 1
	assert_int(ok).is_equal(VoiceAllocator.TOTAL_BUDGET)


func test_empty_tags_are_unbounded_except_total() -> void:
	var a := VoiceAllocator.new()
	assert_bool(a.try_alloc(&"", &"", 0)).is_true()
	assert_int(a.voice_total()).is_equal(1)
