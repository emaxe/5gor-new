extends GdUnitTestSuite
## Граф ходьбы — основа ПДД для пешеходов. Главный инвариант, унаследованный
## из регрессий проекта capital: НИ ОДИН участок маршрута без гейта не должен
## пересекать проезжую часть. Если он нарушен, пешеходы срезают через дорогу
## мимо перехода, и никакая логика ожидания зелёного это не исправит.
##
## После перехода на явный граф (этап 8) инвариант проверяется общей
## геометрией «отрезок против полилинии ребра», а не коридором вокруг оси:
## у произвольного графа осей нет.

## Узел сетки 9x9 в нумерации `CityGraphGrid.from_field()`.
const GRID := 9
## Подходы узла упорядочены по возрастанию atan2(dz, dx): север (-Z) идёт
## первым, дальше восток, юг, запад. На внутреннем узле сетки это 0..3.
const N := 0
const E := 1
const S := 2
const W := 3

var _field: CityField
var _graph: PedGraph
## Тот же граф улиц, из которого PedGraph строит тротуары.
var _street: CityGraph


func before() -> void:
	_field = CityField.new(Db.balance)
	_graph = PedGraph.new(_field)
	_street = CityGraphGrid.from_field(_field)


static func _node_id(i: int, j: int) -> int:
	return i * GRID + j


# --- Структура --------------------------------------------------------------

func test_node_count_matches_layout() -> void:
	# Углов ровно столько, сколько подходов у всех узлов: 2 * 144 ребра = 288.
	# Плюс по два серединных узла на ребро — ещё 288.
	assert_int(_graph.node_count())\
		.override_failure_message("узлов в графе %d, ожидалось 576"
			% _graph.node_count())\
		.is_equal(576)


func test_corner_count_follows_node_degree() -> void:
	# Ключевое отличие от сеточной версии: углов столько, сколько подходов,
	# а не всегда четыре. Углы узла лежат подряд, поэтому их число — это
	# расстояние до первого угла следующего узла.
	for node in _street.node_count():
		var next_first := _graph.corner_node(node + 1, 0) \
			if node + 1 < _street.node_count() else _graph.mid_first()
		var corners := next_first - _graph.corner_node(node, 0)
		assert_int(corners)\
			.override_failure_message("у узла %d углов %d при степени %d"
				% [node, corners, _street.node_degree(node)])\
			.is_equal(_street.node_degree(node))


func test_corners_sit_off_the_roadway() -> void:
	# Угол внутреннего перекрёстка отстоит на 8 м по обеим осям — вне полосы
	# движения (6 м). Это ровно те же (±8, ±8), что были у сеточной версии.
	var node := _node_id(4, 4)
	# Угол между подходами N и E — северо-восточный.
	var ne := _graph.position_of(_graph.corner_node(node, N))
	assert_float(ne.x).is_equal_approx(8.0, 1e-3)
	assert_float(ne.z).is_equal_approx(-8.0, 1e-3)
	# Угол между W и N (замыкающий сектор) — северо-западный.
	var nw := _graph.position_of(_graph.corner_node(node, W))
	assert_float(nw.x).is_equal_approx(-8.0, 1e-3)
	assert_float(nw.z).is_equal_approx(-8.0, 1e-3)


func test_dead_end_corner_wraps_the_street_end() -> void:
	# На краю сетки у узла три подхода, и в «пустом» секторе угол один,
	# на выносе ровно ped_side: тротуар огибает торец улицы.
	var node := _node_id(0, 4)
	# Подходы узла (0,4): N (-Z), E (+X), S (+Z). Сектор S -> N охватывает
	# весь запад, его угол — единственный на этой стороне.
	var west := _graph.position_of(_graph.corner_node(node, 2))
	assert_float(west.x - _field.road_axes[0]).is_equal_approx(-8.0, 1e-3)
	assert_float(west.z - _field.road_axes[4]).is_equal_approx(0.0, 1e-3)


func test_mid_nodes_sit_between_intersections() -> void:
	# Середина ленты — на половине длины ребра, в стороне на ped_side.
	# Ребро (4,4)->(4,5) идёт вдоль Z, значит середина смещена по X.
	var mid := _graph.position_of(_graph.mid_node(_south_edge(4, 4), false))
	assert_float(absf(mid.x - _field.road_axes[4])).is_equal_approx(8.0, 1e-3)
	assert_float(mid.z).is_equal_approx(
		(_field.road_axes[4] + _field.road_axes[5]) * 0.5, 1e-3)


