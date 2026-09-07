class_name CityPlanner
extends RefCounted
## Фаза A генерации города: из данных получается CityPlan.
##
## Только чистые вычисления над Packed*Array — ни одной ноды, ни одного
## ресурса. Поэтому фаза целиком выносится в WorkerThreadPool, а на
## однопоточном web-экспорте разбивается по кадрам.
##
## Порт _buildings/_trees/_lamps/_props/_parkedCars/_collectPickupPoints
## из citygen.js. Ключевое отличие: ВСЯ генерация идёт через сидированный
## SeededRng. В оригинале сидирована только часть (this.rng), а размещение
## зданий и деревьев шло через несидированный Math.random() — то есть город
## там был разным при каждой загрузке, и выучить его было невозможно.
##
## [b]Источник геометрии — граф улиц, а не сетка 9x9 (этап 9).[/b] Раньше
## каждая фаза шла циклом `for c in field.road_axes` и ставила пропс на
## «полполотна вбок от оси»; на настоящей топологии осей нет вовсе. Теперь
## курсор идёт по полилинии РЕБРА, а вбок отмеряется полуширина ЭТОГО ребра:
## на проспекте Кирова (18 м) фонарь встаёт дальше от оси, чем в переулке
## (8 м). Кварталы — полигоны `CityBlocks`, застройка — `BlockPlanner`.
##
## Что осталось прежним: сами правила «сколько чего и как часто», цвета,
## пороги свободного места и порядок фаз. Менялся источник координат, а не
## содержание.

## Отступ от узла, на котором пропс вдоль улицы не ставится: место занято
## ПОПЕРЕЧНОЙ улицей с её тротуаром. Тот же расчёт, что у застройщика
## (`BlockPlanner._corner_margin`).
const JUNCTION_MARGIN_EXTRA := 1.0

## Радиус поиска дорог вокруг точки, м: самое широкое полотно (18 м) плюс
## запас. Дальше этой границы полотно до точки не достаёт.
const ROAD_SEARCH := 40.0

## Деревья: минимальный запас от габарита дерева до КРОМКИ полотна, м.
## Прежние 11.5 м мерились до ОСИ при полуполотне 6 м — это те же 5.5 м до
## кромки, только теперь полуширина у каждой улицы своя.
const TREE_ROAD_CLEARANCE := 5.5
const TREE_SERP_CLEARANCE := 12.0
## Попыток попасть случайной точкой внутрь полигона квартала.
const TREE_TRIES := 6
## Деревьев на квартал по районам (citygen.js:2078).
const TREES_PER_DISTRICT := {
	&"center": 1, &"kurort": 3, &"prigorod": 2, &"sanatorii": 4,
	&"mashuk": 3, &"proval": 8, &"rynok": 2, &"vokzal": 3,
}
const TREES_IN_PARK := 12
const TREES_FOOTHILL := 70
const TREES_RING := 280
## Участок достопримечательности, свободный от посадок, м — то же число, что
## у застройщика (`BlockPlanner.LANDMARK_PLOT`): сцена лендмарка строит свою
## геометрию вокруг точки, и дерево посреди неё лишнее.
const LANDMARK_PLOT := 20.0

## Фонари: шаг вдоль улицы и вынос за кромку полотна.
##
## Шаг вдвое мельче прежних 48 м: на сетке улица тянулась через весь город и
## 48 м давали десяток фонарей на ней, а рёбра настоящего графа — 30-130 м,
## и на большинстве из них при шаге 48 м уместился бы один фонарь на улицу.
const LAMP_STEP := 26.0
## Вынос фонаря за кромку полотна, м. При полотне оригинала (полуширина 6 м)
## прежний абсолютный вынос 9 м от оси — это ровно 3 м за кромку.
const LAMP_EDGE_OFFSET := 3.0

## Точки подачи: шаг вдоль улицы.
const PICKUP_STEP := 48.0

