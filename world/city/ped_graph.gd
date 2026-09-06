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

## Половина угла между соседними рукавами, ниже/выше которой один общий угол
## тротуара сектору уже не годится, рад. 0.4 (23°) — та же по смыслу отсечка,
## что `RoadMesh.TRIM_EDGE_FRACTION` у мешера.
##
## Граница РАЗВЕТВЛЯЕТ построение, а не зажимает его (см. `_corner_pos`):
## сектор острее `2 * MIN_CORNER_HALF` получает честный митр, сектор шире
## `TAU - 2 * MIN_CORNER_HALF` — две кербовые точки с обводом. Прежний
## `clampf(gap * 0.5, MIN_CORNER_HALF, PI - MIN_CORNER_HALF)` в обеих этих
## ветках выдавал КОНЕЧНОЕ расстояние вместо верного и уводил угол внутрь
## полотна одного из рукавов — 9 из 20 нарушений инварианта на живой
## топологии Пятигорска.
const MIN_CORNER_HALF := 0.4

## Ниже этого |sin| угла сектора кромки двух рукавов считаются параллельными
## и точки пересечения у них нет. Та же граница, что `RoadMesh.PARALLEL_SIN`:
## 0.05 — это 2.9°, дальше формула пересечения теряет точность быстрее, чем
## растёт польза от неё.
const PARALLEL_SIN := 0.05

## Запас обвода над полушириной полотна. Хорда обвода обязана пройти СНАРУЖИ
## полотна; 5 % — чтобы она проходила с зазором, а не легла на кромку впритык,
## где всё решает погрешность acos/cos.
const DEAD_END_CLEARANCE := 1.05
## Потолок числа звеньев обвода. На 8 звеньях хорда отходит от узла на
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

## Косинус, ниже которого стык двух сегментов полилинии считается ИЗЛОМОМ и
## получает собственную станцию ленты. 0.999 — это 2.6°; хорда, срезающая такой
## излом, отходит от оси на `side * (1 - cos(1.3°))` = 2 мм при выносе 8 м,
## против запаса тротуара над кромкой полотна в 2 м. Порог нужен потому, что
## уплотнение полилинии рельефом даёт коллинеарные точки, чьи нормали
## расходятся лишь на шум float32.
const RIBBON_BEND_COS := 0.999

## Потолок числа итераций выноса серединного узла ленты (`_push_out`). Шаг
## закрывает недостачу с множителем `cos(излома)`: на изломе в 60° это половина
## за шаг, и восьми шагов хватает с запасом в 250 раз.
const MID_PUSH_STEPS := 8
## Допуск сходимости выноса серединного узла, м. Сантиметр: в 200 раз меньше
## запаса тротуара над кромкой полотна (`walk_width / 2` = 2 м) и заведомо
## больше погрешности float32 на координатах в сотни метров.
const MID_PUSH_EPS := 0.01

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

# --- Мост к сеточной модели -------------------------------------------------
## Осей дорог в сеточном городе. Живой город с этапа 9 работает на настоящей
## топологии и сюда не заглядывает; константа и `is_signalized()` ниже
## остались поставщиком синтетической сетки для `CityGraphGrid`, на которой
## стоят юнит-тесты трафика, пешеходов и полиции.
const AXES := 9

## Ширина тротуара, м (`CityField.sidewalk`). Вынос тротуарной точки от оси
## улицы считается ОТ НЕЁ и полуширины конкретного ребра, а не одной
## константой на весь город: топология хранит ширину per-edge (переулок 8 м,
## проспект Кирова 18 м), и общая константа 8 м провела бы ленту тротуара
## Кирова на метр ВНУТРИ полотна — нарушение инварианта по всей длине
## проспекта, а не в крайнем случае.
var walk_width := 4.0
## Вынос тротуарной точки для каждого ребра графа улиц, м.
var _side: PackedFloat32Array = PackedFloat32Array()

## Граф без jwalk — для законопослушных пешеходов.
var legal: PedAStar
## Граф со всеми рёбрами — для нарушителей.
var full: PedAStar

