extends Node3D
## Пятигорский трамвай КТМ-1/Татра. Порт _pyatigorskTramway() (citygen.js:1115-1219),
## упрощённый под планку низкополигональности CarMeshBuilder.
##
## Статичный: анимация по рельсам (tramAnim, citygen.js:3096-3106) не портируется —
## трамвай стоит как достопримечательность, а не движущийся объект. Полная
## сеть путей (480 м вдоль X через весь город, citygen.js:1121-1136) тоже не
## переносится — под трамваем короткий локальный отрезок рельс для контекста.
##
## Ось капота/кормы — локальный +Z (общее соглашение проекта, Heading.forward),
## а не мировая X, как в оригинале: там трамвай двигался вдоль X, здесь он
## неподвижен, и надобности в мировой оси нет.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

const FRAME := Color("#3a3a3c")
const WHEEL := Color("#222224")
const BODY := Color("#cc2222")
const CREAM := Color("#f4eedc")
const DOOR := Color("#2a2a2c")
const SEAT := Color("#8a5a3a")
const SIGN_DARK := Color("#111111")
const SIGN_LIT := Color("#ffdf66")
const HEADLIGHT := Color("#fff0aa")
const TAILLIGHT := Color("#ff2222")
const GLASS := Color("#9fd8e8")
const RAIL := Color("#c4c4cc")
const TIE := Color("#3e342a")
const BED := Color("#48484c")


func _ready() -> void:
	var b := MeshBuilder.new()
	_add_rails(b)
	_add_body(b)
	_add_details(b)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = PALETTE_MAT
	add_child(mi)
	_add_collision()


func _add_rails(b: MeshBuilder) -> void:
	b.box(Vector3(0.0, 0.02, 0.0), Vector3(1.5, 0.03, 12.0), BED)
	for sx: float in [-0.55, 0.55]:
		b.box(Vector3(sx, 0.05, 0.0), Vector3(0.07, 0.09, 12.0), RAIL)
	for sz in [-5.0, -2.5, 0.0, 2.5, 5.0]:
		b.box(Vector3(0.0, 0.06, sz), Vector3(1.4, 0.05, 0.25), TIE)


## Кузов: усечённый бокс со скруглёнными носом и кормой (taperedBox
## оригинала), длина вдоль Z вместо мировой X.
func _add_body(b: MeshBuilder) -> void:
	b.tapered_box(Vector3(0.0, 1.35, 0.0), Vector3(2.3, 1.4, 9.9), BODY,
		Vector2(0.92, 1.0), 0.0, -0.55, -0.55)
	b.box(Vector3(0.0, 0.5, 0.0), Vector3(2.2, 0.3, 10.2), FRAME)


func _add_details(b: MeshBuilder) -> void:
	var across := Basis(Vector3.FORWARD, PI * 0.5)

	# Тележки и колёсные пары (4 оси).
	for sz: float in [-4.9, 4.9]:
		b.box(Vector3(0.0, 0.5, sz), Vector3(2.3, 0.35, 0.2), FRAME)
	for sz: float in [-2.8, -1.6, 1.6, 2.8]:
		for sx: float in [-0.55, 0.55]:
			b.cylinder(Vector3(sx, 0.35, sz), 0.35, 0.35, 0.1, WHEEL, 10, across)

	# Бежевая полоса и крыша.
	b.box(Vector3(0.0, 2.4, 0.0), Vector3(2.38, 0.7, 10.05), CREAM)
	b.box(Vector3(0.0, 2.9, 0.0), Vector3(2.25, 0.35, 9.8), CREAM)
	for sz: float in [-2.5, 0.0, 2.5]:
		b.box(Vector3(0.0, 3.12, sz), Vector3(0.8, 0.12, 1.2), FRAME)

	# Пантограф.
	b.box(Vector3(0.0, 3.12, 0.5), Vector3(1.2, 0.08, 1.6), FRAME)
	b.cylinder(Vector3(0.0, 3.7, 0.5), 0.03, 0.03, 1.4, FRAME, 5,
		Basis(Vector3.RIGHT, PI * 0.25))
	b.box(Vector3(0.0, 4.2, 0.4), Vector3(1.6, 0.06, 0.1), FRAME)

	# Двери и остекление — со стороны +X (борт с посадкой).
	for sz: float in [-3.2, 0.0, 3.2]:
		b.box(Vector3(1.16, 1.55, sz), Vector3(0.08, 1.8, 1.1), DOOR)
		b.box(Vector3(1.16, 1.9, sz), Vector3(0.1, 0.8, 0.9), GLASS)
	b.box(Vector3(0.0, 2.15, 0.0), Vector3(2.42, 0.85, 9.6), GLASS)

	# Сиденья салона, видны через остекление.
	for sz in range(-3, 4):
		for sx: float in [-0.7, 0.7]:
			b.box(Vector3(sx, 1.0, float(sz) * 1.2), Vector3(0.45, 0.4, 0.45), SEAT)

	# Маршрутоуказатель, фары, габариты.
	b.box(Vector3(0.0, 2.55, -4.85), Vector3(1.2, 0.35, 0.15), SIGN_DARK)
	b.box(Vector3(0.0, 2.55, -5.05), Vector3(1.1, 0.28, 0.05), SIGN_LIT)
	for sx: float in [-0.6, 0.6]:
		b.cylinder(Vector3(sx, 1.1, -4.95), 0.16, 0.16, 0.1, HEADLIGHT, 10,
			Basis(Vector3.RIGHT, PI * 0.5))
	for sz: float in [-0.7, 0.7]:
		b.cylinder(Vector3(sz, 1.1, 4.95), 0.12, 0.12, 0.1, TAILLIGHT, 8,
			Basis(Vector3.RIGHT, PI * 0.5))


func _add_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.3, 3.0, 10.2)
	shape.shape = box
	shape.position = Vector3(0.0, 1.5, 0.0)
	body.add_child(shape)
	add_child(body)
