class_name PlayerPedLogic
extends RefCounted
## Чистая логика пешего режима игрока. Порт PlayerPed (playerped.js:8-254)
## и механик выхода/посадки/ударов (game.js:910-1000).
##
## Не зависит от узлов SceneTree, поэтому на 100% покрывается headless-тестами:
## скорости, прыжок, гравитация, урон, нокаут, кулдауны и геометрия выхода из авто.

var x: float = 0.0
var z: float = 0.0
var ground_y: float = 0.0
var heading: float = 0.0
var speed: float = 0.0
var walk_phase: float = 0.0
var is_running: bool = false

var vy: float = 0.0
var y_off: float = 0.0
var jump_cd: float = 0.0

var punch_cd: float = 0.0
var punch_anim_t: float = 0.0
var hit_cd: float = 0.0

var max_hp: int = 3
var hp: int = 3
var stun_t: float = 0.0
var knock_vx: float = 0.0
var knock_vz: float = 0.0
var knock_t: float = 0.0
var is_knocked_out: bool = false


func init_with_config(config: PedConfig) -> void:
	max_hp = config.player_max_hp if config != null else 3
	hp = max_hp


func set_pos(new_x: float, new_z: float, new_heading: float = 0.0) -> void:
	x = new_x
	z = new_z
	heading = new_heading
	speed = 0.0
	walk_phase = 0.0
	punch_cd = 0.0
	punch_anim_t = 0.0
	hp = max_hp
	stun_t = 0.0
	knock_vx = 0.0
	knock_vz = 0.0
	knock_t = 0.0
	is_knocked_out = false
	vy = 0.0
	y_off = 0.0
	jump_cd = 0.0
	hit_cd = 0.0


# --- Прыжок и удар -----------------------------------------------------------

func jump(config: PedConfig) -> bool:
	if stun_t > 0.0 or knock_t > 0.0 or jump_cd > 0.0:
		return false
	if vy > 0.0 or y_off > 0.0:
		return false
	var j_speed := config.jump_speed if config != null else 6.5
	var cd := config.jump_cooldown if config != null else 0.25
	vy = j_speed
	jump_cd = cd
	return true


func punch(config: PedConfig) -> bool:
	if stun_t > 0.0 or punch_cd > 0.0:
		return false
	var cd := config.punch_cooldown if config != null else 0.8
	punch_cd = cd
	punch_anim_t = 0.3
	return true


# --- Получение урона и нокаут ------------------------------------------------

func take_hit(from_x: float, from_z: float, damage: int = 1,
		config: PedConfig = null) -> bool:
	hp = maxi(0, hp - damage)
	var dx := x - from_x
	var dz := z - from_z
	var dist := sqrt(dx * dx + dz * dz)
	if dist < 0.0001:
		dist = 1.0
		dx = 0.0
		dz = 1.0
	var dir_x := dx / dist
	var dir_z := dz / dist

	var down_dur := config.player_down_duration if config != null else 2.0
	var stun_dur := config.player_stun_duration if config != null else 0.6

	if hp <= 0:
		stun_t = down_dur
		is_knocked_out = true
		knock_vx = dir_x * 5.5
		knock_vz = dir_z * 5.5
		knock_t = 0.4
	else:
		stun_t = stun_dur
		is_knocked_out = false
		knock_vx = dir_x * 4.0
		knock_vz = dir_z * 4.0
		knock_t = 0.25

	speed = 0.0
	return hp <= 0


func apply_knockback(vx: float, vz: float, duration: float = 0.25) -> void:
	knock_vx = vx
	knock_vz = vz
	knock_t = duration
	speed = 0.0


# --- Интеграция таймеров и перемещения ---------------------------------------

func advance_timers(delta: float) -> void:
	if punch_cd > 0.0:
		punch_cd = maxf(0.0, punch_cd - delta)
	if punch_anim_t > 0.0:
		punch_anim_t = maxf(0.0, punch_anim_t - delta)
	if hit_cd > 0.0:
		hit_cd = maxf(0.0, hit_cd - delta)
	if jump_cd > 0.0:
		jump_cd = maxf(0.0, jump_cd - delta)

	if stun_t > 0.0:
		stun_t = maxf(0.0, stun_t - delta)
		if stun_t <= 0.0 and is_knocked_out:
			is_knocked_out = false
			hp = max_hp