## Переходы как данные: из этого списка рисуются зебры, стойки и линзы —
## разметка не может разъехаться с логикой.
##
## [b]Связь с разметкой (этап 9).[/b] `RoadMarkings` берёт отсюда ТОЛЬКО
## множество переходов — пару (`node`, `approach`), — а геометрию зебры
## (вынос от горловины узла, ширину, поворот полос) считает сам по `RoadMesh`.
## Так и расходятся две записи: здесь `center` — середина отрезка между
## кербовыми точками (там, где пешеход реально ступает), а `yaw` —
## `-atan2(dz, dx)` направления ХОДА пешехода; разметке же нужен центр,
## отодвинутый от кромки перекрёстка на `ZEBRA_SETBACK`, и поворот полос
## ВДОЛЬ движения машин. Сводить эти числа не нужно и вредно: у них разный
## смысл, общая у них только адресация (узел, подход).
var crossings: Array[Dictionary] = []

var poi_nodes: PackedInt32Array = PackedInt32Array()
var poi_tags: PackedStringArray = PackedStringArray()

var _graph: CityGraph
var _positions: PackedVector3Array = PackedVector3Array()
var _edge_kind: Dictionary[int, int] = {}
var _edge_cost: Dictionary[int, float] = {}
var _edge_gate: Dictionary[int, int] = {}
## Ребро графа УЛИЦ, которое пересекает пешеходное ребро (зебра или jwalk).
## Им трафик и пешеход говорят об одной и той же дороге по id, а не по
## совпадению координат: ребро моста и ребро улицы под ним разные по
## построению, и сравнение по id никогда их не спутает.
var _edge_road: Dictionary[int, int] = {}

## Первый угловой (кербовый) узел тротуара для узла графа улиц; сами углы
## лежат подряд, поэтому таблица нужна одна.
var _corner_first: PackedInt32Array = PackedInt32Array()
## Вторая кербовая точка развёрнутого сектора: `gate_id(узел, k)` -> узел,
## обслуживающий ЛЕВУЮ сторону подхода k+1. Таблица, а не место в общей
## нумерации углов: основные углы обязаны лежать подряд по номеру подхода
## (`corner_node`), а вторые точки есть далеко не у каждого сектора.
var _split_corner: Dictionary[int, int] = {}
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
	_setup(CityGraphGrid.from_field(field),
		CityGraphGrid.signalized_nodes(field), field.sidewalk)


## Пешеходный граф поверх произвольного графа улиц: настоящая топология
## (этап 9), синтетические полигоны тестов.
## `sidewalk` — ширина тротуара, м; вынос считается per-edge из неё и ширины
## самого ребра (см. `side_of_edge`).
static func on_graph(graph: CityGraph, signal_nodes: PackedInt32Array,
		sidewalk: float) -> PedGraph:
	var g := PedGraph.new()
	g._setup(graph, signal_nodes, sidewalk)
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
## (`signalized_nodes()`), то есть ради синтетической сетки юнит-тестов. Сам
## PedGraph её не зовёт: регулируемость узла он спрашивает у
## `is_regulated(node_id)` по списку из топологии.
static func is_signalized(i: int, j: int) -> bool:
	return i % 2 == 1 and j % 2 == 1 and i < AXES - 1 and j < AXES - 1


# --- Построение -------------------------------------------------------------

func _setup(graph: CityGraph, signal_nodes: PackedInt32Array,
		sidewalk: float) -> void:
	_graph = graph
	walk_width = sidewalk
	_build_sides()
	_build_regulated(signal_nodes)
	_build_corners()
	_build_ribbons()
	_build_crossings()
	_build_ring_walks()
	_build_dead_end_caps()
	_build_sharp_wraps()
	_build_jwalks()
	_build_hash()
	if is_inf(_h_scale):
		_h_scale = 0.0


## Вынос тротуарной точки каждого ребра: полуширина полотна плюс половина
## тротуара. Из построения следует главное свойство, на которое опирается весь
## класс: вынос СТРОГО больше полуширины ровно на `walk_width / 2` — тротуарная
## точка всегда снаружи полотна своего ребра, какой бы ширины оно ни было.
func _build_sides() -> void:
	_side.resize(_graph.edge_count())
	for e in _graph.edge_count():
		_side[e] = _graph.edge_width(e) * 0.5 + walk_width * 0.5


