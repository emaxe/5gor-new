extends GdUnitTestSuite
## Спецификация этапа 3: разноуровневое пересечение, рампы, тело моста.
##
## `test_pyatigorsk_topology.gd` проверяет, что путепровод в топологии ЕСТЬ.
## Здесь проверяется, что он работает как разноуровневая развязка: под декой
## остаётся клиренс, общего узла в точке пересечения нет, рампа переводит с
## яруса на ярус непрерывно, запрос поверхности различает деку и улицу под
## ней, а опоры не стоят на проезжей части.

## Допуск на расстояния: полилинии хранятся во float32.
const EPS := 0.05
## Шаг кинематического прогона по рампе, м — примерно кадр физики на 60 км/ч.
const STEP := 1.0
## Максимальный допустимый скачок высоты поверхности за шаг, м. Уклон рампы
## 9.3%, то есть 0.093 м на метр; втрое больше — это уже провал сквозь
## геометрию, а не профиль.
const MAX_STEP_RISE := 0.3

var _field: CityField
var _graph: CityGraph
var _bridge: BridgeGeometry
## Ребро пролёта и ребро улицы под ним.
var _deck := -1
var _below := -1
## Точка пересечения их полилиний в плане.
var _cross := Vector2.INF


func before_test() -> void:
	var balance: BalanceData = load("res://data/balance/balance.tres")
	_field = CityField.new(balance)
	_graph = PyatigorskTopology.new().build(_field)
	_bridge = BridgeGeometry.new(_graph, _field)
	_deck = _find_kind(CityGraph.EdgeKind.BRIDGE)
	_below = _find_edge_under_deck()
	_cross = _crossing(_deck, _below)


# --- Модель разноуровневого пересечения -------------------------------------

func test_deck_and_street_below_share_no_node() -> void:
	assert_int(_deck)\
		.override_failure_message("в графе нет ребра kind=BRIDGE")\
		.is_greater_equal(0)
	assert_int(_below)\
		.override_failure_message("под пролётом не найдено ребро яруса 0")\
		.is_greater_equal(0)
	assert_bool(_cross != Vector2.INF)\
		.override_failure_message("полилинии пролёта и улицы внизу не пересекаются в плане")\
		.is_true()

	var deck_ends := _graph.edge_ends(_deck)
	var below_ends := _graph.edge_ends(_below)
	var shared := PackedInt32Array()
	for a: int in [deck_ends.x, deck_ends.y]:
		if a == below_ends.x or a == below_ends.y:
			shared.append(a)
	assert_int(shared.size())\
		.override_failure_message(
			"пролёт и улица под ним делят узлы %s — тогда это перекрёсток, а не развязка"
			% [shared])\
		.is_equal(0)


func test_no_node_stands_at_the_crossing_point() -> void:
	# Узел в точке (x, z)-пересечения означал бы, что развязка схлопнута в
	# обычный перекрёсток: трафик поехал бы с улицы прямо на эстакаду.
	var nearest := INF
	var who := -1
	for n in _graph.node_count():
		var p := _graph.node_position(n)
		var d := _cross.distance_to(Vector2(p.x, p.z))
		if d < nearest:
			nearest = d
			who = n
	# Полуширина улицы 6 м: ближе — узел уже внутри пересечения полотен.
	assert_float(nearest)\
		.override_failure_message(
			"узел %d стоит в %.1f м от точки пересечения (%.1f, %.1f) — общий узел развязки"
			% [who, nearest, _cross.x, _cross.y])\
		.is_greater(6.0)


func test_clearance_over_the_street_below() -> void:
	var deck_y := _height_on_edge(_deck, _cross)
	var road_y := _height_on_edge(_below, _cross)
	var clearance := deck_y - BridgeGeometry.DECK_THICKNESS - road_y
	assert_float(clearance)\
		.override_failure_message(
			"просвет под декой в точке (%.1f, %.1f): дека %.2f м, плита %.2f м, улица %.2f м -> %.2f м при минимуме %.2f м"
			% [_cross.x, _cross.y, deck_y, BridgeGeometry.DECK_THICKNESS, road_y,
				clearance, CityGraph.MIN_CLEARANCE])\
		.is_greater_equal(CityGraph.MIN_CLEARANCE)


func test_level_tolerance_stays_below_half_clearance() -> void:
	# Иначе точка ровно посередине между улицей и декой подойдёт обоим ярусам
	# и дизамбигуация по высоте перестанет их разводить.
	assert_float(CityGraph.LEVEL_TOLERANCE)\
		.override_failure_message(
			"допуск яруса %.2f м не меньше половины клиренса %.2f м"
			% [CityGraph.LEVEL_TOLERANCE, CityGraph.MIN_CLEARANCE * 0.5])\
		.is_less(CityGraph.MIN_CLEARANCE * 0.5)


