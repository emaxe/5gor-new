extends GdUnitTestSuite
## Логика ротации тостов HUD: не больше max_size одновременно, при
## переполнении вытесняется самый старый.

const ToastQueueScript = preload("res://ui/hud/toast_queue.gd")


func test_push_below_capacity_does_not_evict() -> void:
	var q = ToastQueueScript.new(3)

	var r1: Array = q.push()
	var r2: Array = q.push()
	var r3: Array = q.push()

	assert_that(r1[1]).is_equal(-1)
	assert_that(r2[1]).is_equal(-1)
	assert_that(r3[1]).is_equal(-1)
	assert_that(q.size()).is_equal(3)


func test_push_over_capacity_evicts_oldest() -> void:
	var q = ToastQueueScript.new(3)

	var first: Array = q.push()
	q.push()
	q.push()
	var fourth: Array = q.push()

	assert_that(fourth[1]).is_equal(first[0])
	assert_that(q.size()).is_equal(3)


func test_remove_frees_capacity_for_next_push() -> void:
	var q = ToastQueueScript.new(2)

	var a: Array = q.push()
	q.push()
	q.remove(a[0])
	var c: Array = q.push()

	assert_that(c[1]).is_equal(-1)
	assert_that(q.size()).is_equal(2)


func test_ids_are_unique_and_increasing() -> void:
	var q = ToastQueueScript.new(5)

	var a: Array = q.push()
	var b: Array = q.push()

	assert_that(b[0]).is_greater(a[0])


## Ранги: 0 = награда, 1 = инфо (по умолчанию), 2 = критическое —
## см. HudStyle.level_rank().

func test_reward_does_not_evict_three_criticals() -> void:
	var q = ToastQueueScript.new(3)
	q.push(2)
	q.push(2)
	q.push(2)

	var result: Array = q.push(0)

	assert_that(result[0]).is_equal(-1)
	assert_that(result[1]).is_equal(-1)
	assert_that(q.size()).is_equal(3)


func test_critical_evicts_oldest_of_lowest_present_rank() -> void:
	var q = ToastQueueScript.new(3)
	var first_reward: Array = q.push(0)
	q.push(0)
	q.push(1)

	var result: Array = q.push(2)

	assert_that(result[1]).is_equal(first_reward[0])
	assert_that(q.size()).is_equal(3)


func test_equal_rank_evicts_oldest_same_as_before() -> void:
	var q = ToastQueueScript.new(3)
	var first: Array = q.push(1)
	q.push(1)
	q.push(1)

	var result: Array = q.push(1)

	assert_that(result[1]).is_equal(first[0])
	assert_that(q.size()).is_equal(3)
