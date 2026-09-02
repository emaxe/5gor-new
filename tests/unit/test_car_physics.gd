extends GdUnitTestSuite
## Физика машины — сердце игры. Эталон снят прогоном формул player.js:217-299
## в Node.js (tools/dump/car_ref.json): разгон, тормозной путь, разворот и
## пиковая пробуксовка для всех семи машин.
##
## Расхождение здесь не падает при запуске — оно тихо меняет ощущение
## управления и ломает калибровку дрифта, near-miss и идеальной остановки.

const REF_PATH := "res://tools/dump/car_ref.json"
const DT := 1.0 / 60.0
## Допуск: сравнивается float64 (JS) против float32-накопления в Godot
## на нескольких сотнях тиков.
const EPS_TIME := 0.02
const EPS_DIST := 0.15

var _ref: Dictionary


func before() -> void:
	var f := FileAccess.open(REF_PATH, FileAccess.READ)
	_ref = JSON.parse_string(f.get_as_text()) if f != null else {}


func _stats(id: StringName) -> CarStats:
	return CarStats.from_car(Db.cars.get_car(id), {}, Db.upgrades)


func _surface() -> CarPhysics.Surface:
	return CarPhysics.Surface.new()


func _axes(throttle: float, brake: float, steer: float,
		handbrake: bool = false) -> Inp.DriveAxes:
	var a := Inp.DriveAxes.new()
	a.throttle = throttle
	a.brake = brake
	a.steer = steer
	a.handbrake = handbrake
	return a


func test_reference_present() -> void:
	assert_bool(_ref.is_empty())\
		.override_failure_message("нет эталона %s" % REF_PATH)\
		.is_false()


func test_acceleration_matches_original() -> void:
	for id: String in _ref:
		var stats := _stats(StringName(id))
		var m := CarPhysics.Motion.new()
		var axes := _axes(1.0, 0.0, 0.0)
		var surface := _surface()
		var t := 0.0
		var t100 := -1.0
		for i in 3600:
			CarPhysics.step(m, axes, surface, stats, false, DT)
			t += DT
			if t100 < 0.0 and m.forward_speed >= 27.7778:
				t100 = t
			if m.forward_speed >= stats.max_speed - 0.01:
				break
		var r: Dictionary = _ref[id]
		assert_float(t100)\
			.override_failure_message("%s: 0-100 км/ч %.3f вместо %.3f"
				% [id, t100, r["timeTo100"]])\
			.is_equal_approx(float(r["timeTo100"]), EPS_TIME)
		assert_float(t)\
			.override_failure_message("%s: разгон до максимума %.3f вместо %.3f"
				% [id, t, r["timeToTop"]])\
			.is_equal_approx(float(r["timeToTop"]), EPS_TIME)


func test_braking_distance_matches_original() -> void:
	for id: String in _ref:
		var stats := _stats(StringName(id))
		var m := CarPhysics.Motion.new()
		m.velocity = Vector3(0.0, 0.0, 27.7778)
		var axes := _axes(0.0, 1.0, 0.0)
		var surface := _surface()
		var t := 0.0
		for i in 1800:
			CarPhysics.step(m, axes, surface, stats, false, DT)
			t += DT
			if m.forward_speed <= 0.05:
				break
		var r: Dictionary = _ref[id]
		assert_float(m.position.z)\
			.override_failure_message("%s: тормозной путь %.2f вместо %.2f м"
				% [id, m.position.z, r["brakeDist"]])\
			.is_equal_approx(float(r["brakeDist"]), EPS_DIST)
		assert_float(t).is_equal_approx(float(r["brakeTime"]), EPS_TIME)


func test_u_turn_matches_original() -> void:
	for id: String in _ref:
		var stats := _stats(StringName(id))
		var m := CarPhysics.Motion.new()
		m.velocity = Vector3(0.0, 0.0, 15.0)
		var axes := _axes(0.35, 0.0, 1.0)
		var surface := _surface()
		var t := 0.0
		for i in 1800:
			CarPhysics.step(m, axes, surface, stats, false, DT)
			t += DT
			if absf(m.heading) >= PI:
				break
		var r: Dictionary = _ref[id]
		assert_float(absf(m.position.x))\
			.override_failure_message("%s: ширина разворота %.2f вместо %.2f м"
				% [id, absf(m.position.x), r["uturnWidth"]])\
			.is_equal_approx(float(r["uturnWidth"]), EPS_DIST)
		assert_float(t).is_equal_approx(float(r["uturnTime"]), EPS_TIME)


