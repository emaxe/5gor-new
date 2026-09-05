extends GdUnitTestSuite
## Спецификация CityGraph на синтетических графах — до появления реальной
## топологии Пятигорска.
##
## Аналог test_dist_to_road_between_axes / test_nearest_intersection_snaps_to_grid
## из test_city_field.gd, но на графе произвольной топологии вместо сетки:
## те же числовые допуски, только опорные числа считаются из геометрии
## треугольника/квадрата/дуги, а не из шага сетки.

## Допуск на расстояния: сегменты строятся из float32 в PackedVector3Array.
const EPS := 0.01
## Ширина полотна во всех синтетических графах, м (проспект оригинала).
const WIDTH := 12.0


# --- Синтетические графы ----------------------------------------------------

## Равносторонний треугольник со стороной 120: три узла степени 2.
func _triangle() -> CityGraph:
	var g := CityGraph.new()
	var a := g.add_node(Vector3(0.0, 0.0, 0.0))
	var b := g.add_node(Vector3(120.0, 0.0, 0.0))
	var c := g.add_node(Vector3(60.0, 0.0, 103.923048))
	g.add_edge(a, b, PackedVector3Array(), WIDTH)
	g.add_edge(b, c, PackedVector3Array(), WIDTH)
	g.add_edge(c, a, PackedVector3Array(), WIDTH)
	g.build()
	return g


## Квадрат 100x100 с диагональю A-C: узлы A и C степени 3.
func _square_with_diagonal() -> CityGraph:
	var g := CityGraph.new()
	var a := g.add_node(Vector3(0.0, 0.0, 0.0))
	var b := g.add_node(Vector3(100.0, 0.0, 0.0))
	var c := g.add_node(Vector3(100.0, 0.0, 100.0))
	var d := g.add_node(Vector3(0.0, 0.0, 100.0))
	g.add_edge(a, b, PackedVector3Array(), WIDTH)
	g.add_edge(b, c, PackedVector3Array(), WIDTH)
	g.add_edge(c, d, PackedVector3Array(), WIDTH)
	g.add_edge(d, a, PackedVector3Array(), WIDTH)
	g.add_edge(a, c, PackedVector3Array(), WIDTH)
	g.build()
	return g


## T-образный перекрёсток: центр степени 3, три тупика степени 1.
func _tee() -> CityGraph:
	var g := CityGraph.new()
	var t := g.add_node(Vector3(0.0, 0.0, 0.0))
	var e := g.add_node(Vector3(80.0, 0.0, 0.0))
	var w := g.add_node(Vector3(-80.0, 0.0, 0.0))
	var s := g.add_node(Vector3(0.0, 0.0, 80.0))
	g.add_edge(t, e, PackedVector3Array(), WIDTH)
	g.add_edge(t, w, PackedVector3Array(), WIDTH)
	g.add_edge(t, s, PackedVector3Array(), WIDTH)
	g.build()
	return g


## Четверть окружности радиусом 50 как одно кривое ребро из 10 точек.
func _arc() -> CityGraph:
	var g := CityGraph.new()
	var pts := PackedVector3Array()
	for i in 10:
		var ang := deg_to_rad(float(i) * 10.0)
		pts.append(Vector3(50.0 * cos(ang), 0.0, 50.0 * sin(ang)))
	var a := g.add_node(pts[0])
	var b := g.add_node(pts[9])
	g.add_edge(a, b, pts, WIDTH)
	g.build()
	return g


## Улица вдоль X на земле и эстакада вдоль Z на высоте 6 м, пересекающиеся
## в плане в (0, 0), но без общего узла — два уровня.
func _overpass() -> CityGraph:
	var g := CityGraph.new()
	var s0 := g.add_node(Vector3(-100.0, 0.0, 0.0))
	var s1 := g.add_node(Vector3(0.0, 0.0, 0.0))
	var s2 := g.add_node(Vector3(100.0, 0.0, 0.0))
	var b0 := g.add_node(Vector3(0.0, 6.0, -100.0), 1)
	var b1 := g.add_node(Vector3(0.0, 6.0, 0.0), 1)
	var b2 := g.add_node(Vector3(0.0, 6.0, 100.0), 1)
	g.add_edge(s0, s1, PackedVector3Array(), WIDTH)
	g.add_edge(s1, s2, PackedVector3Array(), WIDTH)
	# Эстакада уже улицы: заодно проверяется приоритет широкого ребра.
	g.add_edge(b0, b1, PackedVector3Array(), 10.0, CityGraph.EdgeKind.BRIDGE, 1)
	g.add_edge(b1, b2, PackedVector3Array(), 10.0, CityGraph.EdgeKind.BRIDGE, 1)
	g.build()
	return g


