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


## Индексы кликабельны из UI без границ — здесь единственное место, где они
## клампятся к реальному размеру каталога.
func color_at(i: int) -> Color:
	return colors[clampi(i, 0, colors.size() - 1)] if colors.size() > 0 else Color.WHITE


func rim_style_at(i: int) -> StringName:
	return StringName(rim_styles[clampi(i, 0, rim_styles.size() - 1)]) if rim_styles.size() > 0 else &"disc"


func rim_color_at(i: int) -> Color:
	return rim_colors[clampi(i, 0, rim_colors.size() - 1)] if rim_colors.size() > 0 else Color.WHITE


func body_kit_at(i: int) -> StringName:
	return StringName(body_kit_ids[clampi(i, 0, body_kit_ids.size() - 1)]) if body_kit_ids.size() > 0 else &"stock"


func decal_at(i: int) -> StringName:
	return StringName(decal_ids[clampi(i, 0, decal_ids.size() - 1)]) if decal_ids.size() > 0 else &"none"
