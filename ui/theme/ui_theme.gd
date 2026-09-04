class_name UiTheme
extends RefCounted
## Цветовая палитра и генератор стилей для интерфейса 5GOR.

const COLOR_BG := Color("#0d1117")
const COLOR_BG_PANEL := Color(0.07, 0.09, 0.13, 0.90)
const COLOR_BG_PANEL_SOLID := Color("#161b22")
const COLOR_BORDER := Color(0.24, 0.28, 0.35, 0.60)

const COLOR_TEXT_PRIMARY := Color("#f0f3f6")
const COLOR_TEXT_MUTED := Color("#8b949e")

const COLOR_TAXI_YELLOW := Color("#f2c12e")
const COLOR_TAXI_HOVER := Color("#ffd75e")
const COLOR_TAXI_PRESSED := Color("#d4a318")

const COLOR_MONEY_GREEN := Color("#7ee787")
const COLOR_DANGER_RED := Color("#ff7b72")
const COLOR_INFO_BLUE := Color("#58a6ff")
const COLOR_PURPLE := Color("#bc8cff")


static func panel_style(radius: int = 8, border_color: Color = COLOR_BORDER,
		bg_color: Color = COLOR_BG_PANEL) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


static func button_primary_style(state: StringName = &"normal") -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	match state:
		&"hover":
			style.bg_color = COLOR_TAXI_HOVER
			style.border_color = Color.WHITE
		&"pressed":
			style.bg_color = COLOR_TAXI_PRESSED
			style.border_color = COLOR_TAXI_YELLOW
		_:
			style.bg_color = COLOR_TAXI_YELLOW
			style.border_color = COLOR_TAXI_HOVER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


static func button_secondary_style(state: StringName = &"normal") -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	match state:
		&"hover":
			style.bg_color = Color(0.20, 0.24, 0.32, 0.90)
			style.border_color = COLOR_TAXI_YELLOW
		&"pressed":
			style.bg_color = Color(0.10, 0.12, 0.16, 0.90)
			style.border_color = COLOR_BORDER
		_:
			style.bg_color = Color(0.14, 0.17, 0.22, 0.85)
			style.border_color = COLOR_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style
