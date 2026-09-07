extends Node3D
## Беседка «Эолова арфа» на Михайловском отроге горы Машук (архитектор Дж. Бернардацци, 1831 г.).
##
## Включает:
## - Скальный массив подножия (отрог Машука с уступами);
## - Круглый 3-ступенчатый каменный стилобат;
## - 8 изящных колонн тосканского ордера по кругу;
## - Классический антаблемент с профилированным карнизом;
## - Белый купол с фигурным шпилем;
## - Музыкальный инструмент (эолову арфу) на центральной тумбе;
## - Смотровую площадку с балюстрадой и панорамным видом на Пятигорск.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

# Палитра белого камня и скал
const ROCK_BASE := Color("#7e796e")
const ROCK_LIGHT := Color("#9a9486")
const STONE_CREPIDA := Color("#d6cfbe")
const STONE_COL := Color("#f2ede2")
const STONE_CORNICE := Color("#dfd8c8")
const DOME_COLOR := Color("#8a9e78")
const HARP_GOLD := Color("#d4a838")
const HARP_DARK := Color("#3a3024")
const STRINGS := Color("#eae4d6")

const COL_COUNT := 8
const COL_RADIUS := 2.6
const COL_H := 3.6


func _ready() -> void:
	var b := MeshBuilder.new()

	_build_rock_pedestal(b)
	_build_rotunda(b)
	_build_aeolian_harp(b)
	_build_viewpoint_terrace(b)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = PALETTE_MAT
	add_child(mi)

	_build_collision()


# --- Скальный отрог Машука --------------------------------------------------

func _build_rock_pedestal(b: MeshBuilder) -> void:
	# Массив скалы, на котором стоит ротонда (нависает над склоном)
	b.cylinder(Vector3(0.0, 0.4, 0.0), 5.4, 6.2, 0.8, ROCK_BASE, 12)
	b.cylinder(Vector3(0.0, 1.0, 0.0), 4.8, 5.5, 0.6, ROCK_LIGHT, 10)

	# Скальные уступы вокруг
	b.cylinder(Vector3(-3.2, 0.5, 1.5), 2.2, 2.8, 1.0, ROCK_BASE, 7)
	b.cylinder(Vector3(3.0, 0.4, -2.0), 2.0, 2.5, 0.8, ROCK_LIGHT, 7)


# --- Ротонда ----------------------------------------------------------------

func _build_rotunda(b: MeshBuilder) -> void:
	var ry := 1.3

	# 3-ступенчатый круглый каменный стилобат (крепида)
	b.cylinder(Vector3(0.0, ry + 0.15, 0.0), 4.0, 4.3, 0.3, STONE_CREPIDA, 20)
	b.cylinder(Vector3(0.0, ry + 0.45, 0.0), 3.6, 3.8, 0.3, STONE_CREPIDA, 20)
	b.cylinder(Vector3(0.0, ry + 0.70, 0.0), 3.2, 3.4, 0.2, STONE_COL, 20)

	var base_y := ry + 0.8

	# 8 тосканских колонн по кругу
	for i in COL_COUNT:
		var a := TAU * float(i) / float(COL_COUNT)
		var cpos := Vector3(cos(a) * COL_RADIUS, base_y + COL_H * 0.5, sin(a) * COL_RADIUS)
		# База колонны
		b.cylinder(Vector3(cpos.x, base_y + 0.15, cpos.z), 0.3, 0.36, 0.3, STONE_CORNICE, 8)
		# Ствол
		b.cylinder(cpos, 0.22, 0.26, COL_H, STONE_COL, 8)
		# Капитель
		b.cylinder(Vector3(cpos.x, base_y + COL_H - 0.15, cpos.z), 0.32, 0.24, 0.3, STONE_CORNICE, 8)

	var roof_y := base_y + COL_H

	# Антаблемент (кольцо архитрава и карниза)
	b.cylinder(Vector3(0.0, roof_y + 0.3, 0.0), 3.3, 3.1, 0.6, STONE_CORNICE, 20)
	b.cylinder(Vector3(0.0, roof_y + 0.7, 0.0), 3.4, 3.3, 0.2, STONE_COL, 20)

	# Классический купол ротонды (полусфера)
	b.sphere(Vector3(0.0, roof_y + 1.2, 0.0), 3.1, DOME_COLOR, 6, 20, 0.6)
	b.cylinder(Vector3(0.0, roof_y + 2.4, 0.0), 1.2, 2.0, 0.8, DOME_COLOR, 16)

	# Шпиль на вершине купола
	b.cylinder(Vector3(0.0, roof_y + 3.2, 0.0), 0.06, 0.14, 1.4, HARP_GOLD, 6)
	b.sphere(Vector3(0.0, roof_y + 3.9, 0.0), 0.22, HARP_GOLD, 4, 6)


