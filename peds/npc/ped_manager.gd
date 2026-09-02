class_name PedManager
extends RefCounted
## ИИ пешеходов и животных. Порт PedestrianManager (peds.js), пешеходный
## обход (pedavoid.js) и правила ПДД поверх готового `PedGraph` (world/city/ped_graph.gd).
##
## Архитектурно НЕ дословный порт: оригинал сам прокладывал путь по перекрёсткам
## тика за тиком (`_decide`/`_startCross`/`_startTurn`, ручная Dijkstra-экономия
## через LOD-зоны active/near/respawn), потому что его граф не умел отдавать
## готовый маршрут. Наш `PedGraph.build_route()` уже возвращает весь путь как
## `points[]`/`gates[]` (приём из capital, см. память проекта) — агенту остаётся
## идти точка за точкой и спрашивать гейт перед шагом. Это устраняет причину,
## по которой в оригинале была отдельная «упрощённая» ближняя зона (там она
## существовала только чтобы не гонять Dijkstra каждый кадр для дальних
## пешеходов — AStar3D по готовому графу на 612 узлах кардинально дешевле).
## Поэтому у нас ОДНА зона полного ИИ до `respawn_radius` (210 м), а не три.
##
## Правила «поворот» и «переход» в оригинале были отдельными режимами с своей
## анимацией дуги/полосы — здесь они не нужны: угол квартала и центр перехода
## это просто узлы графа, полилиния маршрута сама поворачивает и пересекает
## дорогу. Различие сохраняется только в том, ЧТО проверяется перед шагом
## (переход — это гейт светофора + машины поблизости; обычный отрезок тротуара
## — ничего).

enum Mode { WALK, WAIT, FLEE, KICK, KNOCKED, IDLE }

const Z_ROAD := TrafficLightController.Axis.Z_ROAD
const X_ROAD := TrafficLightController.Axis.X_ROAD

## Дистанция до цели/узла, при которой считаем «дошёл».
const ARRIVE_EPS := 0.08
## Половина ширины тротуара для бокового смещения при обходе — ограничивает laneOff.
const LANE_OFF_MAX := 1.4
## Проб вперёд для статического обхода, м (упрощено относительно оригинала:
## один проб вместо three-probe — не критично на масштабе города).
const AVOID_PROBE_DIST := 1.6
const AVOID_PROBE_RADIUS := 0.4
## Полная блокировка (обе стороны заняты) дольше — явная реакция.
const STUCK_CANCEL_TIME := 1.5

## Ближе этого — реальный наезд/сбитие машиной; между этим и STATIC_HIT_R —
## лёгкое касание/уворот (порт player.js:_collidePed).
const HIT_RADIUS := 0.85
const HIT_SPEED_MIN := 4.2
const DODGE_SPEED_MIN := 1.0

var count := 0

var field: CityField
var graph: PedGraph
var lights: TrafficLightController
var catalog: PedCatalog
var config: PedConfig
var rng: SeededRng
## Слой физики города (CityCollision.LAYER) — обход статики читает его же
## коллайдеры, что и машина игрока, отдельного spatial hash не заводим.
var space: RID
## Ссылка на трафик — нужна и обходу дороги перед переходом, и наезду
## машины трафика на пешехода (правила 4-5 TrafficManager).
var traffic: TrafficManager

var archetype_ref: Array[PedArchetypeData] = []
var is_animal: PackedByteArray = PackedByteArray()
var body_scale: PackedVector2Array = PackedVector2Array()
var skin_color: PackedColorArray = PackedColorArray()
var hair_color: PackedColorArray = PackedColorArray()
var shoe_color: PackedColorArray = PackedColorArray()
var cloth_color: PackedColorArray = PackedColorArray()
var pants_color: PackedColorArray = PackedColorArray()

var x: PackedFloat32Array = PackedFloat32Array()
var z: PackedFloat32Array = PackedFloat32Array()
var heading: PackedFloat32Array = PackedFloat32Array()
var speed: PackedFloat32Array = PackedFloat32Array()
var base_speed: PackedFloat32Array = PackedFloat32Array()
var mode: PackedByteArray = PackedByteArray()
var walk_phase: PackedFloat32Array = PackedFloat32Array()
var alive: PackedByteArray = PackedByteArray()

## Маршрут — переменной длины, поэтому не Packed-массив фиксированного шага,
## а массив массивов (по одному на пешехода). route_idx указывает точку,
## К КОТОРОЙ пешеход сейчас идёт (не пройденную).
var route_points: Array[PackedVector3Array] = []
var route_gates: Array[PackedInt32Array] = []
var route_nodes: Array[PackedInt32Array] = []
var route_idx: PackedInt32Array = PackedInt32Array()
var wait_t: PackedFloat32Array = PackedFloat32Array()
var idle_t: PackedFloat32Array = PackedFloat32Array()
var stuck_t: PackedFloat32Array = PackedFloat32Array()

