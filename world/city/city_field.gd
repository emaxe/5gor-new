class_name CityField
extends RefCounted
## Скалярные поля мира: высота рельефа, расстояние до дороги, «на дороге ли».
##
## Чистая логика без нод и без рендера — то же, что gps.js/pedgraph.js в
## оригинале: полностью покрывается юнит-тестами и одинаково доступна
## генератору, физике машины, пешеходам и ИИ трафика.
##
## Порт heightAt/distToRoad/onRoad/distToSerp (citygen.js:125-170) и
## оси серпантина (citygen.js:654-742).
##
## Рельеф в игре только один — гора Машук на севере. Всё, что южнее
## z = -260 и вне коридора |x| <= 190, строго плоское.

# --- Границы рельефа --------------------------------------------------------
const TERRAIN_Z_MAX := -260.0
const TERRAIN_Z_MIN := -640.0
const TERRAIN_X_LIMIT := 190.0

# --- Машук ------------------------------------------------------------------
## Центр горы под смотровой башней, радиус подошвы, высота конуса, плато.
const HILL := {"x": 0.0, "z": -448.0, "r": 155.0, "cone": 66.0, "top": 58.0}
## Вторая вершина, гладко сопряжённая с основной.
const PEAK2 := {"x": 55.0, "z": -500.0, "r": 70.0, "cone": 46.0, "top": 40.0}
## Радиус плоской площадки на вершине.
const SUMMIT_FLAT_R := 20.0

# --- Горные трассы -----------------------------------------------------------
## Полуширина полотна серпантина (без обочины) и ширина отсыпки/выемки,
## которой полка сопрягается с естественным рельефом.
const SERP_HALF_WIDTH := 3.6
const SERP_SLOPE := 8.0
## Радиус влияния оси: больше, чем полуширина + откос.
const SERP_INFLUENCE := 14.0
const SERP_HASH_CELL := 8.0
## Ширина, в пределах которой серпантин считается проезжей частью.
const SERP_ROAD_HALF := 4.4

## Обочина полки горной дороги, м: нижняя граница — диагональ мелкой ячейки
## рельефа `CityMesher.TERRAIN_FINE_STEP` (2.0), иначе вершина сетки рядом
## с полотном не попадёт на плоскую часть полки и билинейная интерполяция
## квада продавит асфальт. 3.0 > 2.0 * sqrt(2) ≈ 2.83 с запасом.
const BENCH_SHOULDER := 3.0
## Сопряжение полки со склоном, м. У́же SERP_SLOPE: радиус дуг серпантина —
## 13 м (`_march`, `legs`), а при `bench_half(3.6+3.0=6.6) + BENCH_SLOPE >= 13`
## в центре окружности шпильки нет однозначно ближайшей точки оси — два плеча
## дуги равноудалены, но несут разную высоту профиля, и на стыке встаёт
## гребень. 6.0 держит сумму 12.6 м с запасом 0.4 м.
const BENCH_SLOPE := 6.0

var cell: float = 64.0
var road_half: float = 6.0
var sidewalk: float = 4.0
var grid_ext: float = 36.0

## Уровни поверхностей города (согласованы с CityMesher).
const Y_GROUND := -0.02
const Y_ROAD := 0.05
const Y_SIDEWALK := 0.15
const Y_CURB := 0.16

## Координаты осей дорог (одинаковы для вертикальных и горизонтальных).
var road_axes: PackedFloat32Array = PackedFloat32Array()
## Перекрёстки — декартово произведение осей.
var intersections: PackedVector2Array = PackedVector2Array()

## Граф улиц города. Пока он не подключён (`attach_roads`), «на дороге ли» и
## «какая под ногами поверхность» отвечает СЕТОЧНАЯ модель — этим путём
## пользуются юнит-тесты сеточной эпохи и мост `CityGraphGrid`. Живой город с
## этапа 9 подключает настоящую топологию сразу после её построения, и оба
## запроса начинают отвечать по рёбрам графа.
##
## Рельеф (`height_at`, `base_height`, серпантин) остаётся за полем при любом
## раскладе: у высоты земли один владелец, граф её только читает.
var roads: CityGraph = null

## Ширина бордюрного камня, м — та же, что у мешера (`RoadMesh.CURB_WIDTH`).
## Живёт здесь, потому что по ней проходит ступенька в `surface_height_at`.
const CURB_WIDTH := 0.5

