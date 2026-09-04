class_name OrderManager
extends Node3D
## Менеджер заказов и пассажиров. Порт orders.js (~770 строк).

const MAT_PALETTE := preload("res://fx/materials/mat_palette.tres")
const OrderScript = preload("res://gameplay/orders/order.gd")
const OrderMarkerScript = preload("res://gameplay/orders/order_marker.gd")
const PedMeshBuilderScript = preload("res://peds/ped_mesh/ped_mesh_builder.gd")

var catalog: OrderCatalog
var field: CityField
var plan: CityPlan
var districts: DistrictCatalog
var balance: BalanceData
var player: PlayerCar

var open_orders: Array[RefCounted] = []
var active_order: RefCounted = null
var completed_missions: Array[StringName] = []

var _order_id_counter: int = 1
var _spawn_timer: float = 0.5 # первый заказ почти сразу
var _markers: Dictionary = {} # int order_id -> Node3D
var _drop_marker: Node3D = null
var _passengers: Dictionary = {} # int order_id -> Node3D
var _cab_passenger: Node3D = null
var _walkers: Array[Dictionary] = []


func setup(order_catalog: OrderCatalog, city_field: CityField, city_plan: CityPlan,
		district_catalog: DistrictCatalog, balance_config: BalanceData,
		player_car: PlayerCar) -> void:
	catalog = order_catalog
	field = city_field
	plan = city_plan
	districts = district_catalog
	balance = balance_config
	player = player_car

	Bus.player_crashed.connect(_on_player_crashed)


# --- Спавн заказов -----------------------------------------------------------

func spawn(rating: float, hour: float, capacity: int, player_pos: Vector2) -> void:
	if catalog == null or open_orders.size() >= balance.max_open_orders:
		return

	var unlocked_districts: Array[DistrictData] = []
	for d in districts.items:
		if rating >= d.unlock_rating:
			unlocked_districts.append(d)
	if unlocked_districts.is_empty():
		return

	# 1. Проверка доступных сюжетных миссий (30% шанс появления)
	var available_missions: Array[MissionData] = []
	for m in catalog.missions:
		if rating >= m.required_rating and not completed_missions.has(m.id):
			available_missions.append(m)

	if not available_missions.is_empty() and randf() < 0.30:
		var m := available_missions[randi() % available_missions.size()]
		var m_order := _create_mission_order(m)
		if m_order != null:
			_register_order(m_order)
			return

	# 2. Обычный заказ
	var is_night := Game.is_night()
	var selected_type := _pick_order_type(is_night, rating, capacity)
	if selected_type == null:
		selected_type = catalog.get_type(&"normal")

	var pick_d := unlocked_districts[randi() % unlocked_districts.size()]
	var pickup_pt := _pick_pickup_point(pick_d.id, player_pos)

	# Гарантируем нормальную дистанцию поездки (не менее 140 м)
	var drops: Array[Dictionary] = []
	if selected_type.id == &"group":
		var p1 := _pick_far_point(pickup_pt, unlocked_districts, 140.0)
		var p2 := _pick_far_point(p1, unlocked_districts, 120.0)
		drops.append({"pos": p1, "name": _district_name(pick_d.id), "district": pick_d.id})
		drops.append({"pos": p2, "name": _district_name(pick_d.id), "district": pick_d.id})
	elif selected_type.id == &"tour":
		var lm1 := _pick_random_landmark(&"")
		drops.append({"pos": lm1.position, "name": tr(lm1.display_name), "district": &"kurort"})
		if randf() < 0.5:
			var lm2 := _pick_random_landmark(lm1.id)
			drops.append({"pos": lm2.position, "name": tr(lm2.display_name), "district": &"kurort"})
	else:
		var drop_pt := _pick_far_point(pickup_pt, unlocked_districts, 140.0)
		drops.append({"pos": drop_pt, "name": _district_name(pick_d.id), "district": pick_d.id})

	var order := _build_order(selected_type.id, &"", selected_type.display_name,
		selected_type.description, selected_type.icon, selected_type.color,
		pickup_pt, pick_d.id, drops, 0, selected_type.time_limit, selected_type.pay_mult)

	if order != null:
		_register_order(order)


