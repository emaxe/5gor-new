extends Node3D
## Верхний рынок (рынок «Лира») — колоритный курортный базар Пятигорска.
##
## Включает:
## - Парадные въездные ворота с вывеской «ВЕРХНИЙ РЫНОК»;
## - Кирпичную ограду с чугунной решёткой;
## - Центральный крытый павильон-пассаж с двускатной крышей;
## - Торговые ряды с разноцветными полосатыми тентами (навесами);
## - Деревянные прилавки, ящики со знаменитыми фруктами и арбузами, бочки и мешки.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

# Палитра мощения и построек
const PAVE_STONE := Color("#c6bfb0")
const BRICK_RED := Color("#9e4b38")
const BRICK_DARK := Color("#7e3728")
const STONE_TRIM := Color("#e0d8c8")
const IRON_FENCE := Color("#2c2d30")
const WOOD_STALL := Color("#8c6846")
const WOOD_DARK := Color("#5a4028")
const ROOF_METAL := Color("#4a5660")

# Разноцветные тенты палаток
const AWNING_RED := Color("#c4382c")
const AWNING_BLUE := Color("#2b6bb0")
const AWNING_GREEN := Color("#2e8540")
const AWNING_YELLOW := Color("#e8a820")
const AWNING_WHITE := Color("#f0ece1")

# Товары (фрукты, овощи, арбузы)
const WATERMELON := Color("#235d29")
const WATERMELON_STRIPE := Color("#419e4a")
const APPLE_RED := Color("#d62828")
const PEACH_ORANGE := Color("#f77f00")
const GRAPE_PURPLE := Color("#582f6e")
const SACK_BURLAP := Color("#a89476")


func _ready() -> void:
	var b := MeshBuilder.new()

	_build_ground_and_fence(b)
	_build_entrance_gate(b)
	_build_central_arcade(b)
	_build_market_stalls(b)
	_build_produce_and_crates(b)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = PALETTE_MAT
	add_child(mi)

	_build_collision()


# --- Мощение и ограда -------------------------------------------------------

func _build_ground_and_fence(b: MeshBuilder) -> void:
	# Мощёная площадь рынка (34 x 30 м)
	b.box(Vector3(0.0, 0.08, 0.0), Vector3(34.0, 0.16, 30.0), PAVE_STONE)

	# Кирпичные столбы и решётки по периметру
	var min_x := -16.8
	var max_x := 16.8
	var min_z := -14.8
	var max_z := 14.8

	# Задняя стена (-Z) и боковые стороны
	b.box(Vector3(0.0, 1.2, min_z), Vector3(33.6, 2.2, 0.5), BRICK_RED)
	b.box(Vector3(0.0, 2.35, min_z), Vector3(34.0, 0.2, 0.7), STONE_TRIM)

	b.box(Vector3(min_x, 1.2, 0.0), Vector3(0.5, 2.2, 29.6), BRICK_RED)
	b.box(Vector3(min_x, 2.35, 0.0), Vector3(0.7, 0.2, 30.0), STONE_TRIM)

	b.box(Vector3(max_x, 1.2, 0.0), Vector3(0.5, 2.2, 29.6), BRICK_RED)
	b.box(Vector3(max_x, 2.35, 0.0), Vector3(0.7, 0.2, 30.0), STONE_TRIM)

	# Передняя сторона (+Z) с воротами
	for s: float in [-1.0, 1.0]:
		var px: float = s * 11.0
		b.box(Vector3(px, 1.0, max_z), Vector3(10.0, 1.8, 0.4), BRICK_RED)
		b.box(Vector3(px, 1.95, max_z), Vector3(10.2, 0.15, 0.6), STONE_TRIM)
		b.box(Vector3(px, 1.4, max_z), Vector3(9.6, 0.8, 0.1), IRON_FENCE)


# --- Парадные ворота с вывеской ---------------------------------------------

