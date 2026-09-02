extends Node3D
## Трамвайная остановка (навес со скамейкой). Порт _tramStop() (citygen.js:1220-1245).
## В оригинале ставится три раза («Цветник», «Вокзал», «Лира») — здесь одна
## сцена, инстанцируемая столько же раз вызывающим кодом.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

const METAL := Color("#3a3a3c")
const GLASS := Color("#4a7fa8")
const BENCH := Color("#8a6a44")


func _ready() -> void:
	var b := MeshBuilder.new()
	b.box(Vector3(0.0, 2.4, 0.0), Vector3(4.2, 0.1, 2.2), METAL)
	b.box(Vector3(0.0, 1.1, -1.0), Vector3(4.0, 2.2, 0.08), GLASS)
	# Опорные стойки навеса.
	for sx: float in [-1.9, 1.9]:
		b.box(Vector3(sx, 1.2, -0.9), Vector3(0.1, 2.4, 0.1), METAL)
	b.box(Vector3(0.0, 0.55, -0.4), Vector3(1.8, 0.1, 0.55), BENCH)
	b.box(Vector3(0.0, 0.8, -0.66), Vector3(1.8, 0.55, 0.1), BENCH)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = PALETTE_MAT
	add_child(mi)
	_add_collision()


func _add_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.2, 2.4, 2.2)
	shape.shape = box
	shape.position = Vector3(0.0, 1.2, -0.1)
	body.add_child(shape)
	add_child(body)
