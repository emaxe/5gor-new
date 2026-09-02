class_name UpgradeCatalog
extends Resource

@export var items: Array[UpgradeData] = []

var _by_id: Dictionary[StringName, UpgradeData] = {}
var _order: Array[StringName] = []


func index() -> void:
	_by_id.clear()
	_order.clear()
	for u in items:
		if u == null:
			continue
		_by_id[u.id] = u
		_order.append(u.id)


func get_upgrade(id: StringName) -> UpgradeData:
	return _by_id.get(id)


func ids() -> Array[StringName]:
	return _order
