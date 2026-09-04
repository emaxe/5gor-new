class_name PropMeshes
extends RefCounted
## Библиотека мешей повторяющегося пропса.
##
## Каждый меш строится один раз и раздаётся в MultiMesh: деревьев, фонарей и
## урн в городе сотни, но draw call у каждого типа один. Цвет вариации идёт
## per-instance, поэтому меши белые (COLOR = 1) и красятся инстансом.

const TRUNK := Color("#583e2e")
const LAMP_POLE := Color("#2c3036")
const LAMP_HEAD := Color("#fff4c0")
const BIN_BODY := Color("#4a5058")
const BENCH_WOOD := Color("#9e6b38")
const BENCH_LEG := Color("#282b30")
const PLANTER := Color("#c4bcac")
const SIGNAL_POLE := Color("#383c42")
const SIGNAL_BOX := Color("#16171a")
const MARKING := Color("#e8e8dc")
const ZEBRA := Color("#ffffff")
const GLASS := Color("#283b4c")
const TYRE := Color("#1a1c20")
const RIM := Color("#c0c4cc")
const CHROME := Color("#d0d4dc")
const LAMP_FRONT := Color("#fff9e6")
const LAMP_REAR := Color("#aa1c1c")
const PLATE := Color("#f0f0f0")


## Лиственное дерево: органический ствол с корневым утолщением и ветвями +
## многоярусная рельефная крона из нескольких взаимопроникающих гранёных объёмов.
## Крона белая — цвет задаёт MultiMesh-инстанс.
static func deciduous_tree() -> ArrayMesh:
	var b := MeshBuilder.new()
	# Ствол с утолщением у земли и развилкой
	b.cylinder(Vector3(0.0, 0.45, 0.0), 0.38, 0.65, 0.9, TRUNK, 6)
	b.cylinder(Vector3(0.0, 1.45, 0.0), 0.28, 0.38, 1.3, TRUNK, 6)
	b.cylinder(Vector3(0.28, 2.25, 0.18), 0.16, 0.28, 1.1, TRUNK, 5,
		Basis(Vector3.RIGHT, 0.32) * Basis(Vector3.UP, 0.45))
	b.cylinder(Vector3(-0.32, 2.2, -0.15), 0.15, 0.26, 1.0, TRUNK, 5,
		Basis(Vector3.RIGHT, -0.28) * Basis(Vector3.UP, -0.6))

	# Многослойная рельефная крона
	b.sphere(Vector3(0.0, 3.4, 0.0), 1.65, Color.WHITE, 4, 7, 1.05)
	b.sphere(Vector3(0.0, 4.3, 0.0), 1.25, Color.WHITE, 3, 6, 0.95)
	b.sphere(Vector3(0.85, 3.1, 0.4), 1.25, Color.WHITE, 4, 6, 0.95)
	b.sphere(Vector3(-0.8, 3.0, -0.45), 1.2, Color.WHITE, 4, 6, 0.95)
	b.sphere(Vector3(-0.35, 2.9, 0.8), 1.15, Color.WHITE, 3, 6, 0.9)
	return b.commit()


## Хвойное дерево: высокий ствол и 4 каскадных яруса хвои с расширяющимися
## юбками конусов (как в курортных парках Пятигорска).
static func pine_tree() -> ArrayMesh:
	var b := MeshBuilder.new()
	# Ствол
	b.cylinder(Vector3(0.0, 1.2, 0.0), 0.24, 0.48, 2.4, TRUNK, 6)
	b.cylinder(Vector3(0.0, 3.3, 0.0), 0.12, 0.24, 2.0, TRUNK, 5)

	# 4 каскадных яруса кроны
	b.cone(Vector3(0.0, 2.4, 0.0), 2.3, 1.8, Color.WHITE, 7)
	b.cone(Vector3(0.0, 3.6, 0.0), 1.85, 1.6, Color.WHITE, 7)
	b.cone(Vector3(0.0, 4.8, 0.0), 1.35, 1.5, Color.WHITE, 6)
	b.cone(Vector3(0.0, 5.9, 0.0), 0.85, 1.6, Color.WHITE, 6)
	return b.commit()


