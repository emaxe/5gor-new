class_name BlockPlanner
extends RefCounted
## Периметральная застройка полигональных кварталов (`CityBlocks`).
##
## Обобщение `CityPlanner._plan_block*` (city_planner.gd:222-309) с `Rect2` на
## произвольный полигон. Сам приём остаётся прежним и сознательно отличается
## от оригинала: там дома разбрасывались случайно по кварталу и выходило 1-2
## дома на квартал — город читался редким макетом; здесь курсор идёт вдоль
## фронта улицы, ставит корпуса с разрывами, а внутри остаётся двор.
##
## Меняется одно: «сторона прямоугольника» превращается в ребро полигона.
## Курсор идёт по длине полилинии РЕАЛЬНОЙ улицы, дом отступает от неё на
## полуширину полотна плюс тротуар и поворачивается по касательной, а не
## выравнивается по осям X/Z. На улице, идущей под углом (бульвар Гагарина,
## дуга у подножия Машука), осеаксиальный дом стоял бы к улице углом.
##
## Фаза чистая: только `Packed*Array`, ни одной ноды — как и `CityPlanner`,
## уходит в `WorkerThreadPool`. Пропс, деревья и точки подачи остаются за
## `CityPlanner`, здесь только застройка.

## Минимальный запас от габарита дома до кромки полотна, м. На фасадной
## линии он равен ширине тротуара (4 м); 2 м — половина тротуара, меньше
## значит дом занял тротуар и вышел к проезжей части.
const MIN_ROAD_CLEARANCE := 2.0
## Радиус поиска дорог вокруг угла дома, м: самый глубокий корпус (17 м) плюс
## самое широкое полотно (18 м) — за этой границей полотно до дома не достаёт.
const ROAD_SEARCH := 40.0
## Участок достопримечательности вокруг её точки, м. Сцены строят геометрию
## вокруг своей точки: у Цветника скамьи стоят в 15.8 м от центра
## (`world/landmarks/cvetnik.gd:28`), у Верхнего рынка торговые ряды — в 17 м
## (`rynok.gd:20`). 20 м покрывают самую крупную с запасом.
const LANDMARK_PLOT := 20.0
## Габариты корпуса, м: длина фронта и глубина (city_planner.gd:261-264).
const WIDTH_MIN := 9.0
const WIDTH_MAX := 22.0
const DEPTH_MIN := 9.0
const DEPTH_SPAN := 8.0
## Мельче этой глубины корпус не ставится: 6 м — одна комната с коридором,
## всё, что уже, это уже не дом, а забор вдоль улицы.
const DEPTH_TIGHT := 6.0
## Двор между встречными фронтами квартала, м: проезд к подъездам и место
## под деревья, которые сажает `CityPlanner`.
const YARD_MIN := 4.0
## Предохранитель цикла на одно ребро. Ребро графа бывает длиной 130 м
## (проспект Кирова между Пастухова и вокзалом), при шаге ~16 м это восемь
## корпусов; 24 — потолок с запасом, а не рабочее число.
const SIDE_GUARD := 24
## Зазор между соседними корпусами и вокруг дворового, м.
const FRONT_GAP := 1.0
const COURTYARD_GAP := 2.5

var blocks: CityBlocks
var graph: CityGraph
var field: CityField
var districts: DistrictCatalog

var _plan: CityPlan
var _rng: SeededRng
## Островки колец и участки достопримечательностей: центр в xy, радиус в z.
var _plots: PackedVector3Array = PackedVector3Array()


func _init(city_blocks: CityBlocks, city_field: CityField,
		district_catalog: DistrictCatalog) -> void:
	blocks = city_blocks
	graph = city_blocks.graph
	field = city_field
	districts = district_catalog


## Заполняет здания в готовом плане. План и генератор приходят снаружи:
## застройка — одна из фаз `CityPlan`, а не отдельный план.
func plan(city_plan: CityPlan, rng: SeededRng,
		landmark_node: Dictionary[StringName, int]) -> void:
	_plan = city_plan
	_rng = rng
	_collect_plots(landmark_node)
	for b in blocks.count():
		# Особый квартал (парк, Провал, Грот) застройке не подлежит — тот же
		# смысл, что у `block_special()`, только по привязкам этапа 2.
		if not blocks.special(b).is_empty():
			continue
		var d := districts.get_district(blocks.district(b))
		if d == null:
			continue
		_plan_block(b, d)


