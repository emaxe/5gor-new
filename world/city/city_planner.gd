class_name CityPlanner
extends RefCounted
## Фаза A генерации города: из данных получается CityPlan.
##
## Только чистые вычисления над Packed*Array — ни одной ноды, ни одного
## ресурса. Поэтому фаза целиком выносится в WorkerThreadPool, а на
## однопоточном web-экспорте разбивается по кадрам.
##
## Порт _buildings/_trees/_lamps/_props/_parkedCars/_collectPickupPoints
## из citygen.js. Ключевое отличие: ВСЯ генерация идёт через сидированный
## SeededRng. В оригинале сидирована только часть (this.rng), а размещение
## зданий и деревьев шло через несидированный Math.random() — то есть город
## там был разным при каждой загрузке, и выучить его было невозможно.

## Кварталов по стороне (8x8 внутри сетки 9x9 дорог).
const BLOCKS := 8
## Левый нижний угол квартала: -246 = -256 + 10 (отступ от оси дороги).
const BLOCK_ORIGIN := -246.0
## Сторона застраиваемой части квартала.
const BLOCK_SIDE := 44.0

## Деревья: минимальное расстояние до оси дороги во дворах.
const TREE_ROAD_CLEARANCE := 11.5
const TREE_SERP_CLEARANCE := 12.0
## Деревьев на квартал по районам (citygen.js:2078).
const TREES_PER_DISTRICT := {
	&"center": 1, &"kurort": 3, &"prigorod": 2, &"sanatorii": 4,
	&"mashuk": 3, &"proval": 8, &"rynok": 2, &"vokzal": 3,
}
const TREES_IN_PARK := 12
const TREES_FOOTHILL := 70
const TREES_RING := 280

## Фонари: шаг вдоль дороги и вынос на внешний край тротуара.
const LAMP_STEP := 48.0
const LAMP_OFFSET := 9.0
const LAMP_FROM := -200.0
const LAMP_TO := 248.0

## Точки подачи: шаг вдоль дороги.
const PICKUP_STEP := 48.0
const PICKUP_RANGE := 208.0

## Стойки светофоров стоят по углам, отступ 8.2 от центра перекрёстка.
const SIGNAL_OFFSET := 8.2

## Цвета мелкого пропса (citygen.js).
const COLOR_BIN := Color("#7a7a72")
const COLOR_BUSH := Color("#4a8a42")
const COLOR_BENCH := Color("#8a6a44")
const COLOR_PLANTER := Color("#bdb4a2")
const COLOR_TREE_TRUNK := Color("#6a4a34")
const TREE_LEAF_COLORS: PackedColorArray = [
	Color("#5a9a4a"), Color("#6aaa55"), Color("#4d8a42"), Color("#74b25e"),
]
const TREE_PINE_COLORS: PackedColorArray = [
	Color("#2e6a3e"), Color("#3a7a48"), Color("#275a33"),
]
const PARKED_COLORS: PackedColorArray = [
	Color("#e8e8e8"), Color("#9aa0a8"), Color("#5060a0"), Color("#b03030"),
	Color("#2a2a2a"), Color("#c0a070"), Color("#d8c088"), Color("#4a5a4a"),
]

var field: CityField
var graph: PedGraph
var districts: DistrictCatalog

var _plan: CityPlan
var _rng: SeededRng
## Занятые места: здания и пропсы, для проверки «место свободно».
var _blockers: SpatialHash2D
var _pickup_hash: SpatialHash2D
var _crosswalk_hash: SpatialHash2D


func _init(city_field: CityField, ped_graph: PedGraph,
		district_catalog: DistrictCatalog) -> void:
	field = city_field
	graph = ped_graph
	districts = district_catalog


## Полный проход планирования.
func plan(seed_value: int) -> CityPlan:
	_plan = CityPlan.new()
	_plan.seed_value = seed_value
	_rng = SeededRng.new(seed_value)
	_blockers = SpatialHash2D.new(16.0)
	_pickup_hash = SpatialHash2D.new(16.0)
	_crosswalk_hash = SpatialHash2D.new(16.0)

	# Порядок значим: разметка и точки подачи резервируют место до того, как
	# на тротуар начнут ставить фонари, урны и лавки.
	_plan_crosswalks()
	_plan_pickups()
	_plan_signals()
	_plan_buildings()
	_plan_trees()
	_plan_lamps()
	_plan_street_furniture()
	_plan_parked_cars()
	return _plan