## Кустарник: пышное скопление листвы с цветочными акцентами.
static func bush() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.sphere(Vector3(0.0, 0.55, 0.0), 0.85, Color.WHITE, 3, 6, 0.75)
	b.sphere(Vector3(0.42, 0.45, 0.2), 0.65, Color.WHITE, 3, 6, 0.7)
	b.sphere(Vector3(-0.38, 0.42, -0.25), 0.62, Color.WHITE, 3, 6, 0.7)
	b.sphere(Vector3(-0.2, 0.4, 0.4), 0.58, Color.WHITE, 3, 6, 0.7)
	# Цветочные вкрапления
	b.sphere(Vector3(0.2, 0.7, 0.35), 0.09, Color("#f4e04d"), 3, 5)
	b.sphere(Vector3(-0.25, 0.65, 0.3), 0.09, Color("#e84a5f"), 3, 5)
	b.sphere(Vector3(0.35, 0.6, -0.2), 0.09, Color("#f1faee"), 3, 5)
	return b.commit()


## Фонарь: изящный чугунный столб с фигурным основанием, кованым кронштейном
## и навесным шестигранным плафоном.
static func lamp_post() -> ArrayMesh:
	var b := MeshBuilder.new()
	# Декоративное основание с фаской
	b.cylinder(Vector3(0.0, 0.28, 0.0), 0.28, 0.38, 0.56, LAMP_POLE, 8)
	b.cylinder(Vector3(0.0, 0.62, 0.0), 0.22, 0.28, 0.16, LAMP_POLE, 8)
	# Основная мачта с небольшим конусом
	b.cylinder(Vector3(0.0, 3.0, 0.0), 0.11, 0.17, 4.6, LAMP_POLE, 8)
	b.cylinder(Vector3(0.0, 5.3, 0.0), 0.15, 0.15, 0.12, LAMP_POLE, 8)
	b.cone(Vector3(0.0, 5.55, 0.0), 0.14, 0.35, LAMP_POLE, 6)

	# Изогнутый кронштейн в сторону дороги (+X)
	b.box(Vector3(0.2, 5.38, 0.0), Vector3(0.36, 0.08, 0.08), LAMP_POLE, Basis(Vector3.FORWARD, -0.3))
	b.box(Vector3(0.42, 5.52, 0.0), Vector3(0.25, 0.08, 0.08), LAMP_POLE, Basis(Vector3.FORWARD, 0.2))
	b.cylinder(Vector3(0.48, 5.42, 0.0), 0.04, 0.04, 0.16, LAMP_POLE, 6)
	b.cone(Vector3(0.48, 5.54, 0.0), 0.22, 0.14, LAMP_POLE, 6)
	b.cone(Vector3(0.48, 5.16, 0.0), 0.06, 0.12, LAMP_POLE, 6, Basis(Vector3.FORWARD, PI))
	return b.commit()


## Светящийся плафон фонаря (вынесен для отдельного ночного свечения).
static func lamp_head() -> ArrayMesh:
	var b := MeshBuilder.new()
	# Шестигранный светящийся стеклянный фонарь
	b.cylinder(Vector3(0.48, 5.34, 0.0), 0.18, 0.13, 0.32, LAMP_HEAD, 6)
	b.sphere(Vector3(0.48, 5.34, 0.0), 0.09, Color.WHITE, 3, 6)
	return b.commit()


## Урна: парковая цилиндрическая урна на опоре с навесом от дождя и пепельницей.
static func waste_bin() -> ArrayMesh:
	var b := MeshBuilder.new()
	# Опорная стойка
	b.cylinder(Vector3(0.0, 0.08, 0.0), 0.18, 0.24, 0.16, SIGNAL_POLE, 8)
	b.cylinder(Vector3(0.0, 0.42, 0.0), 0.06, 0.06, 0.65, SIGNAL_POLE, 6)
	# Корпус урны
	b.cylinder(Vector3(0.0, 0.52, 0.0), 0.32, 0.28, 0.68, BIN_BODY, 8)
	b.cylinder(Vector3(0.0, 0.86, 0.0), 0.34, 0.34, 0.06, SIGNAL_BOX, 8)
	# Стойки навеса
	b.box(Vector3(-0.25, 0.94, 0.0), Vector3(0.04, 0.16, 0.04), SIGNAL_POLE)
	b.box(Vector3(0.25, 0.94, 0.0), Vector3(0.04, 0.16, 0.04), SIGNAL_POLE)
	b.cone(Vector3(0.0, 1.05, 0.0), 0.36, 0.18, SIGNAL_BOX, 8)
	return b.commit()


