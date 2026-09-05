extends GdUnitTestSuite
## Спецификация периметральной застройки полигональных кварталов
## (`BlockPlanner`).
##
## Главный инвариант — критерий готовности этапа: ни один дом не стоит на
## проезжей части. Проверяется он не по сетке `CityField`, а по графу
## (`CityGraph.road_clearance`), потому что дороги теперь — рёбра графа
## произвольной ширины, а не девять осей.

## Допуск на запас до кромки, м: полилинии хранятся во float32.
const EPS := 0.01
## Насколько фасад может отклониться от улицы, градусы. Дом ставится по
## хорде участка улицы, а не по касательной, поэтому на кривой улице
## отклонение ненулевое: на самой крутой дуге (бульвар Гагарина) хорда
## 22-метрового фасада уходит от касательной середины примерно на 8°.
const FRONT_TOLERANCE := 20.0

var _field: CityField
var _topo: PyatigorskTopology
var _graph: CityGraph
var _blocks: CityBlocks
var _catalog: DistrictCatalog
var _plan: CityPlan
var _seed := 0


func before_test() -> void:
	var balance: BalanceData = load("res://data/balance/balance.tres")
	_seed = balance.world_seed
	_catalog = load("res://data/districts/district_catalog.tres")
	_catalog.index()
	_field = CityField.new(balance)
	_topo = PyatigorskTopology.new()
	_graph = _topo.build(_field)
	_blocks = CityBlocks.new()
	_blocks.build(_graph, _topo.node_district, _topo.landmark_node)
	_plan = _build(_seed)


func _build(seed_value: int) -> CityPlan:
	var plan := CityPlan.new()
	plan.seed_value = seed_value
	BlockPlanner.new(_blocks, _field, _catalog).plan(
		plan, SeededRng.new(seed_value), _topo.landmark_node)
	return plan


# --- Критерий готовности ----------------------------------------------------

func test_buildings_never_stand_on_the_roadway() -> void:
	# Аналог `test_buildings_never_stand_on_the_roadway` (test_city_planner.gd:51)
	# для полигональных кварталов: запас считается до кромки ЛЮБОГО ребра
	# графа, а не до ближайшей оси — рядом с проспектом может проходить узкий
	# проезд, который ближе, но безопаснее.
	for i in _plan.building_count():
		for c in _plan.building_corners(i):
			var clearance := _graph.road_clearance(
				Vector3(c.x, 0.0, c.y), BlockPlanner.ROAD_SEARCH)
			assert_float(clearance)\
				.override_failure_message(
					"угол здания %d (%.1f, %.1f) заходит за кромку полотна на %.2f м"
					% [i, c.x, c.y, -clearance])\
				.is_greater(0.0)
			assert_bool(_graph.on_road(Vector3(c.x, 0.0, c.y)))\
				.override_failure_message("угол здания %d (%.1f, %.1f) на проезжей части"
					% [i, c.x, c.y])\
				.is_false()


func test_buildings_keep_the_sidewalk_clear() -> void:
	# Не только «не на дороге», но и «не на тротуаре»: фасадная линия отстоит
	# от кромки на ширину тротуара, минимум — половина.
	for i in _plan.building_count():
		for c in _plan.building_corners(i):
			assert_float(_graph.road_clearance(
					Vector3(c.x, 0.0, c.y), BlockPlanner.ROAD_SEARCH))\
				.override_failure_message("угол здания %d занял тротуар" % i)\
				.is_greater_equal(BlockPlanner.MIN_ROAD_CLEARANCE - EPS)


func test_buildings_stand_inside_their_block() -> void:
	for i in _plan.building_count():
		var block := _blocks.block_at(_plan.building_center(i))
		assert_int(block)\
			.override_failure_message("здание %d стоит вне кварталов, центр (%.1f, %.1f)"
				% [i, _plan.building_center(i).x, _plan.building_center(i).y])\
			.is_greater_equal(0)
		for c in _plan.building_corners(i):
			assert_bool(_blocks.contains(block, c))\
				.override_failure_message(
					"угол здания %d вышел из квартала %d" % [i, block])\
				.is_true()


