class_name CityField
extends RefCounted
## Скалярные поля мира: высота рельефа, расстояние до дороги, «на дороге ли».
##
## Чистая логика без нод и без рендера — то же, что gps.js/pedgraph.js в
## оригинале: полностью покрывается юнит-тестами и одинаково доступна
## генератору, физике машины, пешеходам и ИИ трафика.
##
## Порт heightAt/distToRoad/onRoad/distToSerp (citygen.js:125-170) и
## оси серпантина (citygen.js:654-742).
##
## Рельеф в игре только один — гора Машук на севере. Всё, что южнее
## z = -260 и вне коридора |x| <= 190, строго плоское.

# --- Границы рельефа --------------------------------------------------------
const TERRAIN_Z_MAX := -260.0
const TERRAIN_Z_MIN := -640.0
const TERRAIN_X_LIMIT := 190.0

# --- Машук ------------------------------------------------------------------
## Центр горы под смотровой башней, радиус подошвы, высота конуса, плато.
const HILL := {"x": 0.0, "z": -448.0, "r": 155.0, "cone": 66.0, "top": 58.0}
## Вторая вершина, гладко сопряжённая с основной.
const PEAK2 := {"x": 55.0, "z": -500.0, "r": 70.0, "cone": 46.0, "top": 40.0}
## Радиус плоской площадки на вершине.
const SUMMIT_FLAT_R := 20.0

# --- Серпантин --------------------------------------------------------------
## Полуширина полотна и ширина откоса к естественному рельефу.
const SERP_HALF_WIDTH := 3.6
const SERP_SLOPE := 8.0
## Радиус влияния оси: больше, чем полуширина + откос.
const SERP_INFLUENCE := 14.0
const SERP_HASH_CELL := 8.0
## Ширина, в пределах которой серпантин считается проезжей частью.
const SERP_ROAD_HALF := 4.4

var cell: float = 64.0
var road_half: float = 6.0
var sidewalk: float = 4.0
var grid_ext: float = 36.0
## Координаты осей дорог (одинаковы для вертикальных и горизонтальных).
var road_axes: PackedFloat32Array = PackedFloat32Array()
## Перекрёстки — декартово произведение осей.
var intersections: PackedVector2Array = PackedVector2Array()

## Точки оси серпантина: x, z, накопленная длина s, высота y.
var _serp_x := PackedFloat32Array()
var _serp_z := PackedFloat32Array()
var _serp_y := PackedFloat32Array()
var _serp_hash: Dictionary[int, PackedInt32Array] = {}
var _serp_length := 0.0
## Максимальная координата дорожной сетки, вынесена из горячего цикла.
var _grid_extent := 0.0


func _init(balance: BalanceData = null) -> void:
	if balance != null:
		cell = balance.cell
		road_half = balance.road_half
		sidewalk = balance.sidewalk
		grid_ext = balance.grid_ext
	_build_grid()
	_build_serpentine()


# --- Дорожная сетка ---------------------------------------------------------

func _build_grid() -> void:
	road_axes = PackedFloat32Array()
	intersections = PackedVector2Array()
	# 9 осей от -256 до +256 с шагом 64 (citygen.js:357).
	for i in 9:
		road_axes.append(-256.0 + i * cell)
	for ax in road_axes:
		for az in road_axes:
			intersections.append(Vector2(ax, az))
	_grid_extent = 256.0 + grid_ext


## Расстояние до ближайшей оси проезжей части (без учёта серпантина).
func dist_to_road(x: float, z: float) -> float:
	var best := INF
	# За торцом сетки расстояние считается по обеим осям, внутри — только
	# поперёк дороги. dz/dx вынесены из цикла: они от оси не зависят.
	var dz_outer: float = maxf(0.0, absf(z) - _grid_extent)
	var dx_outer: float = maxf(0.0, absf(x) - _grid_extent)
	for c in road_axes:
		var dv := sqrt((x - c) * (x - c) + dz_outer * dz_outer)
		if dv < best:
			best = dv
		var dh := sqrt((z - c) * (z - c) + dx_outer * dx_outer)
		if dh < best:
			best = dh
	return best


## Проезжая часть города или полотно серпантина.
func on_road(x: float, z: float) -> bool:
	if dist_to_road(x, z) < road_half + sidewalk + 3.0:
		return true
	return dist_to_serp(x, z) < SERP_ROAD_HALF


