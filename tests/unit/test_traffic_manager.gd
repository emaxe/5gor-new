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


func _new_manager(catalog: TrafficCatalog, traffic_count: int, seed_value: int,
		field: CityField, graph: CityGraph,
		lights: TrafficLightController) -> TrafficManager:
	var mgr := TrafficManager.new()
	mgr.setup(catalog, field, graph, lights, SeededRng.new(seed_value), traffic_count)
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


## Кольцо радиусом 30 м из 12 дуг + четыре подходящие улицы.
##
## Кольцо разложено в цепочку коротких рёбер по аннулюсу — решение этапа 6:
## движение по дуге это то же движение по полилинии ребра, третий режим
## движения не нужен, а «уже на кольце» отличается от «въезжаю» видом ребра
## (`CityGraph.EdgeKind.ROUNDABOUT`).
func _ring() -> CityGraph:
	var g := CityGraph.new()
	const R := 30.0
	const SEGMENTS := 12
	for k in SEGMENTS:
		var ang := TAU * float(k) / float(SEGMENTS)
		g.add_node(Vector3(R * cos(ang), 0.0, R * sin(ang)), 0,
			CityGraph.NodeKind.ROUNDABOUT, R)
	for k in SEGMENTS:
		g.add_edge(k, (k + 1) % SEGMENTS, PackedVector3Array(), WIDTH,
			CityGraph.EdgeKind.ROUNDABOUT)
	# Четыре улицы наружу от узлов 0, 3, 6, 9.
	for k in 4:
		var node := k * 3
		var ang := TAU * float(node) / float(SEGMENTS)
		var outer := g.add_node(Vector3(120.0 * cos(ang), 0.0, 120.0 * sin(ang)))
		g.add_edge(node, outer, PackedVector3Array(), WIDTH)
	g.build()
	return g


## Первое ребро вида ROUNDABOUT, инцидентное узлу.
func _ring_edge_at(g: CityGraph, node: int) -> int:
	for k in g.node_degree(node):
		var e := g.approach_edge(node, k)
		if g.edge_kind(e) == CityGraph.EdgeKind.ROUNDABOUT:
			return e
	return -1


# --- Пул --------------------------------------------------------------------

func test_setup_spawns_requested_count_with_guaranteed_police() -> void:
	var field := _default_field()
	var lights := TrafficLightController.new(field)
	var mgr := _new_manager(Db.traffic, Db.balance.traffic_count, 42, field,
		CityGraphGrid.from_field(field), lights)
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
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 1, 2026, field, g,
		TrafficLightController.new(field))
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
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 1, 77, field, g,
		TrafficLightController.new(field))
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
func _place_approaching_red_z(mgr: TrafficManager, g: CityGraph, field: CityField,
		lights: TrafficLightController) -> void:
	const ISEC_INDEX := 1
	var axis_v := field.road_axes[ISEC_INDEX]
	# Ребро вдоль Z, приходящее в (axis_v, axis_v) с юга карты.
	var e := g.query_nearest_edge(Vector3(axis_v, 0.0, axis_v - 25.0), 20.0)
	mgr.place_on_edge(0, e, g.edge_length(e) - 25.0, 1.0)
	mgr.speed[0] = 10.0
	mgr.target[0] = 10.0
	mgr.run_red[0] = 0
	# Ось Z красная 8..16 в локальном времени перекрёстка (citygen.js:3034).
	lights.time = fposmod(9.8 - lights.phase_offset(ISEC_INDEX), TrafficLightController.CYCLE)


