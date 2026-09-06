extends GdUnitTestSuite
## Дорожный граф GPS — порт gps.js, с этапа 9 поверх настоящего `CityGraph`.
##
## Два набора проверок с разными задачами:
##  - на регулярной сетке (`CityGraphGrid`) — сам алгоритм: геометрию здесь
##    видно руками, «маршрут не срезает через квартал» проверяемо числом;
##  - на живой топологии Пятигорска — то, чего у сетки нет: кольцевые узлы,
##    кривые рёбра и вес по длине полилинии, а не по хорде.

var _field: CityField
## Регулярная сетка 9x9 как граф: узел (i, j) = i * 9 + j.
var _grid: RoadGraph
## Живой граф улиц Пятигорска и индекс GPS поверх него.
var _roads: CityGraph
var _city: RoadGraph


func before() -> void:
	_field = CityField.new(Db.balance)
	_grid = RoadGraph.new(CityGraphGrid.from_field(_field))
	_roads = PyatigorskTopology.new().build(_field)
	_city = RoadGraph.new(_roads)


# --- Алгоритм на регулярной сетке -------------------------------------------

func test_nearest_node_id_matches_city_field_snap() -> void:
	# RoadGraph на сетке обязан сходиться к тому же перекрёстку, что
	# CityField.nearest_intersection — иначе GPS и мир расходятся.
	var snapped := _field.nearest_intersection(60.0, 70.0)
	var id := _grid.nearest_node_id(Vector2(60.0, 70.0))
	assert_vector(_grid.node_position(id)).is_equal(snapped)


func test_route_between_adjacent_intersections_is_direct() -> void:
	var from := Vector2(-256.0, -256.0)
	var to := Vector2(-192.0, -256.0)
	var route := _grid.build_route(from, to)
	assert_vector(route[0]).is_equal(from)
	assert_vector(route[route.size() - 1]).is_equal(to)
	assert_float(RoadGraph.route_length(route)).is_equal_approx(64.0, 1e-3)


func test_route_never_cuts_diagonally_across_a_block() -> void:
	# По прямой (евклидово) это ~90.5 м, но улиц по диагонали нет — маршрут
	# обязан пройти оба хопа сетки: ровно 128 м (2 x cell).
	var from := Vector2(-256.0, -256.0)
	var to := Vector2(-192.0, -192.0)
	var route := _grid.build_route(from, to)
	assert_float(RoadGraph.route_length(route)).is_equal_approx(128.0, 1e-3)
	# Ни один сегмент маршрута не идёт по диагонали: на каждом шаге меняется
	# только одна координата.
	for i in route.size() - 1:
		var a := route[i]
		var b := route[i + 1]
		var dx := absf(b.x - a.x)
		var dz := absf(b.y - a.y)
		assert_bool(dx < 0.01 or dz < 0.01).is_true()


func test_route_keeps_exact_endpoints_off_grid() -> void:
	# Начало и конец — точные мировые координаты запроса, а не ближайший
	# перекрёсток (порт findCarRoute: pts[0] = {fromX, fromZ}).
	var from := Vector2(10.0, -30.0)
	var to := Vector2(-40.0, 100.0)
	var route := _grid.build_route(from, to)
	assert_vector(route[0]).is_equal(from)
	assert_vector(route[route.size() - 1]).is_equal(to)
	assert_int(route.size()).is_greater(2)


func test_route_length_is_polyline_sum() -> void:
	var pts := PackedVector2Array([Vector2(0.0, 0.0), Vector2(3.0, 4.0), Vector2(3.0, 0.0)])
	assert_float(RoadGraph.route_length(pts)).is_equal_approx(9.0, 1e-3)


func test_route_length_of_single_point_is_zero() -> void:
	var pts := PackedVector2Array([Vector2(5.0, 5.0)])
	assert_float(RoadGraph.route_length(pts)).is_equal(0.0)


func test_route_same_start_and_end_is_single_point() -> void:
	var p := Vector2(0.0, 0.0)
	var route := _grid.build_route(p, p)
	assert_int(route.size()).is_equal(1)
	assert_vector(route[0]).is_equal(p)


# --- Вес ребра: длина полилинии, а не хорда ---------------------------------

func test_curved_edge_costs_its_polyline_not_its_chord() -> void:
	# A -> B напрямую одним ребром с крюком в 200 м вбок: хорда 100 м, сама
	# полилиния 412 м. Обход через M — 116.6 м. На хордовых весах A* выбрал бы
	# крюк (100 < 116.6); на полилинейных обязан выбрать обход.
	var g := CityGraph.new()
	var a := g.add_node(Vector3(0.0, 0.0, 0.0))
	var m := g.add_node(Vector3(50.0, 0.0, -30.0))
	var b := g.add_node(Vector3(100.0, 0.0, 0.0))
	g.add_edge(a, b, PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(50.0, 0.0, 200.0), Vector3(100.0, 0.0, 0.0)]))
	g.add_edge(a, m)
	g.add_edge(m, b)
	g.build()

	var route := RoadGraph.new(g).build_route(Vector2(0.0, 0.0), Vector2(100.0, 0.0))
	assert_float(RoadGraph.route_length(route))\
		.override_failure_message(
			"маршрут длиной %.1f м: ожидался обход через M (116.6 м), а не крюк"
				% RoadGraph.route_length(route))\
		.is_equal_approx(116.62, 0.1)


