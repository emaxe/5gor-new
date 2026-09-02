class_name WantedConfig
extends Resource
## Уровень розыска. Порт CFG.WANTED (config.js:151) + police.js.

@export var max_level: int = 5
## Секунд на спад одного уровня без новых нарушений.
@export var decay_time: float = 25.0
## L2 => ×1.5, L5 => ×3.0 исходного штрафа.
@export var fine_mult_per_level: float = 0.5
@export var rating_mult_per_level: float = 0.5
## Базовый радиус детекции патрулём, м.
@export var detect_radius: float = 60.0
## +м к радиусу за каждый уровень выше 1.
@export var detect_radius_bonus: float = 15.0
## С этого уровня ближайший патруль переходит в преследование.
## В оригинале объявлено, но не реализовано — в порте реализуем.
@export var chase_level: int = 4
## На этом уровне второй патруль выставляется на перехват впереди по маршруту.
@export var intercept_level: int = 5
@export var escape_reward_per_level: int = 150
@export var escape_rating_bonus: int = 2

@export_group("Нарушения")
## Порог превышения скорости, м/с (~108 км/ч).
@export var speed_threshold: float = 30.0
@export var fine_speeding: int = 300
@export var fine_red_light: int = 500
@export var fine_hit_ped: int = 800
@export var fine_ped_punch: int = 500
@export var rating_speeding: int = 3
@export var rating_red_light: int = 5
@export var rating_hit_ped: int = 10
@export var rating_ped_punch: int = 5
@export var cooldown_speeding: float = 8.0
@export var cooldown_red_light: float = 10.0
@export var cooldown_hit_ped: float = 12.0
@export var cooldown_ped_punch: float = 15.0


## Множитель штрафа на уровне level (police.js).
func fine_mult(level: int) -> float:
	return 1.0 + maxf(0.0, level - 1) * fine_mult_per_level


func effective_detect_radius(level: int) -> float:
	return detect_radius + maxf(0.0, level - 1) * detect_radius_bonus
