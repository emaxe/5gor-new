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
