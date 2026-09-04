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
const COLOR_WINDOW_DARK := Color("#202630")
const COLOR_WINDOW_LIT_WARM := Color("#ffd984")
const COLOR_WINDOW_LIT_COOL := Color("#6c96ba")
const COLOR_WINDOW_FRAME := Color("#1a1e22")
const COLOR_ROOF_GRAVEL := Color("#35393f")
const COLOR_DOOR_WOOD := Color("#3c261a")
const COLOR_CANOPY := Color("#2e343c")
const COLOR_BRASS := Color("#d4af37")
const COLOR_CHIMNEY := Color("#7c382b")
const COLOR_BEACON := Color("#e02222")

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

	# 1. Полотно дорог
	for c in field.road_axes:
		b.plane_xz(Vector3(c, Y_ROAD, 0.0), Vector2(half * 2.0, span * 2.0), COLOR_ROAD)
		b.plane_xz(Vector3(0.0, Y_ROAD, c), Vector2(span * 2.0, half * 2.0), COLOR_ROAD)

	# 2. Сегменты между перекрёстками, чтобы тротуары и бордюры не рассекали перекрёстки
	var seg_centers := PackedFloat32Array()
	var seg_lengths := PackedFloat32Array()

	var end_len := field.grid_ext - half
	seg_centers.append((-span + (field.road_axes[0] - half)) * 0.5)
	seg_lengths.append(end_len)

	var block_len := field.cell - half * 2.0
	for j in field.road_axes.size() - 1:
		seg_centers.append((field.road_axes[j] + field.road_axes[j + 1]) * 0.5)
		seg_lengths.append(block_len)

	seg_centers.append((span + (field.road_axes[field.road_axes.size() - 1] + half)) * 0.5)
	seg_lengths.append(end_len)

	for c in field.road_axes:
		for k in seg_centers.size():
			var center := seg_centers[k]
			var length := seg_lengths[k]
			for s: float in [-1.0, 1.0]:
				var off := s * (half + walk * 0.5)
				var curb := s * (half + 0.25)

				# Вдоль дорог оси Z
				b.plane_xz(Vector3(c + off, Y_SIDEWALK, center),
					Vector2(walk, length), COLOR_SIDEWALK)
				b.box(Vector3(c + curb, Y_CURB_TOP * 0.5, center),
					Vector3(0.5, Y_CURB_TOP, length), COLOR_CURB)

				# Вдоль дорог оси X
				b.plane_xz(Vector3(center, Y_SIDEWALK, c + off),
					Vector2(length, walk), COLOR_SIDEWALK)
				b.box(Vector3(center, Y_CURB_TOP * 0.5, c + curb),
					Vector3(length, Y_CURB_TOP, 0.5), COLOR_CURB)

	# 3. Угловые площадки тротуаров и бордюров вокруг перекрёстков
	for cv in field.road_axes:
		for ch in field.road_axes:
			for sv: float in [-1.0, 1.0]:
				for sh: float in [-1.0, 1.0]:
					var off_v := sv * (half + walk * 0.5)
					var off_h := sh * (half + walk * 0.5)
					b.plane_xz(Vector3(cv + off_v, Y_SIDEWALK, ch + off_h),
						Vector2(walk, walk), COLOR_SIDEWALK)
					b.box(Vector3(cv + sv * (half + 0.25), Y_CURB_TOP * 0.5, ch + sh * (half + 0.25)),
						Vector3(0.5, Y_CURB_TOP, 0.5), COLOR_CURB)

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
	var seed_hash: int = (i * 7919 + int(cx * 13.0) + int(cz * 17.0)) & 0x7fffffff
	var archetype := (seed_hash % 4)

	# 1. Цоколь здания (Массивный машукский камень / гранит)
	var base_h: float = clampf(h * 0.08, 0.50, 1.1)
	var plinth_color := facade.darkened(0.42).lerp(Color("#282a2e"), 0.4)
	b.box(Vector3(cx, Y_SIDEWALK + base_h * 0.5, cz),
		Vector3(w + 0.22, base_h, dep + 0.22), plinth_color)
	# Пояс цокольного отлива
	b.box(Vector3(cx, Y_SIDEWALK + base_h, cz),
		Vector3(w + 0.28, 0.08, dep + 0.28), plinth_color.lightened(0.15))

	# 2. Основной объём фасада
	b.box(Vector3(cx, Y_SIDEWALK + h * 0.5, cz), Vector3(w, h, dep), facade)

	# 3. Рустованные угловые камни (Rusticated Quoins из машукского белого камня)
	var quoin_col := Color("#f0ece1") if facade.v < 0.75 else facade.darkened(0.25)
	var quoin_step := 1.1
	var num_quoins := int((h - base_h) / quoin_step)
	for q in num_quoins:
		var qy := Y_SIDEWALK + base_h + (q + 0.5) * quoin_step
		var q_size := 0.70 if (q % 2 == 0) else 0.48
		# 4 угла здания
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				b.box(Vector3(cx + sx * (w * 0.5 - 0.04), qy, cz + sz * (dep * 0.5 - 0.04)),
					Vector3(q_size + 0.12, quoin_step * 0.88, q_size + 0.12), quoin_col)

	# 4. Межэтажный поясок и карниз над коммерческим этажом
	if h >= 5.5:
		var belt_y := Y_SIDEWALK + minf(h * 0.32, 3.8)
		b.box(Vector3(cx, belt_y, cz), Vector3(w + 0.18, 0.24, dep + 0.18), quoin_col)
		b.box(Vector3(cx, belt_y + 0.14, cz), Vector3(w + 0.26, 0.06, dep + 0.26), quoin_col.darkened(0.1))

	# 5. Венчающий карниз и кровля
	var is_pitched := plan.building_roof_kind[i] == 1
	var cornice_color := quoin_col.darkened(0.08)

	if is_pitched:
		# Скатная кровля с нависающими свесами и карнизом с кронштейнами
		b.box(Vector3(cx, Y_SIDEWALK + h + 0.12, cz), Vector3(w + 0.42, 0.24, dep + 0.42), cornice_color)
		var pitch: float = clampf(minf(w, dep) * 0.28, 1.8, 4.5)
		var roof_base_y := Y_SIDEWALK + h + 0.24

		if w > dep * 1.15:
			b.prism(Vector3(cx, roof_base_y + pitch * 0.5, cz),
				Vector3(dep + 0.5, pitch, w + 0.5), roof, Basis(Vector3.UP, PI * 0.5))
			# Слуховые окна (люкарны) на скате
			if w >= 12.0:
				for sx: float in [-w * 0.24, w * 0.24]:
					b.box(Vector3(cx + sx, roof_base_y + pitch * 0.35, cz + dep * 0.36),
						Vector3(1.3, 1.1, 1.1), facade)
					b.prism(Vector3(cx + sx, roof_base_y + pitch * 0.35 + 0.8, cz + dep * 0.36),
						Vector3(1.4, 0.6, 1.2), roof)
					b.box(Vector3(cx + sx, roof_base_y + pitch * 0.35, cz + dep * 0.36 + 0.56),
						Vector3(0.8, 0.8, 0.05), COLOR_WINDOW_LIT_WARM)
		elif dep > w * 1.15:
			b.prism(Vector3(cx, roof_base_y + pitch * 0.5, cz),
				Vector3(w + 0.5, pitch, dep + 0.5), roof)
			if dep >= 12.0:
				for sz: float in [-dep * 0.24, dep * 0.24]:
					b.box(Vector3(cx + w * 0.36, roof_base_y + pitch * 0.35, cz + sz),
						Vector3(1.1, 1.1, 1.3), facade)
					b.prism(Vector3(cx + w * 0.36, roof_base_y + pitch * 0.35 + 0.8, cz + sz),
						Vector3(1.2, 0.6, 1.4), roof, Basis(Vector3.UP, PI * 0.5))
					b.box(Vector3(cx + w * 0.36 + 0.56, roof_base_y + pitch * 0.35, cz + sz),
						Vector3(0.05, 0.8, 0.8), COLOR_WINDOW_LIT_WARM)
		else:
			b.cone(Vector3(cx, roof_base_y + pitch * 0.5, cz),
				minf(w, dep) * 0.78, pitch, roof, 4, Basis(Vector3.UP, PI * 0.25))

		# Дымоходы из красного кирпича
		if seed_hash % 3 != 0:
			var ch_x := cx + (w * 0.24 if (seed_hash % 2 == 0) else -w * 0.24)
			var ch_z := cz + (dep * 0.18 if ((seed_hash >> 2) % 2 == 0) else -dep * 0.18)
			var ch_y := roof_base_y + pitch * 0.55
			b.box(Vector3(ch_x, ch_y, ch_z), Vector3(0.70, 1.3, 0.70), COLOR_CHIMNEY)
			b.box(Vector3(ch_x, ch_y + 0.70, ch_z), Vector3(0.86, 0.12, 0.86), COLOR_WINDOW_FRAME)
	else:
		# Плоская кровля с аттиком, балюстрадой или ротондой
		b.box(Vector3(cx, Y_SIDEWALK + h + 0.22, cz), Vector3(w + 0.38, 0.44, dep + 0.38), cornice_color)
		b.plane_xz(Vector3(cx, Y_SIDEWALK + h + 0.08, cz), Vector2(w - 0.2, dep - 0.2), COLOR_ROOF_GRAVEL)

		# Пятигорская ротонда-бельведер (символ курорта) на классических зданиях
		if archetype == 0 and w >= 11.0 and dep >= 11.0:
			var rot_y := Y_SIDEWALK + h + 0.25
			var rot_r := 2.0
			b.cylinder(Vector3(cx, rot_y + 0.15, cz), rot_r, rot_r, 0.30, quoin_col, 12)
			for k in 6:
				var a := TAU * k / 6.0
				var col_p := Vector3(cx + cos(a) * (rot_r * 0.75), rot_y + 1.2, cz + sin(a) * (rot_r * 0.75))
				b.cylinder(col_p, 0.10, 0.10, 1.8, Color.WHITE, 6)
			# Купол ротонды
			b.cone(Vector3(cx, rot_y + 2.6, cz), rot_r * 0.95, 1.2, Color("#488078"), 8)
			b.cylinder(Vector3(cx, rot_y + 3.3, cz), 0.03, 0.03, 0.6, COLOR_BRASS, 4)
		else:
			# Лифтовая шахта / выход на крышу
			if w >= 8.0 and dep >= 8.0:
				var pent_w := minf(w * 0.30, 4.0)
				var pent_d := minf(dep * 0.30, 4.0)
				var pent_h := 1.9
				var off_x := (w * 0.18) if (seed_hash % 2 == 0) else (-w * 0.18)
				var off_z := (dep * 0.18) if ((seed_hash >> 1) % 2 == 0) else (-dep * 0.18)
				b.box(Vector3(cx + off_x, Y_SIDEWALK + h + pent_h * 0.5, cz + off_z),
					Vector3(pent_w, pent_h, pent_d), facade.darkened(0.2))
				b.box(Vector3(cx + off_x, Y_SIDEWALK + h + pent_h + 0.06, cz + off_z),
					Vector3(pent_w + 0.2, 0.12, pent_d + 0.2), cornice_color)

			# Блок вентиляции / HVAC
			var ac_x := cx - (w * 0.2) if (seed_hash % 2 == 0) else cx + (w * 0.2)
			var ac_z := cz - (dep * 0.2) if ((seed_hash >> 1) % 2 == 0) else cz + (dep * 0.2)
			b.box(Vector3(ac_x, Y_SIDEWALK + h + 0.55, ac_z), Vector3(1.8, 0.9, 1.3), Color("#4a525a"))
			b.box(Vector3(ac_x, Y_SIDEWALK + h + 0.55, ac_z), Vector3(1.6, 0.7, 1.4), Color("#32363c"))

			if h >= 10.0:
				var ant_h := 3.8
				b.cylinder(Vector3(cx, Y_SIDEWALK + h + ant_h * 0.5, cz), 0.06, 0.09, ant_h, Color("#363a40"), 6)
				b.box(Vector3(cx, Y_SIDEWALK + h + ant_h + 0.2, cz), Vector3(0.3, 0.3, 0.3), COLOR_BEACON)

	# 6. Входные группы и портики
	_add_entrance(b, r, cx, cz, w, dep, facade, seed_hash, archetype, quoin_col)

	# 7. Балконы и лоджии
	if h >= 6.0 and not is_pitched:
		_add_balconies(b, r, h, w, dep, facade, seed_hash)

	# 8. Окна, витрины и маркизы
	_add_windows(b, i, seed_hash, archetype)


