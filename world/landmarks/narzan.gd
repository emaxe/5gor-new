extends Node3D
## Нарзанные ванны / Центральная питьевая галерея — шедевр курортной архитектуры
## Пятигорска (неоклассицизм / ампир).
##
## Включает:
## - Монументальный центральный портик с колоннами, архитравом и фронтоном;
## - Ротонду с куполом, арочными окнами барабана и шпилем-фонариком;
## - Симметричные боковые галерейные крылья с балюстрадами и карнизами;
## - Парадную каменную лестницу, террасу с балюстрадами и фонарями.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

# Палитра кавказского камня (травертин, машукский известняк)
const STONE_MAIN := Color("#e8e0cc")
const STONE_TRIM := Color("#f5efe2")
const STONE_BASE := Color("#baae98")
const STONE_DARK := Color("#9a8f7b")
const DOME_COPPER := Color("#558273")
const DOME_ACCENT := Color("#3e6558")
const GOLD := Color("#d4a843")
const DOOR_WOOD := Color("#4d3626")
const GLASS_WINDOW := Color("#2e3d48")
const LIGHT_GLOW := Color("#fff2cc")
const IRON_LAMP := Color("#2e3033")


func _ready() -> void:
	var b := MeshBuilder.new()

	_build_terrace_and_steps(b)
	_build_main_building(b)
	_build_portico_and_columns(b)
	_build_dome(b)
	_build_wings(b)
	_build_terrace_decor(b)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = PALETTE_MAT
	add_child(mi)

	_build_collision()


# --- Терраса и парадная лестница --------------------------------------------

func _build_terrace_and_steps(b: MeshBuilder) -> void:
	# Главная мощёная терраса перед входом (26x18 м)
	b.box(Vector3(0.0, 0.4, 0.0), Vector3(28.0, 0.8, 20.0), STONE_BASE)
	b.box(Vector3(0.0, 0.85, 0.0), Vector3(27.4, 0.1, 19.4), STONE_MAIN)

	# Парадная 3-ступенчатая лестница спереди (-Z)
	var step_w := 14.0
	for step in 3:
		var sy := 0.2 + float(step) * 0.25
		var sz := -10.0 - float(2 - step) * 0.8
		b.box(Vector3(0.0, sy * 0.5, sz), Vector3(step_w, sy, 0.9), STONE_BASE)

	# Балюстрада по краю террасы
	for s: float in [-1.0, 1.0]:
		var bx: float = s * 13.5
		# Боковые перила
		b.box(Vector3(bx, 1.35, 0.0), Vector3(0.4, 0.9, 19.0), STONE_TRIM)
		# Угловые тумбы
		b.box(Vector3(bx, 1.5, -9.5), Vector3(0.8, 1.2, 0.8), STONE_TRIM)
		b.box(Vector3(bx, 1.5, 9.5), Vector3(0.8, 1.2, 0.8), STONE_TRIM)
		b.sphere(Vector3(bx, 2.25, -9.5), 0.28, STONE_MAIN, 4, 8)
		b.sphere(Vector3(bx, 2.25, 9.5), 0.28, STONE_MAIN, 4, 8)

	# Передние секции перил до лестницы
	for s: float in [-1.0, 1.0]:
		var px: float = s * 10.5
		b.box(Vector3(px, 1.35, -9.5), Vector3(5.6, 0.9, 0.4), STONE_TRIM)
		b.box(Vector3(s * 7.5, 1.5, -9.5), Vector3(0.8, 1.2, 0.8), STONE_TRIM)
		b.sphere(Vector3(s * 7.5, 2.25, -9.5), 0.28, STONE_MAIN, 4, 8)


# --- Центральный корпус -----------------------------------------------------

