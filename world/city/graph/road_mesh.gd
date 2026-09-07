class_name RoadMesh
extends RefCounted
## Полотно, тротуары, бордюры и геометрия узлов по `CityGraph` — то, что
## сегодня делает `CityMesher.build_ground()` для сетки 9x9.
##
## [b]Почему не правка `build_ground()`.[/b] Сегодняшнее «полотно» — 2x9
## бесконечных полос, наложенных крест-накрест (`city_mesher.gd:63-115`);
## перекрёсток получается как их пересечение, отдельной геометрии узла нет.
## Приём не работает для кривых улиц, узлов степени N != 4 и колец. Здесь
## строится их замена по графу; с этапа 9 её и кладёт `CityMesher.build_ground()`
## вместо собственной сеточной геометрии.
##
## [b]Модель.[/b] Каждое ребро — три ленты `MeshBuilder.ribbon()`: полотно,
## тротуары и бордюры по обе стороны. Лента обрезается у узла на «вылет
## горловины» — расстояние, на котором кромки соседних подходов пересекаются
## (`_pair_corner`). Освободившийся полигон узла закрывается веером
## произвольной степени, а угол между соседними подходами — полосой тротуара
## и бордюра (обобщение «угловых площадок», `city_mesher.gd:104-114`, с N=4 на
## любое N). У кольца вместо веера — аннулюс: замкнутая лента по окружности,
## в которую ленты подходов заходят с нахлёстом.
##
## [b]Уклон достаётся бесплатно[/b]: полилиния ребра уже `PackedVector3Array`
## (этап 1), `ribbon()` такие точки принимает. Собственной математики высот
## здесь нет — ни рельефа, ни профиля рампы: и то и другое приходит из
## `CityField`/графа, у высоты один владелец.
##
## [b]Чего этот класс не строит.[/b] Тело моста (плита, опоры, перила) и
## полотно деки — за `BridgeGeometry` (этап 3), рёбра `EdgeKind.BRIDGE` здесь
## пропускаются целиком, чтобы не задваивать полотно. Тоннелей в топологии
## нет (решение этапа 2). Разметка — `RoadMarkings`, отдельным классом:
## она выводится из графа переходов, а не из геометрии.

# --- Узел -------------------------------------------------------------------

## Потолок вылета горловины, в полуширинах самого широкого подхода узла.
## Нужен только для острых развилок: при 32° между подходами (самый острый
## угол топологии, узел `kir_e1`) честное пересечение кромок уходит на 26 м,
## и без потолка узел съел бы соседние рёбра целиком. Обрезка вылета дырок не
## создаёт: точка пересечения кромок всё равно попадает в контур узла
## (`junction_polygon`), а ленты в этом месте перекрываются.
const TRIM_CAP_FACTOR := 2.0

## Доля собственной длины ребра, больше которой горловина узла в него не
## заходит. Без этого переулок к Гроту Лермонтова (22 м) исчезал целиком:
## он отходит от проспекта под 42°, и честное пересечение кромок уносит
## горловину на 18 м. Обрезка вылета безопасна — точка пересечения кромок
## всё равно попадает в полигон узла, а полотно там перекрыто лентами.
const TRIM_EDGE_FRACTION := 0.45

## Ниже этого |sin| угла между подходами кромки считаются параллельными и
## точки пересечения у них нет: 0.05 — это 2.9°, дальше формула пересечения
## теряет точность быстрее, чем растёт польза от неё.
const PARALLEL_SIN := 0.05

## Минимальная длина ленты, остающаяся от ребра после обрезки с двух концов, м.
## Срабатывает только там, где горловины двух узлов не помещаются в ребро;
## оба вылета тогда ужимаются пропорционально (`_cut_edges`).
const MIN_RIBBON := 1.0

## Короче этого тротуар вдоль ребра не строится, м. У переулка, отходящего от
## проспекта под острым углом, обе горловины съедают почти всю длину, и
## остаток в пару метров читается не тротуаром, а брошенной плитой.
const MIN_WALK_RIBBON := 6.0

## Вылет горловины, ниже которого считается, что узел ленту не обрезал, м.
## Прямой стык двух рёбер в цепочке (степень 2, угол ~180°) даёт вылет 0 —
## там ленты и так смыкаются.
const MIN_JUNCTION := 0.05

## Минимальная площадь грани в плане, м². Мельче — не геометрия, а дрожание
## float на почти совпавших точках: такие грани не попадают в меш вовсе.
const MIN_FACE_AREA := 0.002

## Насколько угол между подходами должен превысить развёрнутый, чтобы считаться
## внешней стороной излома, рад. 0.05 (2.9°) — та же граница, что PARALLEL_SIN:
## ближе к 180° кромки практически параллельны и промежутка между ними нет.
const REFLEX_MARGIN := 0.05

## Доля ширины полотна, короче которой огрызок ленты у среза схлопывается в
## ближайший излом полилинии (см. `_slice`).
const SNAP_FACTOR := 0.35

# --- Профиль дороги ---------------------------------------------------------

## Ширина бордюрного камня, м — как в старом мешере (`city_mesher.gd:95`).
const CURB_WIDTH := 0.5

# --- Кольцо -----------------------------------------------------------------

## Нахлёст ленты подхода на аннулюс, м. Лента обрывается ВНУТРИ кольцевого
## полотна, а не на его кромке: торец ленты прямой, кромка аннулюса круглая,
## и стык «хорда к дуге» оставил бы серпы пустоты. Нахлёст — и есть тот самый
## «клин въезда», только выраженный перекрытием, а не отдельным полигоном:
## два копланарных куска одного цвета неразличимы, а дырки быть не может.
const RING_OVERLAP := 2.0
## Целевая длина сегмента полилинии кольца, м, и границы их числа.
const RING_SEGMENT := 4.0
const RING_MIN_SEGMENTS := 16
const RING_MAX_SEGMENTS := 64

# --- Насыпь под рампой ------------------------------------------------------

## Заложение откоса: метров по горизонтали на метр высоты. 1:1.5 — стандартный
## земляной откос (около 34°), круче осыпается.
const EMBANKMENT_RUN := 1.5
## Число полос откоса поперёк. Профиль полос — smoothstep, тот же приём, что
## врезает полку серпантина в рельеф (`CityField.height_at`, city_field.gd:154):
## три полосы дают скруглённые бровку и подошву за шесть треугольников на
## сечение, чего для low-poly достаточно.
const EMBANKMENT_BANDS := 3
## Ниже этого превышения полотна над рельефом откос не строится, м: рампа
## начинается вровень с землёй, и там насыпи ещё нет.
const EMBANKMENT_MIN_RISE := 0.15

## Земля откоса у бровки и трава у подошвы. Полосы красятся от одного к
## другому — насыпь читается земляной, а не куском газона, поставленным на ребро.
const COLOR_EMBANKMENT := Color("#7d7466")

var _graph: CityGraph
var _field: CityField
## Ширина тротуара, м — из баланса (`CityField.sidewalk`), не константой:
## у неё один владелец.
var _walk := 4.0