## Места, свободные от застройки помимо полотна: остров кольца — это
## проезжая часть, которой в графе нет ребром, участок достопримечательности
## занят её сценой, а рампа с пролётом не видны обычной проверке запаса до
## полотна (см. `elevated_corridors`).
func _collect_plots(landmark_node: Dictionary[StringName, int]) -> void:
	_plots = PackedVector3Array()
	for n in graph.node_count():
		if graph.node_kind(n) == CityGraph.NodeKind.ROUNDABOUT:
			var p := graph.node_position(n)
			_plots.append(Vector3(p.x, p.z, graph.node_radius(n) + field.sidewalk))
	_plots.append_array(elevated_corridors(graph, field.sidewalk))
	# Порядок по алфавиту, а не по словарю: сам список на результат не влияет,
	# но фаза обязана быть воспроизводимой целиком (`CityBlocks.sorted_ids`
	# — там же про то, почему `StringName` нельзя сортировать напрямую).
	for id in CityBlocks.sorted_ids(landmark_node):
		var p := graph.node_position(landmark_node[id])
		_plots.append(Vector3(p.x, p.z, LANDMARK_PLOT))


## Коридор вдоль рампы и пролёта — цепочка кругов (центр xy, радиус z),
## закрывающая полотно от застройки и уличного пропса.
##
## Обычная проверка запаса (`CityGraph.road_clearance`) их пропускает, и не по
## ошибке: она сравнивает высоту полотна с высотой запроса и отбрасывает всё,
## что отличается больше чем на `LEVEL_TOLERANCE`, — иначе рядом с опорой
## путепровода нельзя было бы построить ничего. Но у рампы и пролёта полотно
## поднимается ОТ ЗЕМЛИ: под верхней половиной рампы лежит не проезд, а
## насыпь, и дом там встал бы прямо в откос. Поэтому их коридор задаётся
## явными кругами, а не выводится из запроса о запасе.
##
## Шаг вдвое мельче радиуса круга: цепочка обязана быть сплошной, а не
## пунктиром с дырами между кругами.
static func elevated_corridors(graph: CityGraph, walk: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for e in graph.edge_count():
		var kind := graph.edge_kind(e)
		if kind != CityGraph.EdgeKind.RAMP and kind != CityGraph.EdgeKind.BRIDGE:
			continue
		var radius := graph.edge_width(e) * 0.5 + walk
		var pts := graph.edge_polyline(e)
		for i in range(1, pts.size()):
			var a := Vector2(pts[i - 1].x, pts[i - 1].z)
			var b := Vector2(pts[i].x, pts[i].z)
			var steps := maxi(1, ceili(a.distance_to(b) / (radius * 0.5)))
			for k in steps + 1:
				var p := a.lerp(b, float(k) / float(steps))
				out.append(Vector3(p.x, p.y, radius))
	return out


# --- Квартал ----------------------------------------------------------------

func _plan_block(block: int, d: DistrictData) -> void:
	var placed: Array[PackedVector2Array] = []
	# Чем плотнее район, тем реже разрывы во фронте и глубже корпуса.
	var density: float = clampf(d.density / 4.0, 0.25, 1.0)
	var side_chance := 0.55 + 0.4 * density
	for k in blocks.boundary_count(block):
		if not _rng.chance(side_chance):
			continue
		_plan_block_side(block, k, d, density, placed)
	# Дворовый корпус — в плотных районах.
	if _rng.chance(0.25 * density) and not placed.is_empty():
		_plan_courtyard(block, d, placed)


## Ряд домов вдоль одного ребра полигона — аналог `_plan_block_side()` для
## стороны `Rect2`. Курсор идёт по длине полилинии в плане, дом встаёт
## серединой фронта на курсор.
func _plan_block_side(block: int, k: int, d: DistrictData, density: float,
		placed: Array[PackedVector2Array]) -> void:
	var pts := blocks.boundary_plan(block, k)
	var edge := blocks.boundary_edge(block, k)
	# Фасадная линия: полуширина полотна плюс тротуар. Ровно тот же отступ,
	# что в сетке оригинала (ось дороги -256, квартал с -246 при полотне 6 м
	# и тротуаре 4 м, city_planner.gd:18).
	var setback := graph.edge_width(edge) * 0.5 + field.sidewalk
	var from := _corner_margin(blocks.boundary_node(block, k), edge)
	var to := _plan_length(pts) - _corner_margin(
		blocks.boundary_node(block, (k + 1) % blocks.boundary_count(block)), edge)
	# Сдвиг начала фронта мал намеренно: между углами настоящего квартала
	# 18-25 м свободного фронта (40 м от оси до оси минус два угловых
	# отступа), и разбег в 5 м, как в сетке с её 44-метровой стороной,
	# съедал бы половину места под единственный дом.
	var cursor := from + _rng.randf_range(0.0, 2.0)
	var guard := 0
	while cursor < to - WIDTH_MIN and guard < SIDE_GUARD:
		guard += 1
		# Границы диапазона, а не обрезка результата: короткий фронт получает
		# дом нормальных пропорций, а не обрубок в 8 м.
		var w := _rng.randf_range(WIDTH_MIN, minf(WIDTH_MAX, to - cursor))
		_place_along(pts, cursor + w * 0.5, w, setback, block, d, density,
			placed, FRONT_GAP)
		# Разрыв между домами: в плотной застройке фасады смыкаются.
		cursor += w + _rng.randf_range(0.5, 2.0 + 6.0 * (1.0 - density))


## Отступ от узла, с которого начинается фронт: на перекрёстке место занято
## ПОПЕРЕЧНОЙ улицей с её собственным тротуаром, поэтому берётся самая
## широкая из сходящихся улиц, кроме той, вдоль которой идёт фронт. У кольца
## добавляется его радиус: остров — тоже проезжая часть.
func _corner_margin(node: int, along: int) -> float:
	var widest := 0.0
	for k in graph.node_degree(node):
		var e := graph.approach_edge(node, k)
		if e != along:
			widest = maxf(widest, graph.edge_width(e))
	return widest * 0.5 + field.sidewalk + graph.node_radius(node)


## Корпус фронтом вдоль улицы: фасад ставится на хорду участка полилинии,
## занятого домом, и отступает от него внутрь квартала.
##
## Фасад прямой, поэтому и равняется он на хорду, а не на касательную в
## середине: на кривой улице (бульвар Гагарина, дуга у подножия) касательная
## середины разворачивает дом так, что концы фасада уходят на полотно.
## К отступу добавляется стрелка прогиба — насколько ось улицы заходит внутрь
## квартала между концами хорды: тогда весь фасад отстоит от полотна не
## меньше, чем на тротуар, а не только его середина.
##
## Глубина берётся не вслепую: в историческом центре квартал бывает 33 м от
## оси до оси, и после двух фасадных отступов внутри остаётся 13 м — дом
## занимает всю глубину квартала и выходит фасадами на обе улицы, как оно в
## городе и есть. Слепой диапазон 9-17 м там не поставил бы ни одного дома.
func _place_along(pts: PackedVector2Array, s: float, w: float, setback: float,
		block: int, d: DistrictData, density: float,
		placed: Array[PackedVector2Array], gap: float) -> void:
	var half := w * 0.5
	var a := _point_at(pts, s - half)
	var b := _point_at(pts, s + half)
	var chord := b - a
	if chord.length_squared() < 1e-6:
		return
	var along := chord.normalized()
	# Внутренность квартала лежит слева по обходу (площадь полигона
	# положительная), то есть в стороне нормали (-tz, tx).
	var inward := Vector2(-along.y, along.x)
	var facade := setback + _sagitta(pts, s - half, s + half, a, inward)
	# Замер по трём лучам — из середины фронта и из обоих его концов: квартал
	# сужается к углам, и корпус, промеренный только по центру, упирался бы
	# дальним углом в поперечную улицу.
	var free: float = minf(_free_depth(block, a, inward, facade),
		_free_depth(block, b, inward, facade))
	free = minf(free, _free_depth(block, (a + b) * 0.5, inward, facade))
	# Если глубины хватает на два фронта с двором между ними, корпус берёт не
	# больше половины: иначе один дом проходит квартал насквозь и улица
	# напротив остаётся без фасадов. Если не хватает — берёт всю, как
	# исторический центр и построен.
	var cap := free
	if free >= DEPTH_MIN * 2.0 + YARD_MIN:
		cap = (free - YARD_MIN) * 0.5
	if cap < DEPTH_TIGHT:
		return
	var depth: float = minf(
		_rng.randf_range(DEPTH_MIN, DEPTH_MIN + DEPTH_SPAN * density), cap)
	var center := (a + b) * 0.5 + inward * (facade + depth * 0.5)
	# Локальная +X вдоль фасада, локальная +Z вглубь квартала.
	_try_place(center, w, depth, atan2(-along.y, along.x), block, d,
		placed, gap)


## Стрелка прогиба: самый глубокий заход оси улицы внутрь квартала между
## концами хорды. Считается по вершинам полилинии — между ними улица прямая.
func _sagitta(pts: PackedVector2Array, s0: float, s1: float, a: Vector2,
		inward: Vector2) -> float:
	var from := int(_locate(pts, s0).x)
	var to := int(_locate(pts, s1).x)
	var sag := 0.0
	for i in range(from + 1, to + 1):
		sag = maxf(sag, inward.dot(pts[i] - a))
	return sag


## Свободная глубина от фасадной линии до фасадной линии противоположной
## стороны квартала.
func _free_depth(block: int, from: Vector2, dir: Vector2,
		setback: float) -> float:
	var room := _room_inward(block, from, dir)
	return room.x - setback - (room.y * 0.5 + field.sidewalk)


## Луч внутрь квартала до противоположной стороны: расстояние и ширина
## полотна той стороны.
func _room_inward(block: int, from: Vector2, dir: Vector2) -> Vector2:
	var n := blocks.polygon_size(block)
	var best := INF
	var width := 0.0
	for k in n:
		var a := blocks.polygon_point(block, k)
		var seg := blocks.polygon_point(block, (k + 1) % n) - a
		var denom := dir.x * seg.y - dir.y * seg.x
		if absf(denom) < 1e-9:
			continue
		var diff := a - from
		var t := (diff.x * seg.y - diff.y * seg.x) / denom
		var u := (diff.x * dir.y - diff.y * dir.x) / denom
		# t > 0.01: точка старта лежит на самой стороне, и своё же ребро
		# не должно считаться противоположным.
		if t <= 0.01 or u < 0.0 or u > 1.0 or t >= best:
			continue
		best = t
		width = graph.edge_width(blocks.polygon_edge(block, k))
	return Vector2(best, width)


## Дворовый корпус: в середине квартала, вдоль его самой длинной улицы.
## Прямоугольник по осям X/Z (как было в сетке) во дворе непрямоугольного
## квартала встал бы наискось к обоим фронтам.
func _plan_courtyard(block: int, d: DistrictData,
		placed: Array[PackedVector2Array]) -> void:
	var w := _rng.randf_range(9.0, 15.0)
	var depth := _rng.randf_range(9.0, 15.0)
	var center := blocks.centroid(block) + Vector2(
		_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0))
	_try_place(center, w, depth, _main_street_yaw(block), block, d, placed,
		COURTYARD_GAP)


