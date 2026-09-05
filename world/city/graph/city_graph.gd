class_name CityGraph
extends RefCounted
## Дорожная сеть как граф произвольной топологии: узлы + рёбра-полилинии.
##
## Сегодня «граф» дорог нигде не материализован: он выводится арифметикой
## round(v / cell) из девяти констант `CityField.road_axes`
## (city_field.gd:76-85), и каждая из пяти подсистем (мешер, трафик,
## пешеходы, GPS, светофоры) заново открывает для себя прямоугольную сетку.
## Здесь граф — первичный источник истины, а сетка 9x9 — лишь один из
## возможных наборов его узлов и рёбер.
##
## Узел и ребро трёхмерные с первого дня, а не Vector2 + высота надстройкой:
## полилиния ребра задаёт одновременно план (x, z) и профиль высоты (y).
## Это прямое обобщение `CityField._serp_x/_serp_z/_serp_y` и готового
## `serpentine_points()` (city_field.gd:334), которые уже хранят ровно такую
## полилинию для одной дороги. `MeshBuilder.ribbon()` (mesh_builder.gd:218)
## принимает `PackedVector3Array`, поэтому полотно на уклоне не потребует
## новой геометрии — только заполненного `y`.
##
## Высота поверхности ВНЕ дорог (рельеф Машука, `surface_height_at`) остаётся
## за `CityField`: граф отвечает только на «на дороге ли и на каком уровне».
##
## [b]Потокобезопасность и сериализация.[/b] Граф целиком состоит из
## `Packed*Array` и словаря с числовыми ключами — как `CityPlan`, его можно
## безопасно собрать в `WorkerThreadPool` на фазе планирования города и
## отдать в главный поток готовым. Отдельного формата сериализации нет и не
## планируется: город восстанавливается из сида, а не из дампа графа.
##
## После `build()` граф read-only — `add_node`/`add_edge` больше не меняют
## его. Но [b]запросы не реентерабельны[/b]: `query_nearest_edge` кладёт
## результат в поля `hit_*` и переиспользует буфер `SpatialHash2D`, чтобы не
## аллоцировать в hot path (трафик и пешеходы дёргают запросы каждый кадр на
## десятки агентов) — поля живут до следующего запроса к этому же графу.
## Один поток — один граф; если позже понадобится опрос из нескольких
## потоков, заводить по курсору на поток, а не мьютекс.

enum NodeKind { INTERSECTION, ROUNDABOUT }

## RAMP — единственный вид ребра, у которого концы лежат на РАЗНЫХ ярусах:
## съезд с эстакады. Его `level` — ярус нижнего конца, поэтому фильтровать
## рампу по `level` наравне с обычным ребром нельзя: она их соединяет.
enum EdgeKind { STREET, AVENUE, SERPENTINE, BRIDGE, TUNNEL, RAMP }

## Сторона относительно направления a -> b, знак `hit_side`.
enum Side { LEFT = -1, ON_AXIS = 0, RIGHT = 1 }

## Шаг ячейки пространственного хеша, м. Соизмерим с полосой влияния ребра
## (полуширина проспекта 6 м + запас 4 м): мельче — сегмент попадает в
## десятки ячеек, крупнее — в ячейке копятся заведомо далёкие кандидаты.
const HASH_CELL := 16.0

## Шаг ячейки хеша узлов, м. Узлы много реже сегментов — шаг взят по шагу
## квартала оригинала (`CityField.cell` = 64 м), чтобы стартовый радиус
## `nearest_node` почти всегда попадал в цель с первой попытки: на мелкой
## сетке поиск тратил втрое больше времени на обход заведомо пустых ячеек.
const NODE_HASH_CELL := 64.0

## Запас к полуширине ребра при регистрации сегмента в хеше, м. Ровно на
## столько за кромку полотна `nearest_edge` отвечает точно, дальше —
## промахом (см. `query_nearest_edge`). Покрывает тротуар (4 м у CityField).
const INFLUENCE_MARGIN := 4.0

