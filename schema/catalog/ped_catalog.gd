class_name PedCatalog
extends Resource

@export var items: Array[PedArchetypeData] = []
## Общие пулы, если у архетипа свой не задан.
@export var quotes_idle: QuoteBank
@export var quotes_curse: QuoteBank
@export var quotes_curse_sidewalk: QuoteBank
@export var quotes_curse_redlight: QuoteBank
@export var quotes_shout: QuoteBank

@export_group("Общие палитры")
@export var skin_colors: PackedColorArray = PackedColorArray()
@export var hair_colors: PackedColorArray = PackedColorArray()
@export var shoe_colors: PackedColorArray = PackedColorArray()
@export var cloth_colors: PackedColorArray = PackedColorArray()
@export var pants_colors: PackedColorArray = PackedColorArray()

var _by_id: Dictionary[StringName, PedArchetypeData] = {}
var _values: Array = []
var _weights := PackedFloat32Array()


func index() -> void:
	_by_id.clear()
	_values.clear()
	_weights = PackedFloat32Array()
	for p in items:
		if p == null:
			continue
		_by_id[p.id] = p
		_values.append(p)
		_weights.append(p.weight)


func get_archetype(id: StringName) -> PedArchetypeData:
	return _by_id.get(id)


func roll(rng: SeededRng) -> PedArchetypeData:
	if _values.is_empty():
		return null
	return rng.pick_weighted(_values, _weights) as PedArchetypeData
