class_name World
extends Node3D
## Корень игрового мира: небо, город, трафик, будущий менеджер пешеходов.
##
## Живёт и умирает вместе со сменой: менеджеры не автолоады, поэтому по
## завершении смены мир выгружается целиком, без остаточного состояния.

signal build_finished(stats: Dictionary)

## Строить город сразу при входе в дерево. Dir выключает это, чтобы успеть
## показать плашку загрузки до блокирующей генерации: иначе сигнал
## build_finished эмитится внутри _ready(), то есть раньше, чем на него
## успевают подписаться.
@export var auto_build := true

@onready var sky: SkyRig = $SkyRig
@onready var camera: ChaseCamera = $Camera3D

var city: CityBuilder
var collision := CityCollision.new()
var player: PlayerCar
var player_ped: PlayerPed
var in_car: bool = true
var traffic: TrafficLayer
var landmarks: LandmarkLayer
var pedestrians: PedLayer
var orders: Node
var police: PoliceManager
var style: StyleService
var gps: GpsRouter
var _drift_reaction_cd := 0.0
var hud: CanvasLayer
var pause_menu: CanvasLayer
var map_screen: CanvasLayer

## Точка старта смены: правая полоса проспекта, как в оригинале (0, 20).
const SPAWN := Vector3(-2.5, 0.0, 20.0)
## Сид трафика/пешеходов независим от генерации города (свой fork), чтобы
## плотность трафика/пешеходов не сдвигала расстановку зданий/пропсов при
## смене баланса.
const TRAFFIC_SEED_SALT := 0x54524146
const PED_SEED_SALT := 0x50454453
## Накопленное время для тактов светофоров.
var _signal_phase := -1


func _ready() -> void:
	if auto_build:
		build()


func build() -> void:
	city = CityBuilder.new()
	city.name = "City"
	add_child(city)
	var stats := city.build(Db.balance, Db.districts, Game.world_seed)
	city.refresh_signal_lenses()
	collision.build(get_world_3d().space, city.plan, city.field)
	stats["collision_shapes"] = collision.shape_count()
	stats["collision_bodies"] = collision.body_count()
	_spawn_landmarks()
	_spawn_player()
	_spawn_traffic()
	_spawn_pedestrians()
	_spawn_orders()
	_spawn_police()
	_spawn_style()
	_spawn_gps()
	_spawn_hud()
	traffic.manager.peds = pedestrians.manager
	pedestrians.manager.traffic = traffic.manager
	sky.set_time_of_day(Game.hour, Game.night_factor(),
		Db.weather.get_weather(Game.weather_id))
	Bus.world_ready.emit(Game.world_seed)
	build_finished.emit(stats)


func _spawn_landmarks() -> void:
	landmarks = LandmarkLayer.new()
	landmarks.name = "Landmarks"
	add_child(landmarks)
	landmarks.build(city.field, Db.districts.landmarks)


func _spawn_player() -> void:
	player = PlayerCar.new()
	player.name = "PlayerCar"
	add_child(player)
	var active_id: StringName = Game.garage.active_car_id
	player.runtime.upgrade_levels = Game.garage.upgrade_levels_for(active_id)
	player.runtime.tuning = Game.garage.tuning_for(active_id)
	player.setup(Db.cars.get_car(active_id), Db.upgrades, city.field)
	player.place(SPAWN, 0.0)
	player.crashed.connect(_on_player_crashed)
	camera.target = player
	camera.snap_to_target()


func _spawn_traffic() -> void:
	traffic = TrafficLayer.new()
	traffic.name = "Traffic"
	add_child(traffic)
	var rng := SeededRng.new(Game.world_seed).fork(TRAFFIC_SEED_SALT)
	traffic.setup(Db.traffic, city.field, city.lights, rng, Db.balance.traffic_count,
		get_world_3d().space, player.global_position.x, player.global_position.z)
	_apply_gfx_traffic_density()


## Пресет графики не сокращает число ИИ-агентов (SoA дёшев), только
## сколько из них рисовать — порт game.js:_applyDensity.
func _apply_gfx_traffic_density() -> void:
	if traffic == null:
		return
	var preset := Db.gfx.get_preset(Prefs.gfx_preset) if Db.gfx != null else null
	var density: float = preset.traffic_density if preset != null else 1.0
	traffic.set_visible_count(maxi(1, roundi(Db.balance.traffic_count * density)))


