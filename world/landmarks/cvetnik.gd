extends Node3D
## Парк «Цветник» с Лермонтовской галереей — сердце курортного Пятигорска.
##
## Включает:
## - Знаменитую Лермонтовскую галерею (1901 г., стиль модерн, лазурно-голубой
##   металлический каркас с витражами и изящными башнями со шпилями);
## - Центральный ступенчатый фонтан с чашами и струями воды;
## - Мощёную площадь и прогулочные аллеи;
## - Живописные фигурные клумбы («Цветник»);
## - Чугунные парковые скамьи, фонари и вазоны с цветами;
## - Памятную арку входа со стороны проспекта Кирова.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

# Палитра парка и отделки
const STONE_PAVE := Color("#c8c4b7")
const STONE_BORDER := Color("#aba596")
const STONE_LIGHT := Color("#dfd9cb")
const KERB := Color("#8e897e")
const WATER := Color("#4aa5e6")
const WATER_SPRAY := Color("#e8f4fc")

# Палитра Лермонтовской галереи (исторический лазурный модерн)
const GAL_WALL := Color("#428896")
const GAL_FRAME := Color("#2c6570")
const GAL_TRIM := Color("#f2ebd9")
const GAL_GLASS := Color("#2e3d48")
const GAL_ROOF := Color("#356f7b")
const GAL_SPIRE := Color("#cfa548")

# Детали
const WOOD_BENCH := Color("#8a5a36")
const IRON_DARK := Color("#2a2d30")
const PLANTER_STONE := Color("#beb8a8")
const LEAVES := Color("#3e7d38")

const FLOWERS: Array[Color] = [
	Color("#d63636"), Color("#f0a824"), Color("#a842bd"),
	Color("#e84a8a"), Color("#ffffff"), Color("#3b82e6"),
]


func _ready() -> void:
	var b := MeshBuilder.new()

	_build_plaza_and_paths(b)
	_build_lermontov_gallery(b)
	_build_fountain(b)
	_build_flower_beds(b)
	_build_park_furniture(b)
	_build_entrance_arch(b)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = PALETTE_MAT
	add_child(mi)

	_build_collision()


# --- Мощение и аллеи --------------------------------------------------------

func _build_plaza_and_paths(b: MeshBuilder) -> void:
	# Главная мощёная площадка парка (40x36 м)
	b.box(Vector3(0.0, 0.08, 0.0), Vector3(38.0, 0.16, 34.0), STONE_PAVE)
	b.box(Vector3(0.0, 0.09, 0.0), Vector3(38.6, 0.14, 34.6), STONE_BORDER)

	# Центральный круговой ковёр мощения вокруг фонтана
	b.cylinder(Vector3(0.0, 0.11, 4.0), 9.5, 9.5, 0.06, STONE_LIGHT, 24)
	b.cylinder(Vector3(0.0, 0.12, 4.0), 9.7, 9.7, 0.04, STONE_BORDER, 24)

	# Аллея к главному входу (в сторону проспекта Кирова на -Z)
	b.box(Vector3(0.0, 0.10, -18.0), Vector3(8.0, 0.15, 6.0), STONE_PAVE)


# --- Лермонтовская галерея --------------------------------------------------