func test_edge_costs() -> void:
	var node := _node_id(4, 4)
	var ne := _graph.corner_node(node, N)
	var nw := _graph.corner_node(node, W)
	var se := _graph.corner_node(node, E)
	# Полулента сетки — 24 м, цена метра выбрана так, чтобы это были прежние
	# 0.5 (порт pedgraph.js).
	var mid := _graph.mid_node(_south_edge(4, 4), false)
	assert_float(_graph.edge_cost(_graph.kerb_node(node, S, false), mid))\
		.is_equal_approx(0.5, 1e-6)
	assert_float(_graph.edge_cost(nw, ne)).is_equal(2.0)
	assert_float(_graph.edge_cost(ne, se)).is_equal(2.0)
	# Диагональ перекрёстка напрямую не соединена — только через два перехода.
	assert_int(_graph.edge_kind(nw, se)).is_equal(-1)


func test_walk_cost_is_proportional_to_length() -> void:
	# Единственное отличие стоимостей от оригинала: тротуар стоит за метр.
	# На сетке это прежние числа, а на графе с рёбрами разной длины
	# фиксированная цена ребра сделала бы длинный обход дешевле короткого.
	var checked := 0
	for m in range(_graph.mid_first(), _graph.mid_first() + _graph.mid_count()):
		for other in _graph.legal.get_point_connections(m):
			if _graph.edge_kind(m, other) != int(PedGraph.Edge.WALK):
				continue
			var d := _graph.position_of(m).distance_to(_graph.position_of(other))
			assert_float(_graph.edge_cost(m, other))\
				.override_failure_message(
					"лента длиной %.2f м стоит %.4f" % [d, _graph.edge_cost(m, other)])\
				.is_equal_approx(d * PedGraph.WALK_COST_PER_M, 1e-6)
			checked += 1
	assert_int(checked)\
		.override_failure_message("проверено лент: %d" % checked)\
		.is_greater(100)


# --- Гейты светофоров -------------------------------------------------------

func test_crossing_edges_carry_gate() -> void:
	# Перекрёсток (3, 3) регулируемый — стойки стоят через один.
	var node := _node_id(3, 3)
	var north := _graph.crossing_ends(node, N)
	var east := _graph.crossing_ends(node, E)
	assert_int(_graph.edge_gate(north.x, north.y)).is_greater_equal(0)
	assert_int(_graph.edge_gate(east.x, east.y)).is_greater_equal(0)
	# Переход через северный и через восточный рукав — разные гейты.
	assert_int(_graph.edge_gate(north.x, north.y))\
		.is_not_equal(_graph.edge_gate(east.x, east.y))


func test_gate_decodes_to_node_and_approach() -> void:
	# Ровно та адресация, которую этап 9 отдаст в
	# NodeSignalController.car_state(node_id, approach_id).
	var gate := PedGraph.gate_id(_node_id(3, 5), E)
	assert_int(PedGraph.gate_node(gate)).is_equal(_node_id(3, 5))
	assert_int(PedGraph.gate_approach(gate)).is_equal(E)


func test_gate_approach_matches_city_graph_ordering() -> void:
	# Номер подхода в гейте обязан совпадать с номером подхода в CityGraph:
	# на этом держится вся синхронизация со светофором узла (этап 7).
	for c: Dictionary in _graph.crossings:
		if int(c["gate"]) < 0:
			continue
		var gate: int = c["gate"]
		var node: int = c["node"]
		var approach: int = c["approach"]
		assert_int(PedGraph.gate_node(gate)).is_equal(node)
		assert_int(PedGraph.gate_approach(gate)).is_equal(approach)
		assert_int(approach)\
			.override_failure_message(
				"подход %d выходит за степень узла %d" % [approach, node])\
			.is_less(_street.node_degree(node))


