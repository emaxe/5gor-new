extends GdUnitTestSuite
## Трафик — 10 правил ИИ traffic.js поверх SoA-массивов и `CityGraph`.
## Тесты сверяют то, что не видно глазом: пул со спецтранспортом,
## распределение поворотов 58/22/20 на реальном 4-подходном узле, торможение
## перед красным для законопослушных, проезд на красный только для
## агрессивных на пустом перекрёстке, границы карты, бюджет апдейта при
## тройной плотности — и то, чего в рельсовой модели не было вовсе: проезд
## узла степени 5, движение по кольцу с уступанием на въезде и разворот на
## тупике без понятия «ось».

const DT := 1.0 / 60.0
## Ширина полотна синтетических графов, м (проспект оригинала).
const WIDTH := 12.0
## Радиус кольца в фикстуре, м — порядок настоящих колец Пятигорска (16-22).
const RING_RADIUS := 20.0


## `signal_nodes` пуст по умолчанию: у синтетических графов (крест, звезда,
## кольцо) светофоров нет, и правило 10 в них не участвует. Сеточные сценарии
## передают список регулируемых узлов сетки — те же перекрёстки, что
## регулировала осевая модель.
##
## Контроллер светофоров строится здесь же и живёт в `mgr.signals`: с этапа 9
## менеджер его не собирает, а получает готовым от города — тестам достаётся
## та же роль владельца часов, что живому `World`.
func _new_manager(catalog: TrafficCatalog, traffic_count: int, seed_value: int,
		graph: CityGraph,
		signal_nodes: PackedInt32Array = PackedInt32Array()) -> TrafficManager:
	var mgr := TrafficManager.new()
	mgr.setup(catalog, graph, NodeSignalController.build(graph, signal_nodes),
		SeededRng.new(seed_value), traffic_count)
	return mgr


func _default_field() -> CityField:
	return CityField.new(Db.balance)


## Мини-каталог с одним типом — для сценариев, где важна детерминированная
## агрессивность/шанс проезда на красный, а не реальные 20 типов трафика.
func _single_type_catalog(aggressive_ratio: float, red_chance: float) -> TrafficCatalog:
	var t := TrafficTypeData.new()
	t.id = &"sedan"
	t.silhouette = &"sedan"
	t.radius = 2.0
	t.length = 4.4
	t.width = 1.9
	t.weight = 1.0
	t.colors = PackedColorArray([Color.WHITE])
	var cat := TrafficCatalog.new()
	cat.items = [t]
	cat.aggressive_ratio = aggressive_ratio
	cat.red_light_run_chance = red_chance
	cat.index()
	return cat


# --- Синтетические графы ----------------------------------------------------

## Обычный 4-подходный перекрёсток: центр (узел 0) и четыре тупика.
## Рёбра: 0 — на восток, 1 — на юг (+Z), 2 — на запад, 3 — на север (-Z).
func _cross() -> CityGraph:
	var g := CityGraph.new()
	var c := g.add_node(Vector3.ZERO)
	var e := g.add_node(Vector3(120.0, 0.0, 0.0))
	var s := g.add_node(Vector3(0.0, 0.0, 120.0))
	var w := g.add_node(Vector3(-120.0, 0.0, 0.0))
	var n := g.add_node(Vector3(0.0, 0.0, -120.0))
	g.add_edge(c, e, PackedVector3Array(), WIDTH)
	g.add_edge(c, s, PackedVector3Array(), WIDTH)
	g.add_edge(c, w, PackedVector3Array(), WIDTH)
	g.add_edge(c, n, PackedVector3Array(), WIDTH)
	g.build()
	return g


## Звезда из пяти лучей: узел 0 степени 5, пять тупиков степени 1.
## Пять лучей, а не четыре, — именно тот случай, который рельсовая модель
## (две оси, три исхода поворота) не умела выразить в принципе.
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


