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
	# Кварталов у настоящей сети улиц около 28, а не 64 клетки сетки, поэтому
	# бюджет задан плотностью на квартал, а не абсолютным числом домов.
	var buildable := 0
	for b in _world.city.blocks.count():
		if _world.city.blocks.special(b).is_empty():
			buildable += 1
	assert_float(float(_world.city.plan.building_count()) / float(maxi(1, buildable)))\
		.override_failure_message("домов %d на %d застраиваемых кварталов"
			% [_world.city.plan.building_count(), buildable])\
		.is_greater_equal(1.5)
	# Коллизии есть у каждого здания и у уличного оборудования.
	assert_int(_world.collision.shape_count())\
		.is_greater(_world.city.plan.building_count())
	assert_int(_world.collision.body_count()).is_greater(0)


func test_player_spawns_on_the_road() -> void:
	var p := _world.player.global_position
	assert_bool(_world.city.field.on_road(p.x, p.z))\
		.override_failure_message("машина заспавнилась вне дороги: %s" % p)\
		.is_true()
	# Правая полоса проспекта Кирова: точка лежит на его полотне, а не просто
	# «где-то на дороге».
	var e := _world.city.roads.query_nearest_edge(p)
	assert_str(_world.city.roads.edge_name(e))\
		.override_failure_message("старт не на проспекте Кирова, а на «%s»"
			% _world.city.roads.edge_name(e))\
		.is_equal(PyatigorskTopology.NAME_KIROV)
	assert_float(_world.city.roads.hit_dist)\
		.override_failure_message("машина стоит в %.2f м от оси проспекта"
			% _world.city.roads.hit_dist)\
		.is_less(_world.city.roads.edge_width(e) * 0.5)


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
	# Машина стоит ровно на поверхности, а не парит и не тонет.
	var p := _world.player.global_position
	assert_float(p.y)\
		.is_equal_approx(_world.city.field.surface_height_at(p.x, p.z), 0.01)
	assert_float(p.y).is_equal_approx(0.05, 0.01)

	# При заезде на тротуар колёса поднимаются на уровень тротуара. Точка —
	# южный тротуар проспекта Кирова: ось проспекта здесь на z ~ 20.1,
	# полуполотно 9 м, бордюр до 9.5 м, дальше тротуар.
	_world.player.place(Vector3(-2.5, 0.0, 31.0), 0.0)
	assert_float(_world.player.global_position.y).is_equal_approx(0.15, 0.01)

	# На газоне внутри квартала (двор между Кирова и Красноармейской,
	# 20+ м от любой оси) колёса стоят на грунте
	_world.player.place(Vector3(-4.0, 0.0, 42.0), 0.0)
	assert_float(_world.player.global_position.y).is_equal_approx(-0.02, 0.01)




func test_car_stops_against_a_building() -> void:
	# Машина ставится напротив конкретного дома и едет прямо в него.
	#
	# Прежний сценарий («разогнаться и вывернуть руль в пол») работал на сетке,
	# где за любым поворотом в 44 м стоял квартал. На настоящей топологии старт
	# лежит на 18-метровом проспекте Кирова, и разворот часто укладывается в
	# само полотно: тест падал примерно в двух прогонах из трёх, не находя
	# ничего плохого в городе.
	var plan := _world.city.plan
	assert_int(plan.building_count()).is_greater(0)
	var size := plan.building_size(0)
	var yaw := plan.building_yaw[0]
	var c := plan.building_center(0)
	# Локальная +Z дома смотрит ВГЛУБЬ квартала (`BlockPlanner._place_along`),
	# значит фасад обращён в -Z, и подъезжать надо оттуда.
	var into := Vector2(sin(yaw), cos(yaw))
	var start := c - into * (size.y * 0.5 + 16.0)
	_world.player.place(Vector3(start.x, 0.0, start.y), yaw)
	await _runner.simulate_frames(2)

	Input.action_press(&"throttle", 1.0)
	await _runner.simulate_frames(SEC * 4)
	assert_float(_world.player.runtime.damage)\
		.override_failure_message("машина проехала сквозь дом 0 (%s) без удара" % c)\
		.is_greater(0.0)


