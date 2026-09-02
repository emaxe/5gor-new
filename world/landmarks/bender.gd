extends Node3D
## Памятник Остапу Бендеру у входа в Провал: сидит на «12-м стуле»,
## продаёт билеты на осмотр достопримечательности. Порт
## _ostapBenderStatue() (citygen.js:1246-1280).
##
## Локальные координаты: (0,0,0) — уровень земли, мировую позицию/высоту
## ставит вызывающий код (LandmarkLayer).

const BRONZE := Color("#7a6a4a")
const WOOD := Color("#6a4a2a")
const SIGN := Color("#f2c12e")


func _ready() -> void:
	var b := MeshBuilder.new()
	b.cylinder(Vector3(0.0, 0.8, 0.0), 0.25, 0.28, 1.5, BRONZE, 6)
	b.sphere(Vector3(0.0, 1.7, 0.0), 0.2, BRONZE, 5, 6)
	b.cylinder(Vector3(0.0, 1.82, 0.02), 0.22, 0.22, 0.06, BRONZE, 6)

	# 12-й стул рядом.
	b.box(Vector3(0.45, 0.5, 0.0), Vector3(0.45, 0.08, 0.45), WOOD)
	b.box(Vector3(0.45, 0.75, -0.2), Vector3(0.45, 0.5, 0.06), WOOD)

	# Табличка «билеты на Провал».
	b.box(Vector3(-0.5, 0.8, 0.0), Vector3(0.8, 0.4, 0.05), SIGN)

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
	box.size = Vector3(1.4, 1.9, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, 0.95, 0.0)
	body.add_child(shape)