## Скамейка: парковая скамья с чугунными ножками, подлокотниками и деревянными рейками.
static func bench() -> ArrayMesh:
	var b := MeshBuilder.new()
	# Чугунные боковые опоры и подлокотники
	for sx: float in [-0.78, 0.78]:
		b.cylinder(Vector3(sx, 0.21, -0.16), 0.04, 0.05, 0.42, BENCH_LEG, 6)
		b.cylinder(Vector3(sx, 0.21, 0.16), 0.04, 0.05, 0.42, BENCH_LEG, 6)
		b.box(Vector3(sx, 0.16, 0.0), Vector3(0.06, 0.06, 0.36), BENCH_LEG)
		b.box(Vector3(sx, 0.52, 0.0), Vector3(0.06, 0.05, 0.42), BENCH_LEG)
		b.cylinder(Vector3(sx, 0.66, -0.20), 0.04, 0.04, 0.46, BENCH_LEG, 6, Basis(Vector3.RIGHT, 0.15))

	# Деревянные рейки сиденья (3 рейки с зазором)
	b.box(Vector3(0.0, 0.42, -0.12), Vector3(1.8, 0.04, 0.12), BENCH_WOOD)
	b.box(Vector3(0.0, 0.42, 0.02), Vector3(1.8, 0.04, 0.12), BENCH_WOOD)
	b.box(Vector3(0.0, 0.42, 0.16), Vector3(1.8, 0.04, 0.12), BENCH_WOOD)

	# Деревянные рейки спинки (2 широкие рейки с наклоном)
	b.box(Vector3(0.0, 0.62, -0.21), Vector3(1.8, 0.12, 0.035), BENCH_WOOD, Basis(Vector3.RIGHT, 0.15))
	b.box(Vector3(0.0, 0.78, -0.24), Vector3(1.8, 0.12, 0.035), BENCH_WOOD, Basis(Vector3.RIGHT, 0.15))
	return b.commit()


## Клумба: фигурный каменный вазон с грунтом и цветущей растительностью.
static func planter() -> ArrayMesh:
	var b := MeshBuilder.new()
	# Вазон
	b.cylinder(Vector3(0.0, 0.1, 0.0), 0.45, 0.54, 0.2, PLANTER, 8)
	b.cylinder(Vector3(0.0, 0.35, 0.0), 0.65, 0.45, 0.32, PLANTER, 8)
	b.cylinder(Vector3(0.0, 0.54, 0.0), 0.72, 0.65, 0.1, PLANTER, 8)
	# Земля
	b.cylinder(Vector3(0.0, 0.55, 0.0), 0.64, 0.64, 0.04, Color("#26201a"), 8)
	# Зелень
	b.sphere(Vector3(0.0, 0.75, 0.0), 0.6, Color("#3d7832"), 4, 7, 0.8)
	# Цветы
	b.sphere(Vector3(0.25, 0.85, 0.18), 0.12, Color("#e63946"), 3, 5)
	b.sphere(Vector3(-0.22, 0.88, 0.22), 0.12, Color("#ffb703"), 3, 5)
	b.sphere(Vector3(-0.24, 0.84, -0.2), 0.12, Color("#8338ec"), 3, 5)
	b.sphere(Vector3(0.2, 0.86, -0.24), 0.12, Color("#f1faee"), 3, 5)
	return b.commit()


