class_name PoliceManager
extends RefCounted
## Полицейские штрафы и погоня. Порт police.js + chaseLevel (chase_level).
##
## Нарушения фиксируются только при наличии патруля в радиусе детекции
## и в прямой видимости (здания не пропускают взгляд). Погоня (wanted >= 4)
## — новый функционал: ближайший патруль выходит из потока трафика и
## преследует игрока по дорожному графу.
##
## [b]Отложено сознательно: «въезд на кольцо без уступания».[/b] На кольце
## светофора нет вовсе (`NodeSignalController` пропускает узлы вида
## `ROUNDABOUT`), поэтому `check_red_light` там молча не срабатывает — это
## правильно, а не пробел в проверке. Отдельного нарушения «не уступил тому,
## кто уже на дуге» здесь НЕТ: правило приоритета кольца живёт в трафике
## (`TrafficManager._rule_intersection_priority`, `RING_YIELD_DIST`) и знает
## о дугах через приватный `_arc`, которого у полиции нет. Чтобы штрафовать
## за него, пришлось бы либо открыть трафику новый публичный запрос «есть ли
## машина на дуге в N метрах от узла», либо продублировать разметку дуг здесь
## — и то и другое дороже самого нарушения. Пункт открытый, а не закрытый:
## увидев его в плане следующего этапа, начинать надо с публичного запроса к
## `TrafficManager`, а не с копии данных.

## Штраф зафиксирован — на него подписывается StyleService, чтобы оборвать
## комбо заказов (game.js:472).
signal violation_fined(id: StringName)

## Розыск спал до нуля — побег от полиции. peak_level — максимальный уровень
## за погоню, используется для силы тряски камеры (game.js:484-485).
signal escaped(peak_level: int)

