class_name PedGraph
extends RefCounted
## Граф ходьбы города: тротуарные ленты, углы кварталов, переходы, jwalk.
##
## Порт pedgraph.js с четырьмя изменениями:
##
##  1. Узлы стоят в УГЛАХ кварталов (x±8, z±8), а не по центру пересекающей
##     дороги. В оригинале тротуарный узел на перекрёстке лежал в точке
##     (r±8, axes[j]) — то есть посреди поперечной проезжей части, и ходьба
##     вдоль ленты пересекала дорогу мимо зебры. Регрессия
##     test_no_ungated_segment_crosses_roadway это ловит.
##  2. Поиск пути — на встроенном AStar3D (C++), а не ручным Dijkstra:
##     693 узла в GDScript-цикле стоили бы 1-3 мс на запрос.
##  3. id узла — чистая функция от индексов, словарь ключей не хранится.
##  4. Маршрут возвращается парой массивов `points[]` / `gates[]`:
##     gates[i] — светофор, который надо пройти на зелёный, чтобы попасть
##     в points[i], или -1. Агент остаётся тупым автоматом (приём из capital).
##
## Стоимости: walk 0.5 (полсегмента тротуара), cross 2.0 (переход через
## дорогу), jwalk 3.0. Поворот за угол бесплатен: угловой узел общий у двух
## лент, так что «срез угла» — это просто прохождение через узел.

enum Edge { WALK, CROSS, JWALK }
## Ось дороги, которую пересекает переход: Z_ROAD — дорога, по которой машины
## едут вдоль Z (пешеход идёт поперёк, вдоль X).
enum CrossAxis { Z_ROAD, X_ROAD }
## Углы квартала вокруг перекрёстка.
enum Corner { NW, NE, SW, SE }

const COST := {
	Edge.WALK: 0.5,
	Edge.CROSS: 2.0,
	Edge.JWALK: 3.0,
}

const AXES := 9
const SEGMENTS := AXES - 1
## Доля сегментов, где протоптан переход в неположенном месте.
const JWALK_CHANCE := 0.3
## Сид, отдельный от городского: добавление зданий не должно сдвигать jwalk.
const JWALK_SEED := 20260807
## POI дальше этого от узла считается вне сетки (Машук) и отбрасывается.
const POI_MAX_DIST := 40.0

# --- Раскладка идентификаторов ----------------------------------------------
const CORNER_COUNT := AXES * AXES * 4                 # 324
const VMID_BASE := CORNER_COUNT                       # 324
const VMID_COUNT := AXES * 2 * SEGMENTS               # 144
const HMID_BASE := VMID_BASE + VMID_COUNT             # 468
const NODE_COUNT := HMID_BASE + VMID_COUNT            # 612

var ped_side := 8.0
var axes: PackedFloat32Array = PackedFloat32Array()

## Граф без jwalk — для законопослушных пешеходов.
var legal: PedAStar
## Граф со всеми рёбрами — для нарушителей.
var full: PedAStar

var _edge_kind: Dictionary[int, int] = {}
var _edge_gate: Dictionary[int, int] = {}
var _positions: PackedVector3Array = PackedVector3Array()
## Переходы как данные: из этого списка рисуются зебры, стойки и линзы —
## разметка не может разъехаться с логикой.
var crossings: Array[Dictionary] = []

var poi_nodes: PackedInt32Array = PackedInt32Array()
var poi_tags: PackedStringArray = PackedStringArray()


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


func _init(field: CityField = null) -> void:
	if field != null:
		axes = field.road_axes
		ped_side = field.road_half + field.sidewalk * 0.5
	else:
		axes = PackedFloat32Array()
		for i in AXES:
			axes.append(-256.0 + i * 64.0)
	_build()


# --- Идентификаторы ---------------------------------------------------------

## Угловой узел квартала у перекрёстка (i, j). corner — значение Corner.
##
## Параметр объявлен как int, а не как Corner: у статических методов GDScript
## внутренний enum и `PedGraph.Corner` снаружи считаются разными типами.
static func corner_id(i: int, j: int, corner: int) -> int:
	return (i * AXES + j) * 4 + corner


## Серединный узел вертикальной ленты: дорога вдоль Z при x = axes[road],
## сторона side ∈ {0: запад, 1: восток}, сегмент seg между axes[seg] и axes[seg+1].
static func vmid_id(road: int, side: int, seg: int) -> int:
	return VMID_BASE + (road * 2 + side) * SEGMENTS + seg


static func hmid_id(road: int, side: int, seg: int) -> int:
	return HMID_BASE + (road * 2 + side) * SEGMENTS + seg


static func edge_key(a: int, b: int) -> int:
	return mini(a, b) * 1024 + maxi(a, b)


