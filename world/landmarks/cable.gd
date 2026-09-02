extends Node3D
## Нижняя станция канатной дороги на Машук + одна кабинка. Порт нижней
## станции из _cableCar() (citygen.js:2404-2411) и _buildCableCarCab()
## (citygen.js:2487-2520).
##
## Оригинал — целая система с опорами по всей трассе до вершины и двумя
## анимированными кабинками на тросе (citygen.js:2380-2486). Порт статичный:
## трасса до вершины (лишние ~160 м геометрии без игровой ценности) и
## анимация не переносятся — только узнаваемый якорь у подножия, где
## LandmarkData "cable" и стоит (config.js:378, x:20 z:-288 — база станции).

const STATION_COLOR := Color("#c8b898")
const DARK := Color("#4a3a2a")
const CABLE_COLOR := Color("#2a2a2a")
const CABIN_BODY := Color("#e86030")
const CABIN_GLASS := Color("#4a6a8a")


func _ready() -> void:
	var b := MeshBuilder.new()
	# Станция: корпус + крыша-платформа, к которой крепится трос.
	b.box(Vector3(0.0, 3.0, 0.0), Vector3(10.0, 6.0, 8.0), STATION_COLOR)
	b.box(Vector3(0.0, 6.2, 0.0), Vector3(8.0, 0.4, 6.0), DARK)

	# Кабинка рядом со станцией, будто зависла у платформы.
	var cab := Vector3(5.5, 7.6, 0.0)
	_build_cabin(b, cab)

	# Обрывок троса от крыши станции к кабинке — читается как «канатка»
	# без переноса всей трассы до вершины.
	var anchor := Vector3(4.0, 6.4, 0.0)
	var clamp_pos := cab + Vector3(0.0, 2.7, 0.0)
	var mid := (anchor + clamp_pos) * 0.5
	var seg_len := anchor.distance_to(clamp_pos)
	var dir := (clamp_pos - anchor).normalized()
	var up := Vector3.UP
	var axis := up.cross(dir)
	var cable_basis := Basis.IDENTITY
	if axis.length() > 0.001:
		cable_basis = Basis(axis.normalized(), up.angle_to(dir))
	b.cylinder(mid, 0.08, 0.08, seg_len, CABLE_COLOR, 5, cable_basis)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = preload("res://fx/materials/mat_palette.tres")
	add_child(mi)

	_build_collision()


func _build_cabin(b: MeshBuilder, pos: Vector3) -> void:
	b.box(pos, Vector3(1.8, 1.4, 1.6), CABIN_BODY)
	for sx: float in [-1.0, 1.0]:
		b.box(pos + Vector3(sx * 0.92, 0.1, 0.0), Vector3(0.05, 0.7, 1.2), CABIN_GLASS)
	b.box(pos + Vector3(0.0, 0.8, 0.0), Vector3(2.0, 0.2, 1.8), Color("#3a3a3a"))
	b.box(pos + Vector3(0.0, 1.8, 0.0), Vector3(0.1, 1.8, 0.1), Color("#3a3a3a"))
	var across := Basis(Vector3.FORWARD, PI * 0.5)
	b.cylinder(pos + Vector3(0.0, 2.7, 0.0), 0.18, 0.18, 0.4, Color("#3a3a3a"), 8, across)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(10.0, 6.0, 8.0)
	shape.shape = box_shape
	shape.position = Vector3(0.0, 3.0, 0.0)
	body.add_child(shape)