## Кольцо той формы, которую реально строит генератор города: ОДИН узел
## `NodeKind.ROUNDABOUT` с радиусом и четыре обычных улицы-подхода — как
## `pir_rynok` (r=16), `kir_vokzal` (r=22), `kal_s2` (r=18) в топологии
## Пятигорска. Разворачивать его в дуги — задача `TrafficRoadView`, а не
## поставщика графа: форма «один узел» нужна мешеру и правилам этапов 4, 7, 8.
func _ring() -> CityGraph:
	var g := CityGraph.new()
	var hub := g.add_node(Vector3.ZERO, 0, CityGraph.NodeKind.ROUNDABOUT, RING_RADIUS)
	for k in 4:
		var ang := TAU * float(k) / 4.0
		var outer := g.add_node(Vector3(120.0 * cos(ang), 0.0, 120.0 * sin(ang)))
		g.add_edge(hub, outer, PackedVector3Array(), WIDTH)
	g.build()
	return g


## Первая дуга кольца среди рёбер производного вида, инцидентная гейту,
## к которому подходит улица `street_hint` (точка в мире рядом с гейтом).
func _arc_near(mgr: TrafficManager, x: float, z: float) -> int:
	var best := -1
	var best_d := INF
	for e in mgr.graph.edge_count():
		if not mgr.is_arc(e):
			continue
		var mid := mgr.graph.edge_point(e, 0)
		var d := MathUtils.dist_2d(mid.x, mid.z, x, z)
		if d < best_d:
			best_d = d
			best = e
	return best


# --- Пул --------------------------------------------------------------------

func test_setup_spawns_requested_count_with_guaranteed_police() -> void:
	var field := _default_field()
	var mgr := _new_manager(Db.traffic, Db.balance.traffic_count, 42,
		CityGraphGrid.from_field(field), CityGraphGrid.signalized_nodes(field))
	mgr.place_all_near(0.0, 0.0)

	assert_int(mgr.count).is_equal(Db.balance.traffic_count)
	var has_police := false
	for i in mgr.count:
		if mgr.type_of(i).id == &"police":
			has_police = true
			break
	assert_bool(has_police)\
		.override_failure_message("в пуле трафика нет ни одной патрульной машины")\
		.is_true()


# --- Выбор направления ------------------------------------------------------

## Веса классов «прямо/направо/налево» на реальном узле обязаны дать то же
## распределение, что жёсткая таблица оригинала (traffic.js:590-592):
## 58% прямо, 22% направо, 20% налево. На 4-подходном узле в каждом классе
## ровно один кандидат, поэтому числа обязаны совпасть точно, а не «примерно
## по духу».
func test_turn_choice_matches_original_split() -> void:
	var field := _default_field()
	var g := _cross()
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 1, 2026, g)
	# Машина едет с запада к центру: ребро 2 (центр -> запад) в обратную сторону.
	mgr.place_on_edge(0, 2, 10.0, -1.0)

	var straight := 0
	var right := 0
	var left := 0
	var trials := 8000
	for _k in trials:
		var k := mgr._roll_exit(0, 0)
		if k == mgr._straight_idx:
			straight += 1
		elif mgr._cand_dev[k] < 0.0:
			right += 1
		else:
			left += 1

	assert_float(float(straight) / trials)\
		.override_failure_message("прямо: %.3f вместо 0.58" % (float(straight) / trials))\
		.is_between(0.55, 0.61)
	assert_float(float(right) / trials)\
		.override_failure_message("направо: %.3f вместо 0.22" % (float(right) / trials))\
		.is_between(0.19, 0.25)
	assert_float(float(left) / trials)\
		.override_failure_message("налево: %.3f вместо 0.20" % (float(left) / trials))\
		.is_between(0.17, 0.23)


