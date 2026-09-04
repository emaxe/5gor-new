extends Node
## Dir — состояния игры, загрузка мира, слои интерфейса.
##
## Стек состояний заменяет поля _pauseFrom/_garageFrom/_settingsFrom/_mapFrom
## оригинала, где возврат «откуда пришёл» ветвился вручную в четырёх местах.
##
## Экраны реестра регистрируются через register_screen() и показываются/
## прячутся автоматически при смене state (см. show_screen()/hide_screen()
## в ui/screens/*). push() в состояние без зарегистрированного экрана
## откатывается сам (экран ещё не построен — этапы 15+) и шлёт тост вместо
## тихого мёртвого нажатия кнопки.

const WORLD_SCENE := "res://world/world.tscn"

var state: StringName = &"boot"
var world: World = null
## Сид, с которым текущий Dir.world был построен. Нужен в main.gd, чтобы
## понять, надо ли перестраивать мир при «Продолжить» слота N>0: если
## Game.world_seed (из сейва) отличается от current_world_seed, город чужой
## и нужен unload + reload.
var current_world_seed: int = -1

var _stack: Array[StringName] = []
var _screens: Dictionary = {}  # StringName -> Node (show_screen()/hide_screen())
var _overlay: CanvasLayer
var _status: Label
var _root: Node


func _ready() -> void:
	_build_overlay()


## Регистрирует экран под именем состояния — Dir сам вызовет show_screen()/
## hide_screen() (если они есть) при входе/выходе из этого состояния.
func register_screen(for_state: StringName, screen: Node) -> void:
	_screens[for_state] = screen


func set_state(next: StringName) -> void:
	if next == state:
		return
	_set_screen_visible(state, false)
	state = next
	_set_screen_visible(next, true)
	Bus.game_state_changed.emit(next)


## true, если удалось перейти. false — экран этого состояния ещё не
## построен (см. таблицу этапов), стек и state не меняются. Bus.notify
## бьёт toast'ом на случай, если сейчас виден HUD (например, пауза во время
## езды); вызывающая сторона (сейчас видимый экран) может дополнительно
## показать собственное уведомление, если HUD скрыт — как MainMenu.
func push(screen: StringName) -> bool:
	if not _screens.has(screen):
		Bus.notify.emit(&"toast", "Скоро", {"color": Color("#8b949e")})
		return false
	_stack.push_back(state)
	set_state(screen)
	return true


func pop() -> void:
	if _stack.is_empty():
		return
	set_state(_stack.pop_back())


func _set_screen_visible(for_state: StringName, shown: bool) -> void:
	var screen: Node = _screens.get(for_state)
	if screen == null:
		return
	if shown and screen.has_method(&"show_screen"):
		screen.show_screen()
	elif not shown and screen.has_method(&"hide_screen"):
		screen.hide_screen()


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
	current_world_seed = Game.world_seed
	set_state(&"driving")
	return world


func unload_world() -> void:
	if world != null:
		world.queue_free()
		world = null
		current_world_seed = -1


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