# --- Рампы ------------------------------------------------------------------

func test_ramps_connect_level_0_to_level_1() -> void:
	var ramps := _edges_of_kind(CityGraph.EdgeKind.RAMP)
	assert_int(ramps.size())\
		.override_failure_message("рампы не заведены: рёбер kind=RAMP нет")\
		.is_greater_equal(2)
	for e in ramps:
		var ends := _graph.edge_ends(e)
		var la := _graph.node_level(ends.x)
		var lb := _graph.node_level(ends.y)
		assert_int(absi(la - lb))\
			.override_failure_message(
				"рампа %d «%s» соединяет узлы одного яруса (%d и %d) — это не переход между ярусами"
				% [e, _graph.edge_name(e), la, lb])\
			.is_equal(1)


func test_ramp_profile_rises_through_intermediate_points() -> void:
	for e in _edges_of_kind(CityGraph.EdgeKind.RAMP):
		var n := _graph.edge_point_count(e)
		assert_int(n)\
			.override_failure_message(
				"рампа %d состоит из %d точек — профиля высоты в ней нет"
				% [e, n])\
			.is_greater(2)
		var pts := _graph.edge_polyline(e)
		var up := pts[n - 1].y > pts[0].y
		var rise := 0.0
		var plan := 0.0
		for k in range(1, n):
			var dy := pts[k].y - pts[k - 1].y
			assert_bool(dy > 0.0 if up else dy < 0.0)\
				.override_failure_message(
					"профиль рампы %d немонотонен: точка %d на %.2f м %s предыдущей"
					% [e, k, absf(dy), "ниже" if dy < 0.0 else "выше"])\
				.is_true()
			rise += absf(dy)
			plan += Vector2(pts[k].x, pts[k].z).distance_to(
				Vector2(pts[k - 1].x, pts[k - 1].z))
		# Уклон 12% — практический потолок для городского пандуса; серпантин
		# с его 17% строится другой математикой и рампой не считается.
		assert_float(rise / plan)\
			.override_failure_message("уклон рампы %d равен %.1f%% при потолке 12%%"
				% [e, rise / plan * 100.0])\
			.is_less(0.12)


func test_kinematic_run_climbs_the_ramp_without_falling_through() -> void:
	# Кинематическая машина: высота на каждом шаге берётся запросом
	# поверхности с ВЫСОТОЙ ПРЕДЫДУЩЕГО шага. Если запрос перепутает ярусы,
	# высота прыгнет с деки на улицу — это и есть провал сквозь геометрию.
	var route := _route_up()
	var y := route[0].y
	var worst := 0.0
	for i in range(1, route.size()):
		var p := route[i]
		var surface := _graph.surface_y_at(Vector3(p.x, y, p.z))
		assert_bool(is_nan(surface))\
			.override_failure_message(
				"на шаге %d (%.1f, %.1f) под машиной нет полотна — маршрут ушёл с дороги"
				% [i, p.x, p.z])\
			.is_false()
		worst = maxf(worst, absf(surface - y))
		y = surface
	assert_float(worst)\
		.override_failure_message(
			"высота поверхности прыгнула на %.2f м за шаг %.1f м — машина провалилась между ярусами"
			% [worst, STEP])\
		.is_less(MAX_STEP_RISE)
	assert_float(y)\
		.override_failure_message("после подъёма по рампе высота %.2f м, а дека на %.2f м"
			% [y, PyatigorskTopology.OVERPASS_DECK_Y])\
		.is_equal_approx(PyatigorskTopology.OVERPASS_DECK_Y, 0.2)


# --- «Поверхность подо мной» ------------------------------------------------

func test_surface_query_tells_the_deck_from_the_street_below() -> void:
	var deck_y := _height_on_edge(_deck, _cross)
	var road_y := _height_on_edge(_below, _cross)
	var on_deck := _graph.surface_y_at(Vector3(_cross.x, deck_y, _cross.y))
	var under := _graph.surface_y_at(Vector3(_cross.x, road_y, _cross.y))
	assert_float(on_deck)\
		.override_failure_message(
			"запрос на деке в (%.1f, %.1f) с высотой %.2f вернул %.2f м"
			% [_cross.x, _cross.y, deck_y, on_deck])\
		.is_equal_approx(deck_y, EPS)
	assert_float(under)\
		.override_failure_message(
			"запрос ПОД мостом в той же точке с высотой %.2f вернул %.2f м вместо %.2f м"
			% [road_y, under, road_y])\
		.is_equal_approx(road_y, EPS)
	assert_float(on_deck - under)\
		.override_failure_message(
			"один и тот же (x, z) обязан дать две разные поверхности, а дал разницу %.2f м"
			% (on_deck - under))\
		.is_greater(CityGraph.MIN_CLEARANCE)