func _add_entrance(b: MeshBuilder, r: Vector4, cx: float, cz: float,
		w: float, dep: float, facade: Color, seed_hash: int,
		archetype: int, quoin_col: Color) -> void:
	var front_z := (seed_hash % 2 == 0)
	var z_pos: float = r.w if front_z else r.y
	var door_dir: float = 1.0 if front_z else -1.0
	var door_w := 1.8
	var door_h := 2.4
	var center_x := cx + clampf(float((seed_hash >> 3) % 5 - 2) * 1.5, -w * 0.25, w * 0.25)
	var door_y := Y_SIDEWALK + door_h * 0.5

	# Ступени перед дверью
	b.box(Vector3(center_x, Y_SIDEWALK + 0.08, z_pos + door_dir * 0.55),
		Vector3(door_w + 1.1, 0.16, 1.1), COLOR_CURB)
	b.box(Vector3(center_x, Y_SIDEWALK + 0.22, z_pos + door_dir * 0.25),
		Vector3(door_w + 0.7, 0.16, 0.6), COLOR_CURB)

	# Дверное полотно
	b.box(Vector3(center_x, door_y, z_pos + door_dir * 0.05),
		Vector3(door_w, door_h, 0.12), COLOR_DOOR_WOOD)
	b.box(Vector3(center_x - 0.42, door_y + 0.2, z_pos + door_dir * 0.08),
		Vector3(0.48, 1.15, 0.08), COLOR_WINDOW_DARK)
	b.box(Vector3(center_x + 0.42, door_y + 0.2, z_pos + door_dir * 0.08),
		Vector3(0.48, 1.15, 0.08), COLOR_WINDOW_DARK)
	b.box(Vector3(center_x - 0.08, door_y - 0.05, z_pos + door_dir * 0.13),
		Vector3(0.04, 0.25, 0.04), COLOR_BRASS)
	b.box(Vector3(center_x + 0.08, door_y - 0.05, z_pos + door_dir * 0.13),
		Vector3(0.04, 0.25, 0.04), COLOR_BRASS)

	# Портик с белыми колоннами и фронтоном (для классических санаториев)
	if archetype == 0 or archetype == 1:
		var port_h := door_h + 0.4
		var col_r := 0.12
		var port_depth := 1.2
		for sx: float in [-1.0, 1.0]:
			var col_pos := Vector3(center_x + sx * (door_w * 0.5 + 0.25),
				Y_SIDEWALK + port_h * 0.5, z_pos + door_dir * (port_depth - 0.15))
			b.cylinder(col_pos, col_r, col_r, port_h, Color.WHITE, 8)
		# Фронтон над портиком
		var fronton_y := Y_SIDEWALK + port_h + 0.30
		b.box(Vector3(center_x, Y_SIDEWALK + port_h + 0.08, z_pos + door_dir * (port_depth * 0.5)),
			Vector3(door_w + 1.0, 0.16, port_depth), quoin_col)
		b.prism(Vector3(center_x, fronton_y, z_pos + door_dir * (port_depth * 0.5)),
			Vector3(door_w + 1.0, 0.65, port_depth), quoin_col,
			Basis(Vector3.UP, 0.0 if front_z else PI))
	else:
		# Современный козырек
		var canopy_y := Y_SIDEWALK + door_h + 0.25
		b.box(Vector3(center_x, canopy_y, z_pos + door_dir * 0.65),
			Vector3(door_w + 0.9, 0.14, 1.3), COLOR_CANOPY)


