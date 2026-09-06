class_name NodeSignalController
extends RefCounted
## Светофоры узлов графа: N фаз по подходам вместо двух осей.
##
## Осевой `TrafficLightController` адресует перекрёсток парой индексов сетки
## и знает ровно две фазы (`Axis.Z_ROAD`/`X_ROAD`). Для узла произвольной
## степени понятие «ось» не определено: у узла степени 3 или 5 подходы не
## складываются в две перпендикулярные прямые. Здесь перекрёсток — это
## упорядоченный по углу список подходов узла (`CityGraph.approach_angle`),
## а фаза — группа подходов, которым разрешено ехать одновременно.
##
## Это ОТДЕЛЬНАЯ модель, а не расширение осевой: две адресации
## (`(i, axis)` против `(node, approach)`) несовместимы. С этапа 9 живой город
## пользуется этой; осевая осталась только у полиции.
##
## [b]Паритет с осевой моделью на сетке.[/b] Расписание, нарезка фаз и
## зелёная волна подобраны так, что на сетке 9x9 (узел степени 4 из двух пар
## противоположных подходов) эта модель выдаёт ТО ЖЕ состояние в то же время,
## что `TrafficLightController`. Паритет нужен был на этапах 7-8, пока линзы
## красил осевой контроллер, а машины слушали узловой; сейчас источник один,
## но паритет остаётся дешёвой проверкой того, что расписание не поехало, —
## тест `test_grid_node_matches_axis_controller`.
##
## Состояние нигде не хранится: фаза считается из времени и сдвига узла, как
## и в осевой модели, — 11 регулируемых узлов стоят одного `fposmod`, а не
## 11 таймеров.

enum State { GREEN, YELLOW, RED }

## Длина цикла, с. Та же, что у осевой модели (порт citygen.js:3032-3060):
## цикл общий для всего города, иначе «зелёная волна» вдоль проспекта
## рассыпается — соседние перекрёстки разъезжаются по фазе за пару минут.
const CYCLE := 16.0

## Доля слота фазы, отданная жёлтому. При двух фазах слот равен 8 с, и эта
## доля даёт ровно 2 с жёлтого после 6 с зелёного — расписание оригинала
## (`TrafficLightController.Z_GREEN_END`/`Z_YELLOW_END`).
const YELLOW_FRACTION := 0.25

## Скорость зелёной волны, м/с. Ровно `CityField.cell / WAVE_PER_CELL` =
## 64 / 1.6 оригинала: сдвиг фазы на метр пути прежний, но выражен через
## расстояние, а не через индекс ячейки сетки.
const WAVE_SPEED := 40.0

## Допуск «подходы противоположны», рад. 45° — та же граница «прямо против
## поворота», что `TrafficManager.STRAIGHT_TOL`: пара подходов, расходящихся
## меньше чем на 45° от развёрнутой прямой, читается водителем как одна
## улица, идущая насквозь.
const OPPOSITE_TOL := PI * 0.25

## Полоса западного фронта волны, м: узел считается стоящим на фронте, если
## его x не дальше этого от самого западного узла графа. Меньше метра —
## «тот же ряд», а не «соседний квартал».
##
## [b]Запасной путь, а не модель.[/b] Полоса работает ровно там, где узлы
## стоят столбцом, — на сетке 9x9 она даёт весь западный ряд и сводит формулу
## к осевой `TrafficLightController.phase_offset()` (закреплено тестом
## паритета). На настоящей топологии столбца нет, и фронт задаётся ЯВНЫМ
## списком узлов (`build(..., front_nodes)`); полоса остаётся только для
## синтетических графов без такого списка.
const FRONT_BAND := 0.5

## Позиция внутри цикла, с. Владелец времени — вызывающий (в живой игре это
## `World._process`, который уже ведёт часы осевого контроллера).
var time := 0.0

var _graph: CityGraph
## Узел -> слот в массивах регулирования, -1 у нерегулируемого. Размер равен
## числу узлов графа: id узла вида трафика, вышедший за этот размер (гейт
## кольца), гарантированно нерегулируемый.
var _slot: PackedInt32Array = PackedInt32Array()
var _slot_node: PackedInt32Array = PackedInt32Array()
## Число фаз узла (слота).
var _phase_count: PackedInt32Array = PackedInt32Array()
## Сдвиг фазы узла, с — зелёная волна.
var _offset: PackedFloat32Array = PackedFloat32Array()
## CSR групп: подходы слота лежат в `_group_of[_group_start[s] ..]`, значение —
## номер фазы, в которую подход входит.
var _group_start: PackedInt32Array = PackedInt32Array()
var _group_of: PackedInt32Array = PackedInt32Array()
## CSR таблицы конфликтов: `_compatible[_table_start[s] + a * N + b]` = 1,
## если подходы a и b узла можно пускать одновременно. Таблица — ЯВНЫЕ данные
## узла: состояние фаз её только читает и никогда не выводит арифметикой,
## поэтому будущее уточнение (разрешить правые повороты на встречный красный)
## меняет построение таблицы, а не логику светофора.
var _table_start: PackedInt32Array = PackedInt32Array()
var _compatible: PackedByteArray = PackedByteArray()


