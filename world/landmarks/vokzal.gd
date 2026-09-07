extends Node3D
## Железнодорожный вокзал Пятигорска — исторический вокзал с башней с часами.
##
## Включает:
## - Монументальный фасад вокзала с арочными окнами, рустовкой и карнизами;
## - Часовую башню с 4 круглыми циферблатами, аркадой звонницы и шпилем;
## - Пассажирский перрон с навесом на металлических кронштейнах;
## - Два железнодорожных пути с гравийной насыпью, шпалами и рельсами;
## - Стоящий пассажирский состав (зелёный локомотив и вагоны РЖД/исторические).

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

# Палитра здания вокзала (исторический песчано-охристый стиль)
const WALL_STONE := Color("#c8b898")
const WALL_TRIM := Color("#ece4d2")
const BASE_STONE := Color("#9a8c72")
const ROOF_COPPER := Color("#557a68")
const ROOF_TILE := Color("#6c4a30")
const DOOR_DARK := Color("#423223")
const GLASS_WINDOW := Color("#283440")
const CLOCK_FACE := Color("#faf7ee")
const CLOCK_HAND := Color("#1a1a18")
const GOLD_SPIRE := Color("#d8aa38")

# Платформа и пути
const PAVE_PLAT := Color("#aba69a")
const TACTILE_EDGE := Color("#e8be28")
const BALLAST := Color("#3e3a35")
const TIES_WOOD := Color("#483a2c")
const RAILS_STEEL := Color("#9fa0a6")
const CANOPY_METAL := Color("#3c5e48")

# Поезд
const TRAIN_GREEN := Color("#205e35")
const TRAIN_ROOF := Color("#42474e")
const TRAIN_STRIPE := Color("#ded39e")
const TRAIN_DARK := Color("#1a1c1e")
const TRAIN_LAMP := Color("#fff4cc")


func _ready() -> void:
	var b := MeshBuilder.new()

	_build_station_building(b)
	_build_clock_tower(b)
	_build_platform_and_canopy(b)
	_build_tracks_and_train(b)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = PALETTE_MAT
	add_child(mi)

	_build_collision()


# --- Здание вокзала ---------------------------------------------------------

func _build_station_building(b: MeshBuilder) -> void:
	# Фасад обращён на север (-Z) к Привокзальной площади
	var bz := 0.0

	# Цоколь здания (высота 1.2 м, ширина 46 м, глубина 14 м)
	b.box(Vector3(0.0, 0.6, bz), Vector3(46.8, 1.2, 14.8), BASE_STONE)

	# Центральный двухэтажный корпус (ширина 18 м, высота 8 м)
	b.box(Vector3(0.0, 5.2, bz), Vector3(18.0, 8.0, 14.0), WALL_STONE)
	b.box(Vector3(0.0, 9.4, bz), Vector3(18.6, 0.6, 14.6), WALL_TRIM)

	# Скатная вальмовая крыша центрального корпуса
	b.box(Vector3(0.0, 10.4, bz), Vector3(17.6, 1.6, 13.6), ROOF_TILE)

	# Боковые крылья (ширина 14 м, высота 6.5 м каждое)
	for s: float in [-1.0, 1.0]:
		var wx: float = s * 15.0
		b.box(Vector3(wx, 4.45, bz), Vector3(13.6, 6.5, 12.8), WALL_STONE)
		b.box(Vector3(wx, 7.9, bz), Vector3(14.0, 0.5, 13.2), WALL_TRIM)
		b.box(Vector3(wx, 8.8, bz), Vector3(13.4, 1.4, 12.4), ROOF_TILE)

	# Главный входной портал с козырьком на северном фасаде (-Z)
	b.box(Vector3(0.0, 3.2, bz - 7.1), Vector3(4.8, 5.0, 0.3), WALL_TRIM)
	b.box(Vector3(0.0, 2.6, bz - 7.15), Vector3(3.4, 4.0, 0.15), DOOR_DARK)
	b.box(Vector3(0.0, 5.8, bz - 7.6), Vector3(6.0, 0.3, 2.0), CANOPY_METAL)
	b.box(Vector3(0.0, 7.2, bz - 7.05), Vector3(8.0, 0.9, 0.15), BASE_STONE)

	# Арочные окна центрального корпуса (1 и 2 этажи)
	for fx: float in [-5.8, -2.4, 2.4, 5.8]:
		# 1-й этаж
		b.box(Vector3(fx, 3.0, bz - 7.05), Vector3(1.6, 2.8, 0.1), GLASS_WINDOW)
		b.box(Vector3(fx, 4.6, bz - 7.05), Vector3(1.8, 0.35, 0.15), WALL_TRIM)
		# 2-й этаж
		b.box(Vector3(fx, 6.8, bz - 7.05), Vector3(1.4, 2.4, 0.1), GLASS_WINDOW)
		b.box(Vector3(fx, 8.2, bz - 7.05), Vector3(1.6, 0.35, 0.15), WALL_TRIM)

	# Окна боковых крыльев
	for s: float in [-1.0, 1.0]:
		for wx_rel: float in [-4.0, 0.0, 4.0]:
			var wx: float = s * 15.0 + wx_rel
			b.box(Vector3(wx, 3.5, bz - 6.45), Vector3(1.6, 3.2, 0.1), GLASS_WINDOW)
			b.box(Vector3(wx, 5.3, bz - 6.45), Vector3(1.8, 0.35, 0.15), WALL_TRIM)