var lane_off: PackedFloat32Array = PackedFloat32Array()
var avoid_target: PackedFloat32Array = PackedFloat32Array()
var avoid_side: PackedFloat32Array = PackedFloat32Array()
var blocked_t: PackedFloat32Array = PackedFloat32Array()

var violator: PackedByteArray = PackedByteArray()
var anger_t: PackedFloat32Array = PackedFloat32Array()
var kick_t: PackedFloat32Array = PackedFloat32Array()
var kick_cd: PackedFloat32Array = PackedFloat32Array()
var hit_cd: PackedFloat32Array = PackedFloat32Array()
var target_angle: PackedFloat32Array = PackedFloat32Array()

var flee_vx: PackedFloat32Array = PackedFloat32Array()
var flee_vz: PackedFloat32Array = PackedFloat32Array()
var flee_t: PackedFloat32Array = PackedFloat32Array()
var knock_t: PackedFloat32Array = PackedFloat32Array()

## Сколько новых маршрутов (AStar3D-вызовов) можно посчитать за этот тик —
## аналог `routesFrom`-лимита оригинала, хотя причина другая (там — цена
## Dijkstra, здесь — просто защита от пичка в кадре, когда полсотни
## пешеходов заспавнились одновременно и всем сразу нужен маршрут).
var _route_budget := 0

var _shape: SphereShape3D
var _query := PhysicsShapeQueryParameters3D.new()


func setup(catalog_: PedCatalog, field_: CityField, graph_: PedGraph,
		lights_: TrafficLightController, config_: PedConfig, rng_: SeededRng,
		space_: RID, ped_count: int) -> void:
	catalog = catalog_
	field = field_
	graph = graph_
	lights = lights_
	config = config_
	rng = rng_
	space = space_
	count = maxi(0, ped_count)
	_resize(count)

	_shape = SphereShape3D.new()
	_shape.radius = AVOID_PROBE_RADIUS
	_query.shape = _shape
	_query.collision_mask = 1
	_query.collide_with_bodies = true
	_query.collide_with_areas = false

	const ARCH_WEIGHTS := {
		&"gopnik": 1.0, &"grandma": 1.0, &"runner": 1.0, &"student": 1.0,
		&"businessman": 1.0, &"tourist": 1.0, &"child": 1.0, &"regular": 3.0,
		&"elder": 1.0, &"mom": 1.0, &"worker": 1.0, &"musician": 1.0, &"nurse": 1.0,
		&"dog": 2.0, &"cat": 2.0,
	}
	var ids: Array = ARCH_WEIGHTS.keys()
	var weights := PackedFloat32Array()
	for id: StringName in ids:
		weights.append(ARCH_WEIGHTS[id])

	for i in count:
		var id: StringName = rng.pick_weighted(ids, weights)
		var arch := catalog.get_archetype(id)
		if arch == null:
			arch = PedArchetypeData.new()
			arch.id = id
		archetype_ref[i] = arch
		is_animal[i] = 1 if arch.is_animal else 0
		body_scale[i] = Vector2(
			rng.randf_range(arch.scale_y_min, arch.scale_y_max),
			rng.randf_range(arch.scale_xz_min, arch.scale_xz_max))
		skin_color[i] = rng.pick_color(catalog.skin_colors)
		hair_color[i] = rng.pick_color(catalog.hair_colors)
		shoe_color[i] = rng.pick_color(catalog.shoe_colors)
		cloth_color[i] = _pick_color(arch.cloth_colors, catalog.cloth_colors)
		pants_color[i] = _pick_color(arch.pants_colors, catalog.pants_colors)
		violator[i] = 1 if rng.chance(config.violator_chance) else 0
		alive[i] = 1
		route_points[i] = PackedVector3Array()
		route_gates[i] = PackedInt32Array()
		route_nodes[i] = PackedInt32Array()


func _pick_color(own: PackedColorArray, shared: PackedColorArray) -> Color:
	if not own.is_empty():
		return rng.pick_color(own)
	if not shared.is_empty():
		return rng.pick_color(shared)
	return Color.WHITE


func _resize(n: int) -> void:
	archetype_ref.resize(n)
	is_animal.resize(n)
	body_scale.resize(n)
	skin_color.resize(n)
	hair_color.resize(n)
	shoe_color.resize(n)
	cloth_color.resize(n)
	pants_color.resize(n)
	x.resize(n)
	z.resize(n)
	heading.resize(n)
	speed.resize(n)
	base_speed.resize(n)
	mode.resize(n)
	walk_phase.resize(n)
	alive.resize(n)
	route_points.resize(n)
	route_gates.resize(n)
	route_nodes.resize(n)
	route_idx.resize(n)
	wait_t.resize(n)
	idle_t.resize(n)
	stuck_t.resize(n)
	lane_off.resize(n)
	avoid_target.resize(n)
	avoid_side.resize(n)
	blocked_t.resize(n)
	violator.resize(n)
	anger_t.resize(n)
	kick_t.resize(n)
	kick_cd.resize(n)
	hit_cd.resize(n)
	target_angle.resize(n)
	flee_vx.resize(n)
	flee_vz.resize(n)
	flee_t.resize(n)
	knock_t.resize(n)