## Вынос тротуарной точки от оси ребра, м.
func side_of_edge(edge: int) -> float:
	return _side[edge]


## Вынос для подхода `k` узла `n` — тот же, что у ребра этого подхода.
func _side_of_approach(node: int, k: int) -> float:
	return _side[_graph.approach_edge(node, k)]


## Самый большой вынос среди подходов узла. Им задаётся радиус тротуара
## вокруг кольца и вынос УГЛА, общего у двух соседних подходов: угол обязан
## лежать снаружи полотна обоих, значит считается по более широкому.
func _side_of_node(node: int) -> float:
	var widest := 0.0
	for k in _graph.node_degree(node):
		widest = maxf(widest, _side_of_approach(node, k))
	return widest


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
## (см. `_ring_kerb_pos`), у тупика (см. `_dead_end_kerb_pos`) и у
## развёрнутого сектора (см. `_reflex_kerb_pos`) — по две кербовые точки.
func _build_corners() -> void:
	var n := _graph.node_count()
	_corner_first.resize(n)
	_split_corner.clear()
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
			# Вторые точки развёрнутых секторов лежат ПОСЛЕ основных углов
			# узла: основные адресуются арифметикой `corner_node()` и обязаны
			# идти подряд по номеру подхода.
			for k in d:
				if _is_reflex_sector(node, k):
					_split_corner[gate_id(node, k)] = _add_node(
						_reflex_kerb_pos(node, k, false))


## Сектор между подходами k и k+1, рад. Подходы упорядочены по возрастанию
## угла, поэтому положительный остаток и есть сектор между ними; на
## замыкающей паре он же даёт остаток круга.
func _sector_gap(node: int, k: int) -> float:
	var d := _graph.node_degree(node)
	return fposmod(_graph.approach_angle(node, (k + 1) % d)
		- _graph.approach_angle(node, k), TAU)


## Острый сектор: два рукава расходятся настолько мало, что общий угол уходит
## от узла дальше `2.57 * ped_side` (`1 / sin(MIN_CORNER_HALF)`).
func _is_sharp_sector(node: int, k: int) -> bool:
	return _sector_gap(node, k) < 2.0 * MIN_CORNER_HALF


## Развёрнутый сектор: рукава сошлись шпилькой, и СНАРУЖИ излома одной точки
## недостаточно — эквидистанта там содержит дугу (см. `_reflex_kerb_pos`).
func _is_reflex_sector(node: int, k: int) -> bool:
	if _is_ring(node) or _graph.node_degree(node) < 2:
		return false
	return _sector_gap(node, k) > TAU - 2.0 * MIN_CORNER_HALF


