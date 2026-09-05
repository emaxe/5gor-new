class_name TrafficManager
extends RefCounted
## ИИ городского трафика. Порт TrafficManager.update() (traffic.js:317-579),
## переложенный на SoA-массивы вместо массива объектов: правило проекта
## «RefCounted вместо Node для агентов» и «Ноль аллокаций в hot path»
## (см. .agents/rules/gdscript-style.md).
##
## Машины ездят по рёбрам `CityGraph` (edge_id, t, lane_offset, dir_along) —
## мировая позиция считается из этой четвёрки (_lane_world_pos), а не
## хранится отдельно. Прежняя рельсовая модель (axis, coord, pos, dir) знала
## ровно две оси движения города; здесь `t` — пройденное расстояние в метрах
## вдоль полилинии ребра от узла a, `dir_along` ∈ {+1, -1} — идём ли мы от a
## к b, `lane_offset` — смещение вправо по ходу от оси полотна.
##
## 10 правил ИИ оригинала реализованы по приоритету; правила 4-7 (пешеходы
## на зебре, наезд на пешехода/игрока-пешехода) включаются вместе с этапом 8.
##
## Позиция для ПРАВИЛ (edge_id/t/dir_along) и позиция для РЕНДЕРА
## (render_x/z/h) намеренно разделены: во время поворота машина визуально
## идёт по кривой Безье, а её ребро и `t` остаются заморожены до завершения
## манёвра (как car.turn.newAxis оригинала применялся только при k>=1). Все
## проверки светофора/дистанции/приоритета в это время читают СТАРОЕ ребро —
## это поведение оригинала, а не баг порта.
##
## Разноуровневые развязки безопасны по построению: бакетизация и правила
## читают `edge_id`, поэтому машина на мосту и машина на улице под ним
## никогда не считаются соседями по полосе, даже если их проекции на (x, z)
## совпадают.

const Z_ROAD := TrafficLightController.Axis.Z_ROAD
const X_ROAD := TrafficLightController.Axis.X_ROAD

## Слой физики для коллайдеров трафика (PlayerCar добавляет его в свою
## collision_mask, чтобы не проезжать машины NPC насквозь).
const COLLISION_LAYER := 4

## Смещение полосы от оси дороги: правостороннее движение (traffic.js:304).
## Прикладывается по правой нормали к касательной полилинии в точке `t`,
## а не подстановкой в X/Z, — само число прежнее.
const LANE_OFFSET := 2.5

const SPEED_ACCEL := 5.0
const SPEED_DECEL := -10.0
const SPEED_MAX := 18.0

const RESPAWN_DIST := 260.0
const UTURN_TRIGGER_SPEED := 2.0
const UTURN_TRIGGER_TIME := 1.2
const UTURN_BACK_OFFSET := 4.0
const UTURN_TURN_SPEED := 5.0
## На каком расстоянии до тупика (узел степени 1) машина начинает
## разворачиваться, м. Прежняя модель разворачивалась на границе карты
## (|pos| > 250) — на графе граница карты выражена топологией, а не числом.
const DEAD_END_LOOKAHEAD := 12.0

## Веса выбора исходящего ребра на узле — те же 58/22/20 оригинала
## (traffic.js:590-592, «прямо/направо/налево»), но теперь это веса КЛАССОВ,
## а не таблица на три исхода: внутри класса вес делится поровну между
## реальными рёбрами узла, отсутствующий класс просто выпадает из
## нормировки. На обычном 4-подходном узле классы содержат ровно по одному
## ребру, и распределение вырождается в исходное.
const W_STRAIGHT := 0.58
const W_RIGHT := 0.22
const W_LEFT := 0.20
## Полуширина сектора «прямо», рад. 45° — граница, по которой перекрёсток
## делится на «продолжение улицы» и «поворот»; кандидат с наименьшим
## отклонением курса внутри сектора и есть «прямо».
const STRAIGHT_TOL := PI * 0.25

const TURN_EXIT_OFFSET := 4.5
const TURN_SPEED := 7.0
const TURN_SPEED_RIGHT := 5.2
const TURN_SPEED_LEFT := 6.8
const WHEELBASE_DEFAULT := 2.5
const MAX_STEER := 0.62
const STEER_RATE := 3.5
const LOOKAHEAD_STRAIGHT := 7.0
const LOOKAHEAD_TURN := 4.5
const TURN_T_COOLDOWN := 0.3
const INTERSECTION_CHOOSE_TOL := 2.5
const INTERSECTION_STOP_TOL := 7.0
const INTERSECTION_TURN_YIELD_DIST := 8.5
## Дистанция, на которой въезжающая машина видит машину, уже идущую по
## кольцу, м. Взята по INTERSECTION_TURN_YIELD_DIST с запасом на длину
## дуги между соседними узлами кольца.
const RING_YIELD_DIST := 14.0
## Погрешность, с которой `t` считается дошедшим до узла, м: проекция на
## ребро упирается в его конец точно, шаг машины за кадр — до 0.3 м.
const NODE_ARRIVAL_EPS := 0.05

const FOLLOW_MIN_DIST := 6.0
const EMERGENCY_YIELD_DIST := 25.0
const EMERGENCY_TARGET_CAP := 3.0

const PLAYER_AHEAD_DIST := 14.0
const PLAYER_AHEAD_LATERAL := 5.5
const PLAYER_AHEAD_TARGET := 2.0

## Правила 4-6 (пешеходы, traffic.js:397-452).
const PED_YIELD_LONGITUDINAL := 24.0
const PED_YIELD_DIST_AGGR := 6.0
const PED_YIELD_DIST_NORMAL := 20.0
const HIT_PED_RADIUS_MARGIN := 0.65
const HIT_PED_SPEED_THRESHOLD := 2.5
const HIT_PED_SPEED_REDUCTION := 3.5

const STOP_LINE := 6.5
const LIGHT_LOOKAHEAD := 30.0
const RED_OVERSHOOT := 3.0

## Самая дальняя продольная проверка правил ПДД, м. Это дистанция следования
## правила 3 на максимальной скорости (`speed * 1.5 + 4` для неагрессивного),
## а не EMERGENCY_YIELD_DIST: при SPEED_MAX = 18 она даёт 31 м против 25.
const MAX_LONGITUDINAL_CHECK := SPEED_MAX * 1.5 + 4.0
## Длина бакета вдоль ребра, м. Ключ бакетизации — (edge_id, t / этого шага):
## та же идея «сравнивать только с соседями по своей полосе», что и у прежних
## (axis, coord), но на длинном ребре полоса больше не один бакет на всех.
##
## Шаг выведен из проверки выше с запасом 20%, а не задан числом: тогда
## сосед гарантированно лежит в своём бакете или в одном из двух смежных,
## которые и просматриваются, и подъём SPEED_MAX не сломает бакетизацию молча
## (правило дистанции начало бы терять соседей — то есть наезды в хвост).
const BUCKET_SPAN := MAX_LONGITUDINAL_CHECK * 1.2

const BEACON_PERIOD := 0.6
## Период мигания поворотников — общий таймер на весь трафик, тот же
## компромисс, что и у маячка полиции/скорой (BEACON_PERIOD).
const TURN_BLINK_PERIOD := 0.6
## Порог угловой скорости для включения поворотника, рад/с — отсекает шум
## прямолинейной езды (руление на неровностях, а не реальный поворот).
const TURN_ANGVEL_THRESHOLD := 0.15
## Продольное замедление, при котором зажигается стоп-сигнал, м/с².
const BRAKE_ACCEL_THRESHOLD := 1.0

## Ближайший светофор впереди — переиспользуемый буфер (аналог
## _tempLightRet оригинала), чтобы не аллоцировать объект 40-120 раз в кадр.
class LightInfo extends RefCounted:
	var found := false
	var dist := 0.0
	var state := TrafficLightController.State.GREEN
	var isec_x := 0.0
	var isec_z := 0.0


var count := 0