# --- Треугольник ------------------------------------------------------------

func test_triangle_topology() -> void:
	var g := _triangle()
	assert_int(g.node_count()).is_equal(3)
	assert_int(g.edge_count()).is_equal(3)
	for n in 3:
		assert_int(g.node_degree(n))\
			.override_failure_message(
				"узел %d треугольника должен иметь степень 2, получено %d"
				% [n, g.node_degree(n)])\
			.is_equal(2)


func test_triangle_edge_length_matches_side() -> void:
	var g := _triangle()
	for e in 3:
		assert_float(g.edge_length(e))\
			.override_failure_message(
				"сторона треугольника 120 м, ребро %d длиной %.3f"
				% [e, g.edge_length(e)])\
			.is_equal_approx(120.0, EPS)


func test_nearest_node_picks_closest_corner() -> void:
	var g := _triangle()
	assert_int(g.nearest_node(Vector3(10.0, 0.0, 5.0))).is_equal(0)
	assert_int(g.nearest_node(Vector3(115.0, 0.0, 5.0))).is_equal(1)
	assert_int(g.nearest_node(Vector3(58.0, 0.0, 100.0))).is_equal(2)


func test_nearest_node_far_outside_graph() -> void:
	# Расширяющийся поиск обязан дойти до графа и выбрать именно вершину C
	# (1298.7 м) — она ближе B (1332.1 м) и A (1414.2 м).
	var g := _triangle()
	assert_int(g.nearest_node(Vector3(1000.0, 0.0, 1000.0)))\
		.override_failure_message("далёкий запрос должен вернуть вершину C (id 2)")\
		.is_equal(2)


func test_nearest_edge_on_straight_side() -> void:
	var g := _triangle()
	var hit := g.nearest_edge(Vector3(60.0, 0.0, 2.0))
	var edge_id: int = hit["edge_id"]
	var t: float = hit["t"]
	var dist: float = hit["dist"]
	var side: int = hit["side"]
	assert_int(edge_id).is_equal(0)
	assert_float(t)\
		.override_failure_message("середина стороны A-B, ожидалось t=0.5, получено %.4f" % t)\
		.is_equal_approx(0.5, EPS)
	assert_float(dist)\
		.override_failure_message("ожидалось 2.0 м от оси, получено %.4f" % dist)\
		.is_equal_approx(2.0, EPS)
	# Ребро идёт на восток (+X), точка на юге (+Z) — справа по ходу.
	assert_int(side).is_equal(CityGraph.Side.RIGHT)


func test_nearest_edge_needs_max_dist_far_from_roads() -> void:
	# Центр треугольника отстоит от каждой стороны на радиус вписанной
	# окружности 120 / (2*sqrt(3)) = 34.641 м. С явным радиусом поиска ответ
	# точен; запрос по умолчанию (полоса влияния 6 + 4 = 10 м) на таком
	# удалении ничего не обещает.
	var g := _triangle()
	var center := Vector3(60.0, 0.0, 34.641016)
	assert_int(g.query_nearest_edge(center, 50.0)).is_greater_equal(0)
	assert_float(g.hit_dist)\
		.override_failure_message(
			"радиус вписанной окружности 34.641 м, получено %.4f" % g.hit_dist)\
		.is_equal_approx(34.641016, EPS)


func test_nearest_edge_misses_far_from_graph() -> void:
	# Точка в 200 м от любого полотна не задевает ни одной ячейки хеша —
	# запрос по умолчанию честно промахивается, а не перебирает все рёбра.
	var g := _tee()
	assert_int(g.query_nearest_edge(Vector3(0.0, 0.0, -200.0)))\
		.override_failure_message("вдали от графа ожидался промах (-1)")\
		.is_equal(-1)
	assert_bool(g.on_road(Vector3(0.0, 0.0, -200.0))).is_false()


func test_equidistant_edges_resolve_deterministically() -> void:
	# Из центра все три стороны равноудалены. Правило приоритета: расстояние,
	# затем большая ширина, затем меньший id — здесь ширины равны, значит
	# всегда ребро 0, а не «как повезёт при обходе ячейки хеша».
	var g := _triangle()
	for _i in 5:
		assert_int(g.query_nearest_edge(Vector3(60.0, 0.0, 34.641016), 50.0))\
			.is_equal(0)