## Проецирует ввод осей (forward, right) относительно курсового угла камеры.
static func compute_move_vector(input_forward: float, input_right: float,
		cam_yaw: float) -> Vector3:
	var fwd_vec := Vector3(sin(cam_yaw), 0.0, cos(cam_yaw))
	var right_vec := Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
	var move := right_vec * input_right + fwd_vec * input_forward
	var len := move.length()
	if len > 1.0:
		move /= len
	return move


## Обновляет положение, скорость, фазу шага и отбрасывание.
func step_motion(move_dir: Vector3, is_shift: bool, config: PedConfig,
		delta: float) -> void:
	if knock_t > 0.0:
		knock_t = maxf(0.0, knock_t - delta)
		x += knock_vx * delta
		z += knock_vz * delta
		knock_vx *= maxf(0.0, 1.0 - delta * 6.0)
		knock_vz *= maxf(0.0, 1.0 - delta * 6.0)
		speed = 0.0
		is_running = false
		return

	if stun_t > 0.0:
		speed = 0.0
		is_running = false
		return

	var len := move_dir.length()
	var has_move := len > 0.001
	is_running = is_shift and has_move

	var walk_sp := config.walk_speed if config != null else 3.1
	var run_sp := config.run_speed if config != null else 5.8
	var max_sp := run_sp if is_running else walk_sp

	if has_move:
		speed = max_sp * minf(1.0, len)
		var step_vec := move_dir.normalized() * (speed * delta)
		x += step_vec.x
		z += step_vec.z

		var target_h := Heading.from_vector(move_dir)
		var rate := config.turn_rate if config != null else 14.0
		heading = Heading.turn_toward(heading, target_h, delta * rate)
		walk_phase += delta * speed * (3.6 if is_running else 3.0)
	else:
		speed = 0.0


func step_vertical(config: PedConfig, delta: float) -> void:
	if vy > 0.0 or y_off > 0.0:
		var g := config.gravity if config != null else 20.0
		vy -= g * delta
		y_off += vy * delta
		if y_off <= 0.0:
			y_off = 0.0
			vy = 0.0


# --- Границы города ----------------------------------------------------------

## Клампит координаты в границы города (±308 м) + серпантин Машука [-470, -300].
static func clamp_bounds(pos_x: float, pos_z: float) -> Vector2:
	var nx := clampf(pos_x, -308.0, 308.0)
	var nz := clampf(pos_z, -308.0, 308.0)
	if pos_z < -300.0 and absf(pos_x) <= 85.0:
		nx = pos_x
		nz = clampf(pos_z, -470.0, -300.0)
	return Vector2(nx, nz)


# --- Посадка и выход из машины -----------------------------------------------

static func can_exit_car(car_speed: float, config: PedConfig) -> bool:
	var max_s := config.car_exit_max_speed if config != null else 1.5
	return absf(car_speed) <= max_s


static func get_exit_offsets(car_pos: Vector3, car_heading: float) -> Array[Vector3]:
	# Водитель выходит из левой двери (local -X).
	var left_dir := Heading.basis_of(car_heading) * Vector3(-1.0, 0.0, 0.0)
	var offsets: Array[float] = [1.5, 2.0, 2.5, 3.0]
	var res: Array[Vector3] = []
	for off in offsets:
		res.append(car_pos + left_dir * off)
	return res


static func can_enter_car(ped_pos: Vector3, car_pos: Vector3,
		config: PedConfig) -> bool:
	var enter_dist := config.car_enter_dist if config != null else 3.0
	var dx := ped_pos.x - car_pos.x
	var dz := ped_pos.z - car_pos.z
	return sqrt(dx * dx + dz * dz) <= enter_dist


# --- Попадание удара кулаком -------------------------------------------------

## Проверяет сектор удара (конус ±punch_arc, радиус punch_radius).
static func is_target_in_punch_cone(attacker_pos: Vector3, attacker_heading: float,
		target_pos: Vector3, punch_radius: float, punch_arc: float) -> bool:
	var dx := target_pos.x - attacker_pos.x
	var dz := target_pos.z - attacker_pos.z
	var d_sq := dx * dx + dz * dz
	if d_sq > punch_radius * punch_radius or d_sq < 0.0001:
		return false
	var dist := sqrt(d_sq)
	var fwd := Heading.forward(attacker_heading)
	var dot := (dx * fwd.x + dz * fwd.z) / dist
	return dot >= cos(punch_arc)