func _pick_order_type(is_night: bool, rating: float, capacity: int) -> OrderTypeData:
	var total_w := 0.0
	var pool: Array[OrderTypeData] = []
	var weights: Array[float] = []

	for t in catalog.types:
		if rating < t.required_rating or capacity < t.required_capacity:
			continue
		var w: float = t.night_weight if is_night else t.day_weight
		if w > 0.0:
			pool.append(t)
			weights.append(w)
			total_w += w

	if pool.is_empty() or total_w <= 0.0:
		return catalog.get_type(&"normal")

	var roll := randf() * total_w
	var cur := 0.0
	for i in pool.size():
		cur += weights[i]
		if roll <= cur:
			return pool[i]
	return pool[0]


func _create_mission_order(m: MissionData) -> RefCounted:
	var pickup_pt := _pick_pickup_point(m.pickup_district, Vector2.ZERO)
	var drops: Array[Dictionary] = []
	for i in m.drops.size():
		var dname: String = tr(m.drop_names[i]) if i < m.drop_names.size() else m.title
		drops.append({"pos": m.drops[i], "name": dname, "district": m.pickup_district})

	if m.final_drop_from_district != &"":
		var fin_pt := _pick_pickup_point(m.final_drop_from_district, Vector2.ZERO)
		drops.append({"pos": fin_pt, "name": _district_name(m.final_drop_from_district), "district": m.final_drop_from_district})

	return _build_order(m.kind, m.id, m.title, m.description, m.icon, m.color,
		pickup_pt, m.pickup_district, drops, m.pay, m.time_limit, 1.0)


func _build_order(type_id: StringName, mission_id: StringName, title: String, desc: String,
		icon: String, color: Color, pickup: Vector2, pickup_district: StringName,
		drops: Array[Dictionary], pay_override: int, time_limit: float, pay_mult: float) -> RefCounted:
	var o = OrderScript.new()
	o.id = _order_id_counter
	_order_id_counter += 1
	o.type_id = type_id
	o.mission_id = mission_id
	o.title = title
	o.desc = desc
	o.icon = icon
	o.color = color
	o.pickup_pos = pickup
	o.pickup_district = pickup_district
	o.drops = drops
	o.drop_idx = 0
	o.state = &"open"
	o.time_limit = time_limit
	o.timer = time_limit
	o.start_time_msec = Time.get_ticks_msec()

	var dist := 0.0
	var prev := pickup
	for d in drops:
		var p: Vector2 = d["pos"]
		dist += absf(p.x - prev.x) + absf(p.y - prev.y)
		prev = p
	o.dist_m = dist

	if pay_override > 0:
		o.est_pay = pay_override
	else:
		o.est_pay = roundi((balance.base_fare + dist * balance.fare_per_unit) * pay_mult)

	o.client_name = _generate_client_name(mission_id)
	o.client_avatar = _get_client_avatar(type_id, mission_id)
	return o


func _register_order(order: RefCounted) -> void:
	open_orders.append(order)
	_place_order_marker(order)
	_place_passenger_mesh(order)
	Bus.order_event.emit(&"spawned", order.id, {"order": order})


# --- Маркеры и 3D-модели в мире ----------------------------------------------

func _place_order_marker(order: RefCounted) -> void:
	var marker: Node3D = OrderMarkerScript.new()
	marker.name = "OrderMarker_%d" % order.id
	var my := field.height_at(order.pickup_pos.x, order.pickup_pos.y) if field != null else 0.0
	marker.position = Vector3(order.pickup_pos.x, my, order.pickup_pos.y)
	marker.setup(order.color, order.icon, false)
	add_child(marker)
	_markers[order.id] = marker