# --- Эолова арфа (музыкальный инструмент внутри) ----------------------------

func _build_aeolian_harp(b: MeshBuilder) -> void:
	var hy := 2.1

	# Центральная каменная тумба-пьедестал
	b.cylinder(Vector3(0.0, hy + 0.45, 0.0), 0.55, 0.65, 0.9, STONE_CORNICE, 8)

	# Корпус арфы (дерево и латунь)
	b.box(Vector3(0.0, hy + 1.4, 0.0), Vector3(0.35, 1.0, 0.7), HARP_DARK)
	# Рама арфы (стойки и верхняя дуга)
	b.cylinder(Vector3(0.0, hy + 1.5, -0.3), 0.05, 0.05, 1.2, HARP_GOLD, 6)
	b.cylinder(Vector3(0.0, hy + 1.5, 0.3), 0.05, 0.05, 1.2, HARP_GOLD, 6)
	b.cylinder(Vector3(0.0, hy + 2.1, 0.0), 0.06, 0.06, 0.65, HARP_GOLD, 6,
		Basis(Vector3.FORWARD, PI * 0.5))

	# Струны арфы (натянуты вертикально)
	for ox: float in [-0.15, -0.05, 0.05, 0.15]:
		b.cylinder(Vector3(0.0, hy + 1.45, ox), 0.015, 0.015, 0.9, STRINGS, 4)


# --- Смотровая площадка с балюстрадой ---------------------------------------

func _build_viewpoint_terrace(b: MeshBuilder) -> void:
	# Полукруглая смотровая терраса, нависающая над городом в сторону -Z
	var ty := 1.2
	b.cylinder(Vector3(0.0, ty + 0.1, -2.5), 4.8, 5.2, 0.2, STONE_CREPIDA, 16)

	# Белая балюстрада по дуге смотровой площадки
	for i in range(-5, 6):
		var a := float(i) * 0.22 - PI * 0.5
		var bx := cos(a) * 4.6
		var bz := sin(a) * 4.6 - 2.5
		b.cylinder(Vector3(bx, ty + 0.55, bz), 0.12, 0.14, 0.7, STONE_COL, 6)

	# Поручень балюстрады
	for i in range(-4, 5):
		var a := float(i) * 0.22 - PI * 0.5
		var px := cos(a) * 4.6
		var pz := sin(a) * 4.6 - 2.5
		b.box(Vector3(px, ty + 0.95, pz), Vector3(1.1, 0.12, 0.25), STONE_CORNICE,
			Basis(Vector3.UP, -a))


# --- Коллизия ---------------------------------------------------------------

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	# Коллизии колонн по кругу (внутри свободно для прохода)
	for i in COL_COUNT:
		var a := TAU * float(i) / float(COL_COUNT)
		var cpos := Vector3(cos(a) * COL_RADIUS, 2.1 + COL_H * 0.5, sin(a) * COL_RADIUS)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.35
		cyl.height = COL_H + 0.8
		cs.shape = cyl
		cs.position = cpos
		body.add_child(cs)

	# Коллизия центральной арфы
	var cs_harp := CollisionShape3D.new()
	var cyl_harp := CylinderShape3D.new()
	cyl_harp.radius = 0.7
	cyl_harp.height = 2.4
	cs_harp.shape = cyl_harp
	cs_harp.position = Vector3(0.0, 2.5, 0.0)
	body.add_child(cs_harp)
