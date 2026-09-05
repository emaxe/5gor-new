extends GdUnitTestSuite
## Регулирование узлов графа: N фаз по подходам вместо двух осей.
##
## Главный инвариант — обобщение `test_axes_are_never_green_together`
## (tests/unit/test_traffic_lights.gd:49) на узел произвольной степени:
## никакие два конфликтующих ПО ТАБЛИЦЕ подхода не зелёные одновременно.
## Проверка идёт перебором самой таблицы конфликтов узла, а не жёстким
## «ровно две оси», и обязательно на узлах степени 3 и 5 — там, где понятие
## оси не определено вовсе.
##
## Второй инвариант — паритет с осевой моделью на сетке 9x9: до этапа 9 линзы
## светофоров красит `TrafficLightController`, а машины слушают эту модель,
## и разойдись они, игрок увидел бы машины, стоящие на зелёный.

## Ширина полотна синтетических графов, м (проспект оригинала).
const WIDTH := 12.0
## Радиус кольца в фикстуре, м — порядок настоящих колец Пятигорска.
const RING_RADIUS := 20.0
## Шаг перебора цикла, с: 320 шагов накрывают все 16 с с запасом на границы фаз.
const STEP := 0.05
const STEPS := 320

## Смещение выборки от границ фаз, с. Осевая и узловая модели считают сдвиг
## фазы по-разному — первая из координаты перекрёстка, вторая из суммы длин
## рёбер, — и на самой границе расходятся на единицы микросекунд float. Это
## шум представления, а не разное поведение: сравнивать состояния надо не
## ровно в точке переключения. 17 мс не кратны ни шагу перебора (50 мс), ни
## сдвигу волны (1.6 с), поэтому выборка не попадает на границу никогда.
const PHASE_EPS := 0.017


# --- Фикстуры ----------------------------------------------------------------

## T-образный узел: подходы на восток, юг и запад — степень 3.
func _tee() -> CityGraph:
	var g := CityGraph.new()
	var c := g.add_node(Vector3.ZERO)
	for dir in [Vector3(120.0, 0.0, 0.0), Vector3(0.0, 0.0, 120.0), Vector3(-120.0, 0.0, 0.0)]:
		g.add_edge(c, g.add_node(dir), PackedVector3Array(), WIDTH)
	g.build()
	return g


## Обычный 4-подходный перекрёсток: две пары противоположных подходов.
func _cross() -> CityGraph:
	var g := CityGraph.new()
	var c := g.add_node(Vector3.ZERO)
	for dir in [Vector3(120.0, 0.0, 0.0), Vector3(0.0, 0.0, 120.0),
			Vector3(-120.0, 0.0, 0.0), Vector3(0.0, 0.0, -120.0)]:
		g.add_edge(c, g.add_node(dir), PackedVector3Array(), WIDTH)
	g.build()
	return g


## Звезда из пяти лучей: степень 5, две пары «почти напротив» и одиночка.
func _star5() -> CityGraph:
	var g := CityGraph.new()
	g.add_node(Vector3.ZERO)
	for k in 5:
		var ang := TAU * float(k) / 5.0
		g.add_node(Vector3(120.0 * cos(ang), 0.0, 120.0 * sin(ang)))
	for k in 5:
		g.add_edge(0, k + 1, PackedVector3Array(), WIDTH)
	g.build()
	return g


## Кольцо: узел 0 — `NodeKind.ROUNDABOUT` с радиусом и четырьмя подходами.
func _ring() -> CityGraph:
	var g := CityGraph.new()
	var hub := g.add_node(Vector3.ZERO, 0, CityGraph.NodeKind.ROUNDABOUT, RING_RADIUS)
	for k in 4:
		var ang := TAU * float(k) / 4.0
		g.add_edge(hub, g.add_node(Vector3(120.0 * cos(ang), 0.0, 120.0 * sin(ang))),
			PackedVector3Array(), WIDTH)
	g.build()
	return g


