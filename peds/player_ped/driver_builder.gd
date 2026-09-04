class_name DriverBuilder
extends RefCounted
## Процедурный мешер аватара водителя игрока. Порт buildDriverMesh (utils.js:799-965).
##
## В отличие от обычных пешеходов (PedMeshBuilder), у водителя больше деталей:
## - бейджик таксиста и шашечки на груди;
## - рация на поясе;
## - кепка таксиста с козырьком и шашечками;
## - тёмные очки и усы;
## - опциональный живот (belly) со смещением ремня и ширины расстановки конечностей.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

const HEAD_PIVOT_Y := 1.42
const LEG_PIVOT_Y := 1.05
const ARM_PIVOT_Y := 1.32

const COLOR_BELT := Color("#1a1a1a")
const COLOR_BUCKLE := Color("#d4af37")
const COLOR_ZIPPER := Color("#cccccc")
const COLOR_CHECKER_TAXI := Color("#f5b020")
const COLOR_DARK := Color("#111111")
const COLOR_BADGE_WHITE := Color("#ffffff")
const COLOR_BADGE_PHOTO := Color("#224477")
const COLOR_BADGE_TEXT := Color("#333333")
const COLOR_RADIO_BODY := Color("#222222")
const COLOR_SUNGLASSES := Color("#15181c")
const COLOR_CAP_CROWN := Color("#1f2328")
const COLOR_SHOE := Color("#1f1f23")


class DriverSpec extends RefCounted:
	var belly: bool = false
	var cap: bool = true
	var shirt_color: Color = Color(0.16, 0.28, 0.50)
	var pants_color: Color = Color(0.16, 0.16, 0.23)
	var skin_color: Color = Color(0.96, 0.82, 0.69)
	var hair_color: Color = Color(0.10, 0.10, 0.10)

	static func from_dictionary(d: Dictionary) -> DriverSpec:
		var s := DriverSpec.new()
		s.belly = bool(d.get(&"belly", false))
		s.cap = bool(d.get(&"cap", true))
		if d.has(&"shirt_color"):
			s.shirt_color = d[&"shirt_color"]
		if d.has(&"pants_color"):
			s.pants_color = d[&"pants_color"]
		if d.has(&"skin_color"):
			s.skin_color = d[&"skin_color"]
		if d.has(&"hair_color"):
			s.hair_color = d[&"hair_color"]
		return s


class DriverRig extends RefCounted:
	var root: Node3D
	var body_pivot: Node3D
	var torso_instance: MeshInstance3D
	var head_pivot: Node3D
	var head_instance: MeshInstance3D
	var left_arm: Node3D
	var right_arm: Node3D
	var left_leg: Node3D
	var right_leg: Node3D
	var arm_spread: float = 0.39
	var leg_spread: float = 0.13