## На узле степени 5 доступны все четыре исхода (кроме разворота), и ни один
## из них не «съедает» весь вес: вырожденное распределение означало бы, что
## машины ходят по звезде одним и тем же маршрутом.
func test_degree_five_node_offers_every_exit() -> void:
	var field := _default_field()
	var g := _star5()
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 1, 77, g)
	assert_int(g.node_degree(0))\
		.override_failure_message("центр звезды должен иметь степень 5, получено %d"
			% g.node_degree(0))\
		.is_equal(5)
	mgr.place_on_edge(0, 0, 10.0, -1.0)

	var hits := PackedInt32Array()
	hits.resize(4)
	for _k in 4000:
		var k := mgr._roll_exit(0, 0)
		hits[k] += 1
	for k in 4:
		assert_int(hits[k])\
			.override_failure_message("исход %d узла степени 5 не выпал ни разу из 4000"
				% k)\
			.is_greater(0)


# --- Светофор ---------------------------------------------------------------

## Ставит одну машину на подъезде к перекрёстку (1,1) — обе координаты
## нечётные, значит регулируемый (PedGraph.is_signalized) — и выставляет
## на нём красный для оси Z.
func _place_approaching_red_z(mgr: TrafficManager, g: CityGraph,
		field: CityField) -> void:
	const ISEC_INDEX := 1
	var axis_v := field.road_axes[ISEC_INDEX]
	# Ребро вдоль Z, приходящее в (axis_v, axis_v) с юга карты.
	var e := g.query_nearest_edge(Vector3(axis_v, 0.0, axis_v - 25.0), 20.0)
	mgr.place_on_edge(0, e, g.edge_length(e) - 25.0, 1.0)
	mgr.speed[0] = 10.0
	mgr.target[0] = 10.0
	mgr.run_red[0] = 0
	# Ось Z красная 8..16 в локальном времени перекрёстка (citygen.js:3034).
	# Узлы сетки нумеруются i * 9 + j (`CityGraphGrid.from_field`), а фазы
	# узловой модели на сетке совпадают с осевыми (тест паритета этапа 7).
	var node := ISEC_INDEX * field.road_axes.size() + ISEC_INDEX
	mgr.signals.time = fposmod(9.8 - mgr.signals.phase_offset(node),
		NodeSignalController.CYCLE)


func test_non_aggressive_car_stops_at_red_light() -> void:
	var field := _default_field()
	var g := CityGraphGrid.from_field(field)
	var cat := _single_type_catalog(0.0, 0.3)
	var mgr := _new_manager(cat, 1, 5, g, CityGraphGrid.signalized_nodes(field))
	mgr.place_all_near(0.0, 0.0)
	_place_approaching_red_z(mgr, g, field)

	var stop_line := field.road_axes[1] - TrafficManager.STOP_LINE
	# Игрок рядом (не респавнит машину), но вбок — не мешает через правило 9.
	var player_x := mgr.world_x(0) + 10.0
	var player_z := mgr.world_z(0)
	for _i in 300:
		mgr.update(DT, player_x, player_z, 1.0)

	assert_float(mgr.world_z(0))\
		.override_failure_message("машина проехала на красный: z=%.2f, стоп-линия=%.2f"
			% [mgr.world_z(0), stop_line])\
		.is_less(stop_line)
	assert_float(mgr.speed_of(0))\
		.override_failure_message("машина не остановилась: скорость=%.2f" % mgr.speed_of(0))\
		.is_less(0.5)


## Зеркало предыдущего теста: агрессивная машина обязана пересечь стоп-линию.
## Проверяется именно она, а не выезд за перекрёсток: на графе за узлом
## машина может уйти в любое из его рёбер, и «проехал прямо» — уже про выбор
## направления, а не про светофор.
func test_aggressive_car_runs_clear_red_light() -> void:
	var field := _default_field()
	var g := CityGraphGrid.from_field(field)
	# aggressive_ratio=1 и red_light_run_chance=1 — детерминированно проезжает,
	# перекрёсток пуст (единственная машина в пуле), значит проезд гарантирован.
	var cat := _single_type_catalog(1.0, 1.0)
	var mgr := _new_manager(cat, 1, 7, g, CityGraphGrid.signalized_nodes(field))
	mgr.place_all_near(0.0, 0.0)
	_place_approaching_red_z(mgr, g, field)
	assert_int(mgr.aggressive[0])\
		.override_failure_message("машина должна быть агрессивной для этого сценария")\
		.is_equal(1)

	var stop_line := field.road_axes[1] - TrafficManager.STOP_LINE
	var player_x := mgr.world_x(0) + 10.0
	var player_z := mgr.world_z(0)
	for _i in 300:
		mgr.update(DT, player_x, player_z, 1.0)

	assert_float(mgr.world_z(0))\
		.override_failure_message("агрессивная машина не пересекла стоп-линию: z=%.2f, стоп-линия=%.2f"
			% [mgr.world_z(0), stop_line])\
		.is_greater(stop_line)