## Проспект с НЕРАВНЫМИ пролётами: узлы 0, 1, 2 стоят на x = 0, 100, 250, у
## каждого по отвилку на север и на юг. Неравные длины — суть проверки волны:
## по индексу ячейки такой сдвиг не выражается, только по расстоянию.
##
## Проспект продолжен тупиками на запад и на восток, чтобы у КАЖДОГО узла был
## и западный, и восточный подход: колонна, идущая на восток, подъезжает по
## западному подходу, и у крайнего узла его иначе просто нет.
func _corridor() -> CityGraph:
	var g := CityGraph.new()
	var xs := PackedFloat32Array([0.0, 100.0, 250.0])
	for x in xs:
		g.add_node(Vector3(x, 0.0, 0.0))
	for k in xs.size():
		g.add_edge(k, g.add_node(Vector3(xs[k], 0.0, 80.0)), PackedVector3Array(), WIDTH)
		g.add_edge(k, g.add_node(Vector3(xs[k], 0.0, -80.0)), PackedVector3Array(), WIDTH)
	g.add_edge(0, 1, PackedVector3Array(), WIDTH)
	g.add_edge(1, 2, PackedVector3Array(), WIDTH)
	g.add_edge(0, g.add_node(Vector3(-80.0, 0.0, 0.0)), PackedVector3Array(), WIDTH)
	g.add_edge(2, g.add_node(Vector3(330.0, 0.0, 0.0)), PackedVector3Array(), WIDTH)
	g.build()
	return g


func _signals(graph: CityGraph, nodes: Array[int]) -> NodeSignalController:
	return NodeSignalController.build(graph, PackedInt32Array(nodes))


# --- Таблица конфликтов и фазы -----------------------------------------------

## Критерий готовности этапа: обобщение `test_axes_are_never_green_together`.
## Доказательство идёт перебором таблицы конфликтов узла, поэтому степень
## узла в него не зашита — 3, 4 и 5 проверяются одним и тем же кодом.
func test_conflicting_approaches_are_never_green_together() -> void:
	for g: CityGraph in [_tee(), _cross(), _star5()]:
		var s := _signals(g, [0])
		var degree := g.node_degree(0)
		var conflicts := 0
		for a in degree:
			for b in degree:
				if not s.may_go_together(0, a, b):
					conflicts += 1
		# Пустая таблица сделала бы проверку ниже бессодержательной.
		assert_int(conflicts)\
			.override_failure_message("у узла степени %d нет ни одной конфликтующей пары подходов"
				% degree)\
			.is_greater(0)

		for step in STEPS:
			s.time = step * STEP
			for a in degree:
				for b in degree:
					if s.may_go_together(0, a, b):
						continue
					assert_bool(s.is_open_for_cars(0, a) and s.is_open_for_cars(0, b))\
						.override_failure_message(
							"узел степени %d: конфликтующие подходы %d и %d оба зелёные в t=%.2f"
								% [degree, a, b, s.time])\
						.is_false()


## Таблица — данные узла, а не функция: она обязана быть симметричной и
## рефлексивной, иначе «конфликт» зависел бы от порядка аргументов.
func test_conflict_table_is_symmetric_and_reflexive() -> void:
	var g := _star5()
	var s := _signals(g, [0])
	for a in 5:
		assert_bool(s.may_go_together(0, a, a))\
			.override_failure_message("подход %d конфликтует сам с собой" % a)\
			.is_true()
		for b in 5:
			assert_bool(s.may_go_together(0, a, b))\
				.override_failure_message("таблица несимметрична на паре (%d, %d)" % [a, b])\
				.is_equal(s.may_go_together(0, b, a))


## Консервативное упрощение: одновременно едет не больше одной пары
## противоположных подходов. Отсюда число фаз — 2 у степени 3 и 4 (пара +
## пара или пара + одиночка) и 3 у степени 5 (две пары + одиночка).
func test_phase_count_follows_opposite_pairing() -> void:
	assert_int(_signals(_tee(), [0]).phase_count(0))\
		.override_failure_message("узел степени 3 обязан разводиться на 2 фазы")\
		.is_equal(2)
	assert_int(_signals(_cross(), [0]).phase_count(0))\
		.override_failure_message("узел степени 4 из двух пар обязан остаться 2-фазным")\
		.is_equal(2)
	assert_int(_signals(_star5(), [0]).phase_count(0))\
		.override_failure_message("узел степени 5 обязан разводиться на 3 фазы")\
		.is_equal(3)