func test_camera_follows_the_car() -> void:
	Input.action_press(&"throttle", 1.0)
	await _runner.simulate_frames(SEC * 3)
	var d := _world.camera.global_position.distance_to(
		_world.player.global_position)
	assert_float(d)\
		.override_failure_message("камера отстала на %.1f м" % d)\
		.is_between(4.0, 20.0)


## У узла произвольной степени «двух осей» нет, поэтому инвариант формулируется
## ГЕОМЕТРИЧЕСКИ: одновременно зелёными бывают только рукава, расходящиеся почти
## на развёрнутый угол, — то есть одна улица, идущая через узел насквозь.
##
## Именно углы, а не `may_go_together()`. Таблица конфликтов заполняется как
## `groups[a] == groups[b]`, `car_state()` пускает подход, только если его
## `groups` совпал с активной фазой, — значит «оба зелёные ⟹ совместимы»
## тождественно истинно при любом графе и любой ошибке. Такой ассерт не может
## упасть. Здесь же сторона проверки считается по `approach_angle` независимо
## от контроллера, и тест впервые ловит на ЖИВОМ городе то, ради чего он
## написан: `_pair_opposites` спаривает рукава с допуском `OPPOSITE_TOL`, и на
## косых узлах настоящей топологии (`kal_s1` — Калинина плюс рампа Козлова,
## `krn_m` — три улицы под неправильными углами) в одну фазу могла бы попасть
## пара, расходящаяся всего на 140°.
func test_traffic_lights_cycle_and_never_open_conflicting_approaches() -> void:
	var signals := _world.city.signals
	var roads := _world.city.roads
	assert_int(signals.regulated_nodes().size())\
		.override_failure_message("в городе не оказалось регулируемых узлов")\
		.is_greater(0)
	# Минимальное расхождение пары, которую модель вправе пустить вместе:
	# `_pair_opposites` спаривает подход с тем, чей угол ближе `OPPOSITE_TOL`
	# к развёрнутому.
	var min_spread := PI - NodeSignalController.OPPOSITE_TOL
	for i in 60:
		await _runner.simulate_frames(3)
		for node in signals.regulated_nodes():
			var degree := roads.node_degree(node)
			for a in degree:
				if not signals.is_open_for_cars(node, a):
					continue
				for b in range(a + 1, degree):
					if not signals.is_open_for_cars(node, b):
						continue
					var spread := absf(Heading.delta(
						roads.approach_angle(node, a), roads.approach_angle(node, b)))
					assert_float(spread)\
						.override_failure_message(
							"узел %d: подходы %d и %d зелёные вместе, а расходятся на %.1f° (нужно >= %.1f°)"
							% [node, a, b, rad_to_deg(spread), rad_to_deg(min_spread)])\
						.is_greater_equal(min_spread)


## Зелёная волна: фронт задан узлом топологии, и сдвиг фазы обязан расти вдоль
## проспекта с запада на восток, а не расходиться радиально от края карты.
##
## Узлы сортируются по x ЗДЕСЬ, а не берутся в порядке `regulated_nodes()`:
## тот отдаёт их в порядке объявления в `PyatigorskTopology._bind_signals()`,
## и проверка «монотонно по этому порядку» говорила бы о порядке строк в
## литерале, а не о географии. После сортировки тест ловит именно то, ради
## чего написан: сдвинь узел по x — и монотонность обязана поехать.
func test_green_wave_runs_along_kirov_avenue() -> void:
	var signals := _world.city.signals
	var roads := _world.city.roads
	var avenue: Array[int] = []
	for node in signals.regulated_nodes():
		var p := roads.node_position(node)
		if p.z > 45.0 or p.z < 5.0:
			continue # только узлы самого проспекта
		avenue.append(node)
	avenue.sort_custom(func(l: int, r: int) -> bool:
		return roads.node_position(l).x < roads.node_position(r).x)
	assert_int(avenue.size())\
		.override_failure_message("узлов проспекта в проверке: %d" % avenue.size())\
		.is_greater_equal(4)
	var prev := INF
	for node in avenue:
		var offset := signals.phase_offset(node)
		if prev < INF:
			assert_float(offset)\
				.override_failure_message(
					"узел %d (x=%.0f): сдвиг фазы %.2f не позже предыдущего %.2f"
						% [node, roads.node_position(node).x, offset, prev])\
				.is_less(prev)
		prev = offset


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