## Одна дорога горы: план + продольный профиль высоты + поперечный габарит.
## Общий контейнер для серпантина и остальных горных улиц — у подъёма и
## врезки полки в рельеф один владелец для всех дорог Машука.
class _MountainRoute:
	var road_half := 0.0    ## полуширина полотна, м
	var bench_half := 0.0   ## полуширина плоской полки в рельефе (полотно + обочина), м
	var slope := 0.0        ## ширина сопряжения полки с естественным склоном, м
	var influence := 0.0    ## радиус, дальше которого трасса не влияет на height_at
	var x := PackedFloat32Array()
	var z := PackedFloat32Array()
	var y := PackedFloat32Array()   ## профиль высоты вдоль оси
	var length := 0.0
	## Индекс станции для каждой опорной точки плана — границы между рёбрами
	## графа, которые топология режет из одной непрерывной полилинии трассы.
	## У серпантина не заполняется: его узлы ищутся по ближайшей станции
	## (`_gazebo_index`), опорных точек в привычном смысле у него нет.
	var anchor_idx := PackedInt32Array()

## Индексы трасс в `_routes`. Серпантин — единственная со своей математикой
## подъёма (`_serp_profile`); у остальных профиль читается с рельефа
## (`_axis_profile`). Совпадают с рёбрами `PyatigorskTopology._mountain_streets`.
const ROUTE_SERPENTINE := 0
const ROUTE_MASHUK_ROAD := 1     ## «дорога на Машук»: kal_n3 -> mash_1 -> lm_cable
const ROUTE_SERP_APPROACH := 2   ## «подъезд к серпантину»: foot_e2 -> mash_e -> serp_bot
const ROUTE_UPPER_MASHUK := 3    ## «Верхняя Машукская дорога»: lm_cable -> mash_w1..w3

var _routes: Array[_MountainRoute] = []
## Ключ ячейки -> закодированные (маршрут, сегмент): общий хеш для всех
## трасс, коридоры которых у общих узлов (serp_bot, lm_cable) перекрываются.
var _route_hash: Dictionary[int, PackedInt32Array] = {}
## Кодирование (маршрут, сегмент) в одно число: маршрутов < 16, сегментов
## внутри трассы < 2^20 (реально — сотни).
const _ROUTE_SEG_MULT := 1 << 20
## Максимальная координата дорожной сетки, вынесена из горячего цикла.
var _grid_extent := 0.0


func _init(balance: BalanceData = null) -> void:
	if balance != null:
		cell = balance.cell
		road_half = balance.road_half
		sidewalk = balance.sidewalk
		grid_ext = balance.grid_ext
	_build_grid()
	_build_mountain_routes()


# --- Дорожная сетка ---------------------------------------------------------

func _build_grid() -> void:
	road_axes = PackedFloat32Array()
	intersections = PackedVector2Array()
	# 9 осей от -256 до +256 с шагом 64 (citygen.js:357).
	for i in 9:
		road_axes.append(-256.0 + i * cell)
	for ax in road_axes:
		for az in road_axes:
			intersections.append(Vector2(ax, az))
	_grid_extent = 256.0 + grid_ext


## Расстояние до ближайшей оси проезжей части (без учёта серпантина).
func dist_to_road(x: float, z: float) -> float:
	var best := INF
	# За торцом сетки расстояние считается по обеим осям, внутри — только
	# поперёк дороги. dz/dx вынесены из цикла: они от оси не зависят.
	var dz_outer: float = maxf(0.0, absf(z) - _grid_extent)
	var dx_outer: float = maxf(0.0, absf(x) - _grid_extent)
	for c in road_axes:
		var dv := sqrt((x - c) * (x - c) + dz_outer * dz_outer)
		if dv < best:
			best = dv
		var dh := sqrt((z - c) * (z - c) + dx_outer * dx_outer)
		if dh < best:
			best = dh
	return best


## Подключает граф улиц: с этого момента `on_road`/`surface_height_at`
## отвечают по нему, а не по сетке. Зовётся один раз, сразу после построения
## топологии (`CityBuilder.build`).
func attach_roads(graph: CityGraph) -> void:
	roads = graph


