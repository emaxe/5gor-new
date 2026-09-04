extends GdUnitTestSuite
## Достижения (этап 16): AchievementTracker сверяет Db.achievements с
## Game.all_stats() и разово эмитит Bus.achievement_unlocked.

const AchievementTrackerScript = preload("res://gameplay/achievements/achievement_tracker.gd")

var _prev_lifetime: Dictionary
var _prev_shift: Dictionary
var _prev_unlocked: Array[StringName]
var _prev_money: int
var _prev_rating: float
var _received: Array[StringName] = []
var _listener: Callable


## Game — общий автозагрузчик на весь прогон тестов (см. test_garage.gd):
## без сохранения/отката lifetime_stats/shift_stats/achievements следующие
## сьюты унаследуют чужие разблокировки.
func before_test() -> void:
	_prev_lifetime = Game.lifetime_stats.duplicate()
	_prev_shift = Game.shift_stats.duplicate()
	_prev_unlocked = Game.achievements.unlocked.duplicate()
	_prev_money = Game.money
	_prev_rating = Game.rating
	Game.reset_lifetime()
	Game.reset_shift()
	Game.achievements.unlocked.clear()

	_received.clear()
	_listener = func(id: StringName) -> void: _received.append(id)
	Bus.achievement_unlocked.connect(_listener)


func after_test() -> void:
	Bus.achievement_unlocked.disconnect(_listener)
	Game.achievements.unlocked = _prev_unlocked
	Game.lifetime_stats = _prev_lifetime
	Game.shift_stats = _prev_shift
	Game.set_money(_prev_money)
	Game.set_rating(_prev_rating)


func test_unlocks_and_emits_on_first_matching_stat() -> void:
	Game.bump("orders", "total_orders", 1.0)
	assert_that(_received).contains(&"first_order")
	assert_that(Game.achievements.is_unlocked(&"first_order")).is_true()


func test_does_not_reemit_already_unlocked_achievement() -> void:
	Game.bump("orders", "total_orders", 1.0)
	_received.clear()

	Game.bump("orders", "total_orders", 1.0) # total_orders=2, first_order уже разблокировано
	assert_that(_received).is_empty()


func test_compound_achievement_requires_all_conditions() -> void:
	# clean_shift: shift_orders>=5 И shift_crashes<=0 И shift_peds<=0.
	for i in 5:
		Game.bump("orders", "total_orders", 1.0)
	assert_that(_received).contains(&"clean_shift")


func test_compound_achievement_blocked_by_any_failing_condition() -> void:
	Game.bump("crashes", "total_crashes", 1.0)
	for i in 5:
		Game.bump("orders", "total_orders", 1.0)
	assert_that(Game.achievements.is_unlocked(&"clean_shift")).is_false()


func test_rating_achievement_via_add_rating() -> void:
	Game.set_rating(100.0)
	assert_that(_received).contains(&"max_rating")


func test_tracker_check_unlocks_is_idempotent() -> void:
	var tracker := AchievementTrackerScript.new()
	Game.lifetime_stats["total_orders"] = 1

	tracker.check_unlocks()
	tracker.check_unlocks()

	var count := 0
	for id in tracker.unlocked:
		if id == &"first_order":
			count += 1
	assert_int(count).is_equal(1)
