class_name RoadGraph
extends RefCounted
## Граф автомобильных дорог для GPS-навигации игрока — порт gps.js
## (buildCarRoadGraph/findCarRoute/routeLength).
##
## Только для GPS: у трафика собственное движение по рёбрам `CityGraph`
## (TrafficManager), этот индекс им не нужен.
##
## Узлы и рёбра берутся из живого `CityGraph` (топология Пятигорска), а не
## строятся решёткой 9x9: id точки `AStar2D` совпадает с id узла графа, вес
## связи — [b]длина полилинии ребра[/b], а не расстояние между позициями
## узлов. Разница не косметическая: у серпантина на Машук полилиния 265 м
## при хорде 101 м (в 2.6 раза), и на хордовых весах A* считал бы подъём в
## гору кратчайшим путём между её подножием и вершиной траверса.
##
## [b]Точки маршрута — позиции узлов, а не полилинии рёбер.[/b] `route[1]`
## для `GpsRouter` — это подсказка поворота (`next_waypoint()`), а маршрут
## пересчитывается не каждый кадр, а раз в `MOVED_FAR_DIST` = 32 м пути.
## Промежуточные точки полилиний идут с шагом 10-12 м
## (`PyatigorskTopology.TERRAIN_STEP`), поэтому за один интервал игрок успел
## бы миновать две-три из них и стрелка указывала бы назад. Плата за это —
## на кривых рёбрах нарисованный маршрут идёт хордой, и `route_length()`
## занижает остаток пути (заметно только на серпантине); стоимость самого
## поиска при этом честная, полилинейная. Развести «точки для стрелки» и
## «полилинию для отрисовки» можно только вместе с `GpsRouter`.

## AStar2D, у которого стоимость связи задана снаружи, а не выведена из
## расстояния между точками. Эвристика (`_estimate_cost`) остаётся штатной
## евклидовой: она не длиннее любой полилинии между теми же концами, значит
## допустима, и A* остаётся оптимальным.
class PolylineAStar extends AStar2D:
	## Пара узлов (меньший id, больший) -> длина ребра, м.
	var _cost: Dictionary[Vector2i, float] = {}

	## Соединяет узлы, запоминая вес. Параллельные рёбра (объезд вокруг
	## одного квартала) схлопываются в одну связь: остаётся кратчайшее.
	func link(a: int, b: int, length: float) -> void:
		var key := Vector2i(mini(a, b), maxi(a, b))
		_cost[key] = minf(_cost.get(key, INF), length)
		connect_points(a, b)

	func _compute_cost(from_id: int, to_id: int) -> float:
		return _cost[Vector2i(mini(from_id, to_id), maxi(from_id, to_id))]


var _astar := PolylineAStar.new()


func _init(roads: CityGraph) -> void:
	for id in roads.node_count():
		var p := roads.node_position(id)
		_astar.add_point(id, Vector2(p.x, p.z))
	for e in roads.edge_count():
		var ends := roads.edge_ends(e)
		_astar.link(ends.x, ends.y, roads.edge_length(e))


## Ближайший узел графа к мировой точке (x, z=y компонента Vector2).
##
## Поиск плоский, без дизамбигуации по ярусу (`CityGraph.nearest_node`):
## у GPS на входе только (x, z) — игрок приходит из `World` без высоты, —
## а подставлять выдуманный y значит с равной вероятностью привязать его к
## чужому ярусу. Цена ошибки здесь мала: маршрут по эстакаде и маршрут по
## улице под ней всё равно сходятся через пандусы в паре десятков метров.
func nearest_node_id(pos: Vector2) -> int:
	return _astar.get_closest_point(pos)


func node_position(id: int) -> Vector2:
	return _astar.get_point_position(id)


## Маршрут от `from` до `to`: точное начало, узлы графа по пути, точный
## конец — порт findCarRoute (gps.js:175-198). Пустой массив, если пути нет
## (узлы в разных компонентах связности — у живого города такого нет).
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
