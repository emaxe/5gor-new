class_name PedGraph
extends RefCounted
## Граф ходьбы города поверх графа улиц: углы перекрёстков, ленты тротуара,
## переходы, jwalk.
##
## Порт pedgraph.js с четырьмя отличиями. Все четыре в силе и после перехода
## на явный граф — переделана была только АДРЕСАЦИЯ узлов:
##
##  1. Узлы стоят в УГЛАХ перекрёстка, а не по центру пересекающей дороги.
##     В оригинале тротуарный узел на перекрёстке лежал в точке (r±8, axes[j]) —
##     посреди поперечной проезжей части, и ходьба вдоль ленты пересекала
##     дорогу мимо зебры. Регрессия test_no_ungated_segment_crosses_roadway
##     это ловит.
##  2. Поиск пути — на встроенном AStar3D (C++), а не ручным Dijkstra:
##     сотни узлов в GDScript-цикле стоили бы 1-3 мс на запрос.
##  3. id узла — плотный индекс в ЯВНЫХ таблицах (`_corner_first`,
##     `_edge_mid`), а не формула по индексам сетки. Формулы
##     `corner_id(i, j, corner)`/`vmid_id`/`hmid_id` больше нет: у узла
##     столько углов, сколько у него подходов, а не всегда четыре.
##  4. Маршрут возвращается парой массивов `points[]` / `gates[]`:
##     gates[i] — светофор, который надо пройти на зелёный, чтобы попасть
##     в points[i], или -1. Агент остаётся тупым автоматом (приём из capital).
##
## [b]Источник топологии — `CityGraph` (этап 1).[/b] Углы, ленты и переходы
## читают ОДНИ И ТЕ ЖЕ данные подходов (`approach_edge`/`approach_angle`),
## что мешер перекрёстка (этап 4) и светофор узла (этап 7). Поэтому число
## углов пешеходного графа равно числу сторон полигона перекрёстка и номер
## подхода в гейте равен номеру подхода светофора — без единой строки
## отдельной синхронизации.
##
## [b]Стоимости.[/b] Переход через дорогу стоит 2.0, jwalk — 3.0 (порт
## оригинала), тротуар — 0.5 за 24 м (половина сеточной ленты в 48 м).
## Отличие от оригинала и от сеточной версии: ходьба стоит ЗА МЕТР, а не
## фиксированно за ребро. На сетке, где все полуленты по 24 м, это ровно
## прежние 0.5 и прежние маршруты; на настоящем графе, где рукав кольца в 20 м
## соседствует со стометровым проспектом, фиксированная цена ребра сделала бы
## длинный путь дешевле короткого. Поворот за угол бесплатен: угловой узел
## общий у двух лент, «срез угла» — это просто проход через узел.
##
## [b]Пешеходы на мостах и в тоннелях.[/b] Тротуар на деке моста — обычная
## лента вдоль ребра, высота приходит из полилинии ребра сама. Внутри тоннеля
## (`EdgeKind.TUNNEL`) ленты нет вовсе: пешеход не ходит по проезжей части
## тоннеля, а обходит поверху. Пешеходный тоннель как самостоятельная
## сущность в модели не заведён — топология этапа 2 тоннелей не содержит
## (`pyatigorsk_topology.gd:51-54`), и заводить их «на будущее» здесь нечего.

enum Edge { WALK, CROSS, JWALK }
## Ось дороги, которую пересекает переход: Z_ROAD — дорога, по которой машины
## едут вдоль Z (пешеход идёт поперёк, вдоль X). Понятие осевое и живёт только
## в мосте к `TrafficLightController` (см. `gate_axial`).
enum CrossAxis { Z_ROAD, X_ROAD }

## Штраф за пересечение проезжей части по зебре, в единицах стоимости
## (порт pedgraph.js: cross 2.0, jwalk 3.0).
const COST_CROSS := 2.0
const COST_JWALK := 3.0
## Цена метра тротуара: полулента сетки — 24 м (шаг 64 м минус два выноса
## угла по 8 м, делённые пополам) и стоит 0.5, как в оригинале.
const WALK_COST_PER_M := 0.5 / 24.0

## Доля рёбер, где протоптан переход в неположенном месте.
const JWALK_CHANCE := 0.3
## Сид, отдельный от городского: добавление зданий не должно сдвигать jwalk.
const JWALK_SEED := 20260807
## POI дальше этого от узла считается вне сетки (Машук) и отбрасывается, м.
const POI_MAX_DIST := 40.0

## Минимальная половина угла между соседними рукавами при расчёте выноса
## угла, рад. 0.4 (23°) ограничивает вынос величиной ped_side / sin(0.4) =
## 2.57 * ped_side: на более острой развилке честное пересечение кромок
## уносит угол на десятки метров от перекрёстка, и «угол тротуара» перестаёт
## быть углом. Та же по смыслу отсечка, что `RoadMesh.TRIM_EDGE_FRACTION`
## у мешера.
const MIN_CORNER_HALF := 0.4

