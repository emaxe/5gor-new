extends GdUnitTestSuite
## Спецификация этапа 4: полотно, тротуары, бордюры и геометрия узлов по графу.
##
## Главный инвариант здесь — **отсутствие дыр**: ось каждого ребра и полоса
## вокруг неё обязаны лежать на асфальте от узла до узла, включая горловины
## перекрёстков произвольной степени. Проверяется не «на глаз», а прогоном проб
## по всей топологии Пятигорска: 66 узлов, 94 ребра, степени от 1 до 5, три
## кольца. Обычная опечатка в контуре узла даёт не падение, а тихую щель в
## асфальте посреди перекрёстка, и поймать её может только такая проба.

## Шаг проб вдоль оси ребра, м.
const PROBE_STEP := 1.5
## Доля полуширины полотна, на которую пробы отходят от оси вбок. 0.85 — почти
## кромка: дыру ищем в том числе у края ленты, а не только по осевой.
const PROBE_LATERAL := 0.85
## Сторона клетки индекса треугольников, м.
const GRID_CELL := 8.0
## Допуск на попадание точки в треугольник, м² площади. Проба у самой кромки
## ленты лежит на границе грани, а вершины меша хранятся во float32: на торце
## ленты в тупике Верхней Машукской дороги проба промахивалась на 3e-4 м², то
## есть на 0.04 мм при длине кромки 8 м. Настоящая дыра — метры, не микроны.
const HIT_EPS := 1e-3
## Допуск на сравнение цвета вершины с палитрой: цвет проходит квантование
## RGBA8 при коммите меша.
const COLOR_EPS := 0.01
## Бюджет сборки полотна всего города, мс. Критерий готовности этапа — < 1 с на
## весь билд города, полотно — его малая часть; 250 мс с запасом внутри.
const BUILD_BUDGET_MS := 250.0

var _field: CityField
var _topo: PyatigorskTopology
var _graph: CityGraph
var _roads: RoadMesh
var _verts := PackedVector3Array()
var _colors := PackedColorArray()
var _index := PackedInt32Array()
var _normals := PackedVector3Array()
## Индекс асфальтовых граней по клеткам GRID_CELL: ключ — клетка, значение —
## номера первых индексов граней.
var _asphalt: Dictionary[Vector2i, PackedInt32Array] = {}
var _build_ms := 0.0


func before() -> void:
	var balance: BalanceData = load("res://data/balance/balance.tres")
	_field = CityField.new(balance)
	_topo = PyatigorskTopology.new()
	_graph = _topo.build(_field)
	var started := Time.get_ticks_usec()
	_roads = RoadMesh.new(_graph, _field)
	var b := MeshBuilder.new()
	_roads.build_mesh(b)
	var mesh := b.commit()
	_build_ms = (Time.get_ticks_usec() - started) / 1000.0
	var arrays := mesh.surface_get_arrays(0)
	_verts = arrays[Mesh.ARRAY_VERTEX]
	_colors = arrays[Mesh.ARRAY_COLOR]
	_index = arrays[Mesh.ARRAY_INDEX]
	_normals = arrays[Mesh.ARRAY_NORMAL]
	_index_asphalt()


# --- Полотно вдоль рёбер ----------------------------------------------------

func test_straight_edge_gets_a_road_ribbon() -> void:
	var e := _straight_edge()
	assert_int(e).override_failure_message(
		"в топологии не нашлось прямого ребра-проспекта").is_greater_equal(0)
	var pts := _graph.edge_polyline(e)
	var mid := (pts[0] + pts[pts.size() - 1]) * 0.5
	assert_bool(_covered(Vector2(mid.x, mid.z))).override_failure_message(
		"середина прямого ребра %d (%s) в (%.1f, %.1f) не покрыта полотном"
		% [e, _graph.edge_name(e), mid.x, mid.z]).is_true()


func test_curved_edge_follows_every_point_of_its_polyline() -> void:
	# Серпантин — 133 точки с набором высоты: лента обязана пройти по всем,
	# иначе уклон срежется хордой и машина поедет сквозь склон.
	var e := _find_kind(CityGraph.EdgeKind.SERPENTINE)
	assert_int(e).override_failure_message(
		"в топологии нет ребра-серпантина").is_greater_equal(0)
	var pts := _graph.edge_polyline(e)
	assert_int(pts.size()).override_failure_message(
		"серпантин задан %d точками — это не кривая" % pts.size())\
		.is_greater(10)
	var missed := 0
	var worst := Vector3.ZERO
	for p in pts:
		if not _covered(Vector2(p.x, p.z)):
			missed += 1
			worst = p
	assert_int(missed).override_failure_message(
		"%d из %d точек серпантина не покрыты полотном, например (%.1f, %.1f)"
		% [missed, pts.size(), worst.x, worst.z]).is_equal(0)