func test_gate_axial_bridges_to_the_axis_controller() -> void:
	# Мост к осевому контроллеру живого города: переход через северный рукав
	# перекрёстка (3,3) пересекает дорогу, по которой машины едут вдоль Z.
	var axial := _graph.gate_axial(PedGraph.gate_id(_node_id(3, 5), N))
	assert_int(axial.x).is_equal(3)
	assert_int(axial.y).is_equal(int(PedGraph.CrossAxis.Z_ROAD))
	var across := _graph.gate_axial(PedGraph.gate_id(_node_id(3, 5), E))
	assert_int(across.y).is_equal(int(PedGraph.CrossAxis.X_ROAD))


func test_walk_edges_have_no_gate() -> void:
	var node := _node_id(4, 4)
	var mid := _graph.mid_node(_south_edge(4, 4), false)
	assert_int(_graph.edge_gate(_graph.kerb_node(node, S, false), mid)).is_equal(-1)


func test_crossings_list_matches_graph() -> void:
	# Переходов по одному на подход: 49 внутренних узлов x 4 + 28 краевых x 3.
	# Углы сетки (степень 2 с поворотом) перехода не получают: у них всего два
	# угла тротуара, и отрезок между ними прошёл бы наискось через перекрёсток.
	assert_int(_graph.crossings.size())\
		.override_failure_message("переходов %d, ожидалось 280"
			% _graph.crossings.size())\
		.is_equal(49 * 4 + 28 * 3)
	for c in _graph.crossings:
		assert_int(_graph.edge_gate(c["a"], c["b"])).is_equal(c["gate"])
		assert_int(_graph.edge_kind(c["a"], c["b"]))\
			.is_equal(int(PedGraph.Edge.CROSS))


func test_only_odd_intersections_are_signalized() -> void:
	# Стойки в оригинале стоят через один перекрёсток (citygen.js:2691).
	# Список регулируемых узлов приходит из моста этапа 6, а не выводится
	# чётностью внутри графа.
	assert_bool(_graph.is_regulated(_node_id(3, 3))).is_true()
	assert_bool(_graph.is_regulated(_node_id(4, 4))).is_false()
	assert_bool(_graph.is_regulated(_node_id(3, 4))).is_false()
	var gated := 0
	for c in _graph.crossings:
		if c["gate"] >= 0:
			gated += 1
	# 4 x 4 регулируемых перекрёстка по 4 перехода.
	assert_int(gated).is_equal(16 * 4)


func test_unsignalized_crossing_is_still_a_crossing() -> void:
	# На нерегулируемом перекрёстке зебра есть, гейта нет: пешеход обязан
	# пропускать транспорт сам, но по проезжей части вне перехода не идёт.
	var ends := _graph.crossing_ends(_node_id(4, 4), N)
	assert_int(_graph.edge_kind(ends.x, ends.y)).is_equal(int(PedGraph.Edge.CROSS))
	assert_int(_graph.edge_gate(ends.x, ends.y)).is_equal(-1)
	assert_bool(_graph.is_unsignalized_crossing(ends.x, ends.y)).is_true()


# --- Маршрутизация ----------------------------------------------------------

func test_path_along_sidewalk() -> void:
	# Вдоль ленты: угол -> середина -> угол соседнего перекрёстка.
	var edge := _south_edge(4, 4)
	var a := _graph.kerb_node(_node_id(4, 4), S, false)
	var b := _graph.kerb_node(_node_id(4, 5), N, true)
	var path := _graph.find_path(a, b, false)
	assert_int(path.size()).is_equal(3)
	assert_int(path[1]).is_equal(_graph.mid_node(edge, false))


func test_crossing_road_is_a_single_gated_edge() -> void:
	var ends := _graph.crossing_ends(_node_id(4, 4), N)
	var path := _graph.find_path(ends.x, ends.y, false)
	assert_int(path.size()).is_equal(2)


func test_legal_graph_has_no_jwalk() -> void:
	# Найдём хотя бы одно jwalk-ребро и убедимся, что законопослушный
	# маршрут им не пользуется.
	var found := false
	for e in _street.edge_count():
		var a := _graph.mid_node(e, false)
		var b := _graph.mid_node(e, true)
		if a < 0 or _graph.edge_kind(a, b) != int(PedGraph.Edge.JWALK):
			continue
		found = true
		var legal_path := _graph.find_path(a, b, false)
		var jwalk_path := _graph.find_path(a, b, true)
		assert_int(jwalk_path.size()).is_equal(2)
		assert_int(legal_path.size()).is_greater(2)
	assert_bool(found)\
		.override_failure_message("в графе нет ни одного jwalk-ребра")\
		.is_true()


