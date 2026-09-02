class_name DistrictData
extends Resource
## Район города. Порт DISTRICTS (config.js:263).

@export var id: StringName = &""
@export var display_name: String = ""
## Рейтинг, с которого в районе появляются заказы.
@export var unlock_rating: int = 0
## Вес генерации заказов и застройки.
@export var weight: float = 10.0
@export var palette: PaletteData
## Диапазон высоты зданий [min, max], м.
@export var height_min: float = 8.0
@export var height_max: float = 18.0
## Плотность застройки: зданий на квартал = density + 1.
@export var density: int = 3
## Цвет района на миникарте.
@export var map_color: Color = Color.WHITE

@export_group("Спрос по времени суток")
## Множители веса заказов: утро (6-11), день (11-17), вечер (17-22), ночь (22-6).
## Улучшение относительно оригинала: там спрос равномерный и смена без ритма.
@export var demand_morning: float = 1.0
@export var demand_day: float = 1.0
@export var demand_evening: float = 1.0
@export var demand_night: float = 1.0


func demand_at(hour: float) -> float:
	if hour >= 22.0 or hour < 6.0:
		return demand_night
	if hour < 11.0:
		return demand_morning
	if hour < 17.0:
		return demand_day
	return demand_evening
