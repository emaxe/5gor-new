class_name ChaseCamera
extends Camera3D
## Догоняющая камера. Порт ChaseCamera (camera.js) со сферическими
## координатами вокруг цели.
##
## Сглаживание задано как `lerp(desired, 1 - k^dt)` — эта форма кадронезависима
## и переносится из оригинала дословно.

enum Mode { CAR, PED }

## Дистанция и высота фокуса по режимам (camera.js:29-38).
const CAR_DIST := 9.5
const CAR_DIST_TOUCH := 11.0
const CAR_FOCUS_Y := 0.8
const CAR_BASE_Y := 1.2
const CAR_ZOOM := Vector2(5.0, 16.0)

const PED_DIST := 3.6
const PED_DIST_TOUCH := 4.2
const PED_FOCUS_Y := 1.35
const PED_BASE_Y := 0.6
const PED_ZOOM := Vector2(2.0, 8.0)

const PITCH_LIMITS := Vector2(0.12, 1.1)
const PITCH_START := 0.38
const PITCH_START_TOUCH := 0.52
## Сколько секунд камера остаётся там, куда её повернули вручную.
const AUTO_RETURN := 3.0
## Скорость доводки за корму после паузы, рад/с.
const RETURN_RATE := 0.4
## Коэффициенты экспоненциального сглаживания (camera.js:94-96).
const POS_DAMP := 0.001
const LOOK_DAMP := 0.002

## Чувствительность мыши и колеса (input.js:83-100).
const MOUSE_SENS := 0.005
const ZOOM_STEP := 0.7

var mode: Mode = Mode.CAR
var target: Node3D
## Курс цели, вокруг которого камера центруется.
var target_heading := 0.0
## Высота земли под целью.
var target_ground := 0.0

var yaw := 0.0
var pitch := PITCH_START
var distance := CAR_DIST
var is_cinematic_panorama: bool = false
var _panorama_angle: float = 0.0

var _target_yaw := 0.0
var _target_dist := CAR_DIST
var _focus_height := CAR_FOCUS_Y
var _auto_return := 0.0
var _look_point := Vector3.ZERO
var _shake_time := 0.0
var _shake_amp := 0.0
var _dragging := false
var _touch := false


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_touch = DisplayServer.is_touchscreen_available()
	pitch = PITCH_START_TOUCH if _touch else PITCH_START
	set_mode(Mode.CAR)


func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	if mode == Mode.PED:
		_target_dist = PED_DIST_TOUCH if _touch else PED_DIST
		_focus_height = PED_FOCUS_Y
	else:
		_target_dist = CAR_DIST_TOUCH if _touch else CAR_DIST
		_focus_height = CAR_FOCUS_Y
	distance = _target_dist


## Мгновенно ставит камеру за цель — при спавне и смене режима.
func snap_to_target() -> void:
	if target == null:
		return
	yaw = target_heading
	_target_yaw = target_heading
	var tf := target.get_global_transform_interpolated() if target.is_inside_tree() else target.global_transform
	var p := tf.origin
	position = _desired_position(p)
	_look_point = p + Vector3(0.0, _focus_height, 0.0)
	look_at(_look_point, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-ZOOM_STEP)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(ZOOM_STEP)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * MOUSE_SENS
		pitch = clampf(pitch + mm.relative.y * MOUSE_SENS,
			PITCH_LIMITS.x, PITCH_LIMITS.y)
		_auto_return = AUTO_RETURN


func _zoom(delta_dist: float) -> void:
	var limits := PED_ZOOM if mode == Mode.PED else CAR_ZOOM
	distance = clampf(distance + delta_dist, limits.x, limits.y)
	_target_dist = distance
	_auto_return = AUTO_RETURN


func _process(delta: float) -> void:
	if is_cinematic_panorama:
		_panorama_angle += delta * 0.12
		var r := 110.0
		position = Vector3(sin(_panorama_angle) * r, 42.0, cos(_panorama_angle) * r)
		look_at(Vector3(0.0, 10.0, 0.0), Vector3.UP)
		return
	if target == null:
		return
	# Правый стик геймпада вращает камеру теми же действиями, что и мышь.
	var stick := Vector2(
		Input.get_axis(&"cam_left", &"cam_right"),
		Input.get_axis(&"cam_up", &"cam_down"))
	if stick.length_squared() > 0.01:
		yaw -= stick.x * 2.4 * delta
		pitch = clampf(pitch + stick.y * 1.6 * delta,
			PITCH_LIMITS.x, PITCH_LIMITS.y)
		_auto_return = AUTO_RETURN

	if _auto_return > 0.0:
		_auto_return -= delta
	else:
		_target_yaw = target_heading
		var diff := Heading.delta(yaw, _target_yaw)
		# Плавная доводка курса без пороговых рывков отсечки
		var turn_speed := clampf(diff * 4.0, -RETURN_RATE * TAU, RETURN_RATE * TAU)
		yaw += turn_speed * delta

	distance = MathUtils.damp(distance, _target_dist, 0.2, delta)

	# Интерполированный трансформ цели даёт плавный ход без дёрганий на любой частоте кадров.
	var tf := target.get_global_transform_interpolated() if target.is_inside_tree() else target.global_transform
	var p := tf.origin
	var desired := _desired_position(p)
	position = MathUtils.damp_pow_vec(position, desired, POS_DAMP, delta)
	_look_point = MathUtils.damp_pow_vec(_look_point,
		p + Vector3(0.0, _focus_height, 0.0), LOOK_DAMP, delta)
	look_at(_look_point, Vector3.UP)
	_apply_shake(delta)
	Audio.set_camera_state(distance, mode == Mode.PED)


func _desired_position(p: Vector3) -> Vector3:
	var base := (PED_BASE_Y if mode == Mode.PED else CAR_BASE_Y)
	return Vector3(
		p.x - sin(yaw) * cos(pitch) * distance,
		p.y + base + sin(pitch) * distance,
		p.z - cos(yaw) * cos(pitch) * distance)



## Тряска — постобработка позиции, как в оригинале (game.js:1418).
func shake(duration: float, amplitude: float) -> void:
	_shake_time = maxf(_shake_time, duration)
	_shake_amp = maxf(_shake_amp, amplitude)


func _apply_shake(delta: float) -> void:
	if _shake_time <= 0.0:
		return
	_shake_time -= delta
	var k := _shake_time * _shake_amp
	position += Vector3(
		randf() - 0.5, randf() - 0.5, randf() - 0.5) * k
	if _shake_time <= 0.0:
		_shake_amp = 0.0
