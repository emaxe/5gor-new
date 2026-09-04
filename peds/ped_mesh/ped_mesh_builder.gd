class_name PedMeshBuilder
extends RefCounted
## Процедурный риг пешехода/собаки/кошки. Порт buildPedMesh/buildDogMesh/
## buildCatMesh (utils.js:362-793), в духе vehicles/car_mesh/car_mesh_builder.gd —
## но НЕ мержится в один меш: ноги/руки/голова/хвост крутятся при ходьбе
## (аниматор — в PedLayer), поэтому каждая часть рига возвращается отдельным
## ArrayMesh, который вызывающий код ставит на свой пивот-узел.
##
## Голова человека строится в АБСОЛЮТНЫХ Y-координатах оригинала, затем
## сдвигается на -HEAD_PIVOT_Y — ровно как headGeo.translate(0,-HEAD_PIVOT_Y,0)
## в оригинале. У животных headGroup/tail в оригинале и так локальны —
## поэтому их части строятся сразу в координатах пивота, без сдвига.
##
## Сознательные упрощения относительно оригинала (весь блок буквально
## случаен в JS через Math.random() внутри конструктора — здесь Spec
## детерминирован, случайность/выбор палитры остаются на вызывающем коде):
## очки, шарф, вторая причёска-вариант и капюшон-гитара музыканта опущены;
## авоська/сумка/гармонь берутся в ЕДИНСТВЕННОМ варианте вместо случайного
## выбора между двумя; платок/наушники/фонендоскоп (в оригинале — Torus,
## которого нет в MeshBuilder) заменены ближайшими по силуэту примитивами
## (сфера/цилиндр).

const HEAD_PIVOT_Y := 1.42

## Пивоты человека. X зеркалится вызывающим кодом (±).
const HUMAN_LEG_PIVOT := Vector3(0.13, 1.05, 0.0)
const HUMAN_ARM_PIVOT := Vector3(0.39, 1.32, 0.0)

## Пивоты собаки (headGroup/tail.position и legPositions[i] оригинала).
const DOG_HEAD_PIVOT := Vector3(0.0, 0.52, 0.3)
const DOG_TAIL_PIVOT := Vector3(0.0, 0.42, -0.32)
const DOG_LEG_PIVOTS: Array[Vector3] = [
	Vector3(-0.12, 0.32, 0.22), Vector3(0.12, 0.32, 0.22),
	Vector3(-0.12, 0.32, -0.22), Vector3(0.12, 0.32, -0.22),
]
const DOG_SCALE := 1.1

## Пивоты кошки.
const CAT_HEAD_PIVOT := Vector3(0.0, 0.36, 0.2)
const CAT_TAIL_PIVOT := Vector3(0.0, 0.3, -0.22)
const CAT_LEG_PIVOTS: Array[Vector3] = [
	Vector3(-0.08, 0.22, 0.16), Vector3(0.08, 0.22, 0.16),
	Vector3(-0.08, 0.22, -0.16), Vector3(0.08, 0.22, -0.16),
]
const CAT_SCALE := 0.95

const _NOSE := Color("#1a1a1a")
const _PINK_NOSE := Color("#eeaaab")
const _WHITE := Color("#dddddd")


## Параметры конкретного пешехода-человека. Палитра и аксессуары —
## PedArchetypeData/PedCatalog переносятся сюда вызывающим кодом.
class Spec extends RefCounted:
	var skin_color := Color("#d8a878")
	var hair_color := Color("#1a1a1a")
	var shoe_color := Color("#202020")
	var cloth_color := Color("#4060a0")
	var pants_color := Color("#2a2a3a")
	var accessories: PackedStringArray = PackedStringArray()


## Риг человека: 4 отдельных меша на пивоты (голова + 2 руки + 2 ноги, руки
## и ноги переиспользуют один и тот же меш на обеих сторонах — зеркалится
## только позиция пивота, не геометрия).
class HumanRig extends RefCounted:
	var torso_mesh: ArrayMesh
	var head_mesh: ArrayMesh
	var arm_mesh: ArrayMesh
	var leg_mesh: ArrayMesh