var catalog: TrafficCatalog
var field: CityField
## Сеть, по которой едут машины: производный вид графа города, где кольца
## развёрнуты в дуги (`TrafficRoadView`). СОБСТВЕННОЕ id-пространство — эти
## id нельзя подставлять в граф, переданный в `setup()`.
var graph: CityGraph
## Признаки рёбер вида, разложенные в свои массивы: в горячем пути дешевле
## читать Packed-массив, чем ходить через объект вида.
var _arc: PackedByteArray = PackedByteArray()
var _one_way: PackedByteArray = PackedByteArray()
var lights: TrafficLightController
var rng: SeededRng
## Необязательная ссылка на пешеходов (этап 8) — правила 4-6 (уступить на
## зебре, наезд, уступить при повороте) выключены, пока она null.
var peds: PedManager
## Необязательная ссылка на пешего игрока (этап 9) — правило 7.
var player_ped: PlayerPed

var type_ref: Array[TrafficTypeData] = []
var body_color: PackedColorArray = PackedColorArray()

## Состояние на графе — правила ПДД читают только эти четыре массива.
var edge_id: PackedInt32Array = PackedInt32Array()
## Пройденное расстояние вдоль полилинии ребра от узла a, м.
var t: PackedFloat32Array = PackedFloat32Array()
## Смещение вправо по ходу движения от оси полотна, м.
var lane_offset: PackedFloat32Array = PackedFloat32Array()
## +1 — едем от a к b, -1 — от b к a.
var dir_along: PackedFloat32Array = PackedFloat32Array()
## Выбранное продолжение за ближайшим узлом (-1 — решение ещё не принято).
## Прямой ход через узел — это тоже смена ребра, в отличие от рельсовой
## модели, где «прямо» означало «остаться на той же бесконечной оси».
var next_edge: PackedInt32Array = PackedInt32Array()
var next_dir: PackedFloat32Array = PackedFloat32Array()

var speed: PackedFloat32Array = PackedFloat32Array()
var target: PackedFloat32Array = PackedFloat32Array()
var aggressive: PackedByteArray = PackedByteArray()
var turn_t: PackedFloat32Array = PackedFloat32Array()
var turn_around_t: PackedFloat32Array = PackedFloat32Array()
var stuck_t: PackedFloat32Array = PackedFloat32Array()
## 0 — решение не принято, 1 — не проезжать на красный, 2 — проехать.
var run_red: PackedByteArray = PackedByteArray()

## Одноразовые флаги near-miss (StyleService): "сближение уже засчитано" /
## "уже было столкновение — детектор глушится". Живут с сущностью, поэтому
## сбрасываются в place_near() вместе с остальным состоянием при респавне.
var nm_passed: PackedByteArray = PackedByteArray()
var nm_hit: PackedByteArray = PackedByteArray()

var turning: PackedByteArray = PackedByteArray()
var t_dist: PackedFloat32Array = PackedFloat32Array()
var t_arc: PackedFloat32Array = PackedFloat32Array()
var t_from_x: PackedFloat32Array = PackedFloat32Array()
var t_from_z: PackedFloat32Array = PackedFloat32Array()
var t_to_x: PackedFloat32Array = PackedFloat32Array()
var t_to_z: PackedFloat32Array = PackedFloat32Array()
var t_p1x: PackedFloat32Array = PackedFloat32Array()
var t_p1z: PackedFloat32Array = PackedFloat32Array()
var t_p2x: PackedFloat32Array = PackedFloat32Array()
var t_p2z: PackedFloat32Array = PackedFloat32Array()
var t_speed: PackedFloat32Array = PackedFloat32Array()
var t_new_edge: PackedInt32Array = PackedInt32Array()
var t_new_dir: PackedFloat32Array = PackedFloat32Array()
## Курс на выходе из поворота. Раньше он выводился из (новая ось, новое
## направление) — четыре константы; на графе выход задаёт касательная
## выбранного ребра, поэтому её проще запомнить в момент начала манёвра.
var t_exit_h: PackedFloat32Array = PackedFloat32Array()

## Позиция и курс для рендера — см. комментарий класса.
var render_x: PackedFloat32Array = PackedFloat32Array()
var render_z: PackedFloat32Array = PackedFloat32Array()
var render_h: PackedFloat32Array = PackedFloat32Array()

## Кинематическое состояние автомобиля (Bicycle Model)
var steer_angle: PackedFloat32Array = PackedFloat32Array()
var target_steer: PackedFloat32Array = PackedFloat32Array()
var angular_vel: PackedFloat32Array = PackedFloat32Array()
var accel_val: PackedFloat32Array = PackedFloat32Array()

## Маячок полиции/скорой: единый таймер на все машины, читается TrafficLayer.
var beacon_red_on := true
var _beacon_t := 0.0
## Мигание поворотников — как маячок, общий таймер на весь трафик читается
## TrafficLayer при выборе материала лампы (core/car_lamp_materials.gd).
var turn_blink_on := true
var _turn_blink_t := 0.0

var _light_buf := LightInfo.new()
var _turning_cars: PackedInt32Array = PackedInt32Array()
## Соседи по полосе для текущей машины — переиспользуемый буфер вместо
## трёх обращений к словарю бакетов в каждом правиле.
var _neigh: PackedInt32Array = PackedInt32Array()

## Результат последнего `_sample_edge`: точка полилинии и единичная
## касательная в ней (направление от a к b). Поля, а не возврат пары, —
## чтобы за один проход по полилинии получить и то, и другое.
var _s_point := Vector3.ZERO
var _s_tangent := Vector2(0.0, 1.0)

## Кандидаты выезда с узла — переиспользуемые буферы `_collect_exits`.
var _cand_edge: PackedInt32Array = PackedInt32Array()
var _cand_dir: PackedFloat32Array = PackedFloat32Array()
var _cand_dev: PackedFloat32Array = PackedFloat32Array()
## Индекс кандидата «прямо» в буферах выше (-1 — прямого продолжения нет).
var _straight_idx := -1

## Результат последнего `_rand_road`: ребро, метры вдоль него, направление.
var _spot_edge := 0
var _spot_t := 0.0
var _spot_dir := 1.0

## Индекс полицейской машины в погоне (-1 = нет погони). Устанавливается
## PoliceManager; машина переключается на преследование игрока.
var chase_idx: int = -1
## Точка преследования (цель = позиция игрока), мир.
var chase_target_x := 0.0
var chase_target_z := 0.0


func setup(catalog_: TrafficCatalog, field_: CityField, graph_: CityGraph,
		lights_: TrafficLightController, rng_: SeededRng, traffic_count: int) -> void:
	catalog = catalog_
	field = field_
	var view := TrafficRoadView.build(graph_)
	graph = view.graph
	_arc = view.arc
	_one_way = view.one_way
	lights = lights_
	rng = rng_
	count = maxi(0, traffic_count)
	_resize(count)

	var police_id := &"police"
	var has_police := false
	for i in count:
		var type_data: TrafficTypeData = null
		var force_police := i == count - 1 and not has_police \
			and catalog.get_type(police_id) != null
		type_data = catalog.get_type(police_id) if force_police else catalog.roll(rng)
		if type_data == null:
			type_data = TrafficTypeData.new()
		type_ref[i] = type_data
		has_police = has_police or type_data.id == police_id
		body_color[i] = _pick_color(type_data)
		aggressive[i] = 1 if rng.chance(catalog.aggressive_ratio) else 0
		edge_id[i] = 0
		t[i] = 0.0
		lane_offset[i] = LANE_OFFSET
		dir_along[i] = 1.0
		next_edge[i] = -1
		next_dir[i] = 1.0
		speed[i] = 0.0
		target[i] = 10.0
		turning[i] = 0
		turn_t[i] = 0.0
		turn_around_t[i] = 0.0
		run_red[i] = 0
		render_x[i] = 0.0
		render_z[i] = 0.0
		render_h[i] = 0.0


func _pick_color(type_data: TrafficTypeData) -> Color:
	if type_data.colors.is_empty():
		return Color.WHITE
	return type_data.colors[0] if type_data.force_color else rng.pick_color(type_data.colors)