## Запас обвода торца тупика над полуширотой полотна. Хорда обвода обязана
## пройти СНАРУЖИ полотна; 5 % — чтобы она проходила с зазором, а не легла на
## кромку впритык, где всё решает погрешность acos/cos.
const DEAD_END_CLEARANCE := 1.05
## Потолок числа звеньев обвода торца. На 8 звеньях хорда отходит от узла на
## `cos(PI/16) = 0.98 * ped_side`: если тротуар не шире полотна, обвода
## снаружи не существует ни при каком дроблении, и дробить дальше незачем.
const DEAD_END_CAP_MAX := 8

## Допуск «рукава противоположны» для узла степени 2, рад. 45° — та же
## граница, что `NodeSignalController.OPPOSITE_TOL`: пара рукавов, расходя-
## щаяся меньше чем на 45° от развёрнутой прямой, читается как одна улица,
## идущая насквозь, и переход поперёк неё законен. На изломе (угол квартала
## сетки) перехода нет вовсе: у узла степени 2 всего два угла тротуара, и
## отрезок между ними прошёл бы наискось через сам перекрёсток, а не поперёк
## одного рукава.
const STRAIGHT_TOL := PI * 0.25

## Шаг ячейки пространственного хеша узлов, м. Соизмерим с шагом самих узлов
## (полулента сетки — 24 м): мельче — пустые ячейки, крупнее — в ячейке
## копятся заведомо далёкие кандидаты.
const HASH_CELL := 32.0

## Разряд упаковки пары узлов в ключ ребра и узла с подходом в гейт.
## 1 << 20 — с запасом на порядок больше, чем узлов в пешеходном графе города
## (сетка 9x9 даёт 576), и заведомо меньше 2^63 при перемножении.
const EDGE_KEY_STRIDE := 1 << 20
## Максимальная степень узла, помещающаяся в гейт.
const GATE_STRIDE := 16

# --- Мост к сеточной модели (умирает на этапе 9) -----------------------------
## Осей дорог в сеточном городе. Читается `CityGraphGrid`, `CityPlanner`,
## `CityBuilder` — вместе со статическим `is_signalized()` ниже это остаток
## сеточной адресации, живущий до перехода живого конвейера на топологию.
const AXES := 9

var ped_side := 8.0
## Оси сеточного города — только для `gate_axial()`; на настоящем графе пусты.
var axes: PackedFloat32Array = PackedFloat32Array()

## Граф без jwalk — для законопослушных пешеходов.
var legal: PedAStar
## Граф со всеми рёбрами — для нарушителей.
var full: PedAStar

## Переходы как данные: из этого списка рисуются зебры, стойки и линзы —
## разметка не может разъехаться с логикой.
##
## [b]Подмена `RoadMarkings._stub_crossings()` отложена на этап 9.[/b]
## `road_markings.gd:12-19` (этап 4b) обязывает заменить заглушку этим
## списком, но сам `RoadMarkings` в живом конвейере ещё не работает — точка
## подключения та же, где живой город переходит на топологию. Обещанной
## заменой «в одну строку» это не будет, и вот чего не хватает:
##
## - формы записи: здесь `{a, b, gate, node, approach, center, yaw}`, а
##   `RoadMarkings._build_zebra()` читает ещё `edge` (ребро рукава) и `width`
##   (ширина полотна, от неё считается число полос зебры);
## - соглашения о `yaw`: `RoadMarkings` берёт `atan2(dir.x, dir.z)` от
##   направления рукава, здесь — `-atan2(dz, dx)` от направления хода
##   пешехода, то есть ПОПЕРЁК рукава. Значения расходятся, сводить их
##   придётся при подмене.
var crossings: Array[Dictionary] = []

var poi_nodes: PackedInt32Array = PackedInt32Array()
var poi_tags: PackedStringArray = PackedStringArray()

var _graph: CityGraph
var _positions: PackedVector3Array = PackedVector3Array()
var _edge_kind: Dictionary[int, int] = {}
var _edge_cost: Dictionary[int, float] = {}
var _edge_gate: Dictionary[int, int] = {}

## Первый угловой (кербовый) узел тротуара для узла графа улиц; сами углы
## лежат подряд, поэтому таблица нужна одна.
var _corner_first: PackedInt32Array = PackedInt32Array()
## Левый серединный узел ленты ребра (правый — следующий id), -1 без ленты.
var _edge_mid: PackedInt32Array = PackedInt32Array()
## Номер подхода ребра у его узла a / b.
var _approach_a: PackedInt32Array = PackedInt32Array()
var _approach_b: PackedInt32Array = PackedInt32Array()
## Регулируется ли узел графа улиц (1) — список из топологии, не арифметика.
var _regulated: PackedByteArray = PackedByteArray()

var _mid_first := 0
var _mid_count := 0

