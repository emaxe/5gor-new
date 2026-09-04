extends Node
## Живой полигон звуковой системы (этап 17). Headless gdUnit4 проверяет
## корректность синтеза (детерминизм, отсутствие клиппинга, бюджеты голосов),
## но НЕ то, что это звучит хорошо — для этого нужен живой Vulkan/аудио-девайс.
## Запускать НЕ headless.
##
## Поднимает настоящий мир, настоящую машину и настоящую радиостанцию —
## обычное управление (WASD/стрелки, Space — ручник, H — гудок, R — радио,
## колесо мыши — зум камеры). Двигатель/шины/ветер/тормоза/дребезг слышны
## сразу при езде.
##
## Цифровые клавиши 1-9 проигрывают отдельные SFX напрямую — так их не нужно
## провоцировать по-настоящему (авария, авария полиции, достижение и т.д.).

const QUICK_SFX := {
	KEY_1: &"crash_heavy", KEY_2: &"achievement_fanfare", KEY_3: &"cash_large",
	KEY_4: &"near_miss_streak_3", KEY_5: &"police_escape_3", KEY_6: &"siren_ambulance",
	KEY_7: &"thunder", KEY_8: &"pickup", KEY_9: &"fail",
}

var _hint: Label


func _ready() -> void:
	await Dir.load_world(self)
	Game.start_shift(1)
	_build_hint()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if QUICK_SFX.has(key):
			Audio.play_sfx(QUICK_SFX[key])


func _build_hint() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_hint = Label.new()
	_hint.position = Vector2(16.0, 16.0)
	_hint.text = "Звук: WASD/стрелки — езда, Space — ручник, H — гудок, R — радио\n" + \
		"1 авария  2 достижение  3 деньги  4 серия near-miss  5 погоня\n" + \
		"6 сирена  7 гром  8 посадка  9 провал заказа"
	layer.add_child(_hint)
