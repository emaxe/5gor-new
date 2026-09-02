extends Node
## Dir — состояния игры, загрузка мира, слои интерфейса.
##
## Стек состояний заменяет поля _pauseFrom/_garageFrom/_settingsFrom/_mapFrom
## оригинала, где возврат «откуда пришёл» ветвился вручную в четырёх местах.
##
## Полноценные экраны приходят на этапе 9; пока Dir умеет главное — поднять
## мир и показать, что происходит, вместо серого экрана.

const WORLD_SCENE := "res://world/world.tscn"

var state: StringName = &"boot"
var world: World = null

var _stack: Array[StringName] = []
var _overlay: CanvasLayer
var _status: Label
var _root: Node


func _ready() -> void:
	_build_overlay()


func set_state(next: StringName) -> void:
	if next == state:
		return
	state = next
	Bus.game_state_changed.emit(next)


func push(screen: StringName) -> void:
	_stack.push_back(state)
	set_state(screen)


func pop() -> void:
	if _stack.is_empty():
		return
	set_state(_stack.pop_back())


func stack_depth() -> int:
	return _stack.size()


# --- Мир --------------------------------------------------------------------

## Поднимает мир под указанным узлом. Генерация пока блокирующая (~0.5 с),
## поэтому перед ней показывается плашка: серый экран без объяснений —
## худший вариант из возможных.
func load_world(parent: Node) -> World:
	_root = parent
	set_state(&"loading")
	show_status("Строим Пятигорск…")
	# Даём кадру отрисоваться, иначе плашка не успеет появиться.
	await get_tree().process_frame
	await get_tree().process_frame

	var packed: PackedScene = load(WORLD_SCENE)
	world = packed.instantiate() as World
	world.auto_build = false
	parent.add_child(world)
	# Ещё кадр на отрисовку плашки — генерация блокирующая.
	await get_tree().process_frame
	world.build()

	hide_status()
	set_state(&"driving")
	return world


func unload_world() -> void:
	if world != null:
		world.queue_free()
		world = null


# --- Оверлей ----------------------------------------------------------------

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "DirOverlay"
	_overlay.layer = 120
	add_child(_overlay)

	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = Color("#0d1117")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(bg)

	_status = Label.new()
	_status.name = "Status"
	_status.set_anchors_preset(Control.PRESET_FULL_RECT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color("#f2c12e"))
	_status.add_theme_font_size_override("font_size", 22)
	_overlay.add_child(_status)
	_overlay.visible = false


func show_status(text: String) -> void:
	if _status == null:
		return
	_status.text = text
	_overlay.visible = true


func hide_status() -> void:
	if _overlay != null:
		_overlay.visible = false