func test_surface_query_is_nan_off_the_carriageway() -> void:
	# Высота вне дорог остаётся за CityField: граф обязан честно ответить
	# «не знаю», а не выдать ближайшее полотно за землю под ногами.
	var y := _graph.surface_y_at(Vector3(_cross.x, 0.0, _cross.y - 60.0))
	assert_bool(is_nan(y))\
		.override_failure_message("в стороне от полотна запрос вернул %.2f м вместо NAN" % y)\
		.is_true()


# --- Тело моста -------------------------------------------------------------

func test_deck_slabs_cover_the_whole_span() -> void:
	var total := 0.0
	for i in _bridge.deck_count():
		total += _bridge.deck_size[i].z
	assert_int(_bridge.deck_count())\
		.override_failure_message("плита деки не построена ни одним сегментом")\
		.is_greater(0)
	assert_float(total)\
		.override_failure_message("плиты покрывают %.1f м из %.1f м пролёта"
			% [total, _graph.edge_length(_deck)])\
		.is_equal_approx(_graph.edge_length(_deck), 0.5)


func test_deck_slab_hangs_below_the_carriageway() -> void:
	var deck_y := PyatigorskTopology.OVERPASS_DECK_Y
	for i in _bridge.deck_count():
		var top := _bridge.deck_center[i].y + _bridge.deck_size[i].y * 0.5
		assert_float(top)\
			.override_failure_message("верх плиты %d на %.2f м, полотно деки на %.2f м"
				% [i, top, deck_y])\
			.is_equal_approx(deck_y, EPS)
		assert_float(_bridge.deck_size[i].y)\
			.override_failure_message("плита %d толщиной %.2f м — не платформа, а объём"
				% [i, _bridge.deck_size[i].y])\
			.is_equal_approx(BridgeGeometry.DECK_THICKNESS, EPS)


func test_piers_stand_clear_of_the_road_below() -> void:
	assert_int(_bridge.pier_count())\
		.override_failure_message("у пролёта нет ни одной опоры")\
		.is_greater(0)
	assert_int(_bridge.piers_over_road)\
		.override_failure_message(
			"ни одна позиция опоры не пришлась на полотно внизу — значит мост стоит не над улицей")\
		.is_greater(0)
	for i in _bridge.pier_count():
		var base := _bridge.pier_base[i]
		var e := _graph.query_nearest_edge(base, BridgeGeometry.PIER_SCAN_RADIUS)
		if e < 0 or absf(_graph.hit_point.y - base.y) > CityGraph.LEVEL_TOLERANCE:
			continue
		assert_float(_graph.hit_dist)\
			.override_failure_message(
				"опора %d в (%.1f, %.1f) стоит в %.1f м от оси ребра «%s» шириной %.1f м"
				% [i, base.x, base.z, _graph.hit_dist, _graph.edge_name(e),
					_graph.edge_width(e)])\
			.is_greater(_graph.edge_width(e) * 0.5 + BridgeGeometry.PIER_RADIUS)


func test_piers_reach_from_the_ground_to_the_deck() -> void:
	for i in _bridge.pier_count():
		var base := _bridge.pier_base[i]
		assert_float(base.y)\
			.override_failure_message("подошва опоры %d на %.2f м, а земля в этой точке на %.2f м"
				% [i, base.y, _field.height_at(base.x, base.z)])\
			.is_equal_approx(_field.height_at(base.x, base.z), EPS)
		var top := base.y + _bridge.pier_height[i] + BridgeGeometry.PIER_CAP_HEIGHT
		assert_float(top)\
			.override_failure_message(
				"верх опоры %d с ригелем на %.2f м, низ плиты деки на %.2f м"
				% [i, top, PyatigorskTopology.OVERPASS_DECK_Y - BridgeGeometry.DECK_THICKNESS])\
			.is_equal_approx(
				PyatigorskTopology.OVERPASS_DECK_Y - BridgeGeometry.DECK_THICKNESS, EPS)


func test_bridge_mesh_has_deck_piers_and_rails() -> void:
	var b := MeshBuilder.new()
	_bridge.build_mesh(b)
	var mesh := b.commit()
	assert_object(mesh)\
		.override_failure_message("мост не дал ни одного треугольника")\
		.is_not_null()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var lo := INF
	var hi := -INF
	for v in verts:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
	# От подошвы опор (земля) до верха перил.
	assert_float(lo)\
		.override_failure_message("низ моста на %.2f м — опоры не доходят до земли" % lo)\
		.is_less(0.5)
	assert_float(hi)\
		.override_failure_message("верх моста на %.2f м, перила ожидались на %.2f м"
			% [hi, PyatigorskTopology.OVERPASS_DECK_Y + BridgeGeometry.RAIL_HEIGHT])\
		.is_equal_approx(
			PyatigorskTopology.OVERPASS_DECK_Y + BridgeGeometry.RAIL_HEIGHT, EPS)


