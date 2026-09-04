class_name RoadGraph
extends RefCounted
## Граф автомобильных дорог для GPS-навигации игрока — порт gps.js
## (buildCarRoadGraph/findCarRoute/routeLength).
##
## Только для GPS: у трафика собственное движение «на рельсах»
## (TrafficManager, axis/coord/pos/dir), этот граф им не нужен.
##
## Узлы — все 81 пересечение сетки 9x9, ребро между соседями по сетке
## (шаг `field.cell`). Сетка регулярная и полностью связная, поэтому
## кратчайший путь по хопам совпадает с кратчайшим по расстоянию — берём
## штатный `AStar2D` вместо ручного BFS оригинала (тот же приём, что и
## PedGraph: движковый C++ поиск вместо ручного обхода).

var _field: CityField
var _astar := AStar2D.new()
var _origin: float
var _count: int


func _init(field: CityField) -> void:
	_field = field
	_origin = field.road_axes[0]
	_count = field.road_axes.size()
	for gx in _count:
		for gz in _count:
			_astar.add_point(_id(gx, gz),
				Vector2(field.road_axes[gx], field.road_axes[gz]))
	for gx in _count:
		for gz in _count:
			var id := _id(gx, gz)
			if gx + 1 < _count:
				_astar.connect_points(id, _id(gx + 1, gz))
			if gz + 1 < _count:
				_astar.connect_points(id, _id(gx, gz + 1))


func _id(gx: int, gz: int) -> int:
	return gx * _count + gz


func _grid_index(v: float) -> int:
	return clampi(roundi((v - _origin) / _field.cell), 0, _count - 1)


## Ближайший узел графа к мировой точке (x, z=y компонента Vector2).
func nearest_node_id(pos: Vector2) -> int:
	return _id(_grid_index(pos.x), _grid_index(pos.y))


func node_position(id: int) -> Vector2:
	return _astar.get_point_position(id)


## Маршрут от `from` до `to`: точное начало, перекрёстки по пути, точный
## конец — порт findCarRoute (gps.js:175-198). Пустой массив, если сетка
## не построена (не должно происходить — граф полносвязный).
func build_route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var from_id := nearest_node_id(from)
	var to_id := nearest_node_id(to)
	var ids := _astar.get_id_path(from_id, to_id)
	if ids.is_empty():
		return points

	points.append(from)
	for id in ids:
		var p := node_position(id)
		if points[points.size() - 1].distance_to(p) > 0.01:
			points.append(p)
	if points[points.size() - 1].distance_to(to) > 0.01:
		points.append(to)
	return points


## Длина ломаной маршрута — порт routeLength (gps.js:93-104).
static func route_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	return total