## Допуск дизамбигуации по высоте, м: разница `pos.y` и высоты полотна
## больше этой считается «другим уровнем», а не шумом уклона.
##
## Число выбрано между двумя границами, а не изолированно:
##  - снизу — шум обычной улицы: агент стоит на полотне, расхождение даёт
##    только клиренс/подвеска и линейная интерполяция профиля между точками
##    полилинии, это доли метра;
##  - сверху — половина минимального клиренса моста (этап 3). При клиренсе
##    4.5 м половина — 2.25 м; допуск обязан быть строго меньше, иначе
##    точка ровно посередине между улицей и эстакадой подойдёт обоим.
## Если этап 3 возьмёт клиренс ниже 4.5 м, это число придётся уменьшить.
const LEVEL_TOLERANCE := 2.0

## Минимальный просвет разноуровневого пересечения, м: от полотна нижнего
## ребра до НИЗА плиты верхнего (под мостом едут под плитой, а не по её
## проезжей части — отметку деки надо брать на толщину плиты выше).
##
## 4.5 м — предельная высота машины по ПДД РФ (4 м без спецразрешения) плюс
## запас на просадку профиля и на то, что полотно внизу может оказаться чуть
## выше расчётного. Число живёт
## здесь, а не в топологии, потому что оно связано с LEVEL_TOLERANCE:
## допуск обязан быть строго меньше половины клиренса, иначе точка ровно
## посередине между ярусами подойдёт обоим (`test_bridge_geometry.gd`).
## Топология задаёт отметку деки (`PyatigorskTopology.OVERPASS_DECK_Y`) —
## это данные конкретного города; клиренс — инвариант модели.
const MIN_CLEARANCE := 4.5

## Полоса, внутри которой два ребра считаются равноудалёнными, м.
## Меньше сантиметра различий — не выбор, а дрожание float.
const TIE_EPSILON := 0.05

# --- Узлы (SoA) -------------------------------------------------------------
var _node_pos: PackedVector3Array = PackedVector3Array()
var _node_level: PackedInt32Array = PackedInt32Array()
var _node_kind: PackedByteArray = PackedByteArray()
## Радиус кольца, 0 для обычного перекрёстка.
var _node_radius: PackedFloat32Array = PackedFloat32Array()

## Подходы узла в CSR-раскладке: `_approach_start` размером узлы+1,
## внутри диапазона рёбра упорядочены по возрастанию угла atan2(dz, dx)
## направления ОТ узла. Для кольца это и есть список подходов по кругу
## (этапы 6-8: выбор полосы въезда/выезда, веерная триангуляция мешера),
## для перекрёстка — обычная смежность; отдельного списка кольцу не нужно.
var _approach_start: PackedInt32Array = PackedInt32Array()
var _approach_edge: PackedInt32Array = PackedInt32Array()
var _approach_angle: PackedFloat32Array = PackedFloat32Array()

# --- Рёбра (SoA) ------------------------------------------------------------
var _edge_a: PackedInt32Array = PackedInt32Array()
var _edge_b: PackedInt32Array = PackedInt32Array()
var _edge_width: PackedFloat32Array = PackedFloat32Array()
var _edge_kind: PackedByteArray = PackedByteArray()
var _edge_level: PackedInt32Array = PackedInt32Array()
## Название улицы, к которой относится ребро; "" — безымянный проезд.
## Обычная строка, а не ключ локализации: сегодня ни один экран названия
## улиц не показывает. Как только покажет (вывеска, подпись на карте) —
## переводить в `_tr_key()`/CSV, см. `.agents/rules/data-pipeline.md`.
var _edge_name: PackedStringArray = PackedStringArray()
## CSR полилиний: точки ребра e — это `_points[_edge_point_start[e] ..
## _edge_point_start[e + 1])`. Одна общая PackedVector3Array вместо массива
## массивов — чтобы граф оставался плоским набором Packed*Array.
var _edge_point_start: PackedInt32Array = PackedInt32Array()
var _points: PackedVector3Array = PackedVector3Array()
## Полная 3D-длина полилинии: параметр `t` в `nearest_edge` нормирован по
## ней, чтобы у трафика t читался как доля пройденного пути, а не плана.
var _edge_length: PackedFloat32Array = PackedFloat32Array()

# --- Сегменты полилиний (единица пространственного хеша) --------------------
var _seg_edge: PackedInt32Array = PackedInt32Array()
## Индекс первой точки сегмента в `_points`; вторая — следующая за ней.
var _seg_point: PackedInt32Array = PackedInt32Array()
## Накопленная длина ребра до начала сегмента — из неё считается `t`.
var _seg_s0: PackedFloat32Array = PackedFloat32Array()