# --- Размещение -----------------------------------------------------------------

func place_all_near(player_x: float, player_z: float) -> void:
	for i in count:
		place_near(i, player_x, player_z)


## Порт _randPlace() (peds.js:778-864): случайная точка на тротуаре не ближе
## 50 м и вне поля зрения игрока; если за 30 попыток не нашли — точка сзади
## игрока за спиной.
func place_near(i: int, player_x: float, player_z: float) -> void:
	_deactivate(i)
	var found := false
	for _attempt in 30:
		var vertical := rng.chance(0.5)
		var rx := rng.randf_range(-160.0, 160.0)
		var rz := rng.randf_range(-160.0, 160.0)
		var coord: float = clampf(roundf(((player_x if vertical else player_z)
			+ (rx if vertical else rz)) / field.cell) * field.cell, -256.0, 256.0)
		var pos: float = clampf((player_z if vertical else player_x)
			+ (rz if vertical else rx), -256.0, 256.0)
		var side := 1.0 if rng.chance(0.5) else -1.0
		var side_off := field.road_half + field.sidewalk * 0.5
		var wx := coord + side * side_off if vertical else pos
		var wz := pos if vertical else coord + side * side_off
		if MathUtils.dist_2d(wx, wz, player_x, player_z) < 50.0:
			continue
		if _obstacle_at(wx, wz):
			continue
		x[i] = wx
		z[i] = wz
		found = true
		break
	if not found:
		var bx: float = clampf(player_x + rng.randf_range(-115.0, 115.0), -250.0, 250.0)
		var bz: float = clampf(player_z + rng.randf_range(-115.0, 115.0), -250.0, 250.0)
		x[i] = bx
		z[i] = bz

	_reset_runtime(i)


func _reset_runtime(i: int) -> void:
	var a := archetype_ref[i]
	base_speed[i] = rng.randf_range(a.speed_min, a.speed_max)
	speed[i] = base_speed[i]
	mode[i] = Mode.IDLE
	idle_t[i] = 0.0
	route_idx[i] = 0
	route_points[i].clear()
	route_gates[i].clear()
	route_nodes[i].clear()
	wait_t[i] = 0.0
	stuck_t[i] = 0.0
	lane_off[i] = 0.0
	avoid_target[i] = 0.0
	avoid_side[i] = 0.0
	blocked_t[i] = 0.0
	anger_t[i] = 0.0
	kick_t[i] = 0.0
	kick_cd[i] = 0.0
	hit_cd[i] = 0.0
	flee_t[i] = 0.0
	knock_t[i] = 0.0
	heading[i] = 0.0
	walk_phase[i] = 0.0


## Разбирает маршрут — после этого route_points/gates/nodes пусты. Инвариант
## проекта: WALK и WAIT читают route_points[route_idx], поэтому оба обязаны
## быть сброшены в IDLE здесь же, а не только WAIT (баг: _dodge() дёргает
## _deactivate() ДО того как выставит mode=FLEE — ped, застигнутый в WALK,
## на миг оставался в WALK с уже пустым маршрутом; следующий тик читал
## route_points[0] на пустом массиве и падал).
func _deactivate(i: int) -> void:
	route_points[i].clear()
	route_gates[i].clear()
	route_nodes[i].clear()
	route_idx[i] = 0
	lane_off[i] = 0.0
	avoid_target[i] = 0.0
	avoid_side[i] = 0.0
	if mode[i] == Mode.WAIT or mode[i] == Mode.WALK:
		mode[i] = Mode.IDLE


# --- Обновление ------------------------------------------------------------------

