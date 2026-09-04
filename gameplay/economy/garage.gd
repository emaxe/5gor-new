class_name Garage
extends RefCounted
## Владение машинами и уровни апгрейдов по каждой из них.
##
## Живёт в Game.garage (не сбрасывается start_shift() — гараж не привязан
## к смене, как и lifetime_stats). MVP этапа 15: покупка/переключение машин
## и апгрейды с реальным списанием денег; тюнинг и обслуживание — позже.

var owned_cars: Array[StringName] = [&"taxi"]
var active_car_id: StringName = &"taxi"
## "<car_id>:<upgrade_id>" -> уровень. Плоский словарь вместо
## Dictionary[StringName, Dictionary] — вложенный Dictionary не сохраняет
## типизацию значения (Dictionary[StringName, int]), которую ждёт
## CarRuntime.upgrade_levels, и присваивание падает рантайм-ошибкой.
var _upgrade_levels: Dictionary[String, int] = {}


func owns(car_id: StringName) -> bool:
	return car_id in owned_cars


func upgrade_level(car_id: StringName, upgrade_id: StringName) -> int:
	return _upgrade_levels.get(_key(car_id, upgrade_id), 0)


## Типизирован под CarRuntime.upgrade_levels — строится заново из плоского
## хранилища, а не читается напрямую, чтобы отдать корректно типизированный
## Dictionary[StringName, int].
func upgrade_levels_for(car_id: StringName) -> Dictionary[StringName, int]:
	var out: Dictionary[StringName, int] = {}
	for upgrade: UpgradeData in Db.upgrades.items:
		var level := upgrade_level(car_id, upgrade.id)
		if level > 0:
			out[upgrade.id] = level
	return out


func _key(car_id: StringName, upgrade_id: StringName) -> String:
	return "%s:%s" % [car_id, upgrade_id]


## Покупка машины по id из Db.cars: недостаточный рейтинг или деньги —
## отказ без списания. true, если куплена (или уже была куплена раньше).
func buy_car(car_id: StringName) -> bool:
	if owns(car_id):
		return false
	var data: CarData = Db.cars.get_car(car_id)
	if data == null:
		return false
	if Game.rating < data.unlock_rating:
		return false
	if not Game.spend(data.price):
		return false
	owned_cars.append(car_id)
	return true


func set_active(car_id: StringName) -> bool:
	if not owns(car_id):
		return false
	active_car_id = car_id
	return true


## Следующий уровень апгрейда upgrade_id для car_id. false на максимуме или
## при нехватке денег — уровень не меняется.
func buy_upgrade(car_id: StringName, upgrade_id: StringName) -> bool:
	var upgrade: UpgradeData = Db.upgrades.get_upgrade(upgrade_id)
	if upgrade == null:
		return false
	var level := upgrade_level(car_id, upgrade_id)
	var cost := upgrade.cost_at(level)
	if cost < 0:
		return false
	if not Game.spend(cost):
		return false
	_upgrade_levels[_key(car_id, upgrade_id)] = level + 1
	return true