## Пешеходный граф уже построен CityBuilder (city.graph), но точки интереса
## (достопримечательности/подача такси/заправки) до этапа 8 некому было
## задать — порт initGraph() (peds.js:965-1003).
func _spawn_pedestrians() -> void:
	var poi_pos := PackedVector2Array()
	var poi_tags := PackedStringArray()
	for l in Db.districts.landmarks:
		if l == null:
			continue
		poi_pos.append(l.position)
		poi_tags.append(String(l.id))
	for p in city.plan.pickup_pos:
		poi_pos.append(p)
		poi_tags.append("pickup")
	for f in Db.districts.fuel_stations:
		poi_pos.append(f)
		poi_tags.append("fuel")
	city.graph.set_pois(poi_pos, poi_tags)

	pedestrians = PedLayer.new()
	pedestrians.name = "Pedestrians"
	add_child(pedestrians)
	var rng := SeededRng.new(Game.world_seed).fork(PED_SEED_SALT)
	pedestrians.setup(Db.peds, city.field, city.graph, city.lights, Db.balance.ped, rng,
		get_world_3d().space, Db.balance.ped_count,
		player.global_position.x, player.global_position.z)
	_apply_gfx_ped_density()


func _apply_gfx_ped_density() -> void:
	if pedestrians == null:
		return
	var preset := Db.gfx.get_preset(Prefs.gfx_preset) if Db.gfx != null else null
	var density: float = preset.ped_density if preset != null else 1.0
	pedestrians.set_visible_count(maxi(1, roundi(Db.balance.ped_count * density)))


func _spawn_orders() -> void:
	orders = OrderManager.new()
	orders.name = "OrderManager"
	add_child(orders)
	orders.setup(Db.orders, city.field, city.plan, Db.districts, Db.balance, player)


func _spawn_police() -> void:
	police = PoliceManager.new()
	police.setup(traffic.manager, city.field, city.lights, Db.balance.wanted, city.plan)
	if pedestrians != null and not pedestrians.manager.player_hit_ped.is_connected(_on_player_hit_ped):
		pedestrians.manager.player_hit_ped.connect(_on_player_hit_ped)


## Игрок сбил пешехода: базовый штраф + рейтинг, затем полиция может добавить
## розыск/штраф, если рядом патруль с прямой видимостью (порт game.js ped:hit).
func _on_player_hit_ped() -> void:
	var b := Db.balance
	Game.bump("peds", "total_peds", 1.0)
	Game.spend(b.hit_ped_fine)
	Game.add_rating(-float(b.rating_loss_hit_ped))
	Bus.notify.emit(&"toast",
		"Вы сбили пешехода! -%d ₽, рейтинг -%d" % [b.hit_ped_fine, b.rating_loss_hit_ped],
		{"color": Color("#ff6b6b")})
	if police != null:
		police.check_hit_ped(player.global_position.x, player.global_position.z)
	if style != null:
		style.reset_streaks()


## Этап 12 (Juice): дрифт, идеальная остановка, near-miss + серии, комбо
## заказов. Порт game.js:1491-1690 поверх StyleService/StyleConfig.
func _spawn_style() -> void:
	style = StyleService.new(Db.balance.style)
	if not Bus.order_event.is_connected(_on_order_event_style):
		Bus.order_event.connect(_on_order_event_style)
	if police != null:
		if not police.violation_fined.is_connected(_on_police_violation_fined):
			police.violation_fined.connect(_on_police_violation_fined)
		if not police.escaped.is_connected(_on_police_escaped):
			police.escaped.connect(_on_police_escaped)


## Штраф ГИБДД обрывает только комбо заказов, остальные серии стиля не трогает
## (game.js:472).
func _on_police_violation_fined(_id: StringName) -> void:
	if style != null:
		style.reset_combo()


## Побег от полиции — тряска камеры растёт с пиковым уровнем розыска
## (game.js:484-485); единственный триггер shake(), которого не было в порте.
func _on_police_escaped(peak_level: int) -> void:
	camera.shake(0.3 + peak_level * 0.08, 0.15 + peak_level * 0.08)


