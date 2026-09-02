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


# --- Торс + аксессуары торса -------------------------------------------------

static func _build_torso(spec: Spec) -> ArrayMesh:
	var b := MeshBuilder.new()
	b.box(Vector3(0.0, 1.05, 0.0), Vector3(0.56, 0.68, 0.34), spec.cloth_color)
	# Полоска куртки — в оригинале 60% шанс, здесь всегда (Spec детерминирован).
	b.box(Vector3(0.0, 1.05, 0.175), Vector3(0.06, 0.66, 0.02), _WHITE)

	for tag in spec.accessories:
		match String(tag):
			"cane":
				b.cylinder(Vector3(0.4, 0.75, 0.1), 0.03, 0.03, 1.1, Color("#5a3a1a"), 6)
			"shoulder_bag":
				b.box(Vector3(0.0, 1.05, 0.175), Vector3(0.04, 0.58, 0.02), Color("#111111"),
					Basis(Vector3.BACK, 0.6))
				b.box(Vector3(0.0, 1.05, -0.175), Vector3(0.04, 0.58, 0.02), Color("#111111"),
					Basis(Vector3.BACK, -0.6))
				b.box(Vector3(0.06, 1.1, 0.19), Vector3(0.18, 0.12, 0.06), Color("#111111"))
			"stripes":
				b.box(Vector3(0.285, 1.05, 0.0), Vector3(0.02, 0.66, 0.35), _WHITE)
				b.box(Vector3(-0.285, 1.05, 0.0), Vector3(0.02, 0.66, 0.35), _WHITE)
			"string_bag":
				b.box(Vector3(0.36, 0.88, 0.1), Vector3(0.22, 0.28, 0.14), Color("#d0c8a0"))
			"stroller":
				b.box(Vector3(0.0, 0.7, 0.5), Vector3(0.5, 0.4, 0.7), Color("#3a5a8a"))
				var wheel_basis := Basis(Vector3.RIGHT, PI * 0.5)
				b.cylinder(Vector3(0.0, 0.35, 0.5), 0.12, 0.12, 0.1, Color("#222222"), 8, wheel_basis)
				b.cylinder(Vector3(0.0, 0.35, 0.9), 0.12, 0.12, 0.1, Color("#222222"), 8, wheel_basis)
			"instrument":
				b.box(Vector3(0.0, 1.1, 0.25), Vector3(0.4, 0.3, 0.2), Color("#8a3a3a"))
				b.box(Vector3(0.0, 1.1, 0.18), Vector3(0.42, 0.2, 0.1), _WHITE)
			"stethoscope":
				# Оригинал — Torus вокруг шеи; MeshBuilder тора не строит,
				# берём плоское кольцо-цилиндр той же общей формы.
				b.cylinder(Vector3(0.0, 1.35, 0.15), 0.1, 0.1, 0.03, Color("#222222"), 10,
					Basis(Vector3.RIGHT, PI * 0.5))
			"backpack":
				var bag := Color("#205080")
				b.box(Vector3(0.0, 1.1, -0.24), Vector3(0.38, 0.45, 0.2), bag)
				b.box(Vector3(0.0, 1.0, -0.35), Vector3(0.26, 0.2, 0.08), bag)
				b.box(Vector3(0.0, 1.11, -0.35), Vector3(0.22, 0.02, 0.09), Color("#cccccc"))
			"camera":
				b.box(Vector3(0.0, 1.15, 0.22), Vector3(0.18, 0.14, 0.12), Color("#222222"))
				b.cylinder(Vector3(0.03, 1.15, 0.29), 0.05, 0.05, 0.05, Color("#444444"), 8,
					Basis(Vector3.RIGHT, PI * 0.5))
			"hi_vis":
				var hv := Color("#d4e157")
				b.box(Vector3(0.0, 1.18, 0.175), Vector3(0.54, 0.04, 0.02), hv)
				b.box(Vector3(0.0, 0.92, 0.175), Vector3(0.54, 0.04, 0.02), hv)
				b.box(Vector3(0.0, 1.18, -0.175), Vector3(0.54, 0.04, 0.02), hv)
			"wrench":
				b.box(Vector3(0.42, 0.9, 0.1), Vector3(0.05, 0.5, 0.05), Color("#888888"))
			"briefcase":
				b.box(Vector3(0.38, 0.85, 0.05), Vector3(0.1, 0.28, 0.36), Color("#1a1410"))
				b.box(Vector3(0.0, 1.12, 0.175), Vector3(0.06, 0.35, 0.02), Color("#204080"))
			# "beard", капа/шапка-теги обрабатываются в _build_head — здесь их пропускаем.
			_:
				pass
	return b.commit()


