class_name TrafficManager
extends RefCounted
## ИИ городского трафика. Дословный порт TrafficManager.update() (traffic.js:317-579),
## переложенный на SoA-массивы вместо массива объектов: правило проекта
## «RefCounted вместо Node для агентов» и «Ноль аллокаций в hot path»
## (см. .agents/rules/gdscript-style.md).
##
## Машины ездят «на рельсах» (axis, coord, pos, dir) — мировая позиция
## считается из этой четвёрки (_world_pos_for), а не хранится отдельно.
## 10 правил ИИ оригинала реализованы по приоритету; правила 4-7 (пешеходы
## на зебре, наезд на пешехода/игрока-пешехода) добавятся вместе с этапом 8
## (PedGraph уже готов, но менеджера пешеходов ещё нет — вводить сейчас
## параметры без единственного вызывающего значило бы проектировать под
## гипотетическое будущее).
##
## Позиция для ПРАВИЛ (axis/coord/pos/dir) и позиция для РЕНДЕРА
## (render_x/z/h) намеренно разделены: в оригинале во время поворота машина
## визуально идёт по кривой Безье, а её axis/coord/pos остаются заморожены
## до завершения поворота (car.turn.newAxis и т.д. применяются только при
## k>=1). Все проверки светофора/дистанции/приоритета в это время читают
## СТАРУЮ полосу — это поведение оригинала, а не баг порта.

const Z_ROAD := TrafficLightController.Axis.Z_ROAD
const X_ROAD := TrafficLightController.Axis.X_ROAD

## Слой физики для коллайдеров трафика (PlayerCar добавляет его в свою
## collision_mask, чтобы не проезжать машины NPC насквозь).
const COLLISION_LAYER := 4

## Смещение полосы от оси дороги: правостороннее движение (traffic.js:304).
const LANE_OFFSET := 2.5

const SPEED_ACCEL := 5.0
const SPEED_DECEL := -10.0
const SPEED_MAX := 18.0

const RESPAWN_DIST := 260.0
const EDGE_LIMIT := 250.0
const UTURN_TRIGGER_SPEED := 2.0
const UTURN_TRIGGER_TIME := 1.2
const UTURN_NEW_POS_LIMIT := 245.0
const UTURN_BACK_OFFSET := 4.0
const UTURN_TURN_SPEED := 5.0

const CHOOSE_STRAIGHT_P := 0.58
const CHOOSE_RIGHT_P := 0.8
const TURN_EXIT_OFFSET := 4.5
const TURN_SPEED := 7.0
const TURN_T_COOLDOWN := 0.3
const INTERSECTION_CHOOSE_TOL := 2.5
const INTERSECTION_STOP_TOL := 7.0
const INTERSECTION_TURN_YIELD_DIST := 8.5

const FOLLOW_MIN_DIST := 6.0
const EMERGENCY_YIELD_DIST := 25.0
const EMERGENCY_TARGET_CAP := 3.0

const PLAYER_AHEAD_DIST := 14.0
const PLAYER_AHEAD_LATERAL := 5.5
const PLAYER_AHEAD_TARGET := 2.0

## Правила 4-6 (пешеходы, traffic.js:397-452).
const PED_YIELD_LATERAL := 7.5
const PED_YIELD_LONGITUDINAL := 24.0
const PED_YIELD_DIST_AGGR := 6.0
const PED_YIELD_DIST_NORMAL := 20.0
const HIT_PED_RADIUS_MARGIN := 0.65
const HIT_PED_SPEED_THRESHOLD := 2.5
const HIT_PED_SPEED_REDUCTION := 3.5
const TURN_YIELD_PED_DIST_AGGR := 6.0
const TURN_YIELD_PED_DIST_NORMAL := 10.0

const STOP_LINE := 6.5
const LIGHT_LOOKAHEAD := 30.0
const RED_OVERSHOOT := 3.0

