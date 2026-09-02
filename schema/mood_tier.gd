class_name MoodTier
extends Resource
## Ступень настроения пассажира. Порт MOOD_TIERS (config.js:239).
## Чистое представление: на экономику не влияет, отображает player.style.

@export var min_style: float = 0.0
@export var icon: StringName = &""
@export var display_name: String = ""
@export var color: Color = Color.WHITE