func _main_street_yaw(block: int) -> float:
	var best := 0.0
	var best_len := -1.0
	for k in blocks.boundary_count(block):
		var e := blocks.boundary_edge(block, k)
		if graph.edge_length(e) <= best_len:
			continue
		best_len = graph.edge_length(e)
		var pts := blocks.boundary_plan(block, k)
		var dir := (pts[pts.size() - 1] - pts[0]).normalized()
		best = atan2(-dir.y, dir.x)
	return best


# --- Проверка места ---------------------------------------------------------

func _try_place(center: Vector2, w: float, depth: float, yaw: float,
		block: int, d: DistrictData, placed: Array[PackedVector2Array],
		gap: float) -> void:
	var corners := _corners(center, w, depth, yaw)
	if not _inside_block(block, corners):
		return
	if not _off_road(corners, center):
		return
	if not _off_plots(corners, center):
		return
	var grown := _corners(center, w + gap * 2.0, depth + gap * 2.0, yaw)
	for other in placed:
		if _obb_overlap(grown, other):
			return
	placed.append(corners)

	var facade := _rng.pick_color(d.palette.facades)
	var height := _rng.randf_range(d.height_min, d.height_max)
	# Скатная кровля бывает только у малоэтажных домов: на восьмиэтажке
	# в Пятигорске плоская крыша.
	var roof_kind := 1 if height < 13.0 and _rng.chance(0.55) else 0
	_plan.add_building(
		Vector4(center.x - w * 0.5, center.y - depth * 0.5,
			center.x + w * 0.5, center.y + depth * 0.5),
		height,
		facade,
		d.palette.roof_color(_rng.pick_color(d.palette.facades)),
		_district_index(blocks.district(block)),
		roof_kind,
		yaw,
		_ground_under(corners))


