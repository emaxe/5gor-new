extends GdUnitTestSuite
## Спецификация топологии Пятигорска (`PyatigorskTopology`).
##
## Синтетические графы `test_city_graph.gd` проверяют сам движок графа; здесь
## проверяется содержимое: связность реальной топологии (сетка 9x9 была связна
## по построению — `road_graph.gd:9-13`, эта уже нет), отсутствие пересечений
## полилиний мимо узлов, привязки лендмарков и районов, детерминизм.

## Допуск на расстояния: полилинии хранятся во float32 PackedVector3Array.
const EPS := 0.01
## Целевой масштаб топологии из плана: сопоставимо с 81 перекрёстком сетки.
const NODES_MIN := 60
const NODES_MAX := 100

var _field: CityField
var _topo: PyatigorskTopology
var _graph: CityGraph


func before_test() -> void:
	var balance: BalanceData = load("res://data/balance/balance.tres")
	_field = CityField.new(balance)
	_topo = PyatigorskTopology.new()
	_graph = _topo.build(_field)


# --- Масштаб ----------------------------------------------------------------

func test_graph_scale_matches_plan_budget() -> void:
	var n := _graph.node_count()
	assert_int(n)\
		.override_failure_message(
			"план требует %d-%d узлов (сегодня 81 перекрёсток сетки), получено %d"
			% [NODES_MIN, NODES_MAX, n])\
		.is_between(NODES_MIN, NODES_MAX)
	assert_int(_graph.edge_count())\
		.override_failure_message("рёбер должно быть больше узлов, получено %d при %d узлах"
			% [_graph.edge_count(), n])\
		.is_greater(n)
	assert_int(_topo.node_district.size())\
		.override_failure_message("район задан не для всех узлов: %d из %d"
			% [_topo.node_district.size(), n])\
		.is_equal(n)


func test_periphery_is_sparser_than_centre() -> void:
	# Плотность сети падает от центра к окраине — сегодня она одинакова по
	# всему городу. Средняя степень узла центра обязана быть выше пригородной.
	assert_float(_mean_degree(&"center"))\
		.override_failure_message(
			"центр (%.2f) должен быть плотнее пригорода (%.2f) по средней степени узла"
			% [_mean_degree(&"center"), _mean_degree(&"prigorod")])\
		.is_greater(_mean_degree(&"prigorod"))


# --- Связность --------------------------------------------------------------

func test_all_nodes_are_reachable() -> void:
	# Проверка обходом, а не «сетка всегда связна»: у топологии с тупиками,
	# горной веткой и путепроводом это уже не следует из построения.
	var seen := _reachable_from(0)
	var lost := PackedInt32Array()
	for n in _graph.node_count():
		if not seen[n]:
			lost.append(n)
	assert_int(lost.size())\
		.override_failure_message(
			"из узла 0 недостижимы %d узлов из %d: %s"
			% [lost.size(), _graph.node_count(), lost])\
		.is_equal(0)


func test_no_isolated_node() -> void:
	for n in _graph.node_count():
		assert_int(_graph.node_degree(n))\
			.override_failure_message("узел %d (%s) имеет степень 0"
				% [n, _topo.node_district[n]])\
			.is_greater(0)


# --- Геометрия --------------------------------------------------------------

func test_edge_polylines_do_not_self_intersect() -> void:
	for e in _graph.edge_count():
		var pts := _graph.edge_polyline(e)
		for i in range(pts.size() - 1):
			for j in range(i + 2, pts.size() - 1):
				var hit: Variant = Geometry2D.segment_intersects_segment(
					Vector2(pts[i].x, pts[i].z), Vector2(pts[i + 1].x, pts[i + 1].z),
					Vector2(pts[j].x, pts[j].z), Vector2(pts[j + 1].x, pts[j + 1].z))
				assert_bool(hit == null)\
					.override_failure_message(
						"ребро %d «%s» пересекает само себя: сегменты %d и %d, точка %s"
						% [e, _graph.edge_name(e), i, j, hit])\
					.is_true()