func _build_main_building(b: MeshBuilder) -> void:
	var by := 0.9

	# Центральный объём здания
	b.box(Vector3(0.0, by + 4.5, 2.5), Vector3(14.0, 9.0, 12.0), STONE_MAIN)
	# Цокольный пояс
	b.box(Vector3(0.0, by + 0.6, 2.5), Vector3(14.4, 1.2, 12.4), STONE_DARK)
	# Венчающий карниз
	b.box(Vector3(0.0, by + 9.2, 2.5), Vector3(14.8, 0.6, 12.8), STONE_TRIM)

	# Парадный вход (двери и портал)
	b.box(Vector3(0.0, by + 2.5, -3.55), Vector3(3.2, 4.4, 0.2), STONE_TRIM)
	b.box(Vector3(0.0, by + 2.2, -3.6), Vector3(2.4, 3.8, 0.1), DOOR_WOOD)
	# Фрамуга над дверью (арочное окно)
	b.box(Vector3(0.0, by + 3.8, -3.58), Vector3(2.2, 0.8, 0.15), GLASS_WINDOW)


# --- Колонный портик --------------------------------------------------------

func _build_portico_and_columns(b: MeshBuilder) -> void:
	var by := 0.9
	var pz := -4.8
	var col_h := 8.2

	# 6 колонн ионического/тосканского ордера по фасаду портика
	var col_xs := [-5.5, -3.3, -1.1, 1.1, 3.3, 5.5]
	for cx in col_xs:
		# База колонны
		b.cylinder(Vector3(cx, by + 0.3, pz), 0.55, 0.65, 0.6, STONE_TRIM, 8)
		# Ствол колонны
		b.cylinder(Vector3(cx, by + 0.6 + col_h * 0.5, pz), 0.42, 0.48, col_h, STONE_TRIM, 8)
		# Капитель
		b.box(Vector3(cx, by + 0.6 + col_h + 0.3, pz), Vector3(1.1, 0.5, 1.1), STONE_TRIM)

	# Архитрав и фриз портика
	b.box(Vector3(0.0, by + 9.4, pz + 0.5), Vector3(14.4, 0.8, 2.6), STONE_TRIM)

	# Треугольный фронтон портика
	var f_mid_z := pz + 0.5
	var f_h := 3.2
	var f_w := 14.4
	# Строим треугольный фронтон скошенными боксами/треугольниками
	b.box(Vector3(0.0, by + 10.4, f_mid_z), Vector3(f_w - 1.0, 1.2, 2.4), STONE_MAIN)
	b.box(Vector3(0.0, by + 11.4, f_mid_z), Vector3(f_w - 5.0, 0.9, 2.4), STONE_MAIN)
	b.box(Vector3(0.0, by + 12.1, f_mid_z), Vector3(f_w - 9.5, 0.7, 2.4), STONE_MAIN)

	# Наклонные карнизы фронтона (левый и правый)
	var slope_basis_l := Basis(Vector3.FORWARD, 0.38)
	var slope_basis_r := Basis(Vector3.FORWARD, -0.38)
	b.box(Vector3(-3.8, by + 11.2, f_mid_z - 1.1), Vector3(8.0, 0.35, 0.5), STONE_TRIM, slope_basis_l)
	b.box(Vector3(3.8, by + 11.2, f_mid_z - 1.1), Vector3(8.0, 0.35, 0.5), STONE_TRIM, slope_basis_r)
	b.sphere(Vector3(0.0, by + 12.8, f_mid_z - 1.1), 0.35, STONE_TRIM, 4, 8)


# --- Купол ротонды ----------------------------------------------------------

func _build_dome(b: MeshBuilder) -> void:
	var dy := 10.4
	var dz := 2.5

	# Цилиндрический световой барабан под куполом
	b.cylinder(Vector3(0.0, dy + 1.6, dz), 4.8, 5.2, 3.2, STONE_MAIN, 16)
	b.cylinder(Vector3(0.0, dy + 3.3, dz), 5.4, 5.0, 0.4, STONE_TRIM, 16)

	# Арочные окна барабана (по кругу)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var ox := cos(a) * 4.85
		var oz := sin(a) * 4.85 + dz
		var basis := Basis(Vector3.UP, -a)
		b.box(Vector3(ox, dy + 1.8, oz), Vector3(1.2, 1.8, 0.2), GLASS_WINDOW, basis)

	# Медный купол (благородная патина)
	b.sphere(Vector3(0.0, dy + 4.6, dz), 4.6, DOME_COPPER, 6, 16, 0.9)
	# Рёбра купола
	b.cylinder(Vector3(0.0, dy + 6.6, dz), 4.4, 4.4, 0.2, DOME_ACCENT, 16)

	# Навершие: фонарик-бельведер и золотой шпиль
	b.cylinder(Vector3(0.0, dy + 8.5, dz), 1.1, 1.3, 1.4, STONE_TRIM, 8)
	b.cone(Vector3(0.0, dy + 9.6, dz), 1.4, 0.8, DOME_COPPER, 8)
	b.cylinder(Vector3(0.0, dy + 10.8, dz), 0.08, 0.16, 1.8, GOLD, 6)
	b.sphere(Vector3(0.0, dy + 11.8, dz), 0.28, GOLD, 4, 6)