## Минимальная цена метра по всем рёбрам графа — множитель эвристики A*.
var _h_scale := INF

var _hash := SpatialHash2D.new(HASH_CELL)
var _span := 0.0
var _center := Vector2.ZERO
var _near_best := -1


## AStar3D со стоимостями рёбер графа, а не евклидовым расстоянием: цена
## перехода — правило ПДД, а не геометрия.
class PedAStar extends AStar3D:
	## Слабая ссылка, а не прямая: граф держит два экземпляра PedAStar,
	## и обратная сильная ссылка замкнула бы цикл RefCounted — граф никогда
	## бы не освободился (проверено: 7 утёкших объектов при выходе).
	var _graph_ref: WeakRef

	func bind_graph(graph: PedGraph) -> void:
		_graph_ref = weakref(graph)

	func _compute_cost(from_id: int, to_id: int) -> float:
		var g := _graph_ref.get_ref() as PedGraph
		return g.edge_cost(from_id, to_id) if g != null else 1.0

	func _estimate_cost(from_id: int, to_id: int) -> float:
		var g := _graph_ref.get_ref() as PedGraph
		return g.heuristic(from_id, to_id) if g != null else 0.0


## Живой сеточный город: граф улиц берётся у моста этапа 6, регулируемые узлы —
## у него же. Ничего сеточного дальше конструктора не проникает: сам PedGraph
## работает с `CityGraph` произвольной топологии.
##
## Без поля создаётся пустой граф — точка входа для `on_graph()`.
func _init(field: CityField = null) -> void:
	legal = PedAStar.new()
	legal.bind_graph(self)
	full = PedAStar.new()
	full.bind_graph(self)
	if field == null:
		return
	axes = field.road_axes
	_setup(CityGraphGrid.from_field(field),
		CityGraphGrid.signalized_nodes(field),
		field.road_half + field.sidewalk * 0.5)


## Пешеходный граф поверх произвольного графа улиц: настоящая топология
## (этап 9), синтетические полигоны тестов.
static func on_graph(graph: CityGraph, signal_nodes: PackedInt32Array,
		side: float) -> PedGraph:
	var g := PedGraph.new()
	g._setup(graph, signal_nodes, side)
	return g


# --- Идентификаторы ---------------------------------------------------------

func edge_key(a: int, b: int) -> int:
	return mini(a, b) * EDGE_KEY_STRIDE + maxi(a, b)


## Гейт: узел графа улиц + номер подхода. Номер подхода — тот же, что у
## `CityGraph.approach_edge`, поэтому этап 9 спрашивает светофор напрямую:
## `NodeSignalController.is_crossing_open(gate_node(g), gate_approach(g))`.
static func gate_id(node_id: int, approach_id: int) -> int:
	return node_id * GATE_STRIDE + approach_id


static func gate_node(gate: int) -> int:
	@warning_ignore("integer_division")
	var node: int = gate / GATE_STRIDE
	return node


static func gate_approach(gate: int) -> int:
	return gate % GATE_STRIDE


## Регулируется ли перекрёсток светофором — СЕТОЧНАЯ модель.
##
## В оригинале стойки ставятся через один перекрёсток (citygen.js:2691:
## `for i = 1; i < 8; i += 2`), то есть на нечётных индексах сетки.
##
## [b]Это мост, а не модель.[/b] Функция осталась ради `CityGraphGrid`
## (`signalized_nodes()`), `CityPlanner` и `CityBuilder`, которые до этапа 9
## живут на сеточной адресации. Сам PedGraph её не зовёт: регулируемость узла
## он спрашивает у `is_regulated(node_id)` по списку из топологии.
static func is_signalized(i: int, j: int) -> bool:
	return i % 2 == 1 and j % 2 == 1 and i < AXES - 1 and j < AXES - 1


# --- Построение -------------------------------------------------------------

func _setup(graph: CityGraph, signal_nodes: PackedInt32Array,
		side: float) -> void:
	_graph = graph
	ped_side = side
	_build_regulated(signal_nodes)
	_build_corners()
	_build_ribbons()
	_build_crossings()
	_build_ring_walks()
	_build_dead_end_caps()
	_build_jwalks()
	_build_hash()
	if is_inf(_h_scale):
		_h_scale = 0.0


## Регулируемые узлы — ЯВНЫЙ список (этап 7), а не чётность индексов сетки.
##
## Два отсева повторяют `NodeSignalController._build()` буква в букву: на
## кольце фаз нет по определению, у узла степени меньше 3 нет конфликтующих
## траекторий. Без них пешеход ждал бы на гейте зелёного, которого светофор
## никогда не даст, — и висел бы до аварийного таймаута.
func _build_regulated(signal_nodes: PackedInt32Array) -> void:
	var n := _graph.node_count()
	_regulated.resize(n)
	_regulated.fill(0)
	for node in signal_nodes:
		if node < 0 or node >= n:
			continue
		if _graph.node_kind(node) == CityGraph.NodeKind.ROUNDABOUT:
			continue
		if _graph.node_degree(node) < 3:
			continue
		_regulated[node] = 1


