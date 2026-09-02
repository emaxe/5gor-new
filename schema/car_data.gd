class_name CarData
extends Resource
## Определение автомобиля. Порт CARS (config.js:297).
## Read-only во время игры: апгрейды и тюнинг живут в CarRuntime.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

@export_group("Экономика")
@export var price: int = 0
@export var unlock_rating: int = 0

@export_group("Характеристики")
## Максимальная скорость, м/с (HUD показывает ×3.6 км/ч).
@export var max_speed: float = 34.0
@export var accel: float = 13.0
@export var brake: float = 26.0
@export var grip: float = 1.0
@export var armor: float = 1.0
## Ёмкость бака, условные единицы топлива.
@export var tank: float = 100.0
@export var capacity: int = 1
@export var steer: float = 2.1

@export_group("Внешность")
@export var shape: CarShapeData
@export var body_color: Color = Color(0.949, 0.757, 0.180)
## Такси-ливрея (шашечки + плафон). У оригинала завязано на carId == 'taxi'.
@export var is_taxi: bool = false
## Декаль по умолчанию: none|stripe|checker|racing.
@export var default_decal: StringName = &"none"