func update(delta: float, player_x: float, player_z: float, player_heading: float,
		player_speed: float, player_vx: float, player_vz: float,
		is_night: bool) -> void:
	_route_budget = config.routes_per_tick
	var bucket := _build_bucket()

	for i in count:
		if alive[i] == 0:
			continue
		if hit_cd[i] > 0.0:
			hit_cd[i] -= delta
		if anger_t[i] > 0.0:
			anger_t[i] -= delta
		if kick_cd[i] > 0.0:
			kick_cd[i] -= delta
		if kick_t[i] > 0.0:
			kick_t[i] -= delta
			if kick_t[i] <= 0.0 and mode[i] == Mode.KICK:
				mode[i] = Mode.IDLE
				idle_t[i] = 0.0
				_deactivate(i)

		walk_phase[i] += delta * speed[i] * (6.0 if _is_fast(i) else 4.0)

		_check_player_reaction(i, player_x, player_z, player_speed)
		_check_player_collision(i, player_x, player_z, player_vx, player_vz, player_speed)

		if knock_t[i] > 0.0:
			knock_t[i] -= delta
			x[i] += flee_vx[i] * delta * 0.25
			z[i] += flee_vz[i] * delta * 0.25
			if knock_t[i] <= 0.0:
				_start_flee(i, flee_vx[i], flee_vz[i], 3.4)
		elif mode[i] == Mode.FLEE:
			x[i] += flee_vx[i] * delta
			z[i] += flee_vz[i] * delta
			flee_t[i] -= delta
			if flee_t[i] <= 0.0:
				_snap_to_sidewalk(i)
		elif mode[i] == Mode.KICK:
			pass
		elif mode[i] == Mode.IDLE:
			_update_idle(i, delta, player_x, player_z)
		elif mode[i] == Mode.WAIT:
			_update_wait(i, delta)
		else:
			_update_walk(i, delta, bucket)

		if MathUtils.dist_2d(x[i], z[i], player_x, player_z) > config.respawn_radius:
			place_near(i, player_x, player_z)


func _is_fast(i: int) -> bool:
	return mode[i] == Mode.FLEE or archetype_ref[i].id == &"runner" or archetype_ref[i].id == &"dog"


func _bucket_key(px: float, pz: float) -> int:
	return MathUtils.hash_key(floori(px / 8.0), floori(pz / 8.0))


## Бакеты по клетке 8x8 м для обхода других пешеходов — без него разъезд
## был бы O(n^2) по всем активным (план: «бакетизация... чинит O(n^2)»).
func _build_bucket() -> Dictionary[int, PackedInt32Array]:
	var b: Dictionary[int, PackedInt32Array] = {}
	for i in count:
		if alive[i] == 0 or mode[i] == Mode.FLEE or knock_t[i] > 0.0:
			continue
		var key := _bucket_key(x[i], z[i])
		if not b.has(key):
			b[key] = PackedInt32Array()
		b[key].append(i)
	return b


# --- Простой (idle) и выбор цели --------------------------------------------------

func _update_idle(i: int, delta: float, player_x: float, player_z: float) -> void:
	idle_t[i] -= delta
	if idle_t[i] > 0.0:
		return
	if _route_budget <= 0:
		idle_t[i] = 0.3
		return
	if _try_activate(i, player_x, player_z):
		return
	# Не нашли цель/путь — короткая пауза и повтор, не сжигаем бюджет впустую.
	idle_t[i] = 1.0


## Строит маршрут до случайной/POI-цели. Возвращает false, если цель или
## путь не нашлись (пешеход останется в IDLE и попробует на следующем тике).
func _try_activate(i: int, player_x: float, player_z: float) -> bool:
	_route_budget -= 1
	var from_pos := Vector3(x[i], 0.0, z[i])
	var from_id := graph.nearest_node(x[i], z[i])
	if from_id < 0:
		return false
	var to_id := _pick_destination(i, from_id)
	if to_id < 0 or to_id == from_id:
		return false
	var allow_jwalk := violator[i] == 1
	var route: Dictionary = graph.build_route(from_pos, to_id, allow_jwalk)
	var points: PackedVector3Array = route["points"]
	if points.size() < 2:
		return false
	route_points[i] = points
	route_gates[i] = route["gates"]
	route_nodes[i] = route["node_ids"]
	speed[i] = base_speed[i]
	_begin_hop(i, 1)
	return true


## Гибрид POI (по архетипу) + случайный узел — порт _pickDestination, но без
## готовой карты dist[] (у AStar3D её нет): дистанция берётся евклидово, что
## на регулярной сетке города — приемлемая замена «2-6 рёбер графа».
func _pick_destination(i: int, from_id: int) -> int:
	var arch_id: StringName = archetype_ref[i].id
	if arch_id == &"tourist":
		var id := _pick_poi_for(from_id, &"cvetnik", &"proval")
		if id >= 0:
			return id
	elif arch_id == &"grandma":
		var id := _pick_poi_for(from_id, &"rynok", &"pickup", &"fuel")
		if id >= 0:
			return id
	if rng.chance(0.5):
		var id := _pick_weighted_poi(from_id)
		if id >= 0:
			return id
	return _pick_random_node(from_id)


const POI_MIN_DIST := 60.0
const POI_MAX_DIST := 260.0


func _pick_poi_for(from_id: int, tag_a: StringName, tag_b: StringName = &"",
		tag_c: StringName = &"") -> int:
	var from_pos := graph.position_of(from_id)
	var pool: PackedInt32Array = PackedInt32Array()
	for k in graph.poi_nodes.size():
		var tag := StringName(graph.poi_tags[k])
		if tag != tag_a and tag != tag_b and tag != tag_c:
			continue
		var node := graph.poi_nodes[k]
		if node == from_id:
			continue
		var d := from_pos.distance_to(graph.position_of(node))
		if d < POI_MIN_DIST or d > POI_MAX_DIST:
			continue
		pool.append(node)
	if pool.is_empty():
		return -1
	return pool[rng.randi_below(pool.size())]