## Кербовая точка, обслуживающая ПРАВУЮ сторону подхода k, — она же общий
## угол сектора (k, k+1), если сектор допускает общую точку.
##
## Форма угла определяется шириной сектора, и это ровно три случая
## эквидистанты (кривой, всюду отстоящей от полотна на вынос тротуара):
##
## 1. [b]Обычный сектор[/b] (46° <= gap <= 314°). Эквидистанта — две прямые,
##    пересекающиеся на биссектрисе на расстоянии `side / sin(gap / 2)`: при
##    90° это привычные (±8, ±8) сетки, при развёрнутых 180° (проход
##    насквозь) — ровно `side` вбок. `side` берётся по САМОМУ ШИРОКОМУ рукаву
##    УЗЛА, а не двух рукавов сектора: полилиния каждого рукава проходит
##    ЧЕРЕЗ узел, поэтому угол, стоящий к узлу ближе полуполотна третьего,
##    самого широкого рукава, лежит в его полотне. Так угол между двумя
##    пригородными проездами у `kal_s3` заходил на 1.8 м в улицу Калинина.
##
## 2. [b]Острый сектор[/b] (gap < 46°, `_miter_pos`). Эквидистанта — те же две
##    прямые, но точка их пересечения уходит далеко, и биссектриса с общим
##    `side` даёт не её. Здесь считается ЧЕСТНОЕ пересечение — у каждого
##    рукава свой вынос.
##
## 3. [b]Развёрнутый сектор[/b] (gap > 314°, `_reflex_kerb_pos`). Эквидистанта
##    снаружи выпуклого излома содержит ДУГУ, а не точку: одна точка ушла бы
##    от узла на `side / sin(gap / 2)` -> бесконечность при gap -> 360°.
##    Сектор получает две кербовые точки и обвод между ними
##    (`_build_sharp_wraps`) — тот же приём, что у торца тупика, частный
##    случай которого сектор в полный круг и есть.
##
## [b]Что отсюда следует.[/b] Конструкция доказывает свойство ТОЧЕК, а главный
## инвариант ПДД — свойство ОТРЕЗКОВ между ними. Второе вытекает из первого
## потому, что каждая кербовая точка отстоит от оси СВОЕГО рукава ровно на его
## вынос: лента идёт от неё вдоль этого же рукава, оба её конца на выносе,
## значит и вся она снаружи полотна. Единственное исключение — степень 1: пары
## соседних подходов нет вовсе, и тупик обслуживает не эта функция, а
## `_dead_end_kerb_pos` плюс обвод торца (`_build_dead_end_caps`).
func _corner_pos(node: int, k: int) -> Vector3:
	if _is_sharp_sector(node, k):
		return _miter_pos(node, k)
	if _is_reflex_sector(node, k):
		return _reflex_kerb_pos(node, k, true)
	var gap := _sector_gap(node, k)
	var ang := _graph.approach_angle(node, k) + gap * 0.5
	# Ветка зовётся только при 2 * MIN_CORNER_HALF <= gap <= TAU - 2 *
	# MIN_CORNER_HALF, поэтому sin(gap / 2) >= sin(MIN_CORNER_HALF) — деления
	# на ноль нет и зажимать нечего.
	return _graph.node_position(node) \
		+ Vector3(cos(ang), 0.0, sin(ang)) * (_side_of_node(node) / sin(gap * 0.5))


## Честное пересечение внешних кромок тротуара двух рукавов острого сектора:
## точка на расстоянии `side_k` от оси рукава k И `side_{k+1}` от оси рукава
## k+1. Та же формула, что `RoadMesh._pair_corner`, которой мешер уже режет
## ВИДИМЫЙ тротуар на тех же развилках, — и без потолка по той же причине:
## тротуар, заехавший на полотно, это ступенька поперёк дороги.
##
## Вывод: точка на угле t от рукава k и радиусе r даёт `r * sin(t) = side_k` и
## `r * sin(gap - t) = side_{k+1}`; раскрытие второго синуса превращает пару в
## `r * cos(t) = (side_{k+1} + side_k * cos(gap)) / sin(gap)` — это и есть
## вынос ВДОЛЬ рукава k, а `side_k` — поперёк.
##
## На живой топологии Пятигорска шесть таких секторов, вынос выходит 23-35 м
## (проспект Кирова x2, Калинина, Октябрьская, Крайнего, Козлова) — не дальше
## прежнего зажатого (20-28 м) настолько, чтобы «угол» перестал быть углом.
func _miter_pos(node: int, k: int) -> Vector3:
	var d := _graph.node_degree(node)
	var gap := _sector_gap(node, k)
	var s := sin(gap)
	assert(s > PARALLEL_SIN, "PedGraph: узел %d, сектор %d — рукава расходятся на %.2f°, кромки тротуара параллельны и общего угла у них нет" % [node, k, rad_to_deg(gap)])
	var side := _side_of_approach(node, k)
	var along := (_side_of_approach(node, (k + 1) % d) + side * cos(gap)) / s
	var a := _graph.approach_angle(node, k)
	return _graph.node_position(node) \
		+ Vector3(cos(a), 0.0, sin(a)) * along \
		+ Vector3(-sin(a), 0.0, cos(a)) * side


## Кербовая точка развёрнутого сектора (k, k+1) со стороны рукава k
## (`first`) или рукава k+1: на окружности выноса узла, отклонённая от оси
## своего рукава на `asin(вынос рукава / радиус)`. Ровно та же конструкция,
## что кербовая точка кольца (`_ring_kerb_pos`), и по той же причине: точка на
## окружности радиуса `r` под углом `delta` к оси рукава отстоит от этой оси
## на `r * sin(delta)`, то есть ровно на вынос рукава.
##
## Радиус — самый широкий вынос УЗЛА: обвод проходит рядом с узлом, через
## который идут полилинии ВСЕХ рукавов.
func _reflex_kerb_pos(node: int, k: int, first: bool) -> Vector3:
	var d := _graph.node_degree(node)
	var arm := k if first else (k + 1) % d
	var delta := _reflex_delta(node, arm)
	var a := _graph.approach_angle(node, arm) + (delta if first else -delta)
	return _graph.node_position(node) \
		+ Vector3(cos(a), 0.0, sin(a)) * _side_of_node(node)