## Статический хеш зданий для проверки видимости. Обёртка над SpatialHash2D
## с дополнительным запросом «отрезок- AABB».
##
## Здание может быть повёрнуто (`CityPlan.building_yaw`, этап 5), поэтому в
## хеш кладётся мировой AABB вокруг повёрнутого габарита — он только
## отсеивает кандидатов, — а решает точный тест: отрезок переводится в
## собственные оси здания, и там работает тот же слэб-метод. Запаса на AABB
## вместо честного OBB не делается: приближение «толще» дома на его диагональ
## (у корпуса 22x12 это лишние 8 м с угла), и патруль засчитывал бы нарушение
## сквозь двор — а видимость это правило игры, а не косметика.
class BuildingHash extends RefCounted:
	var _hash: SpatialHash2D
	## Параллельно хешу: центр, полугабарит и поворот. Индексы совпадают —
	## `SpatialHash2D` возвращает индексы в порядке добавления.
	var _center: PackedVector2Array = PackedVector2Array()
	var _half: PackedVector2Array = PackedVector2Array()
	var _yaw: PackedFloat32Array = PackedFloat32Array()

	func _init() -> void:
		_hash = SpatialHash2D.new(16.0)

	func build(plan: CityPlan) -> void:
		_hash.clear()
		_center = PackedVector2Array()
		_half = PackedVector2Array()
		_yaw = PackedFloat32Array()
		for i in plan.building_count():
			var box := plan.building_world_aabb(i)
			_hash.add_rect(box.position.x, box.position.y, box.end.x, box.end.y)
			_center.append(plan.building_center(i))
			_half.append(plan.building_size(i) * 0.5)
			_yaw.append(plan.building_yaw[i])

	## Пересекает ли отрезок (x0,z0)→(x1,z1) хотя бы одно здание.
	## Использует bounding-circle кандидатов + точный segment-OBB тест.
	func segment_hits(x0: float, z0: float, x1: float, z1: float) -> bool:
		var cx := (x0 + x1) * 0.5
		var cz := (z0 + z1) * 0.5
		var dx := x1 - x0
		var dz := z1 - z0
		var r := sqrt(dx * dx + dz * dz) * 0.5 + 0.5
		for idx: int in _hash.query_circle(cx, cz, r):
			var c := _center[idx]
			var h := _half[idx]
			var yaw := _yaw[idx]
			if is_zero_approx(yaw):
				if _seg_hits_aabb(x0, z0, x1, z1,
						c.x - h.x, c.y - h.y, c.x + h.x, c.y + h.y):
					return true
				continue
			# Поворот отрезка на -yaw вокруг центра дома: в его осях коробка
			# снова осеаксиальная, и годится тот же слэб-метод.
			var a := _to_local(x0, z0, c, yaw)
			var b := _to_local(x1, z1, c, yaw)
			if _seg_hits_aabb(a.x, a.y, b.x, b.y, -h.x, -h.y, h.x, h.y):
				return true
		return false

	## Точка в осях здания: обратный поворот к `CityPlan.building_corners()`,
	## где локальный +X уходит в мир как (cos yaw, -sin yaw).
	static func _to_local(x: float, z: float, center: Vector2,
			yaw: float) -> Vector2:
		var dx := x - center.x
		var dz := z - center.y
		var cs := cos(yaw)
		var sn := sin(yaw)
		return Vector2(dx * cs - dz * sn, dx * sn + dz * cs)

	## 2D segment-AABB intersection (Slab method, port segmentIntersectsAABB).
	static func _seg_hits_aabb(x0: float, z0: float, x1: float, z1: float,
			ax: float, az: float, bx: float, bz: float) -> bool:
		var dx := x1 - x0
		var dz := z1 - z0
		var inv_dx := 1.0 / dx if not is_zero_approx(dx) else INF
		var inv_dz := 1.0 / dz if not is_zero_approx(dz) else INF
		var t0x := (ax - x0) * inv_dx
		var t1x := (bx - x0) * inv_dx
		if t0x > t1x:
			var tmp := t0x
			t0x = t1x
			t1x = tmp
		var t0z := (az - z0) * inv_dz
		var t1z := (bz - z0) * inv_dz
		if t0z > t1z:
			var tmp := t0z
			t0z = t1z
			t1z = tmp
		var t_enter := maxf(t0x, t0z)
		var t_exit := minf(t1x, t1z)
		return t_enter <= t_exit and t_exit >= 0.0 and t_enter <= 1.0


## Радиус зоны фиксации проезда на красный вокруг узла, м. Прежняя сеточная
## проверка ловила игрока не дальше 8 м до оси перекрёстка (порт police.js), и
## окно сохранено ровно таким: на графе те же 8 м отмеряются от позиции узла.
## Для масштаба: трафик останавливается у стоп-линии в 6.5 м
## (`TrafficManager.STOP_LINE`), то есть окно штрафа начинается там, где
## законопослушная машина уже стоит.
const RED_LIGHT_ZONE := 8.0

## Скорость, ниже которой проезд на красный не считается проездом, м/с
## (значение из police.js). Медленнее — игрок докатывается к стоп-линии и
## тормозит, а не проскакивает перекрёсток.
const RED_LIGHT_MIN_SPEED := 3.0


## Нарушение ПДД.
class Violation extends RefCounted:
	var id: StringName
	var fine: int
	var rating_loss: int
	var cooldown: float

	func _init(p_id: StringName, p_fine: int, p_rating: int, p_cd: float) -> void:
		id = p_id
		fine = p_fine
		rating_loss = p_rating
		cooldown = p_cd


# Нарушения — неизменяемые данные. Хранятся как var, т.к. GDScript не даёт
# `const` с конструкцией new(). Значения = константы police.js VIOLATIONS.
var _v_speeding := Violation.new(&"speeding", 300, 3, 8.0)
var _v_red_light := Violation.new(&"red_light", 500, 5, 10.0)
var _v_hit_ped := Violation.new(&"hit_ped", 800, 10, 12.0)
var _v_ped_punch := Violation.new(&"ped_punch", 500, 5, 15.0)