## Взвешенно: достопримечательность 0.5 / подача такси 0.35 / заправка 0.15
## (в диапазоне дистанции) — порт _pickWeightedPoi.
func _pick_weighted_poi(from_id: int) -> int:
	var from_pos := graph.position_of(from_id)
	var landmark := PackedInt32Array()
	var pickup := PackedInt32Array()
	var fuel := PackedInt32Array()
	for k in graph.poi_nodes.size():
		var node := graph.poi_nodes[k]
		if node == from_id:
			continue
		var d := from_pos.distance_to(graph.position_of(node))
		if d < POI_MIN_DIST or d > POI_MAX_DIST:
			continue
		var tag := String(graph.poi_tags[k])
		if tag == "pickup":
			pickup.append(node)
		elif tag == "fuel":
			fuel.append(node)
		else:
			landmark.append(node)
	var cats: Array = []
	var weights := PackedFloat32Array()
	if not landmark.is_empty():
		cats.append(landmark); weights.append(0.5)
	if not pickup.is_empty():
		cats.append(pickup); weights.append(0.35)
	if not fuel.is_empty():
		cats.append(fuel); weights.append(0.15)
	if cats.is_empty():
		return -1
	var chosen: PackedInt32Array = rng.pick_weighted(cats, weights)
	return chosen[rng.randi_below(chosen.size())]


## Случайный mid-узел (середина квартала) на разумной дистанции — предпочтён
## угловым/перекрёстным, чтобы idle не случался посреди проезжей части.
func _pick_random_node(from_id: int) -> int:
	var from_pos := graph.position_of(from_id)
	var lo := PedGraph.VMID_BASE
	var hi := PedGraph.HMID_BASE + PedGraph.VMID_COUNT
	for _attempt in 12:
		var node := lo + rng.randi_below(hi - lo)
		if node == from_id:
			continue
		var d := from_pos.distance_to(graph.position_of(node))
		if d >= POI_MIN_DIST and d <= POI_MAX_DIST:
			return node
	return -1


# --- Ходьба по маршруту ------------------------------------------------------------

func _update_walk(i: int, delta: float, bucket: Dictionary[int, PackedInt32Array]) -> void:
	if route_idx[i] >= route_points[i].size():
		mode[i] = Mode.IDLE
		idle_t[i] = rng.randf_range(config.idle_time_min, config.idle_time_max)
		return

	# _avoid_static() может отменить маршрут изнутри (застрял дольше
	# STUCK_CANCEL_TIME -> _cancel_route() -> mode=IDLE, route_points пуст).
	# Перечитываем состояние ПОСЛЕ обоих обходов, а не кэшируем route_points
	# в локальную переменную заранее: PackedVector3Array, полученный через
	# `route_points[i]`, разделяет буфer с хранимым элементом, и .clear()
	# внутри _cancel_route() виден и через старую ссылку — падение по
	# индексу на «уже опустевшем» массиве, а не защита от него.
	_avoid_static(i, delta)
	_avoid_peds(i, delta, bucket)
	_step_lane_off(i, delta)

	if mode[i] != Mode.WALK or route_idx[i] >= route_points[i].size():
		return

	var target := route_points[i][route_idx[i]]
	var cur := Vector2(x[i], z[i])
	var to_target := Vector2(target.x, target.z) - cur
	var dist := to_target.length()
	if dist < ARRIVE_EPS:
		_arrive_at_point(i)
		return

	var dir := to_target / dist
	# Перпендикулярное боковое смещение (обход) — сетка города осеаксиальна,
	# поэтому "перпендикуляр" всегда просто перестановка компонент.
	var perp := Vector2(-dir.y, dir.x)
	var eff_target := Vector2(target.x, target.z) + perp * lane_off[i]
	var to_eff := eff_target - cur
	var eff_dist := to_eff.length()
	if eff_dist < 0.001:
		heading[i] = atan2(dir.x, dir.y)
		return
	var eff_dir := to_eff / eff_dist
	var step: float = speed[i] * delta
	if step >= eff_dist:
		x[i] = eff_target.x
		z[i] = eff_target.y
	else:
		x[i] += eff_dir.x * step
		z[i] += eff_dir.y * step
	heading[i] = atan2(dir.x, dir.y)


func _arrive_at_point(i: int) -> void:
	var next_idx := route_idx[i] + 1
	if next_idx > route_points[i].size() - 1:
		# Дошли до конца маршрута.
		route_points[i].clear()
		route_gates[i].clear()
		route_nodes[i].clear()
		route_idx[i] = 0
		mode[i] = Mode.IDLE
		idle_t[i] = rng.randf_range(config.idle_time_min, config.idle_time_max)
		return
	_begin_hop(i, next_idx)


