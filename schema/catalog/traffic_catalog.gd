class_name TrafficCatalog
extends Resource

@export var items: Array[TrafficTypeData] = []
## Реплики водителей трафика.
@export var quotes_ram: QuoteBank
@export var quotes_ped: QuoteBank
@export var quotes_ped_jwalk: QuoteBank
@export var quotes_hit_ped: QuoteBank
@export var quotes_ped_reply: QuoteBank
@export var quotes_ped_reply_jwalk: QuoteBank
## Доля агрессивных водителей.
@export var aggressive_ratio: float = 0.04
## Шанс агрессивного проехать на красный при свободном перекрёстке.
@export var red_light_run_chance: float = 0.3

var _by_id: Dictionary[StringName, TrafficTypeData] = {}
var _values: Array = []
var _weights := PackedFloat32Array()


func index() -> void:
	_by_id.clear()
	_values.clear()
	_weights = PackedFloat32Array()
	for t in items:
		if t == null:
			continue
		_by_id[t.id] = t
		_values.append(t)
		_weights.append(t.weight)


func get_type(id: StringName) -> TrafficTypeData:
	return _by_id.get(id)


func roll(rng: SeededRng) -> TrafficTypeData:
	if _values.is_empty():
		return null
	return rng.pick_weighted(_values, _weights) as TrafficTypeData
