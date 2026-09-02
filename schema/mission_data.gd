class_name MissionData
extends Resource
## Сюжетная миссия. Порт MISSION_TEMPLATES (orders.js:18).
## Выполняется один раз за смену, шанс появления вместо обычного заказа — 30%.

@export var id: StringName = &""
@export var title: String = ""
@export_multiline var description: String = ""
@export var icon: String = "M"
@export var color: Color = Color.WHITE

@export var required_rating: int = 0
@export var pay: int = 900
@export var time_limit: float = 0.0
## Базовый тип поведения: mission|race|tour.
@export var kind: StringName = &"mission"

## Район, в котором берётся точка подачи.
@export var pickup_district: StringName = &"center"
## Точки высадки в мировых координатах XZ, по порядку.
@export var drops: PackedVector2Array = PackedVector2Array()
## Подписи точек высадки (ключи локализации), параллельно drops.
@export var drop_names: PackedStringArray = PackedStringArray()
## Если задано — финальная точка берётся как точка подачи в этом районе,
## а не по координатам (порт race: финиш на реальной дороге у вокзала).
@export var final_drop_from_district: StringName = &""
