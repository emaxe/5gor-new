class_name WeatherData
extends Resource
## Погодные условия. Порт WEATHER_DEFS (config.js:397).

@export var id: StringName = &""
@export var display_name: String = ""
@export var icon: StringName = &""
## Интенсивность дождя 0..1.
@export var rain: float = 0.0
@export var fog_near: float = 500.0
@export var fog_far: float = 1600.0
## Множитель сцепления машины с дорогой.
@export var grip: float = 1.0
## Множитель скорости/плотности трафика.
@export var traffic: float = 1.0
## Вес случайного выбора погоды на смену (clear 55 / rain 25 / fog 20).
@export var spawn_weight: float = 1.0
## Тонировка неба этой погодой.
@export var sky_tint: Color = Color.WHITE
@export var sky_tint_strength: float = 0.0