const BEACON_PERIOD := 0.6

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
var lights: TrafficLightController
var rng: SeededRng
## Необязательная ссылка на пешеходов (этап 8) — правила 4-6 (уступить на
## зебре, наезд, уступить при повороте) выключены, пока она null. Правило 7
## (наезд на игрока-пешехода) ждёт пешего режима игрока (этап 9).
var peds: PedManager

var type_ref: Array[TrafficTypeData] = []
var body_color: PackedColorArray = PackedColorArray()

## Состояние «на рельсах» — правило ПДД читает только эти четыре массива.
var axis: PackedByteArray = PackedByteArray()
var coord: PackedFloat32Array = PackedFloat32Array()
var pos: PackedFloat32Array = PackedFloat32Array()
var dir: PackedFloat32Array = PackedFloat32Array()

var speed: PackedFloat32Array = PackedFloat32Array()
var target: PackedFloat32Array = PackedFloat32Array()
var aggressive: PackedByteArray = PackedByteArray()
var turn_t: PackedFloat32Array = PackedFloat32Array()
var turn_around_t: PackedFloat32Array = PackedFloat32Array()
## 0 — решение не принято, 1 — не проезжать на красный, 2 — проехать.
var run_red: PackedByteArray = PackedByteArray()

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
var t_from_h: PackedFloat32Array = PackedFloat32Array()
var t_speed: PackedFloat32Array = PackedFloat32Array()
var t_new_axis: PackedByteArray = PackedByteArray()
var t_new_coord: PackedFloat32Array = PackedFloat32Array()
var t_new_pos: PackedFloat32Array = PackedFloat32Array()
var t_new_dir: PackedFloat32Array = PackedFloat32Array()

## Позиция и курс для рендера — см. комментарий класса.
var render_x: PackedFloat32Array = PackedFloat32Array()
var render_z: PackedFloat32Array = PackedFloat32Array()
var render_h: PackedFloat32Array = PackedFloat32Array()

## Маячок полиции/скорой: единый таймер на все машины, читается TrafficLayer.
var beacon_red_on := true
var _beacon_t := 0.0

var _light_buf := LightInfo.new()


func setup(catalog_: TrafficCatalog, field_: CityField,
		lights_: TrafficLightController, rng_: SeededRng, traffic_count: int) -> void:
	catalog = catalog_
	field = field_
	lights = lights_
	rng = rng_
	count = maxi(0, traffic_count)
	_resize(count)

	var police_id := &"police"
	var has_police := false
	for i in count:
		var t: TrafficTypeData = null
		var force_police := i == count - 1 and not has_police \
			and catalog.get_type(police_id) != null
		t = catalog.get_type(police_id) if force_police else catalog.roll(rng)
		if t == null:
			t = TrafficTypeData.new()
		type_ref[i] = t
		has_police = has_police or t.id == police_id
		body_color[i] = _pick_color(t)
		aggressive[i] = 1 if rng.chance(catalog.aggressive_ratio) else 0
		axis[i] = Z_ROAD
		coord[i] = 0.0
		pos[i] = 0.0
		dir[i] = 1.0
		speed[i] = 0.0
		target[i] = 10.0
		turning[i] = 0
		turn_t[i] = 0.0
		turn_around_t[i] = 0.0
		run_red[i] = 0
		render_x[i] = 0.0
		render_z[i] = 0.0
		render_h[i] = 0.0


func _pick_color(t: TrafficTypeData) -> Color:
	if t.colors.is_empty():
		return Color.WHITE
	return t.colors[0] if t.force_color else rng.pick_color(t.colors)


func _resize(n: int) -> void:
	type_ref.resize(n)
	body_color.resize(n)
	axis.resize(n)
	coord.resize(n)
	pos.resize(n)
	dir.resize(n)
	speed.resize(n)
	target.resize(n)
	aggressive.resize(n)
	turn_t.resize(n)
	turn_around_t.resize(n)
	run_red.resize(n)
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
	t_from_h.resize(n)
	t_speed.resize(n)
	t_new_axis.resize(n)
	t_new_coord.resize(n)
	t_new_pos.resize(n)
	t_new_dir.resize(n)
	render_x.resize(n)
	render_z.resize(n)
	render_h.resize(n)


