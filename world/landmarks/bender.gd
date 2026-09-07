extends Node3D
## Памятник Остапу Бендеру у входа в Провал (скульптор С. Алипов, 2008 г.).
## Великий комбинатор в капитанской фуражке и длинном шарфе продаёт билеты
## «на ремонт Провала, чтобы не слишком проваливался», опираясь на заветный
## 12-й стул мадам Петуховой.
##
## Локальные координаты: (0,0,0) — уровень мостовой площади перед входом.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

const BRONZE_DARK := Color("#4d3e28")
const BRONZE_MAIN := Color("#735f3d")
const BRONZE_LIGHT := Color("#9c8255")
const BRONZE_SHINE := Color("#bf9f67")
const CHAIR_WOOD := Color("#592d15")
const CHAIR_CUSHION := Color("#732219")
const TICKET_PAPER := Color("#ede4cb")
const PLINTH_STONE := Color("#5a5852")


func _ready() -> void:
	var b := MeshBuilder.new()

	_build_plinth(b)
	_build_chair(b)
	_build_ostap(b)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = PALETTE_MAT
	add_child(mi)

	_build_collision()


## Бронзово-каменный плинтус (постамент вровень с брусчаткой площади)
func _build_plinth(b: MeshBuilder) -> void:
	b.box(Vector3(0.0, 0.08, 0.0), Vector3(2.2, 0.16, 1.8), PLINTH_STONE)
	b.box(Vector3(0.0, 0.18, 0.0), Vector3(2.0, 0.06, 1.6), BRONZE_DARK)


## Легендарный 12-й стул работы мастера Гамбса
func _build_chair(b: MeshBuilder) -> void:
	var cx := 0.45
	var cz := 0.0
	var cy := 0.2

	# Сиденье стула (мягкая трапециевидная подушка)
	b.box(Vector3(cx, cy + 0.44, cz), Vector3(0.48, 0.08, 0.48), CHAIR_WOOD)
	b.box(Vector3(cx, cy + 0.48, cz), Vector3(0.44, 0.04, 0.44), CHAIR_CUSHION)

	# 4 точёные изогнутые ножки стула
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var nx := cx + sx * 0.19
			var nz := cz + sz * 0.19
			b.cylinder(Vector3(nx, cy + 0.22, nz), 0.025, 0.035, 0.44, CHAIR_WOOD, 5)

	# Царговый круговой обод под сиденьем
	b.cylinder(Vector3(cx, cy + 0.38, cz), 0.22, 0.22, 0.05, CHAIR_WOOD, 8)
	# Проножки (крестовина внизу для прочности)
	b.box(Vector3(cx, cy + 0.15, cz), Vector3(0.38, 0.03, 0.03), CHAIR_WOOD)
	b.box(Vector3(cx, cy + 0.15, cz), Vector3(0.03, 0.03, 0.38), CHAIR_WOOD)

	# Гнутая полукруглая спинка венского стула (сзади, +Z)
	var bz := cz - 0.20
	# Две вертикальные боковые стойки спинки
	b.cylinder(Vector3(cx - 0.19, cy + 0.72, bz), 0.028, 0.028, 0.52, CHAIR_WOOD, 5)
	b.cylinder(Vector3(cx + 0.19, cy + 0.72, bz), 0.028, 0.028, 0.52, CHAIR_WOOD, 5)
	# Верхняя полукруглая дуга спинки
	b.box(Vector3(cx, cy + 0.98, bz), Vector3(0.44, 0.06, 0.04), CHAIR_WOOD)
	# Внутренний декоративный резной веер спинки
	b.box(Vector3(cx, cy + 0.72, bz), Vector3(0.12, 0.40, 0.02), CHAIR_WOOD)


