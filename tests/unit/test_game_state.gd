extends GdUnitTestSuite
## Точечные тесты автолоада GameState, не покрытые другими сьютами.

func before_test() -> void:
	Game.reset_shift()


func test_track_shift_max_keeps_the_larger_value() -> void:
	Game.shift_stats["best_combo"] = 0
	Game.track_shift_max("best_combo", 3.0)
	Game.track_shift_max("best_combo", 1.0)
	Game.track_shift_max("best_combo", 5.0)
	assert_that(Game.shift_stats["best_combo"]).is_equal(5)
