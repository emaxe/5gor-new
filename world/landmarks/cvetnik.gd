extends Node3D
## Парк «Цветник»: круглая мощёная площадь с фонтаном, клумбами, скамьями,
## вазонами у входов и перголой в углу. Порт _parkCvetnik() (citygen.js:1334-1417),
## упрощённый под low-poly (4 клумбы/скамьи вместо 8 — оригинал читался
## одинаково плотным кольцом что при 4, что при 8 объектах на таком масштабе;
## текстура мощения заменена плоским цветом).
##
## Локальные координаты — вокруг фонтана (0,0,0), мировую позицию и разворот
## выставляет вызывающий код.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

const STONE := Color("#b8b8b0")
const STONE_D := Color("#a4a49c")
const KERB := Color("#cac4b6")
const WOOD := Color("#8a6a44")
const BENCH_LEG := Color("#5a5a54")
const PLANTER_STONE := Color("#bdb4a2")
const PLANTER_RIM := Color("#d2cabb")
const PLANTER_LEAF := Color("#4f8a3f")
const WATER := Color("#66ccff")
const FLOWERS: Array[Color] = [
	Color("#d94f4f"), Color("#e8b84a"), Color("#b06ad9"), Color("#5aa85a"),
]

const PLAZA_R := 11.0
const RING_R := 12.8
const BENCH_R := 15.8


func _ready() -> void:
	var b := MeshBuilder.new()
	b.cylinder(Vector3.ZERO, PLAZA_R, PLAZA_R, 0.18, KERB, 24)
	_add_fountain(b)
	for k in 4:
		var a := (k * 90.0 + 45.0) * PI / 180.0
		_add_flower_bed(b, cos(a) * RING_R, sin(a) * RING_R, -a - PI * 0.5, FLOWERS[k])
		_add_bench(b, cos(a) * BENCH_R, sin(a) * BENCH_R, -a - PI * 0.5)
	_add_planter(b, PLAZA_R + 1.2, 0.0, 0.0)
	_add_planter(b, -(PLAZA_R + 1.2), 0.0, PI)
	_add_pergola(b, -14.0, 14.0)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = PALETTE_MAT
	add_child(mi)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = PLAZA_R
	shape.height = 2.0
	cs.shape = shape
	cs.position = Vector3(0.0, 1.0, 0.0)
	body.add_child(cs)
	add_child(body)


## Ступенчатый фонтан: ступень, чаша, тумба, две тарелки, шар, три диска воды.
func _add_fountain(b: MeshBuilder) -> void:
	b.cylinder(Vector3(0.0, 0.32, 0.0), 8.0, 8.0, 0.34, KERB, 28)
	b.cylinder(Vector3(0.0, 0.89, 0.0), 7.0, 7.0, 0.8, STONE, 28)
	b.cylinder(Vector3(0.0, 1.89, 0.0), 1.2, 1.2, 1.2, STONE, 12)
	b.cylinder(Vector3(0.0, 2.69, 0.0), 3.0, 1.3, 0.4, STONE, 18)
	b.cylinder(Vector3(0.0, 3.59, 0.0), 0.5, 0.7, 1.4, STONE, 10)
	b.cylinder(Vector3(0.0, 4.46, 0.0), 1.6, 0.75, 0.34, STONE, 14)
	b.sphere(Vector3(0.0, 4.95, 0.0), 0.36, STONE_D)
	b.cylinder(Vector3(0.0, 1.31, 0.0), 6.5, 6.5, 0.06, WATER, 28)
	b.cylinder(Vector3(0.0, 2.91, 0.0), 2.85, 2.85, 0.06, WATER, 20)
	b.cylinder(Vector3(0.0, 4.65, 0.0), 1.45, 1.45, 0.06, WATER, 16)
	b.cylinder(Vector3(0.0, 5.55, 0.0), 0.10, 0.18, 1.5, Color("#eaf6ff"), 6)


func _add_flower_bed(b: MeshBuilder, x: float, z: float, rot_y: float, color: Color) -> void:
	var basis := Basis(Vector3.UP, rot_y)
	b.box(Vector3(x, 0.30, z), Vector3(5.2, 0.7, 1.9), KERB, basis)
	b.box(Vector3(x, 0.72, z), Vector3(4.6, 0.24, 1.34), color, basis)
	b.sphere(Vector3(x, 0.88, z), 0.55, color, 4, 8, 0.6)


## Спинка на локальном -z, то есть в мир смотрит по (sin rotY, cos rotY) —
## сидящий обращён к фонтану (порт _bench(), citygen.js:1447-1457).
func _add_bench(b: MeshBuilder, x: float, z: float, rot_y: float) -> void:
	var basis := Basis(Vector3.UP, rot_y)
	b.box(Vector3(x, 0.0, z) + basis * Vector3(0.0, 0.55, 0.0), Vector3(1.8, 0.1, 0.55), WOOD, basis)
	b.box(Vector3(x, 0.0, z) + basis * Vector3(0.0, 0.8, -0.26), Vector3(1.8, 0.55, 0.1), WOOD, basis)
	b.box(Vector3(x, 0.0, z) + basis * Vector3(0.0, 0.25, 0.0), Vector3(1.5, 0.5, 0.1), BENCH_LEG, basis)


func _add_planter(b: MeshBuilder, x: float, z: float, hue_shift: float) -> void:
	b.cylinder(Vector3(x, 0.07, z), 0.28, 0.34, 0.14, PLANTER_STONE, 8)
	b.cylinder(Vector3(x, 0.37, z), 0.46, 0.30, 0.46, PLANTER_STONE, 8)
	b.cylinder(Vector3(x, 0.66, z), 0.52, 0.48, 0.13, PLANTER_RIM, 8)
	b.sphere(Vector3(x, 0.74, z), 0.44, PLANTER_LEAF, 4, 8, 0.5)
	b.sphere(Vector3(x, 0.9, z), 0.16, FLOWERS[int(hue_shift) % FLOWERS.size()], 3, 6)


## Деревянная пергола в дальнем углу квартала — 4 стойки и две продольные балки.
func _add_pergola(b: MeshBuilder, x: float, z: float) -> void:
	for gx in [-2.6, 2.6]:
		for gz in [-1.5, 1.5]:
			b.box(Vector3(x + gx, 1.40, z + gz), Vector3(0.26, 3.0, 0.26), WOOD)
	for gz in [-1.5, 1.5]:
		b.box(Vector3(x, 3.01, z + gz), Vector3(6.0, 0.22, 0.30), WOOD)
	_add_bench(b, x, z - 2.4, 0.0)
