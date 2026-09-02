extends Node3D
## Рынок «Лира». Порт _market() (citygen.js:1519-1641), упрощённый под
## планку low-poly car_mesh_builder.gd: вместо 12 полнодетальных палаток с
## индивидуальными ножками и текстурного полосатого тента — прилавок +
## навес + 2 опоры на палатку, тент одним цветом вместо чередования полос.
## Мощение, вывеска и колонка/весы тоже без canvas-текстур — плоские цвета.
##
## Локальные координаты: (0,0,0) — центр квартала (BX=96, BZ=-32 оригинала),
## уровень земли; мировую позицию ставит вызывающий код.

const GROUND := Color("#c8c2b2")
const STALL := Color("#8a6a44")
const POST := Color("#6a6a60")
const AWNING := Color("#c0392b")
const RAIL := Color("#7a6a52")
const STONE := Color("#b0a898")
const SIGN_BG := Color("#7c1f18")

## Локальные позиции палаток: 3 ряда x 4 колонки (COLS/ROWS оригинала минус BX/BZ).
const COLS := [-17.0, -8.0, 8.0, 17.0]
const ROWS := [-16.0, -2.0, 12.0]


func _ready() -> void:
	var b := MeshBuilder.new()

	# Мощение квартала (44x44, оригинал: FX0..FX1 / FZ0..FZ1).
	b.box(Vector3(0.0, 0.05, 0.0), Vector3(44.0, 0.2, 44.0), GROUND)

	for z in ROWS:
		for x in COLS:
			_add_stall(b, x, z)

	_add_fence(b)
	_add_gate(b)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = preload("res://fx/materials/mat_palette.tres")
	add_child(mi)

	_add_collision()


## По коллайдеру на препятствие, а не один сплошной по всему кварталу:
## в оригинале площадь мощения специально проезжая — это точка высадки
## заказа «Рынок Лира» (config.js LANDMARKS + orders.js), внутрь квартала
## нужно заезжать через ворота.
func _add_collision() -> void:
	for z in ROWS:
		for x in COLS:
			_box_collider(Vector3(x, 1.9, z), Vector3(8.4, 3.8, 5.0))
	_box_collider(Vector3(-21.6, 0.85, -0.4), Vector3(0.3, 0.5, 42.4))
	_box_collider(Vector3(21.6, 0.85, -0.4), Vector3(0.3, 0.5, 42.4))
	_box_collider(Vector3(0.0, 0.85, -21.6), Vector3(43.2, 0.5, 0.3))
	_box_collider(Vector3(-15.5, 0.85, 20.8), Vector3(12.2, 0.5, 0.3))
	_box_collider(Vector3(15.5, 0.85, 20.8), Vector3(12.2, 0.5, 0.3))
	for gx: float in [-5.0, 5.0]:
		_box_collider(Vector3(gx, 1.9, 20.8), Vector3(1.5, 3.8, 1.5))


func _box_collider(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	body.add_child(shape)
	add_child(body)


func _add_stall(b: MeshBuilder, x: float, z: float) -> void:
	b.box(Vector3(x, 1.55, z), Vector3(8.0, 0.8, 4.6), STALL)
	b.box(Vector3(x, 3.35, z), Vector3(8.4, 0.24, 5.0), AWNING)
	# Стойки навеса — вертикальные: ось цилиндра уже вдоль Y, доп. поворот
	# не нужен (Basis(Vector3.FORWARD, PI*0.5) укладывает цилиндр набок —
	# это идиома для КОЛЁС, а не для опор).
	b.cylinder(Vector3(x - 3.4, 2.45, z), 0.15, 0.15, 1.8, POST, 5)
	b.cylinder(Vector3(x + 3.4, 2.45, z), 0.15, 0.15, 1.8, POST, 5)


## Периметр упрощён до четырёх сплошных ограждающих балок вместо перебора
## отдельных столбов (в оригинале — из-за линейной проверки propsAABB
## каждый кадр; здесь коллизия у ограды всего одна общая, см. _add_collision).
func _add_fence(b: MeshBuilder) -> void:
	b.box(Vector3(-21.6, 0.85, -0.4), Vector3(0.15, 0.5, 42.4), RAIL)
	b.box(Vector3(21.6, 0.85, -0.4), Vector3(0.15, 0.5, 42.4), RAIL)
	b.box(Vector3(0.0, 0.85, -21.6), Vector3(43.2, 0.5, 0.15), RAIL)
	# Северная сторона — с проёмом ворот по центру (створ ~8.4 м).
	b.box(Vector3(-15.5, 0.85, 20.8), Vector3(12.2, 0.5, 0.15), RAIL)
	b.box(Vector3(15.5, 0.85, 20.8), Vector3(12.2, 0.5, 0.15), RAIL)


## Ворота с перекладиной и табличкой вместо вывески на canvas-текстуре.
func _add_gate(b: MeshBuilder) -> void:
	for gx: float in [-5.0, 5.0]:
		b.box(Vector3(gx, 1.9, 20.8), Vector3(1.5, 3.5, 1.5), STONE)
		b.box(Vector3(gx, 3.76, 20.8), Vector3(1.8, 0.22, 1.8), STONE)
	b.box(Vector3(0.0, 4.15, 20.8), Vector3(11.6, 0.55, 1.0), POST)
	b.box(Vector3(0.0, 4.15, 21.34), Vector3(9.6, 1.35, 0.06), SIGN_BG)