static func build(spec: DriverSpec) -> DriverRig:
	var rig := DriverRig.new()
	rig.arm_spread = 0.42 if spec.belly else 0.39
	rig.leg_spread = 0.15 if spec.belly else 0.13

	var torso_mesh := _build_torso(spec)
	var head_mesh := _build_head(spec)
	var arm_mesh := _build_arm(spec)
	var leg_mesh := _build_leg(spec)

	var root := Node3D.new()
	root.name = "DriverAvatar"

	# body_pivot наклоняется при нокауте/падении (PI/2 * 0.8)
	var body_pivot := Node3D.new()
	body_pivot.name = "BodyPivot"
	root.add_child(body_pivot)

	var torso_inst := MeshInstance3D.new()
	torso_inst.name = "Torso"
	torso_inst.mesh = torso_mesh
	torso_inst.material_override = PALETTE_MAT
	body_pivot.add_child(torso_inst)

	var head_pivot := Node3D.new()
	head_pivot.name = "HeadPivot"
	head_pivot.position = Vector3(0.0, HEAD_PIVOT_Y, 0.0)
	body_pivot.add_child(head_pivot)

	var head_inst := MeshInstance3D.new()
	head_inst.name = "Head"
	head_inst.mesh = head_mesh
	head_inst.material_override = PALETTE_MAT
	head_pivot.add_child(head_inst)

	var left_arm := Node3D.new()
	left_arm.name = "LeftArm"
	left_arm.position = Vector3(-rig.arm_spread, ARM_PIVOT_Y, 0.0)
	body_pivot.add_child(left_arm)
	var la_inst := MeshInstance3D.new()
	la_inst.mesh = arm_mesh
	la_inst.material_override = PALETTE_MAT
	left_arm.add_child(la_inst)

	var right_arm := Node3D.new()
	right_arm.name = "RightArm"
	right_arm.position = Vector3(rig.arm_spread, ARM_PIVOT_Y, 0.0)
	body_pivot.add_child(right_arm)
	var ra_inst := MeshInstance3D.new()
	ra_inst.mesh = arm_mesh
	ra_inst.material_override = PALETTE_MAT
	right_arm.add_child(ra_inst)

	var left_leg := Node3D.new()
	left_leg.name = "LeftLeg"
	left_leg.position = Vector3(-rig.leg_spread, LEG_PIVOT_Y, 0.0)
	root.add_child(left_leg)
	var ll_inst := MeshInstance3D.new()
	ll_inst.mesh = leg_mesh
	ll_inst.material_override = PALETTE_MAT
	left_leg.add_child(ll_inst)

	var right_leg := Node3D.new()
	right_leg.name = "RightLeg"
	right_leg.position = Vector3(rig.leg_spread, LEG_PIVOT_Y, 0.0)
	root.add_child(right_leg)
	var rl_inst := MeshInstance3D.new()
	rl_inst.mesh = leg_mesh
	rl_inst.material_override = PALETTE_MAT
	right_leg.add_child(rl_inst)

	rig.root = root
	rig.body_pivot = body_pivot
	rig.torso_instance = torso_inst
	rig.head_pivot = head_pivot
	rig.head_instance = head_inst
	rig.left_arm = left_arm
	rig.right_arm = right_arm
	rig.left_leg = left_leg
	rig.right_leg = right_leg

	return rig


# --- Торс и экипировка --------------------------------------------------------