func _place_passenger_mesh(order: RefCounted) -> void:
	if order.type_id == &"package":
		return # посылка без стоящего пассажира или со стандартным курьером
	var spec := PedMeshBuilder.Spec.new()
	spec.cloth_color = order.color.lightened(0.2)
	spec.pants_color = Color("#2a2d34")
	if order.mission_id == &"grandma":
		spec.accessories = [&"headscarf", &"string_bag"]
	elif order.type_id == &"tour":
		spec.accessories = [&"panama", &"camera"]
	elif order.type_id == &"vip":
		spec.cloth_color = Color("#111115")
		spec.pants_color = Color("#111115")

	var mi: Node3D = PedMeshBuilderScript.build_ped_node(spec)
	mi.name = "PedOrder_%d" % order.id
	var py := field.height_at(order.pickup_pos.x, order.pickup_pos.y) if field != null else 0.0
	mi.position = Vector3(order.pickup_pos.x, py + 0.15, order.pickup_pos.y)
	add_child(mi)
	_passengers[order.id] = mi


func _remove_order_visuals(order: RefCounted) -> void:
	if _markers.has(order.id):
		var m: Node = _markers[order.id]
		m.queue_free()
		_markers.erase(order.id)
	if _passengers.has(order.id):
		var p: Node = _passengers[order.id]
		p.queue_free()
		_passengers.erase(order.id)


func _show_drop_marker(pos: Vector2) -> void:
	if _drop_marker == null:
		_drop_marker = OrderMarkerScript.new()
		_drop_marker.name = "DropMarker"
		add_child(_drop_marker)
	var dy := field.height_at(pos.x, pos.y) if field != null else 0.0
	_drop_marker.position = Vector3(pos.x, dy, pos.y)
	_drop_marker.setup(Color("#ffd040"), "★", true)
	_drop_marker.visible = true


func _hide_drop_marker() -> void:
	if _drop_marker != null:
		_drop_marker.visible = false


# --- Принятие и завершение заказов -------------------------------------------

func accept(order: RefCounted, player_car: PlayerCar) -> bool:
	if order == null or order.state != &"open":
		return false
	if player_car.motion.speed > 0.8:
		Bus.notify.emit(&"toast", "Для посадки пассажира полностью остановите машину!", {"color": Color("#ff9900")})
		return false

	order.state = &"active"
	active_order = order
	open_orders.erase(order)
	_remove_order_visuals(order)

	# Ставим пассажира в салон такси (если не посылка) — этот счётчик
	# гейтит бонусы StyleService и затухание style в CarRuntime.tick()
	# (orders.js:452: passengerCount = type === 'package' ? 0 : 1).
	if order.type_id != &"package":
		_spawn_cab_passenger(player_car, order)
		player_car.runtime.passenger_count = 1

	var drop: Dictionary = order.current_drop()
	_show_drop_marker(drop.get("pos", Vector2.ZERO))

	Bus.order_event.emit(&"accepted", order.id, {"order": order})
	Bus.notify.emit(&"toast", "Заказ принят: %s" % order.title, {"color": order.color})

	# Реплика пассажира при посадке
	var greeting: String = _get_dialogue_quote(order, &"pickup")
	if not greeting.is_empty():
		Bus.notify.emit(&"dialogue", greeting, {"speaker": order.client_name, "avatar": order.client_avatar})

	return true


