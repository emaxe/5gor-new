extends Node
## Audio — шины, пул пространственных источников, бюджет голосов, радио.
## Заглушка этапа 0: реальная реализация приходит на этапе 8.

## Порт AU_BUDGET (audiocore.js:6).
const BUDGET := {
	&"total": 30, &"horn": 3, &"crash": 2, &"ped": 3,
	&"voice": 3, &"click": 4, &"siren": 2,
}
## Порт AU_COOLDOWN (audiocore.js:7), мс.
const COOLDOWN := {
	&"horn": 140, &"crash": 80, &"ped_hit": 120,
	&"thud": 90, &"click": 40, &"step": 60,
}


func _ready() -> void:
	pass
