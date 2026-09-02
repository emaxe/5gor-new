class_name DistrictCatalog
extends Resource

@export var items: Array[DistrictData] = []
@export var landmarks: Array[LandmarkData] = []
## Заправки, мировые координаты XZ. Порт FUEL_STATIONS (config.js:391).
@export var fuel_stations: PackedVector2Array = PackedVector2Array()

var _by_id: Dictionary[StringName, DistrictData] = {}
var _landmark_by_id: Dictionary[StringName, LandmarkData] = {}


func index() -> void:
	_by_id.clear()
	_landmark_by_id.clear()
	for d in items:
		if d != null:
			_by_id[d.id] = d
	for l in landmarks:
		if l != null:
			_landmark_by_id[l.id] = l


func get_district(id: StringName) -> DistrictData:
	return _by_id.get(id)


func get_landmark(id: StringName) -> LandmarkData:
	return _landmark_by_id.get(id)


## Районы, доступные при текущем рейтинге игрока.
func unlocked(rating: float) -> Array[DistrictData]:
	var out: Array[DistrictData] = []
	for d in items:
		if d != null and rating >= d.unlock_rating:
			out.append(d)
	return out