func _build_lermontov_gallery(b: MeshBuilder) -> void:
	# Галерея располагается в глубине парка (+Z), лицом к площади
	var gz := 11.0
	var gy := 0.15

	# Цоколь галереи
	b.box(Vector3(0.0, gy + 0.4, gz), Vector3(26.4, 0.8, 8.4), STONE_LIGHT)

	# Центральный зал (более высокий)
	b.box(Vector3(0.0, gy + 3.8, gz), Vector3(12.0, 6.0, 8.0), GAL_WALL)

	# Арочная крыша центрального зала (свод)
	b.cylinder(Vector3(0.0, gy + 6.8, gz), 4.1, 4.1, 12.0, GAL_ROOF, 12,
		Basis(Vector3.FORWARD, PI * 0.5))

	# Световой фонарь / гребень крыши
	b.box(Vector3(0.0, gy + 8.2, gz), Vector3(11.0, 0.6, 1.2), GAL_TRIM)

	# Боковые крылья галереи (слева и справа)
	for s: float in [-1.0, 1.0]:
		var wx: float = s * 9.5
		b.box(Vector3(wx, gy + 2.8, gz), Vector3(7.0, 4.0, 7.2), GAL_WALL)
		# Скатная крыша крыла
		b.box(Vector3(wx, gy + 5.1, gz), Vector3(7.2, 0.6, 7.4), GAL_ROOF)
		# Декоративный аттик / парапет
		b.box(Vector3(wx, gy + 5.5, gz - 3.4), Vector3(7.0, 0.5, 0.3), GAL_TRIM)

	# Остекление фасада (витражные окна стиля модерн)
	for i in range(-5, 6):
		var wx := float(i) * 2.0
		b.box(Vector3(wx, gy + 3.2, gz - 4.05), Vector3(1.3, 3.4, 0.1), GAL_GLASS)
		b.box(Vector3(wx, gy + 5.1, gz - 4.05), Vector3(1.4, 0.4, 0.15), GAL_TRIM)

	# Две угловые башни со шпилями (визитная карточка галереи!)
	for s: float in [-1.0, 1.0]:
		var tx: float = s * 6.2
		var tz: float = gz - 3.8
		# Квадратный ствол башни
		b.box(Vector3(tx, gy + 5.0, tz), Vector3(2.4, 8.4, 2.4), GAL_WALL)
		# Карниз башни
		b.box(Vector3(tx, gy + 9.4, tz), Vector3(2.7, 0.4, 2.7), GAL_TRIM)
		# Оконные проёмы на башне
		b.box(Vector3(tx, gy + 8.2, tz - 1.15), Vector3(1.0, 1.6, 0.1), GAL_GLASS)
		# Пирамидальный шатёр башни
		b.cone(Vector3(tx, gy + 11.2, tz), 1.6, 3.2, GAL_ROOF, 4,
			Basis(Vector3.UP, PI * 0.25))
		# Изящный золотой шпиль на вершине
		b.cylinder(Vector3(tx, gy + 13.4, tz), 0.06, 0.14, 1.6, GAL_SPIRE, 6)
		b.sphere(Vector3(tx, gy + 14.3, tz), 0.22, GAL_SPIRE, 4, 6)

	# Центральный входной портал с козырьком
	b.box(Vector3(0.0, gy + 2.0, gz - 4.2), Vector3(3.2, 3.2, 0.4), GAL_FRAME)
	b.box(Vector3(0.0, gy + 1.6, gz - 4.3), Vector3(2.2, 2.6, 0.2), WOOD_BENCH)
	b.box(Vector3(0.0, gy + 3.8, gz - 4.4), Vector3(3.6, 0.2, 1.6), GAL_TRIM)


# --- Фонтан -----------------------------------------------------------------

func _build_fountain(b: MeshBuilder) -> void:
	var fpos := Vector3(0.0, 0.15, 4.0)

	# Внешнее каменное ограждение бассейна
	b.cylinder(fpos + Vector3(0.0, 0.25, 0.0), 4.8, 5.0, 0.5, STONE_BORDER, 20)
	b.cylinder(fpos + Vector3(0.0, 0.52, 0.0), 5.1, 4.8, 0.12, STONE_LIGHT, 20)

	# Водная гладь
	b.cylinder(fpos + Vector3(0.0, 0.40, 0.0), 4.6, 4.6, 0.05, WATER, 20)

	# Центральный постамент
	b.cylinder(fpos + Vector3(0.0, 0.9, 0.0), 1.1, 1.3, 1.0, STONE_LIGHT, 12)

	# Нижняя фигурная чаша фонтана
	b.cylinder(fpos + Vector3(0.0, 1.5, 0.0), 2.2, 0.8, 0.4, STONE_LIGHT, 16)
	b.cylinder(fpos + Vector3(0.0, 1.65, 0.0), 2.1, 2.1, 0.06, WATER, 16)

	# Верхняя малая чаша
	b.cylinder(fpos + Vector3(0.0, 2.2, 0.0), 0.5, 0.7, 1.0, STONE_LIGHT, 10)
	b.cylinder(fpos + Vector3(0.0, 2.8, 0.0), 1.2, 0.5, 0.3, STONE_LIGHT, 14)
	b.cylinder(fpos + Vector3(0.0, 2.9, 0.0), 1.1, 1.1, 0.05, WATER, 14)

	# Верхнее навершие и пенная струя
	b.sphere(fpos + Vector3(0.0, 3.2, 0.0), 0.28, STONE_LIGHT, 4, 8)
	b.cylinder(fpos + Vector3(0.0, 3.9, 0.0), 0.12, 0.22, 1.4, WATER_SPRAY, 6)


