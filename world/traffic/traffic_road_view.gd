class_name TrafficRoadView
extends RefCounted
## Дорожная сеть глазами трафика: производный вид `CityGraph`, в котором
## каждое кольцо развёрнуто в проезжую кольцевую полосу.
##
## В графе города кольцо — ОДИН узел `NodeKind.ROUNDABOUT` с `node_radius()`
## и подходами, упорядоченными по углу (`city_graph.gd`, этап 1). Эта форма
## нужна мешеру (веерная триангуляция острова по радиусу, этап 4), правилам
## регулирования (этап 7) и пешеходам (переход через рукав, этап 8) — трогать
## её нельзя. Но ехать по узлу нельзя тоже: машина, выбравшая на нём
## направление, прошла бы по Безье сквозь центр острова.
##
## Поэтому трафик едет не по графу города, а по его виду:
##  - каждое ребро, упирающееся в кольцо, подрезано до окружности радиуса
##    `node_radius()` — его конец переезжает в «гейт», точку въезда;
##  - гейты одного кольца соединены дугами по аннулюсу, односторонними в
##    сторону правостороннего движения;
##  - остальной граф скопирован один в один.
##
## Вид — отдельный `CityGraph` с собственным id-пространством: его id
## нельзя подставлять в граф города и наоборот. В граф города вид ничего не
## записывает.
##
## Движение, бакетизация и правила ПДД от этого не меняются вовсе: дуга —
## такое же ребро с полилинией, как улица (`TrafficManager._sample_edge`).
## Меняется только источник ответа на вопрос «что здесь кольцо».

## Шаг дискретизации дуги, рад (15°). Дуга обязана быть ломаной, а не хордой:
## выбор направления на гейте сравнивает касательную ВХОДЯЩЕЙ дуги с
## касательной ИСХОДЯЩЕЙ, и у настоящей дуги они в этой точке совпадают —
## продолжение по кольцу попадает в сектор «прямо». Хорда дала бы на каждом
## гейте излом в 360/N градусов и превратила бы кольцо в череду поворотов.
const ARC_STEP := PI / 12.0

## Кольцо радиусом меньше этого не разворачивается: гейты слились бы с
## центром, а дуги выродились в точку. Такой узел остаётся обычным
## перекрёстком — это честнее молчаливого деления на ноль.
const MIN_RADIUS := 1.0

## Какую долю длины ребра подрезка обязана оставить. Упирается в патологию
## «улица короче двух радиусов колец на её концах»; на настоящей топологии
## (кольца 16-22 м, кварталы сотнями метров) не срабатывает.
const MIN_KEEP := 0.2

## Производный граф — по нему едут машины.
var graph := CityGraph.new()
## Ребро вида — дуга кольца (1) или обычная дорога (0). Индекс — id ребра
## ПРОИЗВОДНОГО графа.
var arc: PackedByteArray = PackedByteArray()
## Ребро проезжается только от узла a к узлу b. Сегодня односторонни ровно
## дуги: по кольцу едут в одну сторону.
var one_way: PackedByteArray = PackedByteArray()


static func build(src: CityGraph) -> TrafficRoadView:
	var view := TrafficRoadView.new()
	view._build(src)
	return view


func _build(src: CityGraph) -> void:
	# Узлы копируются с сохранением id: так позиция узла города и позиция
	# узла вида — одно и то же, и отладка не требует таблицы перевода.
	# Узел-кольцо копируется тоже, но в виде к нему не подходит ни одно
	# ребро: его роль забирают гейты.
	for n in src.node_count():
		@warning_ignore("return_value_discarded")
		graph.add_node(src.node_position(n), src.node_level(n),
			src.node_kind(n), src.node_radius(n))

	# Ключ — (узел кольца, номер подхода), значение — id гейта в виде.
	var gates: Dictionary[int, int] = {}
	for e in src.edge_count():
		_add_trimmed_edge(src, e, gates)
	for h in src.node_count():
		_add_ring_arcs(src, h, gates)
	graph.build()


## Радиус, на который подход к узлу подрезается: 0 для обычного узла.
func _hub_radius(src: CityGraph, node: int) -> float:
	if src.node_kind(node) != CityGraph.NodeKind.ROUNDABOUT:
		return 0.0
	if src.node_degree(node) < 2 or src.node_radius(node) < MIN_RADIUS:
		return 0.0
	return src.node_radius(node)


func _add_trimmed_edge(src: CityGraph, e: int, gates: Dictionary[int, int]) -> void:
	var ends := src.edge_ends(e)
	var length := src.edge_length(e)
	var cut_a := _hub_radius(src, ends.x)
	var cut_b := _hub_radius(src, ends.y)
	if cut_a + cut_b > length * (1.0 - MIN_KEEP):
		# Улица короче суммы радиусов на её концах — режем пропорционально,
		# чтобы ребро не выродилось в точку.
		var scale := length * (1.0 - MIN_KEEP) / (cut_a + cut_b)
		cut_a *= scale
		cut_b *= scale

	var points := _sub_polyline(src.edge_polyline(e), cut_a, length - cut_b)
	var va := ends.x if cut_a <= 0.0 else _gate(src, gates, ends.x, e, points[0])
	var vb := ends.y if cut_b <= 0.0 \
		else _gate(src, gates, ends.y, e, points[points.size() - 1])
	@warning_ignore("return_value_discarded")
	graph.add_edge(va, vb, points, src.edge_width(e), src.edge_kind(e), src.edge_level(e))
	arc.append(0)
	one_way.append(0)