func _on_order_event_style(kind: StringName, _order_id: int, data: Dictionary) -> void:
	if style == null or player == null:
		return
	match kind:
		&"completed":
			if style.has_pending_perfect_stop():
				var ps: Dictionary = style.consume_perfect_stop()
				var ps_reward: int = ps.get("reward", 0)
				Game.add_money(ps_reward)
				Game.bump("perfect_stops", "total_perfect_stops", 1.0)
				player.runtime.style = clampf(
					player.runtime.style + Db.balance.style.perfect_stop_style_bonus, 0.0, 1.0)
				Bus.notify.emit(&"toast", "✨ Идеальная остановка! +%d ₽" % ps_reward,
					{"color": Color("#7ee787")})
				Bus.juice_event.emit(&"perfect_stop", ps)

			var pay: int = data.get("pay", 0)
			var combo: Dictionary = style.register_order_completed(pay)
			var bonus_pay: int = combo.get("bonus_pay", 0)
			if bonus_pay > 0:
				Game.add_money(bonus_pay)
			var streak: int = combo.get("streak", 0)
			Game.track_shift_max("best_combo", float(streak))
			if streak in Db.balance.style.combo_streak_counts:
				Bus.notify.emit(&"toast",
					"🔥 СЕРИЯ ЗАКАЗОВ ×%d! Бонус ×%.2f" % [streak, combo.get("mult", 1.0)],
					{"color": Color("#ffd75e")})
			Bus.juice_event.emit(&"combo", combo)
		&"failed":
			# Проваленный заказ обрывает только заслуженную, но не выданную
			# идеальную остановку — комбо-серия не сбрасывается (game.js:574-578).
			style.cancel_perfect_stop()


## Этап 13 (GPS): дорожный граф + маршрутизация до цели заказа/заправки.
## Строится сразу после City (нужен только field), но после StyleService по
## порядку вызовов из build() — зависимостей между ними нет.
func _spawn_gps() -> void:
	gps = GpsRouter.new(city.field, Db.districts, Db.balance)


func _spawn_hud() -> void:
	hud = Hud.new()
	hud.name = "HUD"
	add_child(hud)
	hud.setup(self)

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	Dir.register_screen(&"pause", pause_menu)
	pause_menu.resume_requested.connect(func() -> void: Dir.pop())
	pause_menu.main_menu_requested.connect(_on_pause_main_menu)
	pause_menu.end_shift_requested.connect(_on_pause_end_shift)

	var map_script: GDScript = load("res://ui/screens/map_screen.gd")
	map_screen = map_script.new()
	map_screen.name = "MapScreen"
	add_child(map_screen)
	Dir.register_screen(&"map", map_screen)



func _on_pause_main_menu() -> void:
	Dir.push(&"menu")


func _on_pause_end_shift() -> void:
	Game.stop_shift()
	Dir.push(&"shift_end")


func _on_player_crashed(impact: float, victim: StringName) -> void:
	Game.bump("crashes", "total_crashes", 1.0)
	# Тряска пропорциональна удару, но с потолком (game.js:390).
	camera.shake(0.45, minf(0.6, impact / 40.0))
	if style != null:
		style.reset_streaks()
	Bus.player_crashed.emit(impact, victim)


var prof_sky_us := 0
var prof_lights_us := 0
var prof_traffic_us := 0
var prof_pedestrians_us := 0
var prof_orders_us := 0

