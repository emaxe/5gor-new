extends GdUnitTestSuite
## Граф ходьбы — основа ПДД для пешеходов. Главный инвариант, унаследованный
## из регрессий проекта capital: НИ ОДИН участок маршрута без гейта не должен
## пересекать проезжую часть. Если он нарушен, пешеходы срезают через дорогу
## мимо перехода, и никакая логика ожидания зелёного это не исправит.

var _field: CityField
var _graph: PedGraph


func before() -> void:
	_field = CityField.new(Db.balance)
	_graph = PedGraph.new(_field)


# --- Структура --------------------------------------------------------------

func test_node_count_matches_layout() -> void:
	# 81 перекрёсток x 4 угла + 9 дорог x 2 стороны x 8 сегментов x 2 = 612.
	assert_int(_graph.node_count()).is_equal(612)


func test_ids_are_unique_and_dense() -> void:
	var seen := {}
	for i in 9:
		for j in 9:
			for c in 4:
				seen[PedGraph.corner_id(i, j, c)] = true
	for road in 9:
		for side in 2:
			for seg in 8:
				seen[PedGraph.vmid_id(road, side, seg)] = true
				seen[PedGraph.hmid_id(road, side, seg)] = true
	assert_int(seen.size()).is_equal(612)


func test_corners_sit_off_the_roadway() -> void:
	# Угол квартала отстоит на 8 м по обеим осям — вне полосы движения (6 м).
	var nw := _graph.position_of(PedGraph.corner_id(4, 4, PedGraph.Corner.NW))
	assert_float(nw.x).is_equal_approx(-8.0, 1e-3)
	assert_float(nw.z).is_equal_approx(-8.0, 1e-3)
	var se := _graph.position_of(PedGraph.corner_id(4, 4, PedGraph.Corner.SE))
	assert_float(se.x).is_equal_approx(8.0, 1e-3)
	assert_float(se.z).is_equal_approx(8.0, 1e-3)


func test_mid_nodes_sit_between_intersections() -> void:
	var mid := _graph.position_of(PedGraph.vmid_id(4, 0, 4))
	assert_float(mid.x).is_equal_approx(-8.0, 1e-3)
	assert_float(mid.z).is_equal_approx(32.0, 1e-3)


func test_edge_costs() -> void:
	var nw := PedGraph.corner_id(4, 4, PedGraph.Corner.NW)
	var ne := PedGraph.corner_id(4, 4, PedGraph.Corner.NE)
	var sw := PedGraph.corner_id(4, 4, PedGraph.Corner.SW)
	assert_float(_graph.edge_cost(nw, PedGraph.vmid_id(4, 0, 3))).is_equal(0.5)
	assert_float(_graph.edge_cost(nw, ne)).is_equal(2.0)
	assert_float(_graph.edge_cost(nw, sw)).is_equal(2.0)
	# Диагональ перекрёстка напрямую не соединена — только через два перехода.
	assert_int(_graph.edge_kind(nw, PedGraph.corner_id(4, 4, PedGraph.Corner.SE)))\
		.is_equal(-1)


# --- Гейты светофоров -------------------------------------------------------

func test_crossing_edges_carry_gate() -> void:
	# Перекрёсток (3, 3) регулируемый — стойки стоят через один.
	var nw := PedGraph.corner_id(3, 3, PedGraph.Corner.NW)
	var ne := PedGraph.corner_id(3, 3, PedGraph.Corner.NE)
	var sw := PedGraph.corner_id(3, 3, PedGraph.Corner.SW)
	assert_int(_graph.edge_gate(nw, ne)).is_greater_equal(0)
	assert_int(_graph.edge_gate(nw, sw)).is_greater_equal(0)
	# Поперёк вертикальной и поперёк горизонтальной дороги — разные сигналы.
	assert_int(_graph.edge_gate(nw, ne)).is_not_equal(_graph.edge_gate(nw, sw))


func test_walk_edges_have_no_gate() -> void:
	var nw := PedGraph.corner_id(4, 4, PedGraph.Corner.NW)
	assert_int(_graph.edge_gate(nw, PedGraph.vmid_id(4, 0, 3))).is_equal(-1)


func test_crossings_list_matches_graph() -> void:
	# Из этого списка генератор рисует зебры и стойки: 4 перехода
	# на каждый из 81 перекрёстка.
	assert_int(_graph.crossings.size()).is_equal(81 * 4)
	for c in _graph.crossings:
		assert_int(_graph.edge_gate(c["a"], c["b"])).is_equal(c["gate"])
		assert_int(_graph.edge_kind(c["a"], c["b"]))\
			.is_equal(int(PedGraph.Edge.CROSS))


func test_only_odd_intersections_are_signalized() -> void:
	# Стойки в оригинале стоят через один перекрёсток (citygen.js:2691).
	assert_bool(PedGraph.is_signalized(3, 3)).is_true()
	assert_bool(PedGraph.is_signalized(4, 4)).is_false()
	assert_bool(PedGraph.is_signalized(3, 4)).is_false()
	var gated := 0
	for c in _graph.crossings:
		if c["gate"] >= 0:
			gated += 1
	# 4 x 4 регулируемых перекрёстка по 4 перехода.
	assert_int(gated).is_equal(16 * 4)


func test_unsignalized_crossing_is_still_a_crossing() -> void:
	# На нерегулируемом перекрёстке зебра есть, гейта нет: пешеход обязан
	# пропускать транспорт сам, но по проезжей части вне перехода не идёт.
	var nw := PedGraph.corner_id(4, 4, PedGraph.Corner.NW)
	var ne := PedGraph.corner_id(4, 4, PedGraph.Corner.NE)
	assert_int(_graph.edge_kind(nw, ne)).is_equal(int(PedGraph.Edge.CROSS))
	assert_int(_graph.edge_gate(nw, ne)).is_equal(-1)
	assert_bool(_graph.is_unsignalized_crossing(nw, ne)).is_true()