func test_serpentine_costs_its_polyline_on_the_live_graph() -> void:
	# Тот же эффект на живом городе: серпантин на Машук — самое кривое ребро
	# топологии, полилиния 265 м при хорде 101 м.
	var e := _first_edge_of_kind(CityGraph.EdgeKind.SERPENTINE)
	var ends := _roads.edge_ends(e)
	var a := _plan(_roads.node_position(ends.x))
	var b := _plan(_roads.node_position(ends.y))

	var route := _city.build_route(a, b)
	assert_int(route.size())\
		.override_failure_message("между концами серпантина ожидался один хоп, "
			+ "получено %d точек" % route.size())\
		.is_equal(2)
	assert_float(_path_cost(a, b))\
		.override_failure_message("стоимость хопа %.1f м вместо длины полилинии %.1f м"
			% [_path_cost(a, b), _roads.edge_length(e)])\
		.is_equal_approx(_roads.edge_length(e), 0.1)
	# И обратная сторона решения «точки маршрута — узлы, а не полилинии»:
	# нарисованная ломаная здесь короче реального пути более чем вдвое.
	assert_float(RoadGraph.route_length(route))\
		.override_failure_message("хорда %.1f м не короче полилинии %.1f м — "
			% [RoadGraph.route_length(route), _roads.edge_length(e)]
			+ "тест перестал проверять кривое ребро")\
		.is_less(_roads.edge_length(e) * 0.7)


# --- Живая топология --------------------------------------------------------

func test_route_south_to_centre_passes_the_roundabout() -> void:
	# Калинина с юга в центр: единственный проезд идёт через кольцо kal_s2
	# (30, 172). Кольцо — обычный узел графа, отдельного случая ему не нужно.
	var from := Vector2(34.0, 232.0)
	var to := Vector2(24.0, 22.0)
	var route := _city.build_route(from, to)
	assert_int(route.size())\
		.override_failure_message("маршрут не построился: %d точек" % route.size())\
		.is_greater(2)

	var rings := 0
	for p in route:
		var id := _city.nearest_node_id(p)
		if _city.node_position(id).distance_to(p) < 0.01 \
				and _roads.node_kind(id) == CityGraph.NodeKind.ROUNDABOUT:
			rings += 1
	assert_int(rings)\
		.override_failure_message(
			"маршрут с юга в центр (%s -> %s) не прошёл ни одного кольца"
				% [from, to])\
		.is_equal(1)

	# Длина без крюков: прямая между концами 210.2 м, улица Калинина идёт
	# почти по ней, поэтому больше полутора прямых был бы объезд.
	var direct := from.distance_to(to)
	assert_float(RoadGraph.route_length(route))\
		.override_failure_message("маршрут %.1f м при прямой %.1f м"
			% [RoadGraph.route_length(route), direct])\
		.is_between(direct, direct * 1.5)


func test_route_steps_only_along_real_streets() -> void:
	# Тот же инвариант, что «не срезает по диагонали» на сетке, но без
	# допущения о прямых углах: каждый переход между узлами маршрута —
	# настоящее ребро графа.
	var route := _city.build_route(Vector2(-176.0, 26.0), Vector2(188.0, 26.0))
	var nodes := PackedInt32Array()
	for i in range(1, route.size() - 1):
		nodes.append(_city.nearest_node_id(route[i]))
	assert_int(nodes.size())\
		.override_failure_message("маршрут через весь город без промежуточных узлов")\
		.is_greater(3)
	for i in nodes.size() - 1:
		assert_bool(_adjacent(nodes[i], nodes[i + 1]))\
			.override_failure_message("между узлами %d и %d нет ребра графа"
				% [nodes[i], nodes[i + 1]])\
			.is_true()


func test_nearest_node_id_snaps_to_the_real_intersection() -> void:
	# Пересечение Кирова и Калинина — (24, 22) в топологии; точка в 6 м от
	# него обязана привязаться к нему, а не к соседнему узлу сетки, которой
	# больше нет.
	var id := _city.nearest_node_id(Vector2(28.0, 26.0))
	assert_vector(_city.node_position(id)).is_equal(Vector2(24.0, 22.0))


# --- Вспомогательное --------------------------------------------------------

## План узла (x, z) в конвенции GPS: Vector2.y хранит мировой z.
static func _plan(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


func _first_edge_of_kind(kind: int) -> int:
	for e in _roads.edge_count():
		if _roads.edge_kind(e) == kind:
			return e
	return -1


## Есть ли ребро между узлами графа.
func _adjacent(a: int, b: int) -> bool:
	for k in _roads.node_degree(a):
		var ends := _roads.edge_ends(_roads.approach_edge(a, k))
		if ends.x == b or ends.y == b:
			return true
	return false


## Стоимость маршрута по живому графу как сумма длин пройденных рёбер —
## именно её минимизирует A*, в отличие от длины нарисованной ломаной.
func _path_cost(from: Vector2, to: Vector2) -> float:
	var route := _city.build_route(from, to)
	var total := 0.0
	for i in route.size() - 1:
		var a := _city.nearest_node_id(route[i])
		var b := _city.nearest_node_id(route[i + 1])
		for k in _roads.node_degree(a):
			var e := _roads.approach_edge(a, k)
			var ends := _roads.edge_ends(e)
			if ends.x == b or ends.y == b:
				total += _roads.edge_length(e)
				break
	return total
