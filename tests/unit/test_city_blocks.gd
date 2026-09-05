extends GdUnitTestSuite
## Спецификация разбивки города на кварталы (`CityBlocks`).
##
## Кварталы — грани планарного графа улиц, а не таблица индексов, поэтому
## главная проверка здесь арифметическая: сумма площадей граней обязана
## сойтись с площадью внешней грани. Любая потерянная или посчитанная дважды
## грань это равенство ломает.

## Допуск на площадь, м²: полилинии хранятся во float32.
const AREA_EPS := 1.0

var _field: CityField
var _topo: PyatigorskTopology
var _graph: CityGraph
var _blocks: CityBlocks


func before_test() -> void:
	var balance: BalanceData = load("res://data/balance/balance.tres")
	_field = CityField.new(balance)
	_topo = PyatigorskTopology.new()
	_graph = _topo.build(_field)
	_blocks = CityBlocks.new()
	_blocks.build(_graph, _topo.node_district, _topo.landmark_node)


# --- Разбивка ---------------------------------------------------------------

func test_blocks_cover_the_whole_city() -> void:
	# Внешняя грань обходит город снаружи, её площадь по построению равна
	# сумме площадей внутренних. Расхождение = потерянная или задвоенная грань.
	var sum := 0.0
	for b in _blocks.count():
		sum += _blocks.area(b)
	assert_float(sum)\
		.override_failure_message(
			"сумма площадей %d кварталов %.1f м², внешняя грань %.1f м² — расхождение %.2f м²"
			% [_blocks.count(), sum, _blocks.outer_area, sum - _blocks.outer_area])\
		.is_equal_approx(_blocks.outer_area, AREA_EPS)


func test_block_count_matches_the_topology() -> void:
	# 28 кварталов против 64 клеток сетки 8x8: настоящая сеть улиц реже и
	# неоднороднее. Границы теста широкие — это защита от вырождения
	# разбивки (одна грань на весь город или сотня осколков), а не заморозка
	# конкретного числа.
	assert_int(_blocks.count())\
		.override_failure_message("кварталов получилось %d" % _blocks.count())\
		.is_between(20, 40)


func test_every_block_is_a_closed_polygon() -> void:
	for b in _blocks.count():
		assert_int(_blocks.polygon_size(b))\
			.override_failure_message("квартал %d: вершин %d, меньше трёх"
				% [b, _blocks.polygon_size(b)])\
			.is_greater_equal(3)
		assert_int(_blocks.boundary_count(b))\
			.override_failure_message("квартал %d: рёбер границы %d"
				% [b, _blocks.boundary_count(b)])\
			.is_greater_equal(3)
		assert_float(_blocks.area(b))\
			.override_failure_message("квартал %d вырожден: площадь %.2f м²"
				% [b, _blocks.area(b)])\
			.is_greater(CityBlocks.MIN_AREA - AREA_EPS)


func test_polygons_are_traversed_counterclockwise() -> void:
	# Ориентация — часть контракта: застройщик по ней определяет, где
	# внутренность квартала, и при обратном обходе поставил бы дома наружу.
	for b in _blocks.count():
		assert_float(CityBlocks.signed_area(_blocks.polygon(b)))\
			.override_failure_message("квартал %d обойдён в обратную сторону" % b)\
			.is_greater(0.0)


func test_centroid_lies_inside_its_block() -> void:
	for b in _blocks.count():
		assert_bool(_blocks.contains(b, _blocks.centroid(b)))\
			.override_failure_message("центр квартала %d (%.1f, %.1f) вне его полигона"
				% [b, _blocks.centroid(b).x, _blocks.centroid(b).y])\
			.is_true()


func test_boundary_edges_are_ground_level() -> void:
	# Дека путепровода пересекает улицу Крайнего без общего узла: если бы она
	# попала в разбивку, грань в этом месте была бы самопересекающейся.
	for b in _blocks.count():
		for k in _blocks.boundary_count(b):
			var e := _blocks.boundary_edge(b, k)
			assert_int(_graph.edge_level(e))\
				.override_failure_message(
					"квартал %d ограничен ребром %d яруса %d — это эстакада"
					% [b, e, _graph.edge_level(e)])\
				.is_equal(0)


func test_dead_ends_are_not_block_boundaries() -> void:
	# Тупики (переулок к Гроту, дорога на Машук, серпантин) граней не
	# образуют; попади они в границу — обход прошёл бы по ребру дважды.
	var used: Dictionary[int, int] = {}
	for b in _blocks.count():
		for k in _blocks.boundary_count(b):
			var e := _blocks.boundary_edge(b, k)
			used[e] = used.get(e, 0) + 1
			assert_int(used[e])\
				.override_failure_message("ребро %d вошло в границы %d раз"
					% [e, used[e]])\
				.is_less_equal(2)
	var grot := _graph.node_position(_topo.landmark_node[&"grot"])
	assert_int(_blocks.block_at(Vector2(grot.x, grot.z)))\
		.override_failure_message("тупиковый узел Грота не попал внутрь квартала")\
		.is_greater_equal(0)


# --- Районы и особые кварталы -----------------------------------------------

func test_every_block_has_a_known_district() -> void:
	var catalog: DistrictCatalog = load("res://data/districts/district_catalog.tres")
	catalog.index()
	for b in _blocks.count():
		assert_object(catalog.get_district(_blocks.district(b)))\
			.override_failure_message("квартал %d получил район '%s', которого нет в каталоге"
				% [b, _blocks.district(b)])\
			.is_not_null()


func test_landmarks_claim_at_most_one_block_each() -> void:
	var claimed: Array[String] = []
	for b in _blocks.count():
		var id := String(_blocks.special(b))
		if id.is_empty():
			continue
		assert_bool(claimed.has(id))\
			.override_failure_message("лендмарк %s занял два квартала, второй — %d"
				% [id, b])\
			.is_false()
		claimed.append(id)
	# Цветник, Провал и Грот стоят у кварталов, рынок и вокзал — на кольцах,
	# и участком им служит сам остров.
	assert_int(claimed.size())\
		.override_failure_message("кварталы заняли %d лендмарков из 9: %s"
			% [claimed.size(), claimed])\
		.is_between(3, 6)
	assert_bool(claimed.has("grot"))\
		.override_failure_message(
			"Грот стоит внутри квартала, а квартал не помечен; помечены: %s" % [claimed])\
		.is_true()


func test_landmark_blocks_touch_their_landmark() -> void:
	for b in _blocks.count():
		var id := _blocks.special(b)
		if id.is_empty():
			continue
		var p := _graph.node_position(_topo.landmark_node[id])
		var flat := Vector2(p.x, p.z)
		var touches := _blocks.contains(b, flat)
		for k in _blocks.boundary_count(b):
			touches = touches or _graph.node_position(
				_blocks.boundary_node(b, k)).is_equal_approx(p)
		assert_bool(touches)\
			.override_failure_message(
				"квартал %d отдан лендмарку %s, до которого от него далеко" % [b, id])\
			.is_true()


# --- Детерминизм ------------------------------------------------------------

func test_split_is_deterministic() -> void:
	var again := CityBlocks.new()
	again.build(_graph, _topo.node_district, _topo.landmark_node)
	assert_int(again.count()).is_equal(_blocks.count())
	for b in _blocks.count():
		assert_array(again.polygon(b))\
			.override_failure_message("квартал %d разошёлся при повторной разбивке" % b)\
			.is_equal(_blocks.polygon(b))
		assert_str(String(again.special(b))).is_equal(String(_blocks.special(b)))
		assert_str(String(again.district(b))).is_equal(String(_blocks.district(b)))
