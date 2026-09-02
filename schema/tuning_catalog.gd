class_name TuningCatalog
extends Resource
## Каталог тюнинга. Порт TUNING (config.js:348).

@export var color_names: PackedStringArray = PackedStringArray()
@export var colors: PackedColorArray = PackedColorArray()

@export var rim_names: PackedStringArray = PackedStringArray()
@export var rim_colors: PackedColorArray = PackedColorArray()
## Геометрия диска, параллельно rim_names: disc | spoke | chrome.
@export var rim_styles: PackedStringArray = PackedStringArray()

@export var body_kit_names: PackedStringArray = PackedStringArray()
## stock | sport
@export var body_kit_ids: PackedStringArray = PackedStringArray()

@export var decal_names: PackedStringArray = PackedStringArray()
## none | stripe | checker | racing
@export var decal_ids: PackedStringArray = PackedStringArray()


func index() -> void:
	pass