## Угловое смещение кербовой точки обвода от оси её рукава.
func _reflex_delta(node: int, arm: int) -> float:
	return asin(clampf(_side_of_approach(node, arm) / _side_of_node(node),
		0.0, 1.0))


## Кербовая точка тупика: сбоку от единственного рукава, вровень с узлом, на
## вынос этого рукава от его оси. Поворот на +90° от направления рукава — правая
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
	return c + Vector3(cos(a), 0.0, sin(a)) * _side_of_approach(node, 0)


## Кербовая точка кольца: тротуар идёт по окружности `radius + side_max`
## снаружи аннулюса (`side_max` — самый большой вынос среди рукавов, чтобы
## окружность была снаружи полотна ВСЕХ), а точка перехода через рукав k
## отстоит от его оси ровно на вынос этого рукава — то есть на угол
## `asin(side_k / ring)` от его оси.
##
## Хорда такого перехода отстоит от центра кольца на `sqrt(ring² - side_k²)`,
## где `ring = radius + side_max >= radius + side_k`. Это ВСЕГДА больше
## `radius` (при side_max = side_k раскрывается в `2 * radius * side_k > 0`,
## при большем — тем более), то есть пешеход пересекает РУКАВ, а не аннулюс.
func _ring_kerb_pos(node: int, k: int, right: bool) -> Vector3:
	var c := _graph.node_position(node)
	var ring := _ring_radius(node)
	var delta := _ring_delta(node, k)
	var a := _graph.approach_angle(node, k) + (delta if right else -delta)
	return c + Vector3(cos(a), 0.0, sin(a)) * ring


## Радиус тротуарной окружности кольца.
func _ring_radius(node: int) -> float:
	return _graph.node_radius(node) + _side_of_node(node)


## Угловое смещение кербовой точки рукава k от его оси. Зовётся только для
## колец, у которых радиус строго положителен (`_is_ring`), — деления на ноль
## нет.
func _ring_delta(node: int, k: int) -> float:
	return asin(clampf(_side_of_approach(node, k) / _ring_radius(node), 0.0, 1.0))


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
		var frame := _ribbon_frame(e)
		var points: PackedVector3Array = frame["points"]
		if points.is_empty():
			continue
		var normals: PackedVector3Array = frame["normals"]
		var mid_at: int = frame["mid"]
		# Серединные узлы идут ПАРОЙ и первыми: `mid_node()` адресует их
		# арифметикой (левый, правый следом), а станции излома — нет.
		_edge_mid[e] = _positions.size()
		var left := PackedInt32Array()
		var right := PackedInt32Array()
		left.resize(points.size())
		right.resize(points.size())
		left[mid_at] = _add_node(_push_out(e, points[mid_at], -normals[mid_at]))
		right[mid_at] = _add_node(_push_out(e, points[mid_at], normals[mid_at]))
		for s in points.size():
			if s == mid_at:
				continue
			left[s] = _add_node(_push_out(e, points[s], -normals[s]))
			right[s] = _add_node(_push_out(e, points[s], normals[s]))
		# Правая сторона направления a -> b — это левая сторона направления
		# b -> a, поэтому у дальнего конца сторона переворачивается.
		_chain_ribbon(kerb_node(ends.x, _approach_a[e], false), left,
			kerb_node(ends.y, _approach_b[e], true))
		_chain_ribbon(kerb_node(ends.x, _approach_a[e], true), right,
			kerb_node(ends.y, _approach_b[e], false))
	_mid_count = _positions.size() - _mid_first


## Лента одной стороны: угол — станции по порядку — угол дальнего конца.
func _chain_ribbon(from_id: int, ids: PackedInt32Array, to_id: int) -> void:
	var prev := from_id
	for id in ids:
		_link(prev, id, Edge.WALK)
		prev = id
	_link(prev, to_id, Edge.WALK)