## Сдвиг первой станции каждого семейства пропса от горловины узла, м.
##
## Разные семейства обязаны идти вразнобой: на сетке они разъезжались сами —
## у каждого цикла было своё начало (-208 у точек подачи, -200 у фонарей,
## -216 у урн), — а на графе все стартуют от одной горловины, и без сдвига
## фонарь вставал бы ровно в зарезервированную точку подачи и не ставился
## вовсе. Числа взяты так, чтобы продольный зазор между любыми двумя
## семействами был больше их суммарных радиусов резервирования (3.7 м —
## самый большой, у точки подачи).
const PICKUP_PHASE := 0.0
const LAMP_PHASE := 13.0
const FURNITURE_PHASE := 6.0
## Лавка идёт по тем же станциям, что урна, но со сдвигом на пол-шага: иначе
## урна, поставленная первой, занимает место и лавки не остаётся ни одной.
## На сетке этот сдвиг был записан прямо в координату (`v + 6.0`).
const BENCH_PHASE := 18.0
const PARKED_PHASE := 7.0

## Шаг урн и лавок вдоль улицы, м, и шаг парковки у бордюра. Шаг парковки
## мельче прежних 28 м по той же причине, что и у фонарей: рёбра короче осей.
const FURNITURE_STEP := 24.0
const PARKED_STEP := 14.0
## Насколько машина у бордюра заходит внутрь полотна от кромки, м.
const PARKED_CURB_INSET := 1.2

## Кустов во дворах на весь город и полоса, в которой они разбрасываются, м.
const BUSHES := 220
const BUSH_SPREAD := 500.0
const BUSH_ROAD_CLEARANCE := 4.0

## Цвета мелкого пропса (citygen.js).
const COLOR_BIN := Color("#7a7a72")
const COLOR_BUSH := Color("#4a8a42")
const COLOR_BENCH := Color("#8a6a44")
const COLOR_PLANTER := Color("#bdb4a2")
const COLOR_TREE_TRUNK := Color("#6a4a34")
const TREE_LEAF_COLORS: PackedColorArray = [
	Color("#5a9a4a"), Color("#6aaa55"), Color("#4d8a42"), Color("#74b25e"),
]
const TREE_PINE_COLORS: PackedColorArray = [
	Color("#2e6a3e"), Color("#3a7a48"), Color("#275a33"),
]
const PARKED_COLORS: PackedColorArray = [
	Color("#e8e8e8"), Color("#9aa0a8"), Color("#5060a0"), Color("#b03030"),
	Color("#2a2a2a"), Color("#c0a070"), Color("#d8c088"), Color("#4a5a4a"),
]

var field: CityField
var roads: CityGraph
var blocks: CityBlocks
var districts: DistrictCatalog
## Район каждого узла графа (`PyatigorskTopology.node_district`) — по нему
## определяется район произвольной точки города.
var node_district: Array[StringName]

var _plan: CityPlan
var _rng: SeededRng
## Занятые места: здания и пропсы, для проверки «место свободно».
var _blockers: SpatialHash2D
var _pickup_hash: SpatialHash2D
var _crosswalk_hash: SpatialHash2D
## Рёбра, вдоль которых расставляется уличный пропс: рядовые улицы нулевого
## яруса. У серпантина, пандуса и деки тротуаров нет (`RoadMesh` их тоже не
## строит), а значит некуда ставить фонарь, урну и точку подачи.
var _street_edges: PackedInt32Array = PackedInt32Array()


func _init(city_field: CityField, city_roads: CityGraph, city_blocks: CityBlocks,
		districts_by_node: Array[StringName],
		district_catalog: DistrictCatalog) -> void:
	field = city_field
	roads = city_roads
	blocks = city_blocks
	node_district = districts_by_node
	districts = district_catalog


## Полный проход планирования.
##
## `crossings` — готовая разметка переходов (`RoadMarkings.crossings`): по ней
## резервируется место, чтобы пропс не встал на зебру. `signals` — стойки
## светофоров (`NodeSignalPlan`): план их только переносит к себе и резервирует
## место, считает их узловой контроллер. `landmark_node` — привязки
## достопримечательностей (`PyatigorskTopology`).
func plan(seed_value: int, crossings: Array[Dictionary],
		signals: NodeSignalPlan,
		landmark_node: Dictionary[StringName, int]) -> CityPlan:
	_plan = CityPlan.new()
	_plan.seed_value = seed_value
	_rng = SeededRng.new(seed_value)
	_blockers = SpatialHash2D.new(16.0)
	_pickup_hash = SpatialHash2D.new(16.0)
	_crosswalk_hash = SpatialHash2D.new(16.0)
	_collect_street_edges()
	_reserve_elevated_corridors()

	# Порядок значим: разметка и точки подачи резервируют место до того, как
	# на тротуар начнут ставить фонари, урны и лавки.
	_plan_crosswalks(crossings)
	_plan_pickups()
	_plan_signals(signals)
	_plan_buildings(landmark_node)
	_plan_trees(landmark_node)
	_plan_lamps()
	_plan_street_furniture()
	_plan_parked_cars()
	return _plan