func _resize(n: int) -> void:
	type_ref.resize(n)
	body_color.resize(n)
	edge_id.resize(n)
	t.resize(n)
	lane_offset.resize(n)
	dir_along.resize(n)
	next_edge.resize(n)
	next_dir.resize(n)
	speed.resize(n)
	target.resize(n)
	aggressive.resize(n)
	turn_t.resize(n)
	turn_around_t.resize(n)
	stuck_t.resize(n)
	run_red.resize(n)
	nm_passed.resize(n)
	nm_hit.resize(n)
	turning.resize(n)
	t_dist.resize(n)
	t_arc.resize(n)
	t_from_x.resize(n)
	t_from_z.resize(n)
	t_to_x.resize(n)
	t_to_z.resize(n)
	t_p1x.resize(n)
	t_p1z.resize(n)
	t_p2x.resize(n)
	t_p2z.resize(n)
	t_speed.resize(n)
	t_new_edge.resize(n)
	t_new_dir.resize(n)
	t_exit_h.resize(n)
	render_x.resize(n)
	render_z.resize(n)
	render_h.resize(n)
	steer_angle.resize(n)
	target_steer.resize(n)
	angular_vel.resize(n)
	accel_val.resize(n)


# --- Геометрия ребра ------------------------------------------------------------

## Точка и касательная полилинии ребра на расстоянии `s` метров от узла a.
## Тот же приём, что `CityField._march()` (city_field.gd:221-262) для профиля
## серпантина: идём по звеньям ломаной, накапливая длину.
func _sample_edge(e: int, s: float) -> void:
	var n := graph.edge_point_count(e)
	var p0 := graph.edge_point(e, 0)
	if n == 2:
		# Прямое ребро — подавляющее большинство: и сетка, и дуги кольца.
		# Отдельная ветка снимает с горячего пути обход ломаной целиком.
		var p1 := graph.edge_point(e, 1)
		var seg := p0.distance_to(p1)
		var u := 0.0 if seg < 0.0001 else clampf(s / seg, 0.0, 1.0)
		_s_point = p0.lerp(p1, u)
		var dx := p1.x - p0.x
		var dz := p1.z - p0.z
		var dl := sqrt(dx * dx + dz * dz)
		_s_tangent = Vector2(0.0, 1.0) if dl < 0.0001 else Vector2(dx / dl, dz / dl)
		return
	var acc := 0.0
	# while, а не `for k in range(1, n)`: range() аллоцирует массив, а этот
	# цикл выполняется по несколько раз на машину в каждом кадре.
	var k := 1
	while k < n:
		var p1 := graph.edge_point(e, k)
		var seg := p0.distance_to(p1)
		if acc + seg >= s or k == n - 1:
			var u := 0.0 if seg < 0.0001 else clampf((s - acc) / seg, 0.0, 1.0)
			_s_point = p0.lerp(p1, u)
			var tx := p1.x - p0.x
			var tz := p1.z - p0.z
			var tl := sqrt(tx * tx + tz * tz)
			_s_tangent = Vector2(0.0, 1.0) if tl < 0.0001 else Vector2(tx / tl, tz / tl)
			return
		acc += seg
		p0 = p1
		k += 1
	_s_point = p0
	_s_tangent = Vector2(0.0, 1.0)


## Точка правой полосы на ребре: точка полилинии плюс смещение по правой
## нормали к направлению движения. Обобщение `_worldPos` (traffic.js:300-311),
## где смещение было константной подстановкой в X либо в Z.
##
## Правая нормаль к курсу (fx, fz) — это (-fz, fx): тот же знак, что у
## `CityGraph.Side.RIGHT`, где точка на +Z справа от движения на +X.
func _lane_point(e: int, s: float, along: float, offset: float) -> Vector2:
	_sample_edge(e, s)
	var fx := _s_tangent.x * along
	var fz := _s_tangent.y * along
	return Vector2(_s_point.x - fz * offset, _s_point.z + fx * offset)


func _lane_world_pos(i: int) -> Vector2:
	return _lane_point(edge_id[i], t[i], dir_along[i], lane_offset[i])


## Курс движения по ребру в точке `s`: касательная полилинии, а не одна из
## четырёх констант рельсовой модели.
func _edge_heading(e: int, s: float, along: float) -> float:
	_sample_edge(e, s)
	return atan2(_s_tangent.x * along, _s_tangent.y * along)


func lane_heading(i: int) -> float:
	return _edge_heading(edge_id[i], t[i], dir_along[i])


## Ближайшая точка полилинии ребра к (x, z) — в метрах вдоль ребра.
##
## Проекция ищется в плане (x, z) — машина ездит по плану, — а переводится в
## `t` по полной 3D-длине звена, как её считает `CityGraph.edge_length()`.
## На уклоне это даёт `t` чуть больше пройденного по плану пути; на уклонах
## города (этап 3) расхождение — доли процента, а согласованность `t` с
## длиной ребра важнее: по ней считаются и остаток до узла, и бакеты.
func _project_onto_edge(e: int, x: float, z: float) -> float:
	var n := graph.edge_point_count(e)
	var p0 := graph.edge_point(e, 0)
	if n == 2:
		# Быстрая ветка прямого ребра — см. `_sample_edge`.
		var p1 := graph.edge_point(e, 1)
		var dx := p1.x - p0.x
		var dz := p1.z - p0.z
		var denom := dx * dx + dz * dz
		if denom < 1e-9:
			return 0.0
		var u := clampf(((x - p0.x) * dx + (z - p0.z) * dz) / denom, 0.0, 1.0)
		return p0.distance_to(p1) * u
	var acc := 0.0
	var best := 0.0
	var best_d := INF
	var k := 1
	while k < n:
		var p1 := graph.edge_point(e, k)
		var dx := p1.x - p0.x
		var dz := p1.z - p0.z
		var denom := dx * dx + dz * dz
		var u := 0.0 if denom < 1e-9 \
			else clampf(((x - p0.x) * dx + (z - p0.z) * dz) / denom, 0.0, 1.0)
		var qx := p0.x + dx * u
		var qz := p0.z + dz * u
		var d := (x - qx) * (x - qx) + (z - qz) * (z - qz)
		var seg := p0.distance_to(p1)
		if d < best_d:
			best_d = d
			best = acc + seg * u
		acc += seg
		p0 = p1
		k += 1
	return best


## Сколько метров осталось до узла по ходу движения.
func _remaining(i: int) -> float:
	return graph.edge_length(edge_id[i]) - t[i] if dir_along[i] > 0.0 else t[i]


## Узел, к которому машина едет.
func _node_ahead(i: int) -> int:
	var ends := graph.edge_ends(edge_id[i])
	return ends.y if dir_along[i] > 0.0 else ends.x


## Значение `t` в конце ребра по ходу движения.
func _end_s(i: int) -> float:
	return graph.edge_length(edge_id[i]) if dir_along[i] > 0.0 else 0.0


func _incident(e: int, node: int) -> bool:
	var ends := graph.edge_ends(e)
	return ends.x == node or ends.y == node


func _sync_render(i: int) -> void:
	var wp := _lane_world_pos(i)
	render_x[i] = wp.x
	render_z[i] = wp.y
	render_h[i] = lane_heading(i)
	steer_angle[i] = 0.0
	target_steer[i] = 0.0
	angular_vel[i] = 0.0
	accel_val[i] = 0.0


## Индекс оси дорожной сетки — нужен только светофорам (см. `_light_ahead`).
func _axis_index(v: float) -> int:
	return clampi(roundi((v - field.road_axes[0]) / field.cell), 0, field.road_axes.size() - 1)


# --- Размещение ---------------------------------------------------------------

func place_all_near(player_x: float, player_z: float) -> void:
	for i in count:
		place_near(i, player_x, player_z)


## Порт placeNear() (traffic.js:243-260): новая случайная полоса за пределами
## ближнего поля зрения игрока, скорость и повадки перебрасываются заново.
func place_near(i: int, player_x: float, player_z: float) -> void:
	if graph == null or graph.edge_count() == 0:
		return
	_rand_road(player_x, player_z)
	edge_id[i] = _spot_edge
	t[i] = _spot_t
	dir_along[i] = _spot_dir
	lane_offset[i] = LANE_OFFSET
	next_edge[i] = -1
	turning[i] = 0
	turn_t[i] = 0.0
	turn_around_t[i] = 0.0
	run_red[i] = 0
	speed[i] = rng.randf_range(6.0, 13.0)
	target[i] = speed[i]
	aggressive[i] = 1 if rng.chance(catalog.aggressive_ratio) else 0
	nm_passed[i] = 0
	nm_hit[i] = 0
	stuck_t[i] = 0.0
	steer_angle[i] = 0.0
	target_steer[i] = 0.0
	angular_vel[i] = 0.0
	accel_val[i] = 0.0
	_sync_render(i)