# --- Кварталы ---------------------------------------------------------------

## Район квартала. Порт blockDistrict (citygen.js:97).
static func block_district(bi: int, bj: int) -> StringName:
	if bi == 3 and bj == 3: return &"center"
	if bi == 4 and bj == 3: return &"center"
	if bi == 4 and bj == 4: return &"center"
	if bi == 3 and bj == 4: return &"center"
	if bi == 5 and bj == 3: return &"rynok"
	if bi == 6 and bj == 5: return &"vokzal"
	if bi == 2 and bj == 1: return &"proval"
	if bi <= 2 and bj <= 1: return &"mashuk"
	if bi >= 5 and bj <= 5: return &"sanatorii"
	if bj >= 6: return &"prigorod"
	if bi <= 2: return &"kurort"
	return &"center"


## Особый квартал, застройке не подлежащий. Порт blockSpecial (citygen.js:110).
static func block_special(bi: int, bj: int) -> StringName:
	if bi == 3 and bj == 4: return &"park"
	if bi == 2 and bj == 1: return &"lake"
	if bi == 5 and bj == 3: return &"rynok"
	if bi == 6 and bj == 5: return &"vokzal"
	if bi == 3 and bj == 3: return &"narzan"
	return &""


static func block_rect(bi: int, bj: int) -> Rect2:
	return Rect2(BLOCK_ORIGIN + bi * 64.0, BLOCK_ORIGIN + bj * 64.0,
		BLOCK_SIDE, BLOCK_SIDE)


# --- Разметка и точки геймплея ----------------------------------------------

## Зебры рисуются из списка переходов графа: разметка не может разъехаться
## с логикой ПДД (принцип из проекта capital).
func _plan_crosswalks() -> void:
	for c: Dictionary in graph.crossings:
		var center: Vector3 = c["center"]
		# Переход поперёк вертикальной дороги идёт вдоль X.
		var yaw := 0.0 if int(c["axis"]) == PedGraph.CrossAxis.Z_ROAD else PI * 0.5
		_plan.crosswalk_pos.append(center)
		_plan.crosswalk_yaw.append(yaw)
		_crosswalk_hash.add_point(center.x, center.z, field.road_half + 1.0)


## Точки подачи такси вдоль каждой дороги. Порт _collectPickupPoints.
func _plan_pickups() -> void:
	var side_offset := field.road_half + field.sidewalk * 0.5
	for c in field.road_axes:
		var v := -PICKUP_RANGE
		while v <= PICKUP_RANGE:
			for s: float in [-1.0, 1.0]:
				# Вдоль вертикальной дороги.
				var px := c + s * side_offset
				if field.dist_to_road(px, v) >= field.road_half:
					_add_pickup(px, v)
				# Вдоль горизонтальной.
				var pz := c + s * side_offset
				if field.dist_to_road(v, pz) >= field.road_half:
					_add_pickup(v, pz)
			v += PICKUP_STEP


func _add_pickup(x: float, z: float) -> void:
	_plan.pickup_pos.append(Vector2(x, z))
	_plan.pickup_district.append(_district_index_at(x, z))
	_pickup_hash.add_point(x, z, 2.0)


func _district_index_at(x: float, z: float) -> int:
	var bi := clampi(floori((x + 256.0) / 64.0), 0, BLOCKS - 1)
	var bj := clampi(floori((z + 256.0) / 64.0), 0, BLOCKS - 1)
	var id := block_district(bi, bj)
	for i in districts.items.size():
		if districts.items[i].id == id:
			return i
	return 0


