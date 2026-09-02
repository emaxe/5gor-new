extends Node
## Inp — единственный слой ввода. Геймплейный код нигде не читает
## Input.is_key_pressed() и не знает про тач: клавиатура, геймпад и виртуальный
## джойстик сходятся в одни и те же action'ы InputMap.
##
## Тач инжектится через Input.action_press(action, strength) из ui/touch —
## поэтому тач это ещё один источник силы действия, а не параллельный путь.

## Оси управления машиной. Переиспользуемый объект: без аллокаций в hot path.
class DriveAxes extends RefCounted:
	var steer := 0.0
	var throttle := 0.0
	var brake := 0.0
	var handbrake := false


## Оси пешего режима.
class WalkAxes extends RefCounted:
	var forward := 0.0
	var right := 0.0
	var running := false


const ACTION_STEER_L := &"steer_left"
const ACTION_STEER_R := &"steer_right"
const ACTION_THROTTLE := &"throttle"
const ACTION_BRAKE := &"brake"
const ACTION_HANDBRAKE := &"handbrake"
const ACTION_WALK_F := &"walk_forward"
const ACTION_WALK_B := &"walk_back"
const ACTION_WALK_L := &"walk_left"
const ACTION_WALK_R := &"walk_right"
const ACTION_RUN := &"run"

## Множитель руля для тач-джойстика (порт game.js: тач-руль ×0.85).
const TOUCH_STEER_MULT := 0.85

var touch_active := false

var _drive := DriveAxes.new()
var _walk := WalkAxes.new()


func drive_axes() -> DriveAxes:
	var a := _drive
	a.steer = Input.get_axis(ACTION_STEER_L, ACTION_STEER_R)
	if touch_active:
		a.steer *= TOUCH_STEER_MULT
	a.throttle = Input.get_action_strength(ACTION_THROTTLE)
	a.brake = Input.get_action_strength(ACTION_BRAKE)
	a.handbrake = Input.is_action_pressed(ACTION_HANDBRAKE)
	return a


func walk_axes() -> WalkAxes:
	var a := _walk
	a.forward = Input.get_axis(ACTION_WALK_B, ACTION_WALK_F)
	a.right = Input.get_axis(ACTION_WALK_L, ACTION_WALK_R)
	a.running = Input.is_action_pressed(ACTION_RUN)
	return a


func _ready() -> void:
	touch_active = DisplayServer.is_touchscreen_available()