## Гейт подхода `edge` к кольцу `hub` — узел вида в точке `pos`.
func _gate(src: CityGraph, gates: Dictionary[int, int], hub: int, edge: int,
		pos: Vector3) -> int:
	var k := _approach_index(src, hub, edge)
	var key := MathUtils.hash_key(hub, k)
	if gates.has(key):
		return gates[key]
	var id := graph.add_node(pos, src.node_level(hub))
	gates[key] = id
	return id


func _approach_index(src: CityGraph, node: int, edge: int) -> int:
	for k in src.node_degree(node):
		if src.approach_edge(node, k) == edge:
			return k
	return -1


## Дуги между соседними гейтами кольца.
##
## Направление движения — В СТОРОНУ УБЫВАНИЯ угла `atan2(dz, dx)`, и это не
## произвол: при правостороннем движении центр кольца обязан быть слева от
## машины. Курс проекта — `atan2(fx, fz)`, левая нормаль к нему —
## `(fz, -fx)` (`Heading.lateral`, со знаком минус). Для точки окружности под
## углом θ убывание θ даёт скорость `(sin θ, -cos θ)`, её левая нормаль —
## `(-cos θ, -sin θ)`, то есть ровно вектор к центру. У возрастания θ она
## смотрит наружу.
##
## Подходы в `CityGraph` упорядочены по возрастанию угла, поэтому дуга ведёт
## от гейта k к гейту k-1.
func _add_ring_arcs(src: CityGraph, hub: int, gates: Dictionary[int, int]) -> void:
	if _hub_radius(src, hub) <= 0.0:
		return
	var degree := src.node_degree(hub)
	var width := 0.0
	for k in degree:
		width = maxf(width, src.edge_width(src.approach_edge(hub, k)))

	var center := src.node_position(hub)
	for k in degree:
		var from_id: int = gates[MathUtils.hash_key(hub, k)]
		var to_id: int = gates[MathUtils.hash_key(hub, (k - 1 + degree) % degree)]
		var points := _arc_points(center, graph.node_position(from_id),
			graph.node_position(to_id))
		@warning_ignore("return_value_discarded")
		graph.add_edge(from_id, to_id, points, width,
			src.edge_kind(src.approach_edge(hub, k)), src.node_level(hub))
		arc.append(1)
		one_way.append(1)


## Ломаная по дуге от `from_pos` к `to_pos` вокруг `center` в сторону
## убывания угла. Радиус и высота интерполируются между концами: гейт
## криволинейного подхода может лежать чуть не на окружности, и дуга обязана
## приходить именно в него, а не рядом.
func _arc_points(center: Vector3, from_pos: Vector3, to_pos: Vector3) -> PackedVector3Array:
	var a_from := atan2(from_pos.z - center.z, from_pos.x - center.x)
	var a_to := atan2(to_pos.z - center.z, to_pos.x - center.x)
	var r_from := Vector2(from_pos.x - center.x, from_pos.z - center.z).length()
	var r_to := Vector2(to_pos.x - center.x, to_pos.z - center.z).length()
	var delta := fposmod(a_from - a_to, TAU)
	if delta < 0.001:
		# Единственный гейт: дуга обходит кольцо целиком.
		delta = TAU
	var steps := maxi(2, ceili(delta / ARC_STEP))
	var points := PackedVector3Array()
	for j in steps + 1:
		var u := float(j) / float(steps)
		var ang := a_from - delta * u
		var r := lerpf(r_from, r_to, u)
		points.append(Vector3(
			center.x + r * cos(ang),
			lerpf(from_pos.y, to_pos.y, u),
			center.z + r * sin(ang)))
	return points


## Кусок ломаной между расстояниями `s0` и `s1` вдоль неё, с интерполяцией
## на концах.
static func _sub_polyline(points: PackedVector3Array, s0: float,
		s1: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var acc := 0.0
	for i in points.size() - 1:
		var p0 := points[i]
		var p1 := points[i + 1]
		var seg := p0.distance_to(p1)
		var next := acc + seg
		if seg > 0.0 and next >= s0 and acc <= s1:
			if out.is_empty():
				out.append(p0.lerp(p1, clampf((s0 - acc) / seg, 0.0, 1.0)))
			if next <= s1:
				out.append(p1)
			else:
				out.append(p0.lerp(p1, clampf((s1 - acc) / seg, 0.0, 1.0)))
		acc = next
	if out.size() < 2:
		return PackedVector3Array([points[0], points[points.size() - 1]])
	return out
