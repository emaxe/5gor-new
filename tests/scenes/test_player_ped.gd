class_name TestPlayerPedScene
extends Node3D
## Полигон пешего режима: тестирование выхода/посадки в авто, ходьбы/бега,
## прыжков, ударов кулаком по NPC, получения урона и кастомизации водителя.

@onready var sky: SkyRig = $SkyRig
@onready var camera: ChaseCamera = $Camera3D
@onready var info_label: Label = $CanvasLayer/InfoLabel

var city: CityBuilder
var collision := CityCollision.new()
var player_car: PlayerCar
var player_ped: PlayerPed
var pedestrians: PedLayer
var in_car := false

var _driver_idx := 0
const DRIVER_PRESETS: Array[Dictionary] = [
	{
		&"belly": false,
		&"cap": true,
		&"shirt_color": Color(0.16, 0.28, 0.50),
		&"pants_color": Color(0.16, 0.16, 0.23),
		&"skin_color": Color(0.96, 0.82, 0.69),
		&"hair_color": Color(0.10, 0.10, 0.10),
	},
	{
		&"belly": true,
		&"cap": true,
		&"shirt_color": Color(0.55, 0.22, 0.20),
		&"pants_color": Color(0.20, 0.20, 0.20),
		&"skin_color": Color(0.85, 0.66, 0.50),
		&"hair_color": Color(0.40, 0.25, 0.15),
	},
	{
		&"belly": false,
		&"cap": false,
		&"shirt_color": Color(0.20, 0.45, 0.25),
		&"pants_color": Color(0.12, 0.18, 0.30),
		&"skin_color": Color(0.98, 0.85, 0.70),
		&"hair_color": Color(0.80, 0.80, 0.80),
	},
	{
		&"belly": true,
		&"cap": false,
		&"shirt_color": Color(0.25, 0.25, 0.28),
		&"pants_color": Color(0.30, 0.25, 0.20),
		&"skin_color": Color(0.65, 0.45, 0.30),
		&"hair_color": Color(0.08, 0.08, 0.08),
	},
]


func _ready() -> void:
	city = CityBuilder.new()
	city.name = "City"
	add_child(city)
	city.build(Db.balance, Db.districts)
	city.refresh_signal_lenses()
	collision.build(get_world_3d().space, city.plan, city.field)

	# Пешеходы-мишени рядом со стартом для проверки ударов
	_spawn_pedestrians()

	# Машина игрока
	player_car = PlayerCar.new()
	player_car.name = "PlayerCar"
	add_child(player_car)
	player_car.setup(Db.cars.get_car(&"taxi"), Db.upgrades, city.field)
	player_car.place(Vector3(-2.5, 0.0, 20.0), 0.0)

	# Пеший игрок рядом с машиной
	player_ped = PlayerPed.new()
	player_ped.name = "PlayerPed"
	add_child(player_ped)
	player_ped.setup(city.field, Db.balance.ped, DRIVER_PRESETS[0], camera,
		pedestrians.manager if pedestrians != null else null)
	player_ped.place(Vector3(-4.5, 0.0, 20.0), 0.0)

	in_car = false
	player_car.is_active = false
	camera.target = player_ped
	camera.set_mode(ChaseCamera.Mode.PED)
	camera.snap_to_target()

	sky.set_time_of_day(12.0, 0.0, Db.weather.get_weather(&"clear"))


func _spawn_pedestrians() -> void:
	pedestrians = PedLayer.new()
	pedestrians.name = "Pedestrians"
	add_child(pedestrians)
	var rng := SeededRng.new(2026)
	pedestrians.setup(Db.peds, city.field, city.graph, city.lights, Db.balance.ped, rng,
		get_world_3d().space, 20, -2.5, 20.0)

	# Ставим троих NPC рядом с игроком для проверки драки
	var mgr := pedestrians.manager
	if mgr.count >= 3:
		mgr.x[0] = -4.5; mgr.z[0] = 22.0; mgr.mode[0] = PedManager.Mode.IDLE
		mgr.x[1] = -3.0; mgr.z[1] = 23.0; mgr.mode[1] = PedManager.Mode.IDLE
		mgr.x[2] = -6.0; mgr.z[2] = 21.0; mgr.mode[2] = PedManager.Mode.IDLE


