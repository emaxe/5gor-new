class_name CityBlocks
extends RefCounted
## Кварталы города как полигоны произвольной формы — грани планарного графа
## улиц вместо `Rect2` по индексам сетки.
##
## Сегодня квартал — буквально формула `block_rect(bi, bj) = Rect2(-246 +
## bi * 64, -246 + bj * 64, 44, 44)` (city_planner.gd:133-135): 64 одинаковых
## квадрата. В настоящем Пятигорске кварталов такой формы нет — между дугой
## у подножия Машука, бульваром Гагарина и Калинина лежит вытянутый
## многоугольник, а не квадрат.
##
## [b]Источник разбивки — грани планарного графа, а не явный список.[/b]
## Этап 2 явных полигонов не дал (только узлы, рёбра, районы по узлам и
## привязки лендмарков), так что вариантов было два: выписать ~28 полигонов
## руками, как выписана сама топология, или найти грани графа. Выбраны
## грани, потому что вся нужная математика в `CityGraph` уже есть: подходы
## узла лежат в CSR, отсортированные по углу `atan2(dz, dx)`
## (`_build_adjacency`, city_graph.gd:265) — а обход граней планарного
## вложения это ровно «прийти в узел и уйти следующим подходом по углу».
## Алгоритм получается короче и надёжнее рукописной таблицы: рукописная
## таблица разъезжается с топологией при первой же правке улицы, а грани
## пересчитываются сами. Проверка сходимости встроена в сам метод: сумма
## площадей внутренних граней обязана равняться площади внешней
## (`test_city_blocks.gd`).
##
## [b]Что исключается из разбивки.[/b] Только рёбра НЕ нулевого яруса: дека
## путепровода у вокзала (этап 3) пересекает улицу Крайнего без общего узла
## и делает граф в плане непланарным — единственное такое место в городе.
## Пандусы (ярус ребра 0) остаются: в плане они ничего не пересекают.
##
## [b]Висячие ветви отсекаются[/b] до обхода: тупики (переулок к Гроту,
## дороги на Машук, серпантин) граней не образуют, но заставляют обход
## идти по ребру дважды и делают полигон невырожденным только на бумаге.
## Стандартное сведение к 2-ядру графа: пока есть узел степени 1 — убрать
## его рёбра.
##
## Чистая логика без нод: строится в том же фоновом потоке, что `CityPlan`.

## Минимальная площадь квартала, м². Дом в плане не меньше 9x9 (city_planner
## .gd:261), плюс отступ фасада от оси полотна — во что-то меньше 200 м²
## застройка не влезает физически, а грань такой площади это артефакт
## сдвоенных узлов, а не квартал.
const MIN_AREA := 200.0

var graph: CityGraph

## CSR полигонов: точки квартала b — `_poly[_poly_start[b] .. _poly_start[b+1])`.
## Полигон идёт по ОСЯМ полотна (узлы и точки полилиний рёбер), а не по
## фасадам: отступ до фасада зависит от ширины конкретной улицы и берётся
## застройщиком (`BlockPlanner`) на каждом ребре свой.
var _poly_start: PackedInt32Array = PackedInt32Array()
var _poly: PackedVector2Array = PackedVector2Array()
## Ребро графа, которому принадлежит точка полигона (и сегмент, который из
## неё выходит). Нужно застройщику: у стороны квартала своя ширина полотна,
## а значит и свой отступ фасада.
var _poly_edge: PackedInt32Array = PackedInt32Array()

## CSR границы: рёбра графа, обходящие квартал, в порядке обхода.
var _bnd_start: PackedInt32Array = PackedInt32Array()
var _bnd_edge: PackedInt32Array = PackedInt32Array()
## Идёт ли обход по ребру от узла a к узлу b (1) или наоборот (0).
var _bnd_forward: PackedByteArray = PackedByteArray()
## Узел, из которого обход выходит по k-му ребру границы.
var _bnd_node: PackedInt32Array = PackedInt32Array()

var _area: PackedFloat32Array = PackedFloat32Array()
var _centroid: PackedVector2Array = PackedVector2Array()
var _district: Array[StringName] = []
## Лендмарк, занявший квартал, или "" — прямой аналог `block_special()`
## (city_planner.gd:124), только по привязкам этапа 2, а не по индексам.
var _special: Array[StringName] = []

## Площадь внешней грани, м². Ровно сумма площадей кварталов — контрольная
## сумма разбивки, её проверяет тест.
var outer_area := 0.0