func complete(player_car: PlayerCar, _hour: float, rating: float) -> Dictionary:
	if active_order == null:
		return {}

	var target_pos: Vector2 = active_order.current_target_pos()
	var pos_3d: Vector3 = player_car.global_position if player_car.is_inside_tree() else player_car.position
	var car_pos := Vector2(pos_3d.x, pos_3d.z)
	if car_pos.distance_to(target_pos) > 8.0:
		return {}

	if player_car.motion.speed > 0.8:
		Bus.notify.emit(&"toast", "Для высадки пассажира полностью остановите машину!", {"color": Color("#ff9900")})
		return {}

	# Если это промежуточная остановка в многоточечном заказе
	if not active_order.is_last_drop():
		active_order.drop_idx += 1
		var next_drop: Dictionary = active_order.current_drop()
		_show_drop_marker(next_drop.get("pos", Vector2.ZERO))
		Bus.order_event.emit(&"leg", active_order.id, {"stop": active_order.drop_idx, "order": active_order})
		Bus.notify.emit(&"toast", "Следующая остановка: %s" % next_drop.get("name", "Цель"), {"color": Color("#3e9e6e")})
		return {"partial": true}

	# Финальное завершение поездки
	var o: RefCounted = active_order
	active_order = null
	_hide_drop_marker()
	_remove_cab_passenger()
	player_car.runtime.passenger_count = 0

	# Расчет оплаты
	var is_night := Game.is_night()
	var pay: int = o.est_pay
	if o.time_limit > 0.0:
		var time_frac := clampf(1.0 - o.timer / o.time_limit, 0.0, 1.0)
		pay = roundi(pay * (1.0 + balance.time_bonus_max * (1.0 - time_frac)))
	if is_night:
		pay = roundi(pay * balance.night_mult)
	if rating >= 60.0:
		pay = roundi(pay * 1.15) # премия за высокий рейтинг
	if o.type_id == &"package" and o.fragile_broken:
		pay = roundi(pay * 0.5)

	# Чаевые за стиль вождения и чистоту
	var dirt_penalty := 1.0 - player_car.runtime.dirt * 0.5
	var vip_bonus := 1.5 if o.type_id == &"vip" else 1.0
	var tips := roundi(balance.tips_max * player_car.runtime.style * vip_bonus * dirt_penalty)
	var total: int = pay + tips

	# Оценка клиентом (1-5 звезд)
	var stars := 5
	stars -= roundi((1.0 - player_car.runtime.style) * 3.0)
	if player_car.runtime.dirt > 0.4:
		stars -= 1
	if o.fragile_broken:
		stars -= 2
	if o.type_id == &"vip" and stars < 4:
		stars -= 1
	stars = clampi(stars, 1, 5)

	var rev_bank: QuoteBank = catalog.reviews_for(stars)
	var review: String = rev_bank.pick(SeededRng.new()) if rev_bank != null else "Спасибо за поездку!"

	# Начисление денег и рейтинга
	Game.add_money(total)
	var rew_rating := 4
	var tdata: OrderTypeData = catalog.get_type(o.type_id)
	if tdata != null:
		rew_rating = tdata.rating_reward
	Game.add_rating(float(rew_rating))

	Game.bump("orders", "total_orders", 1.0)
	Game.bump("tips", "total_tips", float(tips))
	if is_night:
		Game.bump("", "night_orders", 1.0)
	if o.mission_id != &"":
		completed_missions.append(o.mission_id)
		Game.bump("missions", "total_missions", 1.0)

	# Спавним пешехода, уходящего по тротуару
	_spawn_walker(target_pos, o)

	var result := {
		"order_id": o.id,
		"title": o.title,
		"pay": pay,
		"tips": tips,
		"total": total,
		"stars": stars,
		"review": review,
		"type": o.type_id,
	}

	Bus.order_event.emit(&"completed", o.id, result)
	Bus.notify.emit(&"toast", "+%d ₽ (включая чаевые %d ₽)" % [total, tips], {"color": Color("#7ee787")})

	var drop_quote: String = _get_dialogue_quote(o, &"dropoff")
	if not drop_quote.is_empty():
		Bus.notify.emit(&"dialogue", drop_quote, {"speaker": o.client_name, "avatar": o.client_avatar})

	return result


func fail(order: RefCounted, reason: StringName) -> void:
	if order == null:
		return
	order.state = &"failed"
	if active_order == order:
		active_order = null
		_hide_drop_marker()
		_remove_cab_passenger()
		if player != null:
			player.runtime.passenger_count = 0

	_remove_order_visuals(order)
	open_orders.erase(order)
	Game.add_rating(-balance.rating_fail_order)

	Bus.order_event.emit(&"failed", order.id, {"reason": reason, "order": order})
	Bus.notify.emit(&"toast", "Заказ провален: %s" % order.title, {"color": Color("#ff7b72")})


# --- Внутренние пассажиры и уходящие пешеходы --------------------------------