## Плановая (x, z) длина полилинии ребра: обрезка и разметка меряются в плане,
## иначе на уклоне горловина узла получалась бы короче задуманной.
var _plan_len := PackedFloat32Array()
## Индекс подхода, которым ребро входит в свой узел a / b.
var _slot_a := PackedInt32Array()
var _slot_b := PackedInt32Array()
## CSR подходов: `_trim[_approach_base[n] + k]` — вылет горловины k-го подхода
## узла n. Собственная раскладка, а не графовая: `CityGraph._approach_start`
## приватен, а степень узла доступна.
var _approach_base := PackedInt32Array()
var _trim := PackedFloat32Array()
## Вылет для тротуаров и бордюров, ОТДЕЛЬНО ПО СТОРОНАМ подхода: `ccw` — та
## сторона, что смотрит по ходу возрастания угла вокруг узла, `cw` — обратная.
## Он больше вылета полотна: тротуар обязан остановиться там, где его ВНЕШНЯЯ
## кромка выходит из полотна соседнего подхода. На кольце — тем более: там
## тротуар останавливается СНАРУЖИ кольцевого полотна, а полотно подхода,
## наоборот, заходит внутрь него.
##
## Две стороны врозь, а не одним максимумом: на развилке 30-50° глубокая
## обрезка нужна ровно ОДНОЙ стороне — той, что смотрит в развилку. Общий
## максимум обрезал и вторую, ни за чем, на те же 20-37 м, и суммы двух концов
## хватало, чтобы от тротуара не осталось `MIN_WALK_RIBBON` и он пропадал у
## ребра целиком. Так теряли тротуар проспект Кирова и привокзальное кольцо.
var _walk_trim_ccw := PackedFloat32Array()
var _walk_trim_cw := PackedFloat32Array()

## Обрезанные полилинии: полотно — одна на ребро, тротуарные — по одной на
## сторону (`pos` — сторона `+n` полилинии, `neg` — противоположная).
var _road_poly: Array[PackedVector3Array] = []
var _walk_poly_pos: Array[PackedVector3Array] = []
var _walk_poly_neg: Array[PackedVector3Array] = []


func _init(graph: CityGraph, field: CityField) -> void:
	_graph = graph
	_field = field
	_walk = field.sidewalk
	_index_approaches()
	_measure_trims()
	_cut_edges()


# ============================================================================
# Подготовка
# ============================================================================

func _index_approaches() -> void:
	var n := _graph.node_count()
	var m := _graph.edge_count()
	_slot_a.resize(m)
	_slot_b.resize(m)
	_slot_a.fill(-1)
	_slot_b.fill(-1)
	_approach_base.resize(n + 1)
	var acc := 0
	for i in n:
		_approach_base[i] = acc
		acc += _graph.node_degree(i)
	_approach_base[n] = acc
	_trim.resize(acc)
	_walk_trim_ccw.resize(acc)
	_walk_trim_cw.resize(acc)

	for i in n:
		for k in _graph.node_degree(i):
			var e := _graph.approach_edge(i, k)
			if _graph.edge_ends(e).x == i and _slot_a[e] < 0:
				_slot_a[e] = k
			else:
				_slot_b[e] = k

	_plan_len.resize(m)
	for e in m:
		var acc_len := 0.0
		for k in range(1, _graph.edge_point_count(e)):
			acc_len += _plan_dist(_graph.edge_point(e, k - 1), _graph.edge_point(e, k))
		_plan_len[e] = acc_len


## Вылет горловины по каждому подходу каждого узла.
func _measure_trims() -> void:
	for n in _graph.node_count():
		var deg := _graph.node_degree(n)
		var base := _approach_base[n]
		if _graph.node_kind(n) == CityGraph.NodeKind.ROUNDABOUT:
			_measure_ring(n, deg, base)
			continue
		var widest := TRIM_CAP_FACTOR * _max_half(n)
		for k in deg:
			var prev := (k - 1 + deg) % deg
			var next := (k + 1) % deg
			var cap := minf(widest,
				TRIM_EDGE_FRACTION * _plan_len[_graph.approach_edge(n, k)])
			var r := 0.0
			var w_cw := 0.0
			var w_ccw := 0.0
			# Пара с предыдущим подходом даёт расстояние вдоль ВТОРОГО из пары
			# и ограничивает сторону `cw`; пара со следующим — сторону `ccw`.
			var left := _pair_corner(n, prev, k)
			if left.x > 0.0:
				r = maxf(r, left.y)
				w_cw = _pair_corner(n, prev, k, _walk, _walk).y
			var right := _pair_corner(n, k, next)
			if right.x > 0.0:
				r = maxf(r, right.x)
				w_ccw = _pair_corner(n, k, next, _walk, _walk).x
			_trim[base + k] = clampf(r, 0.0, cap)
			# Тротуар обрезается по пересечению ВНЕШНИХ кромок тротуаров, и без
			# потолка. Причин две. Во-первых, тротуар, заехавший на проезжую
			# часть, лежит на 10 см выше асфальта — это ступенька поперёк
			# дороги (так южный тротуар Хетагуровой обрывался посреди бульвара
			# Гагарина, развилка 50°). Во-вторых, срез строго по внешним
			# кромкам ставит торец ленты ровно во внешний угол площадки: обе
			# цепочки площадки идут в одну сторону, и полоса между ними не
			# выворачивается бабочкой. Промежуточный срез — между углом полотна
			# и углом тротуара — даёт именно её.
			_walk_trim_cw[base + k] = maxf(_trim[base + k], w_cw)
			_walk_trim_ccw[base + k] = maxf(_trim[base + k], w_ccw)


func _measure_ring(n: int, deg: int, base: int) -> void:
	var half := ring_half(n)
	var outer := _graph.node_radius(n) + half
	var inner := _graph.node_radius(n) - half
	for k in deg:
		var h := _graph.edge_width(_graph.approach_edge(n, k)) * 0.5
		# Углы торца ленты обязаны лечь ВНУТРЬ окружности аннулюса, иначе
		# между прямой хордой торца и дугой останется серп пустоты. Отсюда
		# sqrt(outer^2 - h^2) — осевое расстояние, на котором угол ленты ещё
		# лежит на окружности; минус запас 0.5 м.
		var chord := sqrt(maxf(outer * outer - h * h, 0.0)) - 0.5
		_trim[base + k] = clampf(minf(outer - RING_OVERLAP, chord), inner + 0.5, outer)
		# Тротуар, наоборот, обрывается снаружи кольцевого полотна, и торец у
		# него прямой: соседних прямых кромок, по которым его скашивать, нет —
		# кромка кольца круглая, промежуток закрывает дуга угловой площадки.
		# У кольца сторон нет: кромка круглая, обе стороны обрываются снаружи
		# кольцевого полотна одинаково.
		_walk_trim_cw[base + k] = maxf(outer, chord + 1.0)
		_walk_trim_ccw[base + k] = _walk_trim_cw[base + k]


## Полуширина кольцевого полотна, м. Публичная: её же читают тесты и разметка.
## Сама величина живёт в графе — по ней же `PedGraph` строит тротуарную
## окружность вокруг кольца, и у ширины проезжей части один владелец.
func ring_half(node: int) -> float:
	return _graph.ring_half(node)