func _add_balconies(b: MeshBuilder, r: Vector4, h: float,
		w: float, dep: float, facade: Color, seed_hash: int) -> void:
	var rows: int = clampi(roundi(h / 3.2), 2, 10)
	var cols: int = clampi(roundi(w / 4.4), 1, 6)
	if rows < 3 or cols < 2:
		return

	var balc_w := 2.0
	var balc_h := 0.8
	var balc_depth := 0.85
	var rail_color: Color = facade.darkened(0.2) if (seed_hash % 2 == 0) else Color("#e2e4e8")

	for row in range(1, rows):
		var y := Y_SIDEWALK + (row + 0.25) * (h / rows)
		if y > Y_SIDEWALK + h - 1.2:
			continue
		for col in cols:
			if (col + row + seed_hash) % 2 != 0:
				continue
			var bx := r.x + (col + 0.5) * (w / cols)
			_single_balcony(b, Vector3(bx, y, r.w), balc_w, balc_h, balc_depth, 1.0, rail_color)
			if (seed_hash >> 2) % 2 == 0:
				_single_balcony(b, Vector3(bx, y, r.y), balc_w, balc_h, balc_depth, -1.0, rail_color)


func _single_balcony(b: MeshBuilder, wall_pos: Vector3, bw: float,
		bh: float, bdepth: float, dir_z: float, rail_col: Color) -> void:
	var slab_z := wall_pos.z + dir_z * bdepth * 0.5
	b.box(Vector3(wall_pos.x, wall_pos.y, slab_z),
		Vector3(bw, 0.16, bdepth), COLOR_CURB)
	b.box(Vector3(wall_pos.x, wall_pos.y + bh * 0.5, wall_pos.z + dir_z * (bdepth - 0.04)),
		Vector3(bw, bh, 0.08), rail_col)
	b.box(Vector3(wall_pos.x - bw * 0.5 + 0.04, wall_pos.y + bh * 0.5, slab_z),
		Vector3(0.08, bh, bdepth), rail_col)
	b.box(Vector3(wall_pos.x + bw * 0.5 - 0.04, wall_pos.y + bh * 0.5, slab_z),
		Vector3(0.08, bh, bdepth), rail_col)


