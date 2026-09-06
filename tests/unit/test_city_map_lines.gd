extends GdUnitTestSuite
## Проекция графа улиц для карт (`CityMapLines`). Инвариант этапа 9: карты
## показывают ту же геометрию, что и мир, — то есть ВСЕ рёбра графа, с их
## настоящей формой и шириной, а не девять прямых из старого хардкода.
##
## Все проверки идут циклом по 94 рёбрам и 463 точкам топологии, поэтому у
## каждой из них своё сообщение с номером ребра/точки: без него падение
## говорит «ожидалось true» и не говорит, где именно.

var _graph: CityGraph
var _lines: CityMapLines


func before() -> void:
	var field := CityField.new(Db.balance)
	_graph = PyatigorskTopology.new().build(field)
	_lines = CityMapLines.of(_graph)


func test_projects_every_edge_with_every_point() -> void:
	assert_int(_lines.edge_count()).is_equal(_graph.edge_count())
	assert_int(_lines.start.size()).is_equal(_graph.edge_count() + 1)
	for e in _graph.edge_count():
		var count := _lines.start[e + 1] - _lines.start[e]
		assert_int(count)\
			.override_failure_message("ребро %d: в проекции %d точек, в графе %d"
				% [e, count, _graph.edge_point_count(e)])\
			.is_equal(_graph.edge_point_count(e))


func test_point_is_plan_projection_of_polyline() -> void:
	# Вид сверху берёт (x, z); высота полилинии карте не нужна и потерять её
	# здесь — намеренно, а не по недосмотру.
	for e in _graph.edge_count():
		var base := _lines.start[e]
		for k in _graph.edge_point_count(e):
			var p := _graph.edge_point(e, k)
			assert_vector(_lines.points[base + k])\
				.override_failure_message(
					"ребро %d, точка %d: в проекции %s, в графе (x, z) = (%.3f, %.3f)"
					% [e, k, _lines.points[base + k], p.x, p.z])\
				.is_equal(Vector2(p.x, p.z))


func test_edge_box_contains_all_its_points() -> void:
	for e in _lines.edge_count():
		var b := _lines.box[e]
		for i in range(_lines.start[e], _lines.start[e + 1]):
			var p := _lines.points[i]
			var k := i - _lines.start[e]
			assert_bool(p.x >= b.x and p.x <= b.z)\
				.override_failure_message(
					"ребро %d, точка %d: x = %.3f вне габарита ребра [%.3f, %.3f]"
					% [e, k, p.x, b.x, b.z])\
				.is_true()
			assert_bool(p.y >= b.y and p.y <= b.w)\
				.override_failure_message(
					"ребро %d, точка %d: z = %.3f вне габарита ребра [%.3f, %.3f]"
					% [e, k, p.y, b.y, b.w])\
				.is_true()


func test_bounds_cover_the_whole_city() -> void:
	# Допуск, а не `Rect2.encloses`: габарит хранится как «угол + размер» в
	# float32, и у крайнего ребра сумма position + size промахивается мимо
	# своей же координаты на последний бит — карте это безразлично (её поле
	# 24 px), а строгая проверка на этом падает.
	var eps := 1.0e-3
	var lo := _lines.bounds.position
	var hi := _lines.bounds.end
	for e in _lines.edge_count():
		var b := _lines.box[e]
		var inside := b.x >= lo.x - eps and b.y >= lo.y - eps \
			and b.z <= hi.x + eps and b.w <= hi.y + eps
		assert_bool(inside)\
			.override_failure_message(
				"ребро %d: габарит (%.3f, %.3f)-(%.3f, %.3f) вылез за габарит города (%.3f, %.3f)-(%.3f, %.3f) при допуске %.4f"
				% [e, b.x, b.y, b.z, b.w, lo.x, lo.y, hi.x, hi.y, eps])\
			.is_true()
	# Кольцо шире своего узла: его внешняя кромка обязана попасть в габарит,
	# иначе большая карта срежет край города вместе с ним.
	for k in _lines.ring_pos.size():
		var c := _lines.ring_pos[k]
		var r: float = _lines.ring_radius[k] + _lines.ring_width[k] * 0.5
		var fits := c.x - r >= lo.x - eps and c.y - r >= lo.y - eps \
			and c.x + r <= hi.x + eps and c.y + r <= hi.y + eps
		assert_bool(fits)\
			.override_failure_message(
				"кольцо %d: центр (%.3f, %.3f), внешняя кромка %.3f м — вылезло за габарит города (%.3f, %.3f)-(%.3f, %.3f)"
				% [k, c.x, c.y, r, lo.x, lo.y, hi.x, hi.y])\
			.is_true()