func test_handbrake_slip_matches_original() -> void:
	for id: String in _ref:
		var stats := _stats(StringName(id))
		var m := CarPhysics.Motion.new()
		m.velocity = Vector3(0.0, 0.0, 20.0)
		var axes := _axes(0.5, 0.0, 1.0, true)
		var surface := _surface()
		var peak := 0.0
		for i in 240:
			CarPhysics.step(m, axes, surface, stats, false, DT)
			peak = maxf(peak, m.slip)
		assert_float(peak)\
			.override_failure_message("%s: пиковая пробуксовка %.3f вместо %.3f"
				% [id, peak, _ref[id]["maxSlip"]])\
			.is_equal_approx(float(_ref[id]["maxSlip"]), 0.05)


# --- Поведенческие инварианты ------------------------------------------------

func test_reverse_is_capped() -> void:
	var stats := _stats(&"taxi")
	var m := CarPhysics.Motion.new()
	var axes := _axes(0.0, 1.0, 0.0)
	for i in 600:
		CarPhysics.step(m, axes, _surface(), stats, false, DT)
	assert_float(m.forward_speed).is_equal_approx(-CarPhysics.REVERSE_MAX, 0.01)


func test_offroad_reduces_grip() -> void:
	var stats := _stats(&"taxi")
	var on := CarPhysics.Motion.new()
	var off := CarPhysics.Motion.new()
	on.velocity = Vector3(0.0, 0.0, 20.0)
	off.velocity = Vector3(0.0, 0.0, 20.0)
	var axes := _axes(0.5, 0.0, 1.0)
	var s_on := _surface()
	var s_off := _surface()
	s_off.on_road = false
	for i in 120:
		CarPhysics.step(on, axes, s_on, stats, false, DT)
		CarPhysics.step(off, axes, s_off, stats, false, DT)
	# Вне дороги руль слушается хуже — машина поворачивает меньше.
	assert_float(absf(off.heading)).is_less(absf(on.heading))


func test_rain_increases_slip() -> void:
	var stats := _stats(&"taxi")
	var dry := CarPhysics.Motion.new()
	var wet := CarPhysics.Motion.new()
	dry.velocity = Vector3(0.0, 0.0, 22.0)
	wet.velocity = Vector3(0.0, 0.0, 22.0)
	var axes := _axes(0.6, 0.0, 1.0)
	var s_dry := _surface()
	var s_wet := _surface()
	s_wet.weather_grip = Db.weather.get_weather(&"rain").grip
	var dry_peak := 0.0
	var wet_peak := 0.0
	for i in 180:
		CarPhysics.step(dry, axes, s_dry, stats, false, DT)
		CarPhysics.step(wet, axes, s_wet, stats, false, DT)
		dry_peak = maxf(dry_peak, dry.slip)
		wet_peak = maxf(wet_peak, wet.slip)
	assert_float(wet_peak).is_greater(dry_peak)


func test_dead_engine_coasts_to_stop() -> void:
	var stats := _stats(&"taxi")
	var m := CarPhysics.Motion.new()
	m.velocity = Vector3(0.0, 0.0, 20.0)
	var axes := _axes(1.0, 0.0, 0.0)
	for i in 600:
		CarPhysics.step(m, axes, _surface(), stats, true, DT)
	assert_float(m.speed).is_less(0.2)


func test_upgrades_improve_stats() -> void:
	var base := CarStats.from_car(Db.cars.get_car(&"taxi"), {}, Db.upgrades)
	var tuned := CarStats.from_car(Db.cars.get_car(&"taxi"),
		{&"engine": 4, &"suspension": 4, &"brakes": 4, &"tank": 4, &"capacity": 3},
		Db.upgrades)
	# engine +3.2 max_speed и +1.6 accel за уровень (upgrades.js:41).
	assert_float(tuned.max_speed).is_equal_approx(base.max_speed + 12.8, 1e-4)
	assert_float(tuned.accel).is_equal_approx(base.accel + 6.4, 1e-4)
	assert_float(tuned.grip).is_equal_approx(base.grip + 0.2, 1e-4)
	assert_float(tuned.brake).is_equal_approx(base.brake + 20.0, 1e-4)
	assert_float(tuned.tank).is_equal_approx(base.tank + 200.0, 1e-4)
	assert_int(tuned.capacity).is_equal(base.capacity + 3)


func test_fully_upgraded_car_is_faster() -> void:
	var stats := CarStats.from_car(Db.cars.get_car(&"taxi"),
		{&"engine": 4}, Db.upgrades)
	var m := CarPhysics.Motion.new()
	var axes := _axes(1.0, 0.0, 0.0)
	for i in 600:
		CarPhysics.step(m, axes, _surface(), stats, false, DT)
	assert_float(m.forward_speed).is_greater(Db.cars.get_car(&"taxi").max_speed)
