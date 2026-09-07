extends Node3D
## Пятигорская телевышка на вершине горы Машук (высота 113 м, открыта в 1959 г.).
##
## Включает:
## - 4-опорную стальную решётчатую конструкцию с характерными красно-белыми поясами;
## - Сервисные площадки и площадки ретрансляторов с перилами;
## - Параболические радиорелейные антенны-тарелки;
## - Верхний антенный шпиль с красным заградительным маяком;
## - Мощёную смотровую площадку вершины с ограждением;
## - Легендарный столб с деревянными указателями городов и расстояний.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

# Палитра телевышки (авиационная маркировка красно-белая)
const TOWER_RED := Color("#d62828")
const TOWER_WHITE := Color("#f4f4f6")
const STEEL_DARK := Color("#2e3238")
const BEACON_RED := Color("#ff2222")
const DISH_WHITE := Color("#dedede")
const PAVE_STONE := Color("#a8a294")
const RAILING := Color("#3a3c40")

# Столб с указателями городов
const POST_WOOD := Color("#6c4a2a")
const ARROW_BLUE := Color("#2a6db5")
const ARROW_RED := Color("#b5322a")
const ARROW_YELLOW := Color("#d49826")
const ARROW_GREEN := Color("#2e8042")

const SECTIONS := 8
const SECTION_H := 5.2
const BASE_W := 8.4


func _ready() -> void:
	var b := MeshBuilder.new()

	_build_summit_terrace(b)
	_build_lattice_tower(b)
	_build_antennas_and_platforms(b)
	_build_city_signpost(b)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = PALETTE_MAT
	add_child(mi)

	_build_collision()


# --- Смотровая площадка вершины ---------------------------------------------

func _build_summit_terrace(b: MeshBuilder) -> void:
	# Круглая мощёная площадка вершины Машука вокруг вышки
	b.cylinder(Vector3(0.0, 0.15, 0.0), 12.0, 12.4, 0.3, PAVE_STONE, 24)

	# Защитное перильное ограждение по краю смотровой площадки
	for i in 20:
		var a := TAU * float(i) / 20.0
		var px := cos(a) * 11.5
		var pz := sin(a) * 11.5
		# Стойка перил
		b.cylinder(Vector3(px, 0.7, pz), 0.05, 0.05, 0.9, RAILING, 4)
		# Поручень
		var a_next := TAU * float(i + 1) / 20.0
		var nx := cos(a_next) * 11.5
		var nz := sin(a_next) * 11.5
		var mid := (Vector3(px, 1.15, pz) + Vector3(nx, 1.15, nz)) * 0.5
		var seg_len := Vector3(px, 0.0, pz).distance_to(Vector3(nx, 0.0, nz))
		var dir := (Vector3(nx, 0.0, nz) - Vector3(px, 0.0, pz)).normalized()
		var basis := Basis(Vector3.UP.cross(dir).normalized(), PI * 0.5) \
			if Vector3.UP.cross(dir).length() > 0.001 else Basis.IDENTITY
		b.cylinder(mid, 0.04, 0.04, seg_len, RAILING, 4, basis)


# --- 4-опорная решётчатая телевышка ----------------------------------------

func _build_lattice_tower(b: MeshBuilder) -> void:
	# 4 бетонных фундамента под ногами башни
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var fx: float = sx * BASE_W * 0.5
			var fz: float = sz * BASE_W * 0.5
			b.box(Vector3(fx, 0.5, fz), Vector3(1.6, 0.8, 1.6), STEEL_DARK)

	# 8 сужающихся ярусов вышки с чередованием красного и белого
	for i in SECTIONS:
		var t1 := float(i) / float(SECTIONS)
		var t2 := float(i + 1) / float(SECTIONS)
		var w1 := lerpf(BASE_W, 1.4, t1)
		var w2 := lerpf(BASE_W, 1.4, t2)
		var y1 := 0.8 + float(i) * SECTION_H
		var y2 := y1 + SECTION_H
		var y_mid := (y1 + y2) * 0.5

		var col: Color = TOWER_WHITE if i % 2 == 1 else TOWER_RED

		# 4 угловые наклонные стойки (ноги)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var p1 := Vector3(sx * w1 * 0.5, y1, sz * w1 * 0.5)
				var p2 := Vector3(sx * w2 * 0.5, y2, sz * w2 * 0.5)
				var mid := (p1 + p2) * 0.5
				var seg_len := p1.distance_to(p2)
				var dir := (p2 - p1).normalized()
				var axis := Vector3.UP.cross(dir)
				var basis := Basis(axis.normalized(), Vector3.UP.angle_to(dir)) \
					if axis.length() > 0.001 else Basis.IDENTITY
				b.cylinder(mid, 0.16, 0.20, seg_len, col, 5, basis)

		# Горизонтальные пояса жёсткости
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(0.0, y2, sx * w2 * 0.5), Vector3(w2, 0.2, 0.2), col)
			b.box(Vector3(sx * w2 * 0.5, y2, 0.0), Vector3(0.2, 0.2, w2), col)

		# Диагональные крестовые раскосы (X-bracing) по 4 сторонам
		_add_x_bracing(b, w1, w2, y1, y2, col)