# --- Размещение ---------------------------------------------------------------

func place_all_near(player_x: float, player_z: float) -> void:
	for i in count:
		place_near(i, player_x, player_z)


## Порт placeNear() (traffic.js:243-260): новая случайная полоса за пределами
## ближнего поля зрения игрока, скорость и повадки перебрасываются заново.
func place_near(i: int, player_x: float, player_z: float) -> void:
	var spot := _rand_road(player_x, player_z)
	axis[i] = spot.axis
	coord[i] = spot.coord
	pos[i] = spot.pos
	dir[i] = spot.dir
	turning[i] = 0
	turn_t[i] = 0.0
	turn_around_t[i] = 0.0
	run_red[i] = 0
	speed[i] = rng.randf_range(6.0, 13.0)
	target[i] = speed[i]
	aggressive[i] = 1 if rng.chance(catalog.aggressive_ratio) else 0
	_sync_render(i)


class RoadSpot extends RefCounted:
	var axis := 0
	var coord := 0.0
	var pos := 0.0
	var dir := 1.0


## Порт _randRoad() (traffic.js:280-298): случайная полоса не ближе 75 м
## от игрока, чтобы машины не «выскакивали» перед глазами.
func _rand_road(player_x: float, player_z: float) -> RoadSpot:
	var best: RoadSpot = null
	for _attempt in 10:
		var spot := RoadSpot.new()
		spot.dir = 1.0 if rng.chance(0.5) else -1.0
		if rng.chance(0.5):
			spot.axis = Z_ROAD
			spot.coord = clampf(
				roundf((player_x + rng.randf_range(-80.0, 80.0)) / field.cell) * field.cell,
				-256.0, 256.0)
			spot.pos = clampf(player_z + rng.randf_range(-140.0, 140.0), -256.0, 256.0)
		else:
			spot.axis = X_ROAD
			spot.coord = clampf(
				roundf((player_z + rng.randf_range(-80.0, 80.0)) / field.cell) * field.cell,
				-256.0, 256.0)
			spot.pos = clampf(player_x + rng.randf_range(-140.0, 140.0), -256.0, 256.0)
		var wp := _world_pos_for(spot.axis, spot.coord, spot.pos, spot.dir)
		if MathUtils.dist_2d(wp.x, wp.y, player_x, player_z) >= 75.0:
			return spot
		best = spot
	return best


# --- Геометрия полосы ----------------------------------------------------------

## Мировая точка правой полосы (traffic.js:_worldPos, 300-311).
func _world_pos_for(car_axis: int, c: float, p: float, d: float) -> Vector2:
	if car_axis == Z_ROAD:
		return Vector2(c - d * LANE_OFFSET, p)
	return Vector2(p, c + d * LANE_OFFSET)


func _world_pos_at(i: int, custom_pos: float) -> Vector2:
	return _world_pos_for(axis[i], coord[i], custom_pos, dir[i])


func _lane_world_pos(i: int) -> Vector2:
	return _world_pos_for(axis[i], coord[i], pos[i], dir[i])


func _lane_heading(i: int) -> float:
	if axis[i] == Z_ROAD:
		return 0.0 if dir[i] > 0.0 else PI
	return PI * 0.5 if dir[i] > 0.0 else -PI * 0.5


func _sync_render(i: int) -> void:
	var wp := _lane_world_pos(i)
	render_x[i] = wp.x
	render_z[i] = wp.y
	render_h[i] = _lane_heading(i)


func _axis_index(v: float) -> int:
	return clampi(roundi((v - field.road_axes[0]) / field.cell), 0, field.road_axes.size() - 1)


func _nearest_axis_value(v: float) -> float:
	return field.road_axes[_axis_index(v)]


# --- Обновление -----------------------------------------------------------------

