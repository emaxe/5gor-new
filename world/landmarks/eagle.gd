extends Node3D
## Памятник Орлу — символ Пятигорска (орёл, терзающий змею). Порт
## _eagleMonument() (citygen.js:1018-1114), упрощённый до low-poly силуэта.
##
## Локальные координаты: (0,0,0) — уровень земли, мировую позицию/высоту
## ставит вызывающий код (LandmarkLayer).
##
## Упрощения относительно оригинала: змея была двумя гладкими торусами
## (MeshBuilder тора не строит) — заменена на кольцо коротких сегментов,
## уложенное под когтями орла на плоском верху постамента (не обвивает
## конус — так читается увереннее с любого ракурса); у крыльев 5 сегментов
## на сторону сведены к 3 (плечо/предплечье/кончик), но заметно утолщены —
## первая версия читалась тонкими досками, а не крылом.

const STONE := Color("#8a8a80")
const EAGLE := Color("#6a5a4a")
const GOLD := Color("#d8a030")
const SNAKE := Color("#2e4a30")
const DARK := Color("#4a3a2a")


func _ready() -> void:
	var b := MeshBuilder.new()
	_build_pedestal(b)
	_build_snake(b)
	_build_bird(b)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = preload("res://fx/materials/mat_palette.tres")
	add_child(mi)

	_build_collision()


## Каменный постамент — три сужающихся ступени.
func _build_pedestal(b: MeshBuilder) -> void:
	b.cylinder(Vector3(0.0, 0.5, 0.0), 2.6, 3.2, 1.0, STONE, 8)
	b.cylinder(Vector3(0.0, 1.6, 0.0), 2.0, 2.5, 1.2, STONE, 8)
	b.cylinder(Vector3(0.0, 2.6, 0.0), 1.4, 1.8, 0.8, STONE, 8)


## Змея под когтями орла — уложенное на плоском верху постамента кольцо
## коротких сегментов, а не обвивка вокруг конуса (так убедительнее читается
## с любого ракурса, чем тонкая спираль, парящая над камнем).
func _build_snake(b: MeshBuilder) -> void:
	const LOOPS := 6
	const TOP_Y := 3.15
	for i in LOOPS:
		var t0 := TAU * float(i) / LOOPS
		var t1 := TAU * float(i + 1) / LOOPS
		var r := 0.95 - (i % 2) * 0.15
		var a := Vector3(cos(t0) * r, TOP_Y, sin(t0) * r)
		var c := Vector3(cos(t1) * r, TOP_Y + 0.03, sin(t1) * r)
		var mid := (a + c) * 0.5
		var seg_len := a.distance_to(c)
		var dir := (c - a).normalized()
		var basis := Basis(dir.cross(Vector3.UP).normalized(), PI * 0.5) \
			if dir.cross(Vector3.UP).length() > 0.01 else Basis.IDENTITY
		b.cylinder(mid, 0.13, 0.16, seg_len, SNAKE, 6, basis)
	# Голова приподнята из кольца — под правым когтем орла.
	b.cylinder(Vector3(0.55, TOP_Y + 0.35, 0.75), 0.08, 0.13, 0.55, SNAKE, 6,
		Basis(Vector3.RIGHT, -0.9))
	b.sphere(Vector3(0.62, TOP_Y + 0.62, 0.98), 0.13, SNAKE, 4, 6)


## Орёл: конусообразное тело, голова, распахнутые крылья, хвост.
func _build_bird(b: MeshBuilder) -> void:
	b.cone(Vector3(0.0, 3.6, 0.0), 0.85, 1.8, EAGLE, 6, Basis(Vector3.RIGHT, -0.3))
	b.sphere(Vector3(0.0, 4.6, 0.35), 0.38, EAGLE, 5, 6)
	b.cone(Vector3(0.0, 4.95, 0.2), 0.12, 0.35, EAGLE, 4, Basis(Vector3.RIGHT, -0.4))
	b.cone(Vector3(0.0, 4.5, 0.75), 0.10, 0.5, GOLD, 5, Basis(Vector3.RIGHT, PI * 0.5))
	for sx: float in [-1.0, 1.0]:
		b.sphere(Vector3(sx * 0.22, 4.65, 0.55), 0.06, DARK, 3, 5)

	# Крылья — заметно толще прежней версии (там читались тонкими досками):
	# три перекрывающихся сегмента на сторону, сужающихся к кончику.
	for s: float in [-1.0, 1.0]:
		var shoulder := Basis(Vector3.FORWARD, s * 0.32).rotated(Vector3.RIGHT, -0.12)
		b.box(Vector3(s * 0.85, 3.95, -0.1), Vector3(1.7, 0.42, 1.0), EAGLE, shoulder)
		var mid_basis := Basis(Vector3.FORWARD, s * 0.62).rotated(Vector3.RIGHT, -0.2)
		b.box(Vector3(s * 2.15, 4.5, -0.35), Vector3(1.6, 0.30, 0.78), EAGLE, mid_basis)
		var tip_basis := Basis(Vector3.FORWARD, s * 0.85).rotated(Vector3.RIGHT, -0.26)
		b.box(Vector3(s * 3.25, 5.15, -0.6), Vector3(1.3, 0.20, 0.6), EAGLE, tip_basis)

	b.box(Vector3(0.0, 3.3, -0.8), Vector3(0.6, 0.16, 0.9), EAGLE, Basis(Vector3.RIGHT, 0.3))


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 3.2
	cyl.height = 5.2
	shape.shape = cyl
	shape.position = Vector3(0.0, 2.6, 0.0)
	body.add_child(shape)