func test_buildings_front_the_street() -> void:
	# Фасад (локальная ось X) идёт вдоль улицы, к которой дом обращён.
	# Улица берётся от середины фасада, а не от центра дома: у углового дома
	# ближайшей к центру может оказаться поперечная.
	var off := 0
	for i in _plan.building_count():
		var yaw := _plan.building_yaw[i]
		var along := Vector2(cos(yaw), -sin(yaw))
		var inward := Vector2(sin(yaw), cos(yaw))
		var face := _plan.building_center(i) \
			- inward * (_plan.building_size(i).y * 0.5)
		var e := _graph.query_nearest_edge(Vector3(face.x, 0.0, face.y),
			BlockPlanner.ROAD_SEARCH)
		if e < 0:
			off += 1
			continue
		if rad_to_deg(_axis_angle(along, _edge_dir(e, face))) > FRONT_TOLERANCE:
			off += 1
	# Дворовые корпуса равняются на главную улицу квартала, а не на ближайшую
	# к своему фасаду, поэтому доля, а не «все до одного».
	var share := 100.0 * float(_plan.building_count() - off) \
		/ float(maxi(1, _plan.building_count()))
	assert_float(share)\
		.override_failure_message(
			"фронтом вдоль улицы стоит %.0f%% домов (%d из %d не вдоль)"
			% [share, off, _plan.building_count()])\
		.is_greater_equal(80.0)


# --- Содержание -------------------------------------------------------------

func test_city_is_built_at_the_density_of_its_blocks() -> void:
	# Сеточный город давал 180+ домов на 64 квартала (2.8 на квартал). Здесь
	# кварталов 28 — настоящая сеть улиц реже, — поэтому сравнивать надо
	# плотность на квартал, а не абсолютное число.
	var built: Dictionary[int, int] = {}
	for i in _plan.building_count():
		var b := _blocks.block_at(_plan.building_center(i))
		built[b] = built.get(b, 0) + 1
	var buildable := 0
	for b in _blocks.count():
		if _blocks.special(b).is_empty():
			buildable += 1
	var per_block := float(_plan.building_count()) / float(maxi(1, buildable))
	assert_float(per_block)\
		.override_failure_message("на застраиваемый квартал приходится %.2f дома (%d на %d)"
			% [per_block, _plan.building_count(), buildable])\
		.is_greater_equal(1.5)
	assert_int(built.size())\
		.override_failure_message("застроено %d кварталов из %d пригодных"
			% [built.size(), buildable])\
		.is_greater_equal(int(buildable * 0.6))


func test_buildings_are_pyatigorsk_scale() -> void:
	for i in _plan.building_count():
		assert_float(_plan.building_height[i])\
			.override_failure_message("здание %d высотой %.1f м"
				% [i, _plan.building_height[i]])\
			.is_between(6.0, 25.0)
		var size := _plan.building_size(i)
		assert_float(size.x)\
			.override_failure_message("фронт здания %d — %.1f м" % [i, size.x])\
			.is_between(BlockPlanner.WIDTH_MIN - EPS, BlockPlanner.WIDTH_MAX + EPS)
		assert_float(size.y)\
			.override_failure_message("глубина здания %d — %.1f м" % [i, size.y])\
			.is_between(BlockPlanner.DEPTH_TIGHT - EPS,
				BlockPlanner.DEPTH_MIN + BlockPlanner.DEPTH_SPAN + EPS)


func test_special_blocks_stay_empty() -> void:
	# Цветник, Провал, Грот: квартал, отданный достопримечательности,
	# застройке не подлежит — тот же смысл, что у `block_special()`.
	for i in _plan.building_count():
		var b := _blocks.block_at(_plan.building_center(i))
		assert_str(String(_blocks.special(b)))\
			.override_failure_message("здание %d стоит в квартале %d, отданном лендмарку"
				% [i, b])\
			.is_empty()


func test_landmark_plots_stay_clear() -> void:
	# Сцена достопримечательности строится вокруг своей точки и выходит за
	# границы квартала (у рынка ряды на 17 м), поэтому мало пометить квартал.
	for id: StringName in _topo.landmark_node:
		var p := _graph.node_position(_topo.landmark_node[id])
		var flat := Vector2(p.x, p.z)
		for i in _plan.building_count():
			for c in _plan.building_corners(i):
				assert_float(c.distance_to(flat))\
					.override_failure_message(
						"здание %d стоит в %.1f м от достопримечательности %s"
						% [i, c.distance_to(flat), id])\
					.is_greater_equal(BlockPlanner.LANDMARK_PLOT - EPS)