func _build_entrance_gate(b: MeshBuilder) -> void:
	var gz := 14.8

	# Два массивных кирпичных пилона ворот
	for s: float in [-1.0, 1.0]:
		var px: float = s * 4.8
		b.box(Vector3(px, 2.2, gz), Vector3(1.6, 4.2, 1.6), BRICK_RED)
		b.box(Vector3(px, 4.4, gz), Vector3(1.9, 0.3, 1.9), STONE_TRIM)
		b.sphere(Vector3(px, 4.9, gz), 0.38, STONE_TRIM, 4, 8)

	# Верхняя арка-перемычка с вывеской
	b.box(Vector3(0.0, 4.2, gz), Vector3(9.0, 0.3, 0.6), IRON_FENCE)
	# Вывеска рынка (красная с золотым кантом)
	b.box(Vector3(0.0, 4.8, gz), Vector3(7.6, 1.0, 0.3), BRICK_DARK)
	b.box(Vector3(0.0, 4.8, gz + 0.16), Vector3(7.2, 0.8, 0.05), AWNING_RED)
	b.box(Vector3(0.0, 5.35, gz), Vector3(7.8, 0.15, 0.35), STONE_TRIM)


# --- Центральный крытый павильон-пассаж -------------------------------------

func _build_central_arcade(b: MeshBuilder) -> void:
	# Длинный павильон по центру рынка (вдоль Z)
	var aw := 7.0
	var al := 18.0
	var ah := 3.8

	# Деревянные опорные колонны аркады
	for z_off: float in [-7.5, -2.5, 2.5, 7.5]:
		for s: float in [-1.0, 1.0]:
			var cx: float = s * 3.3
			b.cylinder(Vector3(cx, 1.8, z_off), 0.18, 0.22, 3.4, WOOD_DARK, 6)

	# Продольные и поперечные балки крыши
	b.box(Vector3(-3.3, ah - 0.2, 0.0), Vector3(0.3, 0.3, al), WOOD_DARK)
	b.box(Vector3(3.3, ah - 0.2, 0.0), Vector3(0.3, 0.3, al), WOOD_DARK)

	# Двускатная крыша павильона (металлопрофиль)
	var slope_l := Basis(Vector3.FORWARD, 0.35)
	var slope_r := Basis(Vector3.FORWARD, -0.35)
	b.box(Vector3(-1.9, ah + 0.6, 0.0), Vector3(4.2, 0.1, al + 0.4), ROOF_METAL, slope_l)
	b.box(Vector3(1.9, ah + 0.6, 0.0), Vector3(4.2, 0.1, al + 0.4), ROOF_METAL, slope_r)
	b.box(Vector3(0.0, ah + 1.35, 0.0), Vector3(0.4, 0.2, al + 0.5), STONE_TRIM)

	# Центральный двухсторонний прилавок внутри павильона
	b.box(Vector3(0.0, 0.55, 0.0), Vector3(3.2, 0.9, al - 2.0), WOOD_STALL)
	b.box(Vector3(0.0, 1.05, 0.0), Vector3(3.5, 0.1, al - 1.8), WOOD_DARK)


# --- Торговые ряды палаток с навесами ---------------------------------------

func _build_market_stalls(b: MeshBuilder) -> void:
	# Боковые ряды палаток (слева и справа от центрального пассажа)
	var side_xs: Array[float] = [-10.5, 10.5]
	var row_zs: Array[float] = [-9.0, -3.0, 3.0, 9.0]
	var colors := [AWNING_RED, AWNING_BLUE, AWNING_GREEN, AWNING_YELLOW]

	var col_idx := 0
	for sx: float in side_xs:
		var face_dir: float = 1.0 if sx < 0.0 else -1.0

		for rz: float in row_zs:
			var awning_col: Color = colors[col_idx % colors.size()]
			col_idx += 1

			# Деревянный прилавок
			b.box(Vector3(sx, 0.55, rz), Vector3(3.8, 0.9, 1.8), WOOD_STALL)
			b.box(Vector3(sx, 1.02, rz), Vector3(4.0, 0.08, 2.0), WOOD_DARK)

			# Опоры навеса
			for ox: float in [-1.7, 1.7]:
				b.cylinder(Vector3(sx + ox, 1.8, rz - 0.8), 0.06, 0.08, 2.6, IRON_FENCE, 5)
				b.cylinder(Vector3(sx + ox, 1.6, rz + 0.8), 0.06, 0.08, 2.2, IRON_FENCE, 5)

			# Скошенный тент палатки (полосатый эффект двумя слоями)
			var awning_basis := Basis(Vector3.RIGHT, 0.18 * face_dir)
			b.box(Vector3(sx, 2.7, rz), Vector3(4.2, 0.08, 2.4), awning_col, awning_basis)
			b.box(Vector3(sx, 2.75, rz), Vector3(2.0, 0.09, 2.4), AWNING_WHITE, awning_basis)
			# Свешивающийся край тента (ламбрекен)
			b.box(Vector3(sx, 2.45, rz + 1.2 * face_dir), Vector3(4.2, 0.4, 0.08), awning_col)


