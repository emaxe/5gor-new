extends Node3D
## Озеро Провал — знаменитый подземный карстовый водоём внутри горы Машук.
##
## Включает:
## - Скальный массив горы Машук с уступами и гротом;
## - Исторический каменный портал тоннеля с классическими пилястрами и карнизом;
## - Знаменитых каменных львов, охраняющих вход в тоннель;
## - Тоннель-штольню, ведущую вглубь горы;
## - Подземный карстовый кратер с лазурно-бирюзовым сероводородным озером;
## - Полукруглую смотровую площадку с каменным парапетом и фонарями.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

# Палитра скал и камня
const CLIFF_BASE := Color("#7e796f")
const CLIFF_MID := Color("#8c877d")
const CLIFF_LIGHT := Color("#a29c90")
const PORTAL_STONE := Color("#dfd8c8")
const PORTAL_TRIM := Color("#ece6d8")
const PORTAL_DARK := Color("#b5ad9e")
const LION_STONE := Color("#cfc7b4")
const CAVE_DARK := Color("#1c1b1a")
const CAVE_WALL := Color("#3a3834")

# Вода Провала (знаменитый бирюзовый оттенок из-за серы)
const WATER_TURQUOISE := Color("#20b2aa")
const WATER_DEEP := Color("#0e6660")
const WATER_GLOW := Color("#48d1cc")

# Площадка и фонари
const PAVE_STONE := Color("#bcb5a4")
const PARAPET := Color("#9a9384")
const IRON_LAMP := Color("#2e3033")
const LAMP_GLOW := Color("#fff2cc")


func _ready() -> void:
	var b := MeshBuilder.new()

	_build_mountain_cliff(b)
	_build_proval_lake(b)
	_build_tunnel_portal(b)
	_build_stone_lions(b)
	_build_plaza(b)

	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = PALETTE_MAT
	add_child(mi)

	_build_collision()


# --- Скальный массив Машука -------------------------------------------------

func _build_mountain_cliff(b: MeshBuilder) -> void:
	# Фоновый массив скал горы Машук позади портала (-X сторона, вглубь горы)
	var cx := -12.0
	# Ступенчатые террасы скал
	b.box(Vector3(cx - 6.0, 5.0, 0.0), Vector3(16.0, 10.0, 36.0), CLIFF_BASE)
	b.box(Vector3(cx - 10.0, 9.5, 0.0), Vector3(14.0, 9.0, 32.0), CLIFF_MID)
	b.box(Vector3(cx - 14.0, 14.0, 0.0), Vector3(12.0, 8.0, 26.0), CLIFF_LIGHT)
	# Скальные выступы по бокам портала
	b.cylinder(Vector3(cx + 2.0, 4.0, -10.0), 4.5, 5.5, 8.0, CLIFF_MID, 7)
	b.cylinder(Vector3(cx + 2.0, 4.0, 10.0), 4.5, 5.5, 8.0, CLIFF_MID, 7)
	b.cylinder(Vector3(cx + 1.0, 7.5, -9.0), 3.0, 4.0, 6.0, CLIFF_LIGHT, 6)
	b.cylinder(Vector3(cx + 1.0, 7.5, 9.0), 3.0, 4.0, 6.0, CLIFF_LIGHT, 6)


# --- Подземное озеро в пещере -----------------------------------------------

func _build_proval_lake(b: MeshBuilder) -> void:
	# Пещера с озером располагается в глубине скалы (-X)
	var lx := -18.0
	var ly := 0.2
	var lz := 0.0

	# Стены грота вокруг озера
	b.cylinder(Vector3(lx, ly + 4.0, lz), 9.0, 8.0, 8.0, CAVE_WALL, 10)
	# Купол пещеры
	b.sphere(Vector3(lx, ly + 8.0, lz), 8.5, CAVE_DARK, 6, 12, 0.8)

	# Водная гладь бирюзового озера Провал
	b.cylinder(Vector3(lx, ly + 0.35, lz), 7.2, 7.2, 0.1, WATER_TURQUOISE, 18)
	# Глубинная воронка (конус вглубь)
	b.cylinder(Vector3(lx, ly - 1.5, lz), 6.8, 2.5, 3.5, WATER_DEEP, 14)
	# Бирюзовый ореол свечения воды у берегов
	b.cylinder(Vector3(lx, ly + 0.38, lz), 7.0, 7.0, 0.04, WATER_GLOW, 18)

	# Скалистый бортик пещеры
	b.cylinder(Vector3(lx, ly + 0.6, lz), 7.4, 7.8, 0.5, CLIFF_BASE, 16)


# --- Каменный портал к Провалу ----------------------------------------------