## Стойки светофоров — по четырём углам регулируемых перекрёстков.
func _plan_signals() -> void:
	for i in PedGraph.AXES:
		for j in PedGraph.AXES:
			if not PedGraph.is_signalized(i, j):
				continue
			var cx := field.road_axes[i]
			var cz := field.road_axes[j]
			# Каждый угол обслуживает одну ось: стойка смотрит на ту дорогу,
			# движение по которой она регулирует (citygen.js:2693).
			var corners := [
				{"x": cx + SIGNAL_OFFSET, "z": cz + SIGNAL_OFFSET,
					"axis": TrafficLightController.Axis.Z_ROAD, "yaw": PI},
				{"x": cx + SIGNAL_OFFSET, "z": cz - SIGNAL_OFFSET,
					"axis": TrafficLightController.Axis.X_ROAD, "yaw": -PI * 0.5},
				{"x": cx - SIGNAL_OFFSET, "z": cz - SIGNAL_OFFSET,
					"axis": TrafficLightController.Axis.Z_ROAD, "yaw": 0.0},
				{"x": cx - SIGNAL_OFFSET, "z": cz + SIGNAL_OFFSET,
					"axis": TrafficLightController.Axis.X_ROAD, "yaw": PI * 0.5},
			]
			for c: Dictionary in corners:
				_plan.signal_pos.append(Vector3(c["x"], 0.0, c["z"]))
				_plan.signal_yaw.append(c["yaw"])
				_plan.signal_intersection.append(i * PedGraph.AXES + j)
				_plan.signal_axis.append(int(c["axis"]))
				_blockers.add_point(c["x"], c["z"], 0.45)


# --- Застройка --------------------------------------------------------------

## Периметральная застройка: дома стоят вдоль улиц, внутри квартала двор.
##
## В оригинале дома разбрасывались случайно по кварталу (rand по x и z с
## проверкой на пересечение), и выходило 1-2 дома на квартал — город читался
## как редкий макет. Пятигорск застроен периметрально, поэтому здесь фасады
## выстраиваются по фронту улицы, а внутри остаётся двор.
func _plan_buildings() -> void:
	for bi in BLOCKS:
		for bj in BLOCKS:
			if not block_special(bi, bj).is_empty():
				continue
			var district_id := block_district(bi, bj)
			var d := districts.get_district(district_id)
			if d == null:
				continue
			_plan_block(block_rect(bi, bj), d)


func _plan_block(r: Rect2, d: DistrictData) -> void:
	var placed: Array[Rect2] = []
	# Чем плотнее район, тем реже разрывы во фронте и глубже корпуса.
	var density := clampf(d.density / 4.0, 0.25, 1.0)
	var side_chance := 0.55 + 0.4 * density
	for side in 4:
		if not _rng.chance(side_chance):
			continue
		_plan_block_side(r, side, d, density, placed)
	# Дворовый корпус — в плотных районах.
	if _rng.chance(0.25 * density) and placed.size() > 0:
		var w := _rng.randf_range(9.0, 15.0)
		var dep := _rng.randf_range(9.0, 15.0)
		var x := r.position.x + (r.size.x - w) * 0.5 + _rng.randf_range(-3.0, 3.0)
		var z := r.position.y + (r.size.y - dep) * 0.5 + _rng.randf_range(-3.0, 3.0)
		_try_place_building(Rect2(x, z, w, dep), d, placed, 2.5)


## Ряд домов вдоль одной стороны квартала. side: 0 — север (-Z), 1 — восток
## (+X), 2 — юг (+Z), 3 — запад (-X).
func _plan_block_side(r: Rect2, side: int, d: DistrictData, density: float,
		placed: Array[Rect2]) -> void:
	var along_len: float = r.size.x if side == 0 or side == 2 else r.size.y
	var cursor := _rng.randf_range(0.0, 5.0)
	var guard := 0
	while cursor < along_len - 8.0 and guard < 16:
		guard += 1
		var w: float = minf(_rng.randf_range(9.0, 22.0), along_len - cursor)
		if w < 8.0:
			break
		var depth := _rng.randf_range(9.0, 9.0 + 8.0 * density)
		var rect := _side_rect(r, side, cursor, w, depth)
		_try_place_building(rect, d, placed, 1.0)
		# Разрыв между домами: в плотной застройке фасады смыкаются.
		cursor += w + _rng.randf_range(0.5, 2.0 + 6.0 * (1.0 - density))


func _side_rect(r: Rect2, side: int, offset: float, w: float,
		depth: float) -> Rect2:
	match side:
		0:
			return Rect2(r.position.x + offset, r.position.y, w, depth)
		1:
			return Rect2(r.end.x - depth, r.position.y + offset, depth, w)
		2:
			return Rect2(r.position.x + offset, r.end.y - depth, w, depth)
		_:
			return Rect2(r.position.x, r.position.y + offset, depth, w)