# --- Боковые галерейные крылья ----------------------------------------------

func _build_wings(b: MeshBuilder) -> void:
	var by := 0.9

	for s: float in [-1.0, 1.0]:
		var wx: float = s * 11.5
		var wz := 2.5

		# Корпус крыла (ниже центральной части)
		b.box(Vector3(wx, by + 3.0, wz), Vector3(9.0, 6.0, 9.6), STONE_MAIN)
		# Цоколь и карниз крыла
		b.box(Vector3(wx, by + 0.5, wz), Vector3(9.3, 1.0, 9.9), STONE_DARK)
		b.box(Vector3(wx, by + 6.2, wz), Vector3(9.5, 0.5, 10.1), STONE_TRIM)
		# Парапетная балюстрада крыши
		b.box(Vector3(wx, by + 6.8, wz), Vector3(9.0, 0.7, 9.6), STONE_TRIM)

		# Арочные окна крыла по фасаду (-Z)
		for fx: float in [-2.5, 0.0, 2.5]:
			var win_x := wx + fx
			b.box(Vector3(win_x, by + 3.0, wz - 4.85), Vector3(1.4, 3.0, 0.1), GLASS_WINDOW)
			b.box(Vector3(win_x, by + 4.7, wz - 4.85), Vector3(1.6, 0.4, 0.15), STONE_TRIM)


# --- Декор террасы (фонари и вазоны) ----------------------------------------

func _build_terrace_decor(b: MeshBuilder) -> void:
	# Два чугунных классических фонаря у подножия лестницы
	for s: float in [-1.0, 1.0]:
		var lx: float = s * 7.5
		var lz := -10.8
		b.cylinder(Vector3(lx, 0.4, lz), 0.35, 0.45, 0.8, STONE_BASE, 8)
		b.cylinder(Vector3(lx, 1.8, lz), 0.1, 0.14, 2.2, IRON_LAMP, 6)
		b.box(Vector3(lx, 3.0, lz), Vector3(0.5, 0.65, 0.5), LIGHT_GLOW)
		b.cone(Vector3(lx, 3.5, lz), 0.65, 0.35, IRON_LAMP, 4, Basis(Vector3.UP, PI * 0.25))


# --- Коллизия ---------------------------------------------------------------

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	# Коллизия центрального здания с портиком
	var cs_main := CollisionShape3D.new()
	var box_main := BoxShape3D.new()
	box_main.size = Vector3(15.0, 10.0, 15.0)
	cs_main.shape = box_main
	cs_main.position = Vector3(0.0, 5.5, 1.0)
	body.add_child(cs_main)

	# Коллизии боковых крыльев
	for s: float in [-1.0, 1.0]:
		var cs_wing := CollisionShape3D.new()
		var box_wing := BoxShape3D.new()
		box_wing.size = Vector3(9.5, 7.0, 10.0)
		cs_wing.shape = box_wing
		cs_wing.position = Vector3(s * 11.5, 4.0, 2.5)
		body.add_child(cs_wing)

	# Коллизия террасы (низкая ступень)
	var cs_ter := CollisionShape3D.new()
	var box_ter := BoxShape3D.new()
	box_ter.size = Vector3(28.0, 0.8, 20.0)
	cs_ter.shape = box_ter
	cs_ter.position = Vector3(0.0, 0.4, 0.0)
	body.add_child(cs_ter)
