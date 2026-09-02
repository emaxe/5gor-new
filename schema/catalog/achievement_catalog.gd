class_name AchievementCatalog
extends Resource

@export var items: Array[AchievementData] = []

var _by_id: Dictionary[StringName, AchievementData] = {}


func index() -> void:
	_by_id.clear()
	for a in items:
		if a != null:
			_by_id[a.id] = a


func get_achievement(id: StringName) -> AchievementData:
	return _by_id.get(id)


func size() -> int:
	return items.size()