## Строит регулирование для перечисленных узлов графа.
##
## `signal_nodes` — ЯВНЫЙ список из топологии города, а не вычисление вроде
## `is_signalized(i, j)` по чётности индексов сетки (`ped_graph.gd:149`):
## какие перекрёстки Пятигорска регулируются, знает топология, а не арифметика.
##
## `front_nodes` — узлы, от которых расходится зелёная волна, тоже явными
## данными топологии (`PyatigorskTopology.wave_front_nodes`). Пустой список
## означает «вывести фронт из габарита» — см. `FRONT_BAND`.
static func build(graph: CityGraph, signal_nodes: PackedInt32Array,
		front_nodes: PackedInt32Array = PackedInt32Array()) -> NodeSignalController:
	var c := NodeSignalController.new()
	c._build(graph, signal_nodes, front_nodes)
	return c


func _build(graph: CityGraph, signal_nodes: PackedInt32Array,
		front_nodes: PackedInt32Array) -> void:
	_graph = graph
	var n := graph.node_count()
	_slot.resize(n)
	_slot.fill(-1)
	if n == 0:
		return

	var wave := _wave_distances(front_nodes)
	var origin := wave[_wave_reference()]
	if is_inf(origin):
		origin = 0.0
	for node in signal_nodes:
		if node < 0 or node >= n or _slot[node] >= 0:
			continue
		# Кольцо не регулируется вовсе: приоритет на нём задан правилом
		# уступания (кто уже на кольце — главный), а не фазами. Список из
		# топологии колец содержать не должен, но проверка тут, а не в
		# доверии к поставщику списка.
		if graph.node_kind(node) == CityGraph.NodeKind.ROUNDABOUT:
			continue
		# Узел степени 1-2 — тупик или излом улицы: конфликтующих траекторий
		# нет, регулировать нечего.
		if graph.node_degree(node) < 3:
			continue
		_add_node(node, wave, origin)


func _add_node(node: int, wave: PackedFloat32Array, origin: float) -> void:
	var degree := _graph.node_degree(node)
	var slot := _slot_node.size()
	_slot[node] = slot
	_slot_node.append(node)
	_group_start.append(_group_of.size())
	_table_start.append(_compatible.size())
	# Узел вне связной компоненты фронта волны едет без сдвига: сдвигать его
	# не от чего, и это честнее NaN из бесконечности.
	var dist := wave[node]
	_offset.append(0.0 if is_inf(dist) else -(dist - origin) / WAVE_SPEED)

	var groups := _pair_opposites(node, degree)
	var phases := 0
	for g in groups:
		phases = maxi(phases, g + 1)
	_phase_count.append(phases)
	_group_of.append_array(groups)

	var table := PackedByteArray()
	table.resize(degree * degree)
	for a in degree:
		for b in degree:
			table[a * degree + b] = 1 if groups[a] == groups[b] else 0
	_compatible.append_array(table)


## Разбиение подходов на фазы: каждый подход спаривается с ближайшим к
## противоположному, непарные едут отдельной фазой.
##
## [b]Упрощение, принятое сознательно.[/b] Точная таблица конфликтов —
## классическая задача светофорного регулирования (какие траектории, включая
## левые повороты, не пересекаются). Игре промышленная точность не нужна,
## поэтому взято консервативное правило из плана этапа: одновременно едет не
## больше одной пары противоположных подходов, все остальные ждут. Оно строго
## безопасно (пересекающиеся потоки никогда не зелёные вместе) ценой
## пропускной способности: левый поворот конфликтует со встречным, но здесь
## они всё равно едут в одну фазу — как и в оригинале, где две оси зелёные
## целиком.
##
## На узле степени 4 из двух пар противоположных подходов правило даёт ровно
## две привычные фазы, на степени 3 — две (пара + одиночка), на степени 5 —
## три (две пары + одиночка).
func _pair_opposites(node: int, degree: int) -> PackedInt32Array:
	var groups := PackedInt32Array()
	groups.resize(degree)
	groups.fill(-1)
	var phase := 0
	for a in degree:
		if groups[a] >= 0:
			continue
		groups[a] = phase
		var opposite := _graph.approach_angle(node, a) + PI
		var best := -1
		var best_dev := OPPOSITE_TOL
		for b in range(a + 1, degree):
			if groups[b] >= 0:
				continue
			var dev := absf(Heading.delta(opposite, _graph.approach_angle(node, b)))
			if dev < best_dev:
				best_dev = dev
				best = b
		if best >= 0:
			groups[best] = phase
		phase += 1
	return groups


