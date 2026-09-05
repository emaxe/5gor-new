class_name RoadMarkings
extends RefCounted
## Осевая разметка, стоп-линии и зебры по графу дорог.
##
## Отдаёт не меш, а списки `Transform3D` — ровно в той форме, которую ждёт
## `CityBuilder._add_multimesh(PropMeshes.road_dash(), ...)`
## (`city_builder.gd:192-247`): разметка живёт в MultiMesh ради draw calls, и
## переезд на граф не должен эту раскладку ломать. Логика штриха, стоп-линии и
## шести полос зебры здесь та же, что там; меняется только источник координат —
## вместо девяти осей сетки это рёбра и подходы графа.
##
## [b]Заглушка до этапа 8.[/b] Сегодня зебры выводятся из `PedGraph.crossings`
## (`city_planner.gd:143`), а `PedGraph` целиком построен на сетке 9x9 и будет
## переписан на граф этапом 8. Пока `crossings` выводится тривиально: по
## переходу на каждый подход узла степени >= 3. Это ЗАГЛУШКА, а не проект
## пешеходной сети — ни гейтов светофора, ни связи с тротуарными узлами, ни
## нерегулируемых переходов посреди квартала здесь нет. Этап 8 обязан заменить
## `_stub_crossings()` настоящим списком переходов; форма записи (`center`,
## `yaw`, `width`) выбрана так, чтобы `_zebra()` от замены не изменился.

## Шаг штриха осевой, м — как в `city_builder.gd:193`.
const DASH_STEP := 6.4
## Отступ штрихов от горловины узла, м: разметка прерывается перед
## перекрёстком, как на настоящей дороге. Больше, чем вынос зебры плюс её
## половина длины (2.6 + 1.7), — иначе штрих ложится поперёк перехода.
const DASH_CLEAR := 7.0
## Уже этого полотна осевой разметки нет: переулок и подъездной проезд
## однополосные (W_LANE = 8 м в топологии).
const DASH_MIN_WIDTH := 10.0

## Вынос зебры от кромки перекрёстка, м. Половина длины полосы — 1.7 м
## (`PropMeshes.zebra_stripe`, 3.4 м вдоль движения), плюс запас.
const ZEBRA_SETBACK := 2.6
## Шаг полос зебры, м — как в `city_builder.gd:245`.
const ZEBRA_PITCH := 1.1
## Доля ширины полотна, которую занимает зебра. 0.55 воспроизводит нынешний
## вид: на 12-метровой улице получается шесть полос, как сейчас.
const ZEBRA_COVER := 0.55
const ZEBRA_MIN := 4
const ZEBRA_MAX := 12

## Вынос стоп-линии от кромки перекрёстка, м — за зеброй, как по ПДД.
const STOP_SETBACK := 5.2
## Толщина стоп-линии, м, и длина заготовки штриха вдоль полосы
## (`PropMeshes.road_dash` — 0.25 x 3.2 м).
const STOP_THICKNESS := 0.4
const DASH_MESH_WIDTH := 0.25
const DASH_MESH_LENGTH := 3.2

var dashes: Array[Transform3D] = []
var stop_lines: Array[Transform3D] = []
var zebra: Array[Transform3D] = []
## Переходы-заглушка: `{node, approach, edge, center, yaw, width}`.
var crossings: Array[Dictionary] = []

var _graph: CityGraph
var _mesh: RoadMesh


## `signal_nodes` — регулируемые узлы (`PyatigorskTopology.signal_nodes`):
## стоп-линия рисуется только там, где есть что останавливать.
func _init(graph: CityGraph, mesh: RoadMesh,
		signal_nodes: PackedInt32Array = PackedInt32Array()) -> void:
	_graph = graph
	_mesh = mesh
	_stub_crossings()
	_build_dashes()
	_build_zebra()
	_build_stop_lines(signal_nodes)


# ============================================================================
# Источник данных
# ============================================================================

