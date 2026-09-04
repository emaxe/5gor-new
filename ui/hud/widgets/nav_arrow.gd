class_name NavArrowIcon
extends Control
## Стрелка GPS-навигатора: векторный треугольник вместо эмодзи "➤"
## (style.css:128). Нейтральная поза — остриё вправо, `rotation = 0`;
## вызывающий код крутит через `.rotation` (см. GpsRouter.arrow_angle()).

var arrow_color: Color = Color("#58a6ff"):
	set(v):
		arrow_color = v
		queue_redraw()


func _ready() -> void:
	pivot_offset = size * 0.5
	resized.connect(func() -> void: pivot_offset = size * 0.5)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(c.x, c.y) - 4.0
	if r <= 0.0:
		return
	var pts := PackedVector2Array([
		c + Vector2(r, 0.0),
		c + Vector2(-r * 0.6, -r * 0.7),
		c + Vector2(-r * 0.3, 0.0),
		c + Vector2(-r * 0.6, r * 0.7),
	])
	draw_colored_polygon(pts, arrow_color)