func _add_windows(b: MeshBuilder, i: int, seed_hash: int, archetype: int = 0) -> void:
	var r := plan.building_rect[i]
	var h := plan.building_height[i]
	var w := r.z - r.x
	var dep := r.w - r.y
	var cols_x: int = clampi(roundi(w / 3.8), 2, 9)
	var cols_z: int = clampi(roundi(dep / 3.8), 2, 9)
	var rows: int = clampi(roundi(h / 3.0), 2, 12)
	if rows < 2:
		return

	var pane_w := minf(1.4, w / cols_x * 0.55)
	var pane_h := 1.45
	var awning_colors := [
		Color("#b53b2a"), # Терракотовая полоса
		Color("#2f6b4f"), # Изумрудная полоса
		Color("#2d538f"), # Курортная синяя
		Color("#c98528"), # Золотисто-охристая
	]
	var awning_col: Color = awning_colors[(seed_hash + i) % awning_colors.size()]

	for row in rows:
		var y := Y_SIDEWALK + (row + 0.6) * (h / rows)
		if y > Y_SIDEWALK + h - 0.8:
			continue
		var is_ground_floor := (row == 0)

		# Северный и южный фасады
		for col in cols_x:
			var fx := r.x + (col + 0.5) * (w / cols_x)
			var w_seed := (seed_hash + row * 19 + col * 7) & 0x7fffffff
			var win_col := _pick_window_color(w_seed, is_ground_floor)
			var win_size := Vector2(pane_w * (1.3 if is_ground_floor else 1.0),
				pane_h * (1.2 if is_ground_floor else 1.0))
			_window_with_frame(b, Vector3(fx, y, r.y - 0.02), win_size, false, win_col,
				is_ground_floor, awning_col, archetype, -1.0)
			_window_with_frame(b, Vector3(fx, y, r.w + 0.02), win_size, false, win_col,
				is_ground_floor, awning_col, archetype, 1.0)

		# Западный и восточный фасады
		for col in cols_z:
			var fz := r.y + (col + 0.5) * (dep / cols_z)
			var w_seed := (seed_hash + row * 23 + col * 11 + 101) & 0x7fffffff
			var win_col := _pick_window_color(w_seed, is_ground_floor)
			var win_size := Vector2(minf(1.4, dep / cols_z * 0.55) * (1.3 if is_ground_floor else 1.0),
				pane_h * (1.2 if is_ground_floor else 1.0))
			_window_with_frame(b, Vector3(r.x - 0.02, y, fz), win_size, true, win_col,
				is_ground_floor, awning_col, archetype, -1.0)
			_window_with_frame(b, Vector3(r.z + 0.02, y, fz), win_size, true, win_col,
				is_ground_floor, awning_col, archetype, 1.0)