## Фигура Остапа Сулеймана Берта Мария Бендер-бея
func _build_ostap(b: MeshBuilder) -> void:
	var ox := -0.25
	var oz := 0.05
	var oy := 0.2

	# Ноги и брюки (свободная непринуждённая поза с опорой на правую ногу)
	# Правая опорная нога
	b.cylinder(Vector3(ox + 0.12, oy + 0.45, oz - 0.05), 0.09, 0.11, 0.9, BRONZE_DARK, 6)
	# Левая нога слегка согнута
	b.cylinder(Vector3(ox - 0.12, oy + 0.42, oz + 0.08), 0.09, 0.10, 0.85, BRONZE_DARK, 6,
		Basis(Vector3.RIGHT, 0.15))
	# Штиблеты на ногах
	b.box(Vector3(ox + 0.12, oy + 0.06, oz - 0.02), Vector3(0.14, 0.10, 0.26), BRONZE_MAIN)
	b.box(Vector3(ox - 0.12, oy + 0.06, oz + 0.12), Vector3(0.14, 0.10, 0.25), BRONZE_MAIN)

	# Торс: франтоватый расстёгнутый пиджак и жилет
	b.box(Vector3(ox, oy + 1.15, oz), Vector3(0.42, 0.55, 0.28), BRONZE_MAIN)
	# Лацканы пиджака
	b.box(Vector3(ox, oy + 1.25, oz + 0.14), Vector3(0.32, 0.35, 0.04), BRONZE_LIGHT)
	# Свисающие полы пиджака
	b.box(Vector3(ox, oy + 0.84, oz), Vector3(0.44, 0.22, 0.30), BRONZE_MAIN)

	# Правая рука Бендера опирается на спинку 12-го стула!
	var arm_r_p1 := Vector3(ox + 0.22, oy + 1.35, oz)
	var arm_r_p2 := Vector3(0.28, oy + 1.18, oz - 0.18)
	_build_limb(b, arm_r_p1, arm_r_p2, 0.07, BRONZE_MAIN)
	# Кисть правой руки лежит на дуге стула
	b.sphere(Vector3(0.32, oy + 1.18, oz - 0.18), 0.06, BRONZE_SHINE, 4, 6)

	# Левая рука согнута в локте, держит папку с билетами
	var arm_l_elbow := Vector3(ox - 0.26, oy + 1.10, oz)
	_build_limb(b, Vector3(ox - 0.20, oy + 1.35, oz), arm_l_elbow, 0.07, BRONZE_MAIN)
	_build_limb(b, arm_l_elbow, Vector3(ox - 0.15, oy + 1.15, oz + 0.25), 0.06, BRONZE_MAIN)

	# Квитанционная книжка «Билеты на Провал» под левой рукой
	b.box(Vector3(ox - 0.18, oy + 1.18, oz + 0.24), Vector3(0.18, 0.26, 0.08), BRONZE_DARK,
		Basis(Vector3.UP, 0.3))
	# Билет в пальцах (вытянут вперёд навстречу туристу)
	b.box(Vector3(ox - 0.08, oy + 1.22, oz + 0.30), Vector3(0.08, 0.04, 0.14), TICKET_PAPER,
		Basis(Vector3.UP, 0.2))

	# Знаменитый длинный шарф вокруг шеи
	# Узел шарфа на шее
	b.cylinder(Vector3(ox, oy + 1.48, oz), 0.13, 0.14, 0.12, BRONZE_LIGHT, 8)
	# Концы шарфа эффектно переброшены через левое плечо и свисают на спину
	b.box(Vector3(ox - 0.14, oy + 1.25, oz - 0.16), Vector3(0.12, 0.42, 0.05), BRONZE_LIGHT,
		Basis(Vector3.RIGHT, 0.1))

	# Шея и гордо поднятая голова Бендера с лёгкой усмешкой
	b.cylinder(Vector3(ox, oy + 1.54, oz), 0.07, 0.08, 0.12, BRONZE_MAIN, 6)
	b.sphere(Vector3(ox, oy + 1.68, oz + 0.03), 0.14, BRONZE_SHINE, 5, 7)
	# Волевой подбородок и нос с горбинкой
	b.cone(Vector3(ox, oy + 1.67, oz + 0.17), 0.04, 0.07, BRONZE_SHINE, 4,
		Basis(Vector3.RIGHT, PI * 0.5))

	# Знаменитая фуражка-капитанка с козырьком
	# Околыш фуражки
	b.cylinder(Vector3(ox, oy + 1.78, oz + 0.02), 0.14, 0.16, 0.08, BRONZE_MAIN, 8,
		Basis(Vector3.RIGHT, -0.15))
	# Блин / тулья фуражки
	b.cylinder(Vector3(ox, oy + 1.84, oz + 0.01), 0.19, 0.15, 0.05, BRONZE_LIGHT, 8,
		Basis(Vector3.RIGHT, -0.15))
	# Глянцевый лакированный козырёк спереди
	b.box(Vector3(ox, oy + 1.76, oz + 0.17), Vector3(0.18, 0.02, 0.10), BRONZE_DARK,
		Basis(Vector3.RIGHT, -0.35))


func _build_limb(b: MeshBuilder, p1: Vector3, p2: Vector3, r: float, col: Color) -> void:
	var mid := (p1 + p2) * 0.5
	var seg_len := p1.distance_to(p2)
	var dir := (p2 - p1).normalized()
	var axis := Vector3.UP.cross(dir)
	var basis := Basis(axis.normalized(), Vector3.UP.angle_to(dir)) \
		if axis.length() > 0.001 else Basis.IDENTITY
	b.cylinder(mid, r, r, seg_len, col, 5, basis)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 2.0, 1.4)
	shape.shape = box
	shape.position = Vector3(0.0, 1.0, 0.0)
	body.add_child(shape)