## Высота, с которой опрашивается граф. Ярус развязки различается по ней:
## вызывающий, который знает свою высоту (машина, пешеход), передаёт её
## `y_hint`, остальные получают отметку рельефа — то есть НИЖНИЙ ярус.
func _probe_y(x: float, z: float, y_hint: float) -> float:
	return height_at(x, z) if is_nan(y_hint) else y_hint


## Проезжая часть города или полотно серпантина.
##
## На графе «дорога» — полотно плюс тротуар: прежняя сеточная модель считала
## дорогой полосу `road_half + sidewalk + 3` (13 м при полотне 12 м), и
## сцепление с звуком не должны переключаться от сантиметра на кромке.
## Полуширина теперь у каждого ребра своя.
func on_road(x: float, z: float, y_hint: float = NAN) -> bool:
	if roads != null:
		var probe := Vector3(x, _probe_y(x, z, y_hint), z)
		var e := roads.query_nearest_edge(probe)
		if e < 0:
			return false
		if absf(probe.y - roads.hit_point.y) > CityGraph.LEVEL_TOLERANCE:
			return false
		return roads.hit_dist <= roads.edge_width(e) * 0.5 + sidewalk
	if dist_to_road(x, z) < road_half + sidewalk + 3.0:
		return true
	return dist_to_serp(x, z) < SERP_ROAD_HALF


## Ближайший перекрёсток — по индексу сетки, без перебора всех 81.
func nearest_intersection(x: float, z: float) -> Vector2:
	return Vector2(_snap_axis(x), _snap_axis(z))


func _snap_axis(v: float) -> float:
	var idx := clampi(roundi((v + 256.0) / cell), 0, road_axes.size() - 1)
	return road_axes[idx]


# --- Рельеф -----------------------------------------------------------------

## Радиус плоской площадки на вершине, вместе с бывшей полушириной серпантина
## (см. ниже) — рельефное свойство горы, а не свойство дороги на ней.
const SUMMIT_PLATEAU_R := SUMMIT_FLAT_R + SERP_HALF_WIDTH

## Базовый рельеф без дороги: Машук + вторая вершина, гладко сопряжённые,
## с плоской площадкой на вершине.
func base_height(x: float, z: float) -> float:
	if z > -288.0:
		return 0.0
	var h := MathUtils.smin(
		HILL.cone * (1.0 - MathUtils.dist_2d(x, z, HILL.x, HILL.z) / HILL.r),
		HILL.top, 6.0)
	h = MathUtils.smax(h, MathUtils.smin(
		PEAK2.cone * (1.0 - MathUtils.dist_2d(x, z, PEAK2.x, PEAK2.z) / PEAK2.r),
		PEAK2.top, 4.0), 8.0)
	h = MathUtils.smax(h, 0.0, 3.0)
	# Плавный сход на ноль у торца проспекта (z = -292).
	h *= clampf((-z - 288.0) / 12.0, 0.0, 1.0)
	# Плоская площадка на вершине: перенесена из _serp_near (была f200517,
	# «плато не должно перекрывать подъём серпантина досрочно») — это черта
	# самой горы, а не серпантина. Радиус и уклон сохранены в точности:
	# SUMMIT_PLATEAU_R (20 + 3.6) м плоских, дальше smoothstep на SERP_SLOPE (8 м)
	# до естественного конуса.
	var d_hill := MathUtils.dist_2d(x, z, HILL.x, HILL.z)
	if d_hill < SUMMIT_PLATEAU_R + SERP_SLOPE:
		var t := clampf((d_hill - SUMMIT_PLATEAU_R) / SERP_SLOPE, 0.0, 1.0)
		var sm := t * t * (3.0 - 2.0 * t)
		h = HILL.top + (h - HILL.top) * sm
	return h


## Высота земли. O(1): рельеф ограничен коридором Машука, внутри —
## выборка базовой формы плюс врезка полки ближайшей горной трассы.
func height_at(x: float, z: float) -> float:
	if z > TERRAIN_Z_MAX or z < TERRAIN_Z_MIN \
			or x < -TERRAIN_X_LIMIT or x > TERRAIN_X_LIMIT:
		return 0.0
	var hb := base_height(x, z)
	var q := _route_near(x, z)
	if q.x < 0.0:
		return hb
	var r := _routes[int(q.z)]
	if q.x <= r.bench_half:
		return q.y
	if q.x >= r.bench_half + r.slope:
		return hb
	# Откос smoothstep между полкой дороги и естественным склоном.
	var t := (q.x - r.bench_half) / r.slope
	return q.y + (hb - q.y) * t * t * (3.0 - 2.0 * t)


