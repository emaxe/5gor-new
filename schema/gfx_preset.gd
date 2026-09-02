class_name GfxPreset
extends Resource
## Пресет графики. Порт CFG_GFX_PRESETS (config.js:254).
## pixelRatio/pixelBudget оригинала переезжают на Viewport.scaling_3d_scale
## с тем же автоподбором sqrt(budget / (w*h)).

@export var id: StringName = &"medium"
@export var display_name: String = ""

@export_group("Тени")
## off | low | high
@export var shadows: StringName = &"low"
@export var shadow_atlas: int = 2048
@export var shadow_splits: int = 2
@export var shadow_max_distance: float = 80.0
## Тени на пешеходах и машинах трафика (дорого — ~600 draw calls).
@export var shadow_actors: bool = false

@export_group("Разрешение")
@export var scale_3d: float = 1.0
## Потолок пикселей буфера: scale урезается, чтобы уложиться.
@export var pixel_budget: int = 2_400_000
@export var msaa: int = 0

@export_group("Мир")
@export var draw_distance: float = 1000.0
@export var traffic_density: float = 1.0
@export var ped_density: float = 1.0
@export var rain: bool = true

@export_group("Эффекты")
@export var glow: bool = true
@export var ssao: bool = false
@export var volumetric_fog: bool = false
## Обводка inverted hull на «героях».
@export var hero_outline: bool = true
## Пул реальных OmniLight3D для ночных фонарей.
@export var light_pool_size: int = 24


## Итоговый scale_3d с учётом бюджета пикселей (порт _effectivePixelRatio).
func effective_scale(viewport_size: Vector2i) -> float:
	var px := float(viewport_size.x * viewport_size.y)
	if px <= 0.0:
		return scale_3d
	var cap := sqrt(float(pixel_budget) / px)
	return clampf(minf(scale_3d, cap), 0.5, 2.0)