## Гейт: перекрёсток + ось пересекаемой дороги.
static func gate_id(i: int, j: int, cross_axis: int) -> int:
	return (i * AXES + j) * 2 + cross_axis


static func gate_intersection(gate: int) -> Vector2i:
	@warning_ignore("integer_division")
	var idx: int = gate / 2
	@warning_ignore("integer_division")
	var i: int = idx / AXES
	return Vector2i(i, idx % AXES)


static func gate_axis(gate: int) -> int:
	return CrossAxis.X_ROAD if gate % 2 == 1 else CrossAxis.Z_ROAD


## Регулируется ли перекрёсток светофором.
##
## В оригинале стойки ставятся через один перекрёсток (citygen.js:2691:
## `for i = 1; i < 8; i += 2`), то есть на нечётных индексах сетки. Остальные
## перекрёстки нерегулируемые: там переход существует, но гейта нет и
## пешеход обязан пропускать транспорт сам.
static func is_signalized(i: int, j: int) -> bool:
	return i % 2 == 1 and j % 2 == 1 and i < AXES - 1 and j < AXES - 1


static func corner_offset(corner: int, side: float) -> Vector2:
	match corner:
		Corner.NW: return Vector2(-side, -side)
		Corner.NE: return Vector2(side, -side)
		Corner.SW: return Vector2(-side, side)
		_: return Vector2(side, side)


# --- Построение -------------------------------------------------------------

func _build() -> void:
	legal = PedAStar.new()
	legal.bind_graph(self)
	full = PedAStar.new()
	full.bind_graph(self)
	_positions.resize(NODE_COUNT)

	for i in AXES:
		for j in AXES:
			for c in 4:
				var off := corner_offset(c, ped_side)
				_add_node(corner_id(i, j, c),
					Vector3(axes[i] + off.x, 0.0, axes[j] + off.y))

	for road in AXES:
		for side in 2:
			var sx := axes[road] + (ped_side if side == 1 else -ped_side)
			var sz := axes[road] + (ped_side if side == 1 else -ped_side)
			for seg in SEGMENTS:
				var zm := (axes[seg] + axes[seg + 1]) * 0.5
				var xm := (axes[seg] + axes[seg + 1]) * 0.5
				_add_node(vmid_id(road, side, seg), Vector3(sx, 0.0, zm))
				_add_node(hmid_id(road, side, seg), Vector3(xm, 0.0, sz))

	_connect_ribbons()
	_connect_crossings()
	_connect_jwalks()


func _add_node(id: int, pos: Vector3) -> void:
	_positions[id] = pos
	legal.add_point(id, pos)
	full.add_point(id, pos)


func _link(a: int, b: int, kind: Edge, gate: int = -1) -> void:
	var key := edge_key(a, b)
	_edge_kind[key] = int(kind)
	if gate >= 0:
		_edge_gate[key] = gate
	if kind != Edge.JWALK:
		legal.connect_points(a, b)
	full.connect_points(a, b)


## Ленты тротуара идут ТОЛЬКО между углами соседних перекрёстков и никогда
## не пересекают проезжую часть: сегмент длиной cell − 2·ped_side (48 м).
func _connect_ribbons() -> void:
	for road in AXES:
		for side in 2:
			for seg in SEGMENTS:
				# Вертикальная лента: от юго-* угла перекрёстка seg
				# к северо-* углу перекрёстка seg+1.
				var lower: int = Corner.SW if side == 0 else Corner.SE
				var upper: int = Corner.NW if side == 0 else Corner.NE
				var a := corner_id(road, seg, lower)
				var m := vmid_id(road, side, seg)
				var b := corner_id(road, seg + 1, upper)
				_link(a, m, Edge.WALK)
				_link(m, b, Edge.WALK)

				# Горизонтальная лента: от восточного угла перекрёстка seg
				# к западному углу перекрёстка seg+1.
				var east: int = Corner.NE if side == 0 else Corner.SE
				var west: int = Corner.NW if side == 0 else Corner.SW
				var ha := corner_id(seg, road, east)
				var hm := hmid_id(road, side, seg)
				var hb := corner_id(seg + 1, road, west)
				_link(ha, hm, Edge.WALK)
				_link(hm, hb, Edge.WALK)