func _collect_street_edges() -> void:
	for e in roads.edge_count():
		if roads.edge_level(e) != 0:
			continue
		var kind := roads.edge_kind(e)
		if kind == CityGraph.EdgeKind.STREET or kind == CityGraph.EdgeKind.AVENUE:
			_street_edges.append(e)


## Полотно рампы и пролёта закрывается от пропса кругами, а не проверкой
## запаса до дороги: та сравнивает высоты и не видит полотно, поднявшееся над
## рельефом (подробности — `BlockPlanner.elevated_corridors`). Без этого
## дерево и фонарь вставали бы в откос насыпи путепровода.
func _reserve_elevated_corridors() -> void:
	for c in BlockPlanner.elevated_corridors(roads, field.sidewalk):
		_blockers.add_point(c.x, c.y, c.z)


# --- Ход вдоль улицы --------------------------------------------------------

## Отступ от узла, с которого начинается свободный фронт ребра: полуширина
## самой широкой ПОПЕРЕЧНОЙ улицы плюс тротуар, у кольца ещё и его радиус.
func _junction_margin(node: int, along: int) -> float:
	var widest := 0.0
	for k in roads.node_degree(node):
		var e := roads.approach_edge(node, k)
		if e != along:
			widest = maxf(widest, roads.edge_width(e))
	return widest * 0.5 + field.sidewalk + roads.node_radius(node) \
		+ JUNCTION_MARGIN_EXTRA


