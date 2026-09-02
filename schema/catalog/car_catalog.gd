class_name CarCatalog
extends Resource
## Каталог автомобилей + тюнинг. Индексируется один раз в Db._ready().

@export var items: Array[CarData] = []
@export var tuning: TuningCatalog

var _by_id: Dictionary[StringName, CarData] = {}
var _order: Array[StringName] = []


func index() -> void:
	_by_id.clear()
	_order.clear()
	for c in items:
		if c == null:
			continue
		_by_id[c.id] = c
		_order.append(c.id)


func get_car(id: StringName) -> CarData:
	return _by_id.get(id)


func ids() -> Array[StringName]:
	return _order


func size() -> int:
	return items.size()