func _pick_window_color(seed_val: int, is_ground: bool) -> Color:
	if is_ground:
		var m := seed_val % 10
		if m < 6:
			return COLOR_WINDOW_LIT_WARM
		elif m < 8:
			return COLOR_WINDOW_LIT_COOL
		return COLOR_WINDOW_DARK
	var r := seed_val % 100
	if r < 36:
		return COLOR_WINDOW_LIT_WARM
	elif r < 50:
		return COLOR_WINDOW_LIT_COOL
	return COLOR_WINDOW_DARK


func _window_with_frame(b: MeshBuilder, pos: Vector3, size: Vector2,
		along_z: bool, glass_color: Color, is_ground: bool = false,
		awning_col: Color = Color.WHITE, archetype: int = 0, face_dir: float = 1.0) -> void:
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	var frame_pad := 0.08

	if along_z:
		b.box(pos, Vector3(0.03, size.y + frame_pad * 2.0, size.x + frame_pad * 2.0), COLOR_WINDOW_FRAME)
		b.box(pos + Vector3(0.0, -hh - 0.04, 0.0), Vector3(0.10, 0.08, size.x + frame_pad * 2.4), COLOR_CURB)
		# Сандрик / карниз над окном на верхних этажах
		if not is_ground and (archetype == 0 or archetype == 1):
			b.box(pos + Vector3(0.0, hh + 0.06, 0.0), Vector3(0.12, 0.08, size.x + frame_pad * 2.6), COLOR_WINDOW_FRAME)
		elif is_ground:
			# Наклонная полосатая маркиза магазина
			var awn_x := pos.x + face_dir * 0.45
			b.box(Vector3(awn_x, pos.y + hh + 0.15, pos.z),
				Vector3(0.85, 0.12, size.x + 0.35), awning_col)
			b.box(Vector3(awn_x, pos.y + hh + 0.15, pos.z),
				Vector3(0.82, 0.03, size.x + 0.33), Color.WHITE)
	else:
		b.box(pos, Vector3(size.x + frame_pad * 2.0, size.y + frame_pad * 2.0, 0.03), COLOR_WINDOW_FRAME)
		b.box(pos + Vector3(0.0, -hh - 0.04, 0.0), Vector3(size.x + frame_pad * 2.4, 0.08, 0.10), COLOR_CURB)
		if not is_ground and (archetype == 0 or archetype == 1):
			b.box(pos + Vector3(0.0, hh + 0.06, 0.0), Vector3(size.x + frame_pad * 2.6, 0.08, 0.12), COLOR_WINDOW_FRAME)
		elif is_ground:
			var awn_z := pos.z + face_dir * 0.45
			b.box(Vector3(pos.x, pos.y + hh + 0.15, awn_z),
				Vector3(size.x + 0.35, 0.12, 0.85), awning_col)
			b.box(Vector3(pos.x, pos.y + hh + 0.15, awn_z),
				Vector3(size.x + 0.33, 0.03, 0.82), Color.WHITE)

	var glass_pos := pos + (Vector3(0.02 if face_dir > 0 else -0.02, 0.0, 0.0) if along_z else Vector3(0.0, 0.0, 0.02 if face_dir > 0 else -0.02))
	if along_z:
		b.quad(
			glass_pos + Vector3(0.0, -hh, -hw), glass_pos + Vector3(0.0, -hh, hw),
			glass_pos + Vector3(0.0, hh, hw), glass_pos + Vector3(0.0, hh, -hw),
			glass_color)
		b.quad(
			glass_pos + Vector3(0.0, -hh, hw), glass_pos + Vector3(0.0, -hh, -hw),
			glass_pos + Vector3(0.0, hh, -hw), glass_pos + Vector3(0.0, hh, hw),
			glass_color)
	else:
		b.quad(
			glass_pos + Vector3(-hw, -hh, 0.0), glass_pos + Vector3(hw, -hh, 0.0),
			glass_pos + Vector3(hw, hh, 0.0), glass_pos + Vector3(-hw, hh, 0.0),
			glass_color)
		b.quad(
			glass_pos + Vector3(hw, -hh, 0.0), glass_pos + Vector3(-hw, -hh, 0.0),
			glass_pos + Vector3(-hw, hh, 0.0), glass_pos + Vector3(hw, hh, 0.0),
			glass_color)


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