var _edge_hash := SpatialHash2D.new(HASH_CELL)
var _node_hash := SpatialHash2D.new(NODE_HASH_CELL)
## Габарит графа в плане: диагональ и центр. Из них берётся потолок радиуса
## расширяющегося поиска в `nearest_node` — гарантия, что цикл завершится и
## что хотя бы один узел в него попадёт.
var _span := 0.0
var _center := Vector2.ZERO
var _built := false

# --- Результат последнего nearest_edge --------------------------------------
## Горячая форма запроса пишет сюда, чтобы не создавать словарь на кадр.
var hit_edge := -1
## Доля вдоль полилинии от узла a к узлу b, 0..1.
var hit_t := 0.0
## Значение Side: с какой стороны от направления a -> b лежит запрос.
var hit_side := 0
## Расстояние в плане (x, z) до полотна: высота учтена фильтром уровня.
var hit_dist := INF
## Ближайшая точка на полилинии, включая высоту.
var hit_point := Vector3.ZERO

## Кандидат, выбранный последним `_scan_nodes`.
var _node_best := -1


# --- Построение -------------------------------------------------------------

## Добавляет узел и возвращает его id.
##
## `level` — целочисленный ярус (0 — земля, положительные — эстакады,
## отрицательные — тоннели). Пока это данные для потребителей графа и задел
## под явный фильтр по ярусу; сами запросы `nearest_node`/`nearest_edge`
## его НЕ читают — они различают ярусы по высоте с допуском LEVEL_TOLERANCE.
##
## Разница важна там, где высоты ярусов сходятся: на пандусе выезда на
## эстакаду допуск по высоте перестаёт разделять уровни, и запрос может
## отдать ребро соседнего яруса. Если этапу 6 (заезд трафика на эстакаду)
## это помешает, лечится добавлением фильтра по `level` в запросы, а не
## подкруткой допуска.
func add_node(position: Vector3, level: int = 0,
		kind: int = NodeKind.INTERSECTION, radius: float = 0.0) -> int:
	if _built:
		push_error("CityGraph: add_node после build() — граф read-only")
		return -1
	var id := _node_pos.size()
	_node_pos.append(position)
	_node_level.append(level)
	_node_kind.append(kind)
	_node_radius.append(radius)
	return id


## Добавляет ребро и возвращает его id.
##
## `polyline` включает концевые точки; пустая или вырожденная полилиния
## означает прямое ребро между позициями узлов. Концы в любом случае
## притягиваются к позициям узлов в `build()` — иначе полотно и граф
## разъедутся на стыке.
##
## Ширина по умолчанию — 12 м, полотно проспекта оригинала
## (2 * `BalanceData.road_half` = 2 * 6, city_field.gd:40).
##
## `street_name` — название улицы, которой принадлежит ребро; цепочка рёбер
## одной улицы несёт одно и то же имя. Пусто для безымянных проездов.
func add_edge(a: int, b: int, polyline: PackedVector3Array = PackedVector3Array(),
		width: float = 12.0, kind: int = EdgeKind.STREET, level: int = 0,
		street_name: String = "") -> int:
	if _built:
		push_error("CityGraph: add_edge после build() — граф read-only")
		return -1
	var id := _edge_a.size()
	_edge_a.append(a)
	_edge_b.append(b)
	_edge_width.append(width)
	_edge_kind.append(kind)
	_edge_level.append(level)
	_edge_name.append(street_name)
	_edge_point_start.append(_points.size())
	if polyline.size() < 2:
		_points.append(_node_pos[a])
		_points.append(_node_pos[b])
	else:
		_points.append_array(polyline)
	return id


## Финализация: замыкание CSR, длины, смежность по углу, хеши.
## После неё граф только читается.
func build() -> void:
	if _built:
		return
	_edge_point_start.append(_points.size())
	_snap_endpoints()
	_build_segments()
	_build_adjacency()
	_build_hashes()
	_built = true


func is_built() -> bool:
	return _built


## Концы полилинии обязаны совпадать с узлами: иначе `nearest_node` и
## `nearest_edge` на перекрёстке дают точки в разных местах, а лента мешера
## отходит от полотна поперечной улицы.
func _snap_endpoints() -> void:
	for e in _edge_a.size():
		var s := _edge_point_start[e]
		var t := _edge_point_start[e + 1]
		_points[s] = _node_pos[_edge_a[e]]
		_points[t - 1] = _node_pos[_edge_b[e]]


