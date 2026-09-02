extends Node3D
## Въездная стела «ПЯТИГОРСК — КУРОРТ». Порт _cityStela() (citygen.js:1307-1333).
##
## Локальные координаты: (0,0,0) — уровень земли, мировую позицию/высоту
## ставит вызывающий код (LandmarkLayer).

const STONE := Color("#d8d0c0")
const GOLD := Color("#f2c12e")


func _ready() -> void:
	var b := MeshBuilder.new()
	b.box(Vector3(0.0, 2.25, 0.0), Vector3(6.4, 4.5, 0.8), STONE)
	b.box(Vector3(0.0, 4.8, 0.0), Vector3(7.2, 0.6, 1.0), GOLD)
	# Эмблема — плоский многогранный диск вместо THREE.CircleGeometry.
	b.cylinder(Vector3(0.0, 2.6, 0.42), 0.9, 0.9, 0.06, GOLD, 8,
		Basis(Vector3.RIGHT, PI * 0.5))

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = preload("res://fx/materials/mat_palette.tres")
	add_child(mi)

	_build_collision()


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(7.2, 5.4, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, 2.5, 0.0)
	body.add_child(shape)