## Ставит машину на конкретное ребро — для витрин и тестов, не для игры.
func place_on_edge(i: int, e: int, s: float, along: float) -> void:
	edge_id[i] = e
	t[i] = clampf(s, 0.0, graph.edge_length(e))
	dir_along[i] = 1.0 if _one_way[e] == 1 else along
	lane_offset[i] = LANE_OFFSET
	next_edge[i] = -1
	turning[i] = 0
	turn_t[i] = 0.0
	turn_around_t[i] = 0.0
	stuck_t[i] = 0.0
	_sync_render(i)


## Порт _randRoad() (traffic.js:280-298): случайная полоса не ближе 75 м
## от игрока, чтобы машины не «выскакивали» перед глазами.
##
## Снап на `field.cell` заменён снапом на граф: бросаем точку в кольце
## 80-140 м вокруг игрока (тот же разброс, что у оригинала) и притягиваем её
## к ближайшему полотну — на произвольной топологии это и есть «случайная
## точка на случайной дороге поблизости».
func _rand_road(player_x: float, player_z: float) -> void:
	_spot_edge = 0
	_spot_t = 0.0
	_spot_dir = 1.0
	for _attempt in 10:
		var ang := rng.randf_range(-PI, PI)
		var r := rng.randf_range(80.0, 140.0)
		var px := player_x + cos(ang) * r
		var pz := player_z + sin(ang) * r
		var e := graph.query_nearest_edge(Vector3(px, 0.0, pz), 40.0)
		if e < 0:
			continue
		_spot_edge = e
		_spot_t = graph.hit_t * graph.edge_length(e)
		_spot_dir = 1.0 if _one_way[e] == 1 or rng.chance(0.5) else -1.0
		var wp := _lane_point(e, _spot_t, _spot_dir, LANE_OFFSET)
		if MathUtils.dist_2d(wp.x, wp.y, player_x, player_z) >= 75.0:
			return


# --- Обновление -----------------------------------------------------------------

## Порт TrafficManager.update() (traffic.js:317-579). Пешеходные правила
## (4-7 из плана) вернутся вместе с этапом 8.
func update(delta: float, player_x: float, player_z: float, density: float) -> void:
	_beacon_t = fmod(_beacon_t + delta, BEACON_PERIOD)
	beacon_red_on = _beacon_t < BEACON_PERIOD * 0.5
	_turn_blink_t = fmod(_turn_blink_t + delta, TURN_BLINK_PERIOD)
	turn_blink_on = _turn_blink_t < TURN_BLINK_PERIOD * 0.5

	_turning_cars.clear()
	for i in count:
		if turning[i] == 1:
			_turning_cars.append(i)

	var bucket := _build_bucket()

	for i in count:
		if i == chase_idx:
			_update_chasing(i, player_x, player_z, delta)
			continue

		if MathUtils.dist_2d(render_x[i], render_z[i], player_x, player_z) > RESPAWN_DIST:
			place_near(i, player_x, player_z)
			continue

		if turning[i] == 0 and _remaining(i) < DEAD_END_LOOKAHEAD \
				and graph.node_degree(_node_ahead(i)) <= 1:
			turn_around_t[i] += delta
			if speed[i] < UTURN_TRIGGER_SPEED or turn_around_t[i] > UTURN_TRIGGER_TIME:
				_start_uturn(i)
				turn_around_t[i] = 0.0

		_gather_neighbours(i, bucket)
		_apply_base_target(i, density)
		_rule_dead_end_ahead(i)
		_rule_yield_emergency(i)
		_rule_following_distance(i)
		if peds != null:
			_rule_yield_crossing_ped(i)
			_rule_hit_pedestrian(i)
			if turning[i] == 1:
				_rule_yield_turning_ped(i)
		if player_ped != null:
			_rule_hit_player_ped(i)
		if turning[i] == 0:
			_rule_intersection_priority(i)
		_rule_player_ahead(i, player_x, player_z)
		_rule_traffic_light(i)
		_update_deadlock_watchdog(i, delta, player_x, player_z)

		if turning[i] == 1:
			target[i] = minf(target[i], t_speed[i])
		_integrate_speed(i, delta)

		if turning[i] == 1:
			_advance_turn(i, delta)
		else:
			_advance_straight(i)

		_step_kinematics(i, delta)

		if turning[i] == 0:
			if turn_t[i] > 0.0:
				turn_t[i] -= delta
			elif _remaining(i) < INTERSECTION_CHOOSE_TOL:
				_choose_direction(i)


## Ключ бакета: (ребро, номер отрезка длиной BUCKET_SPAN вдоль него).
func _bucket_key(e: int, slot: int) -> int:
	return MathUtils.hash_key(e, slot)


func _bucket_slot(s: float) -> int:
	return floori(s / BUCKET_SPAN)


## Бакеты по (edge_id, отрезок t): следование и уступание спецтранспорту
## сравнивают машину только с соседями по своей полосе, а не со всеми
## (архитектура, план: «Бакетизация... это чинит дефект №5 (O(n²))»).
func _build_bucket() -> Dictionary[int, PackedInt32Array]:
	var b: Dictionary[int, PackedInt32Array] = {}
	for i in count:
		var key := _bucket_key(edge_id[i], _bucket_slot(t[i]))
		if not b.has(key):
			b[key] = PackedInt32Array()
		b[key].append(i)
	return b


## Собирает соседей по полосе в `_neigh`: свой бакет и два смежных.
## Шаг бакета больше самой дальней продольной проверки, поэтому три бакета
## гарантированно накрывают всех, кого правила могут увидеть.
func _gather_neighbours(i: int, bucket: Dictionary[int, PackedInt32Array]) -> void:
	_neigh.clear()
	var e := edge_id[i]
	var slot := _bucket_slot(t[i])
	_append_bucket(bucket, e, slot - 1)
	_append_bucket(bucket, e, slot)
	_append_bucket(bucket, e, slot + 1)


func _append_bucket(bucket: Dictionary[int, PackedInt32Array], e: int, slot: int) -> void:
	var key := _bucket_key(e, slot)
	if not bucket.has(key):
		return
	var list: PackedInt32Array = bucket[key]
	_neigh.append_array(list)


func _apply_base_target(i: int, density: float) -> void:
	var is_aggr := aggressive[i] == 1
	var base_target: float
	if is_aggr:
		base_target = rng.randf_range(9.0, 15.0) * density * 1.25
	else:
		base_target = rng.randf_range(7.0, 13.0) * density
	target[i] = clampf(base_target, 4.0, 18.0 if is_aggr else 16.0)


## Правило 1: опасность впереди. Генератор этого города не ставит препятствия
## на проезжую часть, а съехать с полотна машина на графе не может по
## построению — единственная реальная опасность осталась одна: упереться в
## тупик (узел, из которого нет продолжения).
func _rule_dead_end_ahead(i: int) -> void:
	# Машина в развороте уже решает эту проблему — тормозить её посреди
	# манёвра значит запереть её у тупика насовсем.
	if turning[i] == 1:
		return
	if _remaining(i) > 5.0:
		return
	if graph.node_degree(_node_ahead(i)) <= 1:
		target[i] = 0.0


## Правило 2: уступить спецтранспорту с мигалкой, идущему сзади в своей полосе.
func _rule_yield_emergency(i: int) -> void:
	if type_ref[i].beacon != &"":
		return
	for j: int in _neigh:
		if j == i or type_ref[j].beacon == &"" or dir_along[j] != dir_along[i]:
			continue
		var d := (t[i] - t[j]) * dir_along[j]
		if d > 0.0 and d < EMERGENCY_YIELD_DIST:
			target[i] = minf(target[i], EMERGENCY_TARGET_CAP)
			return


## Правило 3: динамическая дистанция до впереди идущего в своей полосе.
func _rule_following_distance(i: int) -> void:
	for j: int in _neigh:
		if j == i or dir_along[j] != dir_along[i]:
			continue
		var d := (t[j] - t[i]) * dir_along[i]
		var safe_dist := (speed[i] * 0.8 + 2.0) if aggressive[i] == 1 \
			else (speed[i] * 1.5 + 4.0)
		if d > 0.0 and d < maxf(FOLLOW_MIN_DIST, safe_dist):
			target[i] = minf(target[i], maxf(0.0, speed[j] - 1.5))
			return