## Трафик едет по НАСТОЯЩЕМУ графу города, а не по сетке под новым визуалом.
##
## Проверяется не «поменялась ли картинка», а то, что позиция каждой машины
## лежит на полотне ребра ТОПОЛОГИИ: у сетки 9x9 колец нет вовсе, а её рёбра
## строго осевые, поэтому машина на дуге привокзального кольца или на
## наклонном участке проспекта Кирова в сеточной модели существовать не может.
func test_traffic_drives_the_city_graph() -> void:
	var roads := _world.city.roads
	var rings := 0
	for n in roads.node_count():
		if roads.node_kind(n) == CityGraph.NodeKind.ROUNDABOUT:
			rings += 1
	assert_int(rings)\
		.override_failure_message("колец в графе города: %d — это не топология Пятигорска" % rings)\
		.is_greater_equal(3)

	await _runner.simulate_frames(SEC)
	var mgr := _world.traffic.manager
	var on_road := 0
	for i in mgr.count:
		var p := Vector3(mgr.world_x(i), mgr.world_road_y(i), mgr.world_z(i))
		var e := roads.query_nearest_edge(p, 30.0)
		if e >= 0 and roads.hit_dist <= roads.edge_width(e) * 0.5 + 1.0:
			on_road += 1
	# Не все: машина на дуге кольца едет по ребру ВИДА трафика, которого в
	# графе города нет (`TrafficRoadView`), и в этот счёт не попадает.
	assert_int(on_road)\
		.override_failure_message("на полотне графа только %d машин из %d"
			% [on_road, mgr.count])\
		.is_greater_equal(int(mgr.count * 0.8))


## Пешеходы ходят по тротуарам того же графа: их позиции обязаны совпадать с
## узлами пешеходной сети, построенной поверх топологии.
func test_pedestrians_walk_the_city_graph() -> void:
	var pm := _world.pedestrians.manager
	var graph := _world.city.graph
	var moved := 0
	var before := PackedVector2Array()
	for i in pm.count:
		before.append(Vector2(pm.world_x(i), pm.world_z(i)))
	await _runner.simulate_frames(SEC * 2)
	var near_graph := 0
	for i in pm.count:
		if pm.alive[i] == 0:
			continue
		var now := Vector2(pm.world_x(i), pm.world_z(i))
		if before[i].distance_to(now) > 0.5:
			moved += 1
		var node := graph.nearest_node(now.x, now.y)
		var np := graph.position_of(node)
		# Пешеход идёт по ребру между узлами графа, поэтому меряется удаление
		# от ближайшего узла, а не совпадение с ним: полулента бывает 60 м.
		if Vector2(np.x, np.z).distance_to(now) < 40.0:
			near_graph += 1
	assert_int(moved)\
		.override_failure_message("за две секунды не сдвинулся ни один пешеход")\
		.is_greater(0)
	assert_int(near_graph)\
		.override_failure_message("рядом с пешеходной сетью только %d из %d"
			% [near_graph, pm.count])\
		.is_greater_equal(int(pm.count * 0.9))


