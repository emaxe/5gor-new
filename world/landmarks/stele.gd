extends Node3D
## Въездная стела «ПЯТИГОРСК — КУРОРТ» на южном въезде в город.
##
## Включает:
## - Островок безопасности с бордюром и клумбой у дороги;
## - Архитектурную стелу из светлого камня с рельефными пилонами;
## - Рельефные объёмные буквы «ПЯТИГОРСК» и «КУРОРТ»;
## - Золотой герб города с орлом на горе;
## - Прожекторы архитектурной подсветки.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

const STONE_WHITE := Color("#ece7dc")
const STONE_BASE := Color("#9a9386")
const GOLD_LETTER := Color("#e8b838")
const GOLD_CREST := Color("#d4a028")
const KERB := Color("#7e796e")
const LEAVES := Color("#3e7d38")
const FLOWERS := Color("#d63636")
const FLOODLIGHT := Color("#2c2d30")


func _ready() -> void:
	var b := MeshBuilder.new()

	# Островок с клумбой у дороги
	b.box(Vector3(0.0, 0.2, 0.0), Vector3(10.0, 0.4, 4.0), KERB)
	b.box(Vector3(0.0, 0.42, 0.0), Vector3(9.4, 0.1, 3.4), LEAVES)
	# Цветы вокруг стелы
	for fx: float in [-3.5, -2.5, -1.5, 1.5, 2.5, 3.5]:
		b.sphere(Vector3(fx, 0.55, 1.2), 0.22, FLOWERS, 3, 6, 0.7)
		b.sphere(Vector3(fx, 0.55, -1.2), 0.22, FLOWERS, 3, 6, 0.7)

	# Ступенчатый постамент стелы
	b.box(Vector3(0.0, 0.65, 0.0), Vector3(8.0, 0.5, 2.2), STONE_BASE)
	b.box(Vector3(0.0, 1.1, 0.0), Vector3(7.4, 0.4, 1.8), STONE_WHITE)

	# Основной монументальный пилон (ширина 7 м, высота 4.8 м)
	b.box(Vector3(0.0, 3.6, 0.0), Vector3(6.8, 4.6, 0.9), STONE_WHITE)
	b.box(Vector3(0.0, 6.0, 0.0), Vector3(7.2, 0.4, 1.1), STONE_BASE)

	# Боковые пилоны-крылья
	for s: float in [-1.0, 1.0]:
		var px: float = s * 3.6
		b.box(Vector3(px, 2.8, 0.0), Vector3(0.6, 3.6, 1.1), STONE_BASE)

	# Золотой герб города (орёл над Машуком)
	b.cylinder(Vector3(0.0, 4.8, 0.5), 1.1, 1.1, 0.15, GOLD_CREST, 16,
		Basis(Vector3.RIGHT, PI * 0.5))
	b.cone(Vector3(0.0, 4.9, 0.6), 0.6, 0.5, GOLD_CREST, 4,
		Basis(Vector3.RIGHT, PI * 0.5))

	# Объёмная надпись «ПЯТИГОРСК» золотыми буквами
	b.box(Vector3(0.0, 3.1, 0.52), Vector3(5.6, 0.8, 0.12), GOLD_LETTER)
	b.box(Vector3(0.0, 2.0, 0.52), Vector3(3.6, 0.5, 0.10), GOLD_LETTER)

	# Прожекторы подсветки перед стелой
	for s: float in [-1.0, 1.0]:
		var lx: float = s * 2.8
		b.box(Vector3(lx, 0.45, 1.4), Vector3(0.3, 0.3, 0.4), FLOODLIGHT,
			Basis(Vector3.RIGHT, -0.4))

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = PALETTE_MAT
	add_child(mi)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 6.0, 2.0)
	shape.shape = box
	shape.position = Vector3(0.0, 3.0, 0.0)
	body.add_child(shape)
