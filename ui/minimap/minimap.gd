class_name Minimap
extends Control
## Миникарта города (Heading-Up / ориентация по направлению движения).

## Минимальная толщина линии дороги, px. Полотно переулка (8 м) при радиусе
## 220 м в панели 180 px даёт 3 px, но миникарта живёт и в меньшей панели:
## тоньше этого линия распадается на пунктир сглаживания.
const MIN_ROAD_PX := 1.5

var world: Node3D
var radius_m: float = 220.0
var _update_timer: float = 0.0
## Проекция графа улиц: строится один раз на город (см. CityMapLines).
var _lines: CityMapLines = null


func _process(delta: float) -> void:
	_update_timer += delta
	# Троттлинг отрисовки до 25 FPS для экономии производительности
	if _update_timer >= 0.04:
		_update_timer = 0.0
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var r := minf(center.x, center.y) - 6.0
	if r <= 10.0:
		return

	# 1. Круглая подложка миникарты
	draw_circle(center, r, Color(0.06, 0.08, 0.11, 0.88))
	draw_arc(center, r * 0.35, 0.0, TAU, 24, Color(0.3, 0.35, 0.45, 0.25), 1.0)
	draw_arc(center, r * 0.70, 0.0, TAU, 28, Color(0.3, 0.35, 0.45, 0.25), 1.0)
	draw_arc(center, r, 0.0, TAU, 48, UiTheme.COLOR_TAXI_YELLOW, 2.0, true)

	if world == null or world.player == null or world.city == null:
		return

	var p_pos := Vector2(world.player.global_position.x, world.player.global_position.z)
	var p_heading: float = world.player.motion.heading if world.in_car else (
		world.player_ped.logic.heading if world.player_ped != null else 0.0
	)
	var scale_factor := r / radius_m
	var rot_ang := -p_heading - PI * 0.5
	var cos_a := cos(rot_ang)
	var sin_a := sin(rot_ang)

	# 2. Улицы — реальные полилинии рёбер графа в видимом радиусе.
	var city: CityBuilder = world.city
	if city.roads != null and city.roads.is_built():
		if _lines == null or _lines.roads != city.roads:
			_lines = CityMapLines.of(city.roads)
		for e in _lines.edge_count():
			if not _lines.touches(e, p_pos, radius_m):
				continue
			var pen: float = maxf(MIN_ROAD_PX, _lines.width[e] * scale_factor)
			var col: Color = _lines.color[e]
			var from: int = _lines.start[e]
			var to: int = _lines.start[e + 1]
			var prev_rel: Vector2 = _lines.points[from] - p_pos
			var prev := center + Vector2(prev_rel.x * cos_a - prev_rel.y * sin_a,
				prev_rel.x * sin_a + prev_rel.y * cos_a) * scale_factor
			for i in range(from + 1, to):
				var rel: Vector2 = _lines.points[i] - p_pos
				var cur := center + Vector2(rel.x * cos_a - rel.y * sin_a,
					rel.x * sin_a + rel.y * cos_a) * scale_factor
				_draw_clipped(prev, cur, center, r, col, pen)
				prev = cur

		# Кольцо — залитый круг по внешней кромке полотна. В мире это аннулюс
		# с приподнятым островком (`RoadMesh._ring_mesh`), но внешний диаметр
		# самого большого кольца города — 22 px на миникарте HUD: островка в
		# нём не разглядеть, а кольцевая ломаная из коротких звеньев толщиной
		# в ширину полотна вырождается в шестерёнку.
		#
		# `draw_circle` не обрезается краем циферблата, поэтому кольцо, не
		# помещающееся целиком, не рисуется вовсе: подходящие к нему улицы
		# всё равно обрезаются штатно, и место перекрёстка видно по ним.
		for k in _lines.ring_pos.size():
			var ring: Vector2 = _lines.ring_pos[k]
			var paved: float = _lines.ring_radius[k] + _lines.ring_width[k] * 0.5
			if p_pos.distance_to(ring) + paved > radius_m:
				continue
			var rel: Vector2 = ring - p_pos
			var rc := center + Vector2(rel.x * cos_a - rel.y * sin_a,
				rel.x * sin_a + rel.y * cos_a) * scale_factor
			draw_circle(rc, paved * scale_factor, CityMapLines.COLOR_ROAD)

	# 3. Достопримечательности (зеленые ромбы)
	if Db.districts != null:
		for lm: LandmarkData in Db.districts.landmarks:
			var rel: Vector2 = lm.position - p_pos
			var lp: Vector2 = center + Vector2(rel.x * cos_a - rel.y * sin_a, rel.x * sin_a + rel.y * cos_a) * scale_factor
			if lp.distance_squared_to(center) <= (r - 4.0) * (r - 4.0):
				draw_circle(lp, 4.0, Color("#58a6ff"))

	# 4. Открытые заказы (цветные кружки)
	if world.orders != null:
		for o: Order in world.orders.open_orders:
			var rel: Vector2 = o.pickup_pos - p_pos
			var op: Vector2 = center + Vector2(rel.x * cos_a - rel.y * sin_a, rel.x * sin_a + rel.y * cos_a) * scale_factor
			if op.distance_squared_to(center) <= (r - 4.0) * (r - 4.0):
				draw_circle(op, 6.0, o.color)
				draw_arc(op, 7.5, 0.0, TAU, 16, Color.WHITE, 1.5)

	# 5. GPS-маршрут (по дорогам, не «по прямой») и цель — заказ или заправка
	# при низком топливе, этап 13. Порт ui.js:547-574.
	if world.gps != null and world.gps.has_target():
		var gps: GpsRouter = world.gps
		var is_fuel: bool = gps.target_type == &"fuel"
		var route_color: Color = Color(0.18, 0.8, 0.25, 0.9) if is_fuel else Color(1.0, 0.84, 0.31, 0.9)
		var target_color: Color = Color("#2ecc40") if is_fuel else Color("#ffd040")
		var to_screen := func(wp: Vector2) -> Vector2:
			var rel: Vector2 = wp - p_pos
			return center + Vector2(rel.x * cos_a - rel.y * sin_a, rel.x * sin_a + rel.y * cos_a) * scale_factor

		var route: PackedVector2Array = gps.route
		for i in route.size() - 1:
			_draw_clipped(to_screen.call(route[i]), to_screen.call(route[i + 1]), center, r, route_color, 2.5)

		var target: Vector2 = gps.final_target()
		if target != Vector2.INF:
			var tp: Vector2 = to_screen.call(target)
			if tp.distance_squared_to(center) <= (r - 4.0) * (r - 4.0):
				draw_circle(tp, 8.0, target_color)
				draw_arc(tp, 10.5, 0.0, TAU, 16, Color.WHITE, 2.0)


	# 6. Игрок — золотая стрелка в центре карты
	var arrow_pts: PackedVector2Array = [
		center + Vector2(0.0, -8.0),
		center + Vector2(6.0, 7.0),
		center + Vector2(0.0, 4.0),
		center + Vector2(-6.0, 7.0),
	]
	draw_colored_polygon(arrow_pts, UiTheme.COLOR_TAXI_YELLOW)
	draw_polyline(arrow_pts, Color.WHITE, 1.2)

	# 7. Индикатор Севера (N)
	var n_rel := Vector2(0.0, -r + 14.0)
	var north_pos := center + Vector2(n_rel.x * cos_a - n_rel.y * sin_a, n_rel.x * sin_a + n_rel.y * cos_a)
	draw_circle(north_pos, 8.0, Color(0.85, 0.15, 0.15, 0.9))


func _draw_clipped(p1: Vector2, p2: Vector2, center: Vector2, r: float, col: Color, width: float) -> void:
	var d1_sq := p1.distance_squared_to(center)
	var d2_sq := p2.distance_squared_to(center)
	var r_sq := r * r
	if d1_sq > r_sq and d2_sq > r_sq:
		var seg := p2 - p1
		var seg_len_sq := seg.length_squared()
		if seg_len_sq > 0.001:
			var t := clampf((center - p1).dot(seg) / seg_len_sq, 0.0, 1.0)
			var closest := p1 + seg * t
			if closest.distance_squared_to(center) > r_sq:
				return
	var p1_c := p1
	var p2_c := p2
	if d1_sq > r_sq:
		p1_c = center + (p1 - center).normalized() * (r - 2.0)
	if d2_sq > r_sq:
		p2_c = center + (p2 - center).normalized() * (r - 2.0)
	draw_line(p1_c, p2_c, col, width)