func test_player_ped_exit_and_enter_car() -> void:
	# Сбрасываем газ от предыдущих тестов и останавливаем машину
	Input.action_release(&"throttle")
	_world.player.motion.speed = 0.0
	_world.player.motion.forward_speed = 0.0
	_world.player.motion.lateral_speed = 0.0
	_world.player.motion.velocity = Vector3.ZERO
	_world.player.velocity = Vector3.ZERO
	await _runner.simulate_frames(2)

	assert_bool(_world.in_car).is_true()
	assert_object(_world.camera.target).is_equal(_world.player)

	# Выход из стоящего авто
	var exited := _world.exit_car()
	assert_bool(exited).is_true()
	assert_bool(_world.in_car).is_false()
	assert_object(_world.player_ped).is_not_null()
	assert_object(_world.camera.target).is_equal(_world.player_ped)
	assert_bool(_world.camera.mode == ChaseCamera.Mode.PED).is_true()
	assert_bool(_world.player.is_active).is_false()

	# Пешеход появился слева от машины
	var ped_pos := _world.player_ped.global_position
	var car_pos := _world.player.global_position
	assert_float(ped_pos.distance_to(car_pos)).is_between(1.0, 3.5)

	# Посадка обратно в авто
	var entered := _world.enter_car()
	assert_bool(entered).is_true()
	assert_bool(_world.in_car).is_true()
	assert_object(_world.camera.target).is_equal(_world.player)
	assert_bool(_world.camera.mode == ChaseCamera.Mode.CAR).is_true()
	assert_bool(_world.player.is_active).is_true()


func test_gps_routes_to_an_order_through_a_roundabout() -> void:
	# Сценарий готовности этапа 9: заказ в центре, игрок на южном выезде
	# Калинина, между ними единственный проезд — через кольцо kal_s2 (30, 172).
	# Кольца есть только у живой топологии, поэтому этот тест ловит и то, что
	# GPS остался бы на сетке 9x9.
	#
	# Кадры мира здесь не крутятся намеренно: World._process() каждый кадр
	# кормит GPS состоянием OrderManager, и без принятого заказа маршрут
	# немедленно сбрасывается. Движение игрока поэтому имитируется двумя
	# вызовами update() из разных точек — ровно то, что делает мир.
	var from := Vector2(34.0, 232.0)
	var drop := Vector2(24.0, 22.0)
	_world.player.place(Vector3(from.x, 0.0, from.y), PI)
	_world.gps.update(GpsRouter.RECOMPUTE_INTERVAL, from, true, true, drop, 1.0)

	assert_bool(_world.gps.has_target())\
		.override_failure_message("маршрут до заказа не построился")\
		.is_true()
	var roads := _world.city.roads
	var rings := 0
	for p in _world.gps.route:
		var id := _world.gps.graph.nearest_node_id(p)
		if _world.gps.graph.node_position(id).distance_to(p) < 0.01 \
				and roads.node_kind(id) == CityGraph.NodeKind.ROUNDABOUT:
			rings += 1
	assert_int(rings)\
		.override_failure_message("маршрут %s -> %s не прошёл ни одного кольца"
			% [from, drop])\
		.is_equal(1)

	# Стрелка HUD целится в следующую точку маршрута: машина стоит носом на
	# север (курс PI), кольцо прямо перед ней — глиф обязан смотреть «вперёд»
	# (-PI/2 в конвенции ui.js), а не вбок и не назад.
	var ang := GpsRouter.arrow_angle(from, _world.player.motion.heading,
		_world.gps.next_waypoint())
	assert_float(ang)\
		.override_failure_message("стрелка повёрнута на %.2f рад вместо %.2f"
			% [ang, -PI / 2.0])\
		.is_equal_approx(-PI / 2.0, 0.2)

	# Проехали 60 м на север — остаток пути обязан сократиться примерно на
	# столько же, а маршрут остаться тем же.
	var before := _world.gps.remaining_distance()
	var moved := Vector2(32.0, 172.0)
	_world.gps.update(GpsRouter.RECOMPUTE_INTERVAL, moved, true, true, drop, 1.0)
	var after := _world.gps.remaining_distance()
	assert_float(before - after)\
		.override_failure_message("остаток пути изменился на %.1f м за 60 м пути"
			% (before - after))\
		.is_between(40.0, 80.0)


func test_world_unloads_without_leaks() -> void:
	var before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	_world.collision.clear()
	assert_int(_world.collision.body_count()).is_equal(0)
	assert_float(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))\
		.is_less_equal(before)
