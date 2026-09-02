class_name WeatherCatalog
extends Resource

@export var items: Array[WeatherData] = []

var _by_id: Dictionary[StringName, WeatherData] = {}


func index() -> void:
	_by_id.clear()
	for w in items:
		if w != null:
			_by_id[w.id] = w


func get_weather(id: StringName) -> WeatherData:
	return _by_id.get(id)


func roll(rng: SeededRng) -> WeatherData:
	var values: Array = []
	var weights := PackedFloat32Array()
	for w in items:
		if w == null:
			continue
		values.append(w)
		weights.append(w.spawn_weight)
	if values.is_empty():
		return null
	return rng.pick_weighted(values, weights) as WeatherData