func _build_tunnel_portal(b: MeshBuilder) -> void:
	# Портал обращён на восток (+X) в сторону туристической площади
	var px := -3.5
	var pz := 0.0

	# Цоколь и боковые пилоны портала
	b.box(Vector3(px, 1.2, pz), Vector3(2.4, 2.4, 10.4), PORTAL_DARK)
	# Две массивные пилястры по сторонам арочного входа
	for s: float in [-1.0, 1.0]:
		var pz_col: float = s * 3.2
		b.box(Vector3(px + 0.2, 3.2, pz_col), Vector3(1.6, 6.0, 1.6), PORTAL_STONE)
		b.box(Vector3(px + 0.25, 6.4, pz_col), Vector3(1.8, 0.4, 1.8), PORTAL_TRIM)

	# Тёмный входной проём тоннеля (штольня в скалу)
	b.box(Vector3(px - 1.5, 2.4, pz), Vector3(4.0, 4.4, 3.4), CAVE_DARK)
	# Арочный свод над проёмом
	b.cylinder(Vector3(px - 1.5, 4.4, pz), 1.7, 1.7, 4.0, CAVE_DARK, 10,
		Basis(Vector3.FORWARD, PI * 0.5))

	# Карниз и фриз над входом с надписью
	b.box(Vector3(px + 0.1, 6.6, pz), Vector3(2.0, 0.8, 8.8), PORTAL_TRIM)
	# Табличка «ПРОВАЛЪ» над входом
	b.box(Vector3(px + 0.25, 6.6, pz), Vector3(0.2, 0.5, 3.8), PORTAL_DARK)

	# Треугольный классический фронтон портала
	b.box(Vector3(px, 7.5, pz), Vector3(1.8, 1.0, 7.6), PORTAL_STONE)
	b.box(Vector3(px, 8.3, pz), Vector3(1.8, 0.8, 4.8), PORTAL_STONE)
	b.box(Vector3(px, 8.9, pz), Vector3(1.8, 0.6, 2.2), PORTAL_STONE)
	b.sphere(Vector3(px + 0.1, 9.4, pz), 0.35, PORTAL_TRIM, 4, 8)


# --- Каменные львы у входа --------------------------------------------------

func _build_stone_lions(b: MeshBuilder) -> void:
	var lx := -1.8

	# Два льва на постаментах по бокам входа
	for s: float in [-1.0, 1.0]:
		var lz: float = s * 3.4
		var basis := Basis(Vector3.UP, PI * 0.5 if s > 0.0 else -PI * 0.5)

		# Каменный постамент
		b.box(Vector3(lx, 0.5, lz), Vector3(2.2, 1.0, 1.2), PORTAL_DARK)
		b.box(Vector3(lx, 1.05, lz), Vector3(2.3, 0.15, 1.3), PORTAL_TRIM)

		# Тело лежащего льва
		b.box(Vector3(lx - 0.2, 1.45, lz), Vector3(1.5, 0.65, 0.8), LION_STONE)
		# Передние лапы
		b.box(Vector3(lx + 0.6, 1.25, lz), Vector3(0.6, 0.35, 0.7), LION_STONE)
		# Гордая львиная голова с гривой
		b.sphere(Vector3(lx + 0.45, 1.85, lz), 0.42, LION_STONE, 5, 8)
		b.box(Vector3(lx + 0.75, 1.75, lz), Vector3(0.35, 0.3, 0.35), LION_STONE)


# --- Туристическая площадка перед входом -------------------------------------

func _build_plaza(b: MeshBuilder) -> void:
	# Полукруглая мощёная площадка перед порталом (X от -2 до +16, Z от -14 до +14)
	b.box(Vector3(6.0, 0.08, 0.0), Vector3(16.0, 0.16, 26.0), PAVE_STONE)

	# Полукруглый парапет смотровой площадки с широким парадным входом с дороги
	for i in range(-5, 6):
		if absi(i) <= 1:
			continue # Парадный вход на площадь со стороны разворотного кольца
		var a := float(i) * 0.26
		var ax := 13.5 + cos(a) * 2.0
		var az := sin(a) * 12.0
		b.box(Vector3(ax, 0.6, az), Vector3(0.5, 0.9, 2.6), PARAPET)

	# Два парадных фонаря по краям входа
	for s: float in [-1.0, 1.0]:
		var fx := 15.2
		var fz := s * 3.5
		b.cylinder(Vector3(fx, 1.2, fz), 0.16, 0.2, 1.6, IRON_LAMP, 6)
		b.box(Vector3(fx, 2.3, fz), Vector3(0.4, 0.6, 0.4), LAMP_GLOW)
		b.cone(Vector3(fx, 2.7, fz), 0.5, 0.3, IRON_LAMP, 4, Basis(Vector3.UP, PI * 0.25))


# --- Коллизия ---------------------------------------------------------------

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	# Коллизия скалы позади портала
	var cs_cliff := CollisionShape3D.new()
	var box_cliff := BoxShape3D.new()
	box_cliff.size = Vector3(16.0, 14.0, 36.0)
	cs_cliff.shape = box_cliff
	cs_cliff.position = Vector3(-14.0, 7.0, 0.0)
	body.add_child(cs_cliff)

	# Коллизия портала (левое и правое крыло, проход свободен)
	for s: float in [-1.0, 1.0]:
		var cs_side := CollisionShape3D.new()
		var box_side := BoxShape3D.new()
		box_side.size = Vector3(4.0, 8.0, 4.0)
		cs_side.shape = box_side
		cs_side.position = Vector3(-3.5, 4.0, s * 4.0)
		body.add_child(cs_side)

	# Коллизия постаментов со львами
	for s: float in [-1.0, 1.0]:
		var cs_lion := CollisionShape3D.new()
		var box_lion := BoxShape3D.new()
		box_lion.size = Vector3(2.4, 2.0, 1.4)
		cs_lion.shape = box_lion
		cs_lion.position = Vector3(-1.8, 1.0, s * 3.4)
		body.add_child(cs_lion)