## Ближайшая точка на серпантине конкретно (не любой горной трассе) — для
## клиренса деревьев (`CityPlanner`) и легаси-тестов. Не хот-путь: вызывается
## только на этапе генерации города, поэтому обходится без хеша.
func dist_to_serp(x: float, z: float) -> float:
	var d := serp_near(x, z)
	return INF if d.x < 0.0 else d.x


## Реальная высота поверхности под колёсами в точке (x, z):
## полотно дороги, тротуар, бордюр или рельеф Машука.
##
## На графе профиль поперёк улицы тот же, что кладёт мешер: полотно на
## `Y_ROAD` над полилинией ребра, бордюр на `Y_CURB`, тротуар на
## `Y_SIDEWALK`, дальше — земля. Бордюр и тротуар выдаются только рядовой
## улице: у серпантина, рампы и деки их не строит и `RoadMesh`
## (`side_has_sidewalk`), и вернуть здесь ступеньку значило бы приподнять
## машину над несуществующей плитой.
func surface_height_at(x: float, z: float, y_hint: float = NAN) -> float:
	if roads != null:
		var ground := height_at(x, z)
		var probe := Vector3(x, ground if is_nan(y_hint) else y_hint, z)
		var e := roads.query_nearest_edge(probe)
		if e >= 0 and absf(probe.y - roads.hit_point.y) <= CityGraph.LEVEL_TOLERANCE:
			var deck := roads.hit_point.y
			var half := roads.edge_width(e) * 0.5
			if roads.hit_dist <= half:
				return deck + Y_ROAD
			var kind := roads.edge_kind(e)
			if kind == CityGraph.EdgeKind.STREET or kind == CityGraph.EdgeKind.AVENUE:
				if roads.hit_dist <= half + CURB_WIDTH:
					return deck + Y_CURB
				if roads.hit_dist <= half + sidewalk:
					return deck + Y_SIDEWALK
		return ground + Y_GROUND

	if z <= TERRAIN_Z_MAX:
		var h := height_at(x, z)
		if on_road(x, z) and h < 2.0:
			return maxf(h, Y_ROAD * (1.0 - h * 0.5))
		return h

	var span := 256.0 + grid_ext
	if absf(x) > span or absf(z) > span:
		return Y_GROUND

	var vx := _snap_axis(x)
	var hz := _snap_axis(z)
	var dv := absf(x - vx)
	var dh := absf(z - hz)

	# 1. Проезжая часть (включая перекрёстки)
	if (dv <= road_half and absf(z) <= span) or (dh <= road_half and absf(x) <= span):
		return Y_ROAD

	# 2. Бордюр и тротуар
	var curb_end := road_half + 0.5
	var walk_end := road_half + sidewalk
	if (dv <= walk_end and absf(z) <= span) or (dh <= walk_end and absf(x) <= span):
		if dv <= curb_end or dh <= curb_end:
			return Y_CURB
		return Y_SIDEWALK

	# 3. Газон / дворы внутри квартала
	return Y_GROUND


# --- Горные трассы -----------------------------------------------------------

## Шаг дискретизации плана горных улиц вне серпантина, м — как у `_march`.
const ROUTE_STEP := 2.0
## Запас радиуса влияния сверх полки и откоса, м — как у серпантина было
## раньше (SERP_INFLUENCE 14 - SERP_HALF_WIDTH 3.6 - SERP_SLOPE 8 = 2.4).
const ROUTE_INFLUENCE_MARGIN := 2.4


func _build_mountain_routes() -> void:
	_routes = []
	_routes.append(_build_serpentine_route())
	# «дорога на Машук»: kal_n3(14,-202) -> mash_1(18,-246) -> lm_cable(20,-288).
	# kal_n3 — обычный узел улицы Машукской, координатами владеет топология;
	# трасса начинается с mash_1, а не с kal_n3.
	_routes.append(_build_graded_route(6.0,
		PackedVector2Array([Vector2(18.0, -246.0), Vector2(20.0, -288.0)])))
	# «подъезд к серпантину»: foot_e2(118,-166) -> mash_e(124,-232) -> serp_bot.
	# serp_bot — начало оси серпантина, читается из уже построенной трассы 0,
	# чтобы не дублировать координату (128, -292).
	var serp0 := _routes[ROUTE_SERPENTINE]
	_routes.append(_build_graded_route(6.0, PackedVector2Array([
		Vector2(124.0, -232.0), Vector2(serp0.x[0], serp0.z[0])])))
	# «Верхняя Машукская дорога»: lm_cable -> mash_w1 -> mash_w2 -> mash_w3.
	# Единственная негорная трасса с настоящим набором высоты (13 м на 172 м).
	_routes.append(_build_graded_route(4.0, PackedVector2Array([
		Vector2(20.0, -288.0), Vector2(-52.0, -298.0),
		Vector2(-86.0, -330.0), Vector2(-104.0, -380.0)])))
	_build_route_hash()