func test_on_road_uses_edge_width() -> void:
	var g := _triangle()
	assert_bool(g.on_road(Vector3(60.0, 0.0, 2.0))).is_true()
	assert_bool(g.on_road(Vector3(60.0, 0.0, 5.9))).is_true()
	assert_bool(g.on_road(Vector3(60.0, 0.0, 6.1)))\
		.override_failure_message("6.1 м от оси при полуширине 6 м — уже не дорога")\
		.is_false()
	assert_bool(g.on_road(Vector3(60.0, 0.0, 34.641016))).is_false()


# --- Квадрат с диагональю ---------------------------------------------------

func test_square_with_diagonal_degrees() -> void:
	var g := _square_with_diagonal()
	assert_int(g.node_count()).is_equal(4)
	assert_int(g.edge_count()).is_equal(5)
	assert_int(g.node_degree(0))\
		.override_failure_message("угол A с диагональю: ожидалась степень 3, получено %d"
			% g.node_degree(0)).is_equal(3)
	assert_int(g.node_degree(2)).is_equal(3)
	assert_int(g.node_degree(1)).is_equal(2)
	assert_int(g.node_degree(3)).is_equal(2)


func test_square_approaches_sorted_by_angle() -> void:
	var g := _square_with_diagonal()
	# Из A(0,0) уходят: B(+X, угол 0), диагональ C(45°), D(+Z, 90°).
	assert_float(g.approach_angle(0, 0)).is_equal_approx(0.0, EPS)
	assert_float(g.approach_angle(0, 1)).is_equal_approx(PI * 0.25, EPS)
	assert_float(g.approach_angle(0, 2)).is_equal_approx(PI * 0.5, EPS)
	assert_int(g.approach_edge(0, 0)).is_equal(0)
	assert_int(g.approach_edge(0, 1)).is_equal(4)
	assert_int(g.approach_edge(0, 2)).is_equal(3)


func test_square_diagonal_wins_near_its_axis() -> void:
	# Точка (52, 48) лежит в 2.83 м от диагонали и в 48 м от сторон.
	var g := _square_with_diagonal()
	assert_int(g.query_nearest_edge(Vector3(52.0, 0.0, 48.0))).is_equal(4)
	assert_float(g.hit_dist)\
		.override_failure_message("ожидалось 2.828 м до диагонали, получено %.4f" % g.hit_dist)\
		.is_equal_approx(2.828427, EPS)


# --- T-образный перекрёсток -------------------------------------------------

func test_tee_degrees() -> void:
	var g := _tee()
	assert_int(g.node_degree(0))\
		.override_failure_message("центр T: ожидалась степень 3, получено %d"
			% g.node_degree(0)).is_equal(3)
	for n in [1, 2, 3]:
		assert_int(g.node_degree(n))\
			.override_failure_message("тупик %d: ожидалась степень 1, получено %d"
				% [n, g.node_degree(n)]).is_equal(1)


func test_tee_side_sign_flips_across_axis() -> void:
	var g := _tee()
	g.query_nearest_edge(Vector3(40.0, 0.0, 3.0))
	assert_int(g.hit_side).is_equal(CityGraph.Side.RIGHT)
	g.query_nearest_edge(Vector3(40.0, 0.0, -3.0))
	assert_int(g.hit_side).is_equal(CityGraph.Side.LEFT)
	g.query_nearest_edge(Vector3(40.0, 0.0, 0.0))
	assert_int(g.hit_side).is_equal(CityGraph.Side.ON_AXIS)


func test_tee_t_runs_from_a_to_b() -> void:
	var g := _tee()
	# Ребро 2 идёт от центра (a) к южному тупику (b), длина 80.
	g.query_nearest_edge(Vector3(0.0, 0.0, 20.0))
	assert_int(g.hit_edge).is_equal(2)
	assert_float(g.hit_t)\
		.override_failure_message("20 м из 80 — ожидалось t=0.25, получено %.4f" % g.hit_t)\
		.is_equal_approx(0.25, EPS)


# --- Кривое ребро -----------------------------------------------------------

func test_arc_polyline_is_not_a_chord() -> void:
	var g := _arc()
	assert_int(g.edge_point_count(0)).is_equal(10)
	# Длина ломаной из девяти хорд по 10°: 9 * 2 * 50 * sin(5°) = 78.44 м,
	# у прямой хорды между концами было бы 70.71 м.
	assert_float(g.edge_length(0))\
		.override_failure_message("ожидалось 78.44 м вдоль дуги, получено %.4f"
			% g.edge_length(0))\
		.is_equal_approx(78.4441, 0.01)


