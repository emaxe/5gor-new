class_name CityMapLines
extends RefCounted
## Проекция графа улиц в план (x, z) для миникарты и большой карты.
##
## Обе карты рисуют одни и те же полилинии рёбер `CityGraph` и
## перерисовываются десятки раз в секунду, а граф после `build()` неизменен —
## поэтому проекция, габариты рёбер и цвета считаются один раз на город.
## Высота полилинии (`y`) карте не нужна: вид сверху её не показывает.
##
## Отсев ребра за краем миникарты идёт по его габариту, а НЕ через
## `SpatialHash2D` графа. Хеш настроен на ячейку 16 м под запросы трафика и
## пешеходов радиусом в единицы метров; круг миникарты радиусом 220 м
## накрывает (440/16)^2 ~ 750 ячеек, и обход их списков с отсевом дублей
## обошёлся бы дороже, чем по одной проверке «прямоугольник против круга» на
## ребро: во всей топологии Пятигорска их сегодня 94 (463 точки суммарно).

## Полотно обычной улицы на карте — цвет сеточной эпохи (ui.js), чтобы вид
## карт не поехал вместе со сменой источника геометрии. Прозрачность взята
## от большой карты (0.7), а не от миникарты (0.6): на её тёмной подложке
## улица при 0.6 читается хуже, а на светлой подложке миникарты разница
## незаметна — один цвет на оба экрана.
const COLOR_ROAD := Color(0.30, 0.35, 0.45, 0.7)

## Эстакада и её пандусы — светлее обычной улицы. Вид сверху не различает
## высоту, и путепровод на улице Козлова иначе неотличим от улицы Крайнего,
## проходящей под ним: две линии просто пересекаются. Решение этапа 9 по
## мостам/тоннелям на карте — различать их цветом, а не рисовать развязку.
const COLOR_ELEVATED := Color(0.50, 0.55, 0.66, 0.75)

## Тоннель — темнее улицы, «уходит под землю». В топологии Пятигорска
## тоннелей сегодня нет, но `EdgeKind.TUNNEL` в модели есть, и оставлять
## его без цвета — значит нарисовать его как обычную улицу в тот день,
## когда он появится.
const COLOR_TUNNEL := Color(0.18, 0.21, 0.29, 0.55)

## Граф, из которого построена проекция: по его тождеству экраны понимают,
## что кеш относится к текущему городу, а не к предыдущей смене.
var roads: CityGraph = null

## CSR полилиний: точки ребра e лежат в `points[start[e] .. start[e + 1])`.
var points := PackedVector2Array()
var start := PackedInt32Array()
## Габарит ребра в плане: (x0, z0, x1, z1).
var box := PackedVector4Array()
## Ширина полотна, м — толщина линии на карте берётся из неё, а не из
## общей константы: проспект Кирова (18 м) обязан читаться шире переулка (8 м).
var width := PackedFloat32Array()
var color := PackedColorArray()

## Кольца: центр в плане, радиус и ширина полотна, м. Кольцо в графе — это
## УЗЕЛ с радиусом, а не цепочка рёбер, поэтому по одним рёбрам карта
## нарисовала бы на его месте обычный перекрёсток-точку, хотя в мире там
## видимая окружность (`RoadMesh` строит её по тому же `node_radius`).
var ring_pos := PackedVector2Array()
var ring_radius := PackedFloat32Array()
var ring_width := PackedFloat32Array()

## Габарит всего города в плане — по нему большая карта вписывает город в экран.
var bounds := Rect2()


static func of(city_roads: CityGraph) -> CityMapLines:
	var lines := CityMapLines.new()
	lines._build(city_roads)
	return lines


func edge_count() -> int:
	return box.size()


## Задевает ли габарит ребра круг видимости — дешёвый отсев до пересчёта
## точек ребра в экранные координаты.
func touches(edge: int, center: Vector2, radius: float) -> bool:
	var b := box[edge]
	var dx := center.x - clampf(center.x, b.x, b.z)
	var dz := center.y - clampf(center.y, b.y, b.w)
	return dx * dx + dz * dz <= radius * radius


func _build(city_roads: CityGraph) -> void:
	roads = city_roads
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for e in city_roads.edge_count():
		start.append(points.size())
		var e_lo := Vector2(INF, INF)
		var e_hi := Vector2(-INF, -INF)
		for k in city_roads.edge_point_count(e):
			var p := city_roads.edge_point(e, k)
			points.append(Vector2(p.x, p.z))
			e_lo = Vector2(minf(e_lo.x, p.x), minf(e_lo.y, p.z))
			e_hi = Vector2(maxf(e_hi.x, p.x), maxf(e_hi.y, p.z))
		box.append(Vector4(e_lo.x, e_lo.y, e_hi.x, e_hi.y))
		width.append(city_roads.edge_width(e))
		color.append(_kind_color(city_roads.edge_kind(e)))
		lo = Vector2(minf(lo.x, e_lo.x), minf(lo.y, e_lo.y))
		hi = Vector2(maxf(hi.x, e_hi.x), maxf(hi.y, e_hi.y))
	start.append(points.size())

	for n in city_roads.node_count():
		if city_roads.node_kind(n) != CityGraph.NodeKind.ROUNDABOUT:
			continue
		var p := city_roads.node_position(n)
		var radius := city_roads.node_radius(n)
		ring_pos.append(Vector2(p.x, p.z))
		ring_radius.append(radius)
		# Ширина по самому широкому подходу: кольцо не уже улицы, с которой
		# на него въезжают.
		var w := 0.0
		for k in city_roads.node_degree(n):
			w = maxf(w, city_roads.edge_width(city_roads.approach_edge(n, k)))
		ring_width.append(w)
		# Полотно кольца выходит за концы рёбер — те упираются в его центр.
		# В габарит идёт внешняя кромка (радиус + полуширина): именно её
		# рисуют обе карты, и именно она не должна уехать за край экрана.
		var paved := radius + w * 0.5
		lo = Vector2(minf(lo.x, p.x - paved), minf(lo.y, p.z - paved))
		hi = Vector2(maxf(hi.x, p.x + paved), maxf(hi.y, p.z + paved))

	if not points.is_empty():
		bounds = Rect2(lo, hi - lo)


## RAMP красится как эстакада намеренно: его `edge_level` — ярус НИЖНЕГО
## конца (0), так что по уровню пандус неотличим от улицы, хотя половина
## его длины идёт над землёй.
func _kind_color(kind: int) -> Color:
	match kind:
		CityGraph.EdgeKind.BRIDGE, CityGraph.EdgeKind.RAMP:
			return COLOR_ELEVATED
		CityGraph.EdgeKind.TUNNEL:
			return COLOR_TUNNEL
	return COLOR_ROAD