static func _build_torso(spec: DriverSpec) -> ArrayMesh:
	var b := MeshBuilder.new()
	var fz := 0.28 if spec.belly else 0.175

	if spec.belly:
		# Фирменная фигура опытного таксиста с животом
		b.tapered_box(Vector3(0.0, 1.18, 0.0), Vector3(0.58, 0.42, 0.36),
			spec.shirt_color, Vector2(0.92, 0.95))
		b.tapered_box(Vector3(0.0, 0.92, 0.06), Vector3(0.56, 0.36, 0.36),
			spec.shirt_color, Vector2(1.08, 1.08))
		b.box(Vector3(0.0, 0.92, 0.23), Vector3(0.46, 0.30, 0.12), spec.shirt_color)
		# Ремень под животом
		b.box(Vector3(0.0, 0.72, 0.02), Vector3(0.56, 0.08, 0.40), COLOR_BELT)
		b.box(Vector3(0.0, 0.72, 0.23), Vector3(0.11, 0.08, 0.03), COLOR_BUCKLE)
	else:
		# Подтянутый спортивный торс
		b.tapered_box(Vector3(0.0, 1.18, 0.0), Vector3(0.54, 0.42, 0.32),
			spec.shirt_color, Vector2(0.92, 0.94))
		b.tapered_box(Vector3(0.0, 0.90, 0.0), Vector3(0.48, 0.28, 0.29),
			spec.shirt_color, Vector2(1.06, 1.06))
		b.box(Vector3(0.0, 0.73, 0.0), Vector3(0.50, 0.08, 0.30), COLOR_BELT)
		b.box(Vector3(0.0, 0.73, 0.16), Vector3(0.10, 0.08, 0.03), COLOR_BUCKLE)

	# Воротник-стойка куртки
	var collar_z := 0.15 if spec.belly else 0.11
	b.box(Vector3(0.0, 1.38, collar_z), Vector3(0.32, 0.08, 0.10), spec.shirt_color.lightened(0.12))
	# Вырез и светлая футболка под курткой
	b.box(Vector3(0.0, 1.30, fz - 0.02), Vector3(0.12, 0.16, 0.04), Color("#e8e8ea"))

	# Молния куртки и бегунок
	b.box(Vector3(0.0, 1.05, fz), Vector3(0.04, 0.60, 0.02), COLOR_ZIPPER)
	b.box(Vector3(0.0, 1.28, fz + 0.01), Vector3(0.06, 0.05, 0.03), COLOR_BUCKLE)

	# Шашечки такси на правой стороне груди (светящаяся золотистая лента)
	var cx := 0.14
	var cy := 1.15
	var cz := fz
	b.box(Vector3(cx, cy, cz), Vector3(0.20, 0.05, 0.01), COLOR_DARK)
	var check_offsets: Array[float] = [-0.06, -0.02, 0.02, 0.06]
	for i in check_offsets.size():
		var off_c: Color = COLOR_CHECKER_TAXI if (i % 2 == 0) else COLOR_DARK
		b.box(Vector3(cx + check_offsets[i], cy, cz + 0.005),
			Vector3(0.038, 0.045, 0.015), off_c)

	# Бейджик таксиста на левой стороне груди (фотография + номер лицензии)
	var bx := -0.14
	var by := 1.15
	var bz := fz
	b.box(Vector3(bx, by, bz), Vector3(0.09, 0.11, 0.015), COLOR_CHECKER_TAXI)
	b.box(Vector3(bx, by, bz + 0.004), Vector3(0.07, 0.08, 0.02), COLOR_BADGE_WHITE)
	b.box(Vector3(bx - 0.015, by + 0.012, bz + 0.007), Vector3(0.028, 0.035, 0.025), COLOR_BADGE_PHOTO)
	b.box(Vector3(bx, by - 0.018, bz + 0.007), Vector3(0.045, 0.015, 0.025), COLOR_BADGE_TEXT)

	# Рация таксиста на поясе (Motorola с регуляторами и антенной)
	var radio_x := -0.32 if spec.belly else -0.28
	b.box(Vector3(radio_x, 0.85, 0.0), Vector3(0.09, 0.15, 0.07), COLOR_RADIO_BODY)
	b.box(Vector3(radio_x, 0.94, 0.02), Vector3(0.05, 0.04, 0.04), Color("#444444")) # ручка громкости
	b.cylinder(Vector3(radio_x - 0.02, 0.99, 0.0), 0.012, 0.014, 0.14, COLOR_DARK, 6) # антенна
	# Динамик рации
	b.box(Vector3(radio_x, 0.85, 0.036), Vector3(0.06, 0.07, 0.01), Color("#111111"))

	return b.commit()


# --- Голова, кепка и лицо -----------------------------------------------------

