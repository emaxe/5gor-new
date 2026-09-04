extends GdUnitTestSuite
## Юнит-тесты гаража (этап 15, MVP): покупка/переключение машин, апгрейды.

const GarageScript = preload("res://gameplay/economy/garage.gd")

var _garage: RefCounted
var _prev_money: int
var _prev_rating: float


func before_test() -> void:
	_garage = GarageScript.new()
	_prev_money = Game.money
	_prev_rating = Game.rating
	Game.set_money(100000)
	Game.set_rating(100.0)


## Game — общий автозагрузчик на весь прогон тестов: без отката rating/money
## следующие сьюты (например, спавн заказов по рейтингу) наследуют чужие
## значения. Поймано на _pick_random_landmark в order_manager.gd.
func after_test() -> void:
	Game.set_money(_prev_money)
	Game.set_rating(_prev_rating)


func test_starts_with_taxi_owned_and_active() -> void:
	assert_that(_garage.owns(&"taxi")).is_true()
	assert_that(_garage.active_car_id).is_equal(&"taxi")


func test_buy_car_spends_money_and_grants_ownership() -> void:
	var before := Game.money
	assert_that(_garage.buy_car(&"classic")).is_true()
	assert_that(_garage.owns(&"classic")).is_true()
	assert_that(Game.money).is_equal(before - 3500)


func test_buy_car_twice_does_not_charge_again() -> void:
	_garage.buy_car(&"classic")
	var after_first := Game.money
	assert_that(_garage.buy_car(&"classic")).is_false()
	assert_that(Game.money).is_equal(after_first)


func test_buy_car_fails_without_enough_rating() -> void:
	Game.set_rating(10.0)
	var before := Game.money
	assert_that(_garage.buy_car(&"business")).is_false()
	assert_that(_garage.owns(&"business")).is_false()
	assert_that(Game.money).is_equal(before)


func test_buy_car_fails_without_enough_money() -> void:
	Game.set_money(100)
	assert_that(_garage.buy_car(&"classic")).is_false()
	assert_that(_garage.owns(&"classic")).is_false()


func test_set_active_requires_ownership() -> void:
	assert_that(_garage.set_active(&"classic")).is_false()
	assert_that(_garage.active_car_id).is_equal(&"taxi")

	_garage.buy_car(&"classic")
	assert_that(_garage.set_active(&"classic")).is_true()
	assert_that(_garage.active_car_id).is_equal(&"classic")


func test_buy_upgrade_increments_level_and_spends_scaled_cost() -> void:
	var before := Game.money
	assert_that(_garage.upgrade_level(&"taxi", &"engine")).is_equal(0)

	assert_that(_garage.buy_upgrade(&"taxi", &"engine")).is_true()
	assert_that(_garage.upgrade_level(&"taxi", &"engine")).is_equal(1)
	assert_that(Game.money).is_less(before)


func test_buy_upgrade_stops_at_max_level() -> void:
	var upgrade: UpgradeData = Db.upgrades.get_upgrade(&"capacity")
	for i in upgrade.max_level:
		assert_that(_garage.buy_upgrade(&"taxi", &"capacity")).is_true()
	assert_that(_garage.upgrade_level(&"taxi", &"capacity")).is_equal(upgrade.max_level)
	assert_that(_garage.buy_upgrade(&"taxi", &"capacity")).is_false()


func test_upgrade_levels_are_independent_per_car() -> void:
	_garage.buy_car(&"classic")
	_garage.buy_upgrade(&"taxi", &"engine")

	assert_that(_garage.upgrade_level(&"taxi", &"engine")).is_equal(1)
	assert_that(_garage.upgrade_level(&"classic", &"engine")).is_equal(0)