func test_curved_edge_keeps_its_elevation_profile() -> void:
	# Профиль высоты приходит из графа; лента обязана его повторить, а не
	# уложить серпантин плашмя.
	var e := _find_kind(CityGraph.EdgeKind.SERPENTINE)
	var pts := _graph.edge_polyline(e)
	var lo := INF
	var hi := -INF
	for p in pts:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	var rise := hi - lo
	assert_float(rise).override_failure_message(
		"серпантин набирает всего %.1f м — профиль потерян" % rise)\
		.is_greater(20.0)
	# Допуск сузился с 0.6 после отказа от _mountain_ribbon (посамплированные
	# по краям высоты, вертикальные юбки): плоская лента ribbon() кладёт все
	# точки сечения на единую высоту точки полилинии, а не на three
	# независимых height_at() — centroid соседних станций отличается от
	# точки не больше половины шага серпантина по уклону.
	for p in pts:
		var got := _road_height_at(Vector2(p.x, p.z))
		assert_float(got).override_failure_message(
			"в (%.1f, %.1f) полотно на высоте %.2f, а полилиния — %.2f"
			% [p.x, p.z, got, p.y]).is_equal_approx(p.y + CityMesher.Y_ROAD, 0.3)


func test_sidewalks_and_curbs_run_along_both_sides() -> void:
	var e := _straight_edge()
	var pts := _roads.road_polyline(e)
	var mid := (pts[0] + pts[pts.size() - 1]) * 0.5
	var dir := (pts[pts.size() - 1] - pts[0])
	dir.y = 0.0
	var normal := dir.normalized().cross(Vector3.UP)
	var half := _graph.edge_width(e) * 0.5
	for side: float in [-1.0, 1.0]:
		var walk := mid + normal * (side * (half + _field.sidewalk * 0.5))
		assert_bool(_has_color(Vector2(walk.x, walk.z), CityMesher.COLOR_SIDEWALK))\
			.override_failure_message(
				"тротуара нет со стороны %+.0f ребра %d в (%.1f, %.1f)"
				% [side, e, walk.x, walk.z]).is_true()
		var curb := mid + normal * (side * (half + RoadMesh.CURB_WIDTH * 0.5))
		assert_bool(_has_color(Vector2(curb.x, curb.z), CityMesher.COLOR_CURB))\
			.override_failure_message(
				"бордюра нет со стороны %+.0f ребра %d в (%.1f, %.1f)"
				% [side, e, curb.x, curb.z]).is_true()


func test_sidewalk_stays_outside_the_carriageway() -> void:
	# Тротуар, заехавший на полотно, — не косметика: он лежит выше асфальта
	# (Y_SIDEWALK > Y_ROAD) и машина въедет в невидимую ступеньку.
	var e := _straight_edge()
	var pts := _roads.road_polyline(e)
	var axis_a := Vector2(pts[0].x, pts[0].z)
	var axis_b := Vector2(pts[pts.size() - 1].x, pts[pts.size() - 1].z)
	var half := _graph.edge_width(e) * 0.5
	var inside := 0
	var worst := 0.0
	for i in range(0, _index.size(), 3):
		if not _is_color(_colors[_index[i]], CityMesher.COLOR_SIDEWALK):
			continue
		for k in 3:
			var v := _verts[_index[i + k]]
			var q := Vector2(v.x, v.z)
			var t := (q - axis_a).dot(axis_b - axis_a) / (axis_b - axis_a).length_squared()
			if t < 0.2 or t > 0.8:
				continue
			var d := absf((q - axis_a).cross(axis_b - axis_a) / (axis_b - axis_a).length())
			if d < half - 0.05:
				inside += 1
				worst = maxf(worst, half - d)
	assert_int(inside).override_failure_message(
		"%d вершин тротуара заехали на полотно ребра %d, глубже всего на %.2f м"
		% [inside, e, worst]).is_equal(0)