## Стойка светофора: фундамент, мачта, экран с козырьками над линзами.
static func signal_post() -> ArrayMesh:
	var b := MeshBuilder.new()
	# Фундамент и основание
	b.box(Vector3(0.0, 0.25, 0.0), Vector3(0.42, 0.5, 0.42), SIGNAL_POLE)
	b.cylinder(Vector3(0.0, 0.52, 0.0), 0.22, 0.26, 0.06, SIGNAL_POLE, 8)
	b.cylinder(Vector3(0.0, 2.7, 0.0), 0.11, 0.16, 4.4, SIGNAL_POLE, 8)
	b.cone(Vector3(0.0, 5.0, 0.0), 0.13, 0.2, SIGNAL_POLE, 6)

	# Кронштейн и щит транспортного светофора
	b.box(Vector3(0.0, 4.2, 0.16), Vector3(0.12, 0.12, 0.32), SIGNAL_POLE)
	b.box(Vector3(0.0, 4.2, 0.31), Vector3(0.66, 1.82, 0.02), Color("#0a0a0c"))
	b.box(Vector3(0.0, 4.2, 0.42), Vector3(0.48, 1.62, 0.22), SIGNAL_BOX)
	for k in 3:
		var y := 4.7 - k * 0.5
		b.cylinder(Vector3(0.0, y, 0.56), 0.20, 0.20, 0.14, SIGNAL_BOX, 8, Basis(Vector3.RIGHT, PI * 0.5), false)

	# Пешеходный светофор
	b.box(Vector3(0.0, 2.3, 0.16), Vector3(0.36, 0.74, 0.02), Color("#0a0a0c"))
	b.box(Vector3(0.0, 2.3, 0.25), Vector3(0.28, 0.64, 0.18), SIGNAL_BOX)
	b.cylinder(Vector3(0.0, 2.45, 0.36), 0.12, 0.12, 0.12, SIGNAL_BOX, 8, Basis(Vector3.RIGHT, PI * 0.5), false)
	b.cylinder(Vector3(0.0, 2.15, 0.36), 0.12, 0.12, 0.12, SIGNAL_BOX, 8, Basis(Vector3.RIGHT, PI * 0.5), false)
	return b.commit()


## Одна линза светофора.
static func signal_lens() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.sphere(Vector3.ZERO, 0.18, Color.WHITE, 3, 8)
	return b.commit()


## Полоса зебры.
static func zebra_stripe() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.plane_xz(Vector3.ZERO, Vector2(0.6, 3.4), ZEBRA)
	return b.commit()


## Штрих осевой разметки.
static func road_dash() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.plane_xz(Vector3.ZERO, Vector2(0.25, 3.2), MARKING)
	return b.commit()