func test_same_level_edges_cross_only_at_shared_nodes() -> void:
	# Две улицы одного яруса, не имеющие общего узла, не должны пересекаться
	# в плане: иначе на схеме перекрёсток есть, а в графе его нет — трафик
	# проедет сквозь встречный поток. Пересечение на РАЗНЫХ ярусах законно,
	# это и есть путепровод у вокзала.
	var crossings := PackedStringArray()
	for a in _graph.edge_count():
		for b in range(a + 1, _graph.edge_count()):
			if _graph.edge_level(a) != _graph.edge_level(b):
				continue
			if _shares_node(a, b):
				continue
			var at := _first_crossing(a, b)
			if at != Vector2.INF:
				crossings.append("«%s» x «%s» в (%.1f, %.1f)"
					% [_graph.edge_name(a), _graph.edge_name(b), at.x, at.y])
	assert_int(crossings.size())\
		.override_failure_message("пересечений мимо узлов: %d — %s"
			% [crossings.size(), ", ".join(crossings)])\
		.is_equal(0)


# --- Хребет и сетка ---------------------------------------------------------

func test_main_axes_are_named_and_dominate() -> void:
	var kirov := _street_length(PyatigorskTopology.NAME_KIROV)
	var kalinin := _street_length(PyatigorskTopology.NAME_KALININ)
	assert_float(kirov)\
		.override_failure_message("проспект Кирова не найден в графе по имени")\
		.is_greater(0.0)
	assert_float(kalinin)\
		.override_failure_message("улица Калинина не найдена в графе по имени")\
		.is_greater(0.0)
	# Обе оси длиннее любой обычной улицы; серпантин не в счёт — это
	# горная дорога, а не улица города.
	for street: String in _street_names():
		if street == PyatigorskTopology.NAME_KIROV \
				or street == PyatigorskTopology.NAME_KALININ \
				or street == "серпантин на Машук":
			continue
		assert_float(_street_length(street))\
			.override_failure_message(
				"улица «%s» (%.1f м) не должна быть длиннее оси Калинина (%.1f м)"
				% [street, _street_length(street), kalinin])\
			.is_less(kalinin)


func test_kirov_is_the_widest_road() -> void:
	for e in _graph.edge_count():
		if _graph.edge_name(e) == PyatigorskTopology.NAME_KIROV:
			assert_float(_graph.edge_width(e))\
				.override_failure_message("проспект Кирова должен быть шириной %.1f м, ребро %d — %.1f м"
					% [PyatigorskTopology.W_AVENUE, e, _graph.edge_width(e)])\
				.is_equal_approx(PyatigorskTopology.W_AVENUE, EPS)
			continue
		assert_float(_graph.edge_width(e))\
			.override_failure_message(
				"ребро %d «%s» шириной %.1f м не должно спорить с проспектом (%.1f м)"
				% [e, _graph.edge_name(e), _graph.edge_width(e),
					PyatigorskTopology.W_AVENUE])\
			.is_less(PyatigorskTopology.W_AVENUE)


# --- Рельеф, мост, серпантин ------------------------------------------------

func test_serpentine_plan_length_is_unchanged() -> void:
	# Серпантин встроен в граф готовой полилинией `serpentine_points()`, а не
	# переписан заново: его длина в плане обязана совпасть с CityField.
	var plan := 0.0
	var count := 0
	for e in _graph.edge_count():
		if _graph.edge_kind(e) != CityGraph.EdgeKind.SERPENTINE:
			continue
		count += 1
		for k in range(1, _graph.edge_point_count(e)):
			var p0 := _graph.edge_point(e, k - 1)
			var p1 := _graph.edge_point(e, k)
			plan += Vector2(p0.x, p0.z).distance_to(Vector2(p1.x, p1.z))
	assert_int(count)\
		.override_failure_message("серпантин должен быть рёбрами графа, найдено %d" % count)\
		.is_greater(0)
	assert_float(plan)\
		.override_failure_message("длина серпантина в плане %.2f м, в CityField %.2f м"
			% [plan, _field.serpentine_length()])\
		.is_equal_approx(_field.serpentine_length(), 0.5)


func test_elevation_profile_exists_outside_serpentine() -> void:
	# Данные для этапа 3: подъём есть не только на серпантине, иначе мост и
	# уклон проектировать будет негде.
	var best := -1
	var gain := 0.0
	for e in _graph.edge_count():
		if _graph.edge_kind(e) == CityGraph.EdgeKind.SERPENTINE:
			continue
		var lo := INF
		var hi := -INF
		for k in _graph.edge_point_count(e):
			var y := _graph.edge_point(e, k).y
			lo = minf(lo, y)
			hi = maxf(hi, y)
		if hi - lo > gain:
			gain = hi - lo
			best = e
	assert_float(gain)\
		.override_failure_message(
			"вне серпантина максимальный перепад высоты %.1f м (ребро «%s») — мало для этапа 3"
			% [gain, "" if best < 0 else _graph.edge_name(best)])\
		.is_greater(8.0)