# --- Границы и бюджет -------------------------------------------------------

func test_cars_stay_within_map_bounds_over_time() -> void:
	var field := _default_field()
	var g := CityGraphGrid.from_field(field)
	var mgr := _new_manager(Db.traffic, Db.balance.traffic_count, 11, g, CityGraphGrid.signalized_nodes(field))
	mgr.place_all_near(0.0, 0.0)

	for _step in 900:
		mgr.update(DT, 0.0, 0.0, 1.0)
		for c in mgr.count:
			assert_float(maxf(absf(mgr.world_x(c)), absf(mgr.world_z(c))))\
				.override_failure_message("машина %d выехала за карту: (%.1f, %.1f)"
					% [c, mgr.world_x(c), mgr.world_z(c)])\
				.is_less(270.0)


## Бакетизация по (edge_id, отрезок t) обязана держать апдейт в бюджете даже
## при тройной плотности (архитектура: «выдержать рост плотности до ×3»).
##
## Замеряется МИНИМУМ из трёх серий после прогревочной, а не одиночный
## прогон. Порог и плотность прежние — меняется только оценка: цель теста
## поймать алгоритмический регресс (он виден в каждой серии), а не поймать
## соседний процесс на той же машине. Проект собирают параллельные сессии
## Godot, и одиночный замер краснел от чужой нагрузки, а не от кода.
func test_update_fits_frame_budget_at_triple_density() -> void:
	var field := _default_field()
	var g := CityGraphGrid.from_field(field)
	var triple := Db.balance.traffic_count * 3
	var mgr := _new_manager(Db.traffic, triple, 9, g, CityGraphGrid.signalized_nodes(field))
	mgr.place_all_near(0.0, 0.0)

	var best := INF
	for round_index in 4:
		var t0 := Time.get_ticks_usec()
		for _i in 60:
			mgr.update(DT, 0.0, 0.0, 1.0)
		if round_index == 0:
			continue
		best = minf(best, ((Time.get_ticks_usec() - t0) / 1000.0) / 60.0)

	# Порог — под headless-интерпретатор GDScript в debug-сборке (медленнее
	# экспортированного релиза в разы); цель теста — поймать O(n²)-регресс
	# бакетизации, а не мерить финальный кадровый бюджет.
	assert_float(best)\
		.override_failure_message("апдейт трафика (%d машин) занял %.3f мс/тик"
			% [triple, best])\
		.is_less(10.0)


# --- Проезд узлов произвольной степени --------------------------------------

