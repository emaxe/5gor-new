extends Node3D
## Озеро Провал. Порт _lakeProval() (citygen.js:1483-1518): голубая вода в
## неглубоком кратере, каменный бортик по кругу и столбики ограждения —
## в оригинале это именно так (плоский диск воды + torus-бортик + 26
## столбиков), без отдельно смоделированного грота-тоннеля. Число столбиков
## снижено с 26 до 12 — планка low-poly car_mesh_builder.gd.
##
## Локальные координаты: (0,0,0) — центр озера на уровне земли; мировую
## позицию ставит вызывающий код. Радиус коллайдера (26 м) — как в оригинале:
## вся площадка вокруг воды непроезжая.

const WATER := Color("#33a8ff")
const DEPTH := Color("#0e5a9e")
const RIM := Color("#9a9a90")
const POST := Color("#8a8a84")

const WATER_R := 24.0
const RIM_R := 24.4
const POST_R := 24.6
const POST_COUNT := 12
const COLLIDER_R := 26.0


func _ready() -> void:
	var b := MeshBuilder.new()

	# Воронка кратера под водой — конус от радиуса воды до узкого дна. Верх
	# на 0.04 м ниже водной глади, чтобы крышки цилиндров не z-fighting'или.
	b.cylinder(Vector3(0.0, -3.05, 0.0), WATER_R, 6.0, 6.5, DEPTH, 20)
	# Водная гладь.
	b.cylinder(Vector3(0.0, 0.3, 0.0), WATER_R, WATER_R, 0.12, WATER, 24)

	# Каменный бортик кольцом (порт TorusGeometry — лентой по кругу).
	var rim_pts := PackedVector3Array()
	for i in 25:
		var a := TAU * i / 24.0
		rim_pts.append(Vector3(cos(a) * RIM_R, 0.5, sin(a) * RIM_R))
	b.ribbon(rim_pts, 1.1, RIM)

	# Столбики ограждения — вертикальные: ось цилиндра уже вдоль Y, доп.
	# поворот не нужен (Basis(Vector3.FORWARD, PI*0.5) укладывает цилиндр
	# набок — это идиома для КОЛЁС, а не для стоячих столбиков).
	for i in POST_COUNT:
		var a := TAU * i / POST_COUNT
		b.cylinder(Vector3(cos(a) * POST_R, 0.55, sin(a) * POST_R), 0.14, 0.16, 1.1,
			POST, 5)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = preload("res://fx/materials/mat_palette.tres")
	add_child(mi)

	_add_collision()


func _add_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = COLLIDER_R
	cyl.height = 2.0
	shape.shape = cyl
	shape.position = Vector3(0.0, 1.0, 0.0)
	body.add_child(shape)
	add_child(body)
