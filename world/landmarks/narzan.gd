extends Node3D
## Нарзанные ванны: цилиндрический корпус галереи под куполом, окружённый
## колоннадой. Порт _narzan() (citygen.js:2022-2044) — пропорции (включая
## высоту купола) взяты из оригинала как есть, гранёность снижена для
## low-poly (10 граней корпуса вместо 14, сфера — дефолтные rings/segments
## MeshBuilder).
##
## Локальные координаты вокруг (0,0,0), мировую позицию выставляет
## вызывающий код.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")
const BODY_COLOR := Color("#e8dcc8")
const FINIAL_COLOR := Color("#666666")

const BASE_Y := 0.15
const BODY_H := 12.0
const BODY_R := 13.5
const DOME_R := 13.0
const COL_RADIUS := 12.6
const COL_COUNT := 8


func _ready() -> void:
	var b := MeshBuilder.new()
	var body_center_y := BASE_Y + BODY_H * 0.5
	b.cylinder(Vector3(0.0, body_center_y, 0.0), BODY_R - 0.5, BODY_R + 0.5, BODY_H,
		BODY_COLOR, 10)

	var dome_y := BASE_Y + BODY_H
	# Полная сфера, утопленная нижней половиной в корпус — виден только
	# верхний купол, силуэт идентичен половине сферы оригинала.
	b.sphere(Vector3(0.0, dome_y, 0.0), DOME_R, BODY_COLOR)

	var col_y := BASE_Y + BODY_H * 0.5 + 0.7
	for i in COL_COUNT:
		var a := TAU * float(i) / float(COL_COUNT)
		b.cylinder(Vector3(cos(a) * COL_RADIUS, col_y, sin(a) * COL_RADIUS),
			0.6, 0.7, BODY_H + 1.4, BODY_COLOR, 6)

	b.cylinder(Vector3(0.0, dome_y + DOME_R + 0.7, 0.0), 0.35, 0.35, 1.4, FINIAL_COLOR, 6)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = PALETTE_MAT
	add_child(mi)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = BODY_R + 0.5
	shape.height = BODY_H
	cs.shape = shape
	cs.position = Vector3(0.0, body_center_y, 0.0)
	body.add_child(cs)
	add_child(body)