## Риг животного: тело + голова + хвост + одна нога на 4 пивота.
class AnimalRig extends RefCounted:
	var body_mesh: ArrayMesh
	var head_mesh: ArrayMesh
	var tail_mesh: ArrayMesh
	var leg_mesh: ArrayMesh


static func build_human(spec: Spec) -> HumanRig:
	var rig := HumanRig.new()
	rig.torso_mesh = _build_torso(spec)
	rig.head_mesh = _build_head(spec)
	rig.arm_mesh = _build_arm(spec)
	rig.leg_mesh = _build_leg(spec)
	return rig


# --- Торс + экипировка --------------------------------------------------------

static func _build_torso(spec: Spec) -> ArrayMesh:
	var b := MeshBuilder.new()

	# Анатомичный low-poly торс с сужением к талии
	# Грудная клетка
	b.tapered_box(Vector3(0.0, 1.16, 0.0), Vector3(0.54, 0.42, 0.32),
		spec.cloth_color, Vector2(0.92, 0.94))
	# Нижняя часть торса / живот
	b.tapered_box(Vector3(0.0, 0.88, 0.0), Vector3(0.48, 0.28, 0.29),
		spec.cloth_color, Vector2(1.08, 1.06))

	# Пояс и пряжка
	var belt_col: Color = spec.pants_color.darkened(0.35).lerp(Color("#1a1a1a"), 0.5)
	b.box(Vector3(0.0, 0.73, 0.0), Vector3(0.48, 0.08, 0.29), belt_col)
	b.box(Vector3(0.0, 0.73, 0.15), Vector3(0.09, 0.07, 0.02), Color("#d4af37"))

	# Воротник и лацканы куртки / пальто
	b.box(Vector3(0.0, 1.37, 0.06), Vector3(0.28, 0.08, 0.12), spec.cloth_color.lightened(0.12))
	# Центральная планка / молния
	b.box(Vector3(0.0, 1.08, 0.165), Vector3(0.05, 0.52, 0.02), _WHITE)

	for tag in spec.accessories:
		match String(tag):
			"cane":
				# Трость с изогнутой рукоятью
				b.cylinder(Vector3(0.38, 0.72, 0.1), 0.025, 0.025, 1.05, Color("#4e3218"), 6)
				b.box(Vector3(0.38, 1.25, 0.14), Vector3(0.05, 0.05, 0.14), Color("#b8860b"))
			"shoulder_bag":
				# Ремень через плечо
				b.box(Vector3(0.0, 1.1, 0.165), Vector3(0.04, 0.58, 0.02), Color("#181818"),
					Basis(Vector3.BACK, 0.58))
				b.box(Vector3(0.0, 1.1, -0.165), Vector3(0.04, 0.58, 0.02), Color("#181818"),
					Basis(Vector3.BACK, -0.58))
				# Сумка на бедре
				b.box(Vector3(0.26, 0.82, 0.06), Vector3(0.12, 0.24, 0.26), Color("#3e2616"))
				b.box(Vector3(0.26, 0.88, 0.06), Vector3(0.13, 0.10, 0.27), Color("#28160c"))
			"stripes":
				# Спортивные лампасы на одежде
				b.box(Vector3(0.275, 1.12, 0.0), Vector3(0.02, 0.50, 0.18), _WHITE)
				b.box(Vector3(-0.275, 1.12, 0.0), Vector3(0.02, 0.50, 0.18), _WHITE)
			"string_bag":
				# Авоська с покупками
				b.box(Vector3(0.36, 0.82, 0.1), Vector3(0.20, 0.26, 0.18), Color("#d4cca6"))
				b.box(Vector3(0.36, 0.96, 0.1), Vector3(0.03, 0.12, 0.03), Color("#a69c76"))
				b.sphere(Vector3(0.36, 0.88, 0.12), 0.06, Color("#e63946"), 3, 5) # яблоко
				b.sphere(Vector3(0.34, 0.89, 0.06), 0.05, Color("#ffb703"), 3, 5) # апельсин
			"stroller":
				# Детская коляска
				b.box(Vector3(0.0, 0.72, 0.55), Vector3(0.48, 0.38, 0.68), Color("#2b5c8f"))
				b.box(Vector3(0.0, 0.94, 0.36), Vector3(0.46, 0.22, 0.34), Color("#1d4069")) # капюшон
				b.box(Vector3(0.0, 1.05, 0.22), Vector3(0.42, 0.04, 0.44), Color("#4a4a4a")) # ручка
				var wheel_basis := Basis(Vector3.RIGHT, PI * 0.5)
				for sx: float in [-0.24, 0.24]:
					b.cylinder(Vector3(sx, 0.32, 0.34), 0.12, 0.12, 0.06, Color("#1a1a1a"), 8, wheel_basis)
					b.cylinder(Vector3(sx, 0.32, 0.76), 0.12, 0.12, 0.06, Color("#1a1a1a"), 8, wheel_basis)
			"instrument":
				# Чехол с гитарой/инструментом
				b.box(Vector3(0.0, 1.08, 0.24), Vector3(0.38, 0.38, 0.16), Color("#7c2828"))
				b.box(Vector3(0.0, 1.34, 0.24), Vector3(0.14, 0.36, 0.12), Color("#7c2828"))
				b.box(Vector3(0.0, 1.08, 0.18), Vector3(0.36, 0.24, 0.04), _WHITE)
			"stethoscope":
				# Фонендоскоп на шее
				b.cylinder(Vector3(0.0, 1.35, 0.14), 0.12, 0.12, 0.04, Color("#1a1a1a"), 10,
					Basis(Vector3.RIGHT, PI * 0.5))
				b.box(Vector3(0.0, 1.18, 0.17), Vector3(0.03, 0.20, 0.02), Color("#222222"))
				b.cylinder(Vector3(0.0, 1.06, 0.18), 0.04, 0.04, 0.02, Color("#c0c0c0"), 8,
					Basis(Vector3.RIGHT, PI * 0.5))
			"backpack":
				# Городской рюкзак с карманами и стропами
				var bag := Color("#244a72")
				b.box(Vector3(0.0, 1.12, -0.24), Vector3(0.38, 0.44, 0.18), bag)
				b.box(Vector3(0.0, 0.98, -0.34), Vector3(0.28, 0.22, 0.08), bag.darkened(0.15))
				b.box(Vector3(0.0, 1.10, -0.34), Vector3(0.24, 0.02, 0.09), Color("#e0e0e0"))
				b.box(Vector3(-0.14, 1.18, -0.06), Vector3(0.06, 0.38, 0.22), bag.darkened(0.2))
				b.box(Vector3(0.14, 1.18, -0.06), Vector3(0.06, 0.38, 0.22), bag.darkened(0.2))
			"camera":
				# Фотоаппарат на ремешке
				b.box(Vector3(0.0, 1.16, 0.22), Vector3(0.20, 0.14, 0.10), Color("#1c1c1e"))
				b.cylinder(Vector3(0.03, 1.16, 0.28), 0.06, 0.06, 0.06, Color("#44484e"), 8,
					Basis(Vector3.RIGHT, PI * 0.5))
				b.box(Vector3(0.0, 1.28, 0.15), Vector3(0.26, 0.18, 0.02), Color("#333333"),
					Basis(Vector3.FORWARD, 0.2))
			"hi_vis":
				# Сигнальный жилет со светоотражающими полосами
				var hv := Color("#d8e632")
				b.box(Vector3(0.0, 1.16, 0.17), Vector3(0.52, 0.42, 0.02), hv)
				b.box(Vector3(0.0, 1.16, -0.17), Vector3(0.52, 0.42, 0.02), hv)
				b.box(Vector3(0.0, 1.22, 0.175), Vector3(0.53, 0.05, 0.02), Color("#f0f0f0"))
				b.box(Vector3(0.0, 0.98, 0.175), Vector3(0.53, 0.05, 0.02), Color("#f0f0f0"))
			"wrench":
				b.box(Vector3(0.38, 0.92, 0.08), Vector3(0.04, 0.48, 0.04), Color("#888d94"))
				b.box(Vector3(0.38, 1.16, 0.08), Vector3(0.09, 0.06, 0.04), Color("#888d94"))
			"briefcase":
				# Кожаный портфель с замками
				b.box(Vector3(0.36, 0.82, 0.06), Vector3(0.10, 0.26, 0.36), Color("#241a14"))
				b.box(Vector3(0.36, 0.96, 0.06), Vector3(0.04, 0.05, 0.12), Color("#18100c"))
				b.box(Vector3(0.36, 0.85, -0.06), Vector3(0.105, 0.03, 0.03), Color("#d4af37"))
				b.box(Vector3(0.36, 0.85, 0.06), Vector3(0.105, 0.03, 0.03), Color("#d4af37"))
			_:
				pass
	return b.commit()


