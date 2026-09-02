class_name CityMesher
extends RefCounted
## Фаза B генерации: из CityPlan получаются меши.
##
## Только математика над массивами — ни одного обращения к RenderingServer,
## поэтому фаза выносится в фоновый поток.
##
## Город режется на чанки 128 м: так работает frustum culling и в кадре
## оказываются 15-25 мешей вместо 250 отдельных зданий. Дороги и разметка
## лежат отдельными мешами — их геометрия тривиальна (несколько квадов).

const CHUNK := 128.0
## Уровни поверхностей. Расхождение по Y убирает z-fighting.
const Y_GROUND := -0.02
const Y_ROAD := 0.05
const Y_MARKING := 0.07
const Y_SIDEWALK := 0.15
const Y_CURB_TOP := 0.16

const COLOR_GRASS := Color("#86a173")
const COLOR_ROAD := Color("#3a3f46")
const COLOR_SIDEWALK := Color("#a8a89e")
const COLOR_CURB := Color("#bcbcb4")
const COLOR_WINDOW_DARK := Color("#39434f")

## Размер общей плоскости земли (в оригинале 1700x1700).
const GROUND_SIZE := 1700.0
## Шаг сетки рельефа Машука.
## Шаг сетки рельефа. 3 м давали 16k квадов и 0.6 с только на гору;
## 4 м визуально неотличимы на low-poly и вдвое дешевле.
const TERRAIN_STEP := 4.0

var field: CityField
var plan: CityPlan


func _init(city_field: CityField, city_plan: CityPlan) -> void:
	field = city_field
	plan = city_plan


## Земля, полотно дорог и тротуары одним мешем — крупная плоская геометрия,
## которая всё равно почти всегда в кадре.
func build_ground() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.plane_xz(Vector3(0.0, Y_GROUND, 0.0),
		Vector2(GROUND_SIZE, GROUND_SIZE), COLOR_GRASS)

	var half := field.road_half
	var walk := field.sidewalk
	var span := 256.0 + field.grid_ext
	for c in field.road_axes:
		# Полотно.
		b.plane_xz(Vector3(c, Y_ROAD, 0.0), Vector2(half * 2.0, span * 2.0), COLOR_ROAD)
		b.plane_xz(Vector3(0.0, Y_ROAD, c), Vector2(span * 2.0, half * 2.0), COLOR_ROAD)
		# Тротуары по обе стороны.
		for s: float in [-1.0, 1.0]:
			var off := s * (half + walk * 0.5)
			b.plane_xz(Vector3(c + off, Y_SIDEWALK, 0.0),
				Vector2(walk, span * 2.0), COLOR_SIDEWALK)
			b.plane_xz(Vector3(0.0, Y_SIDEWALK, c + off),
				Vector2(span * 2.0, walk), COLOR_SIDEWALK)
			# Бордюр — тонкий брусок по краю проезжей части.
			var curb := s * (half + 0.25)
			b.box(Vector3(c + curb, Y_CURB_TOP * 0.5, 0.0),
				Vector3(0.5, Y_CURB_TOP, span * 2.0), COLOR_CURB)
			b.box(Vector3(0.0, Y_CURB_TOP * 0.5, c + curb),
				Vector3(span * 2.0, Y_CURB_TOP, 0.5), COLOR_CURB)
	return b.commit()


## Здания, сгруппированные в чанки 128 м. Ключ — координата чанка.
func build_building_chunks() -> Dictionary[Vector2i, ArrayMesh]:
	var builders: Dictionary[Vector2i, MeshBuilder] = {}
	for i in plan.building_count():
		var r := plan.building_rect[i]
		var center := Vector2((r.x + r.z) * 0.5, (r.y + r.w) * 0.5)
		var key := Vector2i(floori(center.x / CHUNK), floori(center.y / CHUNK))
		if not builders.has(key):
			builders[key] = MeshBuilder.new()
		_add_building(builders[key], i)

	var out: Dictionary[Vector2i, ArrayMesh] = {}
	for key: Vector2i in builders:
		var mesh := builders[key].commit()
		if mesh != null:
			out[key] = mesh
	return out


func _add_building(b: MeshBuilder, i: int) -> void:
	var r := plan.building_rect[i]
	var h := plan.building_height[i]
	var facade := plan.building_facade[i]
	var roof := plan.building_roof[i]
	var w := r.z - r.x
	var dep := r.w - r.y
	var cx := (r.x + r.z) * 0.5
	var cz := (r.y + r.w) * 0.5

	# Коробка без нижней грани не нужна: низ всё равно под землёй, а лишние
	# 2 треугольника на 260 зданий дешевле, чем отдельный путь построения.
	b.box(Vector3(cx, Y_SIDEWALK + h * 0.5, cz), Vector3(w, h, dep), facade)
	b.plane_xz(Vector3(cx, Y_SIDEWALK + h + 0.01, cz), Vector2(w, dep), roof)
	if plan.building_roof_kind[i] == 1:
		# Четырёхскатная кровля. Высота ската — доля от МЕНЬШЕЙ стороны дома,
		# а не от его высоты: иначе на многоэтажке вырастал колпак в полдома.
		var pitch: float = clampf(minf(w, dep) * 0.22, 1.2, 3.4)
		b.cone(Vector3(cx, Y_SIDEWALK + h + pitch * 0.5, cz),
			minf(w, dep) * 0.72, pitch, roof, 4)
	_add_windows(b, i)


