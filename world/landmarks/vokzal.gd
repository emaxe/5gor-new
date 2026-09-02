extends Node3D
## Ж/д вокзал: здание с часовой башней, крытый перрон, три пути и стоящий
## состав (тепловоз + 2 вагона). Порт _station()/_stationVehicle()
## (citygen.js:1734-2021), упрощённый до low-poly силуэта.
##
## Оригинал рисует часы/вывески/полосатый козырёк канвас-текстурами и ставит
## под навесом десятки шпал вдоль 90 м путей — здесь они заменены плоскими
## цветными формами и прорежены: силуэт и узнаваемость сохранены, счёт
## примитивов на порядок меньше.

const C_WALL := Color("#c8b898")
const C_TRIM := Color("#e8dcc4")
const C_BASE := Color("#9a8c70")
const C_ROOF := Color("#6a4a2a")
const C_DOOR := Color("#4a3423")
const C_GLASS := Color("#2a3442")
const C_MET := Color("#6a6a66")
const C_PAVE := Color("#b0b0a8")
const C_EDGE := Color("#e8c840")
const C_BALLAST := Color("#3a3733")
const C_RAIL := Color("#a8a8b0")
const C_TOWER := Color("#d8c8a8")
const C_BELFRY := Color("#1e2228")
const C_SPIRE_POLE := Color("#7a6a4a")
const C_SPIRE_BALL := Color("#d8b83a")
const C_CLOCK_FACE := Color("#f4f1e6")
const C_CLOCK_HAND := Color("#1a1a18")
const C_SIGNAL_LENS := Color("#3a1414")

## TRAIN_PAL (citygen.js:19-28).
const P_LOCO := Color("#2e7a46")
const P_CAR := Color("#1b5230")
const P_BAND := Color("#e6d9a8")
const P_UNDER := Color("#26282c")
const P_DARK := Color("#17181b")
const P_WHEEL := Color("#141416")
const P_ROOF := Color("#40464e")
const P_GLASS := Color("#223040")


func _ready() -> void:
	var b := MeshBuilder.new()
	_building(b)
	_platform_and_tracks(b)
	_train(b, -22.0, 24.0, &"loco")
	_train(b, -3.0, 24.0, &"car")
	_train(b, 16.0, 24.0, &"car")
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = preload("res://fx/materials/mat_palette.tres")
	add_child(mi)
	_collision()


# --- Здание с часовой башней -------------------------------------------------

func _building(b: MeshBuilder) -> void:
	# Цоколь, стены, карниз, аттик (citygen.js:1849-1853).
	b.box(Vector3(0.0, 0.75, 0.0), Vector3(56.6, 1.6, 18.6), C_BASE)
	b.box(Vector3(0.0, 7.15, 0.0), Vector3(56.0, 14.0, 18.0), C_WALL)
	b.box(Vector3(0.0, 13.75, 0.0), Vector3(58.0, 0.8, 20.0), C_TRIM)
	b.box(Vector3(0.0, 14.75, 0.0), Vector3(56.8, 1.2, 18.8), C_WALL)

	# Часовая башня: ствол, пилястры по углам, пояс звонницы, шпиль.
	b.box(Vector3(0.0, 13.15, 0.0), Vector3(9.0, 26.0, 9.0), C_TOWER)
	for sx: float in [-4.2, 4.2]:
		for sz: float in [-4.2, 4.2]:
			b.box(Vector3(sx, 13.15, sz), Vector3(1.2, 26.0, 1.2), C_TRIM)
	b.box(Vector3(0.0, 25.8, 0.0), Vector3(10.8, 0.65, 10.8), C_TRIM)
	for s: float in [-1.0, 1.0]:
		b.box(Vector3(0.0, 23.4, s * 4.55), Vector3(2.4, 3.4, 0.3), C_BELFRY)
		b.box(Vector3(s * 4.55, 23.4, 0.0), Vector3(0.3, 3.4, 2.4), C_BELFRY)
	b.cylinder(Vector3(0.0, 33.5, 0.0), 0.12, 0.12, 2.8, C_SPIRE_POLE, 6)
	b.sphere(Vector3(0.0, 35.2, 0.0), 0.5, C_SPIRE_BALL, 3, 6)
	b.cone(Vector3(0.0, 29.15, 0.0), 6.5, 6.0, C_ROOF, 4, Basis(Vector3.UP, PI * 0.25))

	# Часы на двух видимых гранях башни (было 4 — циферблат в текстуре,
	# здесь диск + две стрелки).
	_clock(b, Vector3(0.0, 19.0, 4.85), Basis(Vector3.RIGHT, PI * 0.5))
	_clock(b, Vector3(4.85, 19.0, 0.0), Basis(Vector3.FORWARD, PI * 0.5))

	# Окна: прорежены вдвое относительно оригинала (8 -> 3 на длинную грань).
	for dx: float in [-18.0, 0.0, 18.0]:
		for wz: float in [9.0, -9.0]:
			b.box(Vector3(dx, 5.0, wz), Vector3(2.4, 4.0, 0.1), C_GLASS)
			b.box(Vector3(dx, 10.4, wz), Vector3(2.0, 2.4, 0.1), C_GLASS)
	for wx: float in [-28.0, 28.0]:
		for dz: float in [-4.6, 4.6]:
			b.box(Vector3(wx, 5.0, dz), Vector3(0.1, 4.0, 2.4), C_GLASS)

	# Входной портал со стороны перрона.
	b.box(Vector3(0.0, 3.65, 9.0), Vector3(11.0, 7.3, 0.6), C_TRIM)
	for dx: float in [-1.05, 1.05]:
		b.box(Vector3(dx, 2.35, 9.25), Vector3(1.9, 4.4, 0.5), C_DOOR)
	b.box(Vector3(0.0, 5.5, 9.25), Vector3(6.4, 1.4, 0.5), C_GLASS)
	for dx: float in [-4.7, 4.7]:
		b.cylinder(Vector3(dx, 3.45, 9.4), 0.45, 0.5, 6.9, C_TRIM, 8)