func test_bridge_edges_are_left_to_bridge_geometry() -> void:
	# Деку строит BridgeGeometry (этап 3). Если бы RoadMesh строил её тоже,
	# получилось бы два копланарных полотна с z-fighting.
	var e := _find_kind(CityGraph.EdgeKind.BRIDGE)
	assert_int(e).override_failure_message(
		"в топологии нет ребра-пролёта").is_greater_equal(0)
	var pts := _graph.edge_polyline(e)
	var mid := (pts[0] + pts[pts.size() - 1]) * 0.5
	var hits := 0
	for i in range(0, _index.size(), 3):
		var c := _centroid(i)
		if Vector2(c.x - mid.x, c.z - mid.z).length() < 4.0 \
				and absf(c.y - mid.y) < 2.0:
			hits += 1
	assert_int(hits).override_failure_message(
		"RoadMesh построил %d граней на середине пролёта — полотно деки задвоено"
		% hits).is_equal(0)


# --- Узлы -------------------------------------------------------------------

func test_no_holes_between_ribbons_and_junctions() -> void:
	# Полная проба по всей топологии: 66 узлов, 94 ребра, степени 1..5.
	var holes := PackedStringArray()
	var probes := 0
	for e in _graph.edge_count():
		if _graph.edge_kind(e) == CityGraph.EdgeKind.BRIDGE:
			continue
		var pts := _graph.edge_polyline(e)
		var half := _graph.edge_width(e) * 0.5 * PROBE_LATERAL
		for i in range(1, pts.size()):
			var seg := Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z)
			if seg.length() <= 0.0:
				continue
			var normal := seg.orthogonal().normalized()
			var steps := maxi(1, ceili(seg.length() / PROBE_STEP))
			for s in steps + 1:
				var p := pts[i - 1].lerp(pts[i], float(s) / float(steps))
				for lat: float in [-half, 0.0, half]:
					var q := Vector2(p.x + normal.x * lat, p.z + normal.y * lat)
					# Островок кольца — не полотно: подходы обрываются в
					# аннулюсе, а внутри него приподнятый сквер.
					if _in_ring_island(q):
						continue
					probes += 1
					if _covered(q):
						continue
					if holes.size() < 8:
						holes.append("ребро %d (%s) в (%.1f, %.1f)"
							% [e, _graph.edge_name(e), q.x, q.y])
	assert_int(probes).override_failure_message(
		"проб оказалось %d — граф пуст?" % probes).is_greater(5000)
	assert_int(holes.size()).override_failure_message(
		"полотно дырявое: из %d проб не покрыто минимум %d, например %s"
		% [probes, holes.size(), holes]).is_equal(0)


func test_junction_fan_covers_every_degree_from_three_to_five() -> void:
	# Пункт чек-листа: веер произвольной степени, не только N=4.
	for want: int in [3, 4, 5]:
		var nodes := _nodes_of_degree(want)
		assert_int(nodes.size()).override_failure_message(
			"в топологии нет ни одного узла степени %d — проверять нечего"
			% want).is_greater(0)
		for n: int in nodes:
			var c := _graph.node_position(n)
			assert_bool(_covered(Vector2(c.x, c.z))).override_failure_message(
				"центр узла %d степени %d в (%.1f, %.1f) не покрыт асфальтом"
				% [n, want, c.x, c.z]).is_true()
			# Горловина каждого подхода: от центра до точки среза ленты.
			for k in want:
				# Горловину пролёта мостит дека (этап 3), не RoadMesh.
				if _graph.edge_kind(_graph.approach_edge(n, k)) \
						== CityGraph.EdgeKind.BRIDGE:
					continue
				var trim := _roads.trim(n, k)
				var a := _graph.approach_angle(n, k)
				var dir := Vector2(cos(a), sin(a))
				var steps := maxi(1, ceili(trim / PROBE_STEP))
				for s in steps + 1:
					var q := Vector2(c.x, c.z) + dir * (trim * float(s) / float(steps))
					assert_bool(_covered(q)).override_failure_message(
						"горловина подхода %d узла %d (степень %d) не закрыта в (%.1f, %.1f), вылет %.1f м"
						% [k, n, want, q.x, q.y, trim]).is_true()