func _try_place_building(rect: Rect2, d: DistrictData, placed: Array[Rect2],
		gap: float) -> void:
	if _overlaps_placed(placed, rect, gap):
		return
	placed.append(rect)
	var facade := _rng.pick_color(d.palette.facades)
	var height := _rng.randf_range(d.height_min, d.height_max)
	# Скатная кровля бывает только у малоэтажных домов: на восьмиэтажке
	# в Пятигорске плоская крыша.
	var roof_kind := 1 if height < 13.0 and _rng.chance(0.55) else 0
	_plan.add_building(
		Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y),
		height,
		facade,
		d.palette.roof_color(_rng.pick_color(d.palette.facades)),
		_district_index_at(rect.get_center().x, rect.get_center().y),
		roof_kind)
	_blockers.add_rect(rect.position.x, rect.position.y, rect.end.x, rect.end.y)


static func _overlaps_placed(placed: Array[Rect2], rect: Rect2, gap: float) -> bool:
	var grown := rect.grow(gap)
	for p in placed:
		if grown.intersects(p):
			return true
	return false


# --- Озеленение -------------------------------------------------------------

func _plan_trees() -> void:
	for bi in BLOCKS:
		for bj in BLOCKS:
			var special := block_special(bi, bj)
			if special == &"rynok":
				continue # рынок мощён и обнесён оградой
			var district_id := block_district(bi, bj)
			var r := block_rect(bi, bj)
			var n: int = TREES_IN_PARK if special == &"park" \
				else int(TREES_PER_DISTRICT.get(district_id, 2))
			for k in n:
				var x := r.position.x + _rng.randf_to(BLOCK_SIDE)
				var z := r.position.y + _rng.randf_to(BLOCK_SIDE)
				if special == &"park":
					# Не сажаем на площади и радиальных дорожках Цветника.
					if MathUtils.dist_2d(x, z, -32.0, 32.0) < 18.0:
						continue
					if absf(x + 32.0) < 3.4 or absf(z - 32.0) < 3.4:
						continue
				_try_add_tree(x, z, _rng.chance(0.75), special == &"park")

	# Опушка Машука и предгорье.
	for k in TREES_FOOTHILL:
		var x := (_rng.next() - 0.5) * 320.0
		var z := -300.0 - _rng.randf_to(200.0)
		_try_add_tree(x, z, _rng.chance(0.35), true)

	# Зелёное кольцо за пределами застройки.
	for k in TREES_RING:
		var a := _rng.randf_to(TAU)
		var dd := 265.0 + _rng.randf_to(140.0)
		_try_add_tree(cos(a) * dd, sin(a) * dd, _rng.chance(0.65), true)


func _try_add_tree(x: float, z: float, deciduous: bool, in_park: bool) -> void:
	if not in_park and field.dist_to_road(x, z) < TREE_ROAD_CLEARANCE:
		return
	if not _is_free(x, z, 1.8):
		return
	if field.dist_to_serp(x, z) < TREE_SERP_CLEARANCE:
		return
	var scale := _rng.randf_range(0.75, 1.35)
	_plan.tree_pos.append(Vector3(x, field.height_at(x, z), z))
	_plan.tree_scale.append(scale)
	_plan.tree_kind.append(0 if deciduous else 1)
	_plan.tree_color.append(_rng.pick_color(
		TREE_LEAF_COLORS if deciduous else TREE_PINE_COLORS))
	# Крона на высоте 2.7 — под ней можно пройти, но не проехать.
	_blockers.add_point(x, z, 0.45, 2.7)


# --- Уличное оборудование ---------------------------------------------------

func _plan_lamps() -> void:
	for c in field.road_axes:
		var side := 1.0
		var v := LAMP_FROM
		while v <= LAMP_TO:
			# Вдоль вертикальной дороги: фонарь на внешнем краю тротуара.
			var lx := c - LAMP_OFFSET * side
			if _is_free(lx, v, 0.5):
				_plan.lamp_pos.append(Vector3(lx, field.height_at(lx, v), v))
				_plan.lamp_yaw.append(0.0 if side > 0.0 else PI)
				_blockers.add_point(lx, v, 0.25)
			# Вдоль горизонтальной.
			var lz := c - LAMP_OFFSET * side
			if _is_free(v, lz, 0.5):
				_plan.lamp_pos.append(Vector3(v, field.height_at(v, lz), lz))
				_plan.lamp_yaw.append(-side * PI * 0.5)
				_blockers.add_point(v, lz, 0.25)
			side = -side
			v += LAMP_STEP