## Критерий готовности этапа: машины реально проезжают узел степени 5 и не
## застревают на нём. Три машины съезжаются к центру звезды с разных лучей —
## это заодно проверяет уступание на узле, которого рельсовая модель для
## пяти подходов выразить не умела. Лучи — тупики, поэтому маршрут неизбежно
## возвращает машины в центр снова и снова.
func test_cars_cross_degree_five_node() -> void:
	var field := _default_field()
	var g := _star5()
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 3, 31, g)
	for c in 3:
		mgr.place_on_edge(c, c * 2, 100.0, -1.0)
		mgr.speed[c] = 8.0

	# Игрок в стороне от лучей, но в пределах RESPAWN_DIST: в центре звезды он
	# тормозил бы машины правилом 9 на каждом проезде узла.
	const PLAYER_X := 0.0
	const PLAYER_Z := 60.0
	var visited := PackedInt32Array()
	var stalled := PackedFloat32Array()
	stalled.resize(3)
	var worst_stall := 0.0
	for _i in 6000:
		mgr.update(DT, PLAYER_X, PLAYER_Z, 1.0)
		for c in 3:
			if not visited.has(mgr.edge_id[c]):
				visited.append(mgr.edge_id[c])
			if mgr.speed_of(c) < 0.5:
				stalled[c] += DT
				worst_stall = maxf(worst_stall, stalled[c])
			else:
				stalled[c] = 0.0

	assert_int(visited.size())\
		.override_failure_message("за 100 с машины побывали на %d лучах звезды из 5 — узел степени 5 не проезжается"
			% visited.size())\
		.is_greater_equal(4)
	# Порог — время срабатывания watchdog'а (5.5 с): три машины, съезжающиеся
	# в одну точку, по правилу 8 действительно ждут друг друга, но обязаны
	# разъехаться сами, без аварийного вмешательства.
	assert_float(worst_stall)\
		.override_failure_message("машина стояла подряд %.1f с — узел степени 5 её запирает"
			% worst_stall)\
		.is_less(5.5)


## Разворот на тупике: у луча звезды нет продолжения, машина обязана
## развернуться на своём ребре — понятия «ось» в этом больше нет.
func test_uturn_at_dead_end_stays_on_edge() -> void:
	var field := _default_field()
	var g := _star5()
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 1, 13, g)
	# Едем от центра к тупику: ребро 0 идёт центр -> луч, значит dir = +1.
	mgr.place_on_edge(0, 0, 100.0, 1.0)
	mgr.speed[0] = 8.0

	var flipped := false
	for _i in 900:
		mgr.update(DT, 0.0, 0.0, 1.0)
		if mgr.dir_along[0] < 0.0:
			flipped = true
			break

	assert_bool(flipped)\
		.override_failure_message("машина не развернулась на тупике за 15 с")\
		.is_true()
	assert_int(mgr.edge_id[0])\
		.override_failure_message("разворот увёл машину с её ребра: edge=%d вместо 0"
			% mgr.edge_id[0])\
		.is_equal(0)


## Встречная машина на продолжении той же улицы — не поперечная. Прежняя
## модель отсекала её признаком «та же ось»; на графе ребро по ту сторону узла
## имеет другой id, и без явной проверки коллинеарности пара встречных машин
## в 4 м от перекрёстка останавливала друг друга до срабатывания watchdog'а.
func test_oncoming_cars_do_not_block_each_other() -> void:
	var field := _default_field()
	var g := CityGraphGrid.from_field(field)
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 2, 23, g, CityGraphGrid.signalized_nodes(field))
	# Перекрёсток (0, 0) — обе координаты чётные, значит нерегулируемый.
	var south := mgr.graph.query_nearest_edge(Vector3(0.0, 0.0, -20.0), 20.0)
	var north := mgr.graph.query_nearest_edge(Vector3(0.0, 0.0, 20.0), 20.0)
	mgr.place_on_edge(0, south, mgr.graph.edge_length(south) - 4.0, 1.0)
	mgr.place_on_edge(1, north, 4.0, -1.0)
	for c in 2:
		mgr.speed[c] = 8.0
		mgr.target[c] = 8.0

	# Игрок сбоку: в 60 м по X он не попадает ни в правило 9, ни в респавн.
	mgr.update(DT, 60.0, 0.0, 1.0)

	assert_float(mgr.target[0])\
		.override_failure_message("машина 0 остановилась перед встречной: цель скорости %.2f"
			% mgr.target[0])\
		.is_greater(0.0)
	assert_float(mgr.target[1])\
		.override_failure_message("машина 1 остановилась перед встречной: цель скорости %.2f"
			% mgr.target[1])\
		.is_greater(0.0)


# --- Кольцо -----------------------------------------------------------------