## Порт TrafficManager.update() (traffic.js:317-579). Пешеходные правила
## (4-7 из плана) вернутся вместе с этапом 8 — сейчас их не вызвать: нет ни
## менеджера пешеходов, ни пешехода-игрока.
func update(delta: float, player_x: float, player_z: float, density: float) -> void:
	_beacon_t = fmod(_beacon_t + delta, BEACON_PERIOD)
	beacon_red_on = _beacon_t < BEACON_PERIOD * 0.5

	var bucket := _build_bucket()

	for i in count:
		var wp := _lane_world_pos(i)
		if MathUtils.dist_2d(wp.x, wp.y, player_x, player_z) > RESPAWN_DIST:
			place_near(i, player_x, player_z)
			continue

		if turning[i] == 0 and absf(pos[i]) > EDGE_LIMIT:
			turn_around_t[i] += delta
			if speed[i] < UTURN_TRIGGER_SPEED or turn_around_t[i] > UTURN_TRIGGER_TIME:
				_start_uturn(i)
				turn_around_t[i] = 0.0

		_apply_base_target(i, density)
		_rule_offroad_ahead(i)
		_rule_yield_emergency(i, bucket)
		_rule_following_distance(i, bucket)
		if peds != null:
			_rule_yield_crossing_ped(i)
			_rule_hit_pedestrian(i)
			if turning[i] == 1:
				_rule_yield_turning_ped(i)
		if turning[i] == 0:
			_rule_intersection_priority(i)
		_rule_player_ahead(i, player_x, player_z)
		_rule_traffic_light(i)

		_integrate_speed(i, delta)

		if turning[i] == 1:
			_advance_turn(i, delta)
			continue

		pos[i] += speed[i] * delta * dir[i]
		if turn_t[i] > 0.0:
			turn_t[i] -= delta
		else:
			var nv := _nearest_axis_value(pos[i])
			if absf(pos[i] - nv) < INTERSECTION_CHOOSE_TOL:
				var isec_x := coord[i] if axis[i] == Z_ROAD else nv
				var isec_z := nv if axis[i] == Z_ROAD else coord[i]
				_choose_direction(i, isec_x, isec_z)
		_sync_render(i)


func _bucket_key(car_axis: int, c: float) -> int:
	return MathUtils.hash_key(car_axis, roundi(c))


## Бакеты по (axis, coord): следование и уступание спецтранспорту сравнивают
## машину только с соседями по своей полосе, а не со всеми (архитектура,
## план: «Бакетизация... это чинит дефект №5 (O(n²))»).
func _build_bucket() -> Dictionary[int, PackedInt32Array]:
	var b: Dictionary[int, PackedInt32Array] = {}
	for i in count:
		var key := _bucket_key(axis[i], coord[i])
		if not b.has(key):
			b[key] = PackedInt32Array()
		b[key].append(i)
	return b


func _apply_base_target(i: int, density: float) -> void:
	var is_aggr := aggressive[i] == 1
	var base_target: float
	if is_aggr:
		base_target = rng.randf_range(9.0, 15.0) * density * 1.25
	else:
		base_target = rng.randf_range(7.0, 13.0) * density
	target[i] = clampf(base_target, 4.0, 18.0 if is_aggr else 16.0)


## Правило 1: пропсы на пути. В этом городе генератор не ставит препятствия
## на проезжую часть (в отличие от вольного скаттера оригинала) — реальная
## опасность впереди здесь одна: съехать с дороги. Проверяем именно это.
func _rule_offroad_ahead(i: int) -> void:
	var ahead := _world_pos_at(i, pos[i] + dir[i] * 5.0)
	if not field.on_road(ahead.x, ahead.y):
		target[i] = 0.0


## Правило 2: уступить спецтранспорту с мигалкой, идущему сзади в своей полосе.
func _rule_yield_emergency(i: int, bucket: Dictionary[int, PackedInt32Array]) -> void:
	if type_ref[i].beacon != &"":
		return
	var key := _bucket_key(axis[i], coord[i])
	if not bucket.has(key):
		return
	for j: int in bucket[key]:
		if j == i or type_ref[j].beacon == &"" or dir[j] != dir[i]:
			continue
		var d := (pos[i] - pos[j]) * dir[j]
		if d > 0.0 and d < EMERGENCY_YIELD_DIST:
			target[i] = minf(target[i], EMERGENCY_TARGET_CAP)
			return