# --- Построение -------------------------------------------------------------

## Разбивает граф на кварталы.
##
## `node_district` и `landmark_node` — данные топологии (этап 2) в чистом
## виде, а не сам `PyatigorskTopology`: разбивка не должна знать, для какого
## города её позвали.
func build(city_graph: CityGraph, node_district: Array[StringName],
		landmark_node: Dictionary[StringName, int]) -> void:
	clear()
	graph = city_graph
	var active := _active_edges()
	_prune_dangling(active)
	_extract_faces(active)
	_assign_districts(node_district)
	_assign_landmarks(landmark_node)


## Сбрасывает разбивку. Вызывается самим `build()`: обход граней дописывает
## CSR с нуля (`_poly_start.append(0)`), и повторный `build()` на том же
## экземпляре без сброса вставил бы второй ноль в середину — `polygon_size()`
## стал бы отрицательным на первом же квартале. Тот же контракт, что у
## `CityCollision.build()` и `PoliceManager.BuildingHash.build()`: собрать
## заново, а не поверх.
func clear() -> void:
	_poly_start = PackedInt32Array()
	_poly = PackedVector2Array()
	_poly_edge = PackedInt32Array()
	_bnd_start = PackedInt32Array()
	_bnd_edge = PackedInt32Array()
	_bnd_forward = PackedByteArray()
	_bnd_node = PackedInt32Array()
	_area = PackedFloat32Array()
	_centroid = PackedVector2Array()
	_district = []
	_special = []
	outer_area = 0.0


## Рёбра, участвующие в разбивке: только нулевой ярус.
func _active_edges() -> PackedByteArray:
	var active := PackedByteArray()
	active.resize(graph.edge_count())
	for e in graph.edge_count():
		active[e] = 1 if graph.edge_level(e) == 0 else 0
	return active


## Сведение к 2-ядру: пока есть узел степени 1, его рёбра из разбивки
## выбывают. Иначе обход тупика идёт по ребру туда и обратно, и «грань»
## получается с нулевой полосой вместо контура.
func _prune_dangling(active: PackedByteArray) -> void:
	while true:
		var degree := PackedInt32Array()
		degree.resize(graph.node_count())
		for e in graph.edge_count():
			if active[e] == 0:
				continue
			var ends := graph.edge_ends(e)
			degree[ends.x] += 1
			degree[ends.y] += 1
		var changed := false
		for e in graph.edge_count():
			if active[e] == 0:
				continue
			var ends := graph.edge_ends(e)
			if degree[ends.x] < 2 or degree[ends.y] < 2:
				active[e] = 0
				changed = true
		if not changed:
			return


## Обход граней. Каждое полуребро (ребро + направление) принадлежит ровно
## одной грани; следующее за ним — предыдущий по углу подход в узле прихода.
## При таком выборе внутренние грани получаются с ПОЛОЖИТЕЛЬНОЙ площадью по
## формуле шнурков в (x, z), а внешняя — с отрицательной, поэтому отдельного
## правила «какая из граней внешняя» не нужно.
func _extract_faces(active: PackedByteArray) -> void:
	_poly_start.append(0)
	_bnd_start.append(0)
	var visited := PackedByteArray()
	visited.resize(graph.edge_count() * 2)
	for e in graph.edge_count():
		if active[e] == 0:
			continue
		for d in 2:
			if visited[e * 2 + d] == 1:
				continue
			_walk_face(e, d, active, visited)


