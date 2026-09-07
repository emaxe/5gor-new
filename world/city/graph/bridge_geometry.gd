class_name BridgeGeometry
extends RefCounted
## Тело путепровода по рёбрам `CityGraph.EdgeKind.BRIDGE`: плита деки,
## опоры с ригелями, перила — плюс те же плиты и опоры как данные для
## коллизий (`CityCollision.build_bridges`).
##
## [b]Почему отдельный класс, а не мешер этапа 4.[/b] Общий мешер полотна по
## всем видам рёбер — задача этапа 4, которого ещё нет. Здесь строится
## ровно то, чего требует этап 3: пролёт, который видно на снимке сбоку, и
## коллизия, которая не перекрывает проезд под ним. Этап 4, обобщая полотно
## на все рёбра, забирает отсюда `_deck_wear()` (та же `ribbon()` по
## полилинии) и оставляет за этим классом опоры и перила — то, чего у
## обычной улицы нет; задваивать полотно нельзя.
##
## [b]Что сознательно не строится.[/b] Тоннели (`EdgeKind.TUNNEL`) отложены
## решением этапа 2: в Пятигорске нет места под автомобильный тоннель, и
## портал было бы некуда врезать. Наклонная плита рампе не строится тоже:
## пандус здесь — насыпь, а не эстакада, его полотно — обычная дорога
## этапа 4.
##
## Геометрия и данные коллизии считаются ОДИН раз в `_init` и живут в
## Packed*-массивах: мешер и коллизия читают одно и то же, поэтому опора,
## которую видно, — та же, в которую можно въехать.

## Толщина плиты деки, м. Просвет под мостом = отметка деки минус эта
## толщина, поэтому она входит в проверку `CityGraph.MIN_CLEARANCE`.
## 0.5 м — визуальный минимум: тоньше плита читается фанерой на спичках.
const DECK_THICKNESS := 0.5

## Шаг опор вдоль пролёта, м. При 41-метровом пролёте даёт четыре позиции;
## две средние приходятся на полотно улицы внизу и пропускаются — опору на
## проезжей части ставить нельзя (`_pier_allowed`).
const PIER_SPACING := 10.0
## Радиус столба опоры, м. Втрое толще фонарного столба (0.18,
## `city_collision.gd:40`) — опора моста обязана читаться несущей.
const PIER_RADIUS := 0.9
## Запас от кромки полотна внизу до края опоры, м.
const PIER_MARGIN := 1.0
## Радиус, в котором ищется полотно нижнего яруса под опорой, м.
const PIER_SCAN_RADIUS := 30.0
## Ригель поверх опоры: высота и вылет за диаметр столба, м.
const PIER_CAP_HEIGHT := 0.5
const PIER_CAP_OVERHANG := 0.6

## Перила: высота над декой и толщина, м. Высота взята по бортику реальных
## путепроводов (0.9 м — уровень пояса), толщина — по бордюру города.
const RAIL_HEIGHT := 0.9
const RAIL_THICK := 0.25

## Полотно кладётся на 2 см выше плиты: слои совпадающих плоскостей дают
## z-fighting, а не аккуратный стык.
const WEAR_LIFT := 0.02

## Бетон плиты и опор. Светлее асфальта и темнее бордюра — иначе на снимке
## сбоку дека сливается либо с полотном, либо с перилами.
const COLOR_CONCRETE := Color("#8e8d86")

## Плиты деки посегментно: центр, габарит (ширина, толщина, длина) и рыскание.
var deck_center := PackedVector3Array()
var deck_size := PackedVector3Array()
var deck_yaw := PackedFloat32Array()
## Опоры: точка на земле, высота столба до низа плиты и рыскание ригеля.
var pier_base := PackedVector3Array()
var pier_height := PackedFloat32Array()
var pier_yaw := PackedFloat32Array()
## Устои моста на стыке пролёта с насыпью: центр, габарит (ширина, высота, глубина) и рыскание.
var abutment_center := PackedVector3Array()
var abutment_size := PackedVector3Array()
var abutment_yaw := PackedFloat32Array()
## Отброшенные позиции опор — те, что пришлись на полотно внизу. Само число
## проверяется тестом: ноль пропусков означал бы, что мост стоит не над
## улицей и разводить по высоте нечего.
var piers_over_road := 0