## Углы тротуара: по одному между каждой парой соседних подходов; у кольца
## (см. `_ring_kerb_pos`) и у тупика (см. `_dead_end_kerb_pos`) — по две
## кербовые точки на рукав.
func _build_corners() -> void:
	var n := _graph.node_count()
	_corner_first.resize(n)
	for node in n:
		var d := _graph.node_degree(node)
		_corner_first[node] = _positions.size()
		if _is_ring(node):
			for k in d:
				_add_node(_ring_kerb_pos(node, k, false))
				_add_node(_ring_kerb_pos(node, k, true))
		elif d == 1:
			_add_node(_dead_end_kerb_pos(node, false))
			_add_node(_dead_end_kerb_pos(node, true))
		else:
			for k in d:
				_add_node(_corner_pos(node, k))


## Угол между подходами k и k+1: точка пересечения внешних кромок этих двух
## рукавов. Она лежит на биссектрисе угла между ними на расстоянии
## `ped_side / sin(половина угла)` — при 90° это привычные (±8, ±8) сетки,
## при развёрнутых 180° (проход насквозь) — ровно `ped_side` вбок.
##
## Расстояние ВСЕГДА не меньше `ped_side`, поэтому САМ УГОЛ гарантированно
## лежит вне полотна обоих рукавов (`ped_side = road_half + sidewalk/2 >
## road_half`). Зовётся только при степени >= 2 и не для кольца.
##
## [b]Что отсюда следует, а что нет.[/b] Конструкция доказывает свойство
## ТОЧЕК, а главный инвариант ПДД — свойство ОТРЕЗКОВ между ними. Второе
## вытекает из первого лишь потому, что угол ОБЩИЙ у пары соседних подходов:
## лента идёт от него вдоль своего рукава, оба её конца отстоят от оси не
## меньше чем на `ped_side`, значит и вся она снаружи полотна. У вывода два
## исключения:
##
## 1. отсечка `MIN_CORNER_HALF`: на развилке острее 46° вынос зажимается, и
##    угол может оказаться ближе `ped_side` к одному из рукавов;
## 2. степень 1: пары соседних подходов нет вовсе, «общий угол» вырождается в
##    точку на самой оси улицы, и ленты к нему режут полотно наискось. Поэтому
##    тупик обслуживает не эта функция, а `_dead_end_kerb_pos` плюс обвод
##    торца (`_build_dead_end_caps`).
##
## В обоих случаях страхует тест, а не конструкция: `_segment_enters_roadway`
## меряет расстояние отрезок-полилиния по всей длине отрезка, а не в концах.
func _corner_pos(node: int, k: int) -> Vector3:
	var c := _graph.node_position(node)
	var d := _graph.node_degree(node)
	var a0 := _graph.approach_angle(node, k)
	var a1 := _graph.approach_angle(node, (k + 1) % d)
	# Подходы упорядочены по возрастанию угла, поэтому положительный остаток
	# и есть сектор между ними; на замыкающей паре он же даёт остаток круга.
	var gap := fposmod(a1 - a0, TAU)
	var half := clampf(gap * 0.5, MIN_CORNER_HALF, PI - MIN_CORNER_HALF)
	var ang := a0 + gap * 0.5
	return c + Vector3(cos(ang), 0.0, sin(ang)) * (ped_side / sin(half))


## Кербовая точка тупика: сбоку от единственного рукава, вровень с узлом, на
## `ped_side` от его оси. Поворот на +90° от направления рукава — правая
## сторона (та же правая тройка, что у `_edge_mid_frame`: на восток идёшь —
## юг справа), поэтому лента с этой стороны приходит сюда без разворота.
##
## Точки ДВЕ, а не одна: единственный угол на оси улицы (как требовало бы
## буквальное «по одному углу на пару соседних подходов») лежал бы на
## продолжении оси, и обе ленты к нему резали бы полотно наискось — см.
## `_corner_pos`. Пара соединяется обводом торца (`_build_dead_end_caps`).
func _dead_end_kerb_pos(node: int, right: bool) -> Vector3:
	var c := _graph.node_position(node)
	var a := _graph.approach_angle(node, 0) + (PI * 0.5 if right else -PI * 0.5)
	return c + Vector3(cos(a), 0.0, sin(a)) * ped_side


## Кербовая точка кольца: тротуар идёт по окружности `radius + ped_side`
## снаружи аннулюса, а точки перехода через рукав отстоят от его оси на
## `ped_side` — то есть на угол `asin(ped_side / R)` от оси рукава.
##
## Хорда такого перехода отстоит от центра кольца на
## `sqrt(ring² - ped_side²)`, где `ring = radius + ped_side`. Это ВСЕГДА
## больше `radius` (раскрывается в `2 * radius * ped_side > 0`), то есть
## пешеход пересекает РУКАВ, а не сам аннулюс.
func _ring_kerb_pos(node: int, k: int, right: bool) -> Vector3:
	var c := _graph.node_position(node)
	var ring := _graph.node_radius(node) + ped_side
	var delta := _ring_delta(node)
	var a := _graph.approach_angle(node, k) + (delta if right else -delta)
	return c + Vector3(cos(a), 0.0, sin(a)) * ring