# --- Клумбы и цветы ---------------------------------------------------------

func _build_flower_beds(b: MeshBuilder) -> void:
	# 4 фигурные дугообразные клумбы вокруг фонтана
	for i in 4:
		var a: float = (float(i) * 90.0 + 45.0) * PI / 180.0
		var bx: float = cos(a) * 7.4
		var bz: float = sin(a) * 7.4 + 4.0
		var basis := Basis(Vector3.UP, -a)

		# Каменный бордюр клумбы
		b.box(Vector3(bx, 0.30, bz), Vector3(3.8, 0.35, 1.6), KERB, basis)
		# Земля / зелень
		b.box(Vector3(bx, 0.45, bz), Vector3(3.5, 0.15, 1.3), LEAVES, basis)

		# Яркие цветы (массивы соцветий)
		var col: Color = FLOWERS[i % FLOWERS.size()]
		for fx: float in [-1.1, -0.4, 0.4, 1.1]:
			b.sphere(Vector3(bx, 0.58, bz) + basis * Vector3(fx, 0.0, 0.0), 0.28, col, 3, 6, 0.6)
			b.sphere(Vector3(bx, 0.56, bz) + basis * Vector3(fx * 0.7, 0.0, 0.35), 0.22,
				FLOWERS[(i + 1) % FLOWERS.size()], 3, 6, 0.6)

	# 2 большие боковые партерные клумбы
	for s: float in [-1.0, 1.0]:
		var px: float = s * 14.5
		b.box(Vector3(px, 0.26, 4.0), Vector3(4.5, 0.32, 16.0), KERB)
		b.box(Vector3(px, 0.40, 4.0), Vector3(4.0, 0.16, 15.4), LEAVES)
		# Узоры из цветов на партерах
		for z_off in range(-6, 7, 2):
			var c_idx := absi(int(z_off) + int(s)) % FLOWERS.size()
			b.sphere(Vector3(px - 1.0, 0.54, 4.0 + float(z_off)), 0.34, FLOWERS[c_idx], 3, 6, 0.6)
			b.sphere(Vector3(px + 1.0, 0.54, 4.0 + float(z_off)), 0.34, FLOWERS[(c_idx + 2) % FLOWERS.size()], 3, 6, 0.6)


# --- Парковая мебель и фонари -----------------------------------------------

func _build_park_furniture(b: MeshBuilder) -> void:
	# 4 классические скамьи вокруг фонтана (лицом к воде)
	for i in 4:
		var a: float = (float(i) * 90.0) * PI / 180.0
		var sx: float = cos(a) * 9.8
		var sz: float = sin(a) * 9.8 + 4.0
		_add_bench(b, sx, sz, -a - PI * 0.5)

	# 4 фонарных столба с классическими 4-гранными фонарями
	var lamp_coords: Array[Vector2] = [
		Vector2(-9.0, -4.0), Vector2(9.0, -4.0),
		Vector2(-9.0, 12.0), Vector2(9.0, 12.0),
	]
	for lc in lamp_coords:
		_add_lantern(b, lc.x, lc.y)

	# Каменные вазоны у аллеи
	for s: float in [-1.0, 1.0]:
		_add_vase(b, s * 4.8, -12.0)
		_add_vase(b, s * 4.8, -4.0)


