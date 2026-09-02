class_name GfxCatalog
extends Resource

@export var items: Array[GfxPreset] = []

var _by_id: Dictionary[StringName, GfxPreset] = {}


func index() -> void:
	_by_id.clear()
	for p in items:
		if p != null:
			_by_id[p.id] = p


func get_preset(id: StringName) -> GfxPreset:
	return _by_id.get(id)


## Пресет по умолчанию для платформы.
func default_id() -> StringName:
	if OS.has_feature("mobile") or OS.has_feature("web"):
		return &"low"
	return &"high"