func test_non_aggressive_car_stops_at_red_light() -> void:
	var field := _default_field()
	var g := CityGraphGrid.from_field(field)
	var lights := TrafficLightController.new(field)
	var cat := _single_type_catalog(0.0, 0.3)
	var mgr := _new_manager(cat, 1, 5, field, g, lights)
	mgr.place_all_near(0.0, 0.0)
	_place_approaching_red_z(mgr, g, field, lights)

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
	var lights := TrafficLightController.new(field)
	# aggressive_ratio=1 и red_light_run_chance=1 — детерминированно проезжает,
	# перекрёсток пуст (единственная машина в пуле), значит проезд гарантирован.
	var cat := _single_type_catalog(1.0, 1.0)
	var mgr := _new_manager(cat, 1, 7, field, g, lights)
	mgr.place_all_near(0.0, 0.0)
	_place_approaching_red_z(mgr, g, field, lights)
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
	var lights := TrafficLightController.new(field)
	var mgr := _new_manager(Db.traffic, Db.balance.traffic_count, 11, field, g, lights)
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
func test_update_fits_frame_budget_at_triple_density() -> void:
	var field := _default_field()
	var g := CityGraphGrid.from_field(field)
	var lights := TrafficLightController.new(field)
	var triple := Db.balance.traffic_count * 3
	var mgr := _new_manager(Db.traffic, triple, 9, field, g, lights)
	mgr.place_all_near(0.0, 0.0)

	var t0 := Time.get_ticks_usec()
	for _i in 60:
		mgr.update(DT, 0.0, 0.0, 1.0)
	var us := Time.get_ticks_usec() - t0
	var per_tick_ms := (us / 1000.0) / 60.0
	# Порог — под headless-интерпретатор GDScript в debug-сборке (медленнее
	# экспортированного релиза в разы); цель теста — поймать O(n²)-регресс
	# бакетизации, а не мерить финальный кадровый бюджет.
	assert_float(per_tick_ms)\
		.override_failure_message("апдейт трафика (%d машин) занял %.3f мс/тик"
			% [triple, per_tick_ms])\
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
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 3, 31, field, g,
		TrafficLightController.new(field))
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
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 1, 13, field, g,
		TrafficLightController.new(field))
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


# --- Кольцо -----------------------------------------------------------------

## Кольцо как цепочка дуг: машина продвигается по нему тем же кодом, что и по
## улице, и не запирается на стыках дуг.
func test_car_drives_around_ring() -> void:
	var field := _default_field()
	var g := _ring()
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 1, 5, field, g,
		TrafficLightController.new(field))
	var ring_edge := _ring_edge_at(g, 1)
	mgr.place_on_edge(0, ring_edge, 1.0, 1.0)
	mgr.speed[0] = 7.0

	var arcs := PackedInt32Array()
	var stalled := 0.0
	var worst_stall := 0.0
	for _i in 1800:
		mgr.update(DT, 0.0, 0.0, 1.0)
		var e := mgr.edge_id[0]
		if g.edge_kind(e) == CityGraph.EdgeKind.ROUNDABOUT and not arcs.has(e):
			arcs.append(e)
		if mgr.speed_of(0) < 0.5:
			stalled += DT
			worst_stall = maxf(worst_stall, stalled)
		else:
			stalled = 0.0

	assert_int(arcs.size())\
		.override_failure_message("машина прошла %d дуг кольца из 12 — движение по кольцу не работает"
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
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 2, 17, field, g,
		TrafficLightController.new(field))
	# Машина 0 — на дуге вплотную к узлу 0, машина 1 — на улице, въезжает.
	var arc := _ring_edge_at(g, 0)
	mgr.place_on_edge(0, arc, g.edge_length(arc) * 0.5, 1.0)
	mgr.speed[0] = 6.0
	var street := -1
	for k in g.node_degree(0):
		var e := g.approach_edge(0, k)
		if g.edge_kind(e) != CityGraph.EdgeKind.ROUNDABOUT:
			street = e
	# Улица идёт от узла 0 наружу, значит въезд — движение в обратную сторону.
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


# --- Watchdog и приборы -----------------------------------------------------

## Watchdog деадлока: машина, простоявшая у узла дольше 8 с, переставляется
## за пределы видимости, а не остаётся пробкой навсегда.
func test_deadlock_watchdog_respawns_stuck_car() -> void:
	var field := _default_field()
	var g := CityGraphGrid.from_field(field)
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 1, 21, field, g,
		TrafficLightController.new(field))
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
	var lights := TrafficLightController.new(field)
	var mgr := _new_manager(_single_type_catalog(0.0, 0.0), 1, 3, field, g, lights)
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