var wanted_level: int = 0
var _decay_paused := false

var _cd_speeding := 0.0
var _cd_red_light := 0.0
var _cd_hit_ped := 0.0
var _cd_ped_punch := 0.0
var _wanted_decay := 0.0
var _peak_wanted := 0

## Индекс преследуемой машины в TrafficManager (-1 = нет погони).
var chase_idx: int = -1
var _chase_t := 0.0

var _traffic: TrafficManager
var _field: CityField
var _roads: CityGraph
var _signals: NodeSignalController
var _wanted: WantedConfig
var _building_hash: BuildingHash
var _escape_pending := false
var _escape_peak := 0


func setup(traffic: TrafficManager, field: CityField, roads: CityGraph,
		signals: NodeSignalController, wanted_cfg: WantedConfig,
		plan: CityPlan) -> void:
	_traffic = traffic
	_field = field
	_roads = roads
	_signals = signals
	_wanted = wanted_cfg if wanted_cfg != null else WantedConfig.new()
	_building_hash = BuildingHash.new()
	if plan != null:
		_building_hash.build(plan)


# --- Вспомогательные --------------------------------------------------------

## Прямая видимость патруля до игрока. Перекрывают её только ЗДАНИЯ:
## `BuildingHash` строится из `CityPlan.building_*` и ничего другого из плана
## не читает.
##
## Из этого следуют оба ответа на вопрос «мосты и видимость» (этап 9) — и оба
## уже верны без правок:
##  - дека путепровода (`BridgeGeometry`) в `CityPlan.building_*` не попадает
##    вовсе, поэтому патруль под мостом видит игрока на той стороне — ровно
##    то поведение, которого требует план;
##  - опоры моста (`BridgeGeometry.pier_*`) тоже не попадают, как и фонарные
##    столбы (`CityPlan.lamp_pos`): и те и другие живут только в
##    `CityCollision` — физика, в которую можно въехать, а не преграда для
##    взгляда. Столб опоры радиусом 0.54 м перекрывал бы линию взгляда на
##    доли градуса; модель здесь простая и намеренная — «дома перекрывают,
##    уличная мебель нет», и опора моста относится ко второй категории.
func _has_los(x0: float, z0: float, x1: float, z1: float) -> bool:
	return not _building_hash.segment_hits(x0, z0, x1, z1)


func _police_nearby(px: float, pz: float) -> bool:
	if _traffic == null:
		return false
	var radius := _wanted.effective_detect_radius(wanted_level)
	for i: int in _traffic.count:
		if _traffic.type_ref[i].id != &"police":
			continue
		var wx := _traffic.world_x(i)
		var wz := _traffic.world_z(i)
		if MathUtils.dist_2d(wx, wz, px, pz) >= radius:
			continue
		if not _has_los(wx, wz, px, pz):
			continue
		return true
	return false


func _on_cooldown(v: Violation) -> bool:
	match v.id:
		&"speeding":
			return _cd_speeding > 0.0
		&"red_light":
			return _cd_red_light > 0.0
		&"hit_ped":
			return _cd_hit_ped > 0.0
		&"ped_punch":
			return _cd_ped_punch > 0.0
	return false


# --- Проверки нарушений -----------------------------------------------------

## `py` — высота игрока: без неё `on_road` опрашивает граф с отметки рельефа
## и на деке путепровода отвечает «не на дороге» (`CityField._probe_y`).
func check_speeding(px: float, py: float, pz: float, speed: float) -> void:
	if _on_cooldown(_v_speeding):
		return
	if absf(speed) < _wanted.speed_threshold:
		return
	if _field != null and not _field.on_road(px, pz, py):
		return
	if not _police_nearby(px, pz):
		return
	_fine(_v_speeding)


