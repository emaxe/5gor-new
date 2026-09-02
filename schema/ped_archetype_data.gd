class_name PedArchetypeData
extends Resource
## Архетип пешехода. Порт таблиц из peds.js и buildPedMesh (utils.js:526).

@export var id: StringName = &""
## Животное игнорирует светофоры и убегает от машины иначе, чем человек.
@export var is_animal: bool = false

@export_group("Движение")
@export var speed_min: float = 1.8
@export var speed_max: float = 2.7
## Вес в пуле спавна.
@export var weight: float = 1.0

@export_group("Внешность")
@export var scale_y_min: float = 0.92
@export var scale_y_max: float = 1.08
@export var scale_xz_min: float = 0.92
@export var scale_xz_max: float = 1.08
@export var cloth_colors: PackedColorArray = PackedColorArray()
@export var pants_colors: PackedColorArray = PackedColorArray()
@export var accessories: PackedStringArray = PackedStringArray()

@export_group("Реплики")
@export var quotes_idle: QuoteBank
@export var quotes_curse: QuoteBank
@export var quotes_panic: QuoteBank
@export var quotes_flee: QuoteBank
@export var quotes_retaliate: QuoteBank
## Шанс ответить ударом, а не убежать.
@export var retaliate_chance: float = 0.3