## Все четыре угла внутри полигона: иначе дом вылезает в соседний квартал
## или на перекрёсток.
func _inside_block(block: int, corners: PackedVector2Array) -> bool:
	for c in corners:
		if not blocks.contains(block, c):
			return false
	return true


## Ни один угол и центр не ближе `MIN_ROAD_CLEARANCE` к кромке любого
## полотна. Проверяется именно запас до кромки, а не расстояние до ближайшей
## оси: рядом с проспектом узкий проезд может оказаться ближе, оставаясь
## безопасным (`CityGraph.road_clearance`).
func _off_road(corners: PackedVector2Array, center: Vector2) -> bool:
	if graph.road_clearance(Vector3(center.x, 0.0, center.y), ROAD_SEARCH) \
			< MIN_ROAD_CLEARANCE:
		return false
	for c in corners:
		if graph.road_clearance(Vector3(c.x, 0.0, c.y), ROAD_SEARCH) \
				< MIN_ROAD_CLEARANCE:
			return false
	return true


func _off_plots(corners: PackedVector2Array, center: Vector2) -> bool:
	for plot in _plots:
		var p := Vector2(plot.x, plot.y)
		if center.distance_to(p) < plot.z:
			return false
		for c in corners:
			if c.distance_to(p) < plot.z:
				return false
	return true