func test_route_returns_points_and_gates_in_parallel() -> void:
	var target := _graph.corner_node(_node_id(6, 6), E)
	var route := _graph.build_route(Vector3(-8.0, 0.0, 0.0), target, false)
	var points: PackedVector3Array = route["points"]
	var gates: PackedInt32Array = route["gates"]
	var nodes: PackedInt32Array = route["node_ids"]
	assert_int(points.size()).is_equal(gates.size())
	assert_int(points.size()).is_equal(nodes.size())
	assert_int(points.size()).is_greater(2)
	assert_int(gates[0]).is_equal(-1)
	# Маршрут через полгорода обязан содержать хотя бы один переход.
	var has_gate := false
	for g in gates:
		if g >= 0:
			has_gate = true
	assert_bool(has_gate).is_true()


func test_route_arrays_stay_parallel_when_starting_off_graph() -> void:
	# Агент стартует посреди тротуара, не в узле: стартовая точка добавляется
	# синтетической, и все три массива обязаны остаться выровненными.
	var target := _graph.corner_node(_node_id(5, 5), N)
	var route := _graph.build_route(Vector3(-8.0, 0.0, 17.0), target, false)
	var points: PackedVector3Array = route["points"]
	var gates: PackedInt32Array = route["gates"]
	var nodes: PackedInt32Array = route["node_ids"]
	assert_int(points.size()).is_equal(gates.size())
	assert_int(points.size()).is_equal(nodes.size())
	assert_int(nodes[0]).is_equal(-1)
	assert_float(points[0].z).is_equal_approx(17.0, 1e-4)
	for i in range(1, nodes.size()):
		assert_int(nodes[i]).is_greater_equal(0)
		assert_vector(points[i]).is_equal(_graph.position_of(nodes[i]))


func test_route_reaches_target() -> void:
	var target := _graph.corner_node(_node_id(2, 7), W)
	var route := _graph.build_route(Vector3(120.0, 0.0, -60.0), target, false)
	var points: PackedVector3Array = route["points"]
	assert_int(points.size()).is_greater(1)
	assert_float(points[points.size() - 1].distance_to(
		_graph.position_of(target))).is_less(0.01)


# --- Эвристика A* -----------------------------------------------------------

func test_heuristic_never_overestimates_a_single_edge() -> void:
	# Индуктивный шаг доказательства допустимости: если оценка не больше цены
	# КАЖДОГО ребра, то по неравенству треугольника она не больше цены любого
	# пути. Проверяются ВСЕ рёбра обоих графов, включая самое короткое.
	var shortest := INF
	var checked := 0
	for a in _graph.node_count():
		for b in _graph.full.get_point_connections(a):
			if b < a:
				continue
			var length := _graph.position_of(a).distance_to(_graph.position_of(b))
			assert_float(_graph.heuristic(a, b))\
				.override_failure_message(
					"оценка %.4f больше цены ребра %.4f (длина %.2f м)"
					% [_graph.heuristic(a, b), _graph.edge_cost(a, b), length])\
				.is_less_equal(_graph.edge_cost(a, b) + 1e-9)
			shortest = minf(shortest, length)
			checked += 1
	assert_int(checked)\
		.override_failure_message("проверено рёбер: %d" % checked)\
		.is_greater(200)
	assert_float(shortest)\
		.override_failure_message("самое короткое ребро графа %.2f м" % shortest)\
		.is_less(30.0)


func test_heuristic_never_overestimates_a_whole_route() -> void:
	var rng := SeededRng.new(31337)
	for attempt in 60:
		var a := _random_node(rng)
		var b := _random_node(rng)
		var path := _graph.find_path(a, b, false)
		if path.size() < 2:
			continue
		var cost := 0.0
		for k in range(1, path.size()):
			cost += _graph.edge_cost(path[k - 1], path[k])
		assert_float(_graph.heuristic(a, b))\
			.override_failure_message(
				"оценка %.4f больше настоящей цены маршрута %.4f"
				% [_graph.heuristic(a, b), cost])\
			.is_less_equal(cost + 1e-6)


# --- Главный инвариант ПДД --------------------------------------------------