func _process(delta: float) -> void:
	if city == null:
		return
	var t0 := Time.get_ticks_usec()
	Game.advance_time(delta)
	sky.set_time_of_day(Game.hour, Game.night_factor(),
		Db.weather.get_weather(Game.weather_id))
	var t1 := Time.get_ticks_usec()
	prof_sky_us += (t1 - t0)

	if in_car and player != null:
		var tf := player.get_global_transform_interpolated() if player.is_inside_tree() else player.global_transform
		camera.target_heading = Heading.from_vector(tf.basis.z)
		camera.target_ground = tf.origin.y
		Game.track_max("max_speed_kmh", player.speed_kmh())
	elif not in_car and player_ped != null:
		var tf := player_ped.get_global_transform_interpolated() if player_ped.is_inside_tree() else player_ped.global_transform
		camera.target_heading = Heading.from_vector(-tf.basis.z)
		camera.target_ground = tf.origin.y


	t0 = Time.get_ticks_usec()
	city.lights.advance(delta)
	# Линзы перекрашиваются только при смене фазы, а не каждый кадр:
	# это запись в 192 инстанса, её нельзя делать по 60 раз в секунду.
	var phase := int(city.lights.local_time(4) / 2.0)
	if phase != _signal_phase:
		_signal_phase = phase
		city.refresh_signal_lenses()
	t1 = Time.get_ticks_usec()
	prof_lights_us += (t1 - t0)

	var p_x: float = player.global_position.x if in_car else player_ped.global_position.x
	var p_z: float = player.global_position.z if in_car else player_ped.global_position.z
	var p_h: float = player.motion.heading if in_car else player_ped.logic.heading
	var p_sp: float = player.motion.speed if in_car else player_ped.logic.speed
	var p_vx: float = player.motion.velocity.x if in_car else player_ped.velocity.x
	var p_vz: float = player.motion.velocity.z if in_car else player_ped.velocity.z

	if traffic != null:
		t0 = Time.get_ticks_usec()
		traffic.tick(delta, p_x, p_z, _traffic_density())
		t1 = Time.get_ticks_usec()
		prof_traffic_us += (t1 - t0)

	if pedestrians != null:
		t0 = Time.get_ticks_usec()
		pedestrians.tick(delta, p_x, p_z, p_h, p_sp, p_vx, p_vz, Game.is_night())
		t1 = Time.get_ticks_usec()
		prof_pedestrians_us += (t1 - t0)

	if orders != null and in_car and player != null:
		t0 = Time.get_ticks_usec()
		orders.tick(delta, player, Game.hour, Game.rating, 1, Game.weather_id)
		t1 = Time.get_ticks_usec()
		prof_orders_us += (t1 - t0)

	if gps != null:
		var active: RefCounted = orders.active_order if orders != null else null
		var has_order := active != null
		var drop_pos: Vector2 = active.current_target_pos() if has_order else Vector2.ZERO
		var fuel_ratio: float = player.runtime.fuel_ratio() if in_car and player != null else 1.0
		gps.update(delta, Vector2(p_x, p_z), in_car, has_order, drop_pos, fuel_ratio)

	if police != null:
		police.update(delta, p_x, p_z, in_car, p_sp, p_h)

	if style != null and in_car and player != null and player.is_active:
		_update_style(delta)



## Дрифт, идеальная остановка и near-miss тикаются только за рулём — порт
## game.js:_updateDrift/_updatePerfectStop/_updateNearMiss (Этап 12).
func _update_style(delta: float) -> void:
	if _drift_reaction_cd > 0.0:
		_drift_reaction_cd -= delta

	var axes := Inp.drive_axes()
	var has_passenger := player.runtime.passenger_count > 0

	var drift: Dictionary = style.update_drift(delta, axes.handbrake, player.motion.slip,
		player.motion.speed, has_passenger)
	if not drift.is_empty():
		var reward: int = drift.get("reward", 0)
		Game.add_money(reward)
		Game.bump("drifts", "total_drifts", 1.0)
		var style_bonus: float = drift.get("style_bonus", 0.0)
		if style_bonus > 0.0:
			player.runtime.style = clampf(player.runtime.style + style_bonus, 0.0, 1.0)
		Bus.notify.emit(&"toast", "💨 Занос! +%d ₽" % reward, {"color": Color("#ffd75e")})
		Bus.juice_event.emit(&"drift", drift)
		_maybe_speak_drift_reaction()

	var braking := axes.brake > 0.0 and not axes.handbrake
	var ps_eligible := orders != null and orders.active_order != null and has_passenger
	style.update_perfect_stop(delta, player.motion.speed, braking, ps_eligible)

	_update_near_miss()


## Реплика пассажира на удачный занос — не чаще раза в drift_reaction_cooldown,
## только при перевозке с активным заказом (game.js:1518-1526).
func _maybe_speak_drift_reaction() -> void:
	if orders == null or orders.active_order == null or player.runtime.passenger_count <= 0:
		return
	if _drift_reaction_cd > 0.0:
		return
	var bank: QuoteBank = Db.orders.drift_reactions if Db.orders != null else null
	if bank == null:
		return
	var quote := bank.pick(SeededRng.new())
	if quote.is_empty():
		return
	_drift_reaction_cd = Db.balance.style.drift_reaction_cooldown
	var o: RefCounted = orders.active_order
	Bus.notify.emit(&"dialogue", quote, {"speaker": o.client_name, "avatar": o.client_avatar})


