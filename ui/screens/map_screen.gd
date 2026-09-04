class_name MapScreen
extends CanvasLayer
## Большая карта города (M) — north-up, в отличие от heading-up миникарты,
## вписана в границы всего города вместо радиуса вокруг игрока.

const UiTheme = preload("res://ui/theme/ui_theme.gd")

var _root: Control
var _canvas: Control
var _redraw_timer := 0.0


func _ready() -> void:
	layer = 105
	_build_ui()
	visible = false
	set_process(false)


func show_screen() -> void:
	visible = true
	set_process(true)
	_canvas.queue_redraw()


func hide_screen() -> void:
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	_redraw_timer += delta
	if _redraw_timer >= 0.05:
		_redraw_timer = 0.0
		_canvas.queue_redraw()


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.03, 0.05, 0.96)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	var hint := Label.new()
	hint.text = "🗺️ Карта города — [M] закрыть"
	hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top = 16
	hint.offset_bottom = 44
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UiTheme.COLOR_TAXI_YELLOW)
	hint.add_theme_font_size_override("font_size", 18)
	_root.add_child(hint)

	_canvas = Control.new()
	_canvas.name = "MapCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.offset_top = 60
	_canvas.offset_bottom = -20
	_canvas.offset_left = 40
	_canvas.offset_right = -40
	_canvas.draw.connect(_on_canvas_draw)
	_root.add_child(_canvas)


func _on_canvas_draw() -> void:
	var w: World = Dir.world
	if w == null or w.player == null or w.city == null:
		return

	var size := _canvas.size
	var center := size * 0.5
	var draw_r: float = minf(center.x, center.y) - 12.0
	if draw_r <= 10.0:
		return

	var b: BalanceData = Db.balance
	var half_span: float = (b.grid_n * b.cell) if b != null else 256.0
	var scale_factor: float = draw_r / (half_span + 60.0)
	var to_screen := func(wp: Vector2) -> Vector2:
		return center + wp * scale_factor

	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.08, 0.11, 0.9))

	var field: CityField = w.city.field
	if field != null and b != null:
		var grid_c: float = field.cell
		var num_roads: int = b.grid_n * 2 + 1
		var hs: float = (num_roads - 1) * 0.5 * grid_c
		var road_color := Color(0.30, 0.35, 0.45, 0.7)
		for i in num_roads:
			var c: float = -hs + i * grid_c
			_canvas.draw_line(to_screen.call(Vector2(c, -hs)), to_screen.call(Vector2(c, hs)), road_color, 2.0)
			_canvas.draw_line(to_screen.call(Vector2(-hs, c)), to_screen.call(Vector2(hs, c)), road_color, 2.0)

	if Db.districts != null:
		for lm: LandmarkData in Db.districts.landmarks:
			_canvas.draw_circle(to_screen.call(lm.position), 4.0, Color("#58a6ff"))

	if w.orders != null:
		for o: Order in w.orders.open_orders:
			var op: Vector2 = to_screen.call(o.pickup_pos)
			_canvas.draw_circle(op, 5.0, o.color)
			_canvas.draw_arc(op, 6.5, 0.0, TAU, 12, Color.WHITE, 1.2)

	if w.gps != null and w.gps.has_target():
		var gps: GpsRouter = w.gps
		var is_fuel: bool = gps.target_type == &"fuel"
		var route_color: Color = Color(0.18, 0.8, 0.25, 0.9) if is_fuel else Color(1.0, 0.84, 0.31, 0.9)
		var route: PackedVector2Array = gps.route
		for i in route.size() - 1:
			_canvas.draw_line(to_screen.call(route[i]), to_screen.call(route[i + 1]), route_color, 2.5)
		var target: Vector2 = gps.final_target()
		if target != Vector2.INF:
			var tc: Color = Color("#2ecc40") if is_fuel else Color("#ffd040")
			_canvas.draw_circle(to_screen.call(target), 7.0, tc)

	var p_pos := Vector2(w.player.global_position.x, w.player.global_position.z)
	var p_screen: Vector2 = to_screen.call(p_pos)
	_canvas.draw_circle(p_screen, 6.0, UiTheme.COLOR_TAXI_YELLOW)
	_canvas.draw_arc(p_screen, 8.0, 0.0, TAU, 16, Color.WHITE, 1.5)
