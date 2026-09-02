@tool
extends SceneTree
## Генератор InputMap. Запуск:
##   godot --headless --path . --script res://tools/setup_input_map.gd
##
## Действия описаны один раз здесь, а не руками в project.godot: так их можно
## пересоздать после правки и не разъехаться с кодом (Inp.ACTION_*).

const DEADZONE := 0.2
## Все устройства. Godot 4.7 ставит InputEventKey.device = 16 по умолчанию,
## но встроенные действия (ui_left и т.п.) используют -1 — иначе геймпад
## работал бы только под номером 0.
const ALL_DEVICES := -1

## action -> { keys: [Key], buttons: [JoyButton], axes: [[JoyAxis, dir]] }
const ACTIONS := {
	# --- Вождение ---
	"throttle": {"keys": [KEY_W, KEY_UP], "buttons": [JOY_BUTTON_A],
		"axes": [[JOY_AXIS_TRIGGER_RIGHT, 1]]},
	"brake": {"keys": [KEY_S, KEY_DOWN], "buttons": [JOY_BUTTON_B],
		"axes": [[JOY_AXIS_TRIGGER_LEFT, 1]]},
	"steer_left": {"keys": [KEY_A, KEY_LEFT], "buttons": [JOY_BUTTON_DPAD_LEFT],
		"axes": [[JOY_AXIS_LEFT_X, -1]]},
	"steer_right": {"keys": [KEY_D, KEY_RIGHT], "buttons": [JOY_BUTTON_DPAD_RIGHT],
		"axes": [[JOY_AXIS_LEFT_X, 1]]},
	"handbrake": {"keys": [KEY_SPACE], "buttons": [JOY_BUTTON_X], "axes": []},

	# --- Пеший режим ---
	"walk_forward": {"keys": [KEY_W, KEY_UP], "buttons": [],
		"axes": [[JOY_AXIS_LEFT_Y, -1]]},
	"walk_back": {"keys": [KEY_S, KEY_DOWN], "buttons": [],
		"axes": [[JOY_AXIS_LEFT_Y, 1]]},
	"walk_left": {"keys": [KEY_A, KEY_LEFT], "buttons": [],
		"axes": [[JOY_AXIS_LEFT_X, -1]]},
	"walk_right": {"keys": [KEY_D, KEY_RIGHT], "buttons": [],
		"axes": [[JOY_AXIS_LEFT_X, 1]]},
	"run": {"keys": [KEY_SHIFT], "buttons": [JOY_BUTTON_LEFT_STICK], "axes": []},
	"jump": {"keys": [KEY_SPACE], "buttons": [JOY_BUTTON_A], "axes": []},
	"punch": {"keys": [KEY_F], "buttons": [JOY_BUTTON_X], "axes": []},

	# --- Взаимодействие и интерфейс ---
	"interact": {"keys": [KEY_E], "buttons": [JOY_BUTTON_Y], "axes": []},
	"horn": {"keys": [KEY_H], "buttons": [JOY_BUTTON_RIGHT_SHOULDER], "axes": []},
	"lights": {"keys": [KEY_L], "buttons": [JOY_BUTTON_LEFT_SHOULDER], "axes": []},
	"radio": {"keys": [KEY_R], "buttons": [JOY_BUTTON_DPAD_UP], "axes": []},
	"map": {"keys": [KEY_M], "buttons": [JOY_BUTTON_DPAD_DOWN], "axes": []},
	"garage": {"keys": [KEY_G], "buttons": [], "axes": []},
	"pause": {"keys": [KEY_ESCAPE, KEY_P], "buttons": [JOY_BUTTON_START], "axes": []},

	# --- Камера ---
	"cam_zoom_in": {"keys": [], "buttons": [], "axes": []},
	"cam_zoom_out": {"keys": [], "buttons": [], "axes": []},
	"cam_left": {"keys": [], "buttons": [], "axes": [[JOY_AXIS_RIGHT_X, -1]]},
	"cam_right": {"keys": [], "buttons": [], "axes": [[JOY_AXIS_RIGHT_X, 1]]},
	"cam_up": {"keys": [], "buttons": [], "axes": [[JOY_AXIS_RIGHT_Y, -1]]},
	"cam_down": {"keys": [], "buttons": [], "axes": [[JOY_AXIS_RIGHT_Y, 1]]},
}

## Действия, которым дополнительно нужны колесо мыши.
const WHEEL := {"cam_zoom_in": MOUSE_BUTTON_WHEEL_UP, "cam_zoom_out": MOUSE_BUTTON_WHEEL_DOWN}


func _init() -> void:
	for action_name: String in ACTIONS:
		var spec: Dictionary = ACTIONS[action_name]
		var events: Array = []

		for k: int in spec["keys"]:
			var ev := InputEventKey.new()
			# physical_keycode, а не keycode: иначе AZERTY-раскладка ломает WASD.
			ev.physical_keycode = k
			ev.device = ALL_DEVICES
			events.append(ev)

		for b: int in spec["buttons"]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = b
			ev.device = ALL_DEVICES
			events.append(ev)

		for pair: Array in spec["axes"]:
			var ev := InputEventJoypadMotion.new()
			ev.axis = pair[0]
			ev.axis_value = float(pair[1])
			ev.device = ALL_DEVICES
			events.append(ev)

		if WHEEL.has(action_name):
			var ev := InputEventMouseButton.new()
			ev.button_index = WHEEL[action_name]
			ev.device = ALL_DEVICES
			events.append(ev)

		ProjectSettings.set_setting("input/" + action_name, {
			"deadzone": DEADZONE,
			"events": events,
		})

	var err := ProjectSettings.save()
	if err != OK:
		printerr("Не удалось сохранить project.godot: ", err)
		quit(1)
		return
	print("InputMap: записано действий — ", ACTIONS.size())
	quit(0)
