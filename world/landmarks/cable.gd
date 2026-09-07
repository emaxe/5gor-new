extends Node3D
## Нижняя станция Пятигорской канатной дороги на гору Машук (открыта в 1971 г.).
##
## Включает:
## - Павильон нижней станции в стиле советского модернизма с панорамным остеклением;
## - Приводной шкив (колесо канатной дороги) и посадочный перрон;
## - Решётчатую стальную опору канатной дороги на склоне горы;
## - Стальные несущие канаты, уходящие вверх к вершине Машука;
## - Пассажирские вагончики канатки в фирменной красно-жёлтой окраске.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

# Палитра станции
const CONCRETE_LIGHT := Color("#ded8cc")
const CONCRETE_BASE := Color("#9a9386")
const STEEL_DARK := Color("#35373a")
const STEEL_CABLE := Color("#202224")
const GLASS_FACADE := Color("#2e3d48")
const ROOF_METAL := Color("#48535e")
const WHEEL_YELLOW := Color("#d49826")

# Вагончики канатки
const CAB_RED := Color("#c63428")
const CAB_YELLOW := Color("#f0b828")
const CAB_ROOF := Color("#dedede")
const CAB_GLASS := Color("#446278")


func _ready() -> void:
	var b := MeshBuilder.new()

	_build_station_building(b)
	_build_cable_mechanism(b)
	_build_hillside_pylon(b)
	_build_cables_and_cabins(b)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = PALETTE_MAT
	add_child(mi)

	_build_collision()


# --- Здание нижней станции --------------------------------------------------

func _build_station_building(b: MeshBuilder) -> void:
	# Павильон станции (длина 14 м, ширина 10 м, высота 6.5 м)
	# Цоколь
	b.box(Vector3(0.0, 0.5, 0.0), Vector3(14.4, 1.0, 10.4), CONCRETE_BASE)

	# Основной корпус
	b.box(Vector3(0.0, 3.2, 0.0), Vector3(14.0, 5.0, 10.0), CONCRETE_LIGHT)

	# Панорамное скошенное остекление кассового зала и перрона (на запад, -X)
	b.box(Vector3(-7.05, 3.2, 0.0), Vector3(0.1, 4.2, 8.8), GLASS_FACADE)
	for z_bar: float in [-3.0, 0.0, 3.0]:
		b.box(Vector3(-7.1, 3.2, z_bar), Vector3(0.15, 4.4, 0.15), STEEL_DARK)

	# Выступающая консольная крыша станции
	b.box(Vector3(-1.0, 6.0, 0.0), Vector3(16.0, 0.6, 11.2), ROOF_METAL)

	# Вывеска над входом «КАНАТНАЯ ДОРОГА»
	b.box(Vector3(-7.5, 5.6, 0.0), Vector3(0.3, 0.8, 7.2), STEEL_DARK)
	b.box(Vector3(-7.6, 5.6, 0.0), Vector3(0.1, 0.5, 6.8), WHEEL_YELLOW)


# --- Приводной механизм канатки ---------------------------------------------

func _build_cable_mechanism(b: MeshBuilder) -> void:
	# Большое колесо-шкив канатной дороги на выходе со станции
	var my := 5.8
	var mx := 3.5

	# Стальная рама крепления шкивов
	b.box(Vector3(mx, my + 0.8, 0.0), Vector3(3.4, 1.6, 6.0), STEEL_DARK)

	# Два больших желтых направляющих шкива (колеса)
	for s: float in [-1.0, 1.0]:
		var wz: float = s * 2.2
		b.cylinder(Vector3(mx, my + 1.2, wz), 1.6, 1.6, 0.35, WHEEL_YELLOW, 16,
			Basis(Vector3.FORWARD, PI * 0.5))
		b.cylinder(Vector3(mx, my + 1.2, wz), 0.4, 0.4, 0.45, STEEL_DARK, 8,
			Basis(Vector3.FORWARD, PI * 0.5))


# --- Промежуточная опора на склоне -----------------------------------------