func test_no_ungated_segment_crosses_roadway() -> void:
	var checked := _sweep_routes(_graph, _street, 120, 4242)
	assert_int(checked)\
		.override_failure_message("проверено всего %d отрезков" % checked)\
		.is_greater(200)


func test_invariant_holds_on_degree_3_5_and_ring_nodes() -> void:
	# Тот же инвариант на графе, где есть узлы степени 3 и 5 и кольцо:
	# сеточный город таких не содержит, а настоящая топология (этап 2) — да.
	var street := _mixed_graph()
	var graph := PedGraph.on_graph(street, PackedInt32Array([CENTER_NODE]),
		_field.road_half + _field.sidewalk * 0.5)
	assert_int(street.node_degree(CENTER_NODE))\
		.override_failure_message("центральный узел полигона не степени 5")\
		.is_equal(5)
	var checked := _sweep_routes(graph, street, 200, 909)
	assert_int(checked)\
		.override_failure_message("проверено всего %d отрезков" % checked)\
		.is_greater(200)


func test_dead_end_sidewalk_wraps_the_end_instead_of_cutting_it() -> void:
	# Тупик — единственный случай, где правило «угол между парой соседних
	# подходов» вырождается: пары подходов нет. Единственный угол на оси улицы
	# (как было до правки) заставлял обе ленты резать полотно наискось, причём
	# ОБА конца такого отрезка лежали снаружи полотна — проверка по концам
	# этого не видела.
	var street := _dead_end_star()
	var side := _field.road_half + _field.sidewalk * 0.5
	var graph := PedGraph.on_graph(street, PackedInt32Array(), side)
	var ends := 0
	for node in street.node_count():
		if street.node_degree(node) != 1:
			continue
		ends += 1
		var left := graph.kerb_node(node, 0, false)
		var right := graph.kerb_node(node, 0, true)
		assert_int(left)\
			.override_failure_message("у тупика %d одна кербовая точка на оси улицы"
				% node)\
			.is_not_equal(right)
		# Кербовые точки стоят по разные стороны рукава, каждая в ped_side от оси.
		var span := graph.position_of(left).distance_to(graph.position_of(right))
		assert_float(span)\
			.override_failure_message("кербовые точки тупика %d разнесены на %.2f м, ожидалось %.2f"
				% [node, span, 2.0 * side])\
			.is_equal_approx(2.0 * side, 1e-3)
		# Перейти тупиковую улицу можно только вокруг торца: перехода
		# (Edge.CROSS) у степени 1 нет, значит путь целиком из тротуара.
		var path := graph.find_path(left, right, false)
		assert_int(path.size())\
			.override_failure_message("обвода торца у тупика %d нет: путь из %d узлов"
				% [node, path.size()])\
			.is_greater(2)
		for k in range(1, path.size()):
			assert_int(graph.edge_kind(path[k - 1], path[k]))\
				.override_failure_message(
					"обвод торца тупика %d идёт не по тротуару" % node)\
				.is_equal(int(PedGraph.Edge.WALK))
	assert_int(ends)\
		.override_failure_message("тупиков в полигоне %d, ожидалось %d"
			% [ends, DEAD_END_ANGLES.size()])\
		.is_equal(DEAD_END_ANGLES.size())
	var checked := _assert_walk_edges_stay_off_the_roadway(graph, street)
	assert_int(checked)\
		.override_failure_message("проверено тротуарных рёбер: %d" % checked)\
		.is_greater(20)


func test_ring_crossing_goes_over_the_arm_not_the_annulus() -> void:
	var street := _mixed_graph()
	var graph := PedGraph.on_graph(street, PackedInt32Array(),
		_field.road_half + _field.sidewalk * 0.5)
	var center := street.node_position(RING_NODE)
	var radius := street.node_radius(RING_NODE)
	var found := 0
	for c: Dictionary in graph.crossings:
		if int(c["node"]) != RING_NODE:
			continue
		found += 1
		var a: Vector3 = graph.position_of(c["a"])
		var b: Vector3 = graph.position_of(c["b"])
		# Хорда перехода обязана проходить СНАРУЖИ аннулюса.
		var d := _point_to_segment(Vector2(center.x, center.z),
			Vector2(a.x, a.z), Vector2(b.x, b.z))
		assert_float(d)\
			.override_failure_message(
				"переход кольца проходит в %.2f м от центра при радиусе %.2f"
				% [d, radius])\
			.is_greater(radius)
		# И обязана пересекать ровно тот рукав, к которому она приписана.
		var arm := street.approach_edge(RING_NODE, int(c["approach"]))
		assert_bool(_crosses_edge(street, arm, a, b))\
			.override_failure_message("переход не пересекает свой рукав кольца")\
			.is_true()
	assert_int(found)\
		.override_failure_message("у кольца не нашлось ни одного перехода")\
		.is_equal(street.node_degree(RING_NODE))


