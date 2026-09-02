class_name PropMeshes
extends RefCounted
## Библиотека мешей повторяющегося пропса.
##
## Каждый меш строится один раз и раздаётся в MultiMesh: деревьев, фонарей и
## урн в городе сотни, но draw call у каждого типа один. Цвет вариации идёт
## per-instance, поэтому меши белые (COLOR = 1) и красятся инстансом.

const TRUNK := Color("#6a4a34")
const LAMP_POLE := Color("#4a4a4a")
const LAMP_HEAD := Color("#fff2b0")
const BIN_BODY := Color("#7a7a72")
const BENCH_WOOD := Color("#8a6a44")
const BENCH_LEG := Color("#5a5a54")
const PLANTER := Color("#bdb4a2")
const SIGNAL_POLE := Color("#484a4c")
const SIGNAL_BOX := Color("#1c1c1e")
const MARKING := Color("#e8e8dc")
const ZEBRA := Color("#ffffff")
const GLASS := Color("#1c2836")
const TYRE := Color("#20242c")


## Лиственное дерево: ствол + гранёная крона. Крона белая — цвет задаёт
## инстанс, поэтому одним мешем покрываются все оттенки листвы.
static func deciduous_tree() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.cylinder(Vector3(0.0, 1.2, 0.0), 0.3, 0.45, 2.4, TRUNK, 5)
	b.sphere(Vector3(0.0, 2.9, 0.0), 1.7, Color.WHITE, 4, 7, 1.05)
	return b.commit()


static func pine_tree() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.cylinder(Vector3(0.0, 1.0, 0.0), 0.3, 0.45, 2.0, TRUNK, 5)
	b.cone(Vector3(0.0, 4.25, 0.0), 2.2, 5.5, Color.WHITE, 7)
	return b.commit()


static func bush() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.sphere(Vector3(0.0, 0.6, 0.0), 0.9, Color.WHITE, 3, 6, 0.7)
	return b.commit()


## Фонарь: столб с кронштейном и плафоном. Плафон вынесен отдельным мешем,
## чтобы ночью зажигать его эмиссией, не трогая столб.
static func lamp_post() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.cylinder(Vector3(0.0, 2.8, 0.0), 0.12, 0.16, 5.6, LAMP_POLE, 6)
	b.box(Vector3(0.18, 5.55, 0.0), Vector3(0.36, 0.1, 0.1), LAMP_POLE)
	return b.commit()


static func lamp_head() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.box(Vector3(0.35, 5.6, 0.0), Vector3(0.55, 0.2, 0.4), LAMP_HEAD)
	return b.commit()


static func waste_bin() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.cylinder(Vector3(0.0, 0.425, 0.0), 0.34, 0.4, 0.85, BIN_BODY, 7)
	b.cylinder(Vector3(0.0, 0.88, 0.0), 0.36, 0.36, 0.06, SIGNAL_BOX, 7)
	return b.commit()


static func bench() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.box(Vector3(0.0, 0.42, 0.0), Vector3(1.8, 0.08, 0.5), BENCH_WOOD)
	b.box(Vector3(0.0, 0.72, -0.22), Vector3(1.8, 0.5, 0.07), BENCH_WOOD)
	for sx: float in [-0.75, 0.75]:
		b.box(Vector3(sx, 0.21, 0.0), Vector3(0.08, 0.42, 0.46), BENCH_LEG)
	return b.commit()


static func planter() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.cylinder(Vector3(0.0, 0.3, 0.0), 0.62, 0.5, 0.6, PLANTER, 8)
	b.cylinder(Vector3(0.0, 0.62, 0.0), 0.56, 0.56, 0.1, Color("#4f8a3f"), 8)
	return b.commit()