func _build_hillside_pylon(b: MeshBuilder) -> void:
	# Опора канатной дороги выше по склону (сдвиг +X, +Y, -Z в сторону вершины)
	var px := 22.0
	var py := 8.5
	var pz := -14.0

	# Бетонное основание опоры
	b.box(Vector3(px, py + 0.5, pz), Vector3(3.2, 1.0, 4.8), CONCRETE_BASE)

	# Стальная А-образная решётчатая опора
	for s: float in [-1.0, 1.0]:
		var oz: float = s * 1.8
		b.cylinder(Vector3(px - 0.6, py + 5.0, pz + oz), 0.18, 0.28, 8.0, STEEL_DARK, 6)
		b.cylinder(Vector3(px + 0.6, py + 5.0, pz + oz), 0.18, 0.28, 8.0, STEEL_DARK, 6)

	# Траверса опоры (горизонтальная перекладина с роликами)
	b.box(Vector3(px, py + 9.2, pz), Vector3(1.2, 0.5, 7.2), STEEL_DARK)

	# Балансиры с роликами под несущий канат
	for s: float in [-1.0, 1.0]:
		var rz: float = pz + s * 2.6
		b.cylinder(Vector3(px, py + 9.6, rz), 0.35, 0.35, 0.8, WHEEL_YELLOW, 8,
			Basis(Vector3.FORWARD, PI * 0.5))


# --- Тросы и вагончики канатной дороги --------------------------------------

func _build_cables_and_cabins(b: MeshBuilder) -> void:
	# Траектория тросов: от станции (X=4) через опору (X=22) вверх к вершине Машука (X=50, Y=35, Z=-40)
	var start_l := Vector3(4.0, 7.0, -2.2)
	var pylon_l := Vector3(22.0, 18.1, -16.6)
	var top_l := Vector3(55.0, 36.0, -42.0)

	var start_r := Vector3(4.0, 7.0, 2.2)
	var pylon_r := Vector3(22.0, 18.1, -11.4)
	var top_r := Vector3(55.0, 36.0, -37.0)

	_add_cable_segment(b, start_l, pylon_l)
	_add_cable_segment(b, pylon_l, top_l)

	_add_cable_segment(b, start_r, pylon_r)
	_add_cable_segment(b, pylon_r, top_r)

	# Нижний красный вагончик (у станции, готов к отправлению)
	_build_cabin(b, Vector3(5.5, 4.2, -2.2), CAB_RED)

	# Верхний жёлтый вагончик (на маршруте, спускается)
	_build_cabin(b, Vector3(32.0, 21.0, -14.0), CAB_YELLOW)


func _add_cable_segment(b: MeshBuilder, a: Vector3, c: Vector3) -> void:
	var mid := (a + c) * 0.5
	var seg_len := a.distance_to(c)
	var dir := (c - a).normalized()
	var basis := Basis.IDENTITY
	var axis := Vector3.UP.cross(dir)
	if axis.length() > 0.001:
		basis = Basis(axis.normalized(), Vector3.UP.angle_to(dir))
	b.cylinder(mid, 0.06, 0.06, seg_len, STEEL_CABLE, 4, basis)


func _build_cabin(b: MeshBuilder, pos: Vector3, color: Color) -> void:
	# Подвеска вагончика к тросу (вертикальная штанга и тележка с роликами)
	b.box(pos + Vector3(0.0, 2.6, 0.0), Vector3(0.12, 1.8, 0.12), STEEL_DARK)
	b.cylinder(pos + Vector3(0.0, 3.5, 0.0), 0.16, 0.16, 0.5, WHEEL_YELLOW, 6,
		Basis(Vector3.FORWARD, PI * 0.5))

	# Корпус вагончика канатки (характерная форма с закруглением)
	b.box(pos + Vector3(0.0, 0.9, 0.0), Vector3(2.6, 1.6, 1.8), color)
	b.box(pos + Vector3(0.0, 1.75, 0.0), Vector3(2.5, 0.2, 1.7), CAB_ROOF)

	# Панорамные окна вагончика
	for s: float in [-1.0, 1.0]:
		var gz: float = s * 0.92
		b.box(pos + Vector3(0.0, 1.05, gz), Vector3(2.3, 0.75, 0.05), CAB_GLASS)
	for s: float in [-1.0, 1.0]:
		var gx: float = s * 1.32
		b.box(pos + Vector3(gx, 1.05, 0.0), Vector3(0.05, 0.75, 1.5), CAB_GLASS)


# --- Коллизия ---------------------------------------------------------------

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	# Коллизия здания станции
	var cs_station := CollisionShape3D.new()
	var box_st := BoxShape3D.new()
	box_st.size = Vector3(14.5, 7.0, 10.5)
	cs_station.shape = box_st
	cs_station.position = Vector3(0.0, 3.5, 0.0)
	body.add_child(cs_station)

	# Коллизия опоры на склоне
	var cs_pylon := CollisionShape3D.new()
	var box_p := BoxShape3D.new()
	box_p.size = Vector3(3.4, 10.0, 5.0)
	cs_pylon.shape = box_p
	cs_pylon.position = Vector3(22.0, 13.0, -14.0)
	body.add_child(cs_pylon)