# --- Голова + головные уборы и причёски ---------------------------------------

static func _head_y(abs_y: float) -> float:
	return abs_y - HEAD_PIVOT_Y


static func _build_head(spec: Spec) -> ArrayMesh:
	var b := MeshBuilder.new()

	var hat_type := ""
	for tag in spec.accessories:
		match String(tag):
			"cap", "headscarf", "beret", "nurse_cap", "panama", "helmet":
				hat_type = String(tag)
				break

	var has_hat := hat_type != ""

	# Шея
	b.cylinder(Vector3(0.0, _head_y(1.44), 0.0), 0.11, 0.13, 0.12, spec.skin_color, 7)

	# Скульптурная low-poly голова
	if has_hat:
		# Усечённая снизу/сверху голова под шапкой (лицо и челюсть, верх накрыт шапкой)
		b.sphere(Vector3(0.0, _head_y(1.54), 0.02), 0.22, spec.skin_color, 5, 8, 0.70)
	else:
		# Полная голова
		b.sphere(Vector3(0.0, _head_y(1.60), 0.0), 0.24, spec.skin_color, 5, 8, 1.0)

	# Нос и подбородок
	b.box(Vector3(0.0, _head_y(1.58), 0.23), Vector3(0.05, 0.08, 0.07), spec.skin_color)
	b.box(Vector3(0.0, _head_y(1.49), 0.11), Vector3(0.16, 0.08, 0.14), spec.skin_color)

	# Уши
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.22, _head_y(1.56), 0.0), Vector3(0.03, 0.08, 0.06), spec.skin_color)

	for tag in spec.accessories:
		match String(tag):
			"beard":
				b.sphere(Vector3(0.0, _head_y(1.50), 0.11), 0.19, Color("#dcdcdc"), 4, 6, 0.7)
			"cap":
				# Бейсболка с объемным куполом и козырьком
				b.cylinder(Vector3(0.0, _head_y(1.66), 0.0), 0.28, 0.28, 0.06, Color("#1f2428"), 12)
				b.sphere(Vector3(0.0, _head_y(1.69), -0.02), 0.29, Color("#1f2428"), 5, 8, 0.75)
				b.box(Vector3(0.0, _head_y(1.65), 0.24), Vector3(0.26, 0.025, 0.18), Color("#181c20"),
					Basis(Vector3.RIGHT, -0.15))
				b.sphere(Vector3(0.0, _head_y(1.86), -0.02), 0.035, Color("#d4af37"), 3, 5)
			"headscarf":
				# Платок / косынка
				b.sphere(Vector3(0.0, _head_y(1.66), 0.0), 0.29, Color("#d89898"), 5, 8, 0.95)
				b.box(Vector3(0.0, _head_y(1.46), 0.14), Vector3(0.14, 0.12, 0.08), Color("#b87878"))
			"beret":
				# Французский / курортный берет
				b.cylinder(Vector3(0.0, _head_y(1.66), 0.0), 0.27, 0.27, 0.05, Color("#882424"), 12)
				b.sphere(Vector3(0.0, _head_y(1.70), -0.02), 0.33, Color("#882424"), 5, 8, 0.70)
				b.cylinder(Vector3(0.0, _head_y(1.90), -0.02), 0.015, 0.015, 0.04, Color("#882424"), 4)
			"nurse_cap":
				b.cylinder(Vector3(0.0, _head_y(1.66), 0.0), 0.27, 0.27, 0.06, Color("#ffffff"), 12)
				b.box(Vector3(0.0, _head_y(1.76), 0.04), Vector3(0.28, 0.14, 0.24), Color("#ffffff"))
				b.box(Vector3(0.0, _head_y(1.76), 0.165), Vector3(0.09, 0.03, 0.02), Color("#cc2222"))
				b.box(Vector3(0.0, _head_y(1.76), 0.165), Vector3(0.03, 0.09, 0.02), Color("#cc2222"))
			"headphones":
				# Наушники: вертикальная дужка через голову + амбушюры на ушах
				b.box(Vector3(0.0, _head_y(1.84), 0.0), Vector3(0.38, 0.035, 0.06), Color("#1c1c1e"))
				b.box(Vector3(-0.22, _head_y(1.73), 0.0), Vector3(0.04, 0.20, 0.05), Color("#1c1c1e"),
					Basis(Vector3.FORWARD, -0.12))
				b.box(Vector3(0.22, _head_y(1.73), 0.0), Vector3(0.04, 0.20, 0.05), Color("#1c1c1e"),
					Basis(Vector3.FORWARD, 0.12))
				for sx: float in [-1.0, 1.0]:
					b.cylinder(Vector3(sx * 0.25, _head_y(1.60), 0.0), 0.09, 0.09, 0.06,
						Color("#282c34"), 8, Basis(Vector3.FORWARD, PI * 0.5))
					b.cylinder(Vector3(sx * 0.26, _head_y(1.60), 0.0), 0.07, 0.07, 0.065,
						Color("#d4af37"), 6, Basis(Vector3.FORWARD, PI * 0.5))
			"panama":
				# Панама с широкими полями, синей лентой и сплошной закрытой тульей
				b.cylinder(Vector3(0.0, _head_y(1.65), 0.0), 0.44, 0.44, 0.025, Color("#dcd2b4"), 14)
				b.cylinder(Vector3(0.0, _head_y(1.70), 0.0), 0.28, 0.28, 0.055, Color("#2b5c8f"), 12)
				b.cylinder(Vector3(0.0, _head_y(1.76), 0.0), 0.27, 0.28, 0.12, Color("#dcd2b4"), 12)
				b.sphere(Vector3(0.0, _head_y(1.80), 0.0), 0.265, Color("#dcd2b4"), 5, 8, 0.35)
			"helmet":
				# Строительная каска
				b.cylinder(Vector3(0.0, _head_y(1.66), 0.0), 0.33, 0.33, 0.04, Color("#f4c418"), 12)
				b.sphere(Vector3(0.0, _head_y(1.70), 0.0), 0.31, Color("#f4c418"), 5, 8, 0.75)
				b.box(Vector3(0.0, _head_y(1.82), 0.0), Vector3(0.07, 0.06, 0.38), Color("#f4c418"))
			_:
				pass

	if not has_hat:
		# Объемная причёска (покрывает весь верх, виски и затылок)
		b.sphere(Vector3(0.0, _head_y(1.66), -0.03), 0.265, spec.hair_color, 5, 8, 0.95)
		b.box(Vector3(0.0, _head_y(1.73), 0.10), Vector3(0.25, 0.08, 0.14), spec.hair_color)
		b.box(Vector3(-0.22, _head_y(1.63), 0.02), Vector3(0.04, 0.14, 0.10), spec.hair_color)
		b.box(Vector3(0.22, _head_y(1.63), 0.02), Vector3(0.04, 0.14, 0.10), spec.hair_color)
	else:
		# Видимые волосы сзади и на висках под шапкой
		b.sphere(Vector3(0.0, _head_y(1.50), -0.05), 0.23, spec.hair_color, 4, 6, 0.55)
		b.box(Vector3(-0.21, _head_y(1.54), 0.01), Vector3(0.03, 0.09, 0.06), spec.hair_color)
		b.box(Vector3(0.21, _head_y(1.54), 0.01), Vector3(0.03, 0.09, 0.06), spec.hair_color)

	return b.commit()


