class_name PaletteData
extends Resource
## Палитра фасадов района. Порт PALETTES (config.js:275).

@export var id: StringName = &""
@export var facades: PackedColorArray = PackedColorArray()

## Цвет крыши = цвет стены × 0.62 (utils.js:107).
const ROOF_FACTOR := 0.62


func roof_color(facade: Color) -> Color:
	return Color(facade.r * ROOF_FACTOR, facade.g * ROOF_FACTOR, facade.b * ROOF_FACTOR)