func _spawn_cab_passenger(player_car: PlayerCar, _order: RefCounted) -> void:
	if _cab_passenger != null:
		_cab_passenger.queue_free()
	var spec := PedMeshBuilder.Spec.new()
	spec.cloth_color = Color("#5078a0")
	var mi: Node3D = PedMeshBuilderScript.build_ped_node(spec)
	mi.name = "CabPassenger"
	mi.scale = Vector3(0.72, 0.72, 0.72)
	mi.position = Vector3(0.42, 0.10, -0.15) # пассажирское сиденье справа
	player_car.add_child(mi)
	_cab_passenger = mi


func _remove_cab_passenger() -> void:
	if _cab_passenger != null:
		_cab_passenger.queue_free()
		_cab_passenger = null


func _spawn_walker(pos: Vector2, _order: RefCounted) -> void:
	var spec := PedMeshBuilder.Spec.new()
	var mi: Node3D = PedMeshBuilderScript.build_ped_node(spec)
	mi.name = "Walker"
	var wy := field.height_at(pos.x, pos.y) if field != null else 0.0
	mi.position = Vector3(pos.x, wy + 0.15, pos.y)
	add_child(mi)
	_walkers.append({"mesh": mi, "time": 0.0, "dir": Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, randf() * TAU)})


# --- Главный цикл обновления -------------------------------------------------

func tick(delta: float, player_car: PlayerCar, hour: float, rating: float, capacity: int, _weather: StringName) -> void:
	# Спавн новых заказов
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		var ppos_3d: Vector3 = player_car.global_position if player_car.is_inside_tree() else player_car.position
		var ppos := Vector2(ppos_3d.x, ppos_3d.z)
		spawn(rating, hour, capacity, ppos)
		var gap := balance.order_spawn_every_sec * (1.6 if Game.is_night() else 1.0)
		_spawn_timer = gap + randf() * 4.0

	# Анимация маркеров и устаревание открытых заказов
	for i in range(open_orders.size() - 1, -1, -1):
		var o := open_orders[i]
		if _markers.has(o.id):
			var m: Node3D = _markers[o.id]
			m.tick(delta)
		o.age += delta
		if o.time_limit > 0.0:
			o.timer -= delta
			if o.timer <= 0.0:
				_remove_order_visuals(o)
				open_orders.remove_at(i)
				Bus.order_event.emit(&"expired", o.id, {"order": o})
		elif o.age > balance.order_expire_sec:
			_remove_order_visuals(o)
			open_orders.remove_at(i)
			Bus.order_event.emit(&"expired", o.id, {"order": o})

	# Обновление активного заказа
	if active_order != null:
		if _drop_marker != null:
			_drop_marker.tick(delta)

		if active_order.time_limit > 0.0:
			active_order.timer -= delta
			if active_order.timer <= 0.0:
				fail(active_order, &"time")

		# Смена маршрута для пьяного пассажира на середине пути
		if active_order.type_id == &"drunk" and not active_order.drunk_changed:
			var car_3d: Vector3 = player_car.global_position if player_car.is_inside_tree() else player_car.position
			var car_p := Vector2(car_3d.x, car_3d.z)
			var total_d: float = active_order.dist_m
			var cur_drop_p: Vector2 = active_order.current_target_pos()
			var rem_d := car_p.distance_to(cur_drop_p)
			if total_d > 0.0 and (1.0 - rem_d / total_d) > 0.45:
				active_order.drunk_changed = true
				var new_pt := _pick_pickup_point(&"center", car_p)
				active_order.drops[active_order.drop_idx] = {"pos": new_pt, "name": "…передумал, едем в Центр", "district": &"center"}
				active_order.est_pay = roundi(active_order.est_pay * 1.35)
				_show_drop_marker(new_pt)
				Bus.notify.emit(&"toast", "Пассажир передумал! Новый адрес назначения.", {"color": Color("#c070e0")})
				Bus.notify.emit(&"dialogue", "Ой, браток, шеф, подожди! Не туда едем, мне в другое место надо!", {"speaker": active_order.client_name, "avatar": active_order.client_avatar})

	# Анимация уходящих пешеходов
	for i in range(_walkers.size() - 1, -1, -1):
		var w := _walkers[i]
		w["time"] += delta
		var mi: Node3D = w["mesh"]
		var dir: Vector3 = w["dir"]
		mi.position += dir * 1.5 * delta
		var y := field.height_at(mi.position.x, mi.position.z) if field != null else 0.0
		mi.position.y = y + 0.15
		if w["time"] > 6.0:
			mi.queue_free()
			_walkers.remove_at(i)


