class_name SpatialHash2D
extends RefCounted
## Пространственный хеш в плоскости XZ.
##
## Используется генератором города (проверка «место свободно»), физикой машины
## (коллизии со зданиями и пропсами) и менеджерами трафика/пешеходов (поиск
## соседей). Ключ ячейки — целое число, а не строка «cx,cz»: в оригинале эта
## конкатенация выполнялась десятки раз за кадр в горячих циклах коллизий.
##
## Запросы возвращают переиспользуемый буфер — ноль аллокаций в hot path.

var cell_size := 16.0

## Ячейка -> индексы элементов.
var _cells: Dictionary[int, PackedInt32Array] = {}
## AABB элементов: x0, z0, x1, z1.
var _rects: PackedVector4Array = PackedVector4Array()
## Высота, ниже которой препятствие проезжаемо (арки, навесы). INF — сплошное.
var _overhead: PackedFloat32Array = PackedFloat32Array()
## Переиспользуемый буфер результата.
var _result: PackedInt32Array = PackedInt32Array()
## Отметки, чтобы один элемент не попал в результат дважды.
var _seen: PackedInt32Array = PackedInt32Array()
var _query_stamp := 0


func _init(size: float = 16.0) -> void:
	cell_size = size


func clear() -> void:
	_cells.clear()
	_rects = PackedVector4Array()
	_overhead = PackedFloat32Array()
	_seen = PackedInt32Array()
	_query_stamp = 0


func size() -> int:
	return _rects.size()


func rect_of(index: int) -> Vector4:
	return _rects[index]


func overhead_of(index: int) -> float:
	return _overhead[index]


## Добавляет прямоугольник и возвращает его индекс.
func add_rect(x0: float, z0: float, x1: float, z1: float,
		overhead: float = INF) -> int:
	var index := _rects.size()
	_rects.append(Vector4(x0, z0, x1, z1))
	_overhead.append(overhead)
	_seen.append(0)
	for cx in range(_cell(x0), _cell(x1) + 1):
		for cz in range(_cell(z0), _cell(z1) + 1):
			var key := MathUtils.hash_key(cx, cz)
			if not _cells.has(key):
				_cells[key] = PackedInt32Array()
			_cells[key].append(index)
	return index


func add_point(x: float, z: float, radius: float, overhead: float = INF) -> int:
	return add_rect(x - radius, z - radius, x + radius, z + radius, overhead)


func _cell(v: float) -> int:
	return floori(v / cell_size)


## Индексы элементов, чьи ячейки задевает круг (x, z, radius).
## Результат — переиспользуемый буфер: копировать, если нужен между кадрами.
func query_circle(x: float, z: float, radius: float) -> PackedInt32Array:
	_result.clear()
	_query_stamp += 1
	for cx in range(_cell(x - radius), _cell(x + radius) + 1):
		for cz in range(_cell(z - radius), _cell(z + radius) + 1):
			var bucket: PackedInt32Array = _cells.get(
				MathUtils.hash_key(cx, cz), PackedInt32Array())
			for i in bucket:
				if _seen[i] == _query_stamp:
					continue
				_seen[i] = _query_stamp
				_result.append(i)
	return _result


## Пересекает ли круг хотя бы один прямоугольник.
## player_y и height задают вертикальный габарит: под арку можно проехать.
func overlaps_circle(x: float, z: float, radius: float,
		player_y: float = 0.0, height: float = 1.5) -> bool:
	for i in query_circle(x, z, radius):
		if _overhead[i] < INF and _overhead[i] <= player_y + height:
			continue
		if _circle_hits(i, x, z, radius):
			return true
	return false


func _circle_hits(index: int, x: float, z: float, radius: float) -> bool:
	var r := _rects[index]
	var nx: float = clampf(x, r.x, r.z)
	var nz: float = clampf(z, r.y, r.w)
	var dx := x - nx
	var dz := z - nz
	return dx * dx + dz * dz < radius * radius


## Вектор выталкивания круга из прямоугольника: (nx, nz, depth).
## depth <= 0 означает «не пересекаются». Порт circleAABB() из utils.js.
func resolve_circle(index: int, x: float, z: float, radius: float) -> Vector3:
	var r := _rects[index]
	var nx: float = clampf(x, r.x, r.z)
	var nz: float = clampf(z, r.y, r.w)
	var dx := x - nx
	var dz := z - nz
	var d2 := dx * dx + dz * dz
	if d2 >= radius * radius:
		return Vector3.ZERO
	if d2 > 1e-9:
		var d := sqrt(d2)
		return Vector3(dx / d, dz / d, radius - d)
	# Центр круга внутри прямоугольника — выталкиваем через ближайшую грань.
	var to_left := x - r.x
	var to_right := r.z - x
	var to_top := z - r.y
	var to_bottom := r.w - z
	var m: float = minf(minf(to_left, to_right), minf(to_top, to_bottom))
	if m == to_left:
		return Vector3(-1.0, 0.0, to_left + radius)
	if m == to_right:
		return Vector3(1.0, 0.0, to_right + radius)
	if m == to_top:
		return Vector3(0.0, -1.0, to_top + radius)
	return Vector3(0.0, 1.0, to_bottom + radius)