func _update_near_miss() -> void:
	var cfg := Db.balance.style
	if player.motion.speed < cfg.near_miss_min_speed:
		return

	var fwd := Heading.forward(player.motion.heading)
	var shape: CarShapeData = player.runtime.stats.shape
	var rc := shape.collider_radius()
	var sep := shape.collider_separation()
	var px := player.global_position.x
	var pz := player.global_position.z
	var speed := player.motion.speed
	var now := Game.shift_elapsed

	if traffic != null:
		var tm := traffic.manager
		for i in tm.count:
			var ex := tm.world_x(i)
			var ez := tm.world_z(i)
			if absf(ex - px) > 7.0 or absf(ez - pz) > 7.0:
				if tm.nm_passed[i] == 1 or tm.nm_hit[i] == 1:
					tm.nm_passed[i] = 0
					tm.nm_hit[i] = 0
				continue
			var e_radius: float = tm.type_of(i).radius if tm.type_of(i) != null else 2.0
			var r := style.evaluate_near_miss(ex, ez, px, pz, fwd.x, fwd.z, rc, sep, e_radius,
				cfg.near_miss_car_margin, speed, tm.nm_passed[i] == 1, tm.nm_hit[i] == 1)
			if r.get("clear_flags", false):
				tm.nm_passed[i] = 0
				tm.nm_hit[i] = 0
			elif r.get("hit", false):
				tm.nm_hit[i] = 1
				tm.nm_passed[i] = 0
			elif r.get("triggered", false):
				tm.nm_passed[i] = 1
				_apply_near_miss_reward(false, now)

	if pedestrians != null:
		var pm := pedestrians.manager
		for i in pm.count:
			if pm.alive[i] == 0:
				continue
			var ex := pm.world_x(i)
			var ez := pm.world_z(i)
			if absf(ex - px) > 7.0 or absf(ez - pz) > 7.0:
				if pm.nm_passed[i] == 1 or pm.nm_hit[i] == 1:
					pm.nm_passed[i] = 0
					pm.nm_hit[i] = 0
				continue
			if pm.knock_t[i] > 0.0:
				continue
			if pm.hit_cd[i] > 0.0:
				pm.nm_hit[i] = 1
				continue
			var r := style.evaluate_near_miss(ex, ez, px, pz, fwd.x, fwd.z, rc, sep, 0.45,
				cfg.near_miss_ped_margin, speed, pm.nm_passed[i] == 1, pm.nm_hit[i] == 1)
			if r.get("clear_flags", false):
				pm.nm_passed[i] = 0
				pm.nm_hit[i] = 0
			elif r.get("hit", false):
				pm.nm_hit[i] = 1
				pm.nm_passed[i] = 0
			elif r.get("triggered", false):
				pm.nm_passed[i] = 1
				_apply_near_miss_reward(true, now)


func _apply_near_miss_reward(is_ped: bool, now: float) -> void:
	var r: Dictionary = style.trigger_near_miss(is_ped, now)
	var reward := roundi(r.get("reward", 0.0))
	Game.add_money(reward)
	Game.bump("near_misses", "total_near_misses", 1.0)
	var streak: int = r.get("streak", 0)
	Game.track_shift_max("max_near_miss_streak", float(streak))
	Game.track_max("max_near_miss_streak", float(streak))
	if player.runtime.passenger_count > 0:
		player.runtime.style = clampf(
			player.runtime.style + Db.balance.style.near_miss_style_bonus, 0.0, 1.0)
	if streak in Db.balance.style.near_miss_streak_counts:
		Bus.notify.emit(&"toast", "🔥 Серия сближений ×%d! (+%d ₽)" % [streak, reward],
			{"color": Color("#ffd75e")})
	else:
		var label := "⚡ Опасное сближение!" if is_ped else "⚡ Опасный обгон!"
		Bus.notify.emit(&"toast", "%s +%d ₽" % [label, reward], {"color": Color("#70d6ff")})
	Bus.juice_event.emit(&"near_miss", r)