## Развёртка узла-кольца в проезжую полосу: подходы подрезаны до окружности,
## гейты соединены дугами, к самому узлу-кольцу не подходит ничего. Тест
## структурный — он ловит именно то, чего не поймала бы езда: молчаливое
## вырождение кольца в обычный перекрёсток.
func test_roundabout_hub_expands_into_arcs() -> void:
	var g := _ring()
	var view := TrafficRoadView.build(g)

	var arcs := 0
	var touches_hub := 0
	for e in view.graph.edge_count():
		if view.arc[e] == 1:
			arcs += 1
			assert_int(view.one_way[e])\
				.override_failure_message("дуга %d должна быть односторонней" % e)\
				.is_equal(1)
		var ends := view.graph.edge_ends(e)
		if ends.x == 0 or ends.y == 0:
			touches_hub += 1
	assert_int(arcs)\
		.override_failure_message("у кольца с четырьмя подходами ожидалось 4 дуги, получено %d"
			% arcs)\
		.is_equal(4)
	assert_int(touches_hub)\
		.override_failure_message("к узлу-кольцу не должно подходить ни одно ребро вида, подходит %d"
			% touches_hub)\
		.is_equal(0)

	# Подход длиной 120 м подрезан ровно на радиус.
	var street := view.graph.query_nearest_edge(Vector3(80.0, 0.0, 0.0), 20.0)
	assert_float(view.graph.edge_length(street))\
		.override_failure_message("подход 120 м при радиусе %.0f должен стать 100 м, получено %.2f"
			% [RING_RADIUS, view.graph.edge_length(street)])\
		.is_equal_approx(120.0 - RING_RADIUS, 0.05)


## Дуги проходятся в сторону правостороннего движения: центр кольца обязан
## оставаться слева от машины. Проверяется по геометрии дуги, а не по езде —
## ошибка знака здесь дала бы формально работающее, но встречное кольцо.
func test_ring_arcs_run_clockwise_for_right_hand_traffic() -> void:
	var g := _ring()
	var view := TrafficRoadView.build(g)
	for e in view.graph.edge_count():
		if view.arc[e] != 1:
			continue
		var p0 := view.graph.edge_point(e, 0)
		var p1 := view.graph.edge_point(e, 1)
		var fx := p1.x - p0.x
		var fz := p1.z - p0.z
		# Левая нормаль к курсу (Heading.lateral со знаком минус) — (fz, -fx).
		var to_center_x := -p0.x
		var to_center_z := -p0.z
		assert_float(fz * to_center_x - fx * to_center_z)\
			.override_failure_message("дуга %d идёт против правостороннего движения: центр справа" % e)\
			.is_greater(0.0)


## Кольцо как цепочка дуг: машина продвигается по нему тем же кодом, что и по
## улице, и не запирается на стыках дуг.
func test_car_drives_around_ring() -> void:
	var field := _default_field()
	var g := _ring()
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 1, 5, g)
	var ring_edge := _arc_near(mgr, RING_RADIUS, 0.0)
	mgr.place_on_edge(0, ring_edge, 1.0, 1.0)
	mgr.speed[0] = 7.0

	var arcs := PackedInt32Array()
	var stalled := 0.0
	var worst_stall := 0.0
	# 100 с, а не 30: машина не наматывает круги без остановки — на каждом
	# гейте у неё 42% шанс съехать на улицу, доехать до её тупика,
	# развернуться и вернуться на кольцо. Круг должен набраться из этого.
	for _i in 6000:
		mgr.update(DT, 0.0, 0.0, 1.0)
		var e := mgr.edge_id[0]
		if mgr.is_arc(e) and not arcs.has(e):
			arcs.append(e)
		if mgr.speed_of(0) < 0.5:
			stalled += DT
			worst_stall = maxf(worst_stall, stalled)
		else:
			stalled = 0.0

	assert_int(arcs.size())\
		.override_failure_message("машина прошла %d дуг кольца из 4 — движение по кольцу не работает"
			% arcs.size())\
		.is_greater_equal(3)
	assert_float(worst_stall)\
		.override_failure_message("машина стояла на кольце подряд %.1f с" % worst_stall)\
		.is_less(3.0)