func test_flat_faces_point_up() -> void:
	# Правило рендера: у нового веерного примитива нормали проверяются тестом
	# сразу (`.agents/rules/rendering.md`, прецедент — `shadow_disc`). Веер узла
	# ориентирует каждую грань сам, по знаку площади в плане; поставленная
	# «наизнанку» грань с фронтальным cull_back исчезает молча, без ошибок в
	# консоли. Щёчка бордюра вертикальна и в проверку не попадает.
	#
	# Столбики отбойника (`RoadMesh._flush_rail`) — обычный `MeshBuilder.box()`,
	# у него, как у любого бокса, есть нижняя грань, и она по построению
	# смотрит вниз: это не «вывернутый веер», а невидимая (совпадает с
	# полотном) грань цоколя. Проверять её направление нормали нечем — box()
	# уже покрыт своим тестом в test_mesh_builder.gd.
	var normals: PackedVector3Array = _normals
	assert_int(normals.size()).override_failure_message(
		"в меше нет нормалей — SurfaceTool их не сгенерировал").is_greater(0)
	var flipped := 0
	var flat := 0
	var worst := 1.0
	for i in range(0, _index.size(), 3):
		var a := _verts[_index[i]]
		var b := _verts[_index[i + 1]]
		var c := _verts[_index[i + 2]]
		if absf(a.y - b.y) > 0.01 or absf(a.y - c.y) > 0.01:
			continue  # наклонная грань откоса или вертикальная щёчка бордюра
		if absf(_plan_area(i)) < RoadMesh.MIN_FACE_AREA:
			continue  # вырожденный квад ленты: площади нет, нормали тоже
		if _is_color(_colors[_index[i]], RoadMesh.COLOR_RAIL):
			continue  # цоколь столбика отбойника — см. комментарий выше
		flat += 1
		for k in 3:
			var ny := normals[_index[i + k]].y
			if ny < 0.9:
				flipped += 1
				worst = minf(worst, ny)
	assert_int(flat).override_failure_message(
		"горизонтальных граней в полотне %d — считать нечего" % flat)		.is_greater(1000)
	assert_int(flipped).override_failure_message(
		"%d вершин горизонтальных граней смотрят не вверх (худшая нормаль y=%.3f) — веер вывернут"
		% [flipped, worst]).is_equal(0)


func test_junction_polygon_has_no_degenerate_faces() -> void:
	# Вырожденная грань — признак того, что контур узла схлопнулся: веер
	# отдаёт нулевую площадь вместо асфальта.
	var bad := 0
	var worst := 0.0
	for i in range(0, _index.size(), 3):
		if not _is_color(_colors[_index[i]], CityMesher.COLOR_ROAD):
			continue
		var area := absf(_plan_area(i))
		if area < RoadMesh.MIN_FACE_AREA:
			bad += 1
			worst = area
	assert_int(bad).override_failure_message(
		"в полотне %d вырожденных граней (минимальная площадь %.5f м²)"
		% [bad, worst]).is_equal(0)


func test_corner_aprons_are_built_for_arbitrary_degree() -> void:
	# Угловые площадки: между соседними подходами узла обязан быть тротуар,
	# иначе на стыке видна дырка между лентами тротуаров двух улиц.
	for n in _graph.node_count():
		var deg := _graph.node_degree(n)
		if deg < 3 or _graph.node_kind(n) == CityGraph.NodeKind.ROUNDABOUT:
			continue
		for k in deg:
			var next := (k + 1) % deg
			# Сторона улицы, у которой тротуара нет (развилка съела его
			# целиком), угол замостить не может — там его и не ждём.
			if not _roads.approach_has_sidewalk(n, k, true):
				continue
			if not _roads.approach_has_sidewalk(n, next, false):
				continue
			var a0 := _graph.approach_angle(n, k)
			var span := _graph.approach_angle(n, next) - a0
			if span <= 0.0:
				span += TAU
			if span > PI:
				continue  # внешняя сторона излома, площадки там нет
			# Идём из центра узла наружу, пока не кончится асфальт: сразу за
			# его кромкой обязан начинаться тротуар (или бордюр на самой
			# кромке), иначе в углу перекрёстка вылезает трава.
			#
			# Два луча на 35% и 65% угла, а не один по биссектрисе: на
			# развилке угол площадки уходит ровно вдоль биссектрисы, и луч по
			# ней едет по самой кромке площадки — попадание там решает
			# арифметика float, а не геометрия.
			var c := _graph.node_position(n)
			for f: float in [0.35, 0.65]:
				var dir := Vector2(cos(a0 + span * f), sin(a0 + span * f))
				var edge_r := _road_edge_along(Vector2(c.x, c.z), dir)
				if edge_r < 0.0:
					continue  # луч вышел мимо полотна — угла как такового нет
				var q := Vector2(c.x, c.z) + dir * (edge_r + 1.0)
				assert_bool(_has_color(q, CityMesher.COLOR_SIDEWALK, 2.0)
						or _has_color(q, CityMesher.COLOR_CURB, 2.0))\
					.override_failure_message(
						"за кромкой полотна в углу подходов %d и %d узла %d (степень %d) нет тротуара: (%.1f, %.1f), кромка в %.1f м"
						% [k, next, n, deg, q.x, q.y, edge_r]).is_true()