## Ось серпантина строится «маршем» (прямая + дуга), а не сплайном через
## опорные точки: так радиус шпильки задан точно, а не получается как придётся.
func _build_serpentine_route() -> _MountainRoute:
	var d2r := PI / 180.0
	var legs: Array = [
		{"arc": false, "len": 140.0},                  # траверс 1
		{"arc": true, "radius": 13.0, "angle": 150.0 * d2r},   # шпилька 1
		{"arc": false, "len": 80.0},                   # траверс 2
		{"arc": true, "radius": 13.0, "angle": -150.0 * d2r},  # шпилька 2
		{"arc": false, "len": 100.0},                  # траверс 3
		{"arc": true, "radius": 13.0, "angle": 150.0 * d2r},   # шпилька 3
		{"arc": false, "len": 41.0},                   # выезд на площадку вершины
	]
	var out_x := PackedFloat32Array()
	var out_z := PackedFloat32Array()
	var s_list := PackedFloat32Array()
	_march(128.0, -292.0, -170.0 * d2r, legs, 2.0, out_x, out_z, s_list)
	var total := s_list[s_list.size() - 1]
	var out_y := PackedFloat32Array()
	for s in s_list:
		out_y.append(_serp_profile(s, total))
	var r := _MountainRoute.new()
	r.road_half = SERP_HALF_WIDTH
	r.bench_half = SERP_HALF_WIDTH + BENCH_SHOULDER
	r.slope = BENCH_SLOPE
	r.influence = r.bench_half + r.slope + ROUTE_INFLUENCE_MARGIN
	r.x = out_x
	r.z = out_z
	r.y = out_y
	r.length = total
	return r


func _march(x0: float, z0: float, heading: float, legs: Array, step: float,
		out_x: PackedFloat32Array, out_z: PackedFloat32Array,
		out_s: PackedFloat32Array) -> void:
	out_x.append(x0)
	out_z.append(z0)
	out_s.append(0.0)
	var x := x0
	var z := z0
	var h := heading
	var s := 0.0
	for leg: Dictionary in legs:
		if not leg["arc"]:
			var length: float = leg["len"]
			var n: int = maxi(1, roundi(length / step))
			var dx := cos(h)
			var dz := sin(h)
			for i in range(1, n + 1):
				var t := length * i / float(n)
				out_x.append(x + dx * t)
				out_z.append(z + dz * t)
				out_s.append(s + t)
			x += dx * length
			z += dz * length
			s += length
		else:
			var r: float = leg["radius"]
			var dh: float = leg["angle"]
			var sgn := signf(dh)
			var cx := x - sgn * r * sin(h)
			var cz := z + sgn * r * cos(h)
			var theta0 := atan2(z - cz, x - cx)
			var arc_len := absf(dh) * r
			var n: int = maxi(1, roundi(arc_len / step))
			for i in range(1, n + 1):
				var frac := i / float(n)
				var theta := theta0 + sgn * absf(dh) * frac
				out_x.append(cx + r * cos(theta))
				out_z.append(cz + r * sin(theta))
				out_s.append(s + arc_len * frac)
			x = cx + r * cos(theta0 + dh)
			z = cz + r * sin(theta0 + dh)
			h += dh
			s += arc_len


## Продольный профиль серпантина: горизонтальный подход, постоянный уклон,
## скруглённые переломы в начале и на выезде.
func _serp_profile(s: float, total: float) -> float:
	const S0 := 20.0
	const VC := 24.0
	var top: float = HILL.top
	var g := top / (total - S0 - VC * 0.5)
	if s <= S0 - VC * 0.5:
		return 0.0
	if s < S0 + VC * 0.5:
		var t := (s - S0 + VC * 0.5) / VC
		return g * VC * t * t * 0.5
	if s > total - VC:
		var t := (total - s) / VC
		return top - g * VC * t * t * 0.5
	return minf(g * (s - S0), top)


