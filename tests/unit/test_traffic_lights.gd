extends GdUnitTestSuite
## Светофоры — общий источник правды для машин и пешеходов. Инварианты:
## сигналы противоположных осей никогда не зелёные одновременно, пешеходный
## зелёный ровно дополняет красный для машин, «зелёная волна» существует.

var _field: CityField
var _lights: TrafficLightController


func before() -> void:
	_field = CityField.new(Db.balance)
	_lights = TrafficLightController.new(_field)


func test_cycle_matches_original() -> void:
	# Ось Z: 0-6 зелёный, 6-8 жёлтый, 8-16 красный (citygen.js:3034).
	# Проверяем на перекрёстке с нулевым сдвигом фазы (x = 0, индекс 4).
	var seq := {
		0.0: TrafficLightController.State.GREEN,
		5.9: TrafficLightController.State.GREEN,
		6.1: TrafficLightController.State.YELLOW,
		7.9: TrafficLightController.State.YELLOW,
		8.1: TrafficLightController.State.RED,
		15.9: TrafficLightController.State.RED,
	}
	for t: float in seq:
		_lights.time = t
		assert_int(int(_lights.car_state(4, TrafficLightController.Axis.Z_ROAD)))\
			.override_failure_message("ось Z в t=%.1f" % t)\
			.is_equal(int(seq[t]))


func test_cross_axis_cycle_matches_original() -> void:
	# Ось X: 0-8 красный, 8-14 зелёный, 14-16 жёлтый.
	var seq := {
		0.0: TrafficLightController.State.RED,
		7.9: TrafficLightController.State.RED,
		8.1: TrafficLightController.State.GREEN,
		13.9: TrafficLightController.State.GREEN,
		14.1: TrafficLightController.State.YELLOW,
	}
	for t: float in seq:
		_lights.time = t
		assert_int(int(_lights.car_state(4, TrafficLightController.Axis.X_ROAD)))\
			.override_failure_message("ось X в t=%.1f" % t)\
			.is_equal(int(seq[t]))


func test_axes_are_never_green_together() -> void:
	for i in 9:
		for step in 320:
			_lights.time = step * 0.05
			var z := _lights.is_open_for_cars(i, TrafficLightController.Axis.Z_ROAD)
			var x := _lights.is_open_for_cars(i, TrafficLightController.Axis.X_ROAD)
			assert_bool(z and x)\
				.override_failure_message(
					"обе оси зелёные на перекрёстке %d в t=%.2f" % [i, _lights.time])\
				.is_false()


func test_pedestrian_green_complements_car_red() -> void:
	var gate := PedGraph.gate_id(4, 4, PedGraph.CrossAxis.Z_ROAD)
	for step in 320:
		_lights.time = step * 0.05
		var open := _lights.is_crossing_open(gate)
		var cars := _lights.car_state(4, TrafficLightController.Axis.Z_ROAD)
		assert_bool(open)\
			.override_failure_message("пешеход и машины в t=%.2f" % _lights.time)\
			.is_equal(cars == TrafficLightController.State.RED)


func test_green_remaining_counts_down_to_zero() -> void:
	var gate := PedGraph.gate_id(4, 4, PedGraph.CrossAxis.Z_ROAD)
	# Машинам вдоль Z красный с 8 до 16 — пешеходу зелёный те же 8 секунд.
	_lights.time = 8.5
	assert_float(_lights.crossing_green_remaining(gate)).is_equal_approx(7.5, 1e-4)
	_lights.time = 15.9
	assert_float(_lights.crossing_green_remaining(gate)).is_equal_approx(0.1, 1e-4)
	_lights.time = 2.0
	assert_float(_lights.crossing_green_remaining(gate)).is_equal(0.0)


func test_time_until_green_is_bounded_by_cycle() -> void:
	for gate_axis in [PedGraph.CrossAxis.Z_ROAD, PedGraph.CrossAxis.X_ROAD]:
		var gate := PedGraph.gate_id(4, 4, gate_axis)
		for step in 160:
			_lights.time = step * 0.1
			var wait := _lights.time_until_crossing_green(gate)
			assert_float(wait).is_between(0.0, TrafficLightController.CYCLE)
			if wait > 0.0:
				assert_bool(_lights.is_crossing_open(gate)).is_false()


func test_pedestrian_always_gets_green_within_a_cycle() -> void:
	# Ожидание не должно образовывать дедлок ни на одном перекрёстке.
	for i in 9:
		for j in 9:
			for gate_axis in [PedGraph.CrossAxis.Z_ROAD, PedGraph.CrossAxis.X_ROAD]:
				var gate := PedGraph.gate_id(i, j, gate_axis)
				_lights.time = 3.7
				assert_float(_lights.time_until_crossing_green(gate))\
					.is_less_equal(TrafficLightController.CYCLE)


func test_green_wave_shifts_phase_along_x() -> void:
	# Соседние по X перекрёстки обязаны иметь разную фазу, иначе весь город
	# переключается синхронно и «зелёной волны» не существует.
	_lights.time = 0.0
	# Разница фаз циклическая: сравниваем по кратчайшей дуге цикла.
	var d := _cycle_delta(_lights.local_time(4), _lights.local_time(5))
	# Сдвиг ровно 1.6 с на клетку (citygen.js:2750).
	assert_float(d).is_equal_approx(1.6, 1e-4)
	assert_float(_cycle_delta(_lights.local_time(0), _lights.local_time(1)))\
		.is_equal_approx(1.6, 1e-4)


func _cycle_delta(a: float, b: float) -> float:
	var d := absf(b - a)
	return minf(d, TrafficLightController.CYCLE - d)


func test_wave_lets_a_convoy_pass_several_intersections() -> void:
	# Машина, идущая на восток со скоростью cell / 1.6 = 40 м/с, должна
	# видеть зелёный на серии перекрёстков.
	var speed := _field.cell / TrafficLightController.WAVE_PER_CELL
	var green_count := 0
	for i in range(3, 8):
		var travel := (_field.road_axes[i] - _field.road_axes[3]) / speed
		_lights.time = fposmod(9.0 + travel, TrafficLightController.CYCLE)
		if _lights.is_open_for_cars(i, TrafficLightController.Axis.X_ROAD):
			green_count += 1
	assert_int(green_count)\
		.override_failure_message("волна не работает: зелёных %d из 5" % green_count)\
		.is_equal(5)


func test_lamp_index_maps_state_to_section() -> void:
	_lights.time = 0.0
	assert_int(_lights.lamp_index(4, TrafficLightController.Axis.Z_ROAD)).is_equal(2)
	_lights.time = 7.0
	assert_int(_lights.lamp_index(4, TrafficLightController.Axis.Z_ROAD)).is_equal(1)
	_lights.time = 12.0
	assert_int(_lights.lamp_index(4, TrafficLightController.Axis.Z_ROAD)).is_equal(0)


func test_advance_wraps_cycle() -> void:
	_lights.time = 15.5
	_lights.advance(1.0)
	assert_float(_lights.time).is_equal_approx(0.5, 1e-5)