## Уступание на въезде: тот, кто уже на дуге, имеет приоритет перед тем, кто
## подъезжает по улице. Базовая версия правила — тонкая настройка на этапе 7.
func test_car_entering_ring_yields_to_car_on_arc() -> void:
	var field := _default_field()
	var g := _ring()
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 2, 17, g)
	# Гейт улицы, идущей на восток, лежит в (RING_RADIUS, 0).
	var arc := _arc_near(mgr, RING_RADIUS, 0.0)
	mgr.place_on_edge(0, arc, mgr.graph.edge_length(arc) * 0.4, 1.0)
	mgr.speed[0] = 6.0
	# Машина 1 — на восточной улице, въезжает: улица идёт от гейта наружу,
	# значит въезд это движение в обратную сторону.
	var street := mgr.graph.query_nearest_edge(Vector3(80.0, 0.0, 0.0), 20.0)
	mgr.place_on_edge(1, street, 4.0, -1.0)
	mgr.speed[1] = 6.0
	mgr.target[1] = 6.0

	# Игрок в центре кольца: дальше RESPAWN_DIST обе машины просто переставило бы.
	mgr.update(DT, 0.0, 0.0, 1.0)

	assert_float(mgr.target[1])\
		.override_failure_message("въезжающая машина не уступила кольцу: цель скорости %.2f"
			% mgr.target[1])\
		.is_equal_approx(0.0, 0.001)
	# Вторая половина того же правила: машина на дуге НЕ пропускает того, кто
	# ждёт на въезде. Без неё обе встали бы насмерть — въезжающий стоит внутри
	# обычной проверки «поперечная машина на узле».
	assert_float(mgr.target[0])\
		.override_failure_message("машина на кольце уступила въезжающей: цель скорости %.2f"
			% mgr.target[0])\
		.is_greater(0.0)


## Критерий готовности этапа 7 для колец: светофоров там нет вовсе, весь
## приоритет держит правило уступания, — и под нагрузкой оно обязано остаться
## живым. Восемь машин: по одной на каждой из четырёх дуг и по одной,
## въезжающей с каждой из четырёх улиц, то есть уступать приходится
## одновременно на всех четырёх гейтах.
##
## Порог простоя — 5.5 с, время срабатывания watchdog'а: если хоть одна машина
## его достигла, кольцо встало намертво и трафик спасает не правило, а
## переброс застрявшего.
func test_ring_stays_live_under_load() -> void:
	var field := _default_field()
	var g := _ring()
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 8, 41, g)
	var arcs := PackedInt32Array()
	var streets := PackedInt32Array()
	for e in mgr.graph.edge_count():
		if mgr.is_arc(e):
			arcs.append(e)
		else:
			streets.append(e)
	assert_int(arcs.size())\
		.override_failure_message("у кольца с четырьмя подходами должно быть 4 дуги, а не %d"
			% arcs.size())\
		.is_equal(4)

	for k in 4:
		mgr.place_on_edge(k, arcs[k], mgr.graph.edge_length(arcs[k]) * 0.35, 1.0)
		mgr.speed[k] = 6.0
		mgr.target[k] = 6.0
		# Улица идёт от гейта наружу, значит въезд — движение в обратную сторону.
		mgr.place_on_edge(4 + k, streets[k], 6.0, -1.0)
		mgr.speed[4 + k] = 6.0
		mgr.target[4 + k] = 6.0

	var stalled := PackedFloat32Array()
	stalled.resize(8)
	var worst_stall := 0.0
	var travelled := PackedFloat32Array()
	travelled.resize(8)
	var prev_x := PackedFloat32Array()
	var prev_z := PackedFloat32Array()
	prev_x.resize(8)
	prev_z.resize(8)
	for c in 8:
		prev_x[c] = mgr.world_x(c)
		prev_z[c] = mgr.world_z(c)

	# 15 с при 60 Гц: почти три полных цикла светофора и заведомо больше
	# порога watchdog'а.
	for _step in 900:
		mgr.update(DT, 0.0, 0.0, 1.0)
		for c in 8:
			travelled[c] += MathUtils.dist_2d(prev_x[c], prev_z[c],
				mgr.world_x(c), mgr.world_z(c))
			prev_x[c] = mgr.world_x(c)
			prev_z[c] = mgr.world_z(c)
			if mgr.speed_of(c) < 0.5:
				stalled[c] += DT
				worst_stall = maxf(worst_stall, stalled[c])
			else:
				stalled[c] = 0.0

	assert_float(worst_stall)\
		.override_failure_message("на кольце машина простояла подряд %.1f с — уступание встало намертво"
			% worst_stall)\
		.is_less(5.5)
	for c in 8:
		assert_float(travelled[c])\
			.override_failure_message("машина %d за 15 с прошла %.1f м — кольцо её не пропустило"
				% [c, travelled[c]])\
			.is_greater(30.0)