## Окна — сетка тёмных панелей на фасадах. Ночью зажигаются отдельным
## эмиссивным мешем (build_window_chunks), поэтому здесь только «дырки».
func _add_windows(b: MeshBuilder, i: int) -> void:
	var r := plan.building_rect[i]
	var h := plan.building_height[i]
	var w := r.z - r.x
	var dep := r.w - r.y
	var cols: int = clampi(roundi(w / 4.2), 2, 9)
	var rows: int = clampi(roundi(h / 3.2), 2, 12)
	if rows < 2:
		return
	var pane := Vector2(minf(1.4, w / cols * 0.5), 1.3)
	for row in rows:
		var y := Y_SIDEWALK + (row + 0.6) * (h / rows)
		if y > Y_SIDEWALK + h - 0.8:
			continue
		for col in cols:
			var fx := r.x + (col + 0.5) * (w / cols)
			var fz := r.y + (col + 0.5) * (dep / cols)
			# Северный и южный фасады.
			_window_quad(b, Vector3(fx, y, r.y - 0.03), pane, false)
			_window_quad(b, Vector3(fx, y, r.w + 0.03), pane, false)
			# Западный и восточный.
			_window_quad(b, Vector3(r.x - 0.03, y, fz), pane, true)
			_window_quad(b, Vector3(r.z + 0.03, y, fz), pane, true)


func _window_quad(b: MeshBuilder, pos: Vector3, size: Vector2,
		along_z: bool) -> void:
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	if along_z:
		b.quad(
			pos + Vector3(0.0, -hh, -hw), pos + Vector3(0.0, -hh, hw),
			pos + Vector3(0.0, hh, hw), pos + Vector3(0.0, hh, -hw),
			COLOR_WINDOW_DARK)
		b.quad(
			pos + Vector3(0.0, -hh, hw), pos + Vector3(0.0, -hh, -hw),
			pos + Vector3(0.0, hh, -hw), pos + Vector3(0.0, hh, hw),
			COLOR_WINDOW_DARK)
	else:
		b.quad(
			pos + Vector3(-hw, -hh, 0.0), pos + Vector3(hw, -hh, 0.0),
			pos + Vector3(hw, hh, 0.0), pos + Vector3(-hw, hh, 0.0),
			COLOR_WINDOW_DARK)
		b.quad(
			pos + Vector3(hw, -hh, 0.0), pos + Vector3(-hw, -hh, 0.0),
			pos + Vector3(-hw, hh, 0.0), pos + Vector3(hw, hh, 0.0),
			COLOR_WINDOW_DARK)


## Меш рельефа Машука. Сетка строится по той же height_at(), что использует
## физика, поэтому визуал и коллизия совпадают пиксель-в-пиксель.
func build_terrain() -> ArrayMesh:
	var b := MeshBuilder.new()
	var x0 := -CityField.TERRAIN_X_LIMIT
	var x1 := CityField.TERRAIN_X_LIMIT
	var z0 := CityField.TERRAIN_Z_MIN
	var z1 := CityField.TERRAIN_Z_MAX
	var nx := int((x1 - x0) / TERRAIN_STEP)
	var nz := int((z1 - z0) / TERRAIN_STEP)
	for ix in nx:
		var xa := x0 + ix * TERRAIN_STEP
		var xb := xa + TERRAIN_STEP
		for iz in nz:
			var za := z0 + iz * TERRAIN_STEP
			var zb := za + TERRAIN_STEP
			var ya := field.height_at(xa, za)
			var yb := field.height_at(xb, za)
			var yc := field.height_at(xb, zb)
			var yd := field.height_at(xa, zb)
			# Полотно серпантина темнее травы — оно и есть дорога.
			var mid := (ya + yb + yc + yd) * 0.25
			var on_serp := field.dist_to_serp((xa + xb) * 0.5, (za + zb) * 0.5) \
				< CityField.SERP_HALF_WIDTH
			var col := COLOR_ROAD if on_serp else _slope_color(ya, yc, mid)
			b.quad(
				Vector3(xa, ya, za), Vector3(xa, yd, zb),
				Vector3(xb, yc, zb), Vector3(xb, yb, za), col)
	return b.commit()


## Склон окрашивается от луговой травы через сухую траву к камню — иначе
## гора читается однотонным блином.
const COLOR_MEADOW := Color("#5f8a4a")
const COLOR_DRY := Color("#8a8f5a")
const COLOR_ROCK := Color("#6a6558")

## Крутизна нормируется на шаг сетки: у Машука средний уклон ~0.43, и без
## нормировки каменный оттенок забивал всю гору до подошвы.
static func _slope_color(ya: float, yc: float, mid: float) -> Color:
	var alt: float = clampf((mid - 6.0) / 40.0, 0.0, 1.0)
	var steep: float = clampf(absf(yc - ya) / (TERRAIN_STEP * 1.6), 0.0, 1.0)
	var base := COLOR_MEADOW.lerp(COLOR_DRY, alt)
	return base.lerp(COLOR_ROCK, clampf(steep * 0.45 + alt * 0.35, 0.0, 1.0))