# --- Рука и нога (переиспользуются на оба пивота) ------------------------------

static func _build_arm(spec: Spec) -> ArrayMesh:
	var b := MeshBuilder.new()
	# Плечо и рукав (сужение к локтю)
	b.tapered_box(Vector3(0.0, -0.16, 0.0), Vector3(0.16, 0.30, 0.16),
		spec.cloth_color, Vector2(0.88, 0.88))
	# Предплечье
	b.tapered_box(Vector3(0.0, -0.42, 0.0), Vector3(0.14, 0.26, 0.14),
		spec.cloth_color, Vector2(0.86, 0.86))
	# Манжета
	b.box(Vector3(0.0, -0.54, 0.0), Vector3(0.15, 0.04, 0.15),
		spec.cloth_color.lightened(0.15))
	# Кисть руки с пальцами
	b.box(Vector3(0.0, -0.62, 0.0), Vector3(0.11, 0.13, 0.11), spec.skin_color)
	b.box(Vector3(0.04, -0.60, 0.04), Vector3(0.04, 0.06, 0.04), spec.skin_color)
	return b.commit()


static func _build_leg(spec: Spec) -> ArrayMesh:
	var b := MeshBuilder.new()
	# Бедро (сужение к колену)
	b.tapered_box(Vector3(0.0, -0.20, 0.0), Vector3(0.19, 0.38, 0.21),
		spec.pants_color, Vector2(0.88, 0.88))
	# Голень (сужение к щиколотке)
	b.tapered_box(Vector3(0.0, -0.52, 0.0), Vector3(0.17, 0.34, 0.18),
		spec.pants_color, Vector2(0.86, 0.86))
	# Подворот / низ брюк
	b.box(Vector3(0.0, -0.68, 0.0), Vector3(0.18, 0.04, 0.19),
		spec.pants_color.darkened(0.2))

	# Обувь с подошвой, носком и каблуком
	var sole_col: Color = Color("#e8e8e4") if (spec.shoe_color.v < 0.25) else Color("#1a1a1c")
	b.box(Vector3(0.0, -0.74, 0.04), Vector3(0.19, 0.09, 0.31), spec.shoe_color)
	b.box(Vector3(0.0, -0.74, 0.15), Vector3(0.18, 0.08, 0.11), spec.shoe_color)
	b.box(Vector3(0.0, -0.79, 0.04), Vector3(0.20, 0.04, 0.33), sole_col)
	b.box(Vector3(0.0, -0.81, -0.06), Vector3(0.19, 0.03, 0.12), Color("#141414"))
	return b.commit()