# --- Часовая башня вокзала --------------------------------------------------

func _build_clock_tower(b: MeshBuilder) -> void:
	# Башня возвышается над центральным входом (по оси X=0, сдвинута к фасаду)
	var tz := -4.2
	var ty := 9.7

	# Ствол башни (квадратный)
	b.box(Vector3(0.0, ty + 2.5, tz), Vector3(4.8, 5.0, 4.8), WALL_STONE)
	b.box(Vector3(0.0, ty + 5.2, tz), Vector3(5.2, 0.4, 5.2), WALL_TRIM)

	# Ярус с часами
	b.box(Vector3(0.0, ty + 7.4, tz), Vector3(4.4, 4.0, 4.4), WALL_STONE)
	b.box(Vector3(0.0, ty + 9.6, tz), Vector3(4.8, 0.4, 4.8), WALL_TRIM)

	# 4 круглых циферблата часов
	# Северный (главный, к площади)
	_add_clock_face(b, Vector3(0.0, ty + 7.4, tz - 2.25), Vector3.FORWARD)
	# Южный (к перрону)
	_add_clock_face(b, Vector3(0.0, ty + 7.4, tz + 2.25), Vector3.BACK)
	# Западный и восточный
	_add_clock_face(b, Vector3(-2.25, ty + 7.4, tz), Vector3.LEFT)
	_add_clock_face(b, Vector3(2.25, ty + 7.4, tz), Vector3.RIGHT)

	# Арочная звонница-бельведер над часами
	for sx: float in [-1.6, 1.6]:
		for sz: float in [-1.6, 1.6]:
			b.box(Vector3(sx, ty + 11.2, tz + sz), Vector3(0.6, 2.8, 0.6), WALL_TRIM)
	b.box(Vector3(0.0, ty + 12.8, tz), Vector3(4.6, 0.4, 4.6), WALL_TRIM)

	# Медный пирамидальный шатёр со шпилем
	b.cone(Vector3(0.0, ty + 15.2, tz), 2.8, 4.6, ROOF_COPPER, 4,
		Basis(Vector3.UP, PI * 0.25))
	# Золотой шпиль и флюгер
	b.cylinder(Vector3(0.0, ty + 18.2, tz), 0.08, 0.18, 2.4, GOLD_SPIRE, 6)
	b.sphere(Vector3(0.0, ty + 19.6, tz), 0.32, GOLD_SPIRE, 4, 6)