# --- Зелёная волна ------------------------------------------------------------

## Расстояние по рёбрам графа от фронта волны до каждого узла, м.
##
## Обобщение `TrafficLightController.phase_offset()`: там сдвиг брался по
## индексу оси сетки (`-(axes[i] / cell) * WAVE_PER_CELL`), здесь — по сумме
## длин рёбер вдоль кратчайшего пути. Принцип тот же: чем дальше по городу от
## фронта, тем позже зелёный, и колонна на разрешённой скорости идёт за
## волной.
##
## Фронт — МНОЖЕСТВО узлов (западный край города), а не один узел, и это
## существенно: на сетке 9x9 расстояние от западного ряда до узла равно
## ровно `x - x_min` вдоль своей улицы, поэтому формула вырождается в старую
## и сеточный город не меняет поведения. Одиночный западный узел дал бы там
## расстояние с лишним слагаемым по z — волна пошла бы по диагонали.
##
## [b]Откуда берётся фронт.[/b] Настоящая топология задаёт его явным списком
## (`front_nodes`, этап 9): на ней узлы стоят не столбцом, и полоса
## `FRONT_BAND` поймала бы ОДИН самый западный узел — расстояние выродилось бы
## в манхэттенское от точки, и волна пошла бы радиально от края карты, а не
## вдоль проспекта. Полоса остаётся запасным путём для графов без списка
## (сетка 9x9 тестов, синтетические графы).
##
## Дейкстра плотной формы (O(V²)) без кучи: узлов сотни, строится один раз на
## этапе планирования города, и куча стоила бы дороже самого поиска.
func _wave_distances(front_nodes: PackedInt32Array) -> PackedFloat32Array:
	var n := _graph.node_count()
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	var visited := PackedByteArray()
	visited.resize(n)

	if front_nodes.is_empty():
		var min_x := INF
		for i in n:
			min_x = minf(min_x, _graph.node_position(i).x)
		for i in n:
			if _graph.node_position(i).x <= min_x + FRONT_BAND:
				dist[i] = 0.0
	else:
		for i in front_nodes:
			if i >= 0 and i < n:
				dist[i] = 0.0

	for _step in n:
		var u := -1
		var best := INF
		for i in n:
			if visited[i] == 0 and dist[i] < best:
				best = dist[i]
				u = i
		if u < 0:
			break
		visited[u] = 1
		for k in _graph.node_degree(u):
			var e := _graph.approach_edge(u, k)
			var ends := _graph.edge_ends(e)
			var v := ends.y if ends.x == u else ends.x
			if v == u:
				continue
			var d := best + _graph.edge_length(e)
			if d < dist[v]:
				dist[v] = d
	return dist


## Узел с нулевым сдвигом фазы: ближайший к центру габарита графа.
##
## Центр, а не край: у осевой модели нулевой сдвиг был в x = 0, то есть в
## середине карты, и сохранение этой точки отсчёта — половина паритета
## (вторая половина — сама формула расстояния). Перебор без хеша узлов: он
## разовый и не имеет права зависеть от порядка обхода ячейки.
func _wave_reference() -> int:
	var n := _graph.node_count()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in n:
		var p := _graph.node_position(i)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var center := (lo + hi) * 0.5
	var best := 0
	var best_d := INF
	for i in n:
		var p := _graph.node_position(i)
		var d := center.distance_squared_to(Vector2(p.x, p.z))
		if d < best_d:
			best_d = d
			best = i
	return best


# --- Запросы ------------------------------------------------------------------

func advance(delta: float) -> void:
	time = fmod(time + delta, CYCLE)


## Регулируется ли узел. Отвечает и на id узла производного вида трафика:
## гейты кольца лежат за пределами узлов города и регулируемыми не бывают.
func is_regulated(node: int) -> bool:
	return node >= 0 and node < _slot.size() and _slot[node] >= 0


func regulated_nodes() -> PackedInt32Array:
	return _slot_node


func phase_count(node: int) -> int:
	var s := _slot_of(node)
	return 0 if s < 0 else _phase_count[s]