## Готовит переход к route_points[idx]: если отрезок, ведущий туда, —
## переход через дорогу (edge_kind CROSS/JWALK), сперва спрашивает
## светофор/машины (_update_wait), иначе сразу идёт. Общая точка входа для
## первого отрезка маршрута (_try_activate) и всех последующих
## (_arrive_at_point) — раньше первый отрезок гейт не проверял вовсе.
func _begin_hop(i: int, idx: int) -> void:
	route_idx[i] = idx
	var a := route_nodes[i][idx - 1]
	var b := route_nodes[i][idx]
	var kind := graph.edge_kind(a, b)
	var is_crossing := kind == int(PedGraph.Edge.CROSS) or kind == int(PedGraph.Edge.JWALK)
	if is_crossing and is_animal[i] == 0:
		mode[i] = Mode.WAIT
		wait_t[i] = 0.0
	else:
		mode[i] = Mode.WALK


## Порт _updateWait/_getLightForPed/_carOnRoad, свёрнутые в один переход
## точки-к-точке. Животные и нарушители не спрашивают светофор (но всё
## равно ждут, если по дороге едет машина) — светофор спрашивают только
## законопослушные люди на гейтованном переходе.
func _update_wait(i: int, delta: float) -> void:
	wait_t[i] += delta
	var next_idx := route_idx[i]
	var gate := route_gates[i][next_idx] if next_idx < route_gates[i].size() else -1
	var check_light := gate >= 0 and is_animal[i] == 0 and violator[i] == 0

	if check_light:
		if not lights.is_crossing_open(gate):
			if wait_t[i] > 22.0:
				_cancel_route(i)
			return
		if _car_on_road(i, next_idx, 18.0):
			return
	else:
		if _car_on_road(i, next_idx, 22.0):
			if wait_t[i] > 7.0:
				_cancel_route(i)
			return
	mode[i] = Mode.WALK


## Отменяет текущий переход/маршрут — пешеход не «висит» на дороге вечно,
## а пробует заново с новой целью (аварийный таймаут, приём из capital).
func _cancel_route(i: int) -> void:
	route_points[i].clear()
	route_gates[i].clear()
	route_nodes[i].clear()
	route_idx[i] = 0
	mode[i] = Mode.IDLE
	idle_t[i] = 0.5


## Едет ли по дороге, которую сейчас пересекает пешеход, машина в опасной
## близости — порт _carOnRoad. Считает и трафик, и машину игрока.
func _car_on_road(i: int, point_idx: int, safe_dist: float) -> bool:
	var from3 := route_points[i][point_idx - 1]
	var to3 := route_points[i][point_idx]
	var mid_x := (from3.x + to3.x) * 0.5
	var mid_z := (from3.z + to3.z) * 0.5
	var crossing_along_x := absf(to3.x - from3.x) > absf(to3.z - from3.z)
	var car_axis := Z_ROAD if crossing_along_x else X_ROAD
	var isec := field.nearest_intersection(mid_x, mid_z)
	var car_coord: float = isec.x if crossing_along_x else isec.y
	var ped_pos: float = mid_z if crossing_along_x else mid_x

	if traffic != null:
		for c in traffic.count:
			if traffic.axis[c] != car_axis or not is_equal_approx(traffic.coord[c], car_coord):
				continue
			if traffic.speed_of(c) <= 0.8:
				continue
			var d_pos := (traffic.pos[c] - ped_pos) * traffic.dir[c]
			if absf(traffic.pos[c] - ped_pos) < safe_dist and d_pos < 3.0:
				return true

	if absf(_player_speed) > 1.0:
		var player_on_road: bool = absf((_player_x if crossing_along_x else _player_z) - car_coord) < 9.0
		if player_on_road:
			var player_pos: float = _player_z if crossing_along_x else _player_x
			var dyn_dist: float = maxf(safe_dist, absf(_player_speed) * 2.5)
			if absf(player_pos - ped_pos) < dyn_dist:
				return true
	return false


# --- Обход препятствий и других пешеходов ------------------------------------------

func _step_lane_off(i: int, delta: float) -> void:
	var target := avoid_target[i]
	var cur := lane_off[i]
	if is_equal_approx(target, cur):
		return
	var step := 3.0 * delta
	var d := target - cur
	lane_off[i] = target if absf(d) <= step else cur + signf(d) * step