func _add_x_bracing(b: MeshBuilder, w1: float, w2: float, y1: float, y2: float, col: Color) -> void:
	# Добавляем диагональные раскосы для прочности силуэта
	for sx: float in [-1.0, 1.0]:
		var z1: float = sx * w1 * 0.5
		var z2: float = sx * w2 * 0.5
		# Диагональ 1
		var a1 := Vector3(-w1 * 0.5, y1, z1)
		var c1 := Vector3(w2 * 0.5, y2, z2)
		var mid1 := (a1 + c1) * 0.5
		b.cylinder(mid1, 0.06, 0.06, a1.distance_to(c1), col, 4,
			Basis(Vector3.FORWARD, 0.5 * sx))
		# Диагональ 2
		var a2 := Vector3(w1 * 0.5, y1, z1)
		var c2 := Vector3(-w2 * 0.5, y2, z2)
		var mid2 := (a2 + c2) * 0.5
		b.cylinder(mid2, 0.06, 0.06, a2.distance_to(c2), col, 4,
			Basis(Vector3.FORWARD, -0.5 * sx))


# --- Антенны, платформы и шпиль ---------------------------------------------

func _build_antennas_and_platforms(b: MeshBuilder) -> void:
	var total_tower_h := 0.8 + SECTIONS * SECTION_H

	# 1. Промежуточная сервисная площадка на 3-м ярусе
	var p1_y := 0.8 + 3.0 * SECTION_H
	b.box(Vector3(0.0, p1_y, 0.0), Vector3(6.2, 0.25, 6.2), STEEL_DARK)
	# Перила площадки
	b.box(Vector3(0.0, p1_y + 0.5, -3.0), Vector3(6.0, 0.8, 0.1), RAILING)
	b.box(Vector3(0.0, p1_y + 0.5, 3.0), Vector3(6.0, 0.8, 0.1), RAILING)

	# 2. Верхняя технологическая площадка
	var p2_y := total_tower_h
	b.box(Vector3(0.0, p2_y, 0.0), Vector3(2.6, 0.3, 2.6), STEEL_DARK)

	# 3. Радиорелейные антенны-тарелки (диски)
	for s: float in [-1.0, 1.0]:
		var dx: float = s * 2.6
		b.cylinder(Vector3(dx, p1_y + 1.2, 0.0), 0.9, 0.9, 0.25, DISH_WHITE, 12,
			Basis(Vector3.FORWARD, PI * 0.5))
		b.cylinder(Vector3(dx, p1_y + 1.2, 0.0), 0.08, 0.08, 0.8, STEEL_DARK, 6,
			Basis(Vector3.FORWARD, PI * 0.5))

	# 4. Верхняя игла-шпиль с антенной решёткой
	var spire_h := 12.0
	b.cylinder(Vector3(0.0, p2_y + spire_h * 0.5, 0.0), 0.12, 0.35, spire_h, TOWER_RED, 6)

	# Заградительный маяк на верхушке
	var beacon_y := p2_y + spire_h + 0.4
	b.sphere(Vector3(0.0, beacon_y, 0.0), 0.45, BEACON_RED, 4, 8)
	b.sphere(Vector3(0.0, beacon_y, 0.0), 0.25, Color("#ffffff"), 4, 6)


# --- Знаменитый столб с указателями городов ---------------------------------

func _build_city_signpost(b: MeshBuilder) -> void:
	# Легендарный столб стоит с краю площадки (X=6.5, Z=4.0)
	var sx := 6.5
	var sz := 4.0
	var sy := 0.3

	# Каменный фундамент и деревянный столб
	b.cylinder(Vector3(sx, sy + 0.2, sz), 0.45, 0.55, 0.4, PAVE_STONE, 8)
	b.cylinder(Vector3(sx, sy + 2.2, sz), 0.14, 0.18, 3.8, POST_WOOD, 6)

	# Разноцветные деревянные стрелы-указатели городов с расстояниями
	var signs: Array[Dictionary] = [
		{"ang": 0.3, "h": 1.6, "col": ARROW_BLUE},     # МОСКВА 1340 км
		{"ang": 1.2, "h": 2.0, "col": ARROW_RED},      # ПАРИЖ 3100 км
		{"ang": 2.4, "h": 2.4, "col": ARROW_YELLOW},   # ЭЛЬБРУС 90 км
		{"ang": 3.7, "h": 2.8, "col": ARROW_GREEN},    # ВЛАДИВОСТОК 6900 км
		{"ang": 4.8, "h": 3.2, "col": ARROW_BLUE},     # САНКТ-ПЕТЕРБУРГ 1980 км
		{"ang": 5.8, "h": 3.6, "col": ARROW_RED},      # ПЯТИГОРСК 0 км
	]

	for s: Dictionary in signs:
		var basis := Basis(Vector3.UP, float(s["ang"]))
		var sh := float(s["h"])
		var scol: Color = s["col"]
		# Стрела-табличка
		b.box(Vector3(sx, sy + sh, sz) + basis * Vector3(0.7, 0.0, 0.0),
			Vector3(1.4, 0.24, 0.06), scol, basis)
		# Острый кончик стрелы
		b.cone(Vector3(sx, sy + sh, sz) + basis * Vector3(1.5, 0.0, 0.0),
			0.18, 0.3, scol, 3, basis * Basis(Vector3.FORWARD, -PI * 0.5))


# --- Коллизия ---------------------------------------------------------------

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	# Коллизия основания вышки
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = BASE_W * 0.55
	cyl.height = SECTIONS * SECTION_H
	cs.shape = cyl
	cs.position = Vector3(0.0, SECTIONS * SECTION_H * 0.5, 0.0)
	body.add_child(cs)

	# Коллизия столба с указателями
	var cs_post := CollisionShape3D.new()
	var cyl_p := CylinderShape3D.new()
	cyl_p.radius = 0.5
	cyl_p.height = 4.0
	cs_post.shape = cyl_p
	cs_post.position = Vector3(6.5, 2.0, 4.0)
	body.add_child(cs_post)
