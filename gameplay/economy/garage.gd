class_name Garage
extends RefCounted
## Владение машинами, уровни апгрейдов и тюнинг-косметика по каждой из них.
##
## Живёт в Game.garage (не сбрасывается start_shift() — гараж не привязан
## к смене, как и lifetime_stats).

var owned_cars: Array[StringName] = [&"taxi"]
var active_car_id: StringName = &"taxi"
## "<car_id>:<upgrade_id>" -> уровень. Плоский словарь вместо
## Dictionary[StringName, Dictionary] — вложенный Dictionary не сохраняет
## типизацию значения (Dictionary[StringName, int]), которую ждёт
## CarRuntime.upgrade_levels, и присваивание падает рантайм-ошибкой.
var _upgrade_levels: Dictionary[String, int] = {}

## Тюнинг — за каждой машиной свой, а не один общий набор: заводская
## окраска у каждой модели своя (CarData.body_color уже совпадает с одним
## из TuningCatalog.colors), и глобальный выбор цвета перекрасил бы разом
## весь парк при первом же клике. -1 у color/decal значит «заводское
## значение машины» (CarData.body_color / CarData.default_decal).
const TUNING_DEFAULTS := {
	&"color": -1, &"rims": 0, &"spoiler": false, &"body_kit": 0, &"decal": -1,
}
var _tuning: Dictionary[String, Variant] = {}


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


# --- Тюнинг-косметика (бесплатно — только внешний вид) ------------------------

func tuning_value(car_id: StringName, field: StringName) -> Variant:
	return _tuning.get(_key(car_id, field), TUNING_DEFAULTS[field])


func set_tuning(car_id: StringName, field: StringName, value: Variant) -> void:
	_tuning[_key(car_id, field)] = value


## Полный набор тюнинга машины — то, что читает PlayerCar._apply_tuning().
func tuning_for(car_id: StringName) -> Dictionary:
	var out := {}
	for field: StringName in TUNING_DEFAULTS:
		out[field] = tuning_value(car_id, field)
	return out


# --- Обслуживание -------------------------------------------------------------

## Стоимость ремонта текущего повреждения активной машины; 0, если нечего чинить.
func repair_cost(runtime: CarRuntime) -> int:
	return ceili(runtime.damage * Db.balance.repair_cost_per_damage)


## Списывает деньги и чинит кузов. false — нечего чинить или не хватает денег.
func repair(runtime: CarRuntime) -> bool:
	var cost := repair_cost(runtime)
	if cost <= 0:
		return false
	if not Game.spend(cost):
		return false
	runtime.repair()
	return true


## false — машина уже чистая или не хватает денег.
func wash(runtime: CarRuntime) -> bool:
	if runtime.dirt <= 0.0:
		return false
	if not Game.spend(Db.balance.wash_cost):
		return false
	runtime.wash()
	return true


# --- Сериализация (SaveManager) ------------------------------------------------

## Снимок для слота сохранения. _upgrade_levels/_tuning остаются приватными —
## SaveManager не должен трогать внутреннее представление гаража напрямую.
func to_save_dict() -> Dictionary:
	var owned: Array[String] = []
	for c in owned_cars:
		owned.append(String(c))
	return {
		"owned_cars": owned,
		"active_car_id": String(active_car_id),
		"upgrade_levels": _upgrade_levels.duplicate(),
		"tuning": _tuning.duplicate(),
	}


## Восстанавливает состояние из dict, произведённого to_save_dict(). Отсутствующие
## ключи берут дефолт — старый формат сейва не должен падать при загрузке.
func apply_save_dict(dict: Dictionary) -> void:
	var owned: Array = dict.get("owned_cars", [])
	var next_owned: Array[StringName] = []
	for c in owned:
		next_owned.append(StringName(String(c)))
	if next_owned.is_empty():
		next_owned.append(&"taxi")
	owned_cars = next_owned
	active_car_id = StringName(String(dict.get("active_car_id", "taxi")))
	_upgrade_levels.clear()
	var levels: Dictionary = dict.get("upgrade_levels", {})
	for k: Variant in levels:
		_upgrade_levels[String(k)] = int(levels[k])
	_tuning.clear()
	var tuning: Dictionary = dict.get("tuning", {})
	for k: Variant in tuning:
		_tuning[String(k)] = tuning[k]