func _build_segments() -> void:
	_edge_length.resize(_edge_a.size())
	for e in _edge_a.size():
		var s := _edge_point_start[e]
		var t := _edge_point_start[e + 1]
		var acc := 0.0
		for i in range(s, t - 1):
			_seg_edge.append(e)
			_seg_point.append(i)
			_seg_s0.append(acc)
			acc += _points[i].distance_to(_points[i + 1])
		_edge_length[e] = acc


func _build_adjacency() -> void:
	var n := _node_pos.size()
	var bucket_edge: Array[PackedInt32Array] = []
	var bucket_angle: Array[PackedFloat32Array] = []
	for i in n:
		bucket_edge.append(PackedInt32Array())
		bucket_angle.append(PackedFloat32Array())
	for e in _edge_a.size():
		_insert_approach(bucket_edge, bucket_angle, _edge_a[e], e)
		_insert_approach(bucket_edge, bucket_angle, _edge_b[e], e)

	_approach_start.resize(n + 1)
	for i in n:
		_approach_start[i] = _approach_edge.size()
		_approach_edge.append_array(bucket_edge[i])
		_approach_angle.append_array(bucket_angle[i])
	_approach_start[n] = _approach_edge.size()


## Вставка с сохранением порядка по углу. Сортировка вставками, а не
## sort_custom: степень узла — единицы, а лямбда-компаратор на каждый узел
## стоила бы дороже самой сортировки.
func _insert_approach(bucket_edge: Array[PackedInt32Array],
		bucket_angle: Array[PackedFloat32Array], node: int, edge: int) -> void:
	var angle := _outgoing_angle(edge, node)
	# Packed*Array — значение с copy-on-write: правка локальной копии не
	# доходит до элемента массива, её обязательно надо положить обратно.
	var list := bucket_edge[node]
	var angles := bucket_angle[node]
	var k := angles.size()
	while k > 0 and angles[k - 1] > angle:
		k -= 1
	list.insert(k, edge)
	angles.insert(k, angle)
	bucket_edge[node] = list
	bucket_angle[node] = angles


## Угол направления, с которым ребро отходит ОТ узла, atan2(dz, dx).
func _outgoing_angle(edge: int, node: int) -> float:
	var s := _edge_point_start[edge]
	var t := _edge_point_start[edge + 1]
	var dir := _points[s + 1] - _points[s] if _edge_a[edge] == node \
		else _points[t - 2] - _points[t - 1]
	return atan2(dir.z, dir.x)


## Каждый сегмент регистрируется в ячейках, которые задевает его габарит,
## расширенный на полосу влияния (полуширина + запас). Благодаря этому
## запрос из точки внутри полосы обходится одной ячейкой без расширения
## радиуса — тот же приём, что в `CityField._build_serp_hash()`.
##
## Индекс в обоих хешах совпадает с индексом сегмента/узла: элементы
## добавляются строго по порядку.
func _build_hashes() -> void:
	for i in _seg_edge.size():
		var p0 := _points[_seg_point[i]]
		var p1 := _points[_seg_point[i] + 1]
		var pad := _influence(_seg_edge[i])
		_edge_hash.add_rect(
			minf(p0.x, p1.x) - pad, minf(p0.z, p1.z) - pad,
			maxf(p0.x, p1.x) + pad, maxf(p0.z, p1.z) + pad)

	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in _node_pos.size():
		var p := _node_pos[i]
		_node_hash.add_point(p.x, p.z, 0.0)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	if not _node_pos.is_empty():
		_span = lo.distance_to(hi) + NODE_HASH_CELL
		_center = (lo + hi) * 0.5


func _influence(edge: int) -> float:
	return _edge_width[edge] * 0.5 + INFLUENCE_MARGIN


# --- Доступ к данным --------------------------------------------------------

func node_count() -> int:
	return _node_pos.size()


func edge_count() -> int:
	return _edge_a.size()


func node_position(id: int) -> Vector3:
	return _node_pos[id]


func node_level(id: int) -> int:
	return _node_level[id]


func node_kind(id: int) -> int:
	return _node_kind[id]


func node_radius(id: int) -> float:
	return _node_radius[id]