## Высота земли под четырьмя углами — данные цоколю (`CityMesher`).
func _ground_under(corners: PackedVector2Array) -> Vector4:
	return Vector4(
		field.height_at(corners[0].x, corners[0].y),
		field.height_at(corners[1].x, corners[1].y),
		field.height_at(corners[2].x, corners[2].y),
		field.height_at(corners[3].x, corners[3].y))


func _district_index(id: StringName) -> int:
	for i in districts.items.size():
		if districts.items[i].id == id:
			return i
	return 0


# --- Геометрия --------------------------------------------------------------

## Углы повёрнутого габарита в порядке (-x,-z), (+x,-z), (+x,+z), (-x,+z)
## локальных осей — тот же порядок, что у `CityPlan.building_corners()`.
static func _corners(center: Vector2, w: float, depth: float,
		yaw: float) -> PackedVector2Array:
	var ex := Vector2(cos(yaw), -sin(yaw)) * (w * 0.5)
	var ez := Vector2(sin(yaw), cos(yaw)) * (depth * 0.5)
	return PackedVector2Array([
		center - ex - ez, center + ex - ez, center + ex + ez, center - ex + ez])


## Пересечение двух повёрнутых прямоугольников (SAT). У прямоугольника
## нормали сторон совпадают с направлениями смежных сторон, поэтому осей
## всего четыре — по две на прямоугольник.
static func _obb_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	return not (_separates(a, a, b) or _separates(b, a, b))


static func _separates(axes_from: PackedVector2Array, a: PackedVector2Array,
		b: PackedVector2Array) -> bool:
	for i in 2:
		var axis := (axes_from[i + 1] - axes_from[i]).normalized()
		var a_lo := INF
		var a_hi := -INF
		var b_lo := INF
		var b_hi := -INF
		for p in a:
			var v := axis.dot(p)
			a_lo = minf(a_lo, v)
			a_hi = maxf(a_hi, v)
		for p in b:
			var v := axis.dot(p)
			b_lo = minf(b_lo, v)
			b_hi = maxf(b_hi, v)
		if a_hi < b_lo or b_hi < a_lo:
			return true
	return false


## Сегмент полилинии, на который попадает длина `s`, и доля внутри него:
## (индекс, t). За концом полилинии отдаётся последний сегмент.
static func _locate(pts: PackedVector2Array, s: float) -> Vector2:
	var acc := 0.0
	for i in pts.size() - 1:
		var length := pts[i].distance_to(pts[i + 1])
		if s <= acc + length or i == pts.size() - 2:
			return Vector2(i, 0.0 if length <= 0.0 \
				else clampf((s - acc) / length, 0.0, 1.0))
		acc += length
	return Vector2(0.0, 0.0)


## Точка полилинии на длине `s` от её начала.
static func _point_at(pts: PackedVector2Array, s: float) -> Vector2:
	var seg := _locate(pts, s)
	var i := int(seg.x)
	return pts[i].lerp(pts[i + 1], seg.y)


static func _plan_length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	return total
