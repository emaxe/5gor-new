class_name StyleConfig
extends Resource
## Механики «стиля» поверх физики: дрифт, идеальная остановка, near-miss, комбо.
## Порт config.js:196-229. В оригинале размазано по четырём методам game.js —
## здесь собрано в один конфиг и одну подсистему StyleService.

@export_group("Дрифт")
@export var drift_min_slip: float = 0.5
@export var drift_min_speed: float = 7.0
@export var drift_min_duration: float = 0.8
@export var drift_base_reward: int = 40
@export var drift_reward_per_sec: float = 50.0
@export var drift_max_reward: int = 200
@export var drift_style_bonus: float = 0.05
## Кулдаун реплики пассажира на занос, сек.
@export var drift_reaction_cooldown: float = 8.0

@export_group("Идеальная остановка")
@export var perfect_stop_min_speed: float = 7.0
## Максимальное пиковое замедление для «плавности», м/с².
@export var perfect_stop_max_decel: float = 9.5
@export var perfect_stop_reward: int = 50
@export var perfect_stop_style_bonus: float = 0.08

@export_group("Опасное сближение")
@export var near_miss_min_speed: float = 10.0
## Максимальный боковой зазор до кузова NPC-авто, м.
@export var near_miss_car_margin: float = 1.2
## Максимальный зазор до пешехода, м.
@export var near_miss_ped_margin: float = 1.0
## Дистанция удаления для сброса одноразового флага NPC, м.
@export var near_miss_reset_dist: float = 8.0
@export var near_miss_reward: int = 35
@export var near_miss_style_bonus: float = 0.04
## Окно удержания серии, сек.
@export var near_miss_streak_window: float = 8.0
## Пороги серии (по возрастанию) и множители награды.
@export var near_miss_streak_counts: PackedInt32Array = PackedInt32Array([2, 5, 10])
@export var near_miss_streak_mults: PackedFloat32Array = PackedFloat32Array([2.0, 5.0, 10.0])

@export_group("Комбо заказов")
## Пороги серии для milestone-фидбека.
@export var combo_streak_counts: PackedInt32Array = PackedInt32Array([3, 5, 10])
## Прибавка к множителю оплаты за каждый заказ серии.
@export var combo_step: float = 0.05
@export var combo_max_steps: int = 10


## Множитель серии сближений для текущей длины.
func near_miss_mult(streak: int) -> float:
	var m := 1.0
	for i in near_miss_streak_counts.size():
		if streak >= near_miss_streak_counts[i]:
			m = near_miss_streak_mults[i]
	return m


## Уровень серии (0 — нет).
func near_miss_level(streak: int) -> int:
	var lvl := 0
	for i in near_miss_streak_counts.size():
		if streak >= near_miss_streak_counts[i]:
			lvl = i + 1
	return lvl


## Множитель оплаты за комбо заказов (game.js:520).
func combo_mult(streak: int) -> float:
	return 1.0 + mini(streak, combo_max_steps) * combo_step
