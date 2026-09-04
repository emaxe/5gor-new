extends GdUnitTestSuite
## Юнит-тесты системы заказов, пассажиров и экономики поездок (Этап 10).

const OrderScript = preload("res://gameplay/orders/order.gd")
const OrderManagerScript = preload("res://gameplay/orders/order_manager.gd")
const CityPlannerScript = preload("res://world/city/city_planner.gd")

var _catalog: OrderCatalog
var _field: CityField
var _plan: CityPlan
var _districts: DistrictCatalog
var _balance: BalanceData


func before_test() -> void:
	_catalog = Db.orders
	_districts = Db.districts
	_balance = Db.balance
	_field = CityField.new(_balance)
	var graph := PedGraph.new(_field)
	var planner = CityPlannerScript.new(_field, graph, _districts)
	_plan = planner.plan(_balance.world_seed)


func test_catalog_integrity() -> void:
	assert_that(_catalog).is_not_null()
	assert_that(_catalog.types.size()).is_equal(8)
	assert_that(_catalog.missions.size()).is_equal(5)

	var normal: OrderTypeData = _catalog.get_type(&"normal")
	assert_that(normal).is_not_null()
	assert_that(normal.pay_mult).is_equal_approx(1.0, 0.01)

	var urgent: OrderTypeData = _catalog.get_type(&"urgent")
	assert_that(urgent).is_not_null()
	assert_that(urgent.time_limit).is_equal_approx(75.0, 0.01)

	var grandma: MissionData = _catalog.get_mission(&"grandma")
	assert_that(grandma).is_not_null()
	assert_that(grandma.pay).is_equal(900)


func test_order_creation_and_fields() -> void:
	var o = OrderScript.new()
	o.id = 1
	o.type_id = &"urgent"
	o.pickup_pos = Vector2(0.0, 0.0)
	var test_drops: Array[Dictionary] = [{"pos": Vector2(100.0, 100.0), "name": "Тест"}]
	o.drops = test_drops
	o.dist_m = 200.0
	o.est_pay = 450
	o.time_limit = 75.0
	o.timer = 75.0

	assert_that(o.is_last_drop()).is_true()
	assert_that(o.current_target_pos()).is_equal(Vector2(0.0, 0.0))
	o.state = &"active"
	assert_that(o.current_target_pos()).is_equal(Vector2(100.0, 100.0))


func test_order_manager_lifecycle_headless() -> void:
	var mgr: Node3D = OrderManagerScript.new()
	var player_car := PlayerCar.new()
	player_car.setup(Db.cars.get_car(&"taxi"), Db.upgrades, _field)

	mgr.setup(_catalog, _field, _plan, _districts, _balance, player_car)

	# 1. Спавн открытых заказов
	mgr.spawn(0.0, 12.0, 1, Vector2.ZERO)
	assert_that(mgr.open_orders.size()).is_greater_equal(1)
	var order: RefCounted = mgr.open_orders[0]
	assert_that(order.state).is_equal(&"open")
	assert_that(order.est_pay).is_greater(0)

	# 2. Нельзя принять на высокой скорости
	player_car.motion.speed = 10.0
	var accepted_fast: bool = mgr.accept(order, player_car)
	assert_that(accepted_fast).is_false()
	assert_that(mgr.active_order).is_null()

	# 3. Успешный прием при остановке
	player_car.motion.speed = 0.0
	var accepted: bool = mgr.accept(order, player_car)
	assert_that(accepted).is_true()
	assert_that(mgr.active_order).is_equal(order)
	assert_that(order.state).is_equal(&"active")

	# 4. Завершение поездки
	var drop_target: Vector2 = order.current_target_pos()
	player_car.position = Vector3(drop_target.x, 0.0, drop_target.y)
	player_car.motion.speed = 0.0
	player_car.runtime.style = 0.95

	var prev_money := Game.money
	var res: Dictionary = mgr.complete(player_car, 12.0, 0.0)
	if res.get("partial", false):
		# Если это тур или группа, доезжаем до финальной точки
		var fin_target: Vector2 = order.current_target_pos()
		player_car.position = Vector3(fin_target.x, 0.0, fin_target.y)
		res = mgr.complete(player_car, 12.0, 0.0)

	assert_that(res.get("pay", 0)).is_greater(0)
	assert_that(res.get("stars", 0)).is_greater_equal(4)
	assert_that(Game.money).is_greater(prev_money)
	assert_that(mgr.active_order).is_null()

	mgr.queue_free()
	player_car.queue_free()


func test_order_manager_sets_passenger_count_on_accept_and_complete() -> void:
	var mgr: Node3D = OrderManagerScript.new()
	var player_car := PlayerCar.new()
	player_car.setup(Db.cars.get_car(&"taxi"), Db.upgrades, _field)
	mgr.setup(_catalog, _field, _plan, _districts, _balance, player_car)

	assert_that(player_car.runtime.passenger_count).is_equal(0)

	# Заказ строим вручную (не через spawn), чтобы не зависеть от случайного
	# типа: у посылки пассажира в салоне нет (orders.js:452), у normal — есть.
	var order := OrderScript.new()
	order.id = 1
	order.type_id = &"normal"
	order.title = "Тест"
	order.pickup_pos = Vector2(0.0, 0.0)
	var test_drops: Array[Dictionary] = [{"pos": Vector2(50.0, 50.0), "name": "Точка"}]
	order.drops = test_drops
	order.est_pay = 200
	order.state = &"open"

	player_car.motion.speed = 0.0
	assert_that(mgr.accept(order, player_car)).is_true()
	assert_that(player_car.runtime.passenger_count).is_equal(1)

	var drop_target: Vector2 = order.current_target_pos()
	player_car.position = Vector3(drop_target.x, 0.0, drop_target.y)
	var res: Dictionary = mgr.complete(player_car, 12.0, 0.0)
	if res.get("partial", false):
		var fin_target: Vector2 = order.current_target_pos()
		player_car.position = Vector3(fin_target.x, 0.0, fin_target.y)
		mgr.complete(player_car, 12.0, 0.0)

	assert_that(player_car.runtime.passenger_count).is_equal(0)

	mgr.queue_free()
	player_car.queue_free()