## Проезд на красный: ближайший регулируемый узел графа + подход, на который
## выезжает игрок.
##
## Осевой адресации «индекс сетки + одна из двух осей» здесь больше нет: у
## узла степени 3 или 5 понятие «ось» не определено, а сравнение курса с
## `absf(cos_h) > absf(sin_h)` предполагало прямоугольную решётку. Подход
## находится по УГЛУ — тем же приёмом, что у трафика
## (`TrafficManager._light_ahead`).
func check_red_light(px: float, py: float, pz: float, speed: float,
		heading: float) -> void:
	if _on_cooldown(_v_red_light):
		return
	if absf(speed) < RED_LIGHT_MIN_SPEED:
		return
	if _field != null and not _field.on_road(px, pz, py):
		return
	if _roads == null or _signals == null:
		return
	if not _police_nearby(px, pz):
		return

	# Ближайший узел, а не перебор регулируемых: `nearest_node` разводит ярусы
	# по высоте, и на деке путепровода игрок не привяжется к перекрёстку под
	# ней. Нерегулируемый узел отказывает сам — в том числе кольцо, где
	# светофора не бывает вовсе (см. заметку об отложенном нарушении вверху).
	var node := _roads.nearest_node(Vector3(px, py, pz))
	if node < 0 or not _signals.is_regulated(node):
		return
	var np := _roads.node_position(node)
	if MathUtils.dist_2d(px, pz, np.x, np.z) > RED_LIGHT_ZONE:
		return
	# Узел обязан быть ВПЕРЕДИ по курсу: выехавшего с перекрёстка не штрафуют
	# второй раз на выезде (прежняя проверка `ahead > 0`).
	var fwd := Heading.forward(heading)
	if (np.x - px) * fwd.x + (np.z - pz) * fwd.z <= 0.0:
		return
	# Подход, по которому игрок ПОДЪЕЗЖАЕТ, отходит от узла назад по его
	# курсу: углы подходов заданы как atan2(dz, dx) направления ОТ узла.
	var approach := _signals.approach_at_angle(node, atan2(-fwd.z, -fwd.x))
	if _signals.car_state(node, approach) == NodeSignalController.State.RED:
		_fine(_v_red_light)


func check_hit_ped(px: float, pz: float) -> void:
	if _on_cooldown(_v_hit_ped):
		return
	if not _police_nearby(px, pz):
		return
	_fine(_v_hit_ped)


func check_punch_ped(px: float, pz: float) -> void:
	if _on_cooldown(_v_ped_punch):
		return
	if not _police_nearby(px, pz):
		return
	_fine(_v_ped_punch)


func is_police_nearby(px: float, pz: float) -> bool:
	return _police_nearby(px, pz)


# --- Штраф и розыск ---------------------------------------------------------

func _fine(v: Violation) -> void:
	match v.id:
		&"speeding":
			_cd_speeding = v.cooldown
		&"red_light":
			_cd_red_light = v.cooldown
		&"hit_ped":
			_cd_hit_ped = v.cooldown
		&"ped_punch":
			_cd_ped_punch = v.cooldown

	wanted_level = clampi(wanted_level + 1, 1, _wanted.max_level)
	_wanted_decay = _wanted.decay_time
	if wanted_level > _peak_wanted:
		_peak_wanted = wanted_level
	Bus.wanted_changed.emit(wanted_level)

	var mult := _wanted.fine_mult(wanted_level)
	var scaled_fine := roundi(v.fine * mult)
	var scaled_rating := roundi(v.rating_loss * mult)
	Game.spend(scaled_fine)
	Game.add_rating(-scaled_rating)
	Game.bump("", "police_fines", 1.0)
	Bus.notify.emit(&"toast",
		"🚨 %s Штраф: %d ₽, рейтинг -%d" % [v.id, scaled_fine, scaled_rating],
		{"level": &"critical"})
	violation_fined.emit(v.id)