## Номер фазы, в которую входит подход, или -1 у нерегулируемого узла.
func phase_of(node: int, approach: int) -> int:
	var s := _slot_of(node)
	if s < 0 or approach < 0 or approach >= _graph.node_degree(node):
		return -1
	return _group_of[_group_start[s] + approach]


## Разрешает ли таблица конфликтов узла пускать оба подхода одновременно.
func may_go_together(node: int, a: int, b: int) -> bool:
	var s := _slot_of(node)
	if s < 0:
		return true
	var degree := _graph.node_degree(node)
	if a < 0 or b < 0 or a >= degree or b >= degree:
		return false
	return _compatible[_table_start[s] + a * degree + b] == 1


## Сдвиг фазы узла, с (зелёная волна).
func phase_offset(node: int) -> float:
	var s := _slot_of(node)
	return 0.0 if s < 0 else _offset[s]


## Положение внутри цикла для узла, 0..CYCLE.
func local_time(node: int) -> float:
	return fposmod(time + phase_offset(node), CYCLE)


## Сигнал для машин, подъезжающих по указанному подходу.
##
## Нерегулируемый узел (в том числе кольцо и гейт кольца) отвечает зелёным:
## светофора там нет, приоритет решают правила уступания трафика.
func car_state(node: int, approach: int) -> State:
	var s := _slot_of(node)
	if s < 0:
		return State.GREEN
	var phases := _phase_count[s]
	if phases <= 1:
		return State.GREEN
	var group := phase_of(node, approach)
	if group < 0:
		return State.GREEN
	var span := CYCLE / float(phases)
	var t := local_time(node)
	var active := int(t / span)
	if active != group:
		return State.RED
	return State.GREEN if t - float(active) * span < span * (1.0 - YELLOW_FRACTION) \
		else State.YELLOW


func is_open_for_cars(node: int, approach: int) -> bool:
	return car_state(node, approach) == State.GREEN


## Пешеходный зелёный на переходе через рукав `approach` горит ровно тогда,
## когда машинам этого подхода красный. Жёлтый пешеходу зелёного не даёт —
## инвариант осевой модели, перенесённый на произвольный подход.
##
## У НЕрегулируемого узла отвечает `false`: сигнала там нет вовсе, и переход
## подчиняется правилам нерегулируемого перехода (этап 8), а не этому
## запросу. Спрашивать надо `is_regulated()`, а не толковать `false` как
## «стой вечно».
func is_crossing_open(node: int, approach: int) -> bool:
	return car_state(node, approach) == State.RED


## Сколько секунд ещё продлится пешеходный зелёный. 0 — уже нельзя идти.
##
## Пешеход обязан спрашивать это ПЕРЕД выходом на зебру: ступать можно,
## только если успеешь дойти, — иначе он застревает посреди рукава при смене
## фазы (приём из capital, перенесён с осевой модели).
func crossing_green_remaining(node: int, approach: int) -> float:
	if not is_crossing_open(node, approach):
		return 0.0
	var span := CYCLE / float(_phase_count[_slot_of(node)])
	return fposmod(float(phase_of(node, approach)) * span - local_time(node), CYCLE)


## Через сколько секунд загорится пешеходный зелёный (0 — уже горит).
## INF — на этом узле светофора нет, зелёного не будет никогда.
func time_until_crossing_green(node: int, approach: int) -> float:
	if is_crossing_open(node, approach):
		return 0.0
	var s := _slot_of(node)
	if s < 0 or phase_of(node, approach) < 0 or _phase_count[s] <= 1:
		return INF
	var span := CYCLE / float(_phase_count[s])
	var end := float(phase_of(node, approach) + 1) * span
	return fposmod(end - local_time(node), CYCLE)


## Упаковка состояния для шейдера линз: индекс горящей секции 0..2.
func lamp_index(node: int, approach: int) -> int:
	match car_state(node, approach):
		State.RED:
			return 0
		State.YELLOW:
			return 1
		_:
			return 2


## Номер подхода, направление которого (ОТ узла) ближе всего к `angle`,
## atan2(dz, dx). Так подъезжающая машина находит свой подход, не зная id
## ребра: трафик едет по производному виду графа с собственным id-пространством
## рёбер, а углы подходов в виде и в городе — одни и те же.
func approach_at_angle(node: int, angle: float) -> int:
	var degree := _graph.node_degree(node)
	var best := -1
	var best_dev := INF
	for k in degree:
		var dev := absf(Heading.delta(angle, _graph.approach_angle(node, k)))
		if dev < best_dev:
			best_dev = dev
			best = k
	return best


func _slot_of(node: int) -> int:
	return -1 if node < 0 or node >= _slot.size() else _slot[node]