## Полилинии пролётов и их ширины — для полотна деки, которое кладётся не
## посегментно, а одной лентой на ребро.
var _spans: Array[PackedVector3Array] = []
var _span_width := PackedFloat32Array()


func _init(graph: CityGraph, field: CityField) -> void:
	for e in graph.edge_count():
		if graph.edge_kind(e) != CityGraph.EdgeKind.BRIDGE:
			continue
		var pts := graph.edge_polyline(e)
		_spans.append(pts)
		_span_width.append(graph.edge_width(e))
		_collect_deck(pts, graph.edge_width(e))
		_collect_piers(graph, field, pts)
		_collect_abutments(field, pts, graph.edge_width(e))


func deck_count() -> int:
	return deck_center.size()


func pier_count() -> int:
	return pier_height.size()


func abutment_count() -> int:
	return abutment_center.size()


## Меш пролёта: плита, полотно, перила, опоры с ригелями, устои.
func build_mesh(b: MeshBuilder) -> void:
	for i in deck_count():
		var rot := Basis.from_euler(Vector3(0.0, deck_yaw[i], 0.0))
		b.box(deck_center[i], deck_size[i], COLOR_CONCRETE, rot)
		_rails(b, i, rot)
	for i in pier_count():
		var base := pier_base[i]
		var h := pier_height[i]
		b.cylinder(base + Vector3(0.0, h * 0.5, 0.0), PIER_RADIUS, PIER_RADIUS,
			h, COLOR_CONCRETE, 8)
		var cap_rot := Basis.from_euler(Vector3(0.0, pier_yaw[i], 0.0))
		b.box(base + Vector3(0.0, h + PIER_CAP_HEIGHT * 0.5, 0.0),
			Vector3(PIER_RADIUS * 4.0, PIER_CAP_HEIGHT,
				PIER_RADIUS * 2.0 + PIER_CAP_OVERHANG),
			COLOR_CONCRETE, cap_rot)
	for i in abutment_count():
		var rot := Basis.from_euler(Vector3(0.0, abutment_yaw[i], 0.0))
		b.box(abutment_center[i], abutment_size[i], COLOR_CONCRETE, rot)
	_deck_wear(b)


## Полотно деки — та же лента, что понесёт обычная улица этапа 4, просто по
## приподнятой полилинии. Ширина — между перилами, а не полная: асфальт не
## заезжает на бортик.
func _deck_wear(b: MeshBuilder) -> void:
	for i in _spans.size():
		b.ribbon(_spans[i], _span_width[i] - RAIL_THICK * 2.0,
			CityMesher.COLOR_ROAD, WEAR_LIFT)


func _rails(b: MeshBuilder, i: int, rot: Basis) -> void:
	var size := deck_size[i]
	var half := (size.x - RAIL_THICK) * 0.5
	var up := Vector3(0.0, RAIL_HEIGHT * 0.5, 0.0)
	for s: float in [-1.0, 1.0]:
		# Плита центрирована по своей толщине, поэтому верх деки — половина
		# толщины вверх от центра; перило стоит на нём.
		var c := deck_center[i] + Vector3(0.0, size.y * 0.5, 0.0) + up \
			+ rot * Vector3(s * half, 0.0, 0.0)
		b.box(c, Vector3(RAIL_THICK, RAIL_HEIGHT, size.z),
			CityMesher.COLOR_CURB, rot)


## Плита по сегментам полилинии: у пролёта дека горизонтальна, поэтому
## сегменту хватает рыскания. Наклонному пролёту (если такой появится)
## понадобится ещё и тангаж — сегодня наклонных пролётов в графе нет.
func _collect_deck(pts: PackedVector3Array, width: float) -> void:
	for k in range(1, pts.size()):
		var p0 := pts[k - 1]
		var p1 := pts[k]
		var dir := p1 - p0
		var length := dir.length()
		if length < 0.01:
			continue
		deck_center.append((p0 + p1) * 0.5 - Vector3(0.0, DECK_THICKNESS * 0.5, 0.0))
		deck_size.append(Vector3(width, DECK_THICKNESS, length))
		deck_yaw.append(atan2(dir.x, dir.z))