## Правило 3: динамическая дистанция до впереди идущего в своей полосе.
func _rule_following_distance(i: int, bucket: Dictionary[int, PackedInt32Array]) -> void:
	var key := _bucket_key(axis[i], coord[i])
	if not bucket.has(key):
		return
	for j: int in bucket[key]:
		if j == i or dir[j] != dir[i]:
			continue
		var d := (pos[j] - pos[i]) * dir[i]
		var safe_dist := (speed[i] * 0.8 + 2.0) if aggressive[i] == 1 \
			else (speed[i] * 1.5 + 4.0)
		if d > 0.0 and d < maxf(FOLLOW_MIN_DIST, safe_dist):
			target[i] = minf(target[i], maxf(0.0, speed[j] - 1.5))
			return


## Правило 4: уступить пешеходу, уже вышедшему на переход в своей полосе —
## порт участка «уступание дороги» из traffic.js:397-415 (без ругани — нет
## речевых пузырей, см. комментарий у поля `peds`).
func _rule_yield_crossing_ped(i: int) -> void:
	for p in peds.count:
		if not peds.is_crossing_or_waiting(p):
			continue
		var px := peds.world_x(p)
		var pz := peds.world_z(p)
		var lateral := absf(px - coord[i]) if axis[i] == Z_ROAD else absf(pz - coord[i])
		if lateral > PED_YIELD_LATERAL:
			continue
		var ped_along := pz if axis[i] == Z_ROAD else px
		var d := (ped_along - pos[i]) * dir[i]
		if d <= 0.0 or d >= PED_YIELD_LONGITUDINAL:
			continue
		var yield_dist := PED_YIELD_DIST_AGGR if aggressive[i] == 1 else PED_YIELD_DIST_NORMAL
		if d < yield_dist:
			target[i] = 0.0
			return


## Правило 5: наезд машины трафика на пешехода — порт traffic.js:417-437.
func _rule_hit_pedestrian(i: int) -> void:
	var r := type_ref[i].radius + HIT_PED_RADIUS_MARGIN
	for p in peds.count:
		if peds.mode_of(p) == PedManager.Mode.KNOCKED or peds.mode_of(p) == PedManager.Mode.FLEE:
			continue
		var dx := render_x[i] - peds.world_x(p)
		var dz := render_z[i] - peds.world_z(p)
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
	var yield_dist := TURN_YIELD_PED_DIST_AGGR if aggressive[i] == 1 else TURN_YIELD_PED_DIST_NORMAL
	for p in peds.count:
		if not peds.is_crossing_or_waiting(p):
			continue
		var d := MathUtils.dist_2d(render_x[i], render_z[i], peds.world_x(p), peds.world_z(p))
		if d < yield_dist:
			target[i] = 0.0
			return


## Правило 8: машина без поворота уступает уже поворачивающей рядом
## с тем же перекрёстком.
func _rule_intersection_priority(i: int) -> void:
	var nv := _nearest_axis_value(pos[i])
	if absf(pos[i] - nv) >= INTERSECTION_STOP_TOL:
		return
	var isec_x := coord[i] if axis[i] == Z_ROAD else nv
	var isec_z := nv if axis[i] == Z_ROAD else coord[i]
	for j in count:
		if j == i or turning[j] == 0:
			continue
		if MathUtils.dist_2d(render_x[j], render_z[j], isec_x, isec_z) \
				< INTERSECTION_TURN_YIELD_DIST:
			target[i] = 0.0
			return


## Правило 9: машина игрока впереди в той же полосе.
func _rule_player_ahead(i: int, player_x: float, player_z: float) -> void:
	var d_p: float
	var lateral: float
	if axis[i] == Z_ROAD:
		d_p = (player_z - pos[i]) if dir[i] > 0.0 else (pos[i] - player_z)
		lateral = absf(player_x - coord[i])
	else:
		d_p = (player_x - pos[i]) if dir[i] > 0.0 else (pos[i] - player_x)
		lateral = absf(player_z - coord[i])
	if d_p > 0.0 and d_p < PLAYER_AHEAD_DIST and lateral < PLAYER_AHEAD_LATERAL:
		target[i] = minf(target[i], PLAYER_AHEAD_TARGET)


