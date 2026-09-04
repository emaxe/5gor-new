class_name HudStyle
extends RefCounted
## Раскладка и приоритеты сообщений HUD. Отделено от UiTheme (палитра всего
## интерфейса, включая меню и экраны) — здесь только то, что специфично для
## игрового HUD: уровни тостов и компактные фабрики стилей угловых плашек.

## Уровень сообщения — StringName, а не enum: в статических методах enum
## конфликтует с Класс.Enum снаружи (см. .agents/rules/gdscript-style.md),
## а порядок вытеснения задаёт отдельный level_rank().
const LEVEL_REWARD := &"reward"
const LEVEL_INFO := &"info"
const LEVEL_CRITICAL := &"critical"

const COLOR_REWARD := Color("#70d6ff")
const COLOR_INFO := Color("#f2c12e")
const COLOR_CRITICAL := Color("#ff7b72")


## Порядок вытеснения тостов: чем больше ранг, тем важнее сообщение и тем
## неохотнее оно уступает место в очереди (см. ToastQueue.push()).
static func level_rank(id: StringName) -> int:
	match id:
		LEVEL_REWARD: return 0
		LEVEL_CRITICAL: return 2
		_: return 1  # LEVEL_INFO и любое незнакомое значение


static func level_color(id: StringName) -> Color:
	match id:
		LEVEL_REWARD: return COLOR_REWARD
		LEVEL_CRITICAL: return COLOR_CRITICAL
		_: return COLOR_INFO


## Время показа тоста, секунды. Мелкие награды (сближение, занос) мелькают
## быстро и не должны копиться на экране; критические (провал, ДТП, штраф)
## держатся дольше — их обычно читают в процессе торможения.
static func level_duration(id: StringName) -> float:
	match id:
		LEVEL_REWARD: return 1.8
		LEVEL_CRITICAL: return 4.5
		_: return 3.2


static func level_font_size(id: StringName) -> int:
	match id:
		LEVEL_REWARD: return 12
		LEVEL_CRITICAL: return 14
		_: return 13


## Стиль плашки тоста: тёмная полупрозрачная подложка, тонкая рамка и левый
## акцент цвета уровня — цвет сообщения теперь несёт рамка, а не текст
## (порт style.css:365-368, border красит именно её).
static func toast_style(id: StringName) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.055, 0.08, 0.72)
	style.border_color = level_color(id)
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


## Компактная угловая плашка (деньги/рейтинг, время/погода) — прозрачнее и
## с меньшими отступами, чем UiTheme.panel_style(), рассчитанный на модальные
## экраны с непрозрачным фоном.
static func pod_style(radius: int = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.055, 0.08, 0.62)
	style.border_color = Color(1.0, 1.0, 1.0, 0.10)
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style