## Правило 4: уступить пешеходу, уже вышедшему на переход в своей полосе —
## порт участка «уступание дороги» из traffic.js:397-415.
##
## Продольная/поперечная координаты пешехода считаются проекцией на курс
## машины, а не подстановкой в ось: на кривом ребре осей нет.
func _rule_yield_crossing_ped(i: int) -> void:
	var fwd := Heading.forward(render_h[i])
	for p: int in peds.active_crossing_peds:
		var dx := peds.world_x(p) - render_x[i]
		var dz := peds.world_z(p) - render_z[i]
		# Уступаем только если пешеход реально находится на проезжей части
		# (в пределах ширины дороги). Пешеход, ожидающий на тротуаре,
		# не должен вызывать остановку трафика.
		var lateral := absf(-dx * fwd.z + dz * fwd.x)
		if lateral > field.road_half:
			continue
		var d := dx * fwd.x + dz * fwd.z
		if d <= 0.0 or d >= PED_YIELD_LONGITUDINAL:
			continue
		var yield_dist := PED_YIELD_DIST_AGGR if aggressive[i] == 1 else PED_YIELD_DIST_NORMAL
		if d < yield_dist:
			target[i] = 0.0
			return


## Правило 5: наезд машины трафика на пешехода — порт traffic.js:417-437.
func _rule_hit_pedestrian(i: int) -> void:
	var r := type_ref[i].radius + HIT_PED_RADIUS_MARGIN
	var rx := render_x[i]
	var rz := render_z[i]
	var x0 := floori((rx - r) / 8.0)
	var x1 := floori((rx + r) / 8.0)
	var z0 := floori((rz - r) / 8.0)
	var z1 := floori((rz + r) / 8.0)
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var key := MathUtils.hash_key(cx, cz)
			if not peds.spatial_bucket.has(key):
				continue
			for p: int in peds.spatial_bucket[key]:
				if peds.mode_of(p) == PedManager.Mode.KNOCKED or peds.mode_of(p) == PedManager.Mode.FLEE:
					continue
				var dx := rx - peds.world_x(p)
				var dz := rz - peds.world_z(p)
				var d2 := dx * dx + dz * dz
				if d2 >= r * r:
					continue
				var dist := sqrt(d2)
				if dist < 0.0001:
					continue
				# nx/nz — от машины к пешеходу: направление, в котором он отлетает.
				var nx := -dx / dist
				var nz := -dz / dist
				if speed[i] > HIT_PED_SPEED_THRESHOLD:
					peds.knock_down_from_traffic(p, nx, nz, speed[i])
					speed[i] = maxf(1.0, speed[i] - HIT_PED_SPEED_REDUCTION)
				else:
					peds.dodge_from_traffic(p, nx, nz, speed[i])
				return


## Правило 6: уступить пешеходам на зебре при активном повороте — порт
## traffic.js:441-452.
func _rule_yield_turning_ped(i: int) -> void:
	var yield_dist := 4.0 if aggressive[i] == 1 else 6.0
	for p: int in peds.active_crossing_peds:
		if peds.mode_of(p) != PedManager.Mode.WALK:
			continue
		var d := MathUtils.dist_2d(render_x[i], render_z[i], peds.world_x(p), peds.world_z(p))
		if d < yield_dist:
			target[i] = 0.0
			return


## Правило 7: наезд машины трафика на игрока-пешехода (пеший режим) — порт traffic.js:452-473.
func _rule_hit_player_ped(i: int) -> void:
	if player_ped == null or not is_instance_valid(player_ped):
		return
	if player_ped.logic.hit_cd > 0.0 or player_ped.logic.stun_t > 0.0:
		return
	var dist := MathUtils.dist_2d(render_x[i], render_z[i], player_ped.logic.x, player_ped.logic.z)
	var col_r: float = type_ref[i].radius + 0.6
	if dist >= col_r:
		return
	player_ped.logic.hit_cd = 1.2
	var dx := player_ped.logic.x - render_x[i]
	var dz := player_ped.logic.z - render_z[i]
	if dist < 0.0001:
		dist = 1.0
		dx = 0.0
		dz = 1.0
	var nx := dx / dist
	var nz := dz / dist
	if speed[i] > 2.5:
		player_ped.take_hit(render_x[i], render_z[i], 1)
		speed[i] = maxf(1.0, speed[i] - 3.5)
	else:
		player_ped.apply_knockback(nx * 4.0, nz * 4.0, 0.25)


## Правило 8: машина без поворота уступает уже поворачивающей рядом с тем же
## узлом, поперечной машине, уже находящейся на узле, и — на въезде в кольцо —
## тому, кто уже едет по дуге.
##
## «Поперечная» на графе — это машина на ДРУГОМ подходе того же узла (раньше
## признаком служило `axis[j] != axis[i]`, что на произвольной топологии
## смысла не имеет).
func _rule_intersection_priority(i: int) -> void:
	if _remaining(i) >= INTERSECTION_STOP_TOL:
		return
	var node := _node_ahead(i)
	var np := graph.node_position(node)
	if not _turning_cars.is_empty():
		for j: int in _turning_cars:
			if j == i:
				continue
			if MathUtils.dist_2d(render_x[j], render_z[j], np.x, np.z) \
					< INTERSECTION_TURN_YIELD_DIST:
				target[i] = 0.0
				return
	# Приоритет кольца: машина, уже находящаяся на дуге, важнее въезжающей.
	# Правило двустороннее, и вторая половина не менее важна первой: если бы
	# машина на дуге пропускала того, кто ждёт на въезде, обе встали бы
	# насмерть — въезжающий уже стоит в пяти метрах от узла, то есть внутри
	# обычной проверки «поперечная машина на узле».
	# Точная формулировка правил уступания — этап 7, здесь базовая версия.
	var on_ring := _arc[edge_id[i]] == 1
	var entering_ring := not on_ring and _node_has_ring(node)
	# Встречная машина на продолжении моей же улицы — не поперечная: раньше её
	# отсекало `axis[j] == axis[i]`, на графе тот же смысл несёт «её подход
	# коллинеарен моему», то есть попадает в сектор «прямо». Без этого пара
	# встречных машин в 4 м от узла останавливает друг друга.
	var straight_edge := _straight_continuation(i, node)
	for j in count:
		if j == i or edge_id[j] == edge_id[i] or edge_id[j] == straight_edge:
			continue
		var j_on_ring := _arc[edge_id[j]] == 1
		if entering_ring and j_on_ring:
			if MathUtils.dist_2d(render_x[j], render_z[j], np.x, np.z) < RING_YIELD_DIST:
				target[i] = 0.0
				return
			continue
		if on_ring and not j_on_ring:
			continue
		if not _incident(edge_id[j], node):
			continue
		if absf(render_x[j] - np.x) < 5.0 and absf(render_z[j] - np.z) < 5.0:
			target[i] = 0.0
			return


## Ребро, продолжающее курс машины за узлом, или -1. То же, что кандидат
## «прямо» в `_collect_exits`, но без заполнения буферов кандидатов: правило 8
## зовётся каждый кадр для каждой машины у узла, и складывать ради одного
## числа три Packed-массива дороже самого ответа.
func _straight_continuation(i: int, node: int) -> int:
	var e := edge_id[i]
	var in_h := _edge_heading(e, _end_s(i), dir_along[i])
	var best := STRAIGHT_TOL
	var found := -1
	for k in graph.node_degree(node):
		var oe := graph.approach_edge(node, k)
		if oe == e:
			continue
		var dev := absf(Heading.delta(in_h, PI * 0.5 - graph.approach_angle(node, k)))
		if dev < best:
			best = dev
			found = oe
	return found


## Узел вида — гейт кольца: хотя бы один его подход это дуга.
func _node_has_ring(node: int) -> bool:
	for k in graph.node_degree(node):
		if _arc[graph.approach_edge(node, k)] == 1:
			return true
	return false


## Правило 9: машина игрока впереди в той же полосе.
func _rule_player_ahead(i: int, player_x: float, player_z: float) -> void:
	var fwd := Heading.forward(render_h[i])
	var dx := player_x - render_x[i]
	var dz := player_z - render_z[i]
	var d_p := dx * fwd.x + dz * fwd.z
	var lateral := absf(-dx * fwd.z + dz * fwd.x)
	if d_p > 0.0 and d_p < PLAYER_AHEAD_DIST and lateral < PLAYER_AHEAD_LATERAL:
		target[i] = minf(target[i], PLAYER_AHEAD_TARGET)