func test_sidewalk_never_lies_on_the_carriageway() -> void:
	# Тротуар выше асфальта на 10 см: заехав на полосу, он становится
	# невидимой ступенькой поперёк дороги. Проверяется по всему городу.
	var bad := PackedStringArray()
	var total := 0
	for i in range(0, _index.size(), 3):
		if not _is_color(_colors[_index[i]], CityMesher.COLOR_SIDEWALK):
			continue
		total += 1
		var c := _centroid(i)
		if not _covered(Vector2(c.x, c.z)):
			continue
		if bad.size() < 8:
			bad.append("(%.1f, %.1f)" % [c.x, c.z])
	assert_int(total).override_failure_message(
		"тротуарных граней в городе %d — мешер их не построил" % total)\
		.is_greater(200)
	assert_int(bad.size()).override_failure_message(
		"%d тротуарных граней лежат на проезжей части, например %s"
		% [bad.size(), bad]).is_equal(0)


# --- Кольцо -----------------------------------------------------------------

func test_ring_annulus_is_continuous_and_reaches_every_approach() -> void:
	var rings := _ring_nodes()
	assert_int(rings.size()).override_failure_message(
		"в топологии нет ни одного кольца").is_greater(0)
	for n: int in rings:
		var c := _graph.node_position(n)
		var r := _graph.node_radius(n)
		# Осевая линия аннулюса — сплошное полотно по всей окружности.
		var steps := 180
		for s in steps:
			var a := TAU * float(s) / float(steps)
			var q := Vector2(c.x, c.z) + Vector2(cos(a), sin(a)) * r
			assert_bool(_covered(q)).override_failure_message(
				"аннулюс кольца %d разорван на %.0f° в (%.1f, %.1f)"
				% [n, rad_to_deg(a), q.x, q.y]).is_true()
		# И стык с каждым въездом — от кромки аннулюса наружу до ленты.
		var half := _roads.ring_half(n)
		for k in _graph.node_degree(n):
			var a := _graph.approach_angle(n, k)
			var dir := Vector2(cos(a), sin(a))
			var from := r - half + 0.5
			var to := r + half + RoadMesh.RING_OVERLAP
			var count := maxi(1, ceili((to - from) / 0.5))
			for s in count + 1:
				var q := Vector2(c.x, c.z) + dir * lerpf(from, to,
					float(s) / float(count))
				assert_bool(_covered(q)).override_failure_message(
					"щель между аннулюсом кольца %d и въездом %d в (%.1f, %.1f)"
					% [n, k, q.x, q.y]).is_true()


func test_ring_island_is_a_raised_lawn_not_asphalt() -> void:
	for n: int in _ring_nodes():
		var c := _graph.node_position(n)
		var inner := _graph.node_radius(n) - _roads.ring_half(n)
		if inner <= RoadMesh.CURB_WIDTH:
			continue
		var q := Vector2(c.x, c.z)
		assert_bool(_covered(q)).override_failure_message(
			"центр кольца %d вымощен асфальтом — островка нет" % n).is_false()
		assert_bool(_has_color(q, CityMesher.COLOR_SIDEWALK))\
			.override_failure_message(
				"в центре кольца %d нет островка" % n).is_true()


# --- Насыпь под рампой ------------------------------------------------------