## Станции ленты вдоль ребра: `points` в порядке от конца `a` к концу `b`,
## `normals` — правая единичная нормаль в каждой, `mid` — индекс серединной.
## Пустой `points`, если у ребра нет ни одного невырожденного в плане сегмента.
##
## Станций две разновидности, и обе обязательны:
##
##  - [b]середина[/b] ребра (по половине ДЛИНЫ полилинии). Из этого диапазона
##    берётся «случайная цель посреди квартала» (`mid_first`/`mid_count`), и
##    только она адресуется снаружи (`mid_node`);
##  - [b]изломы плана[/b]. Лента обязана повторить изгиб улицы: прямая хорда
##    через излом срезает полотно СНАРУЖИ поворота — так лента бульвара
##    Гагарина проходила в 5.6 м от оси при полуполотне 6 м. Уплотнение
##    полилинии рельефом изломов не создаёт (`_densify` кладёт точки на прямой
##    плана), поэтому на прямой улице станция по-прежнему ровно одна.
func _ribbon_frame(e: int) -> Dictionary:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var mid := 0
	var count := _graph.edge_point_count(e)
	var target := _graph.edge_length(e) * 0.5
	var acc := 0.0
	var mid_done := false
	var prev_n := Vector3.ZERO
	for i in count - 1:
		var p0 := _graph.edge_point(e, i)
		var p1 := _graph.edge_point(e, i + 1)
		var dx := p1.x - p0.x
		var dz := p1.z - p0.z
		var flat := sqrt(dx * dx + dz * dz)
		var seg := p0.distance_to(p1)
		if seg <= 0.0 or flat <= 1e-6:
			continue
		# Правая нормаль к направлению (dx, dz) в плоскости (x, z) — та же
		# правая тройка, что у `CityGraph.hit_side`: на восток едешь, юг
		# справа.
		var n := Vector3(-dz / flat, 0.0, dx / flat)
		# Излом в вершине p0 идёт ПЕРЕД серединой этого сегмента: обе станции
		# кладутся по возрастанию длины вдоль ребра, а вершина стоит в его
		# начале.
		if prev_n != Vector3.ZERO and prev_n.dot(n) < RIBBON_BEND_COS:
			points.append(p0)
			normals.append((prev_n + n).normalized())
		if not mid_done and (acc + seg >= target or i == count - 2):
			mid = points.size()
			points.append(p0.lerp(p1, clampf((target - acc) / seg, 0.0, 1.0)))
			normals.append(n)
			mid_done = true
		acc += seg
		prev_n = n
	return {"points": points, "normals": normals, "mid": mid}


## Точка на выносе ребра от ВСЕЙ его полилинии: от `p` в направлении `dir`.
##
## Простой сдвиг на вынос по нормали своего сегмента годится только на прямой.
## На ВНУТРЕННЕЙ стороне излома параллель одного сегмента подходит к соседнему
## ближе выноса — так серединный узел ленты бульвара Гагарина оказывался в
## 5.24 м от полотна при полуполотне 6 м. Верная точка лежит дальше по той же
## нормали, на кромке параллели соседнего сегмента.
##
## Итерация сходится: каждый шаг закрывает недостачу с множителем `cos(излома)`
## от неё, то есть геометрически. `assert` вместо молчаливого выхода — если
## сходимости нет, излом ребра развёрнут назад, и это дефект полилинии, а не
## тротуара.
func _push_out(e: int, p: Vector3, dir: Vector3) -> Vector3:
	var side := _side[e]
	var out := p + dir * side
	var gap := side - _plan_dist_to_edge(e, out)
	var steps := 0
	while gap > MID_PUSH_EPS and steps < MID_PUSH_STEPS:
		out += dir * gap
		gap = side - _plan_dist_to_edge(e, out)
		steps += 1
	assert(gap <= MID_PUSH_EPS, "PedGraph: ребро %d — серединный узел ленты не удалось вынести из полотна за %d шагов, недостача %.3f м" % [e, MID_PUSH_STEPS, gap])
	return out


