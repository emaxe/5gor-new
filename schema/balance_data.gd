class_name BalanceData
extends Resource
## Весь CFG (config.js:97) одним ресурсом. Read-only во время игры.

@export_group("Мир")
## Размер квартала, м.
@export var cell: float = 64.0
## Ширина дороги (4 полосы), м.
@export var road_width: float = 12.0
## Половина дороги, м.
@export var road_half: float = 6.0
## Ширина тротуара, м.
@export var sidewalk: float = 4.0
## Дороги от -grid_n*cell до +grid_n*cell.
@export var grid_n: int = 4
## Выступ дорог за сетку, м.
@export var grid_ext: float = 36.0
## Половина бокса shadow-камеры солнца, м.
@export var shadow_half: float = 90.0
## Сид генерации города. В оригинале 20260805, но там сидирована лишь часть.
@export var world_seed: int = 20260805

@export_group("Экономика")
@export var start_money: int = 800
@export var start_fuel: float = 70.0
## Рубли за 1 единицу топлива.
@export var fuel_price: float = 0.9
@export var base_fare: float = 120.0
## Рубли за 1 метр пути.
@export var fare_per_unit: float = 1.35
## До +35% за быстрое выполнение.
@export var time_bonus_max: float = 0.35
@export var tips_max: float = 90.0
## Ночной тариф ×2.
@export var night_mult: float = 2.0
## Бонус за высокий рейтинг (>= 60).
@export var high_rating_bonus: float = 1.15
@export var high_rating_threshold: int = 60
## Рубли за 1% урона.
@export var repair_cost_per_damage: float = 22.0
@export var wash_cost: int = 60
@export var tow_cost: int = 400
## Процент урона, который чинит эвакуатор.
@export var tow_repair: float = 35.0
@export var tow_fuel: float = 15.0
## Дистанция до колонки для заправки, м.
@export var refuel_dist: float = 8.0
## Ниже этой доли бака GPS ведёт к заправке.
@export var low_fuel_ratio: float = 0.25
## Гистерезис, чтобы маршрут не дёргался на пороге.
@export var low_fuel_hysteresis: float = 0.05
## Штраф за наезд на пешехода.
@export var hit_ped_fine: int = 300

@export_group("Рейтинг")
@export var rating_loss_hit_ped: int = 15
@export var rating_loss_fail_order: int = 5
@export var rating_loss_vip_leave: int = 8
@export var vip_leave_penalty: int = 100
@export var vip_leave_impact: float = 12.0

@export_group("Смена")
@export var shift_start_hour: float = 9.0
## Длина игровых суток в реальных секундах.
@export var day_length_sec: float = 720.0
@export var night_start_hour: float = 22.0
@export var night_end_hour: float = 6.0
## Множитель темпа смены из настроек: 0.5 / 1.0 / 2.0.
@export var shift_speed: float = 1.0
## Автозавершение смены при возврате к shift_start_hour следующего дня.
## Улучшение: в оригинале смена не заканчивалась никогда (час не брался по mod 24).
@export var auto_end_shift: bool = true

@export_group("Трафик и мир")
@export var traffic_count: int = 40
@export var ped_count: int = 120
@export var max_open_orders: int = 4
@export var order_expire_sec: float = 110.0
@export var order_spawn_every_sec: float = 9.0
## Ночью заказы реже.
@export var order_spawn_night_mult: float = 1.6
## Ночью трафика меньше.
@export var traffic_night_mult: float = 0.55
## Шанс, что вместо обычного заказа появится сюжетная миссия.
@export var mission_chance: float = 0.3

@export_group("Подсистемы")
@export var wanted: WantedConfig
@export var ped: PedConfig
@export var style: StyleConfig
@export var skid: SkidConfig