func test_ramp_gets_an_embankment_on_both_sides() -> void:
	var e := _find_kind(CityGraph.EdgeKind.RAMP)
	assert_int(e).override_failure_message(
		"в топологии нет ребра-рампы").is_greater_equal(0)
	var pts := _graph.edge_polyline(e)
	# Точка наибольшего превышения рампы над рельефом — там откос обязан быть.
	var best := Vector3.ZERO
	var rise := 0.0
	for p in pts:
		var d := p.y - _field.height_at(p.x, p.z)
		if d > rise:
			rise = d
			best = p
	assert_float(rise).override_failure_message(
		"рампа нигде не поднимается над рельефом (максимум %.2f м)" % rise)\
		.is_greater(1.0)
	var dir := (pts[pts.size() - 1] - pts[0])
	dir.y = 0.0
	var normal := dir.normalized().cross(Vector3.UP)
	var half := _graph.edge_width(e) * 0.5
	for side: float in [-1.0, 1.0]:
		# Первая полоса откоса примыкает к бровке и красится чистой землёй.
		var q := best + normal * (side * (half + rise * RoadMesh.EMBANKMENT_RUN * 0.15))
		assert_bool(_has_color(Vector2(q.x, q.z), _band_color(0), 0.6))\
			.override_failure_message(
				"со стороны %+.0f рампы нет откоса в (%.1f, %.1f), превышение %.1f м"
				% [side, q.x, q.z, rise]).is_true()


func test_embankment_bridges_the_gap_from_road_to_ground() -> void:
	# Насыпь без стыковки с рельефом — это парящая полка: верх откоса обязан
	# быть у бровки полотна, низ — на земле.
	var e := _find_kind(CityGraph.EdgeKind.RAMP)
	var top := -INF
	var floating := 0
	var worst := 0.0
	for i in range(0, _index.size(), 3):
		if not _is_embankment(_colors[_index[i]]):
			continue
		for k in 3:
			var v := _verts[_index[i + k]]
			top = maxf(top, v.y - _field.height_at(v.x, v.z))
			# Ни одна вершина откоса не должна оказаться НИЖЕ рельефа: тогда
			# насыпь уходит под землю и её склон не читается.
			var under := _field.height_at(v.x, v.z) - v.y
			if under > 0.5:
				floating += 1
				worst = maxf(worst, under)
	assert_float(top).override_failure_message(
		"откос рампы %d нигде не поднимается над рельефом" % e).is_greater(1.0)
	assert_int(floating).override_failure_message(
		"%d вершин откоса ушли под рельеф, глубже всего на %.2f м"
		% [floating, worst]).is_equal(0)


func test_embankment_normals_point_outward_and_up() -> void:
	var total_embankment_tris := 0
	var inverted_tris := 0
	for i in range(0, _index.size(), 3):
		if not _is_embankment(_colors[_index[i]]):
			continue
		total_embankment_tris += 1
		var n0 := _normals[_index[i]]
		var n1 := _normals[_index[i + 1]]
		var n2 := _normals[_index[i + 2]]
		var fn := (n0 + n1 + n2) / 3.0
		# Боковой откос насыпи смотрит вверх-наружу (fn.y > 0),
		# а торцевая заглушка вертикальна (fn.y == 0).
		# Вывернутая наизнанку грань смотрела бы вниз (fn.y < -0.01).
		if fn.y < -0.01:
			inverted_tris += 1
	assert_int(total_embankment_tris).is_greater(0)
	assert_int(inverted_tris)\
		.override_failure_message("%d из %d граней откоса смотрят вниз (вывернуты наизнанку)" % [inverted_tris, total_embankment_tris])\
		.is_equal(0)


func test_embankment_has_end_caps_at_elevated_ends() -> void:
	# Торцевые заглушки насыпи должны иметь вертикальную плоскость (fn.y близко к 0)
	# и закрывать сквозную пустоту под полотном на стыке с мостом.
	var cap_tris := 0
	for i in range(0, _index.size(), 3):
		if not _is_embankment(_colors[_index[i]]):
			continue
		var n0 := _normals[_index[i]]
		var n1 := _normals[_index[i + 1]]
		var n2 := _normals[_index[i + 2]]
		var fn := (n0 + n1 + n2) / 3.0
		if absf(fn.y) < 0.05:
			cap_tris += 1
	assert_int(cap_tris)\
		.override_failure_message("у насыпи нет вертикальных торцевых заглушек")\
		.is_greater(0)








# --- Разметка ---------------------------------------------------------------