## Минимальное расстояние в плане от точки до полилинии ребра, м.
func _plan_dist_to_edge(e: int, p: Vector3) -> float:
	var q := Vector2(p.x, p.z)
	var best := INF
	for i in _graph.edge_point_count(e) - 1:
		var p0 := _graph.edge_point(e, i)
		var p1 := _graph.edge_point(e, i + 1)
		var a := Vector2(p0.x, p0.z)
		var ab := Vector2(p1.x - p0.x, p1.z - p0.z)
		var len2 := ab.length_squared()
		if len2 < 1e-12:
			best = minf(best, q.distance_to(a))
			continue
		best = minf(best,
			q.distance_to(a + ab * clampf((q - a).dot(ab) / len2, 0.0, 1.0)))
	return best


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
			_edge_road[edge_key(l, r)] = _graph.approach_edge(node, k)
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
		for k in d:
			var next := (k + 1) % d
			var from_kerb := kerb_node(node, k, true)
			var to_kerb := kerb_node(node, next, false)
			if from_kerb == to_kerb:
				continue
			# Дугу из сектора вырезают ДВЕ кербовые точки, у каждой свой вынос:
			# на рукаве-переулке она ближе к оси, на проспекте дальше.
			var delta := _ring_delta(node, k)
			var delta_next := _ring_delta(node, next)
			var arm_gap := TAU if d == 1 else fposmod(
				_graph.approach_angle(node, next)
				- _graph.approach_angle(node, k), TAU)
			if arm_gap <= delta + delta_next:
				# Рукава сошлись теснее, чем ширина двух переходов: дуги между
				# ними нет, кербовые точки смыкаются напрямую.
				_link(from_kerb, to_kerb, Edge.WALK)
				continue
			var ring := _ring_radius(node)
			var mid_ang := _graph.approach_angle(node, k) + delta \
				+ (arm_gap - delta - delta_next) * 0.5
			var mid := _add_node(_graph.node_position(node)
				+ Vector3(cos(mid_ang), 0.0, sin(mid_ang)) * ring)
			_link(from_kerb, mid, Edge.WALK)
			_link(mid, to_kerb, Edge.WALK)


## Обвод торца тупиковой улицы: ломаная по дуге радиуса выноса рукава вокруг
## узла, от левой кербовой точки за торец к правой. Это единственный законный
## способ перейти тупиковую улицу — перехода (`Edge.CROSS`) у степени 1 нет.
##
## Прямая хорда между кербовыми точками не годится: она прошла бы через сам
## узел, то есть через торец полотна. У дуги же каждая точка отстоит от узла
## ровно на вынос рукава, а для всего, что позади торца, узел и есть ближайшая
## точка полилинии — значит весь обвод снаружи полотна.
func _build_dead_end_caps() -> void:
	for node in _graph.node_count():
		if _is_ring(node) or _graph.node_degree(node) != 1:
			continue
		# Сектор тупика — полный круг, а обвод покрывает ту его часть, что не
		# закрыта лентами вдоль единственного рукава: PI = TAU - 2 * (PI / 2).
		_wrap(node, kerb_node(node, 0, false), kerb_node(node, 0, true),
			_graph.approach_angle(node, 0) - PI * 0.5, -PI)


## Обвод развёрнутого сектора: та же ломаная по дуге выноса узла, что у торца
## тупика, между двумя кербовыми точками сектора. Тупик — её частный случай:
## там сектор равен полному кругу, здесь — от 314° и шире.
func _build_sharp_wraps() -> void:
	for node in _graph.node_count():
		var d := _graph.node_degree(node)
		for k in d:
			if not _is_reflex_sector(node, k):
				continue
			var next := (k + 1) % d
			var from_ang := _graph.approach_angle(node, k) + _reflex_delta(node, k)
			var sweep := _sector_gap(node, k) - _reflex_delta(node, k) \
				- _reflex_delta(node, next)
			_wrap(node, corner_node(node, k), kerb_node(node, next, false),
				from_ang, sweep)


