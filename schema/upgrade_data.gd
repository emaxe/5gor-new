class_name UpgradeData
extends Resource
## Апгрейд. Порт UPGRADES (config.js:287) + эффекты из upgrades.js:37.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: StringName = &""

@export_group("Цена")
@export var max_level: int = 4
@export var base_cost: int = 600
@export var cost_mult: float = 1.7

@export_group("Эффект за уровень")
@export var max_speed_per_level: float = 0.0
@export var accel_per_level: float = 0.0
@export var brake_per_level: float = 0.0
@export var grip_per_level: float = 0.0
@export var steer_per_level: float = 0.0
@export var armor_per_level: float = 0.0
@export var tank_per_level: float = 0.0
@export var capacity_per_level: int = 0


## Цена следующего уровня. -1 если уровень максимальный (upgrades.js:22).
func cost_at(level: int) -> int:
	if level >= max_level:
		return -1
	return roundi(base_cost * pow(cost_mult, level))