## Правило 10: светофор впереди (traffic.js:497-529).
func _rule_traffic_light(i: int) -> void:
	# Машина в процессе поворота уже выехала на перекрёсток и обязана его
	# освободить, не останавливаясь посреди проезжей части на красный свет.
	if turning[i] == 1:
		return
	var l := _light_ahead(i)
	if not l.found or l.state == TrafficLightController.State.GREEN:
		run_red[i] = 0
		return

	var brake_dist := speed[i] * speed[i] / 20.0
	if l.state == TrafficLightController.State.YELLOW:
		if l.dist >= brake_dist + STOP_LINE:
			target[i] = minf(target[i], 0.0)
		return

	# Красный.
	var will_run_red := false
	if aggressive[i] == 1:
		if run_red[i] == 0:
			run_red[i] = 2 if rng.chance(catalog.red_light_run_chance) else 1
		if run_red[i] == 2 and _is_intersection_clear(l.isec_x, l.isec_z, i):
			will_run_red = true
	if will_run_red:
		return
	if l.dist > STOP_LINE:
		if l.dist <= brake_dist + STOP_LINE + RED_OVERSHOOT:
			target[i] = minf(target[i], 0.0)
	elif speed[i] < 1.0:
		target[i] = minf(target[i], 0.0)


## Ближайший регулируемый узел впереди — это конец текущего ребра, а не
## результат арифметики `ceil(pos / cell)`: на графе «следующий перекрёсток»
## задан топологией.
##
## [b]Временная граница этапа 6/7.[/b] Сам `TrafficLightController` до этапа 7
## остаётся сеточным: он адресует перекрёсток парой индексов осей и знает
## ровно две фазы (`Axis.Z_ROAD`/`X_ROAD`). Поэтому здесь узел графа
## переводится обратно в эту адресацию — индексы осей по (x, z) его позиции,
## ось — по преобладающей компоненте курса машины. Для сетки это тождественно
## прежнему `_axis_index()` (путь (a) из решения контроллера:
## поведение светофоров сохранено без изменений), для произвольного графа —
## приближение, которое уходит вместе с переводом светофоров на узлы графа
## (этап 7, N-фазные сигналы).
func _light_ahead(i: int) -> LightInfo:
	var l := _light_buf
	l.found = false
	var dist := _remaining(i)
	if dist <= 0.0 or dist > LIGHT_LOOKAHEAD:
		return l

	var np := graph.node_position(_node_ahead(i))
	var i_idx := _axis_index(np.x)
	var j_idx := _axis_index(np.z)
	if not PedGraph.is_signalized(i_idx, j_idx):
		return l

	var fwd := Heading.forward(render_h[i])
	var car_axis := Z_ROAD if absf(fwd.z) >= absf(fwd.x) else X_ROAD
	l.found = true
	l.dist = dist
	l.state = lights.car_state(i_idx, car_axis)
	l.isec_x = np.x
	l.isec_z = np.z
	return l


## Порт _isIntersectionClear() (traffic.js:262-276) без пешеходов — те же
## вернутся с этапом 8.
func _is_intersection_clear(isec_x: float, isec_z: float, self_index: int) -> bool:
	for j in count:
		if j == self_index:
			continue
		if MathUtils.dist_2d(render_x[j], render_z[j], isec_x, isec_z) < 8.5:
			return false
	return true


func _integrate_speed(i: int, delta: float) -> void:
	var old_speed := speed[i]
	var diff := target[i] - speed[i]
	speed[i] = clampf(speed[i] + clampf(diff, SPEED_DECEL * delta, SPEED_ACCEL * delta),
		0.0, SPEED_MAX)
	accel_val[i] = (speed[i] - old_speed) / maxf(delta, 0.0001)


# --- Выбор исходящего ребра -----------------------------------------------------

## Собирает исходящие рёбра узла (кроме того, по которому приехали) в
## `_cand_*` и отмечает среди них «прямо» — кандидата с наименьшим
## отклонением курса, если оно укладывается в STRAIGHT_TOL.
##
## Отклонение считается от курса въезда: `dev > 0` — влево, `dev < 0` —
## вправо (курс `atan2(fx, fz)` растёт от +Z к +X, а справа от +Z лежит -X).
func _collect_exits(i: int, node: int) -> void:
	_cand_edge.clear()
	_cand_dir.clear()
	_cand_dev.clear()
	_straight_idx = -1
	var e := edge_id[i]
	var in_h := _edge_heading(e, _end_s(i), dir_along[i])
	var best_abs := INF
	for k in graph.node_degree(node):
		var oe := graph.approach_edge(node, k)
		if oe == e:
			continue
		if _one_way[oe] == 1 and graph.edge_ends(oe).x != node:
			# Односторонняя дуга кольца, которая в этот гейт ВХОДИТ: выехать
			# по ней значит поехать по кольцу навстречу.
			continue
		# approach_angle — atan2(dz, dx) направления ОТ узла; курс проекта
		# считается как atan2(dx, dz), отсюда поворот на четверть.
		var exit_h := PI * 0.5 - graph.approach_angle(node, k)
		var dev := Heading.delta(in_h, exit_h)
		_cand_edge.append(oe)
		_cand_dir.append(1.0 if graph.edge_ends(oe).x == node else -1.0)
		_cand_dev.append(dev)
		if absf(dev) < best_abs:
			best_abs = absf(dev)
			_straight_idx = _cand_edge.size() - 1
	if best_abs > STRAIGHT_TOL:
		_straight_idx = -1


## Бросок кубика по весам классов (прямо/право/лево). Возвращает индекс
## кандидата в `_cand_*` или -1, если выезда нет (тупик).
func _roll_exit(i: int, node: int) -> int:
	_collect_exits(i, node)
	var n := _cand_edge.size()
	if n == 0:
		return -1
	var n_right := 0
	var n_left := 0
	for k in n:
		if k == _straight_idx:
			continue
		if _cand_dev[k] < 0.0:
			n_right += 1
		else:
			n_left += 1
	var total := 0.0
	if _straight_idx >= 0:
		total += W_STRAIGHT
	if n_right > 0:
		total += W_RIGHT
	if n_left > 0:
		total += W_LEFT
	var roll := rng.next() * total
	var acc := 0.0
	for k in n:
		if k == _straight_idx:
			acc += W_STRAIGHT
		elif _cand_dev[k] < 0.0:
			acc += W_RIGHT / float(n_right)
		else:
			acc += W_LEFT / float(n_left)
		if roll < acc:
			return k
	return n - 1


## Продолжение с наименьшим отклонением курса — запасной ход, когда решение
## не было принято вовремя (кулдаун, занятый узел): машина обязана уехать с
## узла, а не встать на нём.
func _force_straight(i: int, node: int) -> void:
	_collect_exits(i, node)
	if _cand_edge.is_empty():
		next_edge[i] = -1
		return
	var best := 0
	for k in _cand_edge.size():
		if absf(_cand_dev[k]) < absf(_cand_dev[best]):
			best = k
	next_edge[i] = _cand_edge[best]
	next_dir[i] = _cand_dir[best]


# --- Погоня ----------------------------------------------------------------------

## Преследование игрока полицейской машиной (PoliceManager ставит chase_idx).
## Жадная погоня по графу: машина мчится на скорости, а на узле выбирает
## исходящее ребро, которое сильнее сокращает дистанцию до цели. Повороты —
## тот же Безье-механизм, что и обычный трафик, поэтому машина не срезает углы.
func _update_chasing(i: int, px: float, pz: float, delta: float) -> void:
	target[i] = SPEED_MAX * 1.15
	if turning[i] == 1:
		target[i] = minf(target[i], t_speed[i])
	_integrate_speed(i, delta)

	if turning[i] == 1:
		_advance_turn(i, delta)
	else:
		_advance_straight(i)
		if turn_t[i] > 0.0:
			turn_t[i] -= delta
		elif _remaining(i) < INTERSECTION_CHOOSE_TOL:
			_turn_toward_player(i, px, pz)

	_step_kinematics(i, delta)


