extends Node3D
## Беседка «Эолова арфа» на склоне Машука. Порт _gazebo() (citygen.js:869-891).
##
## Шесть колонн по кругу и конусная крыша. Коллизия — по колоннам, а не
## сплошным цилиндром: в оригинале под крышу можно зайти между колонн
## (addPropAABB с overhead-клиренсом на уровне крыши).

const COLUMN_COUNT := 6
const COLUMN_RADIUS := 1.7
const COLUMN_H := 2.6
const COLUMN_COLOR := Color("#e8e0d0")
const ROOF_COLOR := Color("#7a8a5a")


func _ready() -> void:
	var b := MeshBuilder.new()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	for i in COLUMN_COUNT:
		var a := TAU * float(i) / COLUMN_COUNT
		var pos := Vector3(cos(a) * COLUMN_RADIUS, COLUMN_H * 0.5, sin(a) * COLUMN_RADIUS)
		b.cylinder(pos, 0.18, 0.22, COLUMN_H, COLUMN_COLOR, 6)

		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.22
		cyl.height = COLUMN_H
		shape.shape = cyl
		shape.position = pos
		body.add_child(shape)

	b.cone(Vector3(0.0, COLUMN_H + 0.8, 0.0), 2.6, 1.6, ROOF_COLOR, 8)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = preload("res://fx/materials/mat_palette.tres")
	add_child(mi)