## Упрощённый обход статики: один проб вперёд (вместо three-probe оригинала)
## через физику CityCollision (тот же слой, что и коллайдер игрока — не
## заводим отдельный spatial hash). Гистерезис стороны через avoid_side.
func _avoid_static(i: int, delta: float) -> void:
	if route_idx[i] >= route_points[i].size():
		return
	var target := route_points[i][route_idx[i]]
	var to_target := Vector2(target.x - x[i], target.z - z[i])
	if to_target.length() < 0.01:
		return
	var dir := to_target.normalized()
	var perp := Vector2(-dir.y, dir.x)

	var probe := Vector2(x[i], z[i]) + perp * lane_off[i] + dir * AVOID_PROBE_DIST
	if not _obstacle_at(probe.x, probe.y):
		var center := Vector2(x[i], z[i]) + dir * AVOID_PROBE_DIST
		if not _obstacle_at(center.x, center.y) or absf(lane_off[i]) < 0.02:
			avoid_target[i] = 0.0
		stuck_t[i] = 0.0
		return

	var order: PackedFloat32Array = [1.2, -1.2] if avoid_side[i] >= 0.0 else [-1.2, 1.2]
	for o in order:
		var cand: float = clampf(lane_off[i] + o, -LANE_OFF_MAX, LANE_OFF_MAX)
		var p := Vector2(x[i], z[i]) + perp * cand + dir * AVOID_PROBE_DIST
		if not _obstacle_at(p.x, p.y):
			avoid_target[i] = cand
			avoid_side[i] = signf(cand) if not is_zero_approx(cand) else avoid_side[i]
			stuck_t[i] = 0.0
			return

	speed[i] = 0.0
	stuck_t[i] += delta
	if stuck_t[i] > STUCK_CANCEL_TIME:
		stuck_t[i] = 0.0
		_cancel_route(i)


## Разъезд/обгон на тротуаре — упрощённо: без требования «та же лента»
## оригинала (у нас нет axis/coord/side во время ходьбы), похожий курс +
## близкая дистанция впереди по курсу.
func _avoid_peds(i: int, delta: float, bucket: Dictionary[int, PackedInt32Array]) -> void:
	var key := _bucket_key(x[i], z[i])
	if not bucket.has(key):
		return
	var fwd := Heading.forward(heading[i])
	for o in bucket[key]:
		if o == i:
			continue
		var dx := x[o] - x[i]
		var dz := z[o] - z[i]
		var d := sqrt(dx * dx + dz * dz)
		if d < 0.001 or d > 2.2:
			continue
		var along := dx * fwd.x + dz * fwd.z
		if along <= 0.0:
			continue
		var lateral := absf(dx * fwd.z - dz * fwd.x)
		if lateral > 0.9:
			continue
		var leader_speed: float = 0.0 if mode[o] == Mode.IDLE or mode[o] == Mode.WAIT else speed[o]
		if speed[i] > leader_speed:
			speed[i] = maxf(0.3, leader_speed)
		if leader_speed < base_speed[i] * 0.6:
			blocked_t[i] += delta
			if blocked_t[i] > 1.0 and is_zero_approx(lane_off[i]):
				var cand: float = 1.2 if signf(lateral) >= 0.0 else -1.2
				avoid_target[i] = cand
				speed[i] = minf(base_speed[i] * 1.25, speed[i] + 0.5)
		else:
			blocked_t[i] = 0.0
	if blocked_t[i] > 2.0:
		blocked_t[i] = 0.0


func _obstacle_at(px: float, pz: float) -> bool:
	if not space.is_valid():
		return false
	_query.transform = Transform3D(Basis.IDENTITY, Vector3(px, 1.0, pz))
	var state := PhysicsServer3D.space_get_direct_state(space)
	return not state.intersect_shape(_query, 1).is_empty()


# --- Реакции на игрока --------------------------------------------------------------

## Кэш позиции/скорости игрока — читают _car_on_road (внутри одного тика
## update()) без протаскивания параметров через весь стек вызовов.
var _player_x := 0.0
var _player_z := 0.0
var _player_speed := 0.0


## Ругань при подрезании + пинок машины игрока — порт _checkNearMissAndKick,
## без реплик (нет UI пузырей — придут вместе с этапом juice/UI).
func _check_player_reaction(i: int, player_x: float, player_z: float,
		player_speed: float) -> void:
	_player_x = player_x
	_player_z = player_z
	_player_speed = player_speed
	if knock_t[i] > 0.0 or mode[i] == Mode.FLEE:
		return
	var dx := player_x - x[i]
	var dz := player_z - z[i]
	var dist := sqrt(dx * dx + dz * dz)
	if dist > 12.0:
		return

	if is_animal[i] == 1:
		if dist < config.animal_flee_dist and absf(player_speed) > 2.0 and flee_t[i] <= 0.0:
			_start_flee(i, -dx, -dz, 4.0)
		return

	if dist < config.anger_dist and player_speed > 2.5 and hit_cd[i] <= 0.0 \
			and anger_t[i] <= 0.0 and mode[i] != Mode.WAIT:
		anger_t[i] = config.anger_duration
		target_angle[i] = atan2(dx, dz)

	if anger_t[i] > 0.0 and dist < config.kick_dist and absf(player_speed) < 3.5 \
			and kick_cd[i] <= 0.0 and kick_t[i] <= 0.0:
		mode[i] = Mode.KICK
		kick_t[i] = config.kick_duration
		kick_cd[i] = config.kick_cooldown
		target_angle[i] = atan2(dx, dz)