func test_touches_accepts_own_points_and_rejects_far_circle() -> void:
	# Круг вокруг любой точки ребра обязан это ребро задеть, а круг вокруг
	# точки за сто километров — ни одного: на этом стоит отсев миникарты.
	var far := Vector2(1.0e5, 1.0e5)
	for e in _lines.edge_count():
		var first: Vector2 = _lines.points[_lines.start[e]]
		assert_bool(_lines.touches(e, first, 0.1))\
			.override_failure_message(
				"ребро %d: круг радиусом 0.1 м вокруг его же первой точки (%.3f, %.3f) его не задел"
				% [e, first.x, first.y])\
			.is_true()
		assert_bool(_lines.touches(e, far, 1000.0))\
			.override_failure_message(
				"ребро %d: круг радиусом 1000 м в точке (%.0f, %.0f), в 140 км от города, его задел"
				% [e, far.x, far.y])\
			.is_false()


func test_width_comes_from_the_edge_not_from_a_constant() -> void:
	# Проспект Кирова (18 м) обязан рисоваться шире переулка (8 м) — ради
	# этого ширина и берётся per-edge, а не одной константой поля.
	var widths := {}
	for e in _lines.edge_count():
		assert_float(_lines.width[e])\
			.override_failure_message("ребро %d: ширина в проекции %.2f м, в графе %.2f м"
				% [e, _lines.width[e], _graph.edge_width(e)])\
			.is_equal(_graph.edge_width(e))
		widths[_lines.width[e]] = true
	assert_int(widths.size()).is_greater(1)


func test_elevated_edges_get_their_own_color() -> void:
	# Решение этапа 9 по мостам: вид сверху не различает ярусы, значит
	# путепровод обязан отличаться от улицы под ним хотя бы цветом.
	var elevated := 0
	for e in _lines.edge_count():
		var kind := _graph.edge_kind(e)
		if kind == CityGraph.EdgeKind.BRIDGE or kind == CityGraph.EdgeKind.RAMP:
			elevated += 1
			assert_object(_lines.color[e])\
				.override_failure_message(
					"ребро %d («%s», вид %d — мост или пандус): ожидался цвет эстакады %s, получен %s"
					% [e, _graph.edge_name(e), kind, CityMapLines.COLOR_ELEVATED,
						_lines.color[e]])\
				.is_equal(CityMapLines.COLOR_ELEVATED)
		elif kind == CityGraph.EdgeKind.TUNNEL:
			assert_object(_lines.color[e])\
				.override_failure_message(
					"ребро %d («%s», вид %d — тоннель): ожидался цвет тоннеля %s, получен %s"
					% [e, _graph.edge_name(e), kind, CityMapLines.COLOR_TUNNEL,
						_lines.color[e]])\
				.is_equal(CityMapLines.COLOR_TUNNEL)
		else:
			assert_object(_lines.color[e])\
				.override_failure_message(
					"ребро %d («%s», вид %d — наземная улица): ожидался цвет улицы %s, получен %s"
					% [e, _graph.edge_name(e), kind, CityMapLines.COLOR_ROAD,
						_lines.color[e]])\
				.is_equal(CityMapLines.COLOR_ROAD)
	# Путепровод улицы Козлова с двумя пандусами — иначе проверка выше пуста.
	assert_int(elevated).is_greater(0)


func test_every_roundabout_node_becomes_a_ring() -> void:
	var rings := 0
	for n in _graph.node_count():
		if _graph.node_kind(n) == CityGraph.NodeKind.ROUNDABOUT:
			rings += 1
	assert_int(_lines.ring_pos.size()).is_equal(rings)
	assert_int(rings).is_greater(0)
	for k in rings:
		assert_float(_lines.ring_radius[k])\
			.override_failure_message("кольцо %d: радиус %.2f м, ожидался положительный"
				% [k, _lines.ring_radius[k]])\
			.is_greater(0.0)
		# Полотно кольца не уже улицы, с которой на него въезжают.
		assert_float(_lines.ring_width[k])\
			.override_failure_message(
				"кольцо %d: ширина полотна %.2f м, ожидалась положительная — она берётся по самому широкому подходу"
				% [k, _lines.ring_width[k]])\
			.is_greater(0.0)
