extends GdUnitTestSuite
## Мир должен собираться, машина — ехать и упираться в застройку.
##
## Юнит-тесты проверяют формулы, но не то, что физика, коллизии и рельеф
## сходятся вместе. Здесь мир поднимается целиком и по нему проезжают.

const WORLD := "res://world/world.tscn"
## Кадров физики на секунду симуляции.
const SEC := 60

var _runner: GdUnitSceneRunner
var _world: World


func before_test() -> void:
	_runner = scene_runner(WORLD)
	_world = _runner.scene() as World
	_world.auto_build = false
	_world.build()


func after_test() -> void:
	Input.action_release(&"throttle")
	Input.action_release(&"brake")
	Input.action_release(&"steer_right")


func test_world_builds_with_city_and_player() -> void:
	assert_object(_world.city).is_not_null()
	assert_object(_world.player).is_not_null()
	assert_int(_world.city.plan.building_count()).is_greater(180)
	# Коллизии есть у каждого здания и у уличного оборудования.
	assert_int(_world.collision.shape_count())\
		.is_greater(_world.city.plan.building_count())
	assert_int(_world.collision.body_count()).is_greater(0)


func test_player_spawns_on_the_road() -> void:
	var p := _world.player.global_position
	assert_bool(_world.city.field.on_road(p.x, p.z))\
		.override_failure_message("машина заспавнилась вне дороги: %s" % p)\
		.is_true()
	# Правая полоса: смещение от оси дороги в сторону, обратную направлению.
	assert_float(p.x).is_equal_approx(-2.5, 0.01)


func test_car_accelerates_and_reaches_top_speed() -> void:
	var start := _world.player.global_position
	Input.action_press(&"throttle", 1.0)
	# Крутим до выхода на полку, а не фиксированное время: simulate_frames
	# считает кадры процесса, а не физические тики, и их соотношение
	# зависит от нагрузки.
	var top := 0.0
	for i in 30:
		await _runner.simulate_frames(20)
		var v := _world.player.speed_kmh()
		if v - top < 0.05:
			top = maxf(top, v)
			break
		top = v
	assert_float(start.distance_to(_world.player.global_position))\
		.override_failure_message("машина не тронулась с места")\
		.is_greater(40.0)
	# «Пятёрочка»: 34 м/с = 122 км/ч.
	assert_float(top).is_between(115.0, 125.0)


func test_car_burns_fuel_while_driving() -> void:
	var before := _world.player.runtime.fuel
	Input.action_press(&"throttle", 1.0)
	await _runner.simulate_frames(SEC * 2)
	assert_float(_world.player.runtime.fuel).is_less(before)


func test_car_follows_terrain_height() -> void:
	# Машина стоит ровно на земле, а не парит и не тонет.
	var p := _world.player.global_position
	assert_float(p.y)\
		.is_equal_approx(_world.city.field.height_at(p.x, p.z), 0.01)


func test_car_stops_against_a_building() -> void:
	# Разгон, затем руль в пол: машина обязана упереться в застройку.
	Input.action_press(&"throttle", 1.0)
	await _runner.simulate_frames(SEC * 4)
	Input.action_press(&"steer_right", 1.0)
	await _runner.simulate_frames(SEC * 6)
	assert_float(_world.player.runtime.damage)\
		.override_failure_message("машина проехала сквозь город без единого удара")\
		.is_greater(0.0)


func test_camera_follows_the_car() -> void:
	Input.action_press(&"throttle", 1.0)
	await _runner.simulate_frames(SEC * 3)
	var d := _world.camera.global_position.distance_to(
		_world.player.global_position)
	assert_float(d)\
		.override_failure_message("камера отстала на %.1f м" % d)\
		.is_between(4.0, 20.0)


func test_traffic_lights_cycle_and_never_open_both_axes() -> void:
	var lights := _world.city.lights
	for i in 200:
		await _runner.simulate_frames(3)
		for isec in 9:
			var z := lights.is_open_for_cars(isec, TrafficLightController.Axis.Z_ROAD)
			var x := lights.is_open_for_cars(isec, TrafficLightController.Axis.X_ROAD)
			assert_bool(z and x).is_false()


func test_landmarks_are_placed_on_terrain() -> void:
	assert_object(_world.landmarks).is_not_null()
	# 14 типов из плана (9 из data/landmarks + орёл, трамвай, остановка,
	# Бендер, стела), но остановка трамвая ставится трижды («Цветник»,
	# «Вокзал», «Лира», как в оригинале) — итого 16 расставленных объектов.
	assert_int(_world.landmarks.count()).is_equal(16)
	for i in _world.landmarks.count():
		var p := _world.landmarks.position_of(i)
		assert_float(p.y)\
			.override_failure_message("достопримечательность %d висит над землёй: y=%.2f, height_at=%.2f"
				% [i, p.y, _world.city.field.height_at(p.x, p.z)])\
			.is_equal_approx(_world.city.field.height_at(p.x, p.z), 0.01)


func test_traffic_spawns_and_drives() -> void:
	assert_object(_world.traffic).is_not_null()
	assert_int(_world.traffic.manager.count).is_equal(Db.balance.traffic_count)
	var mgr := _world.traffic.manager
	var start := Vector2(mgr.world_x(0), mgr.world_z(0))
	await _runner.simulate_frames(SEC * 2)
	var moved := Vector2(mgr.world_x(0), mgr.world_z(0))
	assert_float(start.distance_to(moved))\
		.override_failure_message("машина трафика 0 не сдвинулась за 2 секунды")\
		.is_greater(0.5)


func test_world_unloads_without_leaks() -> void:
	var before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	_world.collision.clear()
	assert_int(_world.collision.body_count()).is_equal(0)
	assert_float(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))\
		.is_less_equal(before)