## Ближайший перекрёсток — по индексу сетки, без перебора всех 81.
func nearest_intersection(x: float, z: float) -> Vector2:
	return Vector2(_snap_axis(x), _snap_axis(z))


func _snap_axis(v: float) -> float:
	var idx := clampi(roundi((v + 256.0) / cell), 0, road_axes.size() - 1)
	return road_axes[idx]


# --- Рельеф -----------------------------------------------------------------

## Базовый рельеф без дороги: Машук + вторая вершина, гладко сопряжённые.
func base_height(x: float, z: float) -> float:
	var h := MathUtils.smin(
		HILL.cone * (1.0 - MathUtils.dist_2d(x, z, HILL.x, HILL.z) / HILL.r),
		HILL.top, 6.0)
	h = MathUtils.smax(h, MathUtils.smin(
		PEAK2.cone * (1.0 - MathUtils.dist_2d(x, z, PEAK2.x, PEAK2.z) / PEAK2.r),
		PEAK2.top, 4.0), 8.0)
	h = MathUtils.smax(h, 0.0, 3.0)
	# Плавный сход на ноль у торца проспекта (z = -292).
	return h * clampf((-z - 288.0) / 12.0, 0.0, 1.0)


## Высота земли. O(1): рельеф ограничен коридором Машука, внутри —
## выборка базовой формы плюс врезка полки серпантина.
func height_at(x: float, z: float) -> float:
	if z > TERRAIN_Z_MAX or z < TERRAIN_Z_MIN \
			or x < -TERRAIN_X_LIMIT or x > TERRAIN_X_LIMIT:
		return 0.0
	var hb := base_height(x, z)
	var d := _serp_near(x, z)
	if d.x < 0.0:
		return hb
	if d.x <= SERP_HALF_WIDTH:
		return d.y
	if d.x >= SERP_HALF_WIDTH + SERP_SLOPE:
		return hb
	# Откос smoothstep между полкой дороги и естественным склоном.
	var t := (d.x - SERP_HALF_WIDTH) / SERP_SLOPE
	return d.y + (hb - d.y) * t * t * (3.0 - 2.0 * t)


func dist_to_serp(x: float, z: float) -> float:
	var d := _serp_near(x, z)
	return INF if d.x < 0.0 else d.x


# --- Серпантин --------------------------------------------------------------

## Ось строится «маршем» (прямая + дуга), а не сплайном через опорные точки:
## так радиус шпильки задан точно, а не получается как придётся.
func _build_serpentine() -> void:
	var d2r := PI / 180.0
	var legs: Array = [
		{"arc": false, "len": 140.0},                  # траверс 1
		{"arc": true, "radius": 13.0, "angle": 150.0 * d2r},   # шпилька 1
		{"arc": false, "len": 80.0},                   # траверс 2
		{"arc": true, "radius": 13.0, "angle": -150.0 * d2r},  # шпилька 2
		{"arc": false, "len": 100.0},                  # траверс 3
		{"arc": true, "radius": 13.0, "angle": 150.0 * d2r},   # шпилька 3
		{"arc": false, "len": 41.0},                   # выезд на площадку вершины
	]
	var s_list := PackedFloat32Array()
	_march(128.0, -292.0, -170.0 * d2r, legs, 2.0, s_list)
	_serp_length = s_list[s_list.size() - 1]
	_serp_y = PackedFloat32Array()
	for s in s_list:
		_serp_y.append(_serp_profile(s, _serp_length))
	_build_serp_hash()