static func _build_head(spec: DriverSpec) -> ArrayMesh:
	var b := MeshBuilder.new()
	var py := HEAD_PIVOT_Y

	# Шея
	b.cylinder(Vector3(0.0, 1.41 - py, 0.0), 0.11, 0.13, 0.14, spec.skin_color, 8)

	# Череп и челюсть
	if spec.cap:
		b.sphere(Vector3(0.0, 1.58 - py, 0.0), 0.23, spec.skin_color, 5, 8, 0.85)
	else:
		b.sphere(Vector3(0.0, 1.62 - py, 0.0), 0.25, spec.skin_color, 5, 8, 1.05)
	b.box(Vector3(0.0, 1.50 - py, 0.12), Vector3(0.18, 0.09, 0.14), spec.skin_color)

	# Нос
	b.tapered_box(Vector3(0.0, 1.60 - py, 0.24), Vector3(0.06, 0.10, 0.08),
		spec.skin_color, Vector2(0.8, 1.0), 0.0, -0.02, 0.0)

	# Уши
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.23, 1.59 - py, 0.0), Vector3(0.035, 0.09, 0.06), spec.skin_color)

	# Солнцезащитные очки-авиаторы (золотая оправа, каплевидные линзы)
	b.box(Vector3(0.0, 1.65 - py, 0.25), Vector3(0.38, 0.015, 0.04), COLOR_BUCKLE) # мостик
	b.box(Vector3(0.0, 1.68 - py, 0.25), Vector3(0.24, 0.015, 0.04), COLOR_BUCKLE) # верхняя дужка
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.10, 1.62 - py, 0.255), Vector3(0.14, 0.09, 0.03), COLOR_SUNGLASSES)
		b.box(Vector3(sx * 0.21, 1.63 - py, 0.12), Vector3(0.02, 0.015, 0.24), COLOR_BUCKLE) # дужка к уху

	# Кавказские таксистские усы
	b.box(Vector3(0.0, 1.53 - py, 0.255), Vector3(0.18, 0.045, 0.04), spec.hair_color)
	b.box(Vector3(-0.09, 1.51 - py, 0.25), Vector3(0.04, 0.05, 0.03), spec.hair_color)
	b.box(Vector3(0.09, 1.51 - py, 0.25), Vector3(0.04, 0.05, 0.03), spec.hair_color)

	# Волосы на затылке и висках
	if spec.cap:
		b.sphere(Vector3(0.0, 1.54 - py, -0.06), 0.24, spec.hair_color, 4, 6, 0.6)
		b.box(Vector3(-0.22, 1.56 - py, 0.02), Vector3(0.03, 0.10, 0.06), spec.hair_color)
		b.box(Vector3(0.22, 1.56 - py, 0.02), Vector3(0.03, 0.10, 0.06), spec.hair_color)
	else:
		b.sphere(Vector3(0.0, 1.66 - py, -0.04), 0.27, spec.hair_color, 5, 8, 1.0)
		b.box(Vector3(-0.23, 1.64 - py, 0.04), Vector3(0.04, 0.14, 0.08), spec.hair_color)
		b.box(Vector3(0.23, 1.64 - py, 0.04), Vector3(0.04, 0.14, 0.08), spec.hair_color)

	# Кепка таксиста (капитанка с лаковым козырьком и шашечками)
	if spec.cap:
		# Околыш
		b.cylinder(Vector3(0.0, 1.68 - py, 0.01), 0.28, 0.28, 0.06, COLOR_DARK, 12)
		# Лента с шашечками на околыше
		var cap_checkers: Array[float] = [-0.10, -0.05, 0.0, 0.05, 0.10]
		for i in cap_checkers.size():
			var col: Color = COLOR_CHECKER_TAXI if (i % 2 == 0) else COLOR_DARK
			b.box(Vector3(cap_checkers[i], 1.68 - py, 0.24),
				Vector3(0.045, 0.04, 0.02), col)

		# Золотая кокарда по центру
		b.cylinder(Vector3(0.0, 1.72 - py, 0.245), 0.04, 0.04, 0.02, COLOR_BUCKLE, 6,
			Basis(Vector3.RIGHT, PI * 0.5))

		# Верхняя тулья
		b.sphere(Vector3(0.0, 1.73 - py, 0.01), 0.31, COLOR_CAP_CROWN, 5, 8, 0.72)
		b.cylinder(Vector3(0.0, 1.78 - py, 0.01), 0.30, 0.28, 0.08, COLOR_CAP_CROWN, 10)
		# Пуговица на макушке
		b.sphere(Vector3(0.0, 1.90 - py, 0.01), 0.035, COLOR_BUCKLE, 3, 6)

		# Изогнутый лаковый козырек
		b.box(Vector3(0.0, 1.67 - py, 0.25), Vector3(0.28, 0.025, 0.18), COLOR_DARK,
			Basis(Vector3.RIGHT, -0.18))

	return b.commit()


# --- Рука и нога -------------------------------------------------------------