## Точки вдоль ребра с шагом `step`, между горловинами его узлов. Возвращает
## накопленные ПЛАНОВЫЕ длины: вбок отмеряется по плану, иначе на уклоне
## вынос тротуара получился бы короче задуманного.
##
## `phase` — сдвиг первой станции; берётся по модулю шага, иначе на коротком
## ребре сдвинутое семейство пропало бы целиком.
func _stations(e: int, step: float, phase: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var ends := roads.edge_ends(e)
	var total := _plan_length(e)
	var from := _junction_margin(ends.x, e) + fmod(phase, step)
	var to := total - _junction_margin(ends.y, e)
	var s := from
	while s <= to:
		out.append(s)
		s += step
	return out


func _plan_length(e: int) -> float:
	var acc := 0.0
	for k in range(1, roads.edge_point_count(e)):
		acc += _plan_dist(roads.edge_point(e, k - 1), roads.edge_point(e, k))
	return acc


static func _plan_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


## Точка полилинии ребра на плановой длине `s` от его начала.
func _point_at(e: int, s: float) -> Vector3:
	var acc := 0.0
	var n := roads.edge_point_count(e)
	for k in range(1, n):
		var p0 := roads.edge_point(e, k - 1)
		var p1 := roads.edge_point(e, k)
		var seg := _plan_dist(p0, p1)
		if seg <= 0.0:
			continue
		if acc + seg >= s:
			return p0.lerp(p1, (s - acc) / seg)
		acc += seg
	return roads.edge_point(e, n - 1)


## Единичная касательная ребра на плановой длине `s`, в плоскости (x, z).
func _tangent_at(e: int, s: float) -> Vector3:
	var acc := 0.0
	var n := roads.edge_point_count(e)
	for k in range(1, n):
		var p0 := roads.edge_point(e, k - 1)
		var p1 := roads.edge_point(e, k)
		var seg := _plan_dist(p0, p1)
		if seg <= 0.0:
			continue
		if acc + seg >= s or k == n - 1:
			return Vector3(p1.x - p0.x, 0.0, p1.z - p0.z).normalized()
		acc += seg
	return Vector3.RIGHT


## Правая нормаль к касательной — та же правая тройка, что у
## `CityGraph.hit_side`: едешь на восток, юг справа.
static func _right_normal(tangent: Vector3) -> Vector3:
	return tangent.cross(Vector3.UP)


# --- Разметка и точки геймплея ----------------------------------------------

## Зебры приходят готовыми из `RoadMarkings`: разметка и пешеходная логика
## выводятся из одного списка переходов (`PedGraph.crossings`), поэтому
## разъехаться не могут. План их только запоминает и резервирует место.
func _plan_crosswalks(crossings: Array[Dictionary]) -> void:
	for c: Dictionary in crossings:
		var center: Vector3 = c["center"]
		var width: float = c["width"]
		_plan.crosswalk_pos.append(center)
		_plan.crosswalk_yaw.append(float(c["yaw"]))
		_crosswalk_hash.add_point(center.x, center.z, width * 0.5 + 1.0)


## Точки подачи такси вдоль улиц. Порт _collectPickupPoints: шаг тот же,
## вынос — середина тротуара своей улицы, а не константа сетки.
func _plan_pickups() -> void:
	for e in _street_edges:
		var lateral := roads.edge_width(e) * 0.5 + field.sidewalk * 0.5
		for s in _stations(e, PICKUP_STEP, PICKUP_PHASE):
			var p := _point_at(e, s)
			var n := _right_normal(_tangent_at(e, s))
			for side: float in [-1.0, 1.0]:
				var q := p + n * (side * lateral)
				# Точка подачи обязана лежать на тротуаре, а не на чужой
				# проезжей части: у перекрёстка тротуар своей улицы попадает
				# в полотно поперечной, и такси вставало бы посреди неё.
				if _road_clearance(q.x, q.z, p.y) < 0.0:
					continue
				_add_pickup(q.x, q.z)


func _add_pickup(x: float, z: float) -> void:
	_plan.pickup_pos.append(Vector2(x, z))
	_plan.pickup_district.append(_district_index_at(x, z))
	_pickup_hash.add_point(x, z, 2.0)


## Район точки — район ближайшего узла графа. Топология задаёт район на узле
## (`node_district`), а не по индексам квартала: квартал у настоящего города
## не квадрат 64x64 и индексов не имеет.
func _district_index_at(x: float, z: float) -> int:
	var node := roads.nearest_node(Vector3(x, field.height_at(x, z), z))
	if node < 0 or node >= node_district.size():
		return 0
	return _district_index(node_district[node])


func _district_index(id: StringName) -> int:
	for i in districts.items.size():
		if districts.items[i].id == id:
			return i
	return 0


## Стойки светофоров приходят от `NodeSignalPlan`: сколько у регулируемого
## узла подходов, столько и стоек. План их переносит к себе (по ним строятся
## меш и коллизия) и резервирует место под пропс.
func _plan_signals(signals: NodeSignalPlan) -> void:
	for i in signals.post_count():
		var p := signals.post_pos[i]
		_plan.signal_pos.append(p)
		_plan.signal_yaw.append(signals.post_yaw[i])
		_blockers.add_point(p.x, p.z, 0.45)


# --- Застройка --------------------------------------------------------------

## Периметральная застройка полигональных кварталов — целиком за
## `BlockPlanner` (этап 5). Здесь только запуск и регистрация габаритов в
## хеше занятых мест: дальше по этому хешу проверяют место деревья и пропс.
func _plan_buildings(landmark_node: Dictionary[StringName, int]) -> void:
	BlockPlanner.new(blocks, field, districts).plan(_plan, _rng, landmark_node)
	for i in _plan.building_count():
		var r := _plan.building_world_aabb(i)
		_blockers.add_rect(r.position.x, r.position.y, r.end.x, r.end.y)


# --- Озеленение -------------------------------------------------------------

func _plan_trees(landmark_node: Dictionary[StringName, int]) -> void:
	for b in blocks.count():
		var special := blocks.special(b)
		var n: int = TREES_IN_PARK if not special.is_empty() \
			else int(TREES_PER_DISTRICT.get(blocks.district(b), 2))
		# Участок самой достопримечательности остаётся свободным: её сцена
		# строит там свою геометрию (скамьи Цветника, ряды рынка).
		var plot := Vector2(INF, INF)
		var site_plot := Vector2(INF, INF)
		if not special.is_empty() and landmark_node.has(special):
			var lp := roads.node_position(landmark_node[special])
			plot = Vector2(lp.x, lp.z)
			var off: Vector2 = LandmarkLayer.SITE_OFFSETS.get(special, Vector2.ZERO)
			site_plot = plot + off
		for k in n:
			var p := _point_in_block(b)
			if is_inf(p.x):
				continue
			if p.distance_to(plot) < LANDMARK_PLOT or p.distance_to(site_plot) < LANDMARK_PLOT:
				continue
			_try_add_tree(p.x, p.y, _rng.chance(0.75), not special.is_empty())

	# Опушка Машука и предгорье.
	for k in TREES_FOOTHILL:
		var x := (_rng.next() - 0.5) * 320.0
		var z := -300.0 - _rng.randf_to(200.0)
		_try_add_tree(x, z, _rng.chance(0.35), true)

	# Зелёное кольцо за пределами застройки.
	for k in TREES_RING:
		var a := _rng.randf_to(TAU)
		var dd := 265.0 + _rng.randf_to(140.0)
		_try_add_tree(cos(a) * dd, sin(a) * dd, _rng.chance(0.65), true)


## Случайная точка внутри полигона квартала: бросок в габарит с проверкой на
## принадлежность. `Vector2(INF, INF)` — за `TREE_TRIES` попыток не попали
## (узкий вытянутый квартал у подножия Машука).
func _point_in_block(b: int) -> Vector2:
	var poly := blocks.polygon(b)
	if poly.is_empty():
		return Vector2(INF, INF)
	var lo := poly[0]
	var hi := poly[0]
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	for _attempt in TREE_TRIES:
		var q := Vector2(lo.x + _rng.randf_to(hi.x - lo.x),
			lo.y + _rng.randf_to(hi.y - lo.y))
		if blocks.contains(b, q):
			return q
	return Vector2(INF, INF)


func _try_add_tree(x: float, z: float, deciduous: bool, in_park: bool) -> void:
	var ground := field.height_at(x, z)
	if not in_park and _road_clearance(x, z, ground) < TREE_ROAD_CLEARANCE:
		return
	if not _is_free(x, z, ground, 1.8):
		return
	if field.dist_to_serp(x, z) < TREE_SERP_CLEARANCE:
		return
	var scale := _rng.randf_range(0.75, 1.35)
	_plan.tree_pos.append(Vector3(x, ground, z))
	_plan.tree_scale.append(scale)
	_plan.tree_kind.append(0 if deciduous else 1)
	_plan.tree_color.append(_rng.pick_color(
		TREE_LEAF_COLORS if deciduous else TREE_PINE_COLORS))
	# Крона на высоте 2.7 — под ней можно пройти, но не проехать.
	_blockers.add_point(x, z, 0.45, 2.7)


# --- Уличное оборудование ---------------------------------------------------

## Фонари вдоль улиц, стороны чередуются. Кронштейн смотрит на дорогу:
## курс отсчитывается от направления «к оси улицы», а не от мировых осей —
## на бульваре Гагарина улица идёт под углом, и фонарь вдоль X светил бы мимо.
func _plan_lamps() -> void:
	for e in _street_edges:
		var lateral := roads.edge_width(e) * 0.5 + LAMP_EDGE_OFFSET
		var side := 1.0
		for s in _stations(e, LAMP_STEP, LAMP_PHASE):
			var p := _point_at(e, s)
			var n := _right_normal(_tangent_at(e, s))
			var q := p + n * (side * lateral)
			if _is_free(q.x, q.z, p.y, 0.5):
				_plan.lamp_pos.append(Vector3(q.x, p.y, q.z))
				_plan.lamp_yaw.append(_facing_yaw(-n * side))
				_blockers.add_point(q.x, q.z, 0.25)
			side = -side


## Курс объекта, «лицо» которого смотрит вдоль `dir` в плоскости (x, z).
## Меши пропса авторены лицом в +X (как фонарь оригинала при yaw = 0),
## а поворот вокруг Y переводит +X в (cos yaw, -sin yaw) — отсюда знак.
static func _facing_yaw(dir: Vector3) -> float:
	return -atan2(dir.z, dir.x)


func _plan_street_furniture() -> void:
	for e in _street_edges:
		var lateral := roads.edge_width(e) * 0.5 + field.sidewalk * 0.5
		for s in _stations(e, FURNITURE_STEP, FURNITURE_PHASE):
			var p := _point_at(e, s)
			var n := _right_normal(_tangent_at(e, s))
			for side: float in [-1.0, 1.0]:
				var q := p + n * (side * lateral)
				if _rng.chance(0.30) and _is_free(q.x, q.z, p.y, 0.6):
					_add_bin(q.x, q.z, p.y)
	for e in _street_edges:
		var lateral := roads.edge_width(e) * 0.5 + field.sidewalk * 0.5
		for s in _stations(e, FURNITURE_STEP, BENCH_PHASE):
			var p := _point_at(e, s)
			var n := _right_normal(_tangent_at(e, s))
			for side: float in [-1.0, 1.0]:
				var q := p + n * (side * lateral)
				# Лавка стоит спинкой к дороге — как и в сетке, где сторона
				# `+1` получала курс 0, то есть «лицом наружу».
				if _rng.chance(0.22) and _is_free(q.x, q.z, p.y, 1.0):
					_add_bench(q.x, q.z, p.y, _facing_yaw(n * side))

	# Кусты во дворах — там же, где деревья, но ближе к домам.
	for k in BUSHES:
		var x := (_rng.next() - 0.5) * BUSH_SPREAD
		var z := (_rng.next() - 0.5) * BUSH_SPREAD
		var ground := field.height_at(x, z)
		if _road_clearance(x, z, ground) < BUSH_ROAD_CLEARANCE:
			continue
		if not _is_free(x, z, ground, 1.0):
			continue
		_plan.bush_pos.append(Vector3(x, ground, z))
		_plan.bush_scale.append(_rng.randf_range(0.7, 1.3))
		_blockers.add_point(x, z, 0.9, 1.2)


func _add_bin(x: float, z: float, y: float) -> void:
	_plan.bin_pos.append(Vector3(x, y, z))
	_blockers.add_point(x, z, 0.45)


func _add_bench(x: float, z: float, y: float, yaw: float) -> void:
	_plan.bench_pos.append(Vector3(x, y, z))
	_plan.bench_yaw.append(yaw)
	_blockers.add_point(x, z, 1.0)


## Припаркованные машины стоят у бордюра, носом ПО ХОДУ своей полосы:
## при правостороннем движении полоса справа от оси идёт по касательной,
## слева — против неё.
func _plan_parked_cars() -> void:
	for e in _street_edges:
		var lateral := roads.edge_width(e) * 0.5 - PARKED_CURB_INSET
		if lateral <= 0.0:
			continue
		for s in _stations(e, PARKED_STEP, PARKED_PHASE):
			var tangent := _tangent_at(e, s)
			var p := _point_at(e, s)
			var n := _right_normal(tangent)
			for side: float in [-1.0, 1.0]:
				if not _rng.chance(0.30):
					continue
				var q := p + n * (side * lateral)
				# Стоянка у бордюра — единственный пропс, который НАХОДИТСЯ
				# на проезжей части, поэтому проверка места без условия
				# «подальше от дороги».
				if not _is_free_on_road(q.x, q.z, 2.4):
					continue
				_add_parked(q.x, q.z, p.y,
					Heading.from_vector(tangent * side))


func _add_parked(x: float, z: float, y: float, yaw: float) -> void:
	_plan.parked_pos.append(Vector3(x, y, z))
	_plan.parked_yaw.append(yaw)
	_plan.parked_color.append(_rng.pick_color(PARKED_COLORS))
	_plan.parked_kind.append(_rng.randi_below(3))
	_blockers.add_rect(x - 1.1, z - 2.3, x + 1.1, z + 2.3)


# --- Проверка места ---------------------------------------------------------

## Запас от точки до КРОМКИ ближайшего полотна, м. Отрицательное значение —
## точка на проезжей части.
##
## `y` — отметка, на которой идёт запрос: она разводит ярусы. У пропса вдоль
## улицы это высота ПОЛОТНА в точке станции, а не рельефа рядом с ней —
## тротуар на склоне Машука лежит на одной полке с дорогой, и промер по
## рельефу в паре метров вбок нашёл бы разницу высот больше допуска и признал
## бы собственную улицу «другим ярусом».
func _road_clearance(x: float, z: float, y: float) -> float:
	return roads.road_clearance(Vector3(x, y, z), ROAD_SEARCH)


## Порт isPositionValid: не на проезжей части, не в здании, не на точке
## подачи, не на зебре и не поверх другого пропса.
func _is_free(x: float, z: float, y: float, radius: float) -> bool:
	if _road_clearance(x, z, y) < radius + 0.3:
		return false
	return _is_free_on_road(x, z, radius)


## То же без условия «подальше от дороги» — для объектов, которые стоят
## на самой проезжей части (припаркованные машины у бордюра).
func _is_free_on_road(x: float, z: float, radius: float) -> bool:
	if _blockers.overlaps_circle(x, z, radius):
		return false
	if _pickup_hash.overlaps_circle(x, z, radius + 1.2):
		return false
	if _crosswalk_hash.overlaps_circle(x, z, radius + 0.8):
		return false
	return true
