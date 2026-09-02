class_name TrafficTypeData
extends Resource
## Тип транспорта в трафике. Порт TRAFFIC_TYPES (traffic.js:106).

@export var id: StringName = &""
## Силуэт для CarMeshBuilder.
@export var silhouette: StringName = &"sedan"
## Радиус для проверки столкновений.
@export var radius: float = 2.0
@export var length: float = 4.4
@export var width: float = 1.9
## Вес случайного выбора при спавне.
@export var weight: float = 1.0
@export var colors: PackedColorArray = PackedColorArray()
## Единственный допустимый цвет (маршрутка, автобус, полиция, скорая, такси).
@export var force_color: bool = false
## Мигалка: &"" | &"police" | &"ambulance".
@export var beacon: StringName = &""
## Жёлтая ливрея такси с шашечками.
@export var livery: bool = false
## Синяя полоса полиции.
@export var police_livery: bool = false
## Обвес: &"stock" | &"sport".
@export var body_kit: StringName = &"stock"
@export var quotes: QuoteBank