func test_markings_come_from_the_crossing_source_not_from_a_grid() -> void:
	var markings := RoadMarkings.new(_graph, _roads, _topo.signal_nodes)
	assert_int(markings.crossings.size()).override_failure_message(
		"источник переходов пуст — зебрам неоткуда взяться").is_greater(0)
	assert_int(markings.zebra.size()).override_failure_message(
		"переходов %d, а полос зебры 0" % markings.crossings.size())\
		.is_greater(markings.crossings.size())
	# Каждая зебра стоит на подходе узла степени >= 3 и лежит на полотне.
	for c: Dictionary in markings.crossings:
		var n: int = c["node"]
		assert_int(_graph.node_degree(n)).override_failure_message(
			"переход поставлен на узле %d степени %d — заглушка обещает >= 3"
			% [n, _graph.node_degree(n)]).is_greater_equal(3)
		var center: Vector3 = c["center"]
		assert_bool(_covered(Vector2(center.x, center.z)))\
			.override_failure_message(
				"зебра узла %d в (%.1f, %.1f) лежит мимо полотна"
				% [n, center.x, center.z]).is_true()
	assert_int(markings.stop_lines.size()).override_failure_message(
		"регулируемых узлов %d, а стоп-линий 0" % _topo.signal_nodes.size())\
		.is_greater(0)


func test_dashes_skip_narrow_streets_and_the_bridge() -> void:
	var markings := RoadMarkings.new(_graph, _roads, _topo.signal_nodes)
	assert_int(markings.dashes.size()).override_failure_message(
		"осевой разметки нет вовсе").is_greater(50)
	var bridge := _find_kind(CityGraph.EdgeKind.BRIDGE)
	var pts := _graph.edge_polyline(bridge)
	var mid := (pts[0] + pts[pts.size() - 1]) * 0.5
	for t: Transform3D in markings.dashes:
		# Считать надо в трёх измерениях: под пролётом проходит своя улица
		# яруса 0, и её осевая в плане попадает ровно под деку.
		if absf(t.origin.y - mid.y) > 2.0:
			continue
		var d := Vector2(t.origin.x - mid.x, t.origin.z - mid.z).length()
		assert_float(d).override_failure_message(
			"штрих осевой стоит в %.1f м от середины пролёта на его высоте — разметку деки строит этап 3"
			% d).is_greater(6.0)


# --- Бюджет -----------------------------------------------------------------

func test_full_city_road_mesh_fits_the_build_budget() -> void:
	assert_float(_build_ms).override_failure_message(
		"полотно всего города собиралось %.1f мс при бюджете %.0f мс"
		% [_build_ms, BUILD_BUDGET_MS]).is_less(BUILD_BUDGET_MS)
	# Всё полотно — одна поверхность одного меша: один draw call на город,
	# бюджет < 200 вызовов на кадр от него не страдает.
	# Индексов ровно по три на грань, остатка от деления быть не может.
	@warning_ignore("integer_division")
	var faces := _index.size() / 3
	assert_int(faces).override_failure_message(
		"полотно города собралось из %d граней — это уже не low-poly"
		% faces).is_less(20000)


# ============================================================================
# Служебное
# ============================================================================

func _index_asphalt() -> void:
	for i in range(0, _index.size(), 3):
		if not _is_color(_colors[_index[i]], CityMesher.COLOR_ROAD):
			continue
		var a := _verts[_index[i]]
		var b := _verts[_index[i + 1]]
		var c := _verts[_index[i + 2]]
		var lo := Vector2i(floori(minf(a.x, minf(b.x, c.x)) / GRID_CELL),
			floori(minf(a.z, minf(b.z, c.z)) / GRID_CELL))
		var hi := Vector2i(floori(maxf(a.x, maxf(b.x, c.x)) / GRID_CELL),
			floori(maxf(a.z, maxf(b.z, c.z)) / GRID_CELL))
		for cx in range(lo.x, hi.x + 1):
			for cz in range(lo.y, hi.y + 1):
				var key := Vector2i(cx, cz)
				var list: PackedInt32Array = _asphalt.get(key, PackedInt32Array())
				list.append(i)
				_asphalt[key] = list


func _covered(q: Vector2) -> bool:
	var key := Vector2i(floori(q.x / GRID_CELL), floori(q.y / GRID_CELL))
	if not _asphalt.has(key):
		return false
	for i: int in _asphalt[key]:
		if _inside(q, i):
			return true
	return false


## Высота полотна в точке — по первой накрывшей её асфальтовой грани.
func _road_height_at(q: Vector2) -> float:
	var key := Vector2i(floori(q.x / GRID_CELL), floori(q.y / GRID_CELL))
	if not _asphalt.has(key):
		return -INF
	for i: int in _asphalt[key]:
		if _inside(q, i):
			return _centroid(i).y
	return -INF