func test_gate_decodes_to_intersection_and_axis() -> void:
	var gate := PedGraph.gate_id(3, 5, PedGraph.CrossAxis.X_ROAD)
	assert_vector(PedGraph.gate_intersection(gate)).is_equal(Vector2i(3, 5))
	assert_int(int(PedGraph.gate_axis(gate))).is_equal(int(PedGraph.CrossAxis.X_ROAD))


# --- Маршрутизация ----------------------------------------------------------

func test_path_along_sidewalk() -> void:
	var a := PedGraph.corner_id(4, 4, PedGraph.Corner.SW)
	var b := PedGraph.corner_id(4, 5, PedGraph.Corner.NW)
	var path := _graph.find_path(a, b, false)
	assert_int(path.size()).is_equal(3)
	assert_int(path[1]).is_equal(PedGraph.vmid_id(4, 0, 4))


func test_crossing_road_is_a_single_gated_edge() -> void:
	var nw := PedGraph.corner_id(4, 4, PedGraph.Corner.NW)
	var ne := PedGraph.corner_id(4, 4, PedGraph.Corner.NE)
	var path := _graph.find_path(nw, ne, false)
	assert_int(path.size()).is_equal(2)


func test_legal_graph_has_no_jwalk() -> void:
	# Найдём хотя бы одно jwalk-ребро и убедимся, что законопослушный
	# маршрут им не пользуется.
	var found := false
	for road in 9:
		for seg in 8:
			var a := PedGraph.vmid_id(road, 0, seg)
			var b := PedGraph.vmid_id(road, 1, seg)
			if _graph.edge_kind(a, b) != int(PedGraph.Edge.JWALK):
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
	var target := PedGraph.corner_id(6, 6, PedGraph.Corner.SE)
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
	var target := PedGraph.corner_id(5, 5, PedGraph.Corner.NE)
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
	var target := PedGraph.corner_id(2, 7, PedGraph.Corner.NW)
	var route := _graph.build_route(Vector3(120.0, 0.0, -60.0), target, false)
	var points: PackedVector3Array = route["points"]
	assert_int(points.size()).is_greater(1)
	assert_float(points[points.size() - 1].distance_to(
		_graph.position_of(target))).is_less(0.01)


# --- Главный инвариант ПДД --------------------------------------------------

func test_no_ungated_segment_crosses_roadway() -> void:
	# Прогоняем маршруты между случайными парами узлов и проверяем, что
	# каждый отрезок без гейта не пересекает полосу движения.
	# Полосой считается коридор шириной ROAD_W вокруг оси дороги.
	var rng := SeededRng.new(4242)
	var checked := 0
	for attempt in 120:
		var a := _random_ribbon_node(rng)
		var b := _random_ribbon_node(rng)
		if a == b:
			continue
		var route := _graph.build_route(_graph.position_of(a), b, false)
		var points: PackedVector3Array = route["points"]
		var gates: PackedInt32Array = route["gates"]
		var ids: PackedInt32Array = route["node_ids"]
		for i in range(1, points.size()):
			if gates[i] >= 0:
				continue
			# Нерегулируемый переход — легальное пересечение дороги.
			if ids[i - 1] >= 0 and ids[i] >= 0 \
					and _graph.is_unsignalized_crossing(ids[i - 1], ids[i]):
				continue
			checked += 1
			assert_bool(_segment_enters_roadway(points[i - 1], points[i]))\
				.override_failure_message(
					"отрезок %s -> %s без гейта пересекает проезжую часть"
					% [points[i - 1], points[i]])\
				.is_false()
	assert_int(checked).is_greater(200)


func _random_ribbon_node(rng: SeededRng) -> int:
	if rng.chance(0.5):
		return PedGraph.corner_id(rng.randi_below(9), rng.randi_below(9),
			rng.randi_below(4))
	var road := rng.randi_below(9)
	var side := rng.randi_below(2)
	var seg := rng.randi_below(8)
	return PedGraph.vmid_id(road, side, seg) if rng.chance(0.5) \
		else PedGraph.hmid_id(road, side, seg)


## Пересекает ли отрезок коридор проезжей части (аналитически, по интервалам).
func _segment_enters_roadway(a: Vector3, b: Vector3) -> bool:
	var half := _field.road_half
	for c in _field.road_axes:
		if _interval_crosses(a.x, b.x, c, half):
			return true
		if _interval_crosses(a.z, b.z, c, half):
			return true
	return false


## Проходит ли отрезок [p0, p1] сквозь полосу [c-half, c+half].
## Касание границы не считается: тротуарные узлы стоят ровно на 8 м,
## а полоса кончается на 6 м, поэтому пересечение всегда строгое.
func _interval_crosses(p0: float, p1: float, c: float, half: float) -> bool:
	var lo: float = minf(p0, p1)
	var hi: float = maxf(p0, p1)
	return lo < c - half + 1e-6 and hi > c + half - 1e-6


func test_astar_is_fast_enough_for_activation_budget() -> void:
	# Пешеходы активируются пачками; бюджет оригинала — не более двух
	# полных пересчётов маршрута за тик.
	var t0 := Time.get_ticks_usec()
	var rng := SeededRng.new(7)
	for i in 200:
		_graph.find_path(_random_ribbon_node(rng), _random_ribbon_node(rng), false)
	var us := Time.get_ticks_usec() - t0
	assert_int(us)\
		.override_failure_message("200 маршрутов заняли %d мкс" % us)\
		.is_less(400_000)