# --- Товары, ящики, фрукты и арбузы ----------------------------------------

func _build_produce_and_crates(b: MeshBuilder) -> void:
	# Горка знаменитых астраханских/ставропольских арбузов у входа
	var wz := 11.5
	for wx: float in [-5.5, 5.5]:
		# Деревянный поддон
		b.box(Vector3(wx, 0.15, wz), Vector3(2.4, 0.2, 2.4), WOOD_DARK)
		# Нижний ряд арбузов (4 шт)
		for ix: float in [-0.6, 0.6]:
			for iz: float in [-0.6, 0.6]:
				b.sphere(Vector3(wx + ix, 0.55, wz + iz), 0.34, WATERMELON, 4, 6, 0.8)
				b.sphere(Vector3(wx + ix, 0.55, wz + iz), 0.24, WATERMELON_STRIPE, 4, 6, 0.8)
		# Верхний арбуз по центру
		b.sphere(Vector3(wx, 0.95, wz), 0.35, WATERMELON, 4, 6, 0.8)

	# Ящики с яблоками и персиками на прилавках
	for sx: float in [-10.5, 10.5]:
		for rz: float in [-9.0, 3.0]:
			# Ящик
			b.box(Vector3(sx - 0.8, 1.2, rz), Vector3(0.9, 0.25, 0.7), WOOD_DARK)
			b.sphere(Vector3(sx - 0.8, 1.35, rz), 0.3, APPLE_RED, 3, 6)

			b.box(Vector3(sx + 0.8, 1.2, rz), Vector3(0.9, 0.25, 0.7), WOOD_DARK)
			b.sphere(Vector3(sx + 0.8, 1.35, rz), 0.3, PEACH_ORANGE, 3, 6)

	# Мешки со специями и бочки в центральном павильоне
	for bz: float in [-4.0, 4.0]:
		b.cylinder(Vector3(-1.0, 0.55, bz), 0.38, 0.32, 0.9, WOOD_DARK, 8)
		b.cylinder(Vector3(1.0, 0.5, bz), 0.35, 0.4, 0.8, SACK_BURLAP, 7)


# --- Коллизия ---------------------------------------------------------------

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	# Коллизии ограждения по периметру
	# Задняя стена
	_add_box_col(body, Vector3(0.0, 1.2, -14.8), Vector3(34.0, 2.4, 0.6))
	# Левая стена
	_add_box_col(body, Vector3(-16.8, 1.2, 0.0), Vector3(0.6, 2.4, 30.0))
	# Правая стена
	_add_box_col(body, Vector3(16.8, 1.2, 0.0), Vector3(0.6, 2.4, 30.0))
	# Передний забор (слева и справа от ворот)
	_add_box_col(body, Vector3(-11.0, 1.0, 14.8), Vector3(10.0, 2.0, 0.6))
	_add_box_col(body, Vector3(11.0, 1.0, 14.8), Vector3(10.0, 2.0, 0.6))

	# Коллизия центрального пассажа
	_add_box_col(body, Vector3(0.0, 1.8, 0.0), Vector3(3.6, 3.6, 17.0))

	# Коллизии боковых рядов прилавков
	for sx: float in [-10.5, 10.5]:
		for rz: float in [-9.0, -3.0, 3.0, 9.0]:
			_add_box_col(body, Vector3(sx, 1.5, rz), Vector3(4.2, 3.0, 2.2))


func _add_box_col(body: StaticBody3D, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	body.add_child(cs)