func _walk_face(start_edge: int, start_dir: int, active: PackedByteArray,
		visited: PackedByteArray) -> void:
	var poly := PackedVector2Array()
	var poly_edge := PackedInt32Array()
	var edges := PackedInt32Array()
	var forward := PackedByteArray()
	var from_nodes := PackedInt32Array()
	var half := start_edge * 2 + start_dir
	var repeated := false
	while true:
		if visited[half] == 1:
			# Возврат в уже пройденное полуребро: контур замкнулся.
			break
		visited[half] = 1
		@warning_ignore("integer_division")
		var edge := half / 2
		var dir := half % 2
		var ends := graph.edge_ends(edge)
		var from_node: int = ends.x if dir == 0 else ends.y
		var to_node: int = ends.y if dir == 0 else ends.x
		if edges.has(edge):
			repeated = true
		edges.append(edge)
		forward.append(1 if dir == 0 else 0)
		from_nodes.append(from_node)
		# Точки ребра без последней: она же первая точка следующего ребра.
		var n := graph.edge_point_count(edge)
		for k in n - 1:
			var p := graph.edge_point(edge, k if dir == 0 else n - 1 - k)
			poly.append(Vector2(p.x, p.z))
			poly_edge.append(edge)
		half = _next_half(edge, to_node, active)
		if half < 0:
			return

	var area := signed_area(poly)
	if area < 0.0:
		outer_area = -area
		return
	# Грань, прошедшая по одному ребру дважды, — не контур квартала, а
	# «перешеек» между двумя кольцами графа. В нынешней топологии таких нет
	# (все висячие ветви уже отсечены), но разбивка обязана оставаться
	# корректной, а не правдоподобной, если топология изменится.
	if repeated or area < MIN_AREA:
		return

	_poly.append_array(poly)
	_poly_edge.append_array(poly_edge)
	_poly_start.append(_poly.size())
	_bnd_edge.append_array(edges)
	_bnd_forward.append_array(forward)
	_bnd_node.append_array(from_nodes)
	_bnd_start.append(_bnd_edge.size())
	_area.append(area)
	_centroid.append(_polygon_centroid(poly, area))
	_district.append(&"")
	_special.append(&"")


## Следующее полуребро обхода: предыдущий по углу подход узла `to_node`
## относительно того, которым в него пришли. Неактивные рёбра пропускаются —
## обход идёт по тому вложению, которое осталось после отсечения.
func _next_half(edge: int, to_node: int, active: PackedByteArray) -> int:
	var degree := graph.node_degree(to_node)
	var slot := -1
	for j in degree:
		if graph.approach_edge(to_node, j) == edge:
			slot = j
			break
	for step in range(1, degree + 1):
		var next_edge := graph.approach_edge(to_node, posmod(slot - step, degree))
		if active[next_edge] == 0:
			continue
		var ends := graph.edge_ends(next_edge)
		return next_edge * 2 + (0 if ends.x == to_node else 1)
	return -1


## Район квартала — по большинству его узлов. Топология задаёт район на узле
## (`node_district`), а узлы одного квартала почти всегда однородны; спорные
## случаи (квартал на стыке центра и курорта) решает большинство, а при
## равенстве — первый по обходу, чтобы результат не зависел от порядка
## словаря.
func _assign_districts(node_district: Array[StringName]) -> void:
	for b in count():
		var votes: Dictionary[StringName, int] = {}
		var best := &""
		var best_votes := 0
		for k in boundary_count(b):
			var id := node_district[_bnd_node[_bnd_start[b] + k]]
			var v: int = votes.get(id, 0) + 1
			votes[id] = v
			if v > best_votes:
				best_votes = v
				best = id
		_district[b] = best


## Особые кварталы — по привязкам лендмарков этапа 2.
##
## В сетке 8x8 особый квартал задавался таблицей индексов; в настоящей
## топологии восемь лендмарков из девяти — это УЗЛЫ графа (площадь, кольцо,
## тупик), а не кварталы, поэтому правило переехало так:
##  - лендмарк внутри полигона (Грот Лермонтова) — квартал его и есть;
##  - лендмарк на кольцевом узле (Верхний рынок, вокзал) — участком служит
##    сам остров кольца, квартал не занимается;
##  - иначе (Цветник, Нарзанные ванны, Провал) — ближайший по центроиду из
##    примыкающих кварталов.
## Каждый лендмарк занимает не больше одного квартала, занятый второй раз не
## отдаётся: иначе Цветник и Нарзанные ванны, стоящие через квартал друг от
## друга, отобрали бы один и тот же участок, а второй остался бы без места.
##
## Проходов два, и порядок между ними значим: сперва лендмарки ВНУТРИ
## кварталов, потом соседние. Грот Лермонтова стоит внутри квартала, и
## отдать этот квартал Цветнику, которому годится любой из четырёх соседних,
## значило бы оставить Грот в застройке.
##
## Сама сцена достопримечательности может выходить за границу занятого
## квартала (у Цветника скамьи на 15.8 м от центра, у рынка ряды на 17 м),
## поэтому застройщик держит ещё и радиус вокруг точки лендмарка — одно
## правило не заменяет другое.
func _assign_landmarks(landmark_node: Dictionary[StringName, int]) -> void:
	for id in sorted_ids(landmark_node):
		var node: int = landmark_node[id]
		var pos := _node_plan(node)
		var inside := block_at(pos)
		if inside >= 0 and _special[inside].is_empty():
			_special[inside] = id

	for id in sorted_ids(landmark_node):
		var node: int = landmark_node[id]
		var pos := _node_plan(node)
		if block_at(pos) >= 0 \
				or graph.node_kind(node) == CityGraph.NodeKind.ROUNDABOUT:
			continue
		var best := -1
		var best_dist := INF
		for b in count():
			if not _special[b].is_empty() or not _touches_node(b, node):
				continue
			var d := _centroid[b].distance_squared_to(pos)
			if d < best_dist:
				best_dist = d
				best = b
		if best >= 0:
			_special[best] = id