# --- Голова + аксессуары головы -----------------------------------------------

static func _head_y(abs_y: float) -> float:
	return abs_y - HEAD_PIVOT_Y


static func _build_head(spec: Spec) -> ArrayMesh:
	var b := MeshBuilder.new()
	b.sphere(Vector3(0.0, _head_y(1.62), 0.0), 0.26, spec.skin_color, 5, 8)
	b.box(Vector3(0.0, _head_y(1.62), 0.26), Vector3(0.04, 0.04, 0.04), spec.skin_color)

	var covers_head := false
	for tag in spec.accessories:
		match String(tag):
			"beard":
				b.sphere(Vector3(0.0, _head_y(1.5), 0.1), 0.2, Color("#d8d8d8"), 4, 6, 0.6)
			"cap":
				b.cylinder(Vector3(0.0, _head_y(1.84), 0.02), 0.28, 0.28, 0.1, Color("#1a1a1c"), 8)
				b.box(Vector3(0.0, _head_y(1.79), 0.24), Vector3(0.24, 0.02, 0.16), Color("#1a1a1c"))
				covers_head = true
			"headscarf":
				b.sphere(Vector3(0.0, _head_y(1.63), 0.0), 0.28, Color("#d8a8a8"), 5, 8, 0.75)
				covers_head = true
			"beret":
				b.sphere(Vector3(0.0, _head_y(1.66), 0.0), 0.28, Color("#2a2a2a"), 4, 8, 0.55)
				b.cylinder(Vector3(0.0, _head_y(1.78), 0.0), 0.3, 0.3, 0.06, Color("#8a3a3a"), 8)
				covers_head = true
			"nurse_cap":
				b.sphere(Vector3(0.0, _head_y(1.66), 0.0), 0.28, Color("#ffffff"), 4, 8, 0.55)
				b.box(Vector3(0.0, _head_y(1.78), 0.0), Vector3(0.3, 0.05, 0.3), Color("#ffffff"))
				b.box(Vector3(0.0, _head_y(1.78), 0.1), Vector3(0.12, 0.04, 0.04), Color("#cc2222"))
				b.box(Vector3(0.0, _head_y(1.78), 0.1), Vector3(0.04, 0.04, 0.12), Color("#cc2222"))
				covers_head = true
			"headphones":
				# Оригинал — Torus-повязка через макушку; заменена на два
				# наушника по бокам головы (тот же силуэт, без примитива тора).
				b.sphere(Vector3(0.0, _head_y(1.63), 0.0), 0.27, spec.hair_color, 4, 8, 0.55)
				for sx: float in [-1.0, 1.0]:
					b.cylinder(Vector3(sx * 0.26, _head_y(1.63), 0.0), 0.07, 0.07, 0.05,
						Color("#222222"), 8, Basis(Vector3.FORWARD, PI * 0.5))
				covers_head = true
			"panama":
				b.cylinder(Vector3(0.0, _head_y(1.74), 0.0), 0.42, 0.42, 0.02, Color("#ddccaa"), 10)
				b.cylinder(Vector3(0.0, _head_y(1.83), 0.0), 0.27, 0.26, 0.16, Color("#ddccaa"), 10)
				covers_head = true
			"helmet":
				b.sphere(Vector3(0.0, _head_y(1.66), 0.0), 0.28, Color("#e8c020"), 4, 8, 0.5)
				b.cylinder(Vector3(0.0, _head_y(1.78), 0.0), 0.3, 0.3, 0.05, Color("#e8c020"), 8)
				covers_head = true
			_:
				pass

	if not covers_head:
		b.sphere(Vector3(0.0, _head_y(1.63), 0.0), 0.27, spec.hair_color, 4, 8, 0.55)
	return b.commit()


