class_name GpsRouter
extends RefCounted
## GPS-навигация игрока — порт game.js:1416-1470 (выбор цели, троттлинг
## пересчёта) и ui.js:400-425 (угол стрелки).
##
## Приоритет цели: активный заказ > заправка при низком топливе (только за
## рулём — пешком к заправке не ведём, как и в оригинале). Маршрут строится
## по RoadGraph и пересчитывается не каждый кадр, а раз в RECOMPUTE_INTERVAL
## секунд либо при смещении дальше MOVED_FAR_DIST м от точки последнего
## пересчёта.
##
## Стрелка указывает не на саму цель, а на следующую точку маршрута
## (`next_waypoint()` = route[1]) — это и есть подсказка поворота на
## перекрёстке (план, «Улучшения гейплея», п.14): как только игрок минует
## перекрёсток, смещение запускает пересчёт и стрелка перескакивает на
## следующий отрезок дороги.

const RECOMPUTE_INTERVAL := 0.5
const MOVED_FAR_DIST := 32.0
## Гистерезис выхода из режима «веду к заправке» — держим маршрут, пока бак
## не наполнится чуть выше порога, иначе стрелка дёргается туда-сюда
## у самой границы lowFuelRatio.
const FUEL_HYSTERESIS := 0.05

var graph: RoadGraph
var fuel_stations: PackedVector2Array
var low_fuel_ratio: float

## &"order" | &"fuel" | &"" (нет цели — маршрут пуст).
var target_type: StringName = &""
var route: PackedVector2Array = PackedVector2Array()

var _accum := 0.0
var _last_drop := Vector2.INF
var _fuel_target := Vector2.INF
var _from_pos := Vector2.INF


func _init(field: CityField, districts: DistrictCatalog, balance: BalanceData) -> void:
	graph = RoadGraph.new(field)
	fuel_stations = districts.fuel_stations if districts != null else PackedVector2Array()
	low_fuel_ratio = balance.low_fuel_ratio if balance != null else 0.25


## Вызывать раз в кадр. `has_order`/`drop_pos` — активный заказ игрока (только
## за рулём); `fuel_ratio` игнорируется вне машины, как в оригинале.
func update(delta: float, pos: Vector2, in_car: bool, has_order: bool,
		drop_pos: Vector2, fuel_ratio: float) -> void:
	_accum += delta
	if _accum < RECOMPUTE_INTERVAL:
		return
	_accum = 0.0

	if has_order:
		_update_order_route(pos, drop_pos)
	elif in_car:
		_update_fuel_route(pos, fuel_ratio)
	else:
		_clear()


func _update_order_route(pos: Vector2, drop_pos: Vector2) -> void:
	var moved_far := pos.distance_squared_to(_from_pos) > MOVED_FAR_DIST * MOVED_FAR_DIST
	if drop_pos != _last_drop or moved_far or route.is_empty():
		route = graph.build_route(pos, drop_pos)
		_last_drop = drop_pos
		_from_pos = pos
	target_type = &"order"
	_fuel_target = Vector2.INF


func _update_fuel_route(pos: Vector2, fuel_ratio: float) -> void:
	var is_low := fuel_ratio < low_fuel_ratio
	var keep := target_type == &"fuel" and fuel_ratio < low_fuel_ratio + FUEL_HYSTERESIS
	if not (is_low or keep) or fuel_stations.is_empty():
		_clear()
		return

	var station := _nearest_fuel_station(pos)
	var moved_far := pos.distance_squared_to(_from_pos) > MOVED_FAR_DIST * MOVED_FAR_DIST
	if station != _fuel_target or moved_far or route.is_empty():
		route = graph.build_route(pos, station)
		_fuel_target = station
		_from_pos = pos
	target_type = &"fuel"
	_last_drop = Vector2.INF


func _nearest_fuel_station(pos: Vector2) -> Vector2:
	var best: Vector2 = fuel_stations[0]
	var best_d := INF
	for s in fuel_stations:
		var d := pos.distance_squared_to(s)
		if d < best_d:
			best_d = d
			best = s
	return best


## Сброс маршрута — вызывается после дозаправки (economy, этап 15), как в
## оригинале refuel() (game.js:1034-1035).
func reset() -> void:
	_clear()


func _clear() -> void:
	route = PackedVector2Array()
	target_type = &""
	_last_drop = Vector2.INF
	_fuel_target = Vector2.INF


func has_target() -> bool:
	return target_type != &""


## Следующая точка маршрута — по ней целится стрелка. Не конечная цель:
## именно это даёт подсказку поворота, см. описание класса.
func next_waypoint() -> Vector2:
	if route.size() > 1:
		return route[1]
	if route.size() == 1:
		return route[0]
	return Vector2.INF


func final_target() -> Vector2:
	return route[route.size() - 1] if not route.is_empty() else Vector2.INF


func remaining_distance() -> float:
	return RoadGraph.route_length(route)


## Угол HUD-стрелки в радианах, готовый для `Control.rotation`: 0 — глиф
## смотрит вправо на экране (нейтральная поза), курс/позиция отсчитываются
## от игрока. Порт формулы ui.js:410-420; `pos`/`target` — мировые (x, z)
## в Vector2 (та же конвенция, что Order.pickup_pos: .y хранит мировой z).
static func arrow_angle(pos: Vector2, heading: float, target: Vector2) -> float:
	var dx := target.x - pos.x
	var dz := target.y - pos.y
	var fwd_c := dx * sin(heading) + dz * cos(heading)
	var rgt_c := -dx * cos(heading) + dz * sin(heading)
	return wrapf(-atan2(fwd_c, rgt_c), -PI, PI)