func _node_plan(node: int) -> Vector2:
	var p := graph.node_position(node)
	return Vector2(p.x, p.z)


## Идентификаторы по алфавиту. Сортировать `Array[StringName]` напрямую
## нельзя: `StringName` сравнивается по внутреннему указателю, а не по
## тексту, — порядок получается стабильным внутри процесса и РАЗНЫМ между
## запусками, то есть город менялся бы от загрузки к загрузке.
static func sorted_ids(dict: Dictionary[StringName, int]) -> Array[StringName]:
	var text: Array[String] = []
	for key: StringName in dict:
		text.append(String(key))
	text.sort()
	var out: Array[StringName] = []
	for t in text:
		out.append(StringName(t))
	return out


func _touches_node(block: int, node: int) -> bool:
	for k in boundary_count(block):
		if _bnd_node[_bnd_start[block] + k] == node:
			return true
	return false


# --- Доступ к данным --------------------------------------------------------

func count() -> int:
	return _area.size()


## Полигон квартала в плане: замкнутый контур по осям полотна, обход даёт
## положительную площадь (внутренность слева по направлению обхода
## в осях (x, z)).
func polygon(block: int) -> PackedVector2Array:
	return _poly.slice(_poly_start[block], _poly_start[block + 1])


func polygon_size(block: int) -> int:
	return _poly_start[block + 1] - _poly_start[block]


func polygon_point(block: int, k: int) -> Vector2:
	return _poly[_poly_start[block] + k]


## Ребро графа, вдоль которого идёт k-й сегмент полигона (от точки k к k+1).
func polygon_edge(block: int, k: int) -> int:
	return _poly_edge[_poly_start[block] + k]


func boundary_count(block: int) -> int:
	return _bnd_start[block + 1] - _bnd_start[block]


func boundary_edge(block: int, k: int) -> int:
	return _bnd_edge[_bnd_start[block] + k]


## Узел, из которого обход выходит по k-му ребру границы.
func boundary_node(block: int, k: int) -> int:
	return _bnd_node[_bnd_start[block] + k]


## Полилиния k-го ребра границы в плане, ориентированная ПО ОБХОДУ квартала:
## внутренность лежит слева по направлению точек в осях (x, z).
func boundary_plan(block: int, k: int) -> PackedVector2Array:
	var e := boundary_edge(block, k)
	var forward := _bnd_forward[_bnd_start[block] + k] == 1
	var n := graph.edge_point_count(e)
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var p := graph.edge_point(e, i if forward else n - 1 - i)
		out[i] = Vector2(p.x, p.z)
	return out


func area(block: int) -> float:
	return _area[block]


func centroid(block: int) -> Vector2:
	return _centroid[block]


func district(block: int) -> StringName:
	return _district[block]


## Лендмарк, занявший квартал, или "" — квартал под обычную застройку.
func special(block: int) -> StringName:
	return _special[block]


func contains(block: int, p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, polygon(block))


## Квартал, внутри которого лежит точка, или -1. Перебор, а не хеш:
## кварталов десятки, а запрос идёт на фазе планирования, не в кадре.
func block_at(p: Vector2) -> int:
	for b in count():
		if contains(b, p):
			return b
	return -1


# --- Геометрия --------------------------------------------------------------

## Площадь по формуле шнурков в осях (x, z). Знак — ориентация обхода.
static func signed_area(poly: PackedVector2Array) -> float:
	var acc := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		acc += p.x * q.y - q.x * p.y
	return acc * 0.5


## Центр масс полигона (не среднее вершин: у кривой полилинии точек с одной
## стороны больше, и среднее уезжает к ней).
static func _polygon_centroid(poly: PackedVector2Array, poly_area: float) -> Vector2:
	var acc := Vector2.ZERO
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		var cross := p.x * q.y - q.x * p.y
		acc += (p + q) * cross
	return acc / (6.0 * poly_area)