# --- Watchdog и приборы -----------------------------------------------------

## Watchdog деадлока: машина, простоявшая у узла дольше 8 с, переставляется
## за пределы видимости, а не остаётся пробкой навсегда.
func test_deadlock_watchdog_respawns_stuck_car() -> void:
	var field := _default_field()
	var g := CityGraphGrid.from_field(field)
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 1, 21, g, CityGraphGrid.signalized_nodes(field))
	# Ребро у центра карты: подъезд к узлу (0, 0) с юга.
	var e := g.query_nearest_edge(Vector3(0.0, 0.0, -20.0), 20.0)
	mgr.place_on_edge(0, e, g.edge_length(e) - 3.0, 1.0)
	mgr.speed[0] = 0.0
	mgr.stuck_t[0] = 8.0 - DT * 0.5

	var before_x := mgr.world_x(0)
	var before_z := mgr.world_z(0)
	mgr.update(DT, 0.0, 0.0, 1.0)
	var moved := MathUtils.dist_2d(before_x, before_z, mgr.world_x(0), mgr.world_z(0))

	assert_float(moved)\
		.override_failure_message("застрявшая машина не была переставлена: сместилась на %.2f м"
			% moved)\
		.is_greater(40.0)
	assert_float(MathUtils.dist_2d(mgr.world_x(0), mgr.world_z(0), 0.0, 0.0))\
		.override_failure_message("машина переставлена в поле зрения игрока")\
		.is_greater_equal(75.0)


## Свет машин зажигается сменой материала по этим accessor'ам
## (world/traffic/traffic_layer.gd:tick) — стоп-сигнал от торможения,
## поворотники от знака угловой скорости на общем таймере мигания.
func test_lamp_accessors_derive_from_kinematics() -> void:
	var field := _default_field()
	var g := CityGraphGrid.from_field(field)
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 1, 3, g, CityGraphGrid.signalized_nodes(field))
	mgr.place_all_near(0.0, 0.0)

	mgr.accel_val[0] = -2.0
	assert_bool(mgr.is_braking(0))\
		.override_failure_message("заметное замедление обязано зажечь стоп")\
		.is_true()
	mgr.accel_val[0] = 0.0
	assert_bool(mgr.is_braking(0)).is_false()

	mgr.turning[0] = 1
	mgr.turn_blink_on = true
	mgr.angular_vel[0] = -1.0
	assert_bool(mgr.turn_a_on(0)).is_true()
	assert_bool(mgr.turn_b_on(0)).is_false()

	mgr.angular_vel[0] = 1.0
	assert_bool(mgr.turn_a_on(0)).is_false()
	assert_bool(mgr.turn_b_on(0)).is_true()

	mgr.turning[0] = 0
	assert_bool(mgr.turn_a_on(0))\
		.override_failure_message("вне манёвра поворотник обязан гаснуть")\
		.is_false()
	assert_bool(mgr.turn_b_on(0)).is_false()

	mgr.turning[0] = 1
	mgr.turn_blink_on = false
	assert_bool(mgr.turn_b_on(0))\
		.override_failure_message("на выключенной фазе мигания поворотник обязан гаснуть")\
		.is_false()