func _add_bench(b: MeshBuilder, x: float, z: float, rot_y: float) -> void:
	var basis := Basis(Vector3.UP, rot_y)
	# Деревянное сиденье и спинка
	b.box(Vector3(x, 0.52, z), Vector3(2.2, 0.08, 0.55), WOOD_BENCH, basis)
	b.box(Vector3(x, 0.85, z) + basis * Vector3(0.0, 0.0, -0.24), Vector3(2.2, 0.45, 0.08), WOOD_BENCH, basis)
	# Чугунные ножки
	for sx: float in [-0.95, 0.95]:
		b.box(Vector3(x, 0.26, z) + basis * Vector3(sx, 0.0, 0.0), Vector3(0.1, 0.48, 0.52), IRON_DARK, basis)


func _add_lantern(b: MeshBuilder, x: float, z: float) -> void:
	# Чугунный фонарный столб
	b.cylinder(Vector3(x, 0.25, z), 0.35, 0.45, 0.5, IRON_DARK, 8)
	b.cylinder(Vector3(x, 2.1, z), 0.12, 0.16, 3.2, IRON_DARK, 6)
	b.box(Vector3(x, 3.8, z), Vector3(0.65, 0.1, 0.65), IRON_DARK)
	# Светящееся стекло фонаря
	b.box(Vector3(x, 4.25, z), Vector3(0.45, 0.75, 0.45), Color("#fff5cc"))
	# Крышка фонаря
	b.cone(Vector3(x, 4.8, z), 0.6, 0.4, IRON_DARK, 4, Basis(Vector3.UP, PI * 0.25))


func _add_vase(b: MeshBuilder, x: float, z: float) -> void:
	b.cylinder(Vector3(x, 0.2, z), 0.4, 0.45, 0.4, STONE_LIGHT, 8)
	b.cylinder(Vector3(x, 0.6, z), 0.6, 0.35, 0.5, STONE_LIGHT, 8)
	b.sphere(Vector3(x, 0.95, z), 0.48, FLOWERS[1], 4, 6, 0.7)


# --- Входная колоннада / арка -----------------------------------------------

func _build_entrance_arch(b: MeshBuilder) -> void:
	# Парадная белая арка со стороны проспекта Кирова (-Z)
	var az := -15.5
	# Две каменные тумбы-пилоны
	for s: float in [-1.0, 1.0]:
		var px: float = s * 4.2
		b.box(Vector3(px, 1.8, az), Vector3(1.2, 3.6, 1.2), STONE_LIGHT)
		b.box(Vector3(px, 3.7, az), Vector3(1.4, 0.25, 1.4), STONE_BORDER)
		b.sphere(Vector3(px, 4.1, az), 0.32, STONE_LIGHT, 6, 6)

	# Ажурная металлическая перемычка над входом
	b.box(Vector3(0.0, 3.6, az), Vector3(8.4, 0.2, 0.2), IRON_DARK)
	b.cylinder(Vector3(0.0, 4.2, az), 2.2, 2.2, 0.15, IRON_DARK, 12,
		Basis(Vector3.RIGHT, PI * 0.5))


# --- Коллизия ---------------------------------------------------------------

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	# Коллизия здания Лермонтовской галереи
	var cs_gal := CollisionShape3D.new()
	var box_gal := BoxShape3D.new()
	box_gal.size = Vector3(27.0, 10.0, 9.0)
	cs_gal.shape = box_gal
	cs_gal.position = Vector3(0.0, 5.0, 11.0)
	body.add_child(cs_gal)

	# Коллизия фонтана (только бассейн и чаша)
	var cs_fount := CollisionShape3D.new()
	var cyl_fount := CylinderShape3D.new()
	cyl_fount.radius = 5.2
	cyl_fount.height = 1.2
	cs_fount.shape = cyl_fount
	cs_fount.position = Vector3(0.0, 0.7, 4.0)
	body.add_child(cs_fount)

	# Коллизии входных пилонов
	for s: float in [-1.0, 1.0]:
		var cs_pylon := CollisionShape3D.new()
		var box_pylon := BoxShape3D.new()
		box_pylon.size = Vector3(1.4, 3.8, 1.4)
		cs_pylon.shape = box_pylon
		cs_pylon.position = Vector3(s * 4.2, 1.9, -15.5)
		body.add_child(cs_pylon)