## Скорость/плотность трафика зависит от погоды и часа (game.js:1326).
func _traffic_density() -> float:
	var w: WeatherData = Db.weather.get_weather(Game.weather_id) if Db.weather != null else null
	var weather_mult := w.traffic if w != null else 1.0
	var night_mult := Db.balance.traffic_night_mult if Game.is_night() else 1.0
	return weather_mult * night_mult


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE):
		if Dir.state == &"pause":
			Dir.pop()
		elif Dir.state == &"driving":
			Dir.push(&"pause")
		return

	if event.is_action_pressed(&"map"):
		if Dir.state == &"map":
			Dir.pop()
		elif Dir.state == &"driving":
			Dir.push(&"map")
		return

	if event.is_action_pressed(&"interact"):
		if _try_interact_order():
			return
		if in_car:
			exit_car()
		else:
			enter_car()
	elif event.is_action_pressed(&"lights") and player != null and in_car:
		player.set_lights(not player.lights_on())


func _try_interact_order() -> bool:
	if orders == null or not in_car or player == null:
		return false
	var ppos := Vector2(player.global_position.x, player.global_position.z)

	# 1. Завершить активный заказ
	if orders.active_order != null:
		var target: Vector2 = orders.active_order.current_target_pos()
		if ppos.distance_to(target) <= 8.0:
			var res: Dictionary = orders.complete(player, Game.hour, Game.rating)
			return not res.is_empty()

	# 2. Принять открытый заказ
	for o in orders.open_orders:
		if ppos.distance_to(o.pickup_pos) <= 8.0:
			return orders.accept(o, player)

	return false


func exit_car() -> bool:
	if not in_car or player == null or city == null:
		return false
	if not PlayerPedLogic.can_exit_car(player.motion.speed, Db.balance.ped):
		Bus.notify.emit(&"toast", "Машина движется слишком быстро, чтобы выйти!", {})
		return false

	var candidates := PlayerPedLogic.get_exit_offsets(player.global_position, player.motion.heading)
	var spawn_pos := Vector3.ZERO
	var found := false

	var space_state := get_world_3d().direct_space_state
	for cand in candidates:
		var q := PhysicsPointQueryParameters3D.new()
		q.position = cand + Vector3(0.0, 0.85, 0.0)
		q.collision_mask = 1
		if space_state.intersect_point(q, 1).is_empty():
			spawn_pos = cand
			found = true
			break

	if not found:
		Bus.notify.emit(&"toast", "Слева нет места, чтобы выйти!", {})
		return false

	player.is_active = false
	player.motion.speed = 0.0
	player.motion.forward_speed = 0.0
	player.motion.lateral_speed = 0.0
	player.motion.velocity = Vector3.ZERO
	player.velocity = Vector3.ZERO

	if player_ped == null:
		player_ped = PlayerPed.new()
		player_ped.name = "PlayerPed"
		add_child(player_ped)
		player_ped.setup(city.field, Db.balance.ped, Prefs.driver, camera,
			pedestrians.manager if pedestrians != null else null)
		player_ped.police = police

	player_ped.place(spawn_pos, player.motion.heading)
	player_ped.show()
	player_ped.set_physics_process(true)
	in_car = false

	if traffic != null:
		traffic.manager.player_ped = player_ped

	camera.target = player_ped
	camera.set_mode(ChaseCamera.Mode.PED)
	camera.snap_to_target()

	Bus.vehicle_mode_changed.emit(false)
	Bus.game_state_changed.emit(&"walking")
	Bus.notify.emit(&"toast", "Пеший режим: WASD — ходьба, Shift — бег, Space — прыжок, F — удар, E — сесть в авто", {})
	return true


func enter_car() -> bool:
	if in_car or player_ped == null or player == null:
		return false
	if not PlayerPedLogic.can_enter_car(player_ped.global_position, player.global_position, Db.balance.ped):
		Bus.notify.emit(&"toast", "Подойдите ближе к машине!", {})
		return false

	player_ped.hide()
	player_ped.set_physics_process(false)
	in_car = true
	player.is_active = true

	if traffic != null:
		traffic.manager.player_ped = null

	camera.target = player
	camera.set_mode(ChaseCamera.Mode.CAR)
	camera.snap_to_target()

	Bus.vehicle_mode_changed.emit(true)
	Bus.game_state_changed.emit(&"driving")
	return true


func _exit_tree() -> void:
	collision.clear()