## Расстояния от узла до точки пересечения кромок соседних подходов i и j
## (j следует за i по возрастанию угла): x — вдоль i, y — вдоль j.
## `Vector2(-1, -1)` — пересечения нет: подходы почти параллельны либо угол
## между ними развёрнутый (внешняя сторона излома, там кромки расходятся).
##
## Вывод: кромка подхода i — прямая `t*u_i + h_i*n_i`, кромка j —
## `s*u_j - h_j*n_j`, где n = u x UP. В системе, где u_i = (1,0), решение
## t = (h_i*cos O + h_j) / sin O, симметрично для s. При равных ширинах и
## O = 90° получается t = h — ровно половина полотна, то есть перекрёсток
## двух улиц шириной 12 м остаётся квадратом 12x12, как в старом мешере.
## `pad_i`/`pad_j` отодвигают кромку наружу: 0 — кромка полотна, `_walk` —
## внешний край тротуара.
func _pair_corner(node: int, i: int, j: int, pad_i: float = 0.0,
		pad_j: float = 0.0) -> Vector2:
	var hi := _graph.edge_width(_graph.approach_edge(node, i)) * 0.5 + pad_i
	var hj := _graph.edge_width(_graph.approach_edge(node, j)) * 0.5 + pad_j
	var theta := _graph.approach_angle(node, j) - _graph.approach_angle(node, i)
	if theta <= 0.0:
		theta += TAU
	var s := sin(theta)
	if absf(s) < PARALLEL_SIN:
		return Vector2(-1.0, -1.0)
	var c := cos(theta)
	var t := (hi * c + hj) / s
	var u := (hj * c + hi) / s
	if t <= 0.0 or u <= 0.0:
		return Vector2(-1.0, -1.0)
	return Vector2(t, u)


func _max_half(node: int) -> float:
	var widest := 0.0
	for k in _graph.node_degree(node):
		widest = maxf(widest, _graph.edge_width(_graph.approach_edge(node, k)))
	return widest * 0.5


## Обрезка полилиний под вылеты горловин. Если горловины двух узлов не
## помещаются в ребро, оба вылета ужимаются пропорционально — иначе лента
## выворачивается наизнанку. Случай возможен только на короткой хорде между
## острой развилкой и кольцом; тест держит его под наблюдением.
func _cut_edges() -> void:
	_road_poly.resize(_graph.edge_count())
	_walk_poly_pos.resize(_graph.edge_count())
	_walk_poly_neg.resize(_graph.edge_count())
	for e in _graph.edge_count():
		var ends := _graph.edge_ends(e)
		var ia := _approach_base[ends.x] + _slot_a[e]
		var ib := _approach_base[ends.y] + _slot_b[e]
		var total := _plan_len[e]
		_fit(_trim, ia, ib, total)
		var pts := _graph.edge_polyline(e)
		var snap := _graph.edge_width(e) * SNAP_FACTOR
		_road_poly[e] = _slice(pts, _trim[ia], total - _trim[ib],
			_snap_at(snap, _trim[ia]), _snap_at(snap, _trim[ib]))
		# Полилиния идёт ОТ узла-начала и К узлу-концу, поэтому одна и та же
		# сторона улицы у начала называется `ccw`, а у конца — `cw`.
		_walk_poly_pos[e] = _cut_walk(pts, total, snap,
			_walk_trim_ccw[ia], _walk_trim_cw[ib])
		_walk_poly_neg[e] = _cut_walk(pts, total, snap,
			_walk_trim_cw[ia], _walk_trim_ccw[ib])


func _cut_walk(pts: PackedVector3Array, total: float, snap: float, from: float,
		to: float) -> PackedVector3Array:
	var pair := _fit_pair(from, to, total)
	return _slice(pts, pair.x, total - pair.y,
		_snap_at(snap, pair.x), _snap_at(snap, pair.y))


## Схлопывание огрызка включается только там, где горловина действительно
## что-то отрезала. Иначе на серпантине вылет 4 мм (пара подходов почти
## развёрнута, пересечения кромок нет) съедал бы весь двухметровый первый
## сегмент — полотно обрывалось за два метра до узла, и там оставалась дыра.
static func _snap_at(snap: float, trim: float) -> float:
	return snap if trim > MIN_JUNCTION else 0.0


func _fit(arr: PackedFloat32Array, ia: int, ib: int, total: float) -> void:
	var pair := _fit_pair(arr[ia], arr[ib], total)
	arr[ia] = pair.x
	arr[ib] = pair.y


## Пара вылетов, ужатая пропорционально до того, чтобы поместиться в ребро.
static func _fit_pair(a: float, b: float, total: float) -> Vector2:
	var sum := a + b
	var room := maxf(total - MIN_RIBBON, 0.0)
	if sum <= room or sum <= 0.0:
		return Vector2(a, b)
	var k := room / sum
	return Vector2(a * k, b * k)


# ============================================================================
# Меш
# ============================================================================

## Всё полотно города одним проходом по общему `MeshBuilder` — как и сегодня,
## земля с дорогами лежит одним мешем (`CityMesher.build_ground`).
func build_mesh(b: MeshBuilder) -> void:
	for e in _graph.edge_count():
		_edge_mesh(b, e)
	for n in _graph.node_count():
		if _graph.node_kind(n) == CityGraph.NodeKind.ROUNDABOUT:
			_ring_mesh(b, n)
		else:
			_junction_mesh(b, n)
		_corner_mesh(b, n)


func _edge_mesh(b: MeshBuilder, e: int) -> void:
	# Полотно деки и её тело строит BridgeGeometry: задваивать нельзя.
	if _graph.edge_kind(e) == CityGraph.EdgeKind.BRIDGE:
		return
	var road := _road_poly[e]
	if road.size() < 2:
		return
	var width := _graph.edge_width(e)
	b.ribbon(road, width, CityMesher.COLOR_ROAD, CityMesher.Y_ROAD)
	if _graph.edge_kind(e) == CityGraph.EdgeKind.RAMP:
		_embankment(b, e)
	var h := width * 0.5
	for s: float in [-1.0, 1.0]:
		if not side_has_sidewalk(e, s > 0.0):
			continue
		var walk_pts := walk_polyline(e, s > 0.0)
		b.ribbon(_offset(walk_pts, s * (h + _walk * 0.5)), _walk,
			CityMesher.COLOR_SIDEWALK, CityMesher.Y_SIDEWALK)
		b.ribbon(_offset(walk_pts, s * (h + CURB_WIDTH * 0.5)), CURB_WIDTH,
			CityMesher.COLOR_CURB, CityMesher.Y_CURB_TOP)
		_curb_face(b, walk_pts, s * h, s)


## Обрезанная полилиния тротуара одной стороны ребра: `positive` — сторона
## `+n` полилинии.
func walk_polyline(edge: int, positive: bool) -> PackedVector3Array:
	return _walk_poly_pos[edge] if positive else _walk_poly_neg[edge]