func test_overpass_clears_the_street_below() -> void:
	var deck := -1
	for e in _graph.edge_count():
		if _graph.edge_kind(e) == CityGraph.EdgeKind.BRIDGE:
			deck = e
	assert_int(deck)\
		.override_failure_message("разноуровневое пересечение не найдено: нет ребра kind=BRIDGE")\
		.is_greater_equal(0)
	assert_int(_graph.edge_level(deck))\
		.override_failure_message("пролёт путепровода должен быть на ярусе 1, получен %d"
			% _graph.edge_level(deck))\
		.is_equal(1)

	# Под серединой пролёта обязана проходить улица нижнего яруса — иначе
	# «мост» стоит в чистом поле и этапу 3 нечего разводить по высоте.
	var mid := _graph.edge_point(deck, 0).lerp(
		_graph.edge_point(deck, _graph.edge_point_count(deck) - 1), 0.5)
	var below := _graph.query_nearest_edge(Vector3(mid.x, 0.0, mid.z), 40.0)
	assert_int(below)\
		.override_failure_message("под серединой путепровода (%.1f, %.1f) нет улицы"
			% [mid.x, mid.z])\
		.is_greater_equal(0)
	assert_int(_graph.edge_level(below))\
		.override_failure_message("под путепроводом ожидался ярус 0, получен %d"
			% _graph.edge_level(below))\
		.is_equal(0)
	assert_float(_graph.hit_dist)\
		.override_failure_message(
			"улица под путепроводом должна проходить под самым пролётом, а не в %.1f м в стороне"
			% _graph.hit_dist)\
		.is_less(_graph.edge_width(below) * 0.5 + 1.0)
	# Просвет считается от НИЗА плиты; тонкости геометрии моста проверяет
	# `test_bridge_geometry.gd`, здесь довольно отметки полотна деки.
	var clearance := mid.y - _graph.hit_point.y
	assert_float(clearance)\
		.override_failure_message("клиренс путепровода %.2f м, минимум %.1f м"
			% [clearance, CityGraph.MIN_CLEARANCE])\
		.is_greater(CityGraph.MIN_CLEARANCE)


# --- Привязки ---------------------------------------------------------------

func test_every_landmark_is_bound_to_the_graph() -> void:
	var catalog: DistrictCatalog = load("res://data/districts/district_catalog.tres")
	catalog.index()
	assert_int(catalog.landmarks.size())\
		.override_failure_message("в каталоге ожидалось 9 лендмарков, найдено %d"
			% catalog.landmarks.size())\
		.is_equal(9)
	for lm in catalog.landmarks:
		var node: int = _topo.landmark_node.get(lm.id, -1)
		assert_int(node)\
			.override_failure_message("лендмарк %s не привязан к узлу графа" % lm.id)\
			.is_greater_equal(0)
		var p := _graph.node_position(node)
		var off := lm.position.distance_to(Vector2(p.x, p.z))
		# 3 м — половина полосы: узел стоит либо ровно в точке лендмарка,
		# либо в вершине полилинии серпантина рядом с ней.
		assert_float(off)\
			.override_failure_message(
				"узел лендмарка %s отстоит от его координат (%.0f, %.0f) на %.1f м"
				% [lm.id, lm.position.x, lm.position.y, off])\
			.is_less(3.0)


func test_landmark_off_the_carriageway_has_an_approach_edge() -> void:
	# Грот Лермонтова стоит в парке над Цветником, а не у полотна проспекта:
	# ему заведено подъездное ребро, а не просто узел на магистрали.
	var edge: int = _topo.landmark_approach.get(&"grot", -1)
	assert_int(edge)\
		.override_failure_message("у Грота Лермонтова нет подъездного ребра")\
		.is_greater_equal(0)
	var ends := _graph.edge_ends(edge)
	var grot: int = _topo.landmark_node[&"grot"]
	assert_bool(ends.x == grot or ends.y == grot)\
		.override_failure_message("подъездное ребро %d не касается узла Грота (%d)"
			% [edge, grot])\
		.is_true()
	assert_int(_graph.node_degree(grot))\
		.override_failure_message("Грот — тупик в парке, ожидалась степень 1, получено %d"
			% _graph.node_degree(grot))\
		.is_equal(1)


