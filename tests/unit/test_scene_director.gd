extends GdUnitTestSuite
## Тесты навигации экранов Dir: регистрация, показ/скрытие по смене
## состояния, откат при push() в незарегистрированное состояние.

const SceneDirectorScript = preload("res://autoload/scene_director.gd")


class FakeScreen:
	extends Node
	var shown := 0
	var hidden := 0

	func show_screen() -> void:
		shown += 1

	func hide_screen() -> void:
		hidden += 1


func test_set_state_shows_and_hides_registered_screens() -> void:
	var dir: Node = SceneDirectorScript.new()
	var menu := FakeScreen.new()
	dir.register_screen(&"menu", menu)

	dir.set_state(&"menu")
	assert_that(menu.shown).is_equal(1)
	assert_that(menu.hidden).is_equal(0)

	dir.set_state(&"driving")
	assert_that(menu.shown).is_equal(1)
	assert_that(menu.hidden).is_equal(1)

	menu.queue_free()
	dir.queue_free()


func test_push_and_pop_toggle_registered_screen_and_restore_state() -> void:
	var dir: Node = SceneDirectorScript.new()
	var pause := FakeScreen.new()
	dir.state = &"driving"
	dir.register_screen(&"pause", pause)

	assert_that(dir.push(&"pause")).is_true()
	assert_that(dir.state).is_equal(&"pause")
	assert_that(pause.shown).is_equal(1)

	dir.pop()
	assert_that(dir.state).is_equal(&"driving")
	assert_that(pause.hidden).is_equal(1)

	pause.queue_free()
	dir.queue_free()


func test_push_unregistered_state_bounces_back_without_growing_stack() -> void:
	var dir: Node = SceneDirectorScript.new()
	dir.state = &"driving"

	assert_that(dir.push(&"garage")).is_false()

	assert_that(dir.state).is_equal(&"driving")
	assert_that(dir.stack_depth()).is_equal(0)

	dir.queue_free()


func test_push_unregistered_state_notifies_via_bus_as_toast() -> void:
	var dir: Node = SceneDirectorScript.new()
	dir.state = &"driving"

	var seen_kind: Array[StringName] = []
	var handler := func(kind: StringName, _text: String, _data: Dictionary) -> void:
		seen_kind.append(kind)
	Bus.notify.connect(handler)

	dir.push(&"settings")

	Bus.notify.disconnect(handler)
	assert_that(seen_kind).is_equal([&"toast"])
	dir.queue_free()