func _on_player_crashed(impact: float, _victim: StringName) -> void:
	if active_order == null:
		return
	if active_order.type_id == &"package" and impact > 15.0:
		if not active_order.fragile_broken:
			active_order.fragile_broken = true
			Bus.notify.emit(&"toast", "Хрупкий груз повреждён! Штраф к оплате.", {"color": Color("#ff7b72")})
	elif active_order.type_id == &"vip" and impact > 22.0:
		Bus.notify.emit(&"toast", "VIP-клиент возмущён аварией и покидает такси!", {"color": Color("#ff7b72")})
		fail(active_order, &"vip_crash")


# --- Вспомогательные методы выборки ------------------------------------------

func _pick_pickup_point(district_id: StringName, player_pos: Vector2) -> Vector2:
	var pts := plan.pickup_pos if plan != null else PackedVector2Array()
	if pts.is_empty():
		return Vector2.ZERO
	if player_pos != Vector2.ZERO and randf() < 0.60:
		var near: Array[Vector2] = []
		for p in pts:
			var d := p.distance_to(player_pos)
			if d > 40.0 and d < 240.0:
				near.append(p)
		if not near.is_empty():
			return near[randi() % near.size()]
	return pts[randi() % pts.size()]


func _pick_far_point(from_pt: Vector2, _districts_list: Array[DistrictData], min_dist: float) -> Vector2:
	var pts := plan.pickup_pos if plan != null else PackedVector2Array()
	var candidates: Array[Vector2] = []
	for p in pts:
		if p.distance_to(from_pt) >= min_dist:
			candidates.append(p)
	if not candidates.is_empty():
		return candidates[randi() % candidates.size()]
	return pts[randi() % pts.size()] if not pts.is_empty() else from_pt + Vector2(150.0, 0.0)


## LandmarkData не имеет unlock_rating (в отличие от DistrictData) —
## достопримечательности открыты игроку с любым рейтингом.
func _pick_random_landmark(exclude_id: StringName) -> LandmarkData:
	var pool: Array[LandmarkData] = []
	for l in districts.landmarks:
		if l.id != exclude_id:
			pool.append(l)
	if pool.is_empty():
		return districts.landmarks[0]
	return pool[randi() % pool.size()]


func _district_name(id: StringName) -> String:
	var d := districts.get_district(id)
	return tr(d.display_name) if d != null else String(id)


func _generate_client_name(mission_id: StringName) -> String:
	if mission_id == &"grandma":
		return "Бабушка Зинаида"
	elif mission_id == &"doctor":
		return "Доктор Соколова"
	var names: Array[String] = [
		"Георгий", "Арсен", "Мария", "Елена", "Дмитрий", "Руслан", "Ашот",
		"Ольга", "Виктор", "Зураб", "Светлана", "Сергей", "Анна", "Тигран"
	]
	return names[randi() % names.size()]


func _get_client_avatar(type_id: StringName, mission_id: StringName) -> String:
	if mission_id == &"grandma":
		return "👵"
	elif mission_id == &"doctor":
		return "👩‍⚕️"
	match type_id:
		&"urgent": return "⚡"
		&"vip": return "🤵"
		&"package": return "📦"
		&"drunk": return "🥴"
		&"group": return "👥"
		&"race": return "🏁"
		&"tour": return "📷"
		_: return "👨‍💼"


func _get_dialogue_quote(order: RefCounted, stage: StringName) -> String:
	var tdata := catalog.get_type(order.type_id)
	if tdata == null:
		return ""
	var bank: QuoteBank = tdata.quotes_pickup if stage == &"pickup" else tdata.quotes_dropoff
	if bank != null:
		return bank.pick(SeededRng.new())
	return ""