func test_arc_nearest_edge_measures_from_polyline() -> void:
	# Точка на луче 45° и радиусе 55. Хорда между 40° и 50° отстоит от центра
	# на 50*cos(5°) = 49.8096, значит до полотна 5.190 м — а не 5.0, как было
	# бы у идеальной окружности. Тест ловит подмену ломаной дугой.
	var g := _arc()
	var ang := deg_to_rad(45.0)
	var p := Vector3(55.0 * cos(ang), 0.0, 55.0 * sin(ang))
	assert_int(g.query_nearest_edge(p)).is_equal(0)
	assert_float(g.hit_dist)\
		.override_failure_message("ожидалось 5.190 м до ломаной, получено %.4f" % g.hit_dist)\
		.is_equal_approx(5.1904, 0.01)
	assert_float(g.hit_t)\
		.override_failure_message("середина дуги, ожидалось t=0.5, получено %.4f" % g.hit_t)\
		.is_equal_approx(0.5, 0.01)


func test_polyline_ends_snap_to_nodes() -> void:
	# Полилиния приходит от генератора с собственной точностью; если её концы
	# не притянуть к узлам, лента мешера отойдёт от полотна поперечной улицы.
	var g := CityGraph.new()
	var a := g.add_node(Vector3(0.0, 0.0, 0.0))
	var b := g.add_node(Vector3(100.0, 0.0, 0.0))
	g.add_edge(a, b, PackedVector3Array([
		Vector3(0.7, 0.0, 0.4), Vector3(50.0, 0.0, 0.0), Vector3(99.3, 0.0, -0.4)]), WIDTH)
	g.build()
	assert_vector(g.edge_point(0, 0))\
		.override_failure_message("начало полилинии должно совпасть с узлом A")\
		.is_equal(Vector3(0.0, 0.0, 0.0))
	assert_vector(g.edge_point(0, 2))\
		.override_failure_message("конец полилинии должен совпасть с узлом B")\
		.is_equal(Vector3(100.0, 0.0, 0.0))


func test_arc_on_road_follows_curvature() -> void:
	var g := _arc()
	var ang := deg_to_rad(45.0)
	assert_bool(g.on_road(Vector3(55.0 * cos(ang), 0.0, 55.0 * sin(ang))))\
		.override_failure_message("5.19 м от полотна при полуширине 6 м — дорога")\
		.is_true()
	assert_bool(g.on_road(Vector3(58.0 * cos(ang), 0.0, 58.0 * sin(ang))))\
		.override_failure_message("8.19 м от полотна при полуширине 6 м — не дорога")\
		.is_false()
	# Точка внутри дуги, но далеко от полотна: хорда, а не сектор.
	assert_bool(g.on_road(Vector3(20.0, 0.0, 20.0))).is_false()


# --- Разноуровневое пересечение ---------------------------------------------

func test_overpass_nearest_edge_picks_own_level() -> void:
	var g := _overpass()
	# На улице под эстакадой: в плане оба полотна на нуле, различает высота.
	assert_int(g.query_nearest_edge(Vector3(20.0, 0.1, 0.0)))\
		.override_failure_message("на земле ожидалось ребро улицы (1), получено %d"
			% g.hit_edge)\
		.is_equal(1)
	# На эстакаде над улицей.
	assert_int(g.query_nearest_edge(Vector3(0.0, 6.1, 20.0)))\
		.override_failure_message("на эстакаде ожидалось ребро моста (3), получено %d"
			% g.hit_edge)\
		.is_equal(3)


func test_overpass_at_crossing_point() -> void:
	# Ровно в точке пересечения планов: (x,z) совпадают, решает только высота.
	var g := _overpass()
	g.query_nearest_edge(Vector3(0.0, 0.2, 0.0))
	assert_int(g.edge_level(g.hit_edge))\
		.override_failure_message("на земле ожидался уровень 0, получен %d"
			% g.edge_level(g.hit_edge))\
		.is_equal(0)
	g.query_nearest_edge(Vector3(0.0, 5.8, 0.0))
	assert_int(g.edge_level(g.hit_edge))\
		.override_failure_message("на эстакаде ожидался уровень 1, получен %d"
			% g.edge_level(g.hit_edge))\
		.is_equal(1)


