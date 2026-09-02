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
var traffic: TrafficLayer
var landmarks: LandmarkLayer
var pedestrians: PedLayer

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
	var stats := city.build(Db.balance, Db.districts)
	city.refresh_signal_lenses()
	collision.build(get_world_3d().space, city.plan, city.field)
	stats["collision_shapes"] = collision.shape_count()
	stats["collision_bodies"] = collision.body_count()
	_spawn_landmarks()
	_spawn_player()
	_spawn_traffic()
	_spawn_pedestrians()
	traffic.manager.peds = pedestrians.manager
	pedestrians.manager.traffic = traffic.manager
	sky.set_time_of_day(Game.hour, Game.night_factor(),
		Db.weather.get_weather(Game.weather_id))
	Bus.world_ready.emit(Db.balance.world_seed)
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
	player.setup(Db.cars.get_car(&"taxi"), Db.upgrades, city.field)
	player.place(SPAWN, 0.0)
	player.crashed.connect(_on_player_crashed)
	camera.target = player
	camera.snap_to_target()


func _spawn_traffic() -> void:
	traffic = TrafficLayer.new()
	traffic.name = "Traffic"
	add_child(traffic)
	var rng := SeededRng.new(Db.balance.world_seed).fork(TRAFFIC_SEED_SALT)
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
	var rng := SeededRng.new(Db.balance.world_seed).fork(PED_SEED_SALT)
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


func _on_player_crashed(impact: float, victim: StringName) -> void:
	# Тряска пропорциональна удару, но с потолком (game.js:390).
	camera.shake(0.45, minf(0.6, impact / 40.0))
	Bus.player_crashed.emit(impact, victim)


func _process(delta: float) -> void:
	if city == null:
		return
	if player != null:
		camera.target_heading = player.motion.heading
		camera.target_ground = player.global_position.y
	city.lights.advance(delta)
	# Линзы перекрашиваются только при смене фазы, а не каждый кадр:
	# это запись в 192 инстанса, её нельзя делать по 60 раз в секунду.
	var phase := int(city.lights.local_time(4) / 2.0)
	if phase != _signal_phase:
		_signal_phase = phase
		city.refresh_signal_lenses()
	if traffic != null and player != null:
		traffic.tick(delta, player.global_position.x, player.global_position.z,
			_traffic_density())
	if pedestrians != null and player != null:
		pedestrians.tick(delta, player.global_position.x, player.global_position.z,
			player.motion.heading, player.motion.speed,
			player.motion.velocity.x, player.motion.velocity.z, Game.is_night())


## Скорость/плотность трафика зависит от погоды и часа (game.js:1326).
func _traffic_density() -> float:
	var w: WeatherData = Db.weather.get_weather(Game.weather_id) if Db.weather != null else null
	var weather_mult := w.traffic if w != null else 1.0
	var night_mult := Db.balance.traffic_night_mult if Game.is_night() else 1.0
	return weather_mult * night_mult


func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	if event.is_action_pressed(&"lights"):
		player.set_lights(not player.lights_on())


func _exit_tree() -> void:
	collision.clear()