## На узле выбирает исходящее ребро, дающее точку ближе к цели, и запускает
## поворот Безье. Перебираются все реальные рёбра узла, а не три исхода
## рельсовой модели. Развороты не используются.
func _turn_toward_player(i: int, px: float, pz: float) -> void:
	var node := _node_ahead(i)
	_collect_exits(i, node)
	if _cand_edge.is_empty():
		turn_t[i] = TURN_T_COOLDOWN
		return
	var best := 0
	var best_d := INF
	for k in _cand_edge.size():
		var d := _after_turn_dist(k, px, pz)
		if d < best_d:
			best_d = d
			best = k
	if best == _straight_idx:
		next_edge[i] = _cand_edge[best]
		next_dir[i] = _cand_dir[best]
		turn_t[i] = TURN_T_COOLDOWN
		return
	if not _begin_turn_to(i, best, TURN_SPEED):
		turn_t[i] = TURN_T_COOLDOWN


## Расстояние до цели после выезда с узла по кандидату k.
func _after_turn_dist(k: int, px: float, pz: float) -> float:
	var oe := _cand_edge[k]
	var od := _cand_dir[k]
	var s := clampf(6.0 if od > 0.0 else graph.edge_length(oe) - 6.0,
		0.0, graph.edge_length(oe))
	var wp := _lane_point(oe, s, od, LANE_OFFSET)
	return MathUtils.dist_2d(wp.x, wp.y, px, pz)


func _update_deadlock_watchdog(i: int, delta: float, player_x: float, player_z: float) -> void:
	if speed[i] < 0.5:
		stuck_t[i] += delta
		if stuck_t[i] > 5.5:
			# Машина застряла дольше 5.5 сек:
			if turning[i] == 1:
				# Если в повороте — принудительно завершаем маневр, освобождая узел
				speed[i] = maxf(speed[i], 5.0)
				target[i] = maxf(target[i], 5.0)
			elif _remaining(i) < INTERSECTION_STOP_TOL + 3.0:
				# В заторе на узле: если затор длится > 8 сек — респавним за пределами видимости
				if stuck_t[i] > 8.0:
					place_near(i, player_x, player_z)
					stuck_t[i] = 0.0
				else:
					target[i] = maxf(target[i], 4.0)
	else:
		stuck_t[i] = 0.0


# --- Продвижение и повороты (Bicycle Model + Pure Pursuit) -----------------------

## Продвижение по прямой с удержанием центра полосы через Pure Pursuit.
## Точка упреждения берётся на полилинии ребра (а при выходе за узел — на
## выбранном продолжении), поэтому кривое ребро отслеживается тем же кодом,
## что и прямое.
func _advance_straight(i: int) -> void:
	var lane_pt := _lane_world_pos(i)
	var cur_pt := Vector2(render_x[i], render_z[i])
	# Защита от телепортации (сброс в тестах или спавне без вызова _sync_render)
	if cur_pt.distance_squared_to(lane_pt) > 16.0:
		render_x[i] = lane_pt.x
		render_z[i] = lane_pt.y
		render_h[i] = lane_heading(i)
		steer_angle[i] = 0.0
		target_steer[i] = 0.0

	var target_pt := _lookahead_point(i, LOOKAHEAD_STRAIGHT)
	var dx := target_pt.x - render_x[i]
	var dz := target_pt.y - render_z[i]
	var ld := sqrt(dx * dx + dz * dz)
	if ld > 0.01:
		var target_h := atan2(dx, dz)
		var alpha := Heading.delta(render_h[i], target_h)
		var steer := atan2(2.0 * _wheelbase(i) * sin(alpha), ld)
		target_steer[i] = clampf(steer, -MAX_STEER, MAX_STEER)


## Точка полосы в `ahead` метрах впереди: на текущем ребре, на выбранном
## продолжении за узлом либо — если продолжение ещё не выбрано — по
## касательной конца ребра.
func _lookahead_point(i: int, ahead: float) -> Vector2:
	var e := edge_id[i]
	var length := graph.edge_length(e)
	var s := t[i] + dir_along[i] * ahead
	if s >= 0.0 and s <= length:
		return _lane_point(e, s, dir_along[i], lane_offset[i])

	var over := (s - length) if dir_along[i] > 0.0 else -s
	var ne := next_edge[i]
	if ne >= 0:
		var nd := next_dir[i]
		var nlen := graph.edge_length(ne)
		var ns := clampf(over if nd > 0.0 else nlen - over, 0.0, nlen)
		return _lane_point(ne, ns, nd, lane_offset[i])

	# `_lane_point` только что заполнил `_s_tangent` касательной конца ребра —
	# по ней и продолжаем прямую за узел.
	var end_pt := _lane_point(e, _end_s(i), dir_along[i], lane_offset[i])
	return end_pt + _s_tangent * dir_along[i] * over


func _wheelbase(i: int) -> float:
	if type_ref[i] != null and type_ref[i].length > 1.0:
		return maxf(type_ref[i].length * 0.55, 2.0)
	return WHEELBASE_DEFAULT


## Аналог _chooseDirection() (traffic.js:589-640) на графе: перебор реальных
## исходящих рёбер узла вместо трёх исходов рельсовой модели. Кубическая
## кривая с касательными входа и выхода — прежняя, меняется только источник
## выходной касательной.
func _choose_direction(i: int) -> void:
	var node := _node_ahead(i)
	var np := graph.node_position(node)
	# Не начинаем поворот, если на этом узле уже выполняет поворот другая машина
	for j: int in _turning_cars:
		if j == i:
			continue
		if MathUtils.dist_2d(render_x[j], render_z[j], np.x, np.z) < INTERSECTION_TURN_YIELD_DIST:
			turn_t[i] = TURN_T_COOLDOWN
			return

	var k := _roll_exit(i, node)
	if k < 0:
		turn_t[i] = TURN_T_COOLDOWN
		return
	if k == _straight_idx:
		# Прямо — это тоже переход на другое ребро, но без манёвра: смена
		# происходит в момент прохода узла (_hand_off).
		next_edge[i] = _cand_edge[k]
		next_dir[i] = _cand_dir[k]
		turn_t[i] = TURN_T_COOLDOWN
		return

	var turn_speed := TURN_SPEED_RIGHT if _cand_dev[k] < 0.0 else TURN_SPEED_LEFT
	if not _begin_turn_to(i, k, turn_speed):
		turn_t[i] = TURN_T_COOLDOWN


## Общая часть «повернуть на кандидата k»: точка выезда, проверка занятости
## выходной полосы, запуск Безье. false — поворот не начат.
func _begin_turn_to(i: int, k: int, turn_speed: float) -> bool:
	var oe := _cand_edge[k]
	var od := _cand_dir[k]
	var olen := graph.edge_length(oe)
	var exit_s := clampf(TURN_EXIT_OFFSET if od > 0.0 else olen - TURN_EXIT_OFFSET, 0.0, olen)
	var exit_wp := _lane_point(oe, exit_s, od, lane_offset[i])
	var end_tangent := _s_tangent * od

	# Не поворачиваем, если выходная полоса сразу за узлом заблокирована
	for j in count:
		if j == i:
			continue
		if MathUtils.dist_2d(render_x[j], render_z[j], exit_wp.x, exit_wp.y) < 5.0 \
				and speed[j] < 1.0:
			return false

	var cur_fwd := Heading.forward(render_h[i])
	_begin_turn(i, Vector2(render_x[i], render_z[i]), exit_wp,
		Vector2(cur_fwd.x, cur_fwd.z), end_tangent, turn_speed)
	t_new_edge[i] = oe
	t_new_dir[i] = od
	t_exit_h[i] = atan2(end_tangent.x, end_tangent.y)
	next_edge[i] = -1
	turn_t[i] = t_arc[i] / maxf(speed[i], 4.0) + TURN_T_COOLDOWN
	return true