## Тривиальный вывод переходов из геометрии узла — см. оговорку в шапке.
func _stub_crossings() -> void:
	for n in _graph.node_count():
		if _graph.node_kind(n) == CityGraph.NodeKind.ROUNDABOUT:
			continue
		var deg := _graph.node_degree(n)
		if deg < 3:
			continue
		for k in deg:
			var e := _graph.approach_edge(n, k)
			if not _mesh.has_sidewalk(e):
				continue
			var dir := _mesh.cut_dir(n, k)
			var center := _mesh.cut_point(n, k) + dir * ZEBRA_SETBACK
			center.y += CityMesher.Y_MARKING
			crossings.append({
				"node": n, "approach": k, "edge": e,
				"center": center,
				# Полосы зебры идут ВДОЛЬ движения, пешеход шагает поперёк них.
				"yaw": atan2(dir.x, dir.z),
				"width": _graph.edge_width(e),
			})


# ============================================================================
# Разметка
# ============================================================================

func _build_dashes() -> void:
	for e in _graph.edge_count():
		if _graph.edge_width(e) < DASH_MIN_WIDTH:
			continue
		if _graph.edge_kind(e) == CityGraph.EdgeKind.BRIDGE:
			continue
		var pts := _mesh.road_polyline(e)
		if pts.size() < 2:
			continue
		var total := _arc_length(pts)
		var s := DASH_CLEAR
		while s <= total - DASH_CLEAR:
			var at := _sample(pts, s)
			var dir := _tangent(pts, s)
			var pos := at + Vector3(0.0, CityMesher.Y_MARKING, 0.0)
			dashes.append(Transform3D(
				Basis.from_euler(Vector3(0.0, atan2(dir.x, dir.z), 0.0)), pos))
			s += DASH_STEP


func _build_zebra() -> void:
	for c: Dictionary in crossings:
		var basis := Basis.from_euler(Vector3(0.0, float(c["yaw"]), 0.0))
		var center: Vector3 = c["center"]
		var width: float = c["width"]
		var count := clampi(roundi(width * ZEBRA_COVER / ZEBRA_PITCH),
			ZEBRA_MIN, ZEBRA_MAX)
		for k in count:
			var offset := (float(k) - float(count - 1) * 0.5) * ZEBRA_PITCH
			zebra.append(Transform3D(basis,
				center + basis * Vector3(offset, 0.0, 0.0)))


## Стоп-линия занимает свою половину полотна: встречная полоса свободна.
func _build_stop_lines(signal_nodes: PackedInt32Array) -> void:
	for n in signal_nodes:
		for k in _graph.node_degree(n):
			var e := _graph.approach_edge(n, k)
			if not _mesh.has_sidewalk(e):
				continue
			var dir := _mesh.cut_dir(n, k)
			var normal := dir.cross(Vector3.UP)
			var half := _graph.edge_width(e) * 0.5
			# Подъезжающий едет ПРОТИВ dir, его правая полоса — со стороны -n.
			var center := _mesh.cut_point(n, k) + dir * STOP_SETBACK \
				- normal * (half * 0.5)
			center.y += CityMesher.Y_MARKING
			# Заготовка штриха вытянута вдоль своей оси Z: разворачиваем её
			# поперёк дороги и растягиваем на полполотна.
			var basis := Basis.from_euler(
				Vector3(0.0, atan2(normal.x, normal.z), 0.0))
			stop_lines.append(Transform3D(basis.scaled(Vector3(
				STOP_THICKNESS / DASH_MESH_WIDTH, 1.0,
				half / DASH_MESH_LENGTH)), center))


# ============================================================================
# Служебное
# ============================================================================

static func _arc_length(pts: PackedVector3Array) -> float:
	var acc := 0.0
	for i in range(1, pts.size()):
		acc += _plan(pts[i - 1], pts[i])
	return acc


static func _plan(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


static func _sample(pts: PackedVector3Array, s: float) -> Vector3:
	var acc := 0.0
	for i in range(1, pts.size()):
		var seg := _plan(pts[i - 1], pts[i])
		if acc + seg >= s and seg > 0.0:
			return pts[i - 1].lerp(pts[i], (s - acc) / seg)
		acc += seg
	return pts[pts.size() - 1]


static func _tangent(pts: PackedVector3Array, s: float) -> Vector3:
	var acc := 0.0
	for i in range(1, pts.size()):
		var seg := _plan(pts[i - 1], pts[i])
		if acc + seg >= s and seg > 0.0:
			var d := pts[i] - pts[i - 1]
			d.y = 0.0
			return d.normalized()
		acc += seg
	var tail := pts[pts.size() - 1] - pts[pts.size() - 2]
	tail.y = 0.0
	return tail.normalized()