static func _build_arm(spec: DriverSpec) -> ArrayMesh:
	var b := MeshBuilder.new()
	# Плечо и предплечье с анатомичным сужением
	b.tapered_box(Vector3(0.0, -0.16, 0.0), Vector3(0.17, 0.30, 0.17),
		spec.shirt_color, Vector2(0.88, 0.88))
	b.tapered_box(Vector3(0.0, -0.42, 0.0), Vector3(0.15, 0.26, 0.15),
		spec.shirt_color, Vector2(0.86, 0.86))
	# Трикотажная манжета рукава
	b.box(Vector3(0.0, -0.54, 0.0), Vector3(0.16, 0.04, 0.16),
		spec.shirt_color.lightened(0.15))

	# Часы на запястье
	b.cylinder(Vector3(0.0, -0.54, 0.0), 0.09, 0.09, 0.03, COLOR_DARK, 8)
	b.box(Vector3(0.0, -0.54, 0.08), Vector3(0.05, 0.03, 0.02), COLOR_BUCKLE)

	# Кожаная водительская перчатка
	b.box(Vector3(0.0, -0.62, 0.0), Vector3(0.12, 0.13, 0.12), Color("#241c16"))
	b.box(Vector3(0.04, -0.60, 0.04), Vector3(0.04, 0.06, 0.04), Color("#241c16"))
	return b.commit()


static func _build_leg(spec: DriverSpec) -> ArrayMesh:
	var b := MeshBuilder.new()
	# Бедро джинсов/брюк
	b.tapered_box(Vector3(0.0, -0.20, 0.0), Vector3(0.20, 0.38, 0.22),
		spec.pants_color, Vector2(0.88, 0.88))
	# Голень
	b.tapered_box(Vector3(0.0, -0.52, 0.0), Vector3(0.18, 0.36, 0.19),
		spec.pants_color, Vector2(0.86, 0.86))
	# Подворот брюк
	b.box(Vector3(0.0, -0.69, 0.0), Vector3(0.19, 0.04, 0.20),
		spec.pants_color.darkened(0.2))

	# Спортивные кроссовки / мокасины с белой подошвой
	b.box(Vector3(0.0, -0.74, 0.04), Vector3(0.20, 0.09, 0.32), COLOR_SHOE)
	b.box(Vector3(0.0, -0.74, 0.16), Vector3(0.19, 0.08, 0.12), COLOR_SHOE)
	# Белая каучуковая подошва
	b.box(Vector3(0.0, -0.79, 0.04), Vector3(0.21, 0.04, 0.34), Color("#e8e8ea"))
	b.box(Vector3(0.0, -0.81, -0.06), Vector3(0.20, 0.03, 0.12), Color("#111111"))
	# Шнуровка
	b.box(Vector3(0.0, -0.70, 0.08), Vector3(0.08, 0.02, 0.12), Color("#e8e8ea"))

	return b.commit()


# --- Анимация ----------------------------------------------------------------

## Применяет позу персонажа к пивотам рига.
static func animate_rig(rig: DriverRig, walk_phase: float, speed: float,
		is_running: bool, punch_anim_t: float, stun_t: float,
		is_knocked_out: bool) -> void:
	if rig == null or rig.root == null:
		return

	if is_knocked_out:
		rig.body_pivot.rotation = Vector3(PI * 0.4, 0.0, 0.0)
		rig.left_leg.rotation.x = 0.2
		rig.right_leg.rotation.x = -0.2
		rig.left_arm.rotation.x = 0.8
		rig.right_arm.rotation.x = 0.8
		return

	rig.body_pivot.rotation = Vector3.ZERO

	if stun_t > 0.0:
		rig.left_leg.rotation.x = 0.0
		rig.right_leg.rotation.x = 0.0
		rig.left_arm.rotation.x = -0.9
		rig.right_arm.rotation.x = -0.9
		return

	if speed > 0.05:
		var amp := 0.82 if is_running else 0.55
		var sw := sin(walk_phase)
		rig.left_leg.rotation.x = sw * amp
		rig.right_leg.rotation.x = -sw * amp
		rig.left_arm.rotation.x = -sw * amp * 0.72
		rig.right_arm.rotation.x = sw * amp * 0.72
	else:
		rig.left_leg.rotation.x = 0.0
		rig.right_leg.rotation.x = 0.0
		rig.left_arm.rotation.x = 0.0
		rig.right_arm.rotation.x = 0.0

	if punch_anim_t > 0.0:
		var k := clampf(1.0 - punch_anim_t / 0.3, 0.0, 1.0)
		var arm_angle := -sin(k * PI) * 1.2
		rig.right_arm.rotation.x = arm_angle
		rig.left_arm.rotation.x = -0.5