func _march(x0: float, z0: float, heading: float, legs: Array, step: float,
		out_s: PackedFloat32Array) -> void:
	_serp_x = PackedFloat32Array([x0])
	_serp_z = PackedFloat32Array([z0])
	out_s.append(0.0)
	var x := x0
	var z := z0
	var h := heading
	var s := 0.0
	for leg: Dictionary in legs:
		if not leg["arc"]:
			var length: float = leg["len"]
			var n: int = maxi(1, roundi(length / step))
			var dx := cos(h)
			var dz := sin(h)
			for i in range(1, n + 1):
				var t := length * i / float(n)
				_serp_x.append(x + dx * t)
				_serp_z.append(z + dz * t)
				out_s.append(s + t)
			x += dx * length
			z += dz * length
			s += length
		else:
			var r: float = leg["radius"]
			var dh: float = leg["angle"]
			var sgn := signf(dh)
			var cx := x - sgn * r * sin(h)
			var cz := z + sgn * r * cos(h)
			var theta0 := atan2(z - cz, x - cx)
			var arc_len := absf(dh) * r
			var n: int = maxi(1, roundi(arc_len / step))
			for i in range(1, n + 1):
				var frac := i / float(n)
				var theta := theta0 + sgn * absf(dh) * frac
				_serp_x.append(cx + r * cos(theta))
				_serp_z.append(cz + r * sin(theta))
				out_s.append(s + arc_len * frac)
			x = cx + r * cos(theta0 + dh)
			z = cz + r * sin(theta0 + dh)
			h += dh
			s += arc_len


## Продольный профиль: горизонтальный подход, постоянный уклон,
## скруглённые переломы в начале и на выезде.
func _serp_profile(s: float, total: float) -> float:
	const S0 := 20.0
	const VC := 24.0
	var top: float = HILL.top
	var g := top / (total - S0 - VC * 0.5)
	if s <= S0 - VC * 0.5:
		return 0.0
	if s < S0 + VC * 0.5:
		var t := (s - S0 + VC * 0.5) / VC
		return g * VC * t * t * 0.5
	if s > total - VC:
		var t := (total - s) / VC
		return top - g * VC * t * t * 0.5
	return minf(g * (s - S0), top)


func _build_serp_hash() -> void:
	_serp_hash.clear()
	for i in _serp_x.size() - 1:
		var x0: float = minf(_serp_x[i], _serp_x[i + 1]) - SERP_INFLUENCE
		var x1: float = maxf(_serp_x[i], _serp_x[i + 1]) + SERP_INFLUENCE
		var z0: float = minf(_serp_z[i], _serp_z[i + 1]) - SERP_INFLUENCE
		var z1: float = maxf(_serp_z[i], _serp_z[i + 1]) + SERP_INFLUENCE
		for cx in range(floori(x0 / SERP_HASH_CELL), floori(x1 / SERP_HASH_CELL) + 1):
			for cz in range(floori(z0 / SERP_HASH_CELL), floori(z1 / SERP_HASH_CELL) + 1):
				var key := MathUtils.hash_key(cx, cz)
				if not _serp_hash.has(key):
					_serp_hash[key] = PackedInt32Array()
				_serp_hash[key].append(i)


## Ближайшая точка оси: возвращает Vector2(расстояние, высота).
## x < 0 означает «вне зоны влияния».
func _serp_near(x: float, z: float) -> Vector2:
	var best_d := INF
	var best_y := 0.0
	var key := MathUtils.hash_key(floori(x / SERP_HASH_CELL), floori(z / SERP_HASH_CELL))
	if _serp_hash.has(key):
		for i in _serp_hash[key]:
			var ax := _serp_x[i]
			var az := _serp_z[i]
			var dx := _serp_x[i + 1] - ax
			var dz := _serp_z[i + 1] - az
			var denom := dx * dx + dz * dz
			var t := 0.0 if denom < 1e-9 else ((x - ax) * dx + (z - az) * dz) / denom
			t = clampf(t, 0.0, 1.0)
			var d := MathUtils.dist_2d(x, z, ax + dx * t, az + dz * t)
			if d < best_d:
				best_d = d
				best_y = _serp_y[i] + (_serp_y[i + 1] - _serp_y[i]) * t
	# Плоская площадка на вершине.
	var dt: float = maxf(0.0,
		MathUtils.dist_2d(x, z, HILL.x, HILL.z) - SUMMIT_FLAT_R)
	if dt < best_d:
		best_d = dt
		best_y = HILL.top
	if best_d >= SERP_INFLUENCE:
		return Vector2(-1.0, 0.0)
	return Vector2(best_d, best_y)


## Точки оси серпантина — нужны генератору полотна, отбойников и ИИ.
func serpentine_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in _serp_x.size():
		out.append(Vector3(_serp_x[i], _serp_y[i], _serp_z[i]))
	return out


func serpentine_length() -> float:
	return _serp_length