func _add_clock_face(b: MeshBuilder, pos: Vector3, normal: Vector3) -> void:
	var basis := Basis.IDENTITY
	if normal == Vector3.FORWARD:
		basis = Basis(Vector3.RIGHT, PI * 0.5)
	elif normal == Vector3.BACK:
		basis = Basis(Vector3.RIGHT, -PI * 0.5)
	elif normal == Vector3.LEFT:
		basis = Basis(Vector3.FORWARD, -PI * 0.5)
	elif normal == Vector3.RIGHT:
		basis = Basis(Vector3.FORWARD, PI * 0.5)

	# Ободок и белый диск циферблата
	b.cylinder(pos, 1.3, 1.3, 0.15, WALL_TRIM, 16, basis)
	b.cylinder(pos + normal * 0.08, 1.15, 1.15, 0.08, CLOCK_FACE, 16, basis)
	# Стрелки часов (на 12:15)
	b.box(pos + normal * 0.14 + Vector3(0.0, 0.3, 0.0), Vector3(0.1, 0.65, 0.02), CLOCK_HAND)
	b.box(pos + normal * 0.14 + Vector3(0.3, 0.0, 0.0), Vector3(0.65, 0.1, 0.02), CLOCK_HAND)


# --- Перрон и навес ---------------------------------------------------------

func _build_platform_and_canopy(b: MeshBuilder) -> void:
	# Перрон позади вокзала (+Z)
	var pz := 11.5
	var pw := 52.0
	var pd := 7.0

	# Платформа перрона
	b.box(Vector3(0.0, 0.45, pz), Vector3(pw, 0.9, pd), PAVE_PLAT)
	# Жёлтая тактильная полоса безопасности по краю (+Z)
	b.box(Vector3(0.0, 0.92, pz + pd * 0.5 - 0.3), Vector3(pw, 0.05, 0.45), TACTILE_EDGE)

	# Навес перрона на металлических опорах
	for x_off in range(-20, 25, 10):
		var col_x := float(x_off)
		b.cylinder(Vector3(col_x, 2.5, pz - 1.0), 0.14, 0.18, 3.8, CANOPY_METAL, 6)
		# Y-образный кронштейн навеса
		b.box(Vector3(col_x, 4.4, pz), Vector3(0.2, 0.3, 5.0), CANOPY_METAL)

	# Кровля навеса перрона
	b.box(Vector3(0.0, 4.6, pz), Vector3(pw, 0.15, 5.6), CANOPY_METAL)


# --- Пути и пассажирский состав ---------------------------------------------

func _build_tracks_and_train(b: MeshBuilder) -> void:
	# Первый путь рядом с перроном
	var t1_z := 17.5
	var tw := 56.0

	# Балластная призма (щебень)
	b.box(Vector3(0.0, 0.18, t1_z), Vector3(tw, 0.36, 4.2), BALLAST)

	# Шпалы (поперечные брусья)
	for x_off in range(-26, 27, 2):
		b.box(Vector3(float(x_off), 0.38, t1_z), Vector3(0.25, 0.14, 2.7), TIES_WOOD)

	# Стальные рельсы (две нити, колея 1520 мм)
	for s: float in [-1.0, 1.0]:
		var rz := t1_z + s * 0.76
		b.box(Vector3(0.0, 0.48, rz), Vector3(tw, 0.14, 0.08), RAILS_STEEL)

	# Тупиковый упор в конце пути
	b.box(Vector3(-27.0, 0.8, t1_z), Vector3(0.8, 1.2, 2.2), BASE_STONE)
	b.box(Vector3(-26.5, 0.9, t1_z), Vector3(0.4, 0.5, 2.4), ROOF_COPPER)

	# Пассажирский поезд у перрона: Локомотив + 2 вагона
	# Локомотив (электровоз)
	_build_locomotive(b, Vector3(-12.0, 0.5, t1_z))
	# Пассажирские вагоны
	_build_passenger_car(b, Vector3(5.0, 0.5, t1_z))
	_build_passenger_car(b, Vector3(21.0, 0.5, t1_z))