func _clock(b: MeshBuilder, pos: Vector3, face_basis: Basis) -> void:
	b.cylinder(pos, 2.6, 2.6, 0.3, C_CLOCK_FACE, 10, face_basis)
	b.box(pos + Vector3(0.0, 0.9, 0.05), Vector3(0.14, 1.6, 0.1), C_CLOCK_HAND)
	b.box(pos + Vector3(0.7, 0.2, 0.05), Vector3(1.4, 0.14, 0.1), C_CLOCK_HAND)


# --- Перрон, навес, пути ------------------------------------------------------

func _platform_and_tracks(b: MeshBuilder) -> void:
	const PLAT_Z := 19.0
	const PLAT_TOP := 1.0
	b.box(Vector3(0.0, 0.475, PLAT_Z), Vector3(46.0, 1.05, 7.0), C_PAVE)
	b.box(Vector3(0.0, PLAT_TOP + 0.01, PLAT_Z), Vector3(45.0, 0.05, 6.6), Color("#bdb9ad"))
	b.box(Vector3(0.0, PLAT_TOP - 0.04, 22.1), Vector3(46.0, 0.16, 0.9), Color("#a8a49c"))
	b.box(Vector3(0.0, PLAT_TOP + 0.04, 22.1), Vector3(46.0, 0.06, 0.45), C_EDGE)

	# Навес: 4 колонны (было 6) + кровля с фризом.
	for k in 4:
		var x := -16.0 + k * 10.6
		b.cylinder(Vector3(x, PLAT_TOP + 2.15, PLAT_Z), 0.2, 0.26, 4.3, C_MET, 6)
	b.box(Vector3(0.0, 5.475, PLAT_Z), Vector3(40.0, 0.35, 7.2), C_MET)
	for sz: float in [-3.6, 3.6]:
		b.box(Vector3(0.0, 5.2, PLAT_Z + sz), Vector3(40.0, 0.5, 0.2), C_TRIM)

	# Три пути: балласт + рельсовые нити (шпалы опущены — прочитываются
	# и без них, а их в оригинале ~35 на путь).
	for tz: float in [24.0, 28.5, 33.0]:
		b.box(Vector3(0.0, 0.10, tz), Vector3(90.0, 0.30, 3.0), C_BALLAST)
		for off: float in [-0.6, 0.6]:
			b.box(Vector3(0.0, 0.40, tz + off), Vector3(90.0, 0.10, 0.12), C_RAIL)

	# Выходной светофор у первого пути.
	b.cylinder(Vector3(24.5, 2.5, 23.0), 0.16, 0.2, 5.0, C_MET, 6)
	b.box(Vector3(24.5, 5.6, 23.0), Vector3(0.55, 1.6, 0.45), C_BELFRY)
	b.box(Vector3(24.5, 5.15, 22.78), Vector3(0.34, 0.34, 0.12), C_SIGNAL_LENS)