func node_degree(id: int) -> int:
	return _approach_start[id + 1] - _approach_start[id]


## Ребро k-го подхода узла в порядке возрастания угла.
func approach_edge(node: int, k: int) -> int:
	return _approach_edge[_approach_start[node] + k]


## Угол k-го подхода, atan2(dz, dx) направления от узла, радианы.
func approach_angle(node: int, k: int) -> float:
	return _approach_angle[_approach_start[node] + k]


func edge_ends(id: int) -> Vector2i:
	return Vector2i(_edge_a[id], _edge_b[id])


func edge_width(id: int) -> float:
	return _edge_width[id]


func edge_kind(id: int) -> int:
	return _edge_kind[id]


func edge_level(id: int) -> int:
	return _edge_level[id]


func edge_name(id: int) -> String:
	return _edge_name[id]


func edge_length(id: int) -> float:
	return _edge_length[id]


func edge_point_count(id: int) -> int:
	return _edge_point_start[id + 1] - _edge_point_start[id]


func edge_point(id: int, k: int) -> Vector3:
	return _points[_edge_point_start[id] + k]


## Копия полилинии ребра — для мешера и отладки, не для hot path:
## slice() аллоцирует. В горячих циклах брать точки через `edge_point()`.
func edge_polyline(id: int) -> PackedVector3Array:
	return _points.slice(_edge_point_start[id], _edge_point_start[id + 1])


# --- Запросы ----------------------------------------------------------------

## Ближайший узел к точке. Замена `CityField.nearest_intersection()`.
##
## Среди найденных кандидатов сперва рассматриваются узлы своего уровня
## (|dy| <= LEVEL_TOLERANCE), и только если таких нет — ближайший по полному
## 3D-расстоянию: агент на эстакаде не должен привязываться к перекрёстку
## под ней. Радиус поиска при этом не расширяется ради узла своего уровня:
## если рядом только чужой ярус, вернётся он, а не собрат за сто метров.
func nearest_node(pos: Vector3) -> int:
	if _node_pos.is_empty():
		return -1
	# Любой узел лежит не дальше половины диагонали от центра габарита,
	# значит на этом радиусе круг накроет как минимум один.
	var limit := _span + Vector2(pos.x, pos.z).distance_to(_center)
	var r := NODE_HASH_CELL
	while r < limit:
		var d := _scan_nodes(pos, r)
		if d < INF:
			# Узел мог найтись у самой кромки круга — круг радиусом d
			# гарантированно покрывает всех, кто ближе.
			if d > r:
				_scan_nodes(pos, d)
			return _node_best
		r *= 2.0
	_scan_nodes(pos, limit)
	return _node_best


## Возвращает минимальное (x, z)-расстояние среди просмотренных узлов
## (INF, если в радиусе нет ни одного); выбранный узел остаётся в `_node_best`.
func _scan_nodes(pos: Vector3, radius: float) -> float:
	_node_best = -1
	var best_level := INF
	var best_any := INF
	var min_xz := INF
	for i in _node_hash.query_circle(pos.x, pos.z, radius):
		var p := _node_pos[i]
		var dx := pos.x - p.x
		var dz := pos.z - p.z
		var dxz := sqrt(dx * dx + dz * dz)
		min_xz = minf(min_xz, dxz)
		var dy := pos.y - p.y
		if absf(dy) <= LEVEL_TOLERANCE:
			if dxz < best_level:
				best_level = dxz
				_node_best = i
		elif best_level == INF:
			var d3 := sqrt(dxz * dxz + dy * dy)
			if d3 < best_any:
				best_any = d3
				_node_best = i
	return min_xz


## Ближайшее ребро: `{edge_id, t, side, dist}`. Каждый вызов отдаёт СВОЙ
## словарь — два результата можно держать рядом и сравнивать.
##
## Словарь стоит аллокации, поэтому в горячих циклах звать
## `query_nearest_edge()` и читать поля `hit_*`; там же живёт и `hit_point`,
## которого в словаре нет.
func nearest_edge(pos: Vector3, max_dist: float = 0.0) -> Dictionary:
	query_nearest_edge(pos, max_dist)
	return {"edge_id": hit_edge, "t": hit_t, "side": hit_side, "dist": hit_dist}