func test_every_district_owns_some_geometry() -> void:
	var catalog: DistrictCatalog = load("res://data/districts/district_catalog.tres")
	catalog.index()
	var seen: Dictionary[StringName, int] = {}
	for d in _topo.node_district:
		seen[d] = seen.get(d, 0) + 1
	for district in catalog.items:
		assert_int(seen.get(district.id, 0))\
			.override_failure_message(
				"район %s не получил ни одного узла — привязка к геометрии неполна"
				% district.id)\
			.is_greater(0)
	assert_int(seen.size())\
		.override_failure_message("узлам розданы районы вне каталога: %s" % [seen.keys()])\
		.is_equal(catalog.items.size())


func test_signalized_nodes_are_explicit_data() -> void:
	assert_int(_topo.signal_nodes.size())\
		.override_failure_message("список регулируемых узлов пуст — этапу 7 нечего читать")\
		.is_greater(0)
	for n in _topo.signal_nodes:
		assert_int(n).is_between(0, _graph.node_count() - 1)
		assert_int(_graph.node_kind(n))\
			.override_failure_message("узел %d — кольцо, светофора на нём быть не может" % n)\
			.is_equal(CityGraph.NodeKind.INTERSECTION)
		assert_int(_graph.node_degree(n))\
			.override_failure_message("светофор на узле %d степени %d — регулировать нечего"
				% [n, _graph.node_degree(n)])\
			.is_greater_equal(3)


func test_roundabouts_carry_a_radius() -> void:
	var rings := 0
	for n in _graph.node_count():
		if _graph.node_kind(n) != CityGraph.NodeKind.ROUNDABOUT:
			continue
		rings += 1
		assert_float(_graph.node_radius(n))\
			.override_failure_message("кольцо %d объявлено с радиусом %.1f м"
				% [n, _graph.node_radius(n)])\
			.is_greater(8.0)
	assert_int(rings)\
		.override_failure_message("колец в топологии не оказалось вовсе")\
		.is_greater(0)


# --- Детерминизм ------------------------------------------------------------

func test_rebuild_is_bitwise_identical() -> void:
	# Топология — литерал, `world_seed` на неё не влияет; повторный вызов
	# обязан дать тот же граф до последнего бита полилинии.
	var balance: BalanceData = load("res://data/balance/balance.tres")
	var again := PyatigorskTopology.new().build(CityField.new(balance))
	assert_str(PyatigorskTopology.digest(again))\
		.override_failure_message("повторное построение дало другой граф")\
		.is_equal(PyatigorskTopology.digest(_graph))


# --- Вспомогательное --------------------------------------------------------

func _reachable_from(start: int) -> Array[bool]:
	var seen: Array[bool] = []
	seen.resize(_graph.node_count())
	var queue := PackedInt32Array([start])
	seen[start] = true
	var head := 0
	while head < queue.size():
		var n := queue[head]
		head += 1
		for k in _graph.node_degree(n):
			var e := _graph.approach_edge(n, k)
			var ends := _graph.edge_ends(e)
			var other := ends.y if ends.x == n else ends.x
			if not seen[other]:
				seen[other] = true
				queue.append(other)
	return seen


func _shares_node(a: int, b: int) -> bool:
	var ea := _graph.edge_ends(a)
	var eb := _graph.edge_ends(b)
	return ea.x == eb.x or ea.x == eb.y or ea.y == eb.x or ea.y == eb.y


## Первая точка пересечения полилиний двух рёбер в плане; Vector2.INF — нет.
func _first_crossing(a: int, b: int) -> Vector2:
	var pa := _graph.edge_polyline(a)
	var pb := _graph.edge_polyline(b)
	for i in range(pa.size() - 1):
		for j in range(pb.size() - 1):
			var hit: Variant = Geometry2D.segment_intersects_segment(
				Vector2(pa[i].x, pa[i].z), Vector2(pa[i + 1].x, pa[i + 1].z),
				Vector2(pb[j].x, pb[j].z), Vector2(pb[j + 1].x, pb[j + 1].z))
			if hit != null:
				return hit
	return Vector2.INF


func _street_names() -> PackedStringArray:
	var out := PackedStringArray()
	for e in _graph.edge_count():
		var s := _graph.edge_name(e)
		if not s.is_empty() and not out.has(s):
			out.append(s)
	return out


func _street_length(street: String) -> float:
	var total := 0.0
	for e in _graph.edge_count():
		if _graph.edge_name(e) == street:
			total += _graph.edge_length(e)
	return total


func _mean_degree(district: StringName) -> float:
	var sum := 0
	var count := 0
	for n in _graph.node_count():
		if _topo.node_district[n] != district:
			continue
		sum += _graph.node_degree(n)
		count += 1
	return 0.0 if count == 0 else float(sum) / float(count)
