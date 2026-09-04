extends GdUnitTestSuite
## Дорожный граф GPS — порт gps.js. Инвариант: маршрут по сетке идёт только
## вдоль улиц (манхэттенский путь), никогда не срезает по диагонали через
## квартал, как честный автомобильный маршрут.

var _field: CityField
var _graph: RoadGraph


func before() -> void:
	_field = CityField.new(Db.balance)
	_graph = RoadGraph.new(_field)


func test_nearest_node_id_matches_city_field_snap() -> void:
	# RoadGraph снапит на ту же сетку, что CityField.nearest_intersection —
	# оба обязаны сходиться к одному перекрёстку.
	var snapped := _field.nearest_intersection(60.0, 70.0)
	var id := _graph.nearest_node_id(Vector2(60.0, 70.0))
	assert_vector(_graph.node_position(id)).is_equal(snapped)


func test_route_between_adjacent_intersections_is_direct() -> void:
	var from := Vector2(-256.0, -256.0)
	var to := Vector2(-192.0, -256.0)
	var route := _graph.build_route(from, to)
	assert_vector(route[0]).is_equal(from)
	assert_vector(route[route.size() - 1]).is_equal(to)
	assert_float(RoadGraph.route_length(route)).is_equal_approx(64.0, 1e-3)


func test_route_never_cuts_diagonally_across_a_block() -> void:
	# По прямой (евклидово) это ~90.5 м, но улиц по диагонали нет — маршрут
	# обязан пройти оба хопа сетки: ровно 128 м (2 x cell).
	var from := Vector2(-256.0, -256.0)
	var to := Vector2(-192.0, -192.0)
	var route := _graph.build_route(from, to)
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
	var route := _graph.build_route(from, to)
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
	var route := _graph.build_route(p, p)
	assert_int(route.size()).is_equal(1)
	assert_vector(route[0]).is_equal(p)