func _process(delta: float) -> void:
	if in_car and player_car != null:
		var tf := player_car.get_global_transform_interpolated() if player_car.is_inside_tree() else player_car.global_transform
		camera.target_heading = Heading.from_vector(tf.basis.z)
		camera.target_ground = tf.origin.y
	elif not in_car and player_ped != null:
		var tf := player_ped.get_global_transform_interpolated() if player_ped.is_inside_tree() else player_ped.global_transform
		camera.target_heading = Heading.from_vector(-tf.basis.z)
		camera.target_ground = tf.origin.y


	city.lights.advance(delta)
	var p_pos := player_car.global_position if in_car else player_ped.global_position
	var p_h := player_car.motion.heading if in_car else player_ped.logic.heading
	var p_sp := player_car.motion.speed if in_car else player_ped.logic.speed
	var p_vx := player_car.motion.velocity.x if in_car else player_ped.velocity.x
	var p_vz := player_car.motion.velocity.z if in_car else player_ped.velocity.z

	if pedestrians != null:
		pedestrians.tick(delta, p_pos.x, p_pos.z, p_h, p_sp, p_vx, p_vz, false)

	_update_ui()


func _update_ui() -> void:
	if info_label == null:
		return
	if in_car:
		info_label.text = "РЕЖИМ: В МАШИНЕ (ТАКСИ)\nСкорость: %.1f км/ч\n[E] - Выйти из машины\nWASD - Управление" % player_car.speed_kmh()
	else:
		var ko_str := " [НОКАУТ!]" if player_ped.logic.is_knocked_out else (" [СТАН!]" if player_ped.logic.stun_t > 0.0 else "")
		var dist_to_car := player_ped.global_position.distance_to(player_car.global_position)
		info_label.text = "РЕЖИМ: ПЕШЕХОД%s\nHP: %d / %d\nСкорость: %.1f м/с (%s)\nДистанция до авто: %.1f м (посадка <= 3.0 м)\n[E] - Сесть в авто\n[F] - Удар кулаком\n[Space] - Прыжок\n[Shift] - Бег\n[1-4] - Пресет внешности водителя" % [
			ko_str,
			player_ped.logic.hp, player_ped.logic.max_hp,
			player_ped.logic.speed, "бег" if player_ped.logic.is_running else "ходьба",
			dist_to_car
		]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact"):
		if in_car:
			_exit_car()
		else:
			_enter_car()
	elif event is InputEventKey and event.pressed:
		var ek := event as InputEventKey
		if ek.keycode >= KEY_1 and ek.keycode <= KEY_4:
			_set_driver_preset(ek.keycode - KEY_1)


func _exit_car() -> void:
	if not PlayerPedLogic.can_exit_car(player_car.motion.speed, Db.balance.ped):
		return
	var candidates := PlayerPedLogic.get_exit_offsets(player_car.global_position, player_car.motion.heading)
	var spawn_pos := candidates[0]
	player_car.is_active = false
	player_car.motion.speed = 0.0
	player_car.velocity = Vector3.ZERO
	player_ped.place(spawn_pos, player_car.motion.heading)
	player_ped.show()
	player_ped.set_physics_process(true)
	in_car = false
	camera.target = player_ped
	camera.set_mode(ChaseCamera.Mode.PED)
	camera.snap_to_target()


func _enter_car() -> void:
	if not PlayerPedLogic.can_enter_car(player_ped.global_position, player_car.global_position, Db.balance.ped):
		return
	player_ped.hide()
	player_ped.set_physics_process(false)
	in_car = true
	player_car.is_active = true
	camera.target = player_car
	camera.set_mode(ChaseCamera.Mode.CAR)
	camera.snap_to_target()


func _set_driver_preset(idx: int) -> void:
	if idx < 0 or idx >= DRIVER_PRESETS.size():
		return
	_driver_idx = idx
	player_ped.setup(city.field, Db.balance.ped, DRIVER_PRESETS[idx], camera,
		pedestrians.manager if pedestrians != null else null)


func _exit_tree() -> void:
	collision.clear()
