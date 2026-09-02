class_name RadioCatalog
extends Resource

@export var items: Array[RadioStationData] = []
## Рецепты синтеза SFX. Порт audiosfx.js.
@export var sfx: Array[SfxRecipe] = []

var _by_id: Dictionary[StringName, RadioStationData] = {}
var _sfx_by_id: Dictionary[StringName, SfxRecipe] = {}
var _order: Array[StringName] = []


func index() -> void:
	_by_id.clear()
	_sfx_by_id.clear()
	_order.clear()
	for s in items:
		if s == null:
			continue
		_by_id[s.id] = s
		_order.append(s.id)
	for r in sfx:
		if r != null:
			_sfx_by_id[r.id] = r


func get_station(id: StringName) -> RadioStationData:
	return _by_id.get(id)


func get_sfx(id: StringName) -> SfxRecipe:
	return _sfx_by_id.get(id)


## Следующая станция по кругу, включая псевдостанцию &"off".
func next_station(current: StringName) -> StringName:
	if _order.is_empty():
		return &"off"
	if current == &"off":
		return _order[0]
	var i := _order.find(current)
	if i < 0 or i + 1 >= _order.size():
		return &"off"
	return _order[i + 1]