## Угловое смещение кербовой точки от оси рукава. Зовётся только для колец,
## у которых радиус строго положителен (`_is_ring`), — деления на ноль нет.
func _ring_delta(node: int) -> float:
	return asin(clampf(ped_side / (_graph.node_radius(node) + ped_side), 0.0, 1.0))


func _is_ring(node: int) -> bool:
	return _graph.node_kind(node) == CityGraph.NodeKind.ROUNDABOUT \
		and _graph.node_radius(node) > 0.0


## Ленты тротуара — по одной с каждой стороны ребра, вдоль его полилинии.
## Высота (уклон, дека моста) приходит из полилинии сама.
func _build_ribbons() -> void:
	var m := _graph.edge_count()
	_edge_mid.resize(m)
	_edge_mid.fill(-1)
	_approach_a.resize(m)
	_approach_a.fill(-1)
	_approach_b.resize(m)
	_approach_b.fill(-1)
	for node in _graph.node_count():
		for k in _graph.node_degree(node):
			var e := _graph.approach_edge(node, k)
			if _graph.edge_ends(e).x == node and _approach_a[e] < 0:
				_approach_a[e] = k
			else:
				_approach_b[e] = k

	_mid_first = _positions.size()
	for e in m:
		if _graph.edge_kind(e) == CityGraph.EdgeKind.TUNNEL:
			continue
		var ends := _graph.edge_ends(e)
		if ends.x == ends.y or _approach_a[e] < 0 or _approach_b[e] < 0:
			continue
		var frame := _edge_mid_frame(e)
		if frame.size() < 2:
			continue
		_edge_mid[e] = _positions.size()
		var left := _add_node(frame[0])
		var right := _add_node(frame[1])
		# Правая сторона направления a -> b — это левая сторона направления
		# b -> a, поэтому у дальнего конца сторона переворачивается.
		_link(kerb_node(ends.x, _approach_a[e], false), left, Edge.WALK)
		_link(left, kerb_node(ends.y, _approach_b[e], true), Edge.WALK)
		_link(kerb_node(ends.x, _approach_a[e], true), right, Edge.WALK)
		_link(right, kerb_node(ends.y, _approach_b[e], false), Edge.WALK)
	_mid_count = _positions.size() - _mid_first


## Середина ленты по обе стороны ребра: точка на половине ДЛИНЫ полилинии,
## смещённая на `ped_side` по нормали. Возвращает [левая, правая] или пустой
## массив, если у ребра нет ни одного невырожденного в плане сегмента.
func _edge_mid_frame(e: int) -> PackedVector3Array:
	var count := _graph.edge_point_count(e)
	var target := _graph.edge_length(e) * 0.5
	var acc := 0.0
	for i in count - 1:
		var p0 := _graph.edge_point(e, i)
		var p1 := _graph.edge_point(e, i + 1)
		var seg := p0.distance_to(p1)
		var dx := p1.x - p0.x
		var dz := p1.z - p0.z
		var flat := sqrt(dx * dx + dz * dz)
		if seg <= 0.0 or flat <= 1e-6:
			continue
		if acc + seg < target and i < count - 2:
			acc += seg
			continue
		var p := p0.lerp(p1, clampf((target - acc) / seg, 0.0, 1.0))
		# Правая нормаль к направлению (dx, dz) в плоскости (x, z) — та же
		# правая тройка, что у `CityGraph.hit_side`: на восток едешь, юг
		# справа.
		var nrm := Vector3(-dz / flat, 0.0, dx / flat) * ped_side
		return PackedVector3Array([p - nrm, p + nrm])
	return PackedVector3Array()


## Переходы: по одному на подход узла, между углами по обе стороны рукава.
func _build_crossings() -> void:
	crossings.clear()
	for node in _graph.node_count():
		var d := _graph.node_degree(node)
		if d < 2:
			continue
		if d == 2 and not _is_ring(node) and not _is_straight(node):
			continue
		for k in d:
			var l := kerb_node(node, k, false)
			var r := kerb_node(node, k, true)
			if l == r or _edge_kind.has(edge_key(l, r)):
				# У прямого прохода насквозь оба подхода дают ОДИН и тот же
				# переход поперёк улицы — второй раз его заводить нечем.
				continue
			var gate := gate_id(node, k) if is_regulated(node) else -1
			_link(l, r, Edge.CROSS, gate)
			var a_pos := _positions[l]
			var b_pos := _positions[r]
			crossings.append({
				"a": l, "b": r, "gate": gate,
				"node": node, "approach": k,
				"center": (a_pos + b_pos) * 0.5,
				# Зебра рисуется полосами ВДОЛЬ хода пешехода; поворот вокруг
				# Y переводит +X в (cos, -sin), отсюда знак.
				"yaw": -atan2(b_pos.z - a_pos.z, b_pos.x - a_pos.x),
			})