func _plan_street_furniture() -> void:
	var side_offset := field.road_half + field.sidewalk * 0.5
	for c in field.road_axes:
		var v := -216.0
		while v <= 216.0:
			for s: float in [-1.0, 1.0]:
				var bx := c + s * side_offset
				if _rng.chance(0.35) and _is_free(bx, v, 0.6):
					_add_bin(bx, v)
				if _rng.chance(0.25) and _is_free(v, c + s * side_offset, 0.6):
					_add_bin(v, c + s * side_offset)
				if _rng.chance(0.22) and _is_free(bx, v + 6.0, 1.0):
					_add_bench(bx, v + 6.0, 0.0 if s > 0.0 else PI)
				if _rng.chance(0.18) and _is_free(v + 6.0, c + s * side_offset, 1.0):
					_add_bench(v + 6.0, c + s * side_offset, PI * 0.5)
			v += 24.0

	# Кусты во дворах — там же, где деревья, но ближе к домам.
	for k in 220:
		var x := (_rng.next() - 0.5) * 500.0
		var z := (_rng.next() - 0.5) * 500.0
		if field.dist_to_road(x, z) < 10.0:
			continue
		if not _is_free(x, z, 1.0):
			continue
		_plan.bush_pos.append(Vector3(x, field.height_at(x, z), z))
		_plan.bush_scale.append(_rng.randf_range(0.7, 1.3))
		_blockers.add_point(x, z, 0.9, 1.2)


func _add_bin(x: float, z: float) -> void:
	_plan.bin_pos.append(Vector3(x, field.height_at(x, z), z))
	_blockers.add_point(x, z, 0.45)


func _add_bench(x: float, z: float, yaw: float) -> void:
	_plan.bench_pos.append(Vector3(x, field.height_at(x, z), z))
	_plan.bench_yaw.append(yaw)
	_blockers.add_point(x, z, 1.0)


## Припаркованные машины стоят у бордюра, носом вдоль дороги.
func _plan_parked_cars() -> void:
	var curb := field.road_half - 1.2
	for c in field.road_axes:
		var v := -200.0
		while v <= 200.0:
			for s: float in [-1.0, 1.0]:
				# Стоянка у бордюра — единственный пропс, который НАХОДИТСЯ
				# на проезжей части, поэтому проверка места без условия
				# «подальше от дороги».
				if _rng.chance(0.30):
					var px := c + s * curb
					if _is_free_on_road(px, v, 2.4):
						_add_parked(px, v, 0.0 if s > 0.0 else PI)
				if _rng.chance(0.30):
					var pz := c + s * curb
					if _is_free_on_road(v, pz, 2.4):
						_add_parked(v, pz, PI * 0.5 if s > 0.0 else -PI * 0.5)
			v += 28.0


func _add_parked(x: float, z: float, yaw: float) -> void:
	_plan.parked_pos.append(Vector3(x, field.height_at(x, z), z))
	_plan.parked_yaw.append(yaw)
	_plan.parked_color.append(_rng.pick_color(PARKED_COLORS))
	_plan.parked_kind.append(_rng.randi_below(3))
	_blockers.add_rect(x - 1.1, z - 2.3, x + 1.1, z + 2.3)


# --- Проверка места ---------------------------------------------------------

## Порт isPositionValid: не на проезжей части, не в здании, не на точке
## подачи, не на зебре и не поверх другого пропса.
func _is_free(x: float, z: float, radius: float) -> bool:
	if field.dist_to_road(x, z) < field.road_half + radius + 0.3:
		return false
	return _is_free_on_road(x, z, radius)


## То же без условия «подальше от дороги» — для объектов, которые стоят
## на самой проезжей части (припаркованные машины у бордюра).
func _is_free_on_road(x: float, z: float, radius: float) -> bool:
	if _blockers.overlaps_circle(x, z, radius):
		return false
	if _pickup_hash.overlaps_circle(x, z, radius + 1.2):
		return false
	if _crosswalk_hash.overlaps_circle(x, z, radius + 0.8):
		return false
	return true
