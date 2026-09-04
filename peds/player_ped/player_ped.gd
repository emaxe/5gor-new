class_name PlayerPed
extends CharacterBody3D
## Пешеход-аватар игрока. Порт PlayerPed (playerped.js).
##
## Управляется с клавиатуры/геймпада/тача через Inp.walk_axes().
## Коллизии со статикой города, машиной игрока и трафиком разрешаются через
## CharacterBody3D.move_and_slide() с радиусом 0.35 м.

signal punched()
signal hit_taken(damage: int, is_knocked_out: bool)
signal knocked_out()
signal recovered()

const COLLISION_LAYER := 8
const CAPSULE_RADIUS := 0.35
const CAPSULE_HEIGHT := 1.7

var logic := PlayerPedLogic.new()
var field: CityField
var config: PedConfig
var rig: DriverBuilder.DriverRig
var camera: ChaseCamera
var peds: PedManager
var police: PoliceManager

var _shape: CollisionShape3D
var _prev_knocked_out := false


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	up_direction = Vector3.UP
	collision_layer = COLLISION_LAYER
	# Коллизии: слой 1 (город/застройка), 2 (машина игрока), 4 (трафик).
	collision_mask = 1 | 2 | TrafficManager.COLLISION_LAYER

	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_RADIUS
	cap.height = CAPSULE_HEIGHT
	_shape.shape = cap
	_shape.position = Vector3(0.0, CAPSULE_HEIGHT * 0.5, 0.0)
	add_child(_shape)


func setup(city_field: CityField, ped_config: PedConfig,
		driver_options: Dictionary, cam: ChaseCamera = null,
		ped_mgr: PedManager = null) -> void:
	field = city_field
	config = ped_config
	camera = cam
	peds = ped_mgr

	logic.init_with_config(config)

	if rig != null and is_instance_valid(rig.root):
		rig.root.queue_free()

	var spec := DriverBuilder.DriverSpec.from_dictionary(driver_options)
	rig = DriverBuilder.build(spec)
	add_child(rig.root)


func place(pos: Vector3, new_heading: float) -> void:
	logic.set_pos(pos.x, pos.z, new_heading)
	if field != null:
		logic.ground_y = field.surface_height_at(pos.x, pos.z)
	global_position = Vector3(pos.x, logic.ground_y, pos.z)
	basis = Heading.basis_of(new_heading)
	reset_physics_interpolation()
	_prev_knocked_out = false


func _physics_process(delta: float) -> void:
	logic.advance_timers(delta)

	if not logic.is_knocked_out and logic.stun_t <= 0.0:
		if Input.is_action_just_pressed(&"jump"):
			logic.jump(config)
		if Input.is_action_just_pressed(&"punch"):
			try_punch()

	var axes := Inp.walk_axes()
	var cam_yaw := camera.yaw if camera != null else logic.heading
	var move_dir := PlayerPedLogic.compute_move_vector(axes.forward, axes.right, cam_yaw)

	var prev_x := logic.x
	var prev_z := logic.z

	logic.step_motion(move_dir, axes.running, config, delta)

	if field != null:
		var clamped := PlayerPedLogic.clamp_bounds(logic.x, logic.z)
		logic.x = clamped.x
		logic.z = clamped.y
		var target_gy := field.surface_height_at(logic.x, logic.z)
		logic.ground_y = MathUtils.damp(logic.ground_y, target_gy, 0.45, delta)


	logic.step_vertical(config, delta)

	# Смещение за текущий кадр передаётся в CharacterBody3D
	var target_vx := (logic.x - prev_x) / delta
	var target_vz := (logic.z - prev_z) / delta
	velocity = Vector3(target_vx, 0.0, target_vz)
	move_and_slide()

	# После реакции коллизий синхронизируем координаты обратно в логику
	logic.x = global_position.x
	logic.z = global_position.z
	global_position.y = logic.ground_y + logic.y_off

	# Поворот персонажа и визуальная анимация
	basis = Heading.basis_of(logic.heading)
	if rig != null:
		DriverBuilder.animate_rig(rig, logic.walk_phase, logic.speed,
			logic.is_running, logic.punch_anim_t, logic.stun_t,
			logic.is_knocked_out)

	# Учёт пешего километража для ачивок и статистики
	if logic.speed > 0.05 and not logic.is_knocked_out:
		var dist_km := (logic.speed * delta) / 1000.0
		Game.bump("km", "total_km", dist_km)

	# Отслеживание момента выхода из нокаута
	if _prev_knocked_out and not logic.is_knocked_out:
		recovered.emit()
	_prev_knocked_out = logic.is_knocked_out


func take_hit(from_x: float, from_z: float, damage: int = 1) -> bool:
	var was_ko := logic.is_knocked_out
	var is_ko := logic.take_hit(from_x, from_z, damage, config)
	hit_taken.emit(damage, is_ko)
	if is_ko and not was_ko:
		knocked_out.emit()
	if camera != null:
		camera.shake(0.3, 0.3)
	return is_ko


func apply_knockback(vx: float, vz: float, duration: float = 0.25) -> void:
	logic.apply_knockback(vx, vz, duration)


func try_punch() -> bool:
	if not logic.punch(config):
		return false

	punched.emit()
	Game.bump("punches", "total_punches", 1.0)

	if peds != null:
		var punch_r := config.punch_radius if config != null else 2.0
		var punch_a := config.punch_arc if config != null else 1.0472
		var hit_idx := peds.punch_at(global_position.x, global_position.z,
			logic.heading, punch_r, punch_a)

		if hit_idx >= 0:
			var retaliated := peds.react_to_punch(hit_idx, global_position.x, global_position.z)
			if retaliated:
				take_hit(peds.x[hit_idx], peds.z[hit_idx], 1)
			if camera != null:
				camera.shake(0.22, 0.25)

			var fine: int = config.punch_fine if config != null else 150
			var r_loss: float = float(config.punch_rating_loss if config != null else 5)

			Game.spend(fine)
			Game.add_rating(-r_loss)
			Bus.notify.emit(&"toast",
				"Нападение на прохожего! -%d ₽, рейтинг -%d" % [fine, int(r_loss)], {})

			# Полиция может добавить свой штраф и розыск, если патруль рядом.
			if police != null:
				police.check_punch_ped(global_position.x, global_position.z)

	return true