## Переходы: по одному на каждую сторону перекрёстка. Список сохраняется —
## из него генератор рисует зебры и стойки светофоров.
func _connect_crossings() -> void:
	crossings.clear()
	for i in AXES:
		for j in AXES:
			var signalized := is_signalized(i, j)
			var gate_z := gate_id(i, j, CrossAxis.Z_ROAD) if signalized else -1
			var gate_x := gate_id(i, j, CrossAxis.X_ROAD) if signalized else -1
			# Поперёк вертикальной дороги (пешеход идёт вдоль X).
			_add_crossing(i, j, Corner.NW, Corner.NE, gate_z, CrossAxis.Z_ROAD)
			_add_crossing(i, j, Corner.SW, Corner.SE, gate_z, CrossAxis.Z_ROAD)
			# Поперёк горизонтальной дороги (пешеход идёт вдоль Z).
			_add_crossing(i, j, Corner.NW, Corner.SW, gate_x, CrossAxis.X_ROAD)
			_add_crossing(i, j, Corner.NE, Corner.SE, gate_x, CrossAxis.X_ROAD)


func _add_crossing(i: int, j: int, a: int, b: int, gate: int,
		cross_axis: int) -> void:
	var ia := corner_id(i, j, a)
	var ib := corner_id(i, j, b)
	_link(ia, ib, Edge.CROSS, gate)
	crossings.append({
		"a": ia, "b": ib, "gate": gate, "axis": int(cross_axis),
		"i": i, "j": j,
		"center": (_positions[ia] + _positions[ib]) * 0.5,
	})


## Нерегулируемый переход: разметка есть, светофора нет.
func is_unsignalized_crossing(a: int, b: int) -> bool:
	return edge_kind(a, b) == int(Edge.CROSS) and edge_gate(a, b) < 0


## Переход в неположенном месте — посреди квартала, между серединными узлами.
func _connect_jwalks() -> void:
	var rng := SeededRng.new(JWALK_SEED)
	for road in AXES:
		for seg in SEGMENTS:
			if rng.chance(JWALK_CHANCE):
				_link(vmid_id(road, 0, seg), vmid_id(road, 1, seg), Edge.JWALK)
	for road in AXES:
		for seg in SEGMENTS:
			if rng.chance(JWALK_CHANCE):
				_link(hmid_id(road, 0, seg), hmid_id(road, 1, seg), Edge.JWALK)


# --- Запросы ----------------------------------------------------------------

func position_of(id: int) -> Vector3:
	return _positions[id]


func edge_kind(a: int, b: int) -> int:
	return _edge_kind.get(edge_key(a, b), -1)


func edge_cost(a: int, b: int) -> float:
	var kind := edge_kind(a, b)
	return 1.0 if kind < 0 else COST[kind]


## Гейт светофора для ребра, или -1 если сигнал не нужен.
func edge_gate(a: int, b: int) -> int:
	return _edge_gate.get(edge_key(a, b), -1)


func heuristic(from_id: int, to_id: int) -> float:
	# Заниженная оценка в единицах стоимости: сегмент тротуара 48 м стоит
	# 2 x WALK, значит метр — не дороже 1/48. Оптимальность A* сохраняется.
	return _positions[from_id].distance_to(_positions[to_id]) * (COST[Edge.WALK] / 32.0)


func node_count() -> int:
	return NODE_COUNT


# --- Поиск узлов ------------------------------------------------------------

## Ближайший узел тротуара. O(1): кандидаты берутся из индексов сетки,
## а не перебором всех узлов.
func nearest_node(x: float, z: float) -> int:
	var best_id := -1
	var best_d := INF
	var target := Vector3(x, 0.0, z)
	for i in _near_axes(x):
		for j in _near_axes(z):
			for c in 4:
				var id := corner_id(i, j, c)
				var d := _positions[id].distance_squared_to(target)
				if d < best_d:
					best_d = d
					best_id = id
	# Серединные узлы ближайших лент.
	for road in _near_axes(x):
		for side in 2:
			for seg in _near_segments(z):
				var id := vmid_id(road, side, seg)
				var d := _positions[id].distance_squared_to(target)
				if d < best_d:
					best_d = d
					best_id = id
	for road in _near_axes(z):
		for side in 2:
			for seg in _near_segments(x):
				var id := hmid_id(road, side, seg)
				var d := _positions[id].distance_squared_to(target)
				if d < best_d:
					best_d = d
					best_id = id
	return best_id


func _near_axes(v: float) -> PackedInt32Array:
	var step := axes[1] - axes[0]
	var t := (v - axes[0]) / step
	var lo := clampi(floori(t), 0, AXES - 1)
	var hi := clampi(lo + 1, 0, AXES - 1)
	return PackedInt32Array([lo]) if lo == hi else PackedInt32Array([lo, hi])


func _near_segments(v: float) -> PackedInt32Array:
	var step := axes[1] - axes[0]
	var t := (v - axes[0]) / step
	var seg := clampi(floori(t), 0, SEGMENTS - 1)
	return PackedInt32Array([seg])


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
