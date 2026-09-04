extends Node
## Bus — глобальная шина сигналов. ТОЛЬКО объявления: ни одного поля состояния,
## ни одной строки логики.
##
## Правило проекта: здесь живут только события жизненного цикла, которые
## пересекают границы систем. Всё внутрисистемное (пешеход сказал реплику,
## светофор переключился, колесо провернулось) — локальные сигналы на нодах.
## Лимит — 14 сигналов; агрегированные (kind + payload) вместо россыпи плоских.

## Деньги изменились. delta нужен для cash-pop VFX.
signal money_changed(value: int, delta: int)

## Рейтинг изменился (0..100).
signal rating_changed(value: float)

## Уровень розыска изменился (0..5).
signal wanted_changed(level: int)

## Игровое время. Эмитится раз в игровую минуту, НЕ покадрово.
signal time_changed(hour: float, day: int, is_night: bool)

## Погода сменилась: &"clear" | &"rain" | &"fog".
signal weather_changed(id: StringName)

## Событие заказа.
## kind: &"spawned" | &"accepted" | &"completed" | &"failed" | &"expired" | &"leg"
signal order_event(kind: StringName, order_id: int, data: Dictionary)

## Столкновение машины игрока. victim: &"static" | &"car" | &"ped".
signal player_crashed(impact: float, victim: StringName)

## Игрок сел в машину / вышел из неё.
signal vehicle_mode_changed(in_car: bool)

## Событие «стиля» (juice).
## kind: &"drift" | &"perfect_stop" | &"near_miss" | &"near_miss_streak" | &"combo"
signal juice_event(kind: StringName, data: Dictionary)

## Достижение открыто.
signal achievement_unlocked(id: StringName)

## Сообщение игроку.
## kind: &"toast" | &"dialogue" | &"banner" | &"interact"
signal notify(kind: StringName, text: String, data: Dictionary)

## Смена состояния игры.
## &"menu" | &"loading" | &"driving" | &"walking" | &"paused" | &"garage" | &"map" | &"shift_end"
signal game_state_changed(state: StringName)

## Мир сгенерирован и готов к игре.
signal world_ready(world_seed: int)

## Настройки применены. section: &"audio" | &"gfx" | &"input" | &"driver" | &"hud"
signal settings_applied(section: StringName)