## Горячая форма: возвращает edge_id (или -1) и оставляет подробности в
## полях `hit_*`. Ноль аллокаций — буфер хеша и поля переиспользуются.
##
## `max_dist` = 0 означает «отвечать в полосе влияния рёбер»: запрос
## обходится одной ячейкой хеша и ТОЧЕН для любой точки, лежащей не дальше
## полуширины плюс `INFLUENCE_MARGIN` от какого-нибудь полотна — то есть
## ровно там, где работают трафик и пешеходы. Дальше ответ не гарантирован:
## в ячейку могут попасть далёкие ребра (габарит длинной диагонали накрывает
## её целиком), а могут не попасть никакие — вернётся -1. Расширяющийся
## поиск ради корректного ответа из середины квартала стоил бы hot path'у
## больше, чем стоит ответ, которым никто не пользуется. Положительный
## `max_dist` включает точный поиск в этом радиусе (GPS, привязка POI).
##
## [b]Разноуровневое пересечение.[/b] Кандидаты сперва фильтруются по
## близости высоты полотна к `pos.y` (LEVEL_TOLERANCE), и уже среди них
## ищется ближайший в плане. Без этого правила агент на мосту «залипал» бы
## на улице под мостом: в плане она ровно так же близка.
func query_nearest_edge(pos: Vector3, max_dist: float = 0.0) -> int:
	hit_edge = -1
	hit_t = 0.0
	hit_side = Side.ON_AXIS
	hit_dist = INF
	hit_point = Vector3.ZERO
	if not _built:
		return -1

	var best_level := INF
	var best_any := INF
	var seg_level := -1
	var seg_any := -1
	var t_level := 0.0
	var t_any := 0.0
	for i in _edge_hash.query_circle(pos.x, pos.z, max_dist):
		var p0 := _points[_seg_point[i]]
		var p1 := _points[_seg_point[i] + 1]
		var dx := p1.x - p0.x
		var dz := p1.z - p0.z
		var denom := dx * dx + dz * dz
		var t := 0.0 if denom < 1e-9 else ((pos.x - p0.x) * dx + (pos.z - p0.z) * dz) / denom
		t = clampf(t, 0.0, 1.0)
		var proj := p0.lerp(p1, t)
		var ddx := pos.x - proj.x
		var ddz := pos.z - proj.z
		var dxz := sqrt(ddx * ddx + ddz * ddz)
		if max_dist > 0.0 and dxz > max_dist:
			continue
		if absf(pos.y - proj.y) <= LEVEL_TOLERANCE:
			if _better(dxz, _seg_edge[i], best_level, seg_level):
				best_level = dxz
				seg_level = i
				t_level = t
		elif seg_level < 0:
			var dy := pos.y - proj.y
			var d3 := sqrt(dxz * dxz + dy * dy)
			if _better(d3, _seg_edge[i], best_any, seg_any):
				best_any = d3
				seg_any = i
				t_any = t

	if seg_level >= 0:
		_fill_hit(seg_level, t_level, pos)
	elif seg_any >= 0:
		_fill_hit(seg_any, t_any, pos)
	return hit_edge


## Приоритет, когда два ребра одного яруса почти равноудалены (стык съезда
## с магистралью, узкий проезд вдоль широкого полотна): сперва расстояние,
## при разнице меньше TIE_EPSILON — более широкое ребро, при равной ширине —
## меньший id.
##
## Широкое побеждает потому, что его полотно физически перекрывает узкое:
## точка на равном удалении от осей лежит внутри широкого и, скорее всего,
## снаружи узкого. Меньший id — только чтобы выбор был детерминированным,
## а не зависел от порядка обхода ячейки хеша.
func _better(dist: float, edge: int, best: float, best_seg: int) -> bool:
	if best_seg < 0:
		return true
	if dist < best - TIE_EPSILON:
		return true
	if dist > best + TIE_EPSILON:
		return false
	var rival := _seg_edge[best_seg]
	if _edge_width[edge] != _edge_width[rival]:
		return _edge_width[edge] > _edge_width[rival]
	return edge < rival