## Опоры равным шагом по длине пролёта в плане. Позиция, попавшая на полотно
## нижнего яруса, пропускается: столб посреди проезжей части — не опора, а
## препятствие, а весь смысл развязки в том, что под ней едут.
func _collect_piers(graph: CityGraph, field: CityField,
		pts: PackedVector3Array) -> void:
	var lengths := _plan_lengths(pts)
	var total: float = lengths[lengths.size() - 1]
	if total < 0.01:
		return
	var count := maxi(1, ceili(total / PIER_SPACING) - 1)
	for k in count:
		var s := total * float(k + 1) / float(count + 1)
		var at := _sample(pts, lengths, s)
		var ground := field.height_at(at.x, at.z)
		var foot := Vector3(at.x, ground, at.z)
		if not _pier_allowed(graph, foot):
			piers_over_road += 1
			continue
		var h := at.y - DECK_THICKNESS - PIER_CAP_HEIGHT - ground
		if h <= 0.0:
			continue
		pier_base.append(foot)
		pier_height.append(h)
		pier_yaw.append(_yaw_at(pts, lengths, s))


## Свободна ли точка на земле под опору. Запрос идёт с высотой земли,
## поэтому дизамбигуация по ярусу сама отсекает деку над головой: если
## ближайшее ребро оказалось на другой высоте, полотна нижнего яруса рядом
## нет вовсе.
func _pier_allowed(graph: CityGraph, foot: Vector3) -> bool:
	var e := graph.query_nearest_edge(foot, PIER_SCAN_RADIUS)
	if e < 0:
		return true
	if absf(graph.hit_point.y - foot.y) > CityGraph.LEVEL_TOLERANCE:
		return true
	return graph.hit_dist > graph.edge_width(e) * 0.5 + PIER_RADIUS + PIER_MARGIN


## Накопленные длины полилинии в плане: высоту в шаг опор мешать нельзя,
## иначе на уклоне опоры сгущаются.
func _plan_lengths(pts: PackedVector3Array) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0])
	var acc := 0.0
	for k in range(1, pts.size()):
		acc += Vector2(pts[k].x, pts[k].z).distance_to(
			Vector2(pts[k - 1].x, pts[k - 1].z))
		out.append(acc)
	return out


func _sample(pts: PackedVector3Array, lengths: PackedFloat32Array,
		s: float) -> Vector3:
	var k := _segment_at(lengths, s)
	var span: float = lengths[k + 1] - lengths[k]
	var t: float = 0.0 if span <= 0.0 else (s - lengths[k]) / span
	return pts[k].lerp(pts[k + 1], t)


func _yaw_at(pts: PackedVector3Array, lengths: PackedFloat32Array,
		s: float) -> float:
	var k := _segment_at(lengths, s)
	var dir := pts[k + 1] - pts[k]
	return atan2(dir.x, dir.z)


func _segment_at(lengths: PackedFloat32Array, s: float) -> int:
	for k in range(1, lengths.size()):
		if s <= lengths[k]:
			return k - 1
	return lengths.size() - 2


## Устои моста на стыке пролёта с насыпью: бетонная подпорная стенка под
## концами деки от уровня земли до низа плиты.
func _collect_abutments(field: CityField, pts: PackedVector3Array, width: float) -> void:
	if pts.size() < 2:
		return
	var ends := [0, pts.size() - 1]
	for idx: int in ends:
		var p := pts[idx]
		var dir := (pts[1] - pts[0]) if idx == 0 else (pts[pts.size() - 1] - pts[pts.size() - 2])
		dir.y = 0.0
		if dir.length_squared() < 1e-6:
			continue
		var ground := field.height_at(p.x, p.z)
		var deck_bottom := p.y - DECK_THICKNESS
		var h := deck_bottom - ground
		if h <= 0.5:
			continue
		var center := Vector3(p.x, ground + h * 0.5, p.z)
		var size := Vector3(width + 0.6, h, 1.2)
		var yaw := atan2(dir.x, dir.z)
		abutment_center.append(center)
		abutment_size.append(size)
		abutment_yaw.append(yaw)