# --- Рука/нога (переиспользуются на оба пивота) --------------------------------

static func _build_arm(spec: Spec) -> ArrayMesh:
	var b := MeshBuilder.new()
	b.box(Vector3(0.0, -0.31, 0.0), Vector3(0.15, 0.62, 0.15), spec.cloth_color)
	return b.commit()


static func _build_leg(spec: Spec) -> ArrayMesh:
	var b := MeshBuilder.new()
	b.box(Vector3(0.0, -0.375, 0.0), Vector3(0.18, 0.75, 0.2), spec.pants_color)
	b.box(Vector3(0.0, -0.77, 0.04), Vector3(0.2, 0.12, 0.32), spec.shoe_color)
	return b.commit()


# --- Собака -------------------------------------------------------------------

static func build_dog(coat_color: Color, collar_color: Color) -> AnimalRig:
	var rig := AnimalRig.new()

	var body := MeshBuilder.new()
	body.box(Vector3(0.0, 0.38, 0.0), Vector3(0.32, 0.35, 0.65), coat_color)
	rig.body_mesh = body.commit()

	var head := MeshBuilder.new()
	head.box(Vector3(0.0, 0.08, 0.08), Vector3(0.24, 0.24, 0.3), coat_color)
	head.box(Vector3(0.0, 0.04, 0.26), Vector3(0.14, 0.12, 0.16), coat_color)
	head.box(Vector3(0.0, 0.08, 0.33), Vector3(0.06, 0.06, 0.06), _NOSE)
	# Висячие уши (в оригинале 50/50 с торчащими — здесь всегда висячие).
	for sx: float in [-1.0, 1.0]:
		head.box(Vector3(sx * 0.14, 0.12, 0.04), Vector3(0.08, 0.16, 0.1), coat_color)
	head.box(Vector3(0.0, 0.0, 0.02), Vector3(0.26, 0.06, 0.26), collar_color)
	rig.head_mesh = head.commit()

	var tail := MeshBuilder.new()
	tail.cylinder(Vector3(0.0, 0.15, -0.15), 0.03, 0.05, 0.35, coat_color, 6,
		Basis(Vector3.RIGHT, PI / 3.0))
	rig.tail_mesh = tail.commit()

	var leg := MeshBuilder.new()
	leg.box(Vector3(0.0, -0.16, 0.0), Vector3(0.1, 0.32, 0.1), coat_color)
	rig.leg_mesh = leg.commit()
	return rig


# --- Кошка ----------------------------------------------------------------------

static func build_cat(coat_color: Color, eye_color: Color) -> AnimalRig:
	var rig := AnimalRig.new()

	var body := MeshBuilder.new()
	body.box(Vector3(0.0, 0.26, 0.0), Vector3(0.22, 0.24, 0.45), coat_color)
	rig.body_mesh = body.commit()

	var head := MeshBuilder.new()
	head.box(Vector3(0.0, 0.06, 0.04), Vector3(0.2, 0.18, 0.2), coat_color)
	for sx: float in [-1.0, 1.0]:
		head.box(Vector3(sx * 0.06, 0.08, 0.15), Vector3(0.04, 0.04, 0.02), eye_color)
		head.cone(Vector3(sx * 0.07, 0.19, 0.04), 0.05, 0.1, coat_color, 4,
			Basis(Vector3.UP, PI * 0.25))
	head.box(Vector3(0.0, 0.05, 0.15), Vector3(0.04, 0.03, 0.02), _PINK_NOSE)
	rig.head_mesh = head.commit()

	var tail := MeshBuilder.new()
	tail.cylinder(Vector3(0.0, 0.18, -0.1), 0.02, 0.03, 0.38, coat_color, 5,
		Basis(Vector3.RIGHT, PI / 4.0))
	rig.tail_mesh = tail.commit()

	var leg := MeshBuilder.new()
	leg.box(Vector3(0.0, -0.11, 0.0), Vector3(0.07, 0.22, 0.07), coat_color)
	rig.leg_mesh = leg.commit()
	return rig