## Качественные low-poly модели припаркованных машин (седан, хэтчбек, фургон).
static func parked_car(kind: int) -> ArrayMesh:
	var b := MeshBuilder.new()
	match kind:
		1: # хэтчбек
			# Нижняя часть кузова и пороги
			b.box(Vector3(0.0, 0.44, 0.0), Vector3(1.88, 0.18, 3.9), SIGNAL_BOX)
			b.tapered_box(Vector3(0.0, 0.70, 0.0), Vector3(1.86, 0.42, 4.0),
				Color.WHITE, Vector2(0.96, 0.98), 0.0, -0.06, -0.04)
			# Кабина и остекление
			b.tapered_box(Vector3(0.0, 1.10, -0.25), Vector3(1.60, 0.46, 2.2),
				Color.WHITE, Vector2(0.88, 0.75), -0.08, -0.16, -0.06)
			b.box(Vector3(0.0, 1.12, -0.25), Vector3(1.52, 0.36, 1.8), GLASS)
			# Фары, бамперы, номера
			b.box(Vector3(0.0, 0.58, 2.02), Vector3(1.82, 0.18, 0.08), SIGNAL_BOX)
			b.box(Vector3(0.0, 0.58, -2.02), Vector3(1.82, 0.18, 0.08), SIGNAL_BOX)
			b.box(Vector3(-0.65, 0.72, 2.02), Vector3(0.32, 0.14, 0.04), LAMP_FRONT)
			b.box(Vector3(0.65, 0.72, 2.02), Vector3(0.32, 0.14, 0.04), LAMP_FRONT)
			b.box(Vector3(-0.65, 0.72, -2.02), Vector3(0.32, 0.14, 0.04), LAMP_REAR)
			b.box(Vector3(0.65, 0.72, -2.02), Vector3(0.32, 0.14, 0.04), LAMP_REAR)
			b.box(Vector3(0.0, 0.54, 2.04), Vector3(0.44, 0.14, 0.03), PLATE)
			b.box(Vector3(0.0, 0.54, -2.04), Vector3(0.44, 0.14, 0.03), PLATE)

		2: # фургон
			b.box(Vector3(0.0, 0.46, 0.0), Vector3(2.02, 0.20, 5.0), SIGNAL_BOX)
			b.tapered_box(Vector3(0.0, 0.72, 0.0), Vector3(2.0, 0.48, 5.0),
				Color.WHITE, Vector2(0.98, 1.0))
			# Кабина водителя
			b.tapered_box(Vector3(0.0, 1.28, 1.6), Vector3(1.92, 0.80, 1.5),
				Color.WHITE, Vector2(0.92, 0.96), 0.0, -0.12, 0.0)
			b.box(Vector3(0.0, 1.34, 2.32), Vector3(1.76, 0.52, 0.06), GLASS)
			# Грузовой отсек
			b.box(Vector3(0.0, 1.50, -0.7), Vector3(1.96, 1.25, 3.4), Color.WHITE)
			b.box(Vector3(0.0, 0.60, 2.52), Vector3(1.94, 0.20, 0.08), SIGNAL_BOX)
			b.box(Vector3(0.0, 0.60, -2.52), Vector3(1.94, 0.20, 0.08), SIGNAL_BOX)
			b.box(Vector3(-0.72, 0.74, 2.52), Vector3(0.34, 0.16, 0.04), LAMP_FRONT)
			b.box(Vector3(0.72, 0.74, 2.52), Vector3(0.34, 0.16, 0.04), LAMP_FRONT)
			b.box(Vector3(-0.72, 0.74, -2.52), Vector3(0.34, 0.16, 0.04), LAMP_REAR)
			b.box(Vector3(0.72, 0.74, -2.52), Vector3(0.34, 0.16, 0.04), LAMP_REAR)
			b.box(Vector3(0.0, 0.56, 2.54), Vector3(0.46, 0.14, 0.03), PLATE)
			b.box(Vector3(0.0, 0.56, -2.54), Vector3(0.46, 0.14, 0.03), PLATE)

		_: # седан
			b.box(Vector3(0.0, 0.44, 0.0), Vector3(1.90, 0.18, 4.4), SIGNAL_BOX)
			b.tapered_box(Vector3(0.0, 0.72, 0.0), Vector3(1.88, 0.44, 4.4),
				Color.WHITE, Vector2(0.96, 0.98), 0.0, -0.07, -0.06)
			# Салон
			b.tapered_box(Vector3(0.0, 1.14, -0.1), Vector3(1.64, 0.48, 2.1),
				Color.WHITE, Vector2(0.88, 0.68), -0.06, -0.18, -0.1)
			b.box(Vector3(0.0, 1.16, -0.1), Vector3(1.54, 0.38, 1.7), GLASS)
			# Фары, бамперы, номера
			b.box(Vector3(0.0, 0.58, 2.22), Vector3(1.84, 0.18, 0.08), SIGNAL_BOX)
			b.box(Vector3(0.0, 0.58, -2.22), Vector3(1.84, 0.18, 0.08), SIGNAL_BOX)
			b.box(Vector3(-0.66, 0.74, 2.22), Vector3(0.32, 0.14, 0.04), LAMP_FRONT)
			b.box(Vector3(0.66, 0.74, 2.22), Vector3(0.32, 0.14, 0.04), LAMP_FRONT)
			b.box(Vector3(-0.66, 0.74, -2.22), Vector3(0.32, 0.14, 0.04), LAMP_REAR)
			b.box(Vector3(0.66, 0.74, -2.22), Vector3(0.32, 0.14, 0.04), LAMP_REAR)
			b.box(Vector3(0.0, 0.54, 2.24), Vector3(0.44, 0.14, 0.03), PLATE)
			b.box(Vector3(0.0, 0.54, -2.24), Vector3(0.44, 0.14, 0.03), PLATE)

	# Реалистичные 3D колёса с диском и шиной
	var across := Basis(Vector3.FORWARD, PI * 0.5)
	for sx: float in [-0.88, 0.88]:
		for sz: float in [-1.35, 1.35]:
			b.cylinder(Vector3(sx, 0.36, sz), 0.36, 0.36, 0.28, TYRE, 10, across)
			b.cylinder(Vector3(sx + (0.02 if sx > 0 else -0.02), 0.36, sz),
				0.24, 0.24, 0.26, RIM, 8, across)
			b.cylinder(Vector3(sx + (0.03 if sx > 0 else -0.03), 0.36, sz),
				0.08, 0.08, 0.27, CHROME, 6, across)
	return b.commit()
