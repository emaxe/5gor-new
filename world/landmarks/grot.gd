extends Node3D
## Грот Лермонтова — романтическая каменная пещера на отроге горы Горячей (1829 г.).
##
## Включает:
## - Скальный массив горы с живописными каменными уступами;
## - Арочный свод входа в грот, сложенный из дикого камня;
## - Внутреннюю пещеру с каменной скамьёй, где Лермонтов наблюдал за «водяным обществом»;
## - Смотровую террасу с кованой узорной решёткой;
## - Памятную бронзовую доску поэту.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

# Палитра машукского камня и скал
const CLIFF_BASE := Color("#7a756b")
const CLIFF_LIGHT := Color("#968f82")
const ROCK_LEDGE := Color("#b0a89a")
const CAVE_INTERIOR := Color("#1c1b1a")
const BENCH_STONE := Color("#8a8376")
const BRONZE_PLAQUE := Color("#b58a36")
const IRON_RAILING := Color("#2c2d30")
const PAVE_STONE := Color("#aba394")


func _ready() -> void:
	var b := MeshBuilder.new()

	_build_rock_cliff(b)
	_build_grotto_cave(b)
	_build_terrace_and_railing(b)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = PALETTE_MAT
	add_child(mi)

	_build_collision()


# --- Скальный массив горы ---------------------------------------------------

func _build_rock_cliff(b: MeshBuilder) -> void:
	# Массив скалы вокруг и позади грота (+Z — глубь скалы)
	b.box(Vector3(0.0, 3.5, 4.0), Vector3(14.0, 7.0, 8.0), CLIFF_BASE)
	b.box(Vector3(0.0, 6.2, 3.0), Vector3(12.0, 4.0, 7.0), CLIFF_LIGHT)
	b.box(Vector3(0.0, 8.5, 2.0), Vector3(9.0, 3.0, 6.0), ROCK_LEDGE)

	# Боковые скальные выступы, обрамляющие вход
	for s in [-1.0, 1.0]:
		var sx: float = s * 4.8
		b.cylinder(Vector3(sx, 3.0, 1.0), 2.2, 2.8, 6.0, CLIFF_BASE, 7)
		b.cylinder(Vector3(sx * 0.8, 5.5, 1.5), 1.6, 2.2, 4.0, CLIFF_LIGHT, 6)


# --- Пещера грота -----------------------------------------------------------

func _build_grotto_cave(b: MeshBuilder) -> void:
	# Тёмная полость грота
	b.box(Vector3(0.0, 2.2, 1.8), Vector3(5.6, 4.2, 3.8), CAVE_INTERIOR)

	# Арочный портал входа из дикого камня (фасад смотрит на -Z)
	for s in [-1.0, 1.0]:
		b.box(Vector3(s * 2.8, 2.4, 0.0), Vector3(1.8, 4.8, 1.4), ROCK_LEDGE)

	# Каменная перемычка и арка над входом
	b.box(Vector3(0.0, 4.6, 0.0), Vector3(6.4, 1.4, 1.6), ROCK_LEDGE)
	b.cylinder(Vector3(0.0, 3.6, 0.0), 2.0, 2.0, 1.6, CAVE_INTERIOR, 10,
		Basis(Vector3.FORWARD, PI * 0.5))

	# Каменная скамья внутри грота у задней стены
	b.box(Vector3(0.0, 0.55, 3.0), Vector3(3.6, 0.6, 1.0), BENCH_STONE)

	# Бронзовая мемориальная доска справа от входа
	b.box(Vector3(2.85, 2.6, -0.72), Vector3(0.9, 1.2, 0.06), BRONZE_PLAQUE)


# --- Смотровая терраса и чугунная ограда ------------------------------------

func _build_terrace_and_railing(b: MeshBuilder) -> void:
	# Мощёная площадка перед входом (Z от 0 до -4)
	b.box(Vector3(0.0, 0.1, -2.0), Vector3(9.0, 0.2, 4.2), PAVE_STONE)

	# Кованая ажурная ограда по внешнему краю террасы (-Z)
	for i in range(-4, 5):
		var rx := float(i) * 1.0
		b.cylinder(Vector3(rx, 0.6, -4.0), 0.04, 0.04, 1.0, IRON_RAILING, 4)

	# Верхний поручень и нижняя балка решётки
	b.box(Vector3(0.0, 1.1, -4.0), Vector3(8.2, 0.08, 0.08), IRON_RAILING)
	b.box(Vector3(0.0, 0.2, -4.0), Vector3(8.2, 0.08, 0.08), IRON_RAILING)


# --- Коллизия ---------------------------------------------------------------

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	# Коллизия скалы позади
	var cs_back := CollisionShape3D.new()
	var box_back := BoxShape3D.new()
	box_back.size = Vector3(14.0, 8.0, 7.0)
	cs_back.shape = box_back
	cs_back.position = Vector3(0.0, 4.0, 4.5)
	body.add_child(cs_back)

	# Боковые скальные стены входа
	for s in [-1.0, 1.0]:
		var cs_side := CollisionShape3D.new()
		var box_side := BoxShape3D.new()
		box_side.size = Vector3(3.6, 5.0, 4.0)
		cs_side.shape = box_side
		cs_side.position = Vector3(s * 4.2, 2.5, 1.0)
		body.add_child(cs_side)