## Идёт ли улица через узел степени 2 насквозь (излом, а не поворот).
func _is_straight(node: int) -> bool:
	var gap := fposmod(_graph.approach_angle(node, 1)
		- _graph.approach_angle(node, 0), TAU)
	return absf(gap - PI) <= STRAIGHT_TOL


## Тротуар вокруг кольца: дуги между кербовыми точками соседних рукавов.
## Промежуточный узел на дуге нужен не для стоимости, а для геометрии —
## прямая хорда через весь сектор задела бы аннулюс.
func _build_ring_walks() -> void:
	for node in _graph.node_count():
		if not _is_ring(node):
			continue
		var d := _graph.node_degree(node)
		var delta := _ring_delta(node)
		for k in d:
			var from_kerb := kerb_node(node, k, true)
			var to_kerb := kerb_node(node, (k + 1) % d, false)
			if from_kerb == to_kerb:
				continue
			var arm_gap := TAU if d == 1 else fposmod(
				_graph.approach_angle(node, (k + 1) % d)
				- _graph.approach_angle(node, k), TAU)
			if arm_gap <= delta * 2.0:
				# Рукава сошлись теснее, чем ширина двух переходов: дуги между
				# ними нет, кербовые точки смыкаются напрямую.
				_link(from_kerb, to_kerb, Edge.WALK)
				continue
			var ring := _graph.node_radius(node) + ped_side
			var mid_ang := _graph.approach_angle(node, k) + delta \
				+ (arm_gap - delta * 2.0) * 0.5
			var mid := _add_node(_graph.node_position(node)
				+ Vector3(cos(mid_ang), 0.0, sin(mid_ang)) * ring)
			_link(from_kerb, mid, Edge.WALK)
			_link(mid, to_kerb, Edge.WALK)


## Обвод торца тупиковой улицы: ломаная по дуге радиуса `ped_side` вокруг
## узла, от левой кербовой точки за торец к правой. Это единственный законный
## способ перейти тупиковую улицу — перехода (`Edge.CROSS`) у степени 1 нет.
##
## Прямая хорда между кербовыми точками не годится: она прошла бы через сам
## узел, то есть через торец полотна. У дуги же каждая точка отстоит от узла
## ровно на `ped_side`, а для всего, что позади торца, узел и есть ближайшая
## точка полилинии — значит весь обвод снаружи полотна.
func _build_dead_end_caps() -> void:
	for node in _graph.node_count():
		if _is_ring(node) or _graph.node_degree(node) != 1:
			continue
		var c := _graph.node_position(node)
		var a0 := _graph.approach_angle(node, 0)
		var steps := _dead_end_cap_steps(node)
		var prev := kerb_node(node, 0, false)
		for s in range(1, steps + 1):
			# От левой кербовой точки (a0 - PI/2) назад через торец: на
			# последнем шаге угол приходит ровно в правую (a0 + PI/2).
			var ang := a0 - PI * 0.5 - PI * float(s) / float(steps)
			var next := kerb_node(node, 0, true) if s == steps \
				else _add_node(c + Vector3(cos(ang), 0.0, sin(ang)) * ped_side)
			_link(prev, next, Edge.WALK)
			prev = next


## Сколько звеньев нужно обводу торца, чтобы каждая хорда прошла снаружи
## полотна: хорда, стягивающая угол `phi`, отстоит от узла на
## `ped_side * cos(phi / 2)`, и это обязано быть больше полуширины полотна.
## Отсюда `phi < 2 * acos(half / ped_side)`, а всего обвод покрывает PI.
func _dead_end_cap_steps(node: int) -> int:
	var half := _graph.edge_width(_graph.approach_edge(node, 0)) * 0.5 \
		* DEAD_END_CLEARANCE
	if half >= ped_side:
		return DEAD_END_CAP_MAX
	return clampi(ceili(PI / (2.0 * acos(half / ped_side))), 1, DEAD_END_CAP_MAX)


## Переход в неположенном месте — посреди ленты, между её серединными узлами.
func _build_jwalks() -> void:
	var rng := SeededRng.new(JWALK_SEED)
	for e in _graph.edge_count():
		var m := _edge_mid[e]
		if m < 0:
			continue
		if rng.chance(JWALK_CHANCE):
			_link(m, m + 1, Edge.JWALK)


func _build_hash() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in _positions.size():
		var p := _positions[i]
		_hash.add_point(p.x, p.z, 0.0)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	if not _positions.is_empty():
		_span = lo.distance_to(hi) + HASH_CELL
		_center = (lo + hi) * 0.5