## Тротуар есть только у рядовой улицы яруса 0. Серпантин — горная дорога, у
## неё тротуара нет и в оригинале; у рампы вместо тротуара насыпь; полотно
## деки со своими перилами — предмет этапа 3. Плюс огрызки: если горловины с
## двух концов не оставляют стороне `MIN_WALK_RIBBON`, тротуара с этой стороны
## нет — иначе вместо него выходит одинокая плита поперёк перекрёстка.
func side_has_sidewalk(edge: int, positive: bool) -> bool:
	var k := _graph.edge_kind(edge)
	if k != CityGraph.EdgeKind.STREET and k != CityGraph.EdgeKind.AVENUE:
		return false
	return side_has_walk_room(edge, positive)


## Осталось ли стороне ребра МЕСТО под тротуар после обрезки горловинами обоих
## узлов. Отдельно от `side_has_sidewalk()`, потому что род улицы тут ни при
## чём: по деке моста пешеход ходит, хотя тротуара мешер на ней не рисует, а
## вот по огрызку в два метра поперёк перекрёстка не ходит никто.
func side_has_walk_room(edge: int, positive: bool) -> bool:
	var poly := walk_polyline(edge, positive)
	return poly.size() >= 2 and _arc(poly) >= MIN_WALK_RIBBON


## Флаги «есть место под тротуар» для `PedGraph`: два байта на ребро, индекс
## `e * 2 + (1 если правая сторона направления a -> b)`.
##
## Правая сторона у обоих одна и та же: `_offset()` смещает на
## `dir.cross(Vector3.UP)` = `(-dz, 0, dx)`, ровно ту нормаль, по которой
## `PedGraph._ribbon_frame()` строит правую ленту.
##
## Так у вопроса «есть ли здесь тротуар» остаётся ОДИН владелец. Считать его
## заново в пешеходном графе нельзя: вылет горловины мешер меряет по кромкам
## полотна с добавкой в полную ширину тротуара, а пешеходный граф ставит углы
## по осевой линии тротуара и по самому широкому рукаву узла — числа близкие,
## но не равные, и на шести сторонах из 178 они расходились.
func walk_room_flags() -> PackedByteArray:
	var flags := PackedByteArray()
	flags.resize(_graph.edge_count() * 2)
	for e in _graph.edge_count():
		flags[e * 2] = 1 if side_has_walk_room(e, false) else 0
		flags[e * 2 + 1] = 1 if side_has_walk_room(e, true) else 0
	return flags


## Есть ли у ребра тротуар хоть с одной стороны — для разметки, которой важно
## лишь то, что улица «с тротуарами», а не какая именно её сторона.
func has_sidewalk(edge: int) -> bool:
	return side_has_sidewalk(edge, true) or side_has_sidewalk(edge, false)


## Есть ли тротуар у подхода `k` узла `n` с той его стороны, что смотрит по
## ходу возрастания угла вокруг узла (`ccw`) или против него.
func approach_has_sidewalk(node: int, k: int, ccw: bool) -> bool:
	var e := _graph.approach_edge(node, k)
	return side_has_sidewalk(e, ccw == (_graph.edge_ends(e).x == node))


## Вертикальная щёчка бордюра со стороны проезжей части. Без неё бордюр —
## плоская полоска: 11 см подъёма читаются только гранью, а не цветом.
func _curb_face(b: MeshBuilder, pts: PackedVector3Array, lateral: float,
		side: float) -> void:
	var edge_pts := _offset(pts, lateral)
	var lo := Vector3(0.0, CityMesher.Y_ROAD, 0.0)
	var hi := Vector3(0.0, CityMesher.Y_CURB_TOP, 0.0)
	for i in range(1, edge_pts.size()):
		var p0 := edge_pts[i - 1]
		var p1 := edge_pts[i]
		if side > 0.0:
			b.quad(p0 + lo, p0 + hi, p1 + hi, p1 + lo, CityMesher.COLOR_CURB)
		else:
			b.quad(p1 + lo, p1 + hi, p0 + hi, p0 + lo, CityMesher.COLOR_CURB)


## Полигон обычного перекрёстка: веер от центра узла по контуру, собранному
## из торцов лент подходов и точек пересечения их кромок. Степень любая —
## порядок подходов по углу уже посчитан графом (`approach_angle`, этап 1).
func _junction_mesh(b: MeshBuilder, n: int) -> void:
	if _graph.node_degree(n) < 2:
		return
	_fan(b, _graph.node_position(n) + Vector3(0.0, CityMesher.Y_ROAD, 0.0),
		junction_polygon(n), CityMesher.COLOR_ROAD)


## Контур полигона узла по возрастанию угла подхода. Публичный: по нему тест
## проверяет отсутствие дыр на стыке ленты и узла.
##
## На каждый подход четыре вершины: два ближних угла горловины (у самого узла,
## `center ± n*h`) и два дальних (у торца ленты). Без ближних углов веер
## накрывал бы только треугольник от узла к торцу, а боковые треугольники
## горловины — нет: ровно эта нехватка оставляла дыру шириной в полполотна на
## внешней стороне излома (узлы `kir_w2`, развилка съезда с путепровода).
##
## Между соседними подходами добавляется точка пересечения их кромок — но
## только на выпуклой стороне. На развёрнутой (внешняя сторона излома) кромки
## сходятся ПОЗАДИ узла, вести контур туда значит рисовать асфальтовый шип в
## чистом поле; там промежуток закрывают уже добавленные ближние углы, и
## получается ус-срез по хорде между ними.
func junction_polygon(n: int) -> PackedVector3Array:
	var deg := _graph.node_degree(n)
	var out := PackedVector3Array()
	if deg < 2:
		return out
	var center := _graph.node_position(n)
	var lift := Vector3(0.0, CityMesher.Y_ROAD, 0.0)
	for k in deg:
		var h := _graph.edge_width(_graph.approach_edge(n, k)) * 0.5
		var near := _approach_normal(n, k) * h
		var p := cut_point(n, k)
		var far := cut_normal(n, k) * h
		out.append(center - near + lift)
		out.append(p - far + lift)
		out.append(p + far + lift)
		out.append(center + near + lift)
		var next := (k + 1) % deg
		if _pair_corner(n, k, next).x > 0.0:
			out.append(_corner_point(n, k, next, 0.0, 0.0) + lift)
	return out


## Точка, которой закрывается промежуток между соседними подходами тротуара:
## угол пересечения кромок либо, на развёрнутой стороне, пара ближних углов —
## ус-срез по той же хорде, что и у полотна. Пустой массив — промежутка нет
## (кромки почти параллельны, торцы лент смыкаются).
func _gap_point(n: int, i: int, j: int, pad_i: float,
		pad_j: float) -> Array[Vector3]:
	if _pair_corner(n, i, j).x > 0.0:
		return [_corner_point(n, i, j, pad_i, pad_j)]
	var theta := _graph.approach_angle(n, j) - _graph.approach_angle(n, i)
	if theta <= 0.0:
		theta += TAU
	if theta <= PI + REFLEX_MARGIN:
		return []
	var hi := _graph.edge_width(_graph.approach_edge(n, i)) * 0.5 + pad_i
	var hj := _graph.edge_width(_graph.approach_edge(n, j)) * 0.5 + pad_j
	var center := _graph.node_position(n)
	return [center + _approach_normal(n, i) * hi,
		center - _approach_normal(n, j) * hj]