## Есть ли рядом с точкой грань заданного цвета: либо точка внутри грани, либо
## центр грани не дальше `radius`. Допуск нужен для узких полос — бордюр 0.5 м
## шириной точкой без запаса не поймать.
func _has_color(q: Vector2, color: Color, radius: float = 1.2) -> bool:
	for i in range(0, _index.size(), 3):
		if not _is_color(_colors[_index[i]], color):
			continue
		var c := _centroid(i)
		if Vector2(c.x - q.x, c.z - q.y).length() <= radius or _inside(q, i):
			return true
	return false


## Цвет полосы откоса номер `band` — тот же расчёт, что в `RoadMesh`: полосы
## красятся от земли у бровки к траве у подошвы.
static func _band_color(band: int) -> Color:
	return RoadMesh.COLOR_EMBANKMENT.lerp(CityMesher.COLOR_GRASS,
		float(band) / float(RoadMesh.EMBANKMENT_BANDS))


static func _is_embankment(got: Color) -> bool:
	for band in RoadMesh.EMBANKMENT_BANDS:
		if _is_color(got, _band_color(band)):
			return true
	return false


static func _is_color(got: Color, want: Color, eps: float = COLOR_EPS) -> bool:
	return absf(got.r - want.r) < eps and absf(got.g - want.g) < eps \
		and absf(got.b - want.b) < eps


func _centroid(i: int) -> Vector3:
	return (_verts[_index[i]] + _verts[_index[i + 1]] + _verts[_index[i + 2]]) / 3.0


func _plan_area(i: int) -> float:
	var a := _verts[_index[i]]
	var b := _verts[_index[i + 1]]
	var c := _verts[_index[i + 2]]
	return ((b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)) * 0.5


func _inside(p: Vector2, i: int) -> bool:
	var a := Vector2(_verts[_index[i]].x, _verts[_index[i]].z)
	var b := Vector2(_verts[_index[i + 1]].x, _verts[_index[i + 1]].z)
	var c := Vector2(_verts[_index[i + 2]].x, _verts[_index[i + 2]].z)
	var d1 := (p - a).cross(b - a)
	var d2 := (p - b).cross(c - b)
	var d3 := (p - c).cross(a - c)
	var neg := d1 < -HIT_EPS or d2 < -HIT_EPS or d3 < -HIT_EPS
	var pos := d1 > HIT_EPS or d2 > HIT_EPS or d3 > HIT_EPS
	return not (neg and pos)


## Расстояние от `from` вдоль `dir` до кромки полотна: последняя точка, ещё
## покрытая асфальтом. -1, если в этом направлении асфальта нет вовсе.
func _road_edge_along(from: Vector2, dir: Vector2) -> float:
	const STEP := 0.25
	const LIMIT := 80.0
	if not _covered(from):
		return -1.0
	var r := STEP
	while r < LIMIT:
		if not _covered(from + dir * r):
			return r - STEP
		r += STEP
	return -1.0


func _in_ring_island(q: Vector2) -> bool:
	for n: int in _ring_nodes():
		var c := _graph.node_position(n)
		if Vector2(c.x, c.z).distance_to(q) < _graph.node_radius(n):
			return true
	return false


func _ring_nodes() -> PackedInt32Array:
	var out := PackedInt32Array()
	for n in _graph.node_count():
		if _graph.node_kind(n) == CityGraph.NodeKind.ROUNDABOUT:
			out.append(n)
	return out


func _nodes_of_degree(deg: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for n in _graph.node_count():
		if _graph.node_kind(n) == CityGraph.NodeKind.ROUNDABOUT:
			continue
		if _graph.node_degree(n) == deg:
			out.append(n)
	return out


func _find_kind(kind: int) -> int:
	for e in _graph.edge_count():
		if _graph.edge_kind(e) == kind:
			return e
	return -1


## Прямой широкий проспект между двумя обычными перекрёстками — образец
## «рядового» ребра для проверок ленты, тротуара и бордюра.
func _straight_edge() -> int:
	for e in _graph.edge_count():
		if _graph.edge_kind(e) != CityGraph.EdgeKind.AVENUE:
			continue
		if _graph.edge_point_count(e) != 2:
			continue
		if _roads.road_polyline(e).size() < 2:
			continue
		var ends := _graph.edge_ends(e)
		if _graph.node_kind(ends.x) == CityGraph.NodeKind.ROUNDABOUT:
			continue
		if _graph.node_kind(ends.y) == CityGraph.NodeKind.ROUNDABOUT:
			continue
		if _roads.plan_length(e) > 40.0:
			return e
	return -1
