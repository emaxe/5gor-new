extends Camera3D
## Отладочная камера свободного полёта. Нужна, пока нет машины игрока:
## позволяет облететь город и проверить генерацию глазами.
##
## Управление: WASD — движение, Shift — ускорение, ПКМ + мышь — обзор,
## колесо — скорость, Q/E — вниз/вверх.

@export var speed := 24.0
@export var boost := 4.0
@export var sensitivity := 0.0032

var _yaw := 0.0
var _pitch := 0.0
var _looking := false


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking \
				else Input.MOUSE_MODE_VISIBLE
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed = minf(speed * 1.2, 400.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed = maxf(speed / 1.2, 2.0)
	elif event is InputEventMouseMotion and _looking:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * sensitivity
		_pitch = clampf(_pitch - mm.relative.y * sensitivity, -1.5, 1.5)
		rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir -= basis.z
	if Input.is_key_pressed(KEY_S):
		dir += basis.z
	if Input.is_key_pressed(KEY_A):
		dir -= basis.x
	if Input.is_key_pressed(KEY_D):
		dir += basis.x
	if Input.is_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		dir -= Vector3.UP
	if dir == Vector3.ZERO:
		return
	var v := speed * (boost if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	position += dir.normalized() * v * delta