## Противоположные подходы 4-подходного узла едут одной фазой: улица,
## проходящая перекрёсток насквозь, не разрывается на две фазы.
func test_opposite_approaches_share_a_phase() -> void:
	var g := _cross()
	var s := _signals(g, [0])
	# Подходы упорядочены по углу: 0 — север, 1 — восток, 2 — юг, 3 — запад.
	assert_int(s.phase_of(0, 0))\
		.override_failure_message("север и юг обязаны ехать одной фазой")\
		.is_equal(s.phase_of(0, 2))
	assert_int(s.phase_of(0, 1))\
		.override_failure_message("восток и запад обязаны ехать одной фазой")\
		.is_equal(s.phase_of(0, 3))
	assert_bool(s.may_go_together(0, 0, 1))\
		.override_failure_message("перпендикулярные подходы попали в одну фазу")\
		.is_false()


# --- Паритет с осевой моделью -------------------------------------------------

## На сетке 9x9 новая модель обязана выдавать РОВНО то же, что осевая: до
## этапа 9 линзы красит осевой контроллер, а машины уже слушают узловой.
func test_grid_node_matches_axis_controller() -> void:
	var field := CityField.new(Db.balance)
	var g := CityGraphGrid.from_field(field)
	var nodes := CityGraphGrid.signalized_nodes(field)
	assert_int(nodes.size())\
		.override_failure_message("на сетке 9x9 регулируемых перекрёстков должно быть 16, а не %d"
			% nodes.size())\
		.is_equal(16)

	var s := NodeSignalController.build(g, nodes)
	var axis_lights := TrafficLightController.new(field)
	# Подходы сеточного узла по возрастанию угла: 0 — север, 1 — восток,
	# 2 — юг, 3 — запад. Север и юг — это ось Z, восток и запад — ось X.
	var axis_of := [TrafficLightController.Axis.Z_ROAD, TrafficLightController.Axis.X_ROAD,
		TrafficLightController.Axis.Z_ROAD, TrafficLightController.Axis.X_ROAD]
	for step in STEPS:
		var t := step * STEP + PHASE_EPS
		s.time = t
		axis_lights.time = t
		for node in nodes:
			@warning_ignore("integer_division")
			var i: int = node / PedGraph.AXES
			for k in 4:
				assert_int(int(s.car_state(node, k)))\
					.override_failure_message(
						"узел %d, подход %d в t=%.2f: узловая модель %d, осевая %d"
							% [node, k, t, int(s.car_state(node, k)),
								int(axis_lights.car_state(i, axis_of[k]))])\
					.is_equal(int(axis_lights.car_state(i, axis_of[k])))


func test_grid_phase_offset_matches_axis_wave() -> void:
	var field := CityField.new(Db.balance)
	var g := CityGraphGrid.from_field(field)
	var s := NodeSignalController.build(g, CityGraphGrid.signalized_nodes(field))
	for node in s.regulated_nodes():
		@warning_ignore("integer_division")
		var i: int = node / PedGraph.AXES
		assert_float(s.phase_offset(node))\
			.override_failure_message("сдвиг фазы узла %d: %.4f вместо осевого %.4f"
				% [node, s.phase_offset(node), TrafficLightController.new(field).phase_offset(i)])\
			.is_equal_approx(TrafficLightController.new(field).phase_offset(i), 1e-3)


# --- Зелёная волна ------------------------------------------------------------

## Сдвиг фазы пропорционален накопленному расстоянию по рёбрам, а не номеру
## узла: пролёты 100 и 150 м дают сдвиги 2.5 и 3.75 с (WAVE_SPEED = 40 м/с).
func test_green_wave_shifts_phase_by_graph_distance() -> void:
	var g := _corridor()
	var s := _signals(g, [0, 1, 2])
	var d01 := s.phase_offset(0) - s.phase_offset(1)
	var d12 := s.phase_offset(1) - s.phase_offset(2)
	assert_float(d01)\
		.override_failure_message("пролёт 100 м обязан сдвигать фазу на 2.5 с, а сдвинул на %.3f"
			% d01)\
		.is_equal_approx(100.0 / NodeSignalController.WAVE_SPEED, 1e-3)
	assert_float(d12)\
		.override_failure_message("пролёт 150 м обязан сдвигать фазу на 3.75 с, а сдвинул на %.3f"
			% d12)\
		.is_equal_approx(150.0 / NodeSignalController.WAVE_SPEED, 1e-3)


