class_name OrderCatalog
extends Resource
## Типы заказов, сюжетные миссии, шкала настроения, пулы отзывов и диалогов.

@export var types: Array[OrderTypeData] = []
@export var missions: Array[MissionData] = []
## Ступени настроения по возрастанию min_style. Порт MOOD_TIERS.
@export var mood_tiers: Array[MoodTier] = []
## Отзывы по числу звёзд 1..5. Порт REVIEWS (orders.js:66).
@export var reviews_1: QuoteBank
@export var reviews_2: QuoteBank
@export var reviews_3: QuoteBank
@export var reviews_4: QuoteBank
@export var reviews_5: QuoteBank

@export_group("Прочие пулы реплик")
@export var passenger_names: QuoteBank
@export var drift_reactions: QuoteBank
@export var dispatcher_general: QuoteBank
@export var dispatcher_rain: QuoteBank
@export var dispatcher_fog: QuoteBank
@export var dispatcher_night: QuoteBank
@export var day_note_good: QuoteBank
@export var day_note_crashes: QuoteBank
@export var day_note_low_earned: QuoteBank
@export var day_note_general: QuoteBank
@export var weather_clear: QuoteBank
@export var weather_rain: QuoteBank
@export var weather_fog: QuoteBank

var _by_id: Dictionary[StringName, OrderTypeData] = {}
var _mission_by_id: Dictionary[StringName, MissionData] = {}


func index() -> void:
	_by_id.clear()
	_mission_by_id.clear()
	for t in types:
		if t != null:
			_by_id[t.id] = t
	for m in missions:
		if m != null:
			_mission_by_id[m.id] = m
	mood_tiers.sort_custom(func(a: MoodTier, b: MoodTier) -> bool:
		return a.min_style < b.min_style)


func get_type(id: StringName) -> OrderTypeData:
	return _by_id.get(id)


func get_mission(id: StringName) -> MissionData:
	return _mission_by_id.get(id)


## Первая подходящая ступень по убыванию min_style (config.js:238).
func mood_for(style: float) -> MoodTier:
	var found: MoodTier = null
	for t in mood_tiers:
		if style >= t.min_style:
			found = t
	return found


func reviews_for(stars: int) -> QuoteBank:
	match clampi(stars, 1, 5):
		1: return reviews_1
		2: return reviews_2
		3: return reviews_3
		4: return reviews_4
		_: return reviews_5