# --- Собака -------------------------------------------------------------------

static func build_dog(coat_color: Color, collar_color: Color) -> AnimalRig:
	var rig := AnimalRig.new()

	var body := MeshBuilder.new()
	# Анатомичное тело: глубокая грудь, поджарый живот, бедра
	body.tapered_box(Vector3(0.0, 0.40, 0.12), Vector3(0.34, 0.36, 0.40),
		coat_color, Vector2(0.88, 1.0))
	body.tapered_box(Vector3(0.0, 0.38, -0.16), Vector3(0.30, 0.32, 0.34),
		coat_color, Vector2(1.05, 0.9))
	rig.body_mesh = body.commit()

	var head := MeshBuilder.new()
	# Череп
	head.box(Vector3(0.0, 0.10, 0.08), Vector3(0.24, 0.22, 0.26), coat_color)
	# Морда
	head.tapered_box(Vector3(0.0, 0.06, 0.26), Vector3(0.15, 0.13, 0.18),
		coat_color, Vector2(0.85, 0.9))
	head.box(Vector3(0.0, 0.10, 0.35), Vector3(0.06, 0.06, 0.05), _NOSE)
	# Висячие уши
	for sx: float in [-1.0, 1.0]:
		head.box(Vector3(sx * 0.15, 0.08, 0.04), Vector3(0.06, 0.18, 0.12), coat_color,
			Basis(Vector3.FORWARD, -sx * 0.2))
	# Ошейник с медальоном
	head.box(Vector3(0.0, 0.01, 0.02), Vector3(0.26, 0.06, 0.26), collar_color)
	head.cylinder(Vector3(0.0, -0.04, 0.14), 0.03, 0.03, 0.01, Color("#d4af37"), 6)
	rig.head_mesh = head.commit()

	var tail := MeshBuilder.new()
	tail.cylinder(Vector3(0.0, 0.16, -0.14), 0.03, 0.05, 0.36, coat_color, 6,
		Basis(Vector3.RIGHT, PI * 0.35))
	rig.tail_mesh = tail.commit()

	var leg := MeshBuilder.new()
	leg.tapered_box(Vector3(0.0, -0.10, 0.0), Vector3(0.11, 0.20, 0.12), coat_color, Vector2(0.85, 0.85))
	leg.box(Vector3(0.0, -0.25, 0.02), Vector3(0.09, 0.12, 0.13), coat_color)
	rig.leg_mesh = leg.commit()
	return rig