## Ломаная по дуге радиуса `_side_of_node` вокруг узла: от `from_id` под углом
## `from_ang` на развёртку `sweep` (знак задаёт направление) до `to_id`.
##
## Прямая хорда между концами обвода не годится: она прошла бы близко к самому
## узлу, то есть по торцу полотна. У дуги же каждая точка отстоит от узла ровно
## на вынос, а для всего, что позади торца, узел и есть ближайшая точка
## полилинии — значит весь обвод снаружи полотна.
func _wrap(node: int, from_id: int, to_id: int, from_ang: float,
		sweep: float) -> void:
	var c := _graph.node_position(node)
	var r := _side_of_node(node)
	var steps := _wrap_steps(node, absf(sweep))
	var prev := from_id
	for s in range(1, steps + 1):
		var ang := from_ang + sweep * float(s) / float(steps)
		var next := to_id if s == steps \
			else _add_node(c + Vector3(cos(ang), 0.0, sin(ang)) * r)
		_link(prev, next, Edge.WALK)
		prev = next


## Сколько звеньев нужно обводу, чтобы каждая хорда прошла снаружи полотна:
## хорда, стягивающая угол `phi`, отстоит от узла на `r * cos(phi / 2)`, и это
## обязано быть больше полуширины САМОГО ШИРОКОГО рукава узла — полилинии всех
## рукавов проходят через узел. Отсюда `phi < 2 * acos(half / r)`, а всего
## обвод покрывает `sweep`.
##
## `assert`, а не молчаливый потолок `DEAD_END_CAP_MAX`: вынос считается
## per-edge (`_build_sides`) и по построению равен `half + walk / 2`, поэтому
## `half * 1.05 >= half + walk / 2` требует `half >= 10 * walk` — 40 м
## полуполотна при тротуаре 4 м, чего в городе быть не может. Раньше потолок
## клал хорды обвода ВНУТРЬ полотна без единой ошибки в консоли.
func _wrap_steps(node: int, sweep: float) -> int:
	var r := _side_of_node(node)
	var half := _widest_half(node) * DEAD_END_CLEARANCE
	assert(half < r, "PedGraph: узел %d — полуполотно %.2f м не меньше выноса тротуара %.2f м, обвод лёг бы на проезжую часть" % [node, half, r])
	return clampi(ceili(sweep / (2.0 * acos(half / r))), 1, DEAD_END_CAP_MAX)


## Полуширина самого широкого полотна среди подходов узла, м.
func _widest_half(node: int) -> float:
	var widest := 0.0
	for k in _graph.node_degree(node):
		widest = maxf(widest,
			_graph.edge_width(_graph.approach_edge(node, k)) * 0.5)
	return widest


## Переход в неположенном месте — посреди ленты, между её серединными узлами.
func _build_jwalks() -> void:
	var rng := SeededRng.new(JWALK_SEED)
	for e in _graph.edge_count():
		var m := _edge_mid[e]
		if m < 0:
			continue
		if rng.chance(JWALK_CHANCE):
			_link(m, m + 1, Edge.JWALK)
			_edge_road[edge_key(m, m + 1)] = e


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

## Угол тротуара между подходами k и k+1 узла графа улиц. У развёрнутого
## сектора это ПЕРВАЯ из двух его кербовых точек — та, что обслуживает правую
## сторону подхода k; вторую отдаёт `kerb_node(node, k + 1, false)`.
func corner_node(node: int, k: int) -> int:
	return _corner_first[node] + k


## Кербовый узел тротуара у подхода k со стороны `right` (правая сторона
## направления ОТ узла). У перекрёстка стороны соседних рукавов — это ОДИН
## общий угол; у кольца, у тупика и у развёрнутого сектора — две отдельные
## точки (общего угла нет: у кольца между рукавами аннулюс, у тупика соседнего
## подхода не существует, у шпильки эквидистанта снаружи излома — дуга).
func kerb_node(node: int, k: int, right: bool) -> int:
	var d := _graph.node_degree(node)
	if _is_ring(node) or d == 1:
		return _corner_first[node] + k * 2 + (1 if right else 0)
	if right:
		return _corner_first[node] + k
	var prev := (k - 1 + d) % d
	var key := gate_id(node, prev)
	return _split_corner[key] if _split_corner.has(key) \
		else _corner_first[node] + prev


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


## Ребро графа улиц, которое пересекает это пешеходное ребро, или -1, если
## ребро идёт вдоль тротуара и проезжую часть не пересекает.
func road_edge_of(a: int, b: int) -> int:
	return _edge_road.get(edge_key(a, b), -1)


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
