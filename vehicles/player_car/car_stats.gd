class_name CarStats
extends RefCounted
## Итоговые характеристики машины: база из CarData плюс уровни апгрейдов.
## Порт UpgradeSystem.stats() (upgrades.js:37-50).
##
## Отдельный RefCounted, а не поля в CarData: CarData — общий read-only
## ресурс, а статы у каждой машины свои.

var car_id: StringName = &"taxi"
var max_speed := 34.0
var accel := 13.0
var brake := 26.0
var grip := 1.0
var armor := 1.0
var tank := 100.0
var capacity := 1
var steer := 2.1
var is_taxi := false
var shape: CarShapeData


static func from_car(data: CarData, levels: Dictionary,
		upgrades: UpgradeCatalog) -> CarStats:
	var s := CarStats.new()
	s.car_id = data.id
	s.max_speed = data.max_speed
	s.accel = data.accel
	s.brake = data.brake
	s.grip = data.grip
	s.armor = data.armor
	s.tank = data.tank
	s.capacity = data.capacity
	s.steer = data.steer
	s.is_taxi = data.is_taxi
	s.shape = data.shape
	if upgrades == null:
		return s
	for u in upgrades.items:
		var lvl: int = levels.get(u.id, 0)
		if lvl <= 0:
			continue
		s.max_speed += u.max_speed_per_level * lvl
		s.accel += u.accel_per_level * lvl
		s.brake += u.brake_per_level * lvl
		s.grip += u.grip_per_level * lvl
		s.steer += u.steer_per_level * lvl
		s.armor += u.armor_per_level * lvl
		s.tank += u.tank_per_level * lvl
		s.capacity += u.capacity_per_level * lvl
	return s