## `py` — высота игрока, нужна проверкам нарушений для дизамбигуации яруса
## развязки (см. `check_speeding`).
func update(delta: float, px: float, py: float, pz: float, in_car: bool,
		speed: float = 0.0, heading: float = 0.0) -> void:
	_decay_paused = in_car and _police_nearby(px, pz)

	_cd_speeding = maxf(0.0, _cd_speeding - delta)
	_cd_red_light = maxf(0.0, _cd_red_light - delta)
	_cd_hit_ped = maxf(0.0, _cd_hit_ped - delta)
	_cd_ped_punch = maxf(0.0, _cd_ped_punch - delta)

	if in_car:
		check_speeding(px, py, pz, speed)
		check_red_light(px, py, pz, speed, heading)

	_update_chase(delta, px, pz)

	if wanted_level > 0 and not _decay_paused:
		_wanted_decay -= delta
		if _wanted_decay <= 0.0:
			wanted_level -= 1
			Bus.wanted_changed.emit(wanted_level)
			if wanted_level > 0:
				_wanted_decay = _wanted.decay_time
			else:
				_wanted_decay = 0.0
				_escape_pending = true
				_escape_peak = maxi(_peak_wanted, 1)

	if _escape_pending:
		_escape_pending = false
		var peak: int = _escape_peak
		_peak_wanted = 0
		var reward := _wanted.escape_reward_per_level * peak
		var rating_bonus := _wanted.escape_rating_bonus * peak
		Game.add_money(reward)
		Game.add_rating(rating_bonus)
		Game.bump("escapes", "total_escapes", 1.0)
		Game.track_max("max_escape_level", float(peak))
		Bus.notify.emit(&"toast",
			"✅ Побег от полиции! +%d ₽, +%d рейтинга" % [reward, rating_bonus],
			{"level": &"reward"})
		escaped.emit(peak)


# --- Погоня -----------------------------------------------------------------

func _update_chase(delta: float, px: float, pz: float) -> void:
	if chase_idx >= 0:
		_chase_t += delta
		if wanted_level < _wanted.chase_level:
			_break_chase()
			return
		if _chase_t > 60.0:
			_break_chase()
			return
		var wx := _traffic.world_x(chase_idx)
		var wz := _traffic.world_z(chase_idx)
		if MathUtils.dist_2d(wx, wz, px, pz) > 120.0:
			_break_chase()
			return
		# Обновляем цель преследования; движение ведёт TrafficManager.
		_traffic.chase_target_x = px
		_traffic.chase_target_z = pz
		return

	if wanted_level < _wanted.chase_level:
		return

	var best_idx := -1
	var best_dist := INF
	for i: int in _traffic.count:
		if _traffic.type_ref[i].id != &"police":
			continue
		if _traffic.is_turning(i):
			continue
		var d := MathUtils.dist_2d(
			_traffic.world_x(i), _traffic.world_z(i), px, pz)
		if d < best_dist:
			best_dist = d
			best_idx = i

	if best_idx < 0 or best_dist > _wanted.effective_detect_radius(wanted_level):
		return

	chase_idx = best_idx
	_chase_t = 0.0
	_traffic.chase_idx = best_idx
	_traffic.chase_target_x = px
	_traffic.chase_target_z = pz


func _break_chase() -> void:
	if chase_idx < 0:
		return
	var i := chase_idx
	chase_idx = -1
	_chase_t = 0.0
	_traffic.chase_idx = -1
	_traffic.speed[i] = 10.0
	_traffic.target[i] = 10.0
	# Возврат в обычный поток трафика: перезапуск ведётся нормальным AI.
	_traffic.turning[i] = 0


# --- Сброс ------------------------------------------------------------------

func reset() -> void:
	_cd_speeding = 0.0
	_cd_red_light = 0.0
	_cd_hit_ped = 0.0
	_cd_ped_punch = 0.0
	wanted_level = 0
	_wanted_decay = 0.0
	_peak_wanted = 0
	_escape_pending = false
	_break_chase()