func _fill_hit(seg: int, t_seg: float, pos: Vector3) -> void:
	var e := _seg_edge[seg]
	var p0 := _points[_seg_point[seg]]
	var p1 := _points[_seg_point[seg] + 1]
	var proj := p0.lerp(p1, t_seg)
	hit_edge = e
	hit_point = proj
	var ddx := pos.x - proj.x
	var ddz := pos.z - proj.z
	hit_dist = sqrt(ddx * ddx + ddz * ddz)
	var length := _edge_length[e]
	var s := _seg_s0[seg] + p0.distance_to(p1) * t_seg
	hit_t = 0.0 if length <= 0.0 else clampf(s / length, 0.0, 1.0)
	# Векторное произведение в плоскости (x, z) правой тройки с Y вверх:
	# при движении на восток (+X) точка на юге (+Z) даёт плюс и лежит
	# справа по ходу — то есть на своей полосе при правостороннем движении.
	var cross := (p1.x - p0.x) * ddz - (p1.z - p0.z) * ddx
	hit_side = Side.ON_AXIS
	if cross > 0.0:
		hit_side = Side.RIGHT
	elif cross < 0.0:
		hit_side = Side.LEFT


## Высота полотна под точкой, NAN — если под ней нет проезжей части.
## Графовый аналог `CityField.surface_height_at()`, но с дизамбигуацией по
## ярусу: на деке моста вернётся отметка деки, под мостом — улица под ним.
##
## Ярус выбирает та же логика, что и в `query_nearest_edge`: сперва рёбра,
## чья высота отличается от `pos.y` не больше чем на LEVEL_TOLERANCE, и
## только если таких нет — ближайшее в 3D. Из этого следует единственная
## неоднозначность: точка ровно посередине между улицей и декой (при
## отметке деки 6.5 м это 3.25 м) не принадлежит ни одному ярусу, и ответ
## решается расстоянием в плане. Держать агента посередине между ярусами
## нечем — на рампе высота меняется непрерывно, а не скачком.
##
## Высота ВНЕ дорог (двор, газон, склон Машука) остаётся за `CityField`:
## поэтому здесь NAN, а не «земля», — у поля рельефа один владелец.
func surface_y_at(pos: Vector3) -> float:
	var e := query_nearest_edge(pos)
	if e < 0 or hit_dist > _edge_width[e] * 0.5:
		return NAN
	return hit_point.y


## Запас от точки до КРОМКИ ближайшего полотна своего яруса, м:
## `dist - width / 2`, минимум по всем рёбрам в радиусе `radius`.
## Отрицательное значение — точка на проезжей части, INF — рядом дорог нет.
##
## Это не `nearest_edge`, у которого другая задача: тот отдаёт ближайшую ОСЬ
## и на равном удалении от узкого проезда и широкого проспекта выберет
## проезд, хотя точка лежит внутри полотна проспекта. Застройке нужен
## именно минимум запаса по всем соседям — «ни один дом не стоит на
## проезжей части» иначе не проверить.
##
## `radius` задаёт и полосу поиска, и границу точности: ответ точен для
## точек не дальше `radius` от оси сегмента, дальше вернётся INF.
func road_clearance(pos: Vector3, radius: float) -> float:
	var best := INF
	for i in _edge_hash.query_circle(pos.x, pos.z, radius):
		var p0 := _points[_seg_point[i]]
		var p1 := _points[_seg_point[i] + 1]
		var dx := p1.x - p0.x
		var dz := p1.z - p0.z
		var denom := dx * dx + dz * dz
		var t := 0.0 if denom < 1e-9 \
			else ((pos.x - p0.x) * dx + (pos.z - p0.z) * dz) / denom
		var proj := p0.lerp(p1, clampf(t, 0.0, 1.0))
		# Ярус разводит полотна так же, как в query_nearest_edge: улица под
		# эстакадой не мешает строить рядом с опорой, и наоборот.
		if absf(pos.y - proj.y) > LEVEL_TOLERANCE:
			continue
		var ddx := pos.x - proj.x
		var ddz := pos.z - proj.z
		if ddx * ddx + ddz * ddz > radius * radius:
			continue
		best = minf(best,
			sqrt(ddx * ddx + ddz * ddz) - _edge_width[_seg_edge[i]] * 0.5)
	return best


## Проезжая часть под точкой — замена `CityField.on_road()`.
## Именно на своём уровне: под мостом остаётся улица, а не полотно моста.
func on_road(pos: Vector3) -> bool:
	var e := query_nearest_edge(pos)
	if e < 0:
		return false
	if absf(pos.y - hit_point.y) > LEVEL_TOLERANCE:
		return false
	return hit_dist <= _edge_width[e] * 0.5