## Аннулюс кольца — проезжая часть, на которую пешеход не выходит НИКОГДА,
## даже по переходу: переходы кольца идут через рукава. Поэтому здесь, в
## отличие от главного инварианта, проверяются все отрезки подряд.
func test_no_route_segment_enters_a_roundabout() -> void:
	var street := _mixed_graph()
	var graph := PedGraph.on_graph(street, PackedInt32Array(),
		_field.road_half + _field.sidewalk * 0.5)
	var center := street.node_position(RING_NODE)
	var radius := street.node_radius(RING_NODE)
	var rng := SeededRng.new(77)
	var checked := 0
	for attempt in 200:
		var a := rng.randi_below(graph.node_count())
		var b := rng.randi_below(graph.node_count())
		var route := graph.build_route(graph.position_of(a), b, false)
		var points: PackedVector3Array = route["points"]
		for i in range(1, points.size()):
			checked += 1
			var d := _point_to_segment(Vector2(center.x, center.z),
				Vector2(points[i - 1].x, points[i - 1].z),
				Vector2(points[i].x, points[i].z))
			assert_float(d)\
				.override_failure_message(
					"отрезок маршрута заходит в аннулюс кольца: %.2f м < %.2f"
					% [d, radius])\
				.is_greater_equal(radius)
	assert_int(checked).is_greater(200)


# --- Бюджеты ----------------------------------------------------------------

func test_astar_is_fast_enough_for_activation_budget() -> void:
	# Пешеходы активируются пачками; бюджет оригинала — не более двух
	# полных пересчётов маршрута за тик.
	var t0 := Time.get_ticks_usec()
	var rng := SeededRng.new(7)
	for i in 200:
		_graph.find_path(_random_node(rng), _random_node(rng), false)
	var us := Time.get_ticks_usec() - t0
	assert_int(us)\
		.override_failure_message("200 маршрутов заняли %d мкс" % us)\
		.is_less(400_000)


# --- Полигон со степенями 3 и 5 и кольцом -----------------------------------

## Узел в центре синтетического графа: сетка 3x3 плюс диагональный луч даёт
## степень 5. Нумерация — как у `CityGraphGrid`: i * 3 + j.
const CENTER_NODE := 4
const RING_NODE := 9
const MIXED_CELL := 64.0
const MIXED_RING_RADIUS := 16.0


## Сетка 3x3 (узлы степени 2, 3 и 4) + диагональный луч из центра (степень 5)
## + кольцо с тремя рукавами. Ширина полотна — та же, что у моста этапа 6.
func _mixed_graph() -> CityGraph:
	var g := CityGraph.new()
	for i in 3:
		for j in 3:
			g.add_node(Vector3(i * MIXED_CELL, 0.0, j * MIXED_CELL))
	var ring_pos := Vector3(-2.0 * MIXED_CELL, 0.0, MIXED_CELL)
	g.add_node(ring_pos, 0, CityGraph.NodeKind.ROUNDABOUT, MIXED_RING_RADIUS)
	# Три конца рукавов кольца, разнесённые на 120°.
	for k in 3:
		var a := TAU * float(k) / 3.0
		g.add_node(ring_pos + Vector3(cos(a), 0.0, sin(a)) * (MIXED_CELL * 0.9))
	# Конец диагонального луча из центра сетки. 1.5 клетки, а не 1.8: на 1.8
	# торец луча оказывался в 12.8 м от осей улиц (4,5)-(8) и (4,7)-(8) —
	# полотна почти касались, и тротуар СОСЕДНЕЙ улицы законно проходил по
	# торцу этого полотна. Это дефект геометрии полигона, а не пешеходного
	# графа: две проезжие части нельзя сводить ближе чем на две полуширины
	# плюс тротуар.
	g.add_node(Vector3(MIXED_CELL * 1.5, 0.0, MIXED_CELL * 1.5))

	for i in 3:
		for j in 3:
			var id := i * 3 + j
			if i + 1 < 3:
				g.add_edge(id, id + 3, PackedVector3Array(), CityGraphGrid.LANE_WIDTH)
			if j + 1 < 3:
				g.add_edge(id, id + 1, PackedVector3Array(), CityGraphGrid.LANE_WIDTH)
	for k in 3:
		g.add_edge(RING_NODE, RING_NODE + 1 + k, PackedVector3Array(),
			CityGraphGrid.LANE_WIDTH)
	g.add_edge(CENTER_NODE, RING_NODE + 4, PackedVector3Array(),
		CityGraphGrid.LANE_WIDTH)
	# Кольцо к городу: западный узел сетки цепляется к первому рукаву.
	g.add_edge(0, RING_NODE + 1, PackedVector3Array(), CityGraphGrid.LANE_WIDTH)
	g.build()
	return g


