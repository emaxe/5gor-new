class_name PedConfig
extends Resource
## Пешеходы и пеший режим игрока. Порт config.js:162-187.

@export_group("ИИ и зоны детализации")
## ≤ этой дистанции — полный ИИ (маршрут, ПДД, обход), м.
@export var active_radius: float = 110.0
## Между active и near — простое движение + обход статики, м.
@export var near_radius: float = 150.0
## Дальше — телепорт-респавн, м.
@export var respawn_radius: float = 210.0
## Ближний LOD с полноценной анимацией и пузырями, м.
@export var detail_radius: float = 45.0
## Доля нарушителей ПДД.
@export var violator_chance: float = 0.08
## Ночью доля нарушителей ×, с потолком.
@export var violator_night_mult: float = 1.4
@export var violator_night_cap: float = 0.35
## Пауза после прибытия в точку, сек.
@export var idle_time_min: float = 5.0
@export var idle_time_max: float = 15.0
## Максимум полных пересчётов маршрута за тик.
@export var routes_per_tick: int = 2

@export_group("Стоимости рёбер графа тротуаров")
@export var edge_cost_walk: float = 0.5
@export var edge_cost_turn: float = 1.5
@export var edge_cost_cross: float = 1.0
@export var edge_cost_jwalk: float = 3.0

@export_group("Реакции на игрока")
## Дистанция, с которой пешеход начинает ругаться, м.
@export var anger_dist: float = 3.2
@export var anger_duration: float = 4.0
## Дистанция ответного пинка по машине, м.
@export var kick_dist: float = 2.4
@export var kick_duration: float = 0.6
@export var kick_cooldown: float = 6.0
## Дистанция, с которой животное убегает, м.
@export var animal_flee_dist: float = 4.5
## Болтовня: интервал между репликами, сек.
@export var chatter_min: float = 16.0
@export var chatter_max: float = 36.0
## Дистанция слышимости реплик, м.
@export var chatter_dist: float = 45.0
## Полураствор поля зрения игрока для показа облачка, рад.
@export var view_cone: float = 1.309
@export var view_dist: float = 60.0

@export_group("Пеший режим игрока")
@export var walk_speed: float = 3.1
@export var run_speed: float = 5.8
## Максимальная дистанция посадки в авто, м.
@export var car_enter_dist: float = 3.0
## Максимальная скорость авто для разрешения выхода, м/с.
@export var car_exit_max_speed: float = 1.5
@export var jump_speed: float = 6.5
@export var gravity: float = 20.0
@export var jump_cooldown: float = 0.25
@export var collide_radius: float = 0.35
## Скорость доворота корпуса, рад/с.
@export var turn_rate: float = 14.0

@export_group("Драка")
@export var punch_radius: float = 2.0
## Половина конуса поражения, рад (60°).
@export var punch_arc: float = 1.0472
@export var punch_cooldown: float = 0.8
@export var punch_knock_speed: float = 5.0
@export var punch_panic_radius: float = 8.0
@export var punch_fine: int = 150
@export var punch_rating_loss: int = 5
@export var player_max_hp: int = 3
@export var player_stun_duration: float = 0.6
@export var player_down_duration: float = 2.0