## Порт _startUTurn() (traffic.js:643-674): разворот по той же траекторной
## схеме с разворотом курса на 180°. Понятия «ось» здесь больше нет — машина
## остаётся на своём ребре и меняет знак `dir_along`.
func _start_uturn(i: int) -> void:
	var e := edge_id[i]
	var new_dir := -dir_along[i]
	var new_t := clampf(t[i] - dir_along[i] * UTURN_BACK_OFFSET, 0.0, graph.edge_length(e))
	var target_wp := _lane_point(e, new_t, new_dir, lane_offset[i])
	var end_tangent := _s_tangent * new_dir
	var cur_fwd := Heading.forward(render_h[i])

	_begin_turn(i, Vector2(render_x[i], render_z[i]), target_wp,
		Vector2(cur_fwd.x, cur_fwd.z), end_tangent, UTURN_TURN_SPEED)
	t_new_edge[i] = e
	t_new_dir[i] = new_dir
	t_exit_h[i] = atan2(end_tangent.x, end_tangent.y)
	next_edge[i] = -1


## Общая часть подготовки траектории поворота (start_tangent -> end_tangent).
func _begin_turn(i: int, from: Vector2, to: Vector2, start_tangent: Vector2,
		end_tangent: Vector2, turn_speed: float) -> void:
	var chord := from.distance_to(to)
	var length := maxf(chord, 3.0)
	var p1 := from + start_tangent * (length / 3.0)
	var p2 := to - end_tangent * (length / 3.0)
	var arc_len := p1.distance_to(from) + p2.distance_to(p1) + to.distance_to(p2)

	turning[i] = 1
	t_dist[i] = 0.0
	t_arc[i] = arc_len
	t_from_x[i] = from.x
	t_from_z[i] = from.y
	t_to_x[i] = to.x
	t_to_z[i] = to.y
	t_p1x[i] = p1.x
	t_p1z[i] = p1.y
	t_p2x[i] = p2.x
	t_p2z[i] = p2.y
	t_speed[i] = turn_speed


## Вычисление точки на направляющей кривой поворота для параметра k in [0, 1].
func _eval_turn_pos(i: int, k_val: float) -> Vector2:
	var k := clampf(k_val, 0.0, 1.0)
	var u := 1.0 - k
	var bx := u * u * u * t_from_x[i] + 3.0 * u * u * k * t_p1x[i] \
		+ 3.0 * u * k * k * t_p2x[i] + k * k * k * t_to_x[i]
	var bz := u * u * u * t_from_z[i] + 3.0 * u * u * k * t_p1z[i] \
		+ 3.0 * u * k * k * t_p2z[i] + k * k * k * t_to_z[i]
	return Vector2(bx, bz)


## Отслеживание траектории поворота через Pure Pursuit и гладкий сход в новую полосу.
func _advance_turn(i: int, delta: float) -> void:
	t_dist[i] += speed[i] * delta
	var arc := maxf(t_arc[i], 0.0001)
	var k := t_dist[i] / arc

	# Точка упреждения на направляющей траектории поворота
	var lookahead_dist := LOOKAHEAD_TURN
	var k_look := clampf((t_dist[i] + lookahead_dist) / arc, 0.0, 1.0)
	var target_pt: Vector2
	if (t_dist[i] + lookahead_dist) <= arc:
		target_pt = _eval_turn_pos(i, k_look)
	else:
		# Экстраполяция по выходу из поворота в целевую полосу
		var exit_pt := Vector2(t_to_x[i], t_to_z[i])
		var exit_fwd := Heading.forward(t_exit_h[i])
		var overshoot := (t_dist[i] + lookahead_dist) - arc
		target_pt = exit_pt + Vector2(exit_fwd.x, exit_fwd.z) * overshoot

	# Pure Pursuit рулёжка к target_pt
	var dx := target_pt.x - render_x[i]
	var dz := target_pt.y - render_z[i]
	var ld := sqrt(dx * dx + dz * dz)
	if ld > 0.01:
		var target_h := atan2(dx, dz)
		var alpha := Heading.delta(render_h[i], target_h)
		var steer := atan2(2.0 * _wheelbase(i) * sin(alpha), ld)
		target_steer[i] = clampf(steer, -MAX_STEER, MAX_STEER)

	# Завершение поворота при достижении конца дуги или совмещении с полосой
	var edx := render_x[i] - t_to_x[i]
	var edz := render_z[i] - t_to_z[i]
	var exit_dist_sq := edx * edx + edz * edz
	var h_diff := absf(Heading.delta(render_h[i], t_exit_h[i]))

	if k >= 1.0 or (k > 0.8 and exit_dist_sq < 4.0 and h_diff < 0.25):
		edge_id[i] = t_new_edge[i]
		dir_along[i] = t_new_dir[i]
		turning[i] = 0
		next_edge[i] = -1
		t[i] = _project_onto_edge(edge_id[i], render_x[i], render_z[i])


## Интегрирование кинематики (Bicycle Model) и синхронизация `t` с полотном.
func _step_kinematics(i: int, delta: float) -> void:
	# 1. Плавный поворот управляемых колёс с ограничением угловой скорости
	var steer_diff := target_steer[i] - steer_angle[i]
	var max_steer_step := STEER_RATE * delta
	steer_angle[i] += clampf(steer_diff, -max_steer_step, max_steer_step)

	# 2. Угловая скорость (yaw rate) по модели велосипеда: dHeading/dt = (v / L) * tan(steer)
	var v := speed[i]
	var yaw_rate := (v / _wheelbase(i)) * tan(steer_angle[i])
	angular_vel[i] = yaw_rate

	# Интегрирование курсового угла
	render_h[i] = wrapf(render_h[i] + yaw_rate * delta, -PI, PI)

	# 3. Перемещение строго по фактическому курсу автомобиля (без бокового скольжения)
	var fwd := Heading.forward(render_h[i])
	var dist_step := v * delta
	render_x[i] += fwd.x * dist_step
	render_z[i] += fwd.z * dist_step

	# 4. Проекция логической координаты `t` на полилинию ребра для правил ПДД
	if turning[i] == 0:
		t[i] = _project_onto_edge(edge_id[i], render_x[i], render_z[i])
		if _remaining(i) <= NODE_ARRIVAL_EPS:
			_hand_off(i)


## Проход узла без манёвра: машина переходит на выбранное продолжение.
## Если решение не принято (кулдаун, узел был занят), продолжение выбирается
## здесь же — иначе машина упёрлась бы в узел и встала.
func _hand_off(i: int) -> void:
	var node := _node_ahead(i)
	if next_edge[i] < 0 or not _incident(next_edge[i], node):
		_force_straight(i, node)
	if next_edge[i] < 0:
		# Тупик: развернуться на месте, ребро остаётся тем же.
		dir_along[i] = -dir_along[i]
		render_h[i] = lane_heading(i)
		return
	edge_id[i] = next_edge[i]
	dir_along[i] = next_dir[i]
	next_edge[i] = -1
	t[i] = _project_onto_edge(edge_id[i], render_x[i], render_z[i])


# --- Запросы для рендера и физики -----------------------------------------------

func world_x(i: int) -> float:
	return render_x[i]


func world_z(i: int) -> float:
	return render_z[i]


func heading_of(i: int) -> float:
	return render_h[i]


func angular_vel_of(i: int) -> float:
	return angular_vel[i]


func accel_of(i: int) -> float:
	return accel_val[i]


func steer_of(i: int) -> float:
	return steer_angle[i]


func type_of(i: int) -> TrafficTypeData:
	return type_ref[i]


func color_of(i: int) -> Color:
	return body_color[i]


func is_turning(i: int) -> bool:
	return turning[i] == 1


## Ребро вида — дуга кольца. Публично ради полигонов и тестов: снаружи графа
## города дуг не видно, они существуют только в производном виде.
func is_arc(e: int) -> bool:
	return _arc[e] == 1


## Стоп-сигнал — заметное продольное замедление (BRAKE_ACCEL_THRESHOLD).
func is_braking(i: int) -> bool:
	return accel_val[i] < -BRAKE_ACCEL_THRESHOLD


## Поворотник борта -X («сторона A») — горит, пока машина реально в повороте
## (turning[i]) и угловая скорость направлена в эту сторону, промодулировано
## общим таймером мигания.
func turn_a_on(i: int) -> bool:
	return turning[i] == 1 and turn_blink_on and angular_vel[i] < -TURN_ANGVEL_THRESHOLD


## Поворотник борта +X («сторона B»).
func turn_b_on(i: int) -> bool:
	return turning[i] == 1 and turn_blink_on and angular_vel[i] > TURN_ANGVEL_THRESHOLD


func speed_of(i: int) -> float:
	return speed[i]