func test_green_wave_lets_a_convoy_pass_several_nodes() -> void:
	# Колонна идёт со скоростью волны (40 м/с) — обязана видеть зелёный на
	# всех трёх узлах проспекта подряд.
	var g := _corridor()
	var s := _signals(g, [0, 1, 2])
	var xs := PackedFloat32Array([0.0, 100.0, 250.0])
	var green := 0
	for k in 3:
		# Момент, когда колонна, вышедшая в t=6 с, доезжает до узла k.
		s.time = fposmod(6.0 + xs[k] / NodeSignalController.WAVE_SPEED,
			NodeSignalController.CYCLE)
		# Колонна идёт на восток, значит подъезжает по ЗАПАДНОМУ подходу
		# (направление подхода задано от узла, угол PI).
		if s.is_open_for_cars(k, s.approach_at_angle(k, PI)):
			green += 1
	assert_int(green)\
		.override_failure_message("волна не работает: зелёных %d из 3" % green)\
		.is_equal(3)


# --- Пешеходная фаза ----------------------------------------------------------

## Инвариант `test_pedestrian_green_complements_car_red`, обобщённый на
## произвольный подход узла степени 5.
func test_pedestrian_green_complements_car_red() -> void:
	var g := _star5()
	var s := _signals(g, [0])
	for step in STEPS:
		s.time = step * STEP
		for k in 5:
			assert_bool(s.is_crossing_open(0, k))\
				.override_failure_message("пешеход и машины на подходе %d в t=%.2f" % [k, s.time])\
				.is_equal(s.car_state(0, k) == NodeSignalController.State.RED)


func test_pedestrian_always_gets_green_within_a_cycle() -> void:
	for g: CityGraph in [_tee(), _cross(), _star5()]:
		var s := _signals(g, [0])
		for step in 32:
			s.time = step * 0.5
			for k in g.node_degree(0):
				var wait := s.time_until_crossing_green(0, k)
				assert_float(wait)\
					.override_failure_message(
						"подход %d узла степени %d ждёт зелёного %.2f с при цикле %.1f с"
							% [k, g.node_degree(0), wait, NodeSignalController.CYCLE])\
					.is_between(0.0, NodeSignalController.CYCLE)
				if wait > 0.0:
					assert_bool(s.is_crossing_open(0, k)).is_false()


func test_crossing_green_remaining_counts_down_to_zero() -> void:
	var g := _cross()
	var s := _signals(g, [0])
	# Фаза 0 (север-юг) зелёная 0-6, жёлтая 6-8; пешеходу через северный рукав
	# зелёный горит ровно оставшиеся 8 с цикла.
	s.time = 8.0
	assert_float(s.crossing_green_remaining(0, 0))\
		.override_failure_message("пешеходный зелёный в t=8.0 длится %.2f с вместо 8.0"
			% s.crossing_green_remaining(0, 0))\
		.is_equal_approx(8.0, 1e-4)
	s.time = 15.9
	assert_float(s.crossing_green_remaining(0, 0)).is_equal_approx(0.1, 1e-4)
	s.time = 2.0
	assert_float(s.crossing_green_remaining(0, 0))\
		.override_failure_message("машинам зелёный, а пешеходу насчитано время перехода")\
		.is_equal(0.0)


# --- Кольца и нерегулируемые узлы ---------------------------------------------

## Кольцу светофора не бывает: приоритет там задан правилом уступания
## (`TrafficManager`, `RING_YIELD_DIST`), а не фазами. Проверка стоит здесь,
## а не в доверии к поставщику списка узлов.
func test_ring_node_is_never_regulated() -> void:
	var g := _ring()
	var s := _signals(g, [0])
	assert_bool(s.is_regulated(0))\
		.override_failure_message("узел-кольцо попал под регулирование фазами")\
		.is_false()
	assert_int(s.regulated_nodes().size()).is_equal(0)


func test_low_degree_node_is_never_regulated() -> void:
	# Тупик (степень 1) конфликтующих траекторий не имеет.
	var g := _tee()
	var s := _signals(g, [1])
	assert_bool(s.is_regulated(1))\
		.override_failure_message("тупик степени 1 попал под регулирование")\
		.is_false()


