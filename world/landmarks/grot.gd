extends Node3D
## Грот Лермонтова: два каменных столба и плита-перемычка над тёмным
## входом. Порт _grotto() (citygen.js:894-909) — уже компактный в оригинале,
## переносится почти 1:1.
##
## Локальные координаты вокруг (0,0,0), мировую позицию выставляет
## вызывающий код.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")
const STONE := Color("#8a8a84")
const DARK := Color("#2a2a2a")

## Небольшой подъём над землёй, как в оригинале (g.position.y = 0.16).
const BASE_Y := 0.16


func _ready() -> void:
	var b := MeshBuilder.new()
	b.cylinder(Vector3(-2.0, BASE_Y + 1.8, 0.0), 1.3, 1.6, 3.6, STONE, 7)
	b.cylinder(Vector3(2.0, BASE_Y + 1.8, 0.0), 1.3, 1.6, 3.6, STONE, 7)
	b.box(Vector3(0.0, BASE_Y + 3.6, 0.0), Vector3(5.4, 1.6, 3.4), STONE)
	b.box(Vector3(0.0, BASE_Y + 1.9, 0.8), Vector3(4.0, 2.2, 1.6), DARK)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = PALETTE_MAT
	add_child(mi)

	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(6.0, 4.0, 3.4)
	cs.shape = shape
	cs.position = Vector3(0.0, 2.0, 0.0)
	body.add_child(cs)
	add_child(body)