## Единичное направление подхода ОТ узла и его левая нормаль. В отличие от
## `cut_dir`/`cut_normal` берутся у самого узла, а не в точке среза: ближний
## угол горловины обязан лежать на оси узла, иначе горловины соседних подходов
## разойдутся и между ними появится щель.
func _approach_dir(n: int, k: int) -> Vector3:
	var a := _graph.approach_angle(n, k)
	return Vector3(cos(a), 0.0, sin(a))


func _approach_normal(n: int, k: int) -> Vector3:
	return _approach_dir(n, k).cross(Vector3.UP)


## Точка пересечения кромок соседних подходов, отодвинутых наружу на
## `pad_i`/`pad_j` (0 — кромка полотна, `_walk` — внешний край тротуара).
## Считается по кромкам в точках среза, а не по осям из центра узла: на
## кривом ребре направление в точке среза уже не то, что у узла, а стыковать
## нужно именно с лентой.
func _corner_point(n: int, i: int, j: int, pad_i: float, pad_j: float) -> Vector3:
	var hi := _graph.edge_width(_graph.approach_edge(n, i)) * 0.5 + pad_i
	var hj := _graph.edge_width(_graph.approach_edge(n, j)) * 0.5 + pad_j
	var pi_ := cut_point(n, i) + cut_normal(n, i) * hi
	var pj := cut_point(n, j) - cut_normal(n, j) * hj
	var ui := cut_dir(n, i)
	var uj := cut_dir(n, j)
	var denom := ui.x * uj.z - ui.z * uj.x
	if absf(denom) < 1e-5:
		return (pi_ + pj) * 0.5
	var dx := pj.x - pi_.x
	var dz := pj.z - pi_.z
	var t := (dx * uj.z - dz * uj.x) / denom
	var hit := pi_ + ui * t
	hit.y = (pi_.y + pj.y) * 0.5
	return hit


## Угловые площадки тротуара и бордюра между соседними подходами — обобщение
## тройного цикла по четырём углам перекрёстка (`city_mesher.gd:104-114`) на
## произвольную степень узла и на кольцо.
func _corner_mesh(b: MeshBuilder, n: int) -> void:
	var deg := _graph.node_degree(n)
	if deg < 2:
		return
	var ring := _graph.node_kind(n) == CityGraph.NodeKind.ROUNDABOUT
	for k in deg:
		var next := (k + 1) % deg
		# Обод кольца строится всегда: дуга аннулюса считается по углам и
		# ширинам подходов и не зависит от того, есть ли у подхода тротуар —
		# от него зависит только, к чему обод причаливает на концах. Иначе
		# привокзальное кольцо оставалось голым асфальтовым диском по всей
		# окружности из-за двух подходов без тротуара.
		if ring:
			# Кольцу довольно тротуара у ОДНОГО из двух соседей: дуга обода
			# считается по углам и ширинам подходов и от наличия тротуара не
			# зависит — от него зависит только, к чему обод причаливает.
			# Иначе привокзальное кольцо оставалось голым асфальтовым диском
			# по всей окружности из-за двух подходов без тротуара.
			if not _anchors(n, k, true, ring) and not _anchors(n, next, false, ring):
				continue
		else:
			if not approach_has_sidewalk(n, k, true):
				continue
			if not approach_has_sidewalk(n, next, false):
				continue
		var chains := _corner_chain(n, k, next, ring, CURB_WIDTH)
		_strip(b, chains[0], chains[1], CityMesher.COLOR_CURB, CityMesher.Y_CURB_TOP)
		chains = _corner_chain(n, k, next, ring, _walk)
		_strip(b, chains[0], chains[1], CityMesher.COLOR_SIDEWALK,
			CityMesher.Y_SIDEWALK)


## Внутренняя и внешняя цепочки угловой площадки. Внутренняя идёт ровно по
## кромке проезжей части — поэтому щели между площадкой и полотном быть не
## может ни на перекрёстке, ни на кольце, где кромка круглая.
func _corner_chain(n: int, i: int, j: int, ring: bool,
		pad: float) -> Array[PackedVector3Array]:
	var inner := PackedVector3Array()
	var outer := PackedVector3Array()
	var hi := _graph.edge_width(_graph.approach_edge(n, i)) * 0.5
	var hj := _graph.edge_width(_graph.approach_edge(n, j)) * 0.5

	if _anchors(n, i, true, ring):
		var pi_ := walk_cut_point(n, i, true)
		var ni := walk_cut_normal(n, i, true)
		inner.append(pi_ + ni * hi)
		outer.append(pi_ + ni * (hi + pad))

	if ring:
		_ring_arc(n, i, j, hi, hj, pad, inner, outer)
	else:
		var ins := _gap_point(n, i, j, 0.0, 0.0)
		var outs := _gap_point(n, i, j, pad, pad)
		for c in mini(ins.size(), outs.size()):
			inner.append(ins[c])
			outer.append(outs[c])

	if _anchors(n, j, false, ring):
		var pj := walk_cut_point(n, j, false)
		var nj := walk_cut_normal(n, j, false)
		inner.append(pj - nj * hj)
		outer.append(pj - nj * (hj + pad))
	return [inner, outer]


## Причаливает ли обод площадки к торцу тротуара этого подхода. У кольца
## мало наличия тротуара: если ребро короткое, его вылеты ужимаются
## пропорционально (`_fit_pair`) и торец тротуара оказывается ВНУТРИ
## кольцевого полотна. Причалить к нему — значит протянуть полосу тротуара
## поперёк аннулюса; там обод просто идёт по дуге дальше.
func _anchors(n: int, k: int, ccw: bool, ring: bool) -> bool:
	if not approach_has_sidewalk(n, k, ccw):
		return false
	if not ring:
		return true
	var center := _graph.node_position(n)
	var outer_r := _graph.node_radius(n) + ring_half(n)
	return _plan_dist(center, walk_cut_point(n, k, ccw)) >= outer_r - 0.5


## Участок дуги кольца между двумя подходами: внутренняя цепочка идёт по
## внешней кромке аннулюса, внешняя — по ней же, отодвинутой на `pad`.
func _ring_arc(n: int, i: int, j: int, hi: float, hj: float, pad: float,
		inner: PackedVector3Array, outer: PackedVector3Array) -> void:
	var center := _graph.node_position(n)
	var outer_r := _graph.node_radius(n) + ring_half(n)
	# Угол, на котором кромка подхода пересекает окружность аннулюса.
	var a0 := _graph.approach_angle(n, i) + atan2(hi, sqrt(maxf(
		outer_r * outer_r - hi * hi, 1.0)))
	var a1 := _graph.approach_angle(n, j) - atan2(hj, sqrt(maxf(
		outer_r * outer_r - hj * hj, 1.0)))
	while a1 < a0:
		a1 += TAU
	var span := a1 - a0
	if span <= 0.0:
		return
	var steps := clampi(ceili(span * outer_r / RING_SEGMENT), 1, RING_MAX_SEGMENTS)
	for s in steps + 1:
		var a: float = a0 + span * float(s) / float(steps)
		var dir := Vector3(cos(a), 0.0, sin(a))
		inner.append(center + dir * outer_r)
		outer.append(center + dir * (outer_r + pad))