## Нерегулируемый узел (и гейт кольца, id которого вообще за пределами узлов
## города) отвечает зелёным: светофора там нет, приоритет решают правила
## уступания. Пешеходу при этом зелёного не обещают — переход нерегулируемый.
func test_unregulated_node_reports_green_and_no_pedestrian_phase() -> void:
	var g := _cross()
	var s := _signals(g, [])
	assert_int(int(s.car_state(0, 0))).is_equal(int(NodeSignalController.State.GREEN))
	assert_int(int(s.car_state(9999, 0))).is_equal(int(NodeSignalController.State.GREEN))
	assert_bool(s.is_crossing_open(0, 0)).is_false()
	assert_float(s.time_until_crossing_green(0, 0))\
		.override_failure_message("на нерегулируемом узле обещан пешеходный зелёный")\
		.is_equal(INF)


# --- Адресация подхода и линз -------------------------------------------------

## Машина находит свой подход по углу, а не по id ребра: у трафика
## собственное id-пространство рёбер (`TrafficRoadView`).
func test_approach_lookup_by_angle() -> void:
	var g := _cross()
	var s := _signals(g, [0])
	# Углы подходов: 0 — север (-PI/2), 1 — восток (0), 2 — юг (PI/2), 3 — запад.
	assert_int(s.approach_at_angle(0, 0.0)).is_equal(1)
	assert_int(s.approach_at_angle(0, PI * 0.5)).is_equal(2)
	# Небольшой промах по углу обязан попадать в тот же подход.
	assert_int(s.approach_at_angle(0, -PI * 0.5 + 0.2))\
		.override_failure_message("промах в 0.2 рад увёл поиск подхода на соседний")\
		.is_equal(0)


func test_lamp_index_maps_state_to_section() -> void:
	var g := _cross()
	var s := _signals(g, [0])
	s.time = 0.0
	assert_int(s.lamp_index(0, 0)).is_equal(2)
	s.time = 7.0
	assert_int(s.lamp_index(0, 0)).is_equal(1)
	s.time = 12.0
	assert_int(s.lamp_index(0, 0)).is_equal(0)


# --- План стоек ---------------------------------------------------------------

## N стоек по числу подходов вместо жёстких четырёх углов.
func test_plan_puts_one_post_per_approach() -> void:
	for g: CityGraph in [_tee(), _cross(), _star5()]:
		var s := _signals(g, [0])
		var plan := NodeSignalPlan.build(g, s)
		assert_int(plan.post_count())\
			.override_failure_message("у узла степени %d запланировано %d стоек"
				% [g.node_degree(0), plan.post_count()])\
			.is_equal(g.node_degree(0))
		for k in g.node_degree(0):
			assert_int(plan.post_of(0, k))\
				.override_failure_message("подход %d остался без стойки" % k)\
				.is_greater_equal(0)


## Позиции стоек 4-подходного узла обязаны совпасть с четырьмя углами
## осевого планировщика (`CityPlanner._plan_signals`, вынос 8.2 м).
func test_plan_reproduces_axis_corners_on_four_way_node() -> void:
	var plan := NodeSignalPlan.build(_cross(), _signals(_cross(), [0]))
	var off := NodeSignalPlan.SIGNAL_OFFSET
	var expected := [Vector2(off, off), Vector2(off, -off), Vector2(-off, off),
		Vector2(-off, -off)]
	for corner: Vector2 in expected:
		var found := false
		for i in plan.post_count():
			var p := plan.post_pos[i]
			if absf(p.x - corner.x) < 1e-3 and absf(p.z - corner.y) < 1e-3:
				found = true
				break
		assert_bool(found)\
			.override_failure_message("угол (%.1f, %.1f) остался без стойки"
				% [corner.x, corner.y])\
			.is_true()


## Линза адресуется тройкой (узел, подход, секция) — замена осевой тройке
## (перекрёсток, ось, секция).
func test_lens_index_addresses_node_approach_section() -> void:
	var g := _star5()
	var plan := NodeSignalPlan.build(g, _signals(g, [0]))
	var seen := PackedInt32Array()
	for k in 5:
		for section in NodeSignalPlan.SECTIONS:
			var lens := plan.lens_of(0, k, section)
			assert_int(lens)\
				.override_failure_message("линза (узел 0, подход %d, секция %d) не найдена"
					% [k, section])\
				.is_greater_equal(0)
			assert_bool(seen.has(lens))\
				.override_failure_message("линза %d выдана дважды" % lens)\
				.is_false()
			seen.append(lens)
	assert_int(seen.size()).is_equal(5 * NodeSignalPlan.SECTIONS)
	assert_int(plan.lens_of(0, 9, 0))\
		.override_failure_message("несуществующий подход получил линзу")\
		.is_equal(-1)