func _add_node(pos: Vector3) -> int:
	var id := _positions.size()
	_positions.append(pos)
	legal.add_point(id, pos)
	full.add_point(id, pos)
	return id


func _link(a: int, b: int, kind: Edge, gate: int = -1) -> void:
	if a == b:
		return
	var key := edge_key(a, b)
	if _edge_kind.has(key):
		return
	var length := _positions[a].distance_to(_positions[b])
	var cost := length * WALK_COST_PER_M
	if kind == Edge.CROSS:
		cost = COST_CROSS
	elif kind == Edge.JWALK:
		cost = COST_JWALK
	_edge_kind[key] = int(kind)
	_edge_cost[key] = cost
	if gate >= 0:
		_edge_gate[key] = gate
	if length > 1e-6:
		_h_scale = minf(_h_scale, cost / length)
	if kind != Edge.JWALK:
		legal.connect_points(a, b)
	full.connect_points(a, b)


# --- Адресация узлов --------------------------------------------------------

## Угол тротуара между подходами k и k+1 узла графа улиц.
func corner_node(node: int, k: int) -> int:
	return _corner_first[node] + k


## Кербовый узел тротуара у подхода k со стороны `right` (правая сторона
## направления ОТ узла). У перекрёстка стороны соседних рукавов — это ОДИН
## общий угол; у кольца и у тупика — две отдельные точки на рукав (общего
## угла нет: у кольца между рукавами аннулюс, у тупика соседнего подхода
## не существует).
func kerb_node(node: int, k: int, right: bool) -> int:
	var d := _graph.node_degree(node)
	if _is_ring(node) or d == 1:
		return _corner_first[node] + k * 2 + (1 if right else 0)
	return _corner_first[node] + (k if right else (k - 1 + d) % d)


## Концы перехода через рукав k: (левый угол, правый угол).
func crossing_ends(node: int, k: int) -> Vector2i:
	return Vector2i(kerb_node(node, k, false), kerb_node(node, k, true))


## Серединный узел ленты ребра со стороны `right` направления a -> b.
## -1, если ленты нет (тоннель, вырожденное ребро).
func mid_node(edge: int, right: bool) -> int:
	var m := _edge_mid[edge]
	return -1 if m < 0 else m + (1 if right else 0)


## Диапазон серединных узлов лент: из него берётся «случайная цель посреди
## квартала» (`PedManager._pick_random_node`) — угловой узел стоит у самого
## перекрёстка, и стоять там без дела пешеходу незачем.
func mid_first() -> int:
	return _mid_first


func mid_count() -> int:
	return _mid_count


func node_count() -> int:
	return _positions.size()


# --- Запросы ----------------------------------------------------------------

func position_of(id: int) -> Vector3:
	return _positions[id]


func edge_kind(a: int, b: int) -> int:
	return _edge_kind.get(edge_key(a, b), -1)


func edge_cost(a: int, b: int) -> float:
	return _edge_cost.get(edge_key(a, b), 1.0)


## Гейт светофора для ребра, или -1 если сигнал не нужен.
func edge_gate(a: int, b: int) -> int:
	return _edge_gate.get(edge_key(a, b), -1)


## Нерегулируемый переход: разметка есть, светофора нет.
func is_unsignalized_crossing(a: int, b: int) -> bool:
	return edge_kind(a, b) == int(Edge.CROSS) and edge_gate(a, b) < 0


## Регулируется ли узел графа улиц светофором. Прямая проверка по списку
## регулируемых узлов из топологии (этап 7) — не чётность индексов сетки.
func is_regulated(node: int) -> bool:
	return node >= 0 and node < _regulated.size() and _regulated[node] == 1


## Заниженная оценка стоимости пути в единицах стоимости рёбер.
##
## Множитель — МИНИМАЛЬНАЯ цена метра по всем рёбрам графа, посчитанная при
## построении. Отсюда допустимость в одну строку: цена любого пути равна сумме
## цен рёбер, каждая не меньше (длина ребра * множитель), сумма длин не меньше
## прямого расстояния — значит оценка не больше настоящей цены, и AStar3D
## сохраняет оптимальность. Она же и КОНСИСТЕНТНА: оценка меняется между
## соседями не быстрее, чем на цену ребра между ними.
##
## Фиксированный делитель прежней сеточной версии (0.5 / 32, откалиброванный
## под сегмент 48 м) на настоящем графе не годится: там рядом стоят рукав
## кольца в 20 м и проспект в 200 м, и делитель, честный для одного, врёт для
## другого. На сетке новый множитель равен 1/48 против прежнего 1/64 — та же
## допустимость, но оценка полуторакратно информативнее, то есть A* быстрее.
func heuristic(from_id: int, to_id: int) -> float:
	return _positions[from_id].distance_to(_positions[to_id]) * _h_scale


# --- Мост к осевому светофору (умирает на этапе 9) --------------------------