## Наезд/касание машиной игрока — порт PlayerCar.js:_collidePed. Сам
## PlayerCar физически не сталкивается с пешеходами (KinematicBody их не
## видит, у них нет коллайдера — только этот дистанционный чек), поэтому
## реакция целиком в PedManager, а не в PlayerCar._resolve_impacts.
func _check_player_collision(i: int, player_x: float, player_z: float,
		player_vx: float, player_vz: float, player_speed: float) -> void:
	if hit_cd[i] > 0.0 or knock_t[i] > 0.0:
		return
	var dx := player_x - x[i]
	var dz := player_z - z[i]
	var d := sqrt(dx * dx + dz * dz)
	if d >= HIT_RADIUS or d < 0.0001:
		return
	var nx := -dx / d
	var nz := -dz / d
	var rel_vel := player_vx * nx + player_vz * nz

	if absf(player_speed) > HIT_SPEED_MIN and rel_vel > 1.5:
		hit_cd[i] = 2.0
		_knock_down(i, nx, nz, absf(player_speed))
	elif absf(player_speed) > DODGE_SPEED_MIN and rel_vel > 0.2:
		hit_cd[i] = 1.2
		_dodge(i, nx, nz, absf(player_speed))


func _dodge(i: int, dx: float, dz: float, car_speed: float) -> void:
	_deactivate(i)
	_start_flee(i, dx, dz, maxf(3.2, car_speed * 0.9 + 0.8))


func _knock_down(i: int, dx: float, dz: float, car_speed: float) -> void:
	mode[i] = Mode.KNOCKED
	knock_t[i] = 2.0
	_deactivate(i)
	var sp := 3.0 + minf(car_speed, 16.0) * 0.3
	var len := sqrt(dx * dx + dz * dz)
	if len < 0.0001:
		len = 1.0
	flee_vx[i] = (dx / len) * sp
	flee_vz[i] = (dz / len) * sp


func _start_flee(i: int, dx: float, dz: float, speed_val: float) -> void:
	mode[i] = Mode.FLEE
	flee_t[i] = 1.0 + speed_val * 0.15
	var len := sqrt(dx * dx + dz * dz)
	if len < 0.0001:
		len = 1.0
	flee_vx[i] = (dx / len) * speed_val
	flee_vz[i] = (dz / len) * speed_val
	_deactivate(i)


## Возвращает убежавшего/сбитого пешехода на ближайший тротуарный узел.
func _snap_to_sidewalk(i: int) -> void:
	var node := graph.nearest_node(x[i], z[i])
	if node >= 0:
		var p := graph.position_of(node)
		x[i] = p.x
		z[i] = p.z
	mode[i] = Mode.IDLE
	idle_t[i] = 0.3
	speed[i] = base_speed[i]
	_deactivate(i)


# --- Внешний удар (машина трафика / игрок-пешеход, TrafficManager правила 4-7) -----

func dodge_from_traffic(i: int, dx: float, dz: float, car_speed: float) -> void:
	_dodge(i, dx, dz, car_speed)


func knock_down_from_traffic(i: int, dx: float, dz: float, car_speed: float) -> void:
	_knock_down(i, dx, dz, car_speed)


func is_crossing_or_waiting(i: int) -> bool:
	return mode[i] == Mode.WAIT or (mode[i] == Mode.WALK and _current_kind(i) != int(PedGraph.Edge.WALK))


func _current_kind(i: int) -> int:
	if route_idx[i] <= 0 or route_idx[i] >= route_nodes[i].size():
		return int(PedGraph.Edge.WALK)
	return graph.edge_kind(route_nodes[i][route_idx[i] - 1], route_nodes[i][route_idx[i]])


# --- Запросы для рендера --------------------------------------------------------

func world_x(i: int) -> float:
	return x[i]


func world_z(i: int) -> float:
	return z[i]


func heading_of(i: int) -> float:
	return heading[i]


func mode_of(i: int) -> int:
	return mode[i]


func speed_of(i: int) -> float:
	return speed[i]


func walk_phase_of(i: int) -> float:
	return walk_phase[i]


func archetype_of(i: int) -> PedArchetypeData:
	return archetype_ref[i]


func is_animal_at(i: int) -> bool:
	return is_animal[i] == 1


## 0..1: доля отыгранной анимации удара (для позы ноги/рук в PedLayer).
func kick_progress(i: int) -> float:
	return clampf(1.0 - kick_t[i] / config.kick_duration, 0.0, 1.0)


func is_angry(i: int) -> bool:
	return anger_t[i] > 0.0


func target_angle_of(i: int) -> float:
	return target_angle[i]


func knocked_velocity(i: int) -> Vector2:
	return Vector2(flee_vx[i], flee_vz[i])