func test_buildings_do_not_intersect_each_other() -> void:
	# Проверка по всему городу, а не внутри квартала: дома соседних кварталов
	# стоят по разные стороны улицы и пересечься не могут, но если полигоны
	# разъедутся, это всплывёт именно здесь.
	for i in _plan.building_count():
		for j in range(i + 1, _plan.building_count()):
			if _plan.building_center(i).distance_to(_plan.building_center(j)) > 40.0:
				continue
			assert_bool(_overlap(_plan.building_corners(i),
					_plan.building_corners(j)))\
				.override_failure_message("здания %d и %d пересекаются" % [i, j])\
				.is_false()


# --- Рельеф -----------------------------------------------------------------

func test_ground_is_sampled_under_every_corner() -> void:
	# Весь нынешний город плоский: рельеф начинается южнее z = -260
	# (`CityField.TERRAIN_Z_MAX`), а туда не выходит ни один квартал — все
	# дороги на Машук тупиковые и граней не образуют. Тест фиксирует именно
	# это наблюдение: если этап 2 заведёт квартал на склоне, он упадёт и
	# напомнит, что цоколю нужна юбка с разной высотой углов, а не коробка.
	var worst := 0.0
	for i in _plan.building_count():
		var g := _plan.building_ground[i]
		var spread: float = maxf(maxf(g.x, g.y), maxf(g.z, g.w)) \
			- minf(minf(g.x, g.y), minf(g.z, g.w))
		worst = maxf(worst, spread)
		for c in _plan.building_corners(i):
			assert_float(_field.height_at(c.x, c.y))\
				.override_failure_message("высота под углом здания %d не с рельефа" % i)\
				.is_equal_approx(g.x, 1.0)
	assert_float(worst)\
		.override_failure_message(
			"под домом появился уклон в %.2f м — цоколь-коробка больше не годится"
			% worst)\
		.is_equal_approx(0.0, EPS)


# --- Детерминизм ------------------------------------------------------------

func test_same_seed_gives_the_same_city() -> void:
	var again := _build(_seed)
	assert_int(again.building_count()).is_equal(_plan.building_count())
	for i in _plan.building_count():
		assert_vector(again.building_rect[i])\
			.override_failure_message("здание %d разъехалось при повторном плане" % i)\
			.is_equal(_plan.building_rect[i])
		assert_float(again.building_yaw[i]).is_equal(_plan.building_yaw[i])
		assert_float(again.building_height[i]).is_equal(_plan.building_height[i])


func test_another_seed_gives_another_city() -> void:
	var other := _build(_seed + 1)
	var same := other.building_count() == _plan.building_count()
	if same:
		for i in _plan.building_count():
			same = same and other.building_rect[i] == _plan.building_rect[i]
	assert_bool(same)\
		.override_failure_message("другой сид дал ровно тот же город")\
		.is_false()


# --- Служебное --------------------------------------------------------------

func _edge_dir(edge: int, near: Vector2) -> Vector2:
	# Направление ребра рядом с точкой: у кривой улицы важен местный кусок,
	# а не хорда всего ребра.
	var best := Vector2.RIGHT
	var best_dist := INF
	for k in _graph.edge_point_count(edge) - 1:
		var a := _graph.edge_point(edge, k)
		var b := _graph.edge_point(edge, k + 1)
		var mid := Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
		var d := mid.distance_squared_to(near)
		if d < best_dist:
			best_dist = d
			best = Vector2(b.x - a.x, b.z - a.z).normalized()
	return best


## Угол между направлениями без учёта знака, радианы: фасад вдоль улицы
## одинаково хорош в обе стороны.
static func _axis_angle(a: Vector2, b: Vector2) -> float:
	var c: float = clampf(absf(a.dot(b)), 0.0, 1.0)
	return acos(c)


static func _overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	return not (_separates(a, a, b) or _separates(b, a, b))


static func _separates(axes: PackedVector2Array, a: PackedVector2Array,
		b: PackedVector2Array) -> bool:
	for i in 2:
		var axis := (axes[i + 1] - axes[i]).normalized()
		var a_lo := INF
		var a_hi := -INF
		var b_lo := INF
		var b_hi := -INF
		for p in a:
			a_lo = minf(a_lo, axis.dot(p))
			a_hi = maxf(a_hi, axis.dot(p))
		for p in b:
			b_lo = minf(b_lo, axis.dot(p))
			b_hi = maxf(b_hi, axis.dot(p))
		# Допуск: соседние корпуса стоят с зазором, касание не пересечение.
		if a_hi < b_lo + EPS or b_hi < a_lo + EPS:
			return true
	return false