## Гейт в адресации осевого `TrafficLightController`: (индекс оси
## перекрёстка, `CrossAxis` пересекаемой дороги).
##
## Живой город до этапа 9 красит линзы и считает фазы осевым контроллером, а
## гейт пешехода с этого этапа адресует (узел, подход). Перевод одной модели
## в другую живёт здесь, потому что здесь же лежит и знание о сеточном
## происхождении графа (`axes`). На этапе 9 метод уходит вместе с осевым
## контроллером: `NodeSignalController` принимает (узел, подход) напрямую.
func gate_axial(gate: int) -> Vector2i:
	var node := gate_node(gate)
	# Рукав вдоль ±Z означает дорогу, по которой машины едут вдоль Z.
	var ang := _graph.approach_angle(node, gate_approach(gate))
	var axis := CrossAxis.Z_ROAD if absf(sin(ang)) >= absf(cos(ang)) \
		else CrossAxis.X_ROAD
	return Vector2i(_axis_index(_graph.node_position(node).x), int(axis))


func _axis_index(v: float) -> int:
	var best := 0
	var best_d := INF
	for i in axes.size():
		var d := absf(axes[i] - v)
		if d < best_d:
			best_d = d
			best = i
	return best


# --- Поиск узлов ------------------------------------------------------------

## Ближайший узел тротуара. Расширяющийся поиск по пространственному хешу —
## тот же приём, что у `CityGraph.nearest_node()`: сеточной арифметики
## индексов, которой это делалось раньше, у произвольного графа нет.
func nearest_node(x: float, z: float) -> int:
	if _positions.is_empty():
		return -1
	var limit := _span + Vector2(x, z).distance_to(_center)
	var r := HASH_CELL
	while r < limit:
		var d := _scan(x, z, r)
		if d < INF:
			# Узел мог найтись у самой кромки круга — круг радиусом d
			# гарантированно покрывает всех, кто ближе.
			if d > r:
				_scan(x, z, d)
			return _near_best
		r *= 2.0
	_scan(x, z, limit)
	return _near_best


## Минимальное расстояние среди просмотренных узлов (INF, если в радиусе нет
## ни одного); выбранный узел остаётся в `_near_best`.
func _scan(x: float, z: float, radius: float) -> float:
	_near_best = -1
	var best := INF
	for i in _hash.query_circle(x, z, radius):
		var p := _positions[i]
		var dx := x - p.x
		var dz := z - p.z
		var d := sqrt(dx * dx + dz * dz)
		if d < best:
			best = d
			_near_best = i
	return best


# --- Маршруты ---------------------------------------------------------------

func find_path(from_id: int, to_id: int, allow_jwalk: bool) -> PackedInt64Array:
	var g := full if allow_jwalk else legal
	return g.get_id_path(from_id, to_id)


## Маршрут для агента: геометрия и параллельный массив светофорных гейтов.
##
## gates[i] — гейт, который надо пройти на зелёный, чтобы попасть В points[i];
## -1 означает свободный участок тротуара.
func build_route(from_pos: Vector3, to_id: int, allow_jwalk: bool) -> Dictionary:
	var from_id := nearest_node(from_pos.x, from_pos.z)
	var ids := find_path(from_id, to_id, allow_jwalk)
	var points := PackedVector3Array()
	var gates := PackedInt32Array()
	var nodes := PackedInt32Array()
	if ids.is_empty():
		return {"points": points, "gates": gates, "node_ids": nodes}

	# Все три массива строго параллельны, включая синтетическую стартовую
	# точку: агенту нужно уметь по индексу шага достать и гейт, и узел.
	# Узел -1 означает «точка не из графа» (текущее положение агента).
	if _positions[ids[0]].distance_to(from_pos) >= 0.2:
		points.append(from_pos)
		gates.append(-1)
		nodes.append(-1)
	for k in ids.size():
		points.append(_positions[ids[k]])
		gates.append(edge_gate(ids[k - 1], ids[k]) if k > 0 else -1)
		nodes.append(ids[k])
	return {"points": points, "gates": gates, "node_ids": nodes}


# --- POI --------------------------------------------------------------------

## Привязка точек интереса к тротуарным узлам. Точки дальше POI_MAX_DIST
## отбрасываются: иначе ориентиры вне сетки (канатка, беседка и башня на
## Машуке) притягиваются к южному краю города и искажают выбор цели.
func set_pois(points: PackedVector2Array, tags: PackedStringArray) -> void:
	poi_nodes = PackedInt32Array()
	poi_tags = PackedStringArray()
	for k in points.size():
		var p := points[k]
		var id := nearest_node(p.x, p.y)
		if id < 0:
			continue
		var n := _positions[id]
		if Vector2(n.x - p.x, n.z - p.y).length() > POI_MAX_DIST:
			continue
		poi_nodes.append(id)
		poi_tags.append(tags[k] if k < tags.size() else "")