# --- Полигон из тупиковых лучей ---------------------------------------------

## Углы лучей звезды тупиков, рад. Намеренно не кратны 90° и разнесены
## неравномерно: тупик обязан огибаться при любой ориентации улицы. Все
## сектора между лучами шире 1.1 рад — иначе в дело вмешается отсечка
## `PedGraph.MIN_CORNER_HALF`, а тест не про неё.
const DEAD_END_ANGLES: Array[float] = [0.0, 1.1, 2.3, 3.6, 5.0]
## Длина луча, м: заметно больше двух выносов тротуара, чтобы у ребра была
## настоящая лента с серединными узлами.
const DEAD_END_ARM := 90.0


## Звезда: центральный узел степени 5 и пять узлов степени 1 вокруг.
func _dead_end_star() -> CityGraph:
	var g := CityGraph.new()
	g.add_node(Vector3.ZERO)
	for a in DEAD_END_ANGLES:
		g.add_node(Vector3(cos(a), 0.0, sin(a)) * DEAD_END_ARM)
	for k in DEAD_END_ANGLES.size():
		g.add_edge(0, k + 1, PackedVector3Array(), CityGraphGrid.LANE_WIDTH)
	g.build()
	return g


# --- Общая проверка инварианта ----------------------------------------------

## Прогоняет случайные маршруты и проверяет, что каждый отрезок без гейта не
## пересекает полотно ни одного ребра графа улиц. Возвращает число проверок.
func _sweep_routes(graph: PedGraph, street: CityGraph, attempts: int,
		seed_value: int) -> int:
	var rng := SeededRng.new(seed_value)
	var checked := 0
	for attempt in attempts:
		var a := rng.randi_below(graph.node_count())
		var b := rng.randi_below(graph.node_count())
		if a == b:
			continue
		var route := graph.build_route(graph.position_of(a), b, false)
		var points: PackedVector3Array = route["points"]
		var gates: PackedInt32Array = route["gates"]
		var ids: PackedInt32Array = route["node_ids"]
		for i in range(1, points.size()):
			if gates[i] >= 0:
				continue
			# Нерегулируемый переход — легальное пересечение дороги.
			if ids[i - 1] >= 0 and ids[i] >= 0 \
					and graph.is_unsignalized_crossing(ids[i - 1], ids[i]):
				continue
			checked += 1
			assert_bool(_segment_enters_roadway(street, points[i - 1], points[i]))\
				.override_failure_message(
					"отрезок %s -> %s без гейта пересекает проезжую часть"
					% [points[i - 1], points[i]])\
				.is_false()
	return checked


## Проверка КОНСТРУКЦИИ, а не выборки маршрутов: каждое ребро типа WALK
## обязано целиком лежать вне полотна любой улицы. Переходы и jwalk исключены —
## им пересекать полотно положено. Возвращает число проверенных рёбер.
func _assert_walk_edges_stay_off_the_roadway(graph: PedGraph,
		street: CityGraph) -> int:
	var checked := 0
	for a in graph.node_count():
		for b in graph.full.get_point_connections(a):
			if b < a or graph.edge_kind(a, b) != int(PedGraph.Edge.WALK):
				continue
			checked += 1
			assert_bool(_segment_enters_roadway(street,
					graph.position_of(a), graph.position_of(b)))\
				.override_failure_message(
					"тротуарное ребро %s -> %s заходит в полотно"
					% [graph.position_of(a), graph.position_of(b)])\
				.is_false()
	return checked


