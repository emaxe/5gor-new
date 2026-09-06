extends GdUnitTestSuite
## Генерация города обязана быть детерминированной и укладываться в бюджеты.
## Сид пишется в слот сохранения, поэтому «тот же сид — тот же город» это
## не оптимизация, а часть игрового дизайна: город должен запоминаться.
##
## С этапа 9 план строится по НАСТОЯЩЕЙ топологии (`PyatigorskTopology`), а не
## по сетке 9x9, поэтому проверки сеточных чисел («16 регулируемых
## перекрёстков», «дом не ближе road_half к оси») заменены на инварианты
## графа: запас до КРОМКИ конкретного полотна, стойка на каждый подход
## регулируемого узла, точка подачи на тротуаре своей улицы.

var _field: CityField
var _roads: CityGraph
var _topology: PyatigorskTopology
var _ped: PedGraph
var _blocks: CityBlocks
var _markings: RoadMarkings
var _signals: NodeSignalPlan
var _plan: CityPlan


func before() -> void:
	_field = CityField.new(Db.balance)
	_topology = PyatigorskTopology.new()
	_roads = _topology.build(_field)
	_field.attach_roads(_roads)
	_ped = PedGraph.on_graph(_roads, _topology.signal_nodes, _field.sidewalk)
	_blocks = CityBlocks.new()
	_blocks.build(_roads, _topology.node_district, _topology.landmark_node)
	_markings = RoadMarkings.new(_roads, RoadMesh.new(_roads, _field),
		_topology.signal_nodes, _ped.crossings)
	_signals = NodeSignalPlan.build(_roads,
		NodeSignalController.build(_roads, _topology.signal_nodes,
			_topology.wave_front_nodes))
	_plan = _make(Db.balance.world_seed)


func _make(seed_value: int) -> CityPlan:
	return CityPlanner.new(_field, _roads, _blocks, _topology.node_district,
		Db.districts).plan(seed_value, _markings.crossings, _signals,
		_topology.landmark_node)


## Запас от точки до кромки ближайшего полотна В ПЛАНЕ, м: перебор всех
## сегментов без разбора ярусов.
##
## Именно в плане, а не через `CityGraph.road_clearance`: тот разводит ярусы
## по высоте запроса, а у теста высоты нет — точки плана двумерные. На склоне
## Машука высота рельефа в паре метров от дороги уже отличается от полотна
## больше допуска, и запрос «по рельефу» объявил бы собственную улицу чужим
## ярусом. Разноуровневых мест на тротуарах города нет (рампа и пролёт из
## расстановки исключены), поэтому плановый промер здесь строже графового.
func _clearance(x: float, z: float) -> float:
	var best := INF
	for e in _roads.edge_count():
		var half := _roads.edge_width(e) * 0.5
		for k in range(1, _roads.edge_point_count(e)):
			var a := _roads.edge_point(e, k - 1)
			var b := _roads.edge_point(e, k)
			var seg := Vector2(b.x - a.x, b.z - a.z)
			var to := Vector2(x - a.x, z - a.z)
			var denom := seg.length_squared()
			var t := 0.0 if denom < 1e-9 else clampf(to.dot(seg) / denom, 0.0, 1.0)
			best = minf(best, to.distance_to(seg * t) - half)
	return best


func test_same_seed_gives_identical_plan() -> void:
	var again := _make(Db.balance.world_seed)
	assert_dict(_plan.summary()).is_equal(again.summary())
	assert_int(again.building_count()).is_equal(_plan.building_count())
	for i in _plan.building_count():
		assert_vector(again.building_rect[i]).is_equal(_plan.building_rect[i])
		assert_float(again.building_height[i]).is_equal(_plan.building_height[i])
		assert_float(again.building_yaw[i]).is_equal(_plan.building_yaw[i])


func test_different_seed_gives_different_city() -> void:
	var other := _make(12345)
	assert_int(other.building_count()).is_not_equal(_plan.building_count())


func test_city_is_built_at_the_density_of_its_blocks() -> void:
	# Кварталов у настоящей сети улиц около 28, а не 64 клетки сетки, поэтому
	# бюджет задан плотностью на квартал, а не абсолютным числом домов.
	var buildable := 0
	for b in _blocks.count():
		if _blocks.special(b).is_empty():
			buildable += 1
	var per_block := float(_plan.building_count()) / float(maxi(1, buildable))
	assert_float(per_block)\
		.override_failure_message("на застраиваемый квартал приходится %.2f дома (%d на %d)"
			% [per_block, _plan.building_count(), buildable])\
		.is_greater_equal(1.5)


func test_buildings_are_pyatigorsk_scale() -> void:
	# Пятигорск малоэтажный: башен выше 25 м в городе нет.
	for h in _plan.building_height:
		assert_float(h).is_between(6.0, 25.0)


func test_buildings_never_stand_on_the_roadway() -> void:
	for i in _plan.building_count():
		for c in _plan.building_corners(i):
			assert_float(_clearance(c.x, c.y))\
				.override_failure_message(
					"угол здания %d стоит на полотне: %s" % [i, c])\
				.is_greater_equal(BlockPlanner.MIN_ROAD_CLEARANCE)