## Правило 10: светофор впереди (traffic.js:497-529). Ближайший перекрёсток
## по ходу движения находится напрямую по регулярной сетке дорог, а не
## перебором списка стоек, как в оригинале — тот же результат дешевле
## и без риска расхождения разметки с логикой.
func _rule_traffic_light(i: int) -> void:
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


## Ближайший регулируемый перекрёсток впереди по ходу движения, если он
## в пределах LIGHT_LOOKAHEAD. Регулируются только перекрёстки с нечётными
## индексами по обеим осям (PedGraph.is_signalized) — как в оригинале, где
## стойки стоят через один.
func _light_ahead(i: int) -> LightInfo:
	var l := _light_buf
	l.found = false
	var p := pos[i]
	var d := dir[i]
	var best := INF
	var candidate := 0.0
	for v in field.road_axes:
		var dist := (v - p) * d
		if dist > 0.0 and dist <= LIGHT_LOOKAHEAD and dist < best:
			best = dist
			candidate = v
			l.found = true
	if not l.found:
		return l

	var idx_candidate := _axis_index(candidate)
	var idx_coord := _axis_index(coord[i])
	var i_idx := idx_coord if axis[i] == Z_ROAD else idx_candidate
	var j_idx := idx_candidate if axis[i] == Z_ROAD else idx_coord
	if not PedGraph.is_signalized(i_idx, j_idx):
		l.found = false
		return l

	l.dist = best
	l.state = lights.car_state(i_idx, axis[i])
	l.isec_x = coord[i] if axis[i] == Z_ROAD else candidate
	l.isec_z = candidate if axis[i] == Z_ROAD else coord[i]
	return l


## Порт _isIntersectionClear() (traffic.js:262-276) без пешеходов — те же
## вернутся с этапом 8.
func _is_intersection_clear(isec_x: float, isec_z: float, self_index: int) -> bool:
	for j in count:
		if j == self_index:
			continue
		var wp := _lane_world_pos(j)
		if MathUtils.dist_2d(wp.x, wp.y, isec_x, isec_z) < 8.5:
			return false
	return true


func _integrate_speed(i: int, delta: float) -> void:
	var diff := target[i] - speed[i]
	speed[i] = clampf(speed[i] + clampf(diff, SPEED_DECEL * delta, SPEED_ACCEL * delta),
		0.0, SPEED_MAX)


# --- Повороты --------------------------------------------------------------------

## Порт _chooseDirection() (traffic.js:589-640): кубическая Безье, касательные
## на концах равны курсу до/после поворота, поэтому нос машины всегда смотрит
## по ходу движения.
func _choose_direction(i: int, isec_x: float, isec_z: float) -> void:
	var roll := rng.next()
	if roll < CHOOSE_STRAIGHT_P:
		turn_t[i] = TURN_T_COOLDOWN
		return
	var right := roll < CHOOSE_RIGHT_P

	var new_axis: int
	var new_coord: float
	var new_dir: float
	if axis[i] == Z_ROAD:
		new_axis = X_ROAD
		new_coord = isec_z
		new_dir = -dir[i] if right else dir[i]
	else:
		new_axis = Z_ROAD
		new_coord = isec_x
		new_dir = dir[i] if right else -dir[i]

	var exit_pos := (isec_x if axis[i] == Z_ROAD else isec_z) + new_dir * TURN_EXIT_OFFSET
	var sdx := 0.0 if axis[i] == Z_ROAD else dir[i]
	var sdz := dir[i] if axis[i] == Z_ROAD else 0.0
	var edx := 0.0 if new_axis == Z_ROAD else new_dir
	var edz := new_dir if new_axis == Z_ROAD else 0.0

	_begin_turn(i, _lane_world_pos(i), _world_pos_for(new_axis, new_coord, exit_pos, new_dir),
		Vector2(sdx, sdz), Vector2(edx, edz), TURN_SPEED)
	t_new_axis[i] = new_axis
	t_new_coord[i] = new_coord
	t_new_pos[i] = exit_pos
	t_new_dir[i] = new_dir
	turn_t[i] = t_arc[i] / maxf(speed[i], 4.0) + TURN_T_COOLDOWN