# --- Кольцо -----------------------------------------------------------------

## Кольцевой узел: аннулюс полотна, приподнятый островок с бордюром по ободу.
## Въезды отдельной геометрией не строятся — ленты подходов заходят в аннулюс
## с нахлёстом (`RING_OVERLAP`), см. комментарий к константе.
func _ring_mesh(b: MeshBuilder, n: int) -> void:
	var center := _graph.node_position(n)
	var radius := _graph.node_radius(n)
	var half := ring_half(n)
	var segments := clampi(ceili(TAU * radius / RING_SEGMENT),
		RING_MIN_SEGMENTS, RING_MAX_SEGMENTS)
	b.ribbon(_circle(center, radius, segments), half * 2.0,
		CityMesher.COLOR_ROAD, CityMesher.Y_ROAD)

	var inner := radius - half
	if inner <= CURB_WIDTH:
		return
	# Островок кольца приподнят до тротуара: по нему не ездят, на нём стоит
	# то, ради чего кольцо и заведено (сквер у вокзала, торговые ряды рынка).
	# Приподнят целиком, вместе с ободом: иначе островок — пологий конус, и у
	# самого бордюра его край проваливается на уровень полотна.
	var walk_lift := center + Vector3(0.0, CityMesher.Y_SIDEWALK, 0.0)
	_fan(b, walk_lift, _ring_points(walk_lift, inner, segments),
		CityMesher.COLOR_SIDEWALK)
	b.ribbon(_circle(center, inner - CURB_WIDTH * 0.5, segments), CURB_WIDTH,
		CityMesher.COLOR_CURB, CityMesher.Y_CURB_TOP)


