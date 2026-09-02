class_name CarRuntime
extends RefCounted
## Изменяемое состояние машины игрока: топливо, урон, грязь, стиль езды,
## купленные апгрейды и тюнинг.
##
## Отдельно от CarData: тот — общий read-only ресурс, один на все машины
## этого типа. Всё, что меняется в игре, живёт здесь и сериализуется в слот.

signal fuel_empty
signal engine_stalled
signal damaged(impact: float, victim: StringName)

## Порог удара, с которого начисляется урон (player.js:_resolve).
const DAMAGE_IMPACT := 6.0
## Коэффициент перевода удара в урон.
const DAMAGE_FACTOR := 0.018
## Удар и уровень урона, после которых мотор глохнет.
const STALL_IMPACT := 20.0
const STALL_DAMAGE := 60.0
const STALL_DURATION := 2.5
## Штраф стилю за столкновение и за удар о машину.
const STYLE_LOSS_CRASH := 0.06
const STYLE_LOSS_CAR := 0.12

var car_id: StringName = &"taxi"
var upgrade_levels: Dictionary[StringName, int] = {}
var tuning := {
	&"color": 0, &"rims": 0, &"spoiler": false, &"body_kit": 0, &"decal": 0,
}
var stats: CarStats

var fuel := 70.0
## Повреждения кузова 0..100.
var damage := 0.0
## Загрязнение 0..1: грязная машина уменьшает чаевые.
var dirt := 0.0
## Оценка манеры езды пассажиром 0..1.
var style := 1.0
var passenger_count := 0

var _style_timer := 0.0
var _stall_timer := 0.0


func setup(data: CarData, upgrades: UpgradeCatalog) -> void:
	car_id = data.id
	stats = CarStats.from_car(data, upgrade_levels, upgrades)
	fuel = minf(fuel, stats.tank)


func engine_dead() -> bool:
	return fuel <= 0.0 or _stall_timer > 0.0


func fuel_ratio() -> float:
	return fuel / maxf(stats.tank, 1.0) if stats != null else 0.0


func tick(motion: CarPhysics.Motion, on_road: bool, delta: float) -> void:
	if _stall_timer > 0.0:
		_stall_timer -= delta

	if not engine_dead():
		var before := fuel
		fuel = maxf(0.0, fuel - CarPhysics.fuel_burn(motion, stats, delta))
		if before > 0.0 and fuel <= 0.0:
			fuel_empty.emit()

	dirt = minf(1.0, dirt + CarPhysics.dirt_gain(motion, delta))

	# Стиль падает только когда в машине есть пассажир: пустое такси
	# оценивать некому.
	if passenger_count <= 0:
		return
	_style_timer += delta
	if _style_timer > 1.0:
		_style_timer = 0.0
		style = clampf(style - CarPhysics.jerk(motion) * 0.03, 0.0, 1.0)
	if not on_road:
		style = clampf(style - delta * 0.05, 0.0, 1.0)


## Удар. Возвращает нанесённый урон.
func apply_impact(impact: float, victim: StringName) -> float:
	if impact <= DAMAGE_IMPACT:
		return 0.0
	var dmg := impact * impact * DAMAGE_FACTOR / maxf(stats.armor, 0.1)
	damage = minf(100.0, damage + dmg)
	style = clampf(style - (STYLE_LOSS_CAR if victim == &"car" else STYLE_LOSS_CRASH),
		0.0, 1.0)
	if impact > STALL_IMPACT and damage > STALL_DAMAGE:
		_stall_timer = STALL_DURATION
		engine_stalled.emit()
	damaged.emit(impact, victim)
	return dmg


func repair() -> void:
	damage = 0.0


func wash() -> void:
	dirt = 0.0


func refuel(amount: float) -> void:
	fuel = minf(stats.tank, fuel + amount)