## Порт _startUTurn() (traffic.js:643-674): разворот на границе карты по той
## же схеме Безье, с касательными, развёрнутыми на 180°.
func _start_uturn(i: int) -> void:
	var new_dir := -dir[i]
	var new_pos := clampf(pos[i] - dir[i] * UTURN_BACK_OFFSET,
		-UTURN_NEW_POS_LIMIT, UTURN_NEW_POS_LIMIT)
	var sdx := 0.0 if axis[i] == Z_ROAD else dir[i]
	var sdz := dir[i] if axis[i] == Z_ROAD else 0.0

	_begin_turn(i, _lane_world_pos(i), _world_pos_for(axis[i], coord[i], new_pos, new_dir),
		Vector2(sdx, sdz), Vector2(-sdx, -sdz), UTURN_TURN_SPEED)
	t_new_axis[i] = axis[i]
	t_new_coord[i] = coord[i]
	t_new_pos[i] = new_pos
	t_new_dir[i] = new_dir


## Общая часть: контрольные точки кубической Безье от касательных на концах
## (traffic.js:619-629 / 654-662, курс в начале = start_tangent, в конце = end_tangent).
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
	t_from_h[i] = _lane_heading(i)
	t_speed[i] = turn_speed


## Продвижение по кривой Безье и завершение поворота (traffic.js:536-563).
func _advance_turn(i: int, delta: float) -> void:
	t_dist[i] += speed[i] * delta
	var k := clampf(t_dist[i] / maxf(t_arc[i], 0.0001), 0.0, 1.0)
	var u := 1.0 - k

	var bx := u * u * u * t_from_x[i] + 3.0 * u * u * k * t_p1x[i] \
		+ 3.0 * u * k * k * t_p2x[i] + k * k * k * t_to_x[i]
	var bz := u * u * u * t_from_z[i] + 3.0 * u * u * k * t_p1z[i] \
		+ 3.0 * u * k * k * t_p2z[i] + k * k * k * t_to_z[i]
	render_x[i] = bx
	render_z[i] = bz

	var dx := 3.0 * u * u * (t_p1x[i] - t_from_x[i]) + 6.0 * u * k * (t_p2x[i] - t_p1x[i]) \
		+ 3.0 * k * k * (t_to_x[i] - t_p2x[i])
	var dz := 3.0 * u * u * (t_p1z[i] - t_from_z[i]) + 6.0 * u * k * (t_p2z[i] - t_p1z[i]) \
		+ 3.0 * k * k * (t_to_z[i] - t_p2z[i])
	var h := t_from_h[i] if is_zero_approx(dx) and is_zero_approx(dz) \
		else Heading.from_vector(Vector3(dx, 0.0, dz))
	render_h[i] = t_from_h[i] + Heading.delta(t_from_h[i], h)

	target[i] = minf(target[i], t_speed[i])
	_integrate_speed(i, delta)

	if k >= 1.0:
		axis[i] = t_new_axis[i]
		coord[i] = t_new_coord[i]
		pos[i] = t_new_pos[i]
		dir[i] = t_new_dir[i]
		turning[i] = 0


# --- Запросы для рендера --------------------------------------------------------

func world_x(i: int) -> float:
	return render_x[i]


func world_z(i: int) -> float:
	return render_z[i]


func heading_of(i: int) -> float:
	return render_h[i]


func type_of(i: int) -> TrafficTypeData:
	return type_ref[i]


func color_of(i: int) -> Color:
	return body_color[i]


func is_turning(i: int) -> bool:
	return turning[i] == 1


func speed_of(i: int) -> float:
	return speed[i]