## Пересекает ли отрезок полотно какого-нибудь ребра графа улиц.
##
## Общая геометрия вместо коридора вокруг оси: полотно ребра — это буфер
## полуширины вокруг его полилинии, и отрезок нарушает ПДД, если он подходит
## к полилинии ближе полуширины ХОТЬ ГДЕ-НИБУДЬ по своей длине.
##
## Расстояние считается честно, отрезок против отрезка, а не «концы отрезка
## против полилинии»: отрезок, обходящий КОНЕЦ улицы и ныряющий в полотно
## серединой, ось не пересекает (заходит за её конец), а оба его конца лежат
## снаружи буфера — проверка по концам его не видит вовсе. Именно такой
## отрезок пешеходный граф порождает на тупиковом узле.
func _segment_enters_roadway(street: CityGraph, a: Vector3, b: Vector3) -> bool:
	var pa := Vector2(a.x, a.z)
	var pb := Vector2(b.x, b.z)
	for e in street.edge_count():
		# Отдельная проверка на пересечение осей: она не зависит от ширины и
		# ловит нарушение даже у вырожденного полотна нулевой ширины.
		if _crosses_edge(street, e, a, b):
			return true
		var half := street.edge_width(e) * 0.5 - 1e-6
		for i in street.edge_point_count(e) - 1:
			var p0 := street.edge_point(e, i)
			var p1 := street.edge_point(e, i + 1)
			if _segment_to_segment(pa, pb, Vector2(p0.x, p0.z),
					Vector2(p1.x, p1.z)) < half:
				return true
	return false


## Минимальное расстояние между двумя отрезками в плане.
##
## Если отрезки пересекаются — ноль; иначе минимум достигается на конце одного
## из них (стандартный факт планарной геометрии: функция расстояния между
## точками двух отрезков выпуклая, и без пересечения её минимум лежит на
## границе области параметров), поэтому четырёх проекций достаточно.
static func _segment_to_segment(a: Vector2, b: Vector2, c: Vector2,
		d: Vector2) -> float:
	if _segments_cross(a, b, c, d):
		return 0.0
	return minf(
		minf(_point_to_segment(a, c, d), _point_to_segment(b, c, d)),
		minf(_point_to_segment(c, a, b), _point_to_segment(d, a, b)))


func _crosses_edge(street: CityGraph, e: int, a: Vector3, b: Vector3) -> bool:
	var pa := Vector2(a.x, a.z)
	var pb := Vector2(b.x, b.z)
	for i in street.edge_point_count(e) - 1:
		var p0 := street.edge_point(e, i)
		var p1 := street.edge_point(e, i + 1)
		if _segments_cross(pa, pb, Vector2(p0.x, p0.z), Vector2(p1.x, p1.z)):
			return true
	return false


## Пересекаются ли отрезки (строго, касание концом не считается — угол
## тротуара законно стоит на продолжении оси тупиковой улицы).
static func _segments_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var d1 := _cross_sign(c, d, a)
	var d2 := _cross_sign(c, d, b)
	var d3 := _cross_sign(a, b, c)
	var d4 := _cross_sign(a, b, d)
	return d1 * d2 < 0.0 and d3 * d4 < 0.0


static func _cross_sign(p: Vector2, q: Vector2, r: Vector2) -> float:
	var v := (q - p).cross(r - p)
	return 0.0 if absf(v) < 1e-9 else signf(v)


static func _point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 1e-12:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --- Вспомогательное --------------------------------------------------------

func _random_node(rng: SeededRng) -> int:
	return rng.randi_below(_graph.node_count())


## Ребро сетки, отходящее от узла (i, j) в сторону подхода k.
func _edge_of(i: int, j: int, k: int) -> int:
	var node := _node_id(i, j)
	return _street.approach_edge(node, k) if k < _street.node_degree(node) else -1


func _south_edge(i: int, j: int) -> int:
	return _edge_of(i, j, S)