## Стойка светофора: фундамент, столб, кронштейны, корпуса.
static func signal_post() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.cylinder(Vector3(0.0, 0.175, 0.0), 0.28, 0.32, 0.35, SIGNAL_POLE, 8)
	b.cylinder(Vector3(0.0, 0.45, 0.0), 0.2, 0.24, 0.3, SIGNAL_POLE, 8)
	b.cylinder(Vector3(0.0, 2.55, 0.0), 0.12, 0.17, 4.1, SIGNAL_POLE, 8)
	b.cylinder(Vector3(0.0, 4.65, 0.0), 0.14, 0.14, 0.1, SIGNAL_POLE, 8)
	# Транспортный корпус на 3 секции и пешеходный на 2.
	b.box(Vector3(0.0, 4.2, 0.28), Vector3(0.5, 1.6, 0.26), SIGNAL_BOX)
	b.box(Vector3(0.0, 4.2, 0.14), Vector3(0.62, 1.72, 0.03), SIGNAL_BOX)
	b.box(Vector3(0.0, 2.3, 0.22), Vector3(0.28, 0.6, 0.18), SIGNAL_BOX)
	for k in 3:
		var y := 4.7 - k * 0.5
		# Козырёк над линзой.
		b.box(Vector3(0.0, y + 0.19, 0.48), Vector3(0.44, 0.05, 0.22), SIGNAL_BOX)
	return b.commit()


## Одна линза светофора. Позиция секции задаётся трансформом инстанса,
## а цвет — per-instance данными: смена фазы не трогает геометрию.
static func signal_lens() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.sphere(Vector3.ZERO, 0.18, Color.WHITE, 3, 8)
	return b.commit()


## Полоса зебры. Зебра собирается из шести таких инстансов.
static func zebra_stripe() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.plane_xz(Vector3.ZERO, Vector2(0.6, 3.4), ZEBRA)
	return b.commit()


## Штрих осевой разметки.
static func road_dash() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.plane_xz(Vector3.ZERO, Vector2(0.25, 3.2), MARKING)
	return b.commit()


## Упрощённый силуэт припаркованной машины. Три варианта: седан, хэтчбек, фургон.
static func parked_car(kind: int) -> ArrayMesh:
	var b := MeshBuilder.new()
	match kind:
		1: # хэтчбек
			b.tapered_box(Vector3(0.0, 0.68, 0.0), Vector3(1.85, 0.44, 4.0),
				Color.WHITE, Vector2(0.98, 1.0))
			b.tapered_box(Vector3(0.0, 1.05, -0.35), Vector3(1.6, 0.44, 2.1),
				Color.WHITE, Vector2(0.9, 0.75), -0.1, -0.22, -0.05)
			b.box(Vector3(0.0, 1.22, -0.35), Vector3(1.44, 0.1, 1.5), GLASS)
		2: # фургон
			b.tapered_box(Vector3(0.0, 0.7, 0.0), Vector3(2.05, 0.5, 5.0),
				Color.WHITE, Vector2(0.99, 1.0))
			b.box(Vector3(0.0, 1.45, -0.5), Vector3(1.98, 1.0, 3.4), Color.WHITE)
			b.box(Vector3(0.0, 1.3, 2.05), Vector3(1.7, 0.5, 0.1), GLASS)
		_: # седан
			b.tapered_box(Vector3(0.0, 0.72, 0.0), Vector3(1.9, 0.42, 4.4),
				Color.WHITE, Vector2(0.98, 1.0))
			b.tapered_box(Vector3(0.0, 1.1, -0.15), Vector3(1.64, 0.46, 2.0),
				Color.WHITE, Vector2(0.9, 0.62), -0.12, -0.28, -0.1)
			b.box(Vector3(0.0, 1.3, -0.15), Vector3(1.48, 0.1, 1.3), GLASS)
	for sx: float in [-0.85, 0.85]:
		for sz: float in [-1.35, 1.35]:
			b.cylinder(Vector3(sx, 0.34, sz), 0.34, 0.34, 0.26, TYRE, 8,
				Basis(Vector3.FORWARD, PI * 0.5))
	return b.commit()