# --- Кошка ----------------------------------------------------------------------

static func build_cat(coat_color: Color, eye_color: Color) -> AnimalRig:
	var rig := AnimalRig.new()

	var body := MeshBuilder.new()
	# Грациозное тело кошки с изогнутой спиной
	body.tapered_box(Vector3(0.0, 0.27, 0.08), Vector3(0.22, 0.24, 0.28),
		coat_color, Vector2(0.9, 1.0))
	body.tapered_box(Vector3(0.0, 0.26, -0.12), Vector3(0.20, 0.22, 0.26),
		coat_color, Vector2(1.0, 0.9))
	rig.body_mesh = body.commit()

	var head := MeshBuilder.new()
	head.sphere(Vector3(0.0, 0.08, 0.04), 0.13, coat_color, 4, 7)
	# Глаза и ушки
	for sx: float in [-1.0, 1.0]:
		head.box(Vector3(sx * 0.065, 0.10, 0.14), Vector3(0.04, 0.04, 0.02), eye_color)
		head.cone(Vector3(sx * 0.075, 0.22, 0.04), 0.05, 0.11, coat_color, 3,
			Basis(Vector3.UP, PI * 0.25))
	# Мордочка и носик
	head.box(Vector3(0.0, 0.05, 0.15), Vector3(0.06, 0.04, 0.04), _WHITE)
	head.box(Vector3(0.0, 0.06, 0.17), Vector3(0.03, 0.025, 0.02), _PINK_NOSE)
	rig.head_mesh = head.commit()

	var tail := MeshBuilder.new()
	tail.cylinder(Vector3(0.0, 0.18, -0.10), 0.02, 0.03, 0.40, coat_color, 5,
		Basis(Vector3.RIGHT, PI * 0.28))
	rig.tail_mesh = tail.commit()

	var leg := MeshBuilder.new()
	leg.cylinder(Vector3(0.0, -0.11, 0.0), 0.035, 0.045, 0.22, coat_color, 6)
	leg.box(Vector3(0.0, -0.21, 0.02), Vector3(0.07, 0.04, 0.09), coat_color)
	rig.leg_mesh = leg.commit()
	return rig


static func build_ped_node(spec: Spec) -> Node3D:
	var root := Node3D.new()
	var rig := build_human(spec)
	var mat := preload("res://fx/materials/mat_palette.tres")

	var torso := MeshInstance3D.new()
	torso.mesh = rig.torso_mesh
	torso.material_override = mat
	root.add_child(torso)

	var head := MeshInstance3D.new()
	head.mesh = rig.head_mesh
	head.position = Vector3(0.0, HEAD_PIVOT_Y, 0.0)
	head.material_override = mat
	root.add_child(head)

	for sx: float in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		leg.mesh = rig.leg_mesh
		leg.position = Vector3(sx * HUMAN_LEG_PIVOT.x, HUMAN_LEG_PIVOT.y, HUMAN_LEG_PIVOT.z)
		leg.material_override = mat
		root.add_child(leg)

		var arm := MeshInstance3D.new()
		arm.mesh = rig.arm_mesh
		arm.position = Vector3(sx * HUMAN_ARM_PIVOT.x, HUMAN_ARM_PIVOT.y, HUMAN_ARM_PIVOT.z)
		arm.material_override = mat
		root.add_child(arm)

	return root