## Полилиния окружности с перехлёстом в один сегмент: `ribbon()` берёт
## направление в крайних точках односторонней разностью, и на замкнутом
## контуре без перехлёста поперечина шва оказалась бы повёрнута на половину
## шага — на радиусе 28 м это щель шириной больше метра.
func _circle(center: Vector3, radius: float, segments: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var step := TAU / float(segments)
	for i in range(-1, segments + 2):
		var a := step * float(i)
		out.append(center + Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	return out


## Те же точки без перехлёста — контур для веера островка.
func _ring_points(center: Vector3, radius: float,
		segments: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		out.append(center + Vector3(cos(a) * radius, 0.0, sin(a) * radius))
	return out


# --- Насыпь под рампой ------------------------------------------------------

## Земляной откос по обе стороны рампы. Этап 3 сознательно оставил рампу без
## насыпи (`bridge_geometry.gd` — узкий билдер деки и опор), из-за чего в
## живой игре полотно висело бы в воздухе. Профиль поперёк — smoothstep между
## бровкой и естественным рельефом: тот же приём, которым
## `CityField.height_at()` сопрягает полку серпантина со склоном
## (`city_field.gd:154`).
func _embankment(b: MeshBuilder, e: int) -> void:
	var pts := _graph.edge_polyline(e)
	var h := _graph.edge_width(e) * 0.5
	for i in range(1, pts.size()):
		_embankment_section(b, pts[i - 1], pts[i], h)
	_embankment_cap(b, pts, h, false)
	_embankment_cap(b, pts, h, true)


func _embankment_cap(b: MeshBuilder, pts: PackedVector3Array, h: float,
		is_end: bool) -> void:
	if pts.size() < 2:
		return
	var idx := pts.size() - 1 if is_end else 0
	var next_idx := pts.size() - 2 if is_end else 1
	var p := pts[idx]
	var seg_dir := (p - pts[next_idx]) if is_end else (pts[next_idx] - p)
	seg_dir.y = 0.0
	if seg_dir.length_squared() < 1e-6:
		return
	var dir := seg_dir.normalized()
	var n := dir.cross(Vector3.UP)
	var e_neg := p - n * h
	var e_pos := p + n * h
	var rise_neg := e_neg.y - _field.height_at(e_neg.x, e_neg.z)
	var rise_pos := e_pos.y - _field.height_at(e_pos.x, e_pos.z)
	if rise_neg < EMBANKMENT_MIN_RISE and rise_pos < EMBANKMENT_MIN_RISE:
		return

	var run_neg := maxf(rise_neg, 0.0) * EMBANKMENT_RUN
	var run_pos := maxf(rise_pos, 0.0) * EMBANKMENT_RUN
	var lift := Vector3(0.0, CityMesher.Y_ROAD, 0.0)
	var top_neg := e_neg + (lift if rise_neg >= EMBANKMENT_MIN_RISE else Vector3.ZERO)
	var top_pos := e_pos + (lift if rise_pos >= EMBANKMENT_MIN_RISE else Vector3.ZERO)
	var g_neg := Vector3(top_neg.x, _field.height_at(top_neg.x, top_neg.z), top_neg.z)
	var g_pos := Vector3(top_pos.x, _field.height_at(top_pos.x, top_pos.z), top_pos.z)

	# 1. Центральный прямоугольник под полотном
	var deg_n := top_neg.distance_squared_to(g_neg) < 1e-4
	var deg_p := top_pos.distance_squared_to(g_pos) < 1e-4
	if deg_n and deg_p:
		pass
	elif deg_n:
		if is_end:
			b.tri(top_neg, top_pos, g_pos, COLOR_EMBANKMENT)
		else:
			b.tri(top_neg, g_pos, top_pos, COLOR_EMBANKMENT)
	elif deg_p:
		if is_end:
			b.tri(g_neg, top_neg, top_pos, COLOR_EMBANKMENT)
		else:
			b.tri(g_neg, top_pos, top_neg, COLOR_EMBANKMENT)
	else:
		if is_end:
			b.quad(g_neg, top_neg, top_pos, g_pos, COLOR_EMBANKMENT)
		else:
			b.quad(g_pos, top_pos, top_neg, g_neg, COLOR_EMBANKMENT)

	# 2. Полосы откоса по бокам
	var prev_pos := top_pos
	var prev_neg := top_neg
	for band in EMBANKMENT_BANDS:
		var t := float(band + 1) / float(EMBANKMENT_BANDS)
		var col := COLOR_EMBANKMENT.lerp(CityMesher.COLOR_GRASS,
			float(band) / float(EMBANKMENT_BANDS))

		# Правая сторона (+n)
		var cur_pos := _slope_point(e_pos, n, run_pos * t, rise_pos, t)
		var g_prev_p := Vector3(prev_pos.x, _field.height_at(prev_pos.x, prev_pos.z), prev_pos.z)
		var g_cur_p := Vector3(cur_pos.x, _field.height_at(cur_pos.x, cur_pos.z), cur_pos.z)
		var deg_prev_p := prev_pos.distance_squared_to(g_prev_p) < 1e-4
		var deg_cur_p := cur_pos.distance_squared_to(g_cur_p) < 1e-4
		if deg_prev_p and deg_cur_p:
			pass
		elif deg_prev_p:
			if is_end:
				b.tri(prev_pos, cur_pos, g_cur_p, col)
			else:
				b.tri(prev_pos, g_cur_p, cur_pos, col)
		elif deg_cur_p:
			if is_end:
				b.tri(g_prev_p, prev_pos, cur_pos, col)
			else:
				b.tri(g_prev_p, cur_pos, prev_pos, col)
		else:
			if is_end:
				b.quad(g_prev_p, prev_pos, cur_pos, g_cur_p, col)
			else:
				b.quad(g_cur_p, cur_pos, prev_pos, g_prev_p, col)
		prev_pos = cur_pos

		# Левая сторона (-n)
		var cur_neg := _slope_point(e_neg, -n, run_neg * t, rise_neg, t)
		var g_prev_n := Vector3(prev_neg.x, _field.height_at(prev_neg.x, prev_neg.z), prev_neg.z)
		var g_cur_n := Vector3(cur_neg.x, _field.height_at(cur_neg.x, cur_neg.z), cur_neg.z)
		var deg_prev_n := prev_neg.distance_squared_to(g_prev_n) < 1e-4
		var deg_cur_n := cur_neg.distance_squared_to(g_cur_n) < 1e-4
		if deg_prev_n and deg_cur_n:
			pass
		elif deg_prev_n:
			if is_end:
				b.tri(g_cur_n, cur_neg, prev_neg, col)
			else:
				b.tri(g_cur_n, prev_neg, cur_neg, col)
		elif deg_cur_n:
			if is_end:
				b.tri(cur_neg, prev_neg, g_prev_n, col)
			else:
				b.tri(cur_neg, g_prev_n, prev_neg, col)
		else:
			if is_end:
				b.quad(g_cur_n, cur_neg, prev_neg, g_prev_n, col)
			else:
				b.quad(g_prev_n, prev_neg, cur_neg, g_cur_n, col)
		prev_neg = cur_neg


func _embankment_section(b: MeshBuilder, p0: Vector3, p1: Vector3,
		h: float) -> void:
	var dir := p1 - p0
	dir.y = 0.0
	if dir.length_squared() < 1e-6:
		return
	var n := dir.normalized().cross(Vector3.UP)
	for s: float in [-1.0, 1.0]:
		var e0 := p0 + n * (s * h)
		var e1 := p1 + n * (s * h)
		var rise0 := e0.y - _field.height_at(e0.x, e0.z)
		var rise1 := e1.y - _field.height_at(e1.x, e1.z)
		if rise0 < EMBANKMENT_MIN_RISE and rise1 < EMBANKMENT_MIN_RISE:
			continue
		var run0 := maxf(rise0, 0.0) * EMBANKMENT_RUN
		var run1 := maxf(rise1, 0.0) * EMBANKMENT_RUN
		# Бровка совпадает с кромкой ленты полотна, а она лежит на Y_ROAD.
		var lift := Vector3(0.0, CityMesher.Y_ROAD, 0.0)
		var prev0 := e0 + (lift if rise0 >= EMBANKMENT_MIN_RISE else Vector3.ZERO)
		var prev1 := e1 + (lift if rise1 >= EMBANKMENT_MIN_RISE else Vector3.ZERO)
		for band in EMBANKMENT_BANDS:

			var t := float(band + 1) / float(EMBANKMENT_BANDS)
			var cur0 := _slope_point(e0, n * s, run0 * t, rise0, t)
			var cur1 := _slope_point(e1, n * s, run1 * t, rise1, t)
			var col := COLOR_EMBANKMENT.lerp(CityMesher.COLOR_GRASS,
				float(band) / float(EMBANKMENT_BANDS))
			var deg0 := cur0.distance_squared_to(prev0) < 1e-4
			var deg1 := cur1.distance_squared_to(prev1) < 1e-4
			if deg0 and deg1:
				pass
			elif deg0:
				if s > 0.0:
					b.tri(prev0, cur1, prev1, col)
				else:
					b.tri(prev0, prev1, cur1, col)
			elif deg1:
				if s > 0.0:
					b.tri(prev0, cur0, cur1, col)
				else:
					b.tri(cur0, prev0, cur1, col)
			else:
				if s > 0.0:
					b.quad(prev0, cur0, cur1, prev1, col)
				else:
					b.quad(cur0, prev0, prev1, cur1, col)
			prev0 = cur0
			prev1 = cur1



## Точка откоса на доле `t` от бровки к подошве. Высота идёт по smoothstep от
## полотна к рельефу — линейный откос дал бы излом на бровке и на подошве.
func _slope_point(edge: Vector3, outward: Vector3, run: float, rise: float,
		t: float) -> Vector3:
	var p := edge + outward * run
	var ground := _field.height_at(p.x, p.z)
	var top := edge.y + CityMesher.Y_ROAD
	if rise <= 0.0:
		return Vector3(p.x, ground, p.z)
	var k := t * t * (3.0 - 2.0 * t)
	return Vector3(p.x, lerpf(top, ground, k), p.z)


# ============================================================================
# Геометрические примитивы
# ============================================================================

## Веер от центра по замкнутому контуру.
##
## Именно веер, а не ушное разбиение: контур узла НЕ обязан быть простым.
## На острой развилке (32° между подходами, узел `kir_e1`) торцы двух лент
## перекрывают друг друга, и контур сам себя пересекает — ушному разбиению
## такой контур не по зубам, оно молча отдаёт пустоту, то есть дыру во всю
## горловину. Вееру самопересечение не мешает: лишние треугольники ложатся
## внахлёст на уже закрытый асфальт (тот же цвет, та же высота — неразличимо),
## а непокрытых мест не остаётся. Ориентацию каждой грани выправляет `_face`,
## поэтому и невыпуклость контура безопасна.
func _fan(b: MeshBuilder, center: Vector3, poly: PackedVector3Array,
		color: Color) -> void:
	for i in poly.size():
		_face(b, center, poly[(i + 1) % poly.size()], poly[i], color)


## Полоса между двумя цепочками равной длины. `inner` ближе к узлу, `outer`
## дальше; обе идут по возрастанию угла.
##
## Развёрнутый или вырожденный треугольник пропускается, а не разворачивается:
## он означает, что тротуары двух подходов в этом углу уже перекрыли друг друга
## (`A` подхода i зашёл за `B` подхода j) и закрывать нечего.
##
## Проверяется каждый треугольник по отдельности, а не квад целиком: на прямом
## угле перекрёстка торец тротуарной ленты приходится ровно в точку пересечения
## кромок, внутренняя цепочка вырождается в одну точку, и отбраковка квада
## целиком выбрасывала бы вместе с ней и вторую, честную половину — угол
## квартала оставался незамощённым квадратом травы 4x4 м.
func _strip(b: MeshBuilder, inner: PackedVector3Array,
		outer: PackedVector3Array, color: Color, y: float) -> void:
	var lift := Vector3(0.0, y, 0.0)
	for i in range(1, mini(inner.size(), outer.size())):
		var o0 := outer[i - 1] + lift
		var i0 := inner[i - 1] + lift
		var i1 := inner[i] + lift
		var o1 := outer[i] + lift
		if _shoelace(o0, i0, i1) < -MIN_FACE_AREA:
			b.tri(o0, i0, i1, color)
		if _shoelace(o0, i1, o1) < -MIN_FACE_AREA:
			b.tri(o0, i1, o1, color)


## Треугольник с принудительной ориентацией вверх. Знак площади в плане
## однозначно говорит, в каком порядке подавать вершины: у обхода, дающего
## нормаль вверх, площадь по формуле шнурков отрицательна (передние грани у
## Godot намотаны по часовой, `MeshBuilder.tri`).
func _face(b: MeshBuilder, a: Vector3, c1: Vector3, c2: Vector3,
		color: Color) -> void:
	var area := _shoelace(a, c1, c2)
	if absf(area) < MIN_FACE_AREA:
		return
	if area < 0.0:
		b.tri(a, c1, c2, color)
	else:
		b.tri(a, c2, c1, color)


## Удвоенная площадь треугольника в плане (x, z) со знаком.
static func _shoelace(a: Vector3, b: Vector3, c: Vector3) -> float:
	return ((b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)) * 0.5


## Полилиния, смещённая вбок на `d` (знак — сторона `dir x UP`). Направление в
## точке считается так же, как в `ribbon()`, иначе тротуар разъедется с
## полотном на изломе.
func _offset(pts: PackedVector3Array, d: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in pts.size():
		out.append(pts[i] + _dir_at(pts, i).cross(Vector3.UP) * d)
	return out


func _dir_at(pts: PackedVector3Array, i: int) -> Vector3:
	var dir: Vector3
	if i == 0:
		dir = pts[1] - pts[0]
	elif i == pts.size() - 1:
		dir = pts[i] - pts[i - 1]
	else:
		dir = pts[i + 1] - pts[i - 1]
	dir.y = 0.0
	if dir.length_squared() < 1e-8:
		return Vector3.FORWARD
	return dir.normalized()


# ============================================================================
# Доступ к срезам (мешер, разметка, тесты)
# ============================================================================

## Обрезанная полилиния полотна ребра — то, по чему легла лента.
func road_polyline(edge: int) -> PackedVector3Array:
	return _road_poly[edge]


## Вылет горловины k-го подхода узла, м.
func trim(node: int, k: int) -> float:
	return _trim[_approach_base[node] + k]


func plan_length(edge: int) -> float:
	return _plan_len[edge]


## Точка, в которой лента подхода обрывается у узла.
func cut_point(node: int, k: int) -> Vector3:
	return _end_point(_road_poly[_graph.approach_edge(node, k)], node,
		_graph.approach_edge(node, k))


## Точка, в которой обрывается тротуар подхода с указанной его стороны.
func walk_cut_point(node: int, k: int, ccw: bool) -> Vector3:
	var e := _graph.approach_edge(node, k)
	return _end_point(walk_polyline(e, ccw == (_graph.edge_ends(e).x == node)),
		node, e)


## Единичное направление ОТ узла в точке среза.
func cut_dir(node: int, k: int) -> Vector3:
	return _end_dir(_road_poly[_graph.approach_edge(node, k)], node,
		_graph.approach_edge(node, k))


func cut_normal(node: int, k: int) -> Vector3:
	return cut_dir(node, k).cross(Vector3.UP)


func walk_cut_normal(node: int, k: int, ccw: bool) -> Vector3:
	var e := _graph.approach_edge(node, k)
	return _end_dir(walk_polyline(e, ccw == (_graph.edge_ends(e).x == node)),
		node, e).cross(Vector3.UP)


func _end_point(pts: PackedVector3Array, node: int, edge: int) -> Vector3:
	if pts.is_empty():
		return _graph.node_position(node)
	return pts[0] if _graph.edge_ends(edge).x == node else pts[pts.size() - 1]


func _end_dir(pts: PackedVector3Array, node: int, edge: int) -> Vector3:
	if pts.size() < 2:
		return Vector3.RIGHT
	var dir: Vector3
	if _graph.edge_ends(edge).x == node:
		dir = pts[1] - pts[0]
	else:
		dir = pts[pts.size() - 2] - pts[pts.size() - 1]
	dir.y = 0.0
	if dir.length_squared() < 1e-8:
		return Vector3.FORWARD
	return dir.normalized()


# ============================================================================
# Служебное
# ============================================================================

static func _plan_dist(a: Vector3, b: Vector3) -> float:
	var dx := b.x - a.x
	var dz := b.z - a.z
	return sqrt(dx * dx + dz * dz)


## Кусок полилинии между плановыми расстояниями `from` и `to` от её начала.
## Высота на срезе интерполируется по тому же параметру — профиль уклона от
## обрезки не страдает.
##
## `snap` убирает огрызок между срезом и ближайшим изломом полилинии: если
## после обрезки до излома осталось меньше `snap`, срез переносится в сам
## излом. Иначе лента получает квад короче трети собственной ширины между
## двумя сильно повёрнутыми поперечинами и складывается сама на себя — ровно
## это происходило на бульваре Гагарина, где горловина развилки 50° съедала
## 12 из 15.6 м первого сегмента.
func _slice(pts: PackedVector3Array, from: float, to: float,
		snap_from: float = 0.0, snap_to: float = 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts.size() < 2 or to <= from:
		return out
	var acc := 0.0
	for i in range(1, pts.size()):
		var seg := _plan_dist(pts[i - 1], pts[i])
		if seg <= 0.0:
			continue
		var s0 := acc
		var s1 := acc + seg
		acc = s1
		if s1 < from or s0 > to:
			continue
		var a := maxf(from, s0)
		var bb := minf(to, s1)
		var pa := pts[i - 1].lerp(pts[i], (a - s0) / seg)
		var pb := pts[i - 1].lerp(pts[i], (bb - s0) / seg)
		if out.is_empty():
			out.append(pa)
		# Срез, попавший ровно в вершину, даёт нулевой кусок — его точка
		# продублировала бы предыдущую, а `ribbon()` берёт направление
		# крайней точки односторонней разностью и на нуле сорвался бы в
		# запасное направление, развернув первый квад ленты.
		if _plan_dist(out[out.size() - 1], pb) > 1e-4:
			out.append(pb)
	# Ровно по одному шагу с каждого конца: убирается только сама точка среза,
	# а не вершины исходной полилинии. Цикл здесь съел бы серпантин целиком —
	# его ось идёт с шагом около двух метров, мельче любого разумного `snap`.
	if from > 0.0 and out.size() > 2 and _plan_dist(out[0], out[1]) < snap_from:
		out.remove_at(0)
	var last := out.size() - 1
	if to < _arc(pts) and out.size() > 2 \
			and _plan_dist(out[last - 1], out[last]) < snap_to:
		out.remove_at(last)
	return out


static func _arc(pts: PackedVector3Array) -> float:
	var acc := 0.0
	for i in range(1, pts.size()):
		acc += _plan_dist(pts[i - 1], pts[i])
	return acc