func test_deck_surface_normals_point_up() -> void:
	# Полотно деки — лента; вывернутая наизнанку, она невидима целиком и без
	# единой ошибки в консоли (`.agents/rules/rendering.md`).
	var b := MeshBuilder.new()
	_bridge.build_mesh(b)
	var arrays := b.commit().surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var up := 0
	for n in normals:
		if n.dot(Vector3.UP) > 0.99:
			up += 1
	assert_int(up)\
		.override_failure_message("у моста нет ни одной грани, смотрящей строго вверх")\
		.is_greater(0)


# --- Служебное --------------------------------------------------------------

func _find_kind(kind: int) -> int:
	for e in _graph.edge_count():
		if _graph.edge_kind(e) == kind:
			return e
	return -1


func _edges_of_kind(kind: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for e in _graph.edge_count():
		if _graph.edge_kind(e) == kind:
			out.append(e)
	return out


## Ребро яруса 0, чья полилиния пересекает полилинию пролёта в плане.
## Смежные рёбра (рампы) отбрасываются: они «пересекаются» с пролётом в
## общем узле на его конце, а искать надо улицу ПОД ним.
func _find_edge_under_deck() -> int:
	if _deck < 0:
		return -1
	var deck_ends := _graph.edge_ends(_deck)
	for e in _graph.edge_count():
		if _graph.edge_level(e) != 0:
			continue
		var ends := _graph.edge_ends(e)
		if ends.x == deck_ends.x or ends.x == deck_ends.y \
				or ends.y == deck_ends.x or ends.y == deck_ends.y:
			continue
		if _crossing(_deck, e) != Vector2.INF:
			return e
	return -1


func _crossing(a: int, b: int) -> Vector2:
	if a < 0 or b < 0:
		return Vector2.INF
	for i in range(1, _graph.edge_point_count(a)):
		var a0 := _graph.edge_point(a, i - 1)
		var a1 := _graph.edge_point(a, i)
		for k in range(1, _graph.edge_point_count(b)):
			var b0 := _graph.edge_point(b, k - 1)
			var b1 := _graph.edge_point(b, k)
			var hit: Variant = Geometry2D.segment_intersects_segment(
				Vector2(a0.x, a0.z), Vector2(a1.x, a1.z),
				Vector2(b0.x, b0.z), Vector2(b1.x, b1.z))
			if hit != null:
				return hit
	return Vector2.INF


## Высота полилинии ребра над точкой плана — линейно внутри сегмента.
func _height_on_edge(edge: int, at: Vector2) -> float:
	var best := INF
	var y := 0.0
	for i in range(1, _graph.edge_point_count(edge)):
		var p0 := _graph.edge_point(edge, i - 1)
		var p1 := _graph.edge_point(edge, i)
		var a := Vector2(p0.x, p0.z)
		var b := Vector2(p1.x, p1.z)
		var ab := b - a
		var t: float = 0.0 if ab.length_squared() < 1e-9 \
			else clampf((at - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := at.distance_to(a + ab * t)
		if d < best:
			best = d
			y = lerpf(p0.y, p1.y, t)
	return y


## Маршрут «с земли на эстакаду»: рампа плюс половина пролёта, с шагом STEP.
func _route_up() -> PackedVector3Array:
	var ramp := -1
	for e in _edges_of_kind(CityGraph.EdgeKind.RAMP):
		var ends := _graph.edge_ends(e)
		if _graph.node_level(ends.x) == 0 and _graph.node_level(ends.y) == 1:
			ramp = e
			break
	var pts := _graph.edge_polyline(ramp)
	# Пролёт продолжает рампу от того же узла, куда она пришла.
	var deck_pts := _graph.edge_polyline(_deck)
	if _graph.edge_ends(_deck).x != _graph.edge_ends(ramp).y:
		deck_pts.reverse()
	pts.append_array(deck_pts.slice(1))

	var out := PackedVector3Array([pts[0]])
	for i in range(1, pts.size()):
		var from := pts[i - 1]
		var to := pts[i]
		var n := maxi(1, ceili(from.distance_to(to) / STEP))
		for k in range(1, n + 1):
			out.append(from.lerp(to, float(k) / float(n)))
	return out
