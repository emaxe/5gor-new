extends GdUnitTestSuite
## GPS-навигатор — порт game.js:1416-1470 (выбор цели) и ui.js:410-420
## (стрелка). Пересчёт троттлится: RECOMPUTE_INTERVAL секунд накопленного
## delta должны пройти прежде, чем маршрут вообще появится.

var _field: CityField
var _router: GpsRouter

## Совпадает с GpsRouter.RECOMPUTE_INTERVAL — порог накопления перед
## пересчётом маршрута.
const INTERVAL := 0.5


func before() -> void:
	_field = CityField.new(Db.balance)
	_router = GpsRouter.new(_field, Db.districts, Db.balance)


func test_no_target_without_order_and_with_fuel() -> void:
	_router.update(INTERVAL, Vector2.ZERO, true, false, Vector2.ZERO, 0.9)
	assert_bool(_router.has_target()).is_false()
	assert_str(String(_router.target_type)).is_equal("")


func test_recompute_is_throttled_until_interval_elapses() -> void:
	# Заказ есть с первого тика, но накопленного времени ещё не хватает —
	# маршрут не должен появиться раньше срока.
	_router.update(INTERVAL * 0.6, Vector2.ZERO, true, true, Vector2(100.0, 0.0), 0.9)
	assert_bool(_router.has_target()).is_false()
	# Второй тик добирает накопленное время до порога (0.6 + 0.6 = 1.2 x INTERVAL).
	_router.update(INTERVAL * 0.6, Vector2.ZERO, true, true, Vector2(100.0, 0.0), 0.9)
	assert_bool(_router.has_target()).is_true()


func test_active_order_takes_priority_over_low_fuel() -> void:
	var drop := Vector2(100.0, 0.0)
	_router.update(INTERVAL, Vector2.ZERO, true, true, drop, 0.05)
	assert_str(String(_router.target_type)).is_equal("order")
	assert_vector(_router.final_target()).is_equal(drop)


func test_low_fuel_routes_to_nearest_station_when_no_order() -> void:
	# fuel_stations (district_catalog.tres): (0,128), (-192,-64), (128,-192),
	# (64,192) — ближайшая к (5,120) это (0,128).
	_router.update(INTERVAL, Vector2(5.0, 120.0), true, false, Vector2.ZERO, 0.1)
	assert_str(String(_router.target_type)).is_equal("fuel")
	assert_vector(_router.final_target()).is_equal(Vector2(0.0, 128.0))


func test_fuel_nav_disabled_while_walking() -> void:
	# Пешком к заправке не ведём — порт game.js:1764-1785 (только activeDrop).
	_router.update(INTERVAL, Vector2(5.0, 120.0), false, false, Vector2.ZERO, 0.1)
	assert_bool(_router.has_target()).is_false()


func test_fuel_target_has_hysteresis_before_clearing() -> void:
	_router.update(INTERVAL, Vector2(5.0, 120.0), true, false, Vector2.ZERO, 0.1)
	assert_str(String(_router.target_type)).is_equal("fuel")
	# low_fuel_ratio (Db.balance) = 0.25: чуть выше порога, но ещё в зоне
	# гистерезиса (+0.05) — маршрут должен держаться.
	var above_threshold: float = Db.balance.low_fuel_ratio + 0.02
	_router.update(INTERVAL, Vector2(5.0, 120.0), true, false, Vector2.ZERO, above_threshold)
	assert_str(String(_router.target_type)).is_equal("fuel")
	# Выше верхней границы гистерезиса — маршрут наконец снимается.
	var past_hysteresis: float = Db.balance.low_fuel_ratio + 0.10
	_router.update(INTERVAL, Vector2(5.0, 120.0), true, false, Vector2.ZERO, past_hysteresis)
	assert_bool(_router.has_target()).is_false()


func test_reset_clears_route() -> void:
	_router.update(INTERVAL, Vector2.ZERO, true, true, Vector2(100.0, 0.0), 0.9)
	assert_bool(_router.has_target()).is_true()
	_router.reset()
	assert_bool(_router.has_target()).is_false()
	assert_int(_router.route.size()).is_equal(0)


func test_next_waypoint_is_second_route_point_not_final_target() -> void:
	_router.update(INTERVAL, Vector2(-256.0, -256.0), true, true, Vector2(-64.0, -256.0), 0.9)
	assert_int(_router.route.size()).is_greater(2)
	assert_vector(_router.next_waypoint()).is_equal(_router.route[1])
	assert_bool(_router.next_waypoint() != _router.final_target()).is_true()


func test_arrow_angle_points_forward_for_target_straight_ahead() -> void:
	# Конвенция курса Heading: 0 = +Z. Порт ui.js:410-420 — «вперёд» = -90°
	# (глиф в нейтральной позе смотрит вправо на экране).
	var ang := GpsRouter.arrow_angle(Vector2.ZERO, 0.0, Vector2(0.0, 10.0))
	assert_float(ang).is_equal_approx(-PI / 2.0, 1e-4)


func test_arrow_angle_points_backward_for_target_behind() -> void:
	var ang := GpsRouter.arrow_angle(Vector2.ZERO, 0.0, Vector2(0.0, -10.0))
	assert_float(ang).is_equal_approx(PI / 2.0, 1e-4)
