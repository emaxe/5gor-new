class_name CarShapeData
extends Resource
## Габариты кузова по типу машины. Порт CAR_TYPE_SHAPE (config.js:337) —
## ЕДИНЫЙ источник правды: и для построения меша, и для капсульного коллайдера
## из трёх кругов, и для геометрии следов шин.

## Силуэт для CarMeshBuilder: sedan|hatch|wagon|coupe|suv|retro|premium|van|bus|pickup|truck
@export var silhouette: StringName = &"sedan"
## Ширина кузова, м.
@export var width: float = 1.9
## Длина кузова, м.
@export var length: float = 4.3


## Радиус круга капсулы: полуширина с запасом 3% (player.js:315).
func collider_radius() -> float:
	return width * 0.5 * 1.03


## Смещение переднего/заднего круга от центра (player.js:316).
func collider_separation() -> float:
	return length * 0.5 - width * 0.5