func test_overpass_gap_between_levels_is_not_road() -> void:
	# 3 м над улицей и 3 м под эстакадой — ни одного уровня, дороги нет.
	var g := _overpass()
	assert_bool(g.on_road(Vector3(20.0, 3.0, 0.0)))\
		.override_failure_message("зазор между уровнями не должен считаться дорогой")\
		.is_false()
	assert_bool(g.on_road(Vector3(20.0, 0.1, 0.0))).is_true()
	assert_bool(g.on_road(Vector3(0.0, 6.1, 20.0))).is_true()


func test_overpass_nearest_node_disambiguates_by_height() -> void:
	# Узлы 1 и 4 стоят в одной точке плана (0, 0) на разных ярусах.
	var g := _overpass()
	assert_vector(Vector2(g.node_position(1).x, g.node_position(1).z))\
		.is_equal(Vector2(g.node_position(4).x, g.node_position(4).z))
	assert_int(g.nearest_node(Vector3(0.0, 0.2, 0.0)))\
		.override_failure_message("с земли ожидался узел улицы (1)").is_equal(1)
	assert_int(g.nearest_node(Vector3(0.0, 5.8, 0.0)))\
		.override_failure_message("с эстакады ожидался узел моста (4)").is_equal(4)
	assert_int(g.node_level(4)).is_equal(1)


# --- Кольцо -----------------------------------------------------------------

func test_roundabout_node_carries_radius_and_ordered_approaches() -> void:
	var g := CityGraph.new()
	var r := g.add_node(Vector3.ZERO, 0, CityGraph.NodeKind.ROUNDABOUT, 20.0)
	var e := g.add_node(Vector3(60.0, 0.0, 0.0))
	var s := g.add_node(Vector3(0.0, 0.0, 60.0))
	var w := g.add_node(Vector3(-60.0, 0.0, 0.0))
	var n := g.add_node(Vector3(0.0, 0.0, -60.0))
	var e_east := g.add_edge(r, e, PackedVector3Array(), WIDTH)
	var e_south := g.add_edge(r, s, PackedVector3Array(), WIDTH)
	var e_west := g.add_edge(r, w, PackedVector3Array(), WIDTH)
	var e_north := g.add_edge(r, n, PackedVector3Array(), WIDTH)
	g.build()

	assert_int(g.node_kind(r)).is_equal(CityGraph.NodeKind.ROUNDABOUT)
	assert_float(g.node_radius(r)).is_equal_approx(20.0, EPS)
	assert_int(g.node_degree(r)).is_equal(4)
	# Подходы упорядочены по возрастанию atan2(dz, dx): север(-pi/2),
	# восток(0), юг(+pi/2), запад(pi).
	assert_array([g.approach_edge(r, 0), g.approach_edge(r, 1),
			g.approach_edge(r, 2), g.approach_edge(r, 3)])\
		.is_equal([e_north, e_east, e_south, e_west])
	for k in 3:
		assert_float(g.approach_angle(r, k))\
			.override_failure_message("подходы кольца должны идти по возрастанию угла")\
			.is_less(g.approach_angle(r, k + 1))


# --- Бюджет -----------------------------------------------------------------

func test_queries_do_not_scan_all_edges() -> void:
	# Сетка 9x9: 81 узел, 144 ребра. on_road зовётся каждый кадр десятками
	# агентов — он обязан идти через хеш, а не перебором всех рёбер.
	var g := CityGraph.new()
	for i in 9:
		for j in 9:
			g.add_node(Vector3(-256.0 + i * 64.0, 0.0, -256.0 + j * 64.0))
	for i in 9:
		for j in 9:
			var id := i * 9 + j
			if i + 1 < 9:
				g.add_edge(id, id + 9, PackedVector3Array(), WIDTH)
			if j + 1 < 9:
				g.add_edge(id, id + 1, PackedVector3Array(), WIDTH)
	g.build()
	assert_int(g.node_count()).is_equal(81)
	assert_int(g.edge_count()).is_equal(144)

	var hits := 0
	var t0 := Time.get_ticks_usec()
	for k in 20000:
		var x := -256.0 + float(k % 512)
		var z := -256.0 + float((k * 7) % 512)
		if g.on_road(Vector3(x, 0.0, z)):
			hits += 1
	var us := Time.get_ticks_usec() - t0
	assert_int(hits).is_greater(0)
	# Замер на этой машине — 90-145 мс. Перебор всех 144 рёбер на том же
	# наборе точек стоит 117 мкс на запрос, то есть 2.3 с на 20000: потолок
	# держит запас на медленную машину и всё равно ловит потерю хеша.
	assert_int(us)\
		.override_failure_message("20000 запросов on_road заняли %d мкс" % us)\
		.is_less(400_000)