func _build_locomotive(b: MeshBuilder, pos: Vector3) -> void:
	var ly := pos.y
	# Тележки с колёсами
	for bx: float in [-5.0, 5.0]:
		b.box(pos + Vector3(bx, 0.4, 0.0), Vector3(3.2, 0.6, 2.2), TRAIN_DARK)

	# Кузов локомотива
	b.box(pos + Vector3(0.0, 2.0, 0.0), Vector3(14.0, 2.6, 2.8), TRAIN_GREEN)
	# Фирменная полоса
	b.box(pos + Vector3(0.0, 1.6, 0.0), Vector3(14.2, 0.3, 2.85), TRAIN_STRIPE)
	# Крыша локомотива со скосами
	b.box(pos + Vector3(0.0, 3.4, 0.0), Vector3(13.6, 0.4, 2.6), TRAIN_ROOF)

	# Кабины машиниста и лобовые стёкла
	for s: float in [-1.0, 1.0]:
		var fx := s * 6.6
		b.box(pos + Vector3(fx, 2.2, 0.0), Vector3(0.8, 1.4, 2.6), TRAIN_DARK)
		b.box(pos + Vector3(fx + s * 0.42, 2.3, 0.0), Vector3(0.05, 1.0, 2.2), GLASS_WINDOW)
		# Буферные фонари и прожектор
		b.sphere(pos + Vector3(fx + s * 0.45, 1.4, -0.9), 0.18, TRAIN_LAMP, 4, 6)
		b.sphere(pos + Vector3(fx + s * 0.45, 1.4, 0.9), 0.18, TRAIN_LAMP, 4, 6)
		b.sphere(pos + Vector3(fx + s * 0.45, 3.3, 0.0), 0.22, TRAIN_LAMP, 4, 6)

	# Пантографы (токоприёмники на крыше)
	for px: float in [-3.5, 3.5]:
		b.box(pos + Vector3(px, 3.9, 0.0), Vector3(1.6, 0.6, 1.8), TRAIN_DARK)


func _build_passenger_car(b: MeshBuilder, pos: Vector3) -> void:
	# Кузов пассажирского вагона
	b.box(pos + Vector3(0.0, 0.35, 0.0), Vector3(13.0, 0.5, 2.2), TRAIN_DARK)
	b.box(pos + Vector3(0.0, 1.9, 0.0), Vector3(14.0, 2.5, 2.8), TRAIN_GREEN)
	b.box(pos + Vector3(0.0, 1.5, 0.0), Vector3(14.1, 0.25, 2.85), TRAIN_STRIPE)
	b.box(pos + Vector3(0.0, 3.3, 0.0), Vector3(13.8, 0.4, 2.6), TRAIN_ROOF)

	# Окна купе вдоль вагона
	for ox in range(-5, 6, 2):
		b.box(pos + Vector3(float(ox), 2.1, 1.42), Vector3(1.1, 0.9, 0.05), GLASS_WINDOW)
		b.box(pos + Vector3(float(ox), 2.1, -1.42), Vector3(1.1, 0.9, 0.05), GLASS_WINDOW)


# --- Коллизия ---------------------------------------------------------------

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	# Коллизия здания вокзала (центральный объём)
	var cs_main := CollisionShape3D.new()
	var box_main := BoxShape3D.new()
	box_main.size = Vector3(47.0, 10.0, 15.0)
	cs_main.shape = box_main
	cs_main.position = Vector3(0.0, 5.0, 0.0)
	body.add_child(cs_main)

	# Коллизия перрона и стоящего поезда
	var cs_train := CollisionShape3D.new()
	var box_train := BoxShape3D.new()
	box_train.size = Vector3(56.0, 4.5, 12.0)
	cs_train.shape = box_train
	cs_train.position = Vector3(0.0, 2.25, 14.5)
	body.add_child(cs_train)