# --- Состав: тепловоз / вагон -------------------------------------------------

## Один экипаж состава. cx — центр по X, tz — ось пути, kind: 'loco'|'car'.
## Сильно упрощено относительно _stationVehicle() (там ~30 боксов на экипаж
## с жалюзи, поручнями и тамбурными переходами) — сохранены только формы,
## задающие силуэт: рама на тележках, кузов, полоса ливреи, крыша, окна/маска.
func _train(b: MeshBuilder, cx: float, tz: float, kind: StringName) -> void:
	const LEN := 14.0
	const Y0 := 0.45
	var half := LEN * 0.5

	for s: float in [-1.0, 1.0]:
		var bogie := s * (half - 2.5)
		b.box(Vector3(cx + bogie, Y0 + 0.9, tz), Vector3(4.9, 0.6, 2.15), P_UNDER)
		for wz: float in [-0.6, 0.6]:
			b.cylinder(Vector3(cx + bogie, Y0 + 0.5, tz + wz), 0.5, 0.5, 0.22, P_WHEEL, 8,
				Basis(Vector3.RIGHT, PI * 0.5))
	b.box(Vector3(cx, Y0 + 1.32, tz), Vector3(LEN - 0.4, 0.45, 2.6), P_UNDER)
	for s: float in [-1.0, 1.0]:
		b.box(Vector3(cx + s * (half + 0.2), Y0 + 1.15, tz), Vector3(0.5, 0.42, 0.5), P_DARK)

	if kind == &"loco":
		b.box(Vector3(cx, Y0 + 2.85, tz), Vector3(LEN - 0.5, 2.7, 2.9), P_LOCO)
		b.box(Vector3(cx, Y0 + 1.74, tz), Vector3(LEN - 0.4, 0.32, 2.96), P_BAND)
		b.box(Vector3(cx, Y0 + 4.41, tz), Vector3(LEN - 1.1, 0.42, 2.72), P_ROOF)
		for s: float in [-1.0, 1.0]:
			b.box(Vector3(cx + s * (half - 0.18), Y0 + 3.45, tz), Vector3(0.16, 0.95, 2.05), P_GLASS)
			b.box(Vector3(cx + s * (half - 0.32), Y0 + 3.42, tz), Vector3(0.14, 1.5, 2.62), P_DARK)
		b.box(Vector3(cx - (half - 0.18), Y0 + 2.1, tz), Vector3(0.2, 0.3, 0.34), Color("#fff4cc"))
	else:
		b.box(Vector3(cx, Y0 + 2.72, tz), Vector3(LEN - 0.4, 2.45, 2.9), P_CAR)
		b.box(Vector3(cx, Y0 + 1.7, tz), Vector3(LEN - 0.3, 0.26, 2.96), P_BAND)
		b.box(Vector3(cx, Y0 + 4.08, tz), Vector3(LEN - 1.0, 0.3, 2.8), P_ROOF)
		for k in 4:
			var wx := cx - 3.4 + k * 1.9
			for sz: float in [-1.0, 1.0]:
				b.box(Vector3(wx, Y0 + 3.15, tz + sz * 1.47), Vector3(1.0, 0.95, 0.1), P_GLASS)
		for s: float in [-1.0, 1.0]:
			b.box(Vector3(cx + s * (half - 1.4), Y0 + 2.52, tz), Vector3(0.95, 2.05, 0.1), P_DARK)


func _collision() -> void:
	_body(Vector3(0.0, 7.7, 0.0), Vector3(56.0, 15.4, 18.0))
	_body(Vector3(0.0, 13.0, 0.0), Vector3(9.0, 26.0, 9.0))
	_body(Vector3(0.0, 1.5, 19.0), Vector3(46.0, 3.0, 7.0))
	_body(Vector3(-3.0, 2.0, 24.0), Vector3(46.0, 4.0, 3.2))


func _body(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
