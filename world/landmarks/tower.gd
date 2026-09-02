extends Node3D
## Смотрящая башня на вершине Машука. Порт _tvTower() (citygen.js:1281-1306).
##
## Гранёный конус из 8 сужающихся четырёхгранных секций, антенна-игла и
## маячок на верхушке. Локальные координаты: (0,0,0) — уровень земли на
## вершине, мировую позицию/высоту ставит вызывающий код.

const SECTIONS := 8
const SECTION_H := 5.0
const BASE_R := 3.5
const RED := Color("#ee2222")
const WHITE := Color("#ffffff")
const BEACON_COLOR := Color("#ff3333")


func _ready() -> void:
	var b := MeshBuilder.new()
	for i in SECTIONS:
		var r1 := BASE_R * (1.0 - float(i) / (SECTIONS + 1.0))
		var r2 := BASE_R * (1.0 - float(i + 1) / (SECTIONS + 1.0))
		var y := 2.5 + i * SECTION_H
		b.cylinder(Vector3(0.0, y, 0.0), r2, r1, SECTION_H,
			WHITE if i % 2 == 1 else RED, 4)
	var spire_y := 2.5 + SECTIONS * SECTION_H + 6.0
	b.cylinder(Vector3(0.0, spire_y, 0.0), 0.08, 0.4, 12.0, RED, 4)
	var beacon_y := spire_y + 6.0
	b.sphere(Vector3(0.0, beacon_y, 0.0), 0.4, BEACON_COLOR, 4, 6)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = preload("res://fx/materials/mat_palette.tres")
	add_child(mi)

	_build_collision(2.5 + SECTIONS * SECTION_H * 0.5)


func _build_collision(mid_height: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = BASE_R
	cyl.height = SECTIONS * SECTION_H
	shape.shape = cyl
	shape.position = Vector3(0.0, mid_height, 0.0)
	body.add_child(shape)