func test_props_are_not_on_the_roadway() -> void:
	# Запас меряется до КРОМКИ полотна, а не до оси: у переулка и проспекта
	# полуширина разная, и общего «road_half» у города больше нет.
	for p in _plan.tree_pos:
		assert_float(_clearance(p.x, p.z))\
			.override_failure_message("дерево на полотне: %s" % p)\
			.is_greater(0.0)
	for p in _plan.lamp_pos:
		assert_float(_clearance(p.x, p.z))\
			.override_failure_message("фонарь на полотне: %s" % p)\
			.is_greater(0.0)
	for p in _plan.bin_pos:
		assert_float(_clearance(p.x, p.z))\
			.override_failure_message("урна на полотне: %s" % p)\
			.is_greater(0.0)


func test_pickup_points_are_on_sidewalks() -> void:
	assert_int(_plan.pickup_pos.size()).is_greater(100)
	for p in _plan.pickup_pos:
		var d := _clearance(p.x, p.y)
		# Точка стоит на тротуаре: не на проезжей части и не в глубине двора.
		#
		# Верхняя граница — ПОЛОВИНА тротуара, а не весь: точка ставится на
		# `half + sidewalk / 2` от оси своего ребра, то есть ровно посередине
		# тротуара, и запас до кромки этого ребра равен `sidewalk / 2`. Граница
		# в целый тротуар была бы недостижима сверху по построению и не
		# проверяла бы ничего.
		assert_float(d)\
			.override_failure_message("точка подачи %s: запас до кромки %.2f м" % [p, d])\
			.is_between(-0.01, _field.sidewalk * 0.5 + 0.01)


func test_every_district_has_pickup_points() -> void:
	var seen := {}
	for d in _plan.pickup_district:
		seen[d] = true
	assert_int(seen.size()).is_equal(Db.districts.items.size())


func test_crosswalks_come_from_the_pedestrian_graph() -> void:
	# Разметка генерируется из списка переходов пешеходной сети: она физически
	# не может разъехаться с логикой ПДД.
	assert_int(_plan.crosswalk_pos.size()).is_equal(_markings.crossings.size())
	assert_int(_plan.crosswalk_pos.size()).is_greater(0)


## Потолок расхождения центров зебры и пешеходного перехода, м. Число
## измеренное: сегодня медиана около 2 м, максимум 10.65 м (узел 34, бульвар
## Гагарина), см. `test_zebra_and_pedestrian_crossing_do_not_drift_apart`.
const ZEBRA_VS_CROSSING_MAX := 12.0


## Зебра и пешеходный переход — две НЕЗАВИСИМЫЕ записи одного места, и это
## сознательное решение этапа 9: у `PedGraph` центр стоит там, где пешеход
## сходит с тротуара, у `RoadMarkings` — там, где полосы ложатся перед
## горловиной узла (`cut_point + dir * ZEBRA_SETBACK`). Сводить их нечем,
## общая у них только адресация (узел, подход).
##
## Ровно поэтому нужна страховка: ничто не мешает правке `ZEBRA_SETBACK`,
## `MIN_CORNER_HALF` или геометрии горловины молча развести их так, что
## пешеход станет переходить в стороне от нарисованной зебры. Тест — храповик
## на расстояние между ними, а не требование совпадения.
func test_zebra_and_pedestrian_crossing_do_not_drift_apart() -> void:
	var ped_center: Dictionary[int, Vector3] = {}
	for c: Dictionary in _ped.crossings:
		ped_center[MathUtils.hash_key(int(c["node"]), int(c["approach"]))] = c["center"]
	var pairs := 0
	for m: Dictionary in _markings.crossings:
		var key := MathUtils.hash_key(int(m["node"]), int(m["approach"]))
		assert_bool(ped_center.has(key))\
			.override_failure_message(
				"зебра на узле %d подходе %d нарисована там, где пешеходного перехода нет"
				% [m["node"], m["approach"]])\
			.is_true()
		if not ped_center.has(key):
			continue
		pairs += 1
		var a: Vector3 = m["center"]
		var b: Vector3 = ped_center[key]
		var d := Vector2(a.x - b.x, a.z - b.z).length()
		assert_float(d)\
			.override_failure_message(
				"узел %d подход %d: зебра и переход разошлись на %.2f м"
				% [m["node"], m["approach"], d])\
			.is_less_equal(ZEBRA_VS_CROSSING_MAX)
	assert_int(pairs)\
		.override_failure_message("сверено пар зебра-переход: %d" % pairs)\
		.is_greater(100)


func test_signal_posts_serve_every_approach_of_every_regulated_node() -> void:
	var expected := 0
	var controller := NodeSignalController.build(_roads, _topology.signal_nodes,
		_topology.wave_front_nodes)
	for node in controller.regulated_nodes():
		expected += _roads.node_degree(node)
	assert_int(_plan.signal_pos.size())\
		.override_failure_message("стоек %d при %d подходах регулируемых узлов"
			% [_plan.signal_pos.size(), expected])\
		.is_equal(expected)


func test_special_blocks_stay_empty() -> void:
	# Квартал, занятый достопримечательностью (Цветник, Нарзанные ванны,
	# Провал, Грот), застройке не подлежит.
	for i in _plan.building_count():
		var b := _blocks.block_at(_plan.building_center(i))
		if b < 0:
			continue
		assert_str(String(_blocks.special(b)))\
			.override_failure_message("здание %d в особом квартале %d" % [i, b])\
			.is_empty()


func test_planning_fits_the_frame_budget() -> void:
	# Фаза планирования уходит в фоновый поток, но и там она не должна
	# растягиваться: это блокирует показ загрузочного экрана.
	var t0 := Time.get_ticks_msec()
	_make(Db.balance.world_seed)
	var ms := Time.get_ticks_msec() - t0
	assert_int(ms).override_failure_message("планирование заняло %d мс" % ms)\
		.is_less(250)