## Горная улица вне серпантина: план из опорных точек, полка и откос —
## тот же шаблон, что у серпантина (`BENCH_SHOULDER`/`BENCH_SLOPE`), а
## продольный профиль — подлинный рельеф вдоль оси (`_axis_profile`).
func _build_graded_route(road_half: float, anchors: PackedVector2Array) -> _MountainRoute:
	var anchor_idx := PackedInt32Array()
	var plan := _densify_plan(anchors, anchor_idx)
	var r := _MountainRoute.new()
	r.road_half = road_half
	r.bench_half = road_half + BENCH_SHOULDER
	r.slope = BENCH_SLOPE
	r.influence = r.bench_half + r.slope + ROUTE_INFLUENCE_MARGIN
	r.anchor_idx = anchor_idx
	for p in plan:
		r.x.append(p.x)
		r.z.append(p.y)
	r.y = _axis_profile(r.x, r.z)
	r.length = 0.0
	for i in range(1, r.x.size()):
		r.length += Vector2(r.x[i] - r.x[i - 1], r.z[i] - r.z[i - 1]).length()
	return r


## Уплотняет план (ломаную из опорных точек) шагом ROUTE_STEP — копия
## прямолинейной ветки `_march()` без дуг: у обычных горных улиц шпилек нет.
## `out_anchor_idx` получает индекс станции каждой опорной точки: границы
## между рёбрами графа, которые режет топология.
func _densify_plan(anchors: PackedVector2Array,
		out_anchor_idx: PackedInt32Array) -> PackedVector2Array:
	var out := PackedVector2Array([anchors[0]])
	out_anchor_idx.append(0)
	for k in range(1, anchors.size()):
		var a := anchors[k - 1]
		var b := anchors[k]
		var n: int = maxi(1, roundi(a.distance_to(b) / ROUTE_STEP))
		for i in range(1, n + 1):
			out.append(a.lerp(b, float(i) / float(n)))
		out_anchor_idx.append(out.size() - 1)
	return out


## Продольный профиль трассы — станции читают `base_height()` (не
## `height_at`, иначе трасса врезалась бы сама в себя) без сглаживания и без
## ограничения уклона: продольный профиль Верхней Машукской дороги остаётся
## подлинным рельефом (нужен для будущего проектирования моста/уклона,
## `test_elevation_profile_exists_outside_serpentine`). Флэттенинг, ради
## которого затевалась полка, нужен только ПОПЕРЁК дороги — его делает
## bench_half в height_at(), а не этот профиль.
func _axis_profile(x: PackedFloat32Array, z: PackedFloat32Array) -> PackedFloat32Array:
	var y := PackedFloat32Array()
	for i in x.size():
		y.append(base_height(x[i], z[i]))
	return y


func _build_route_hash() -> void:
	_route_hash.clear()
	for ri in _routes.size():
		var r := _routes[ri]
		for i in r.x.size() - 1:
			var x0: float = minf(r.x[i], r.x[i + 1]) - r.influence
			var x1: float = maxf(r.x[i], r.x[i + 1]) + r.influence
			var z0: float = minf(r.z[i], r.z[i + 1]) - r.influence
			var z1: float = maxf(r.z[i], r.z[i + 1]) + r.influence
			var code := ri * _ROUTE_SEG_MULT + i
			for cx in range(floori(x0 / SERP_HASH_CELL), floori(x1 / SERP_HASH_CELL) + 1):
				for cz in range(floori(z0 / SERP_HASH_CELL), floori(z1 / SERP_HASH_CELL) + 1):
					var key := MathUtils.hash_key(cx, cz)
					if not _route_hash.has(key):
						_route_hash[key] = PackedInt32Array()
					_route_hash[key].append(code)


## Ближайшая горная трасса: Vector3(расстояние, высота полки, номер трассы).
## x < 0 — вне влияния всех трасс. O(1) — общий пространственный хеш.
func _route_near(x: float, z: float) -> Vector3:
	var best_d_sq := INF
	var best_y := 0.0
	var best_route := -1
	var key := MathUtils.hash_key(floori(x / SERP_HASH_CELL), floori(z / SERP_HASH_CELL))
	if _route_hash.has(key):
		for code in _route_hash[key]:
			# Декодирование (маршрут, сегмент): деление намеренно целочисленное.
			@warning_ignore("integer_division")
			var ri := code / _ROUTE_SEG_MULT
			var i := code - ri * _ROUTE_SEG_MULT
			var r := _routes[ri]
			var ax := r.x[i]
			var az := r.z[i]
			var dx := r.x[i + 1] - ax
			var dz := r.z[i + 1] - az
			var denom := dx * dx + dz * dz
			var t := 0.0 if denom < 1e-9 else ((x - ax) * dx + (z - az) * dz) / denom
			t = clampf(t, 0.0, 1.0)
			var px := ax + dx * t
			var pz := az + dz * t
			var d_sq := (x - px) * (x - px) + (z - pz) * (z - pz)
			if d_sq < best_d_sq:
				best_d_sq = d_sq
				best_y = r.y[i] + (r.y[i + 1] - r.y[i]) * t
				best_route = ri
	if best_route < 0:
		return Vector3(-1.0, 0.0, 0.0)
	var best_d := sqrt(best_d_sq)
	if best_d >= _routes[best_route].influence:
		return Vector3(-1.0, 0.0, 0.0)
	return Vector3(best_d, best_y, float(best_route))


## Ближайшая точка на одной конкретной трассе — брутфорсом по её точкам, без
## хеша. Не хот-путь (генерация города и легаси-API), в отличие от `height_at`.
func _nearest_on_route(route: int, x: float, z: float) -> Vector2:
	var r := _routes[route]
	var best_d_sq := INF
	var best_y := 0.0
	for i in r.x.size() - 1:
		var ax := r.x[i]
		var az := r.z[i]
		var dx := r.x[i + 1] - ax
		var dz := r.z[i + 1] - az
		var denom := dx * dx + dz * dz
		var t := 0.0 if denom < 1e-9 else ((x - ax) * dx + (z - az) * dz) / denom
		t = clampf(t, 0.0, 1.0)
		var px := ax + dx * t
		var pz := az + dz * t
		var d_sq := (x - px) * (x - px) + (z - pz) * (z - pz)
		if d_sq < best_d_sq:
			best_d_sq = d_sq
			best_y = r.y[i] + (r.y[i + 1] - r.y[i]) * t
	var best_d := sqrt(best_d_sq)
	return Vector2(-1.0, 0.0) if best_d >= r.influence else Vector2(best_d, best_y)


## Ближайшая точка оси серпантина: Vector2(расстояние, высота) или x < 0 вне зоны влияния.
func serp_near(x: float, z: float) -> Vector2:
	return _nearest_on_route(ROUTE_SERPENTINE, x, z)


## Точка (x, z) лежит в зоне, где `height_at` врезает полку/откос горной
## трассы — там высота осознанно расходится с оригиналом citygen.js (у него
## полки нет). Используется для сужения эталонной сверки и для клиренса
## деревьев/пропсов вместо жёстко привязанного к серпантину `dist_to_serp`.
func is_on_mountain_bench(x: float, z: float) -> bool:
	var q := _route_near(x, z)
	if q.x < 0.0:
		return false
	var r := _routes[int(q.z)]
	return q.x < r.bench_half + r.slope


## Полилиния горной трассы (план + профиль) — источник координат и высот для
## узлов и рёбер топологии; свой у каждой трассы, один владелец подъёма.
func mountain_route_points(route: int) -> PackedVector3Array:
	var r := _routes[route]
	var out := PackedVector3Array()
	for i in r.x.size():
		out.append(Vector3(r.x[i], r.y[i], r.z[i]))
	return out


## Ширина полотна горной трассы (без обочины) — для ширины ребра графа.
func mountain_route_width(route: int) -> float:
	return _routes[route].road_half * 2.0


## Индекс станции k-й опорной точки плана трассы — граница между рёбрами
## графа, на которые топология режет одну непрерывную полилинию трассы.
func mountain_route_anchor(route: int, k: int) -> int:
	return _routes[route].anchor_idx[k]


## Точки оси серпантина — нужны генератору полотна, отбойников и ИИ.
func serpentine_points() -> PackedVector3Array:
	return mountain_route_points(ROUTE_SERPENTINE)


func serpentine_length() -> float:
	return _routes[ROUTE_SERPENTINE].length
