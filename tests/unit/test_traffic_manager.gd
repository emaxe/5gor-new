extends GdUnitTestSuite
## Трафик — 10 правил ИИ traffic.js поверх SoA-массивов. Тесты сверяют то,
## что не видно глазом: пул со спецтранспортом, распределение поворотов
## 58/22/20, торможение перед красным для законопослушных, проезд на
## красный только для агрессивных на пустом перекрёстке, границы карты
## и бюджет апдейта при тройной плотности.

const DT := 1.0 / 60.0


func _new_manager(catalog: TrafficCatalog, traffic_count: int, seed_value: int,
		field: CityField, lights: TrafficLightController) -> TrafficManager:
	var mgr := TrafficManager.new()
	mgr.setup(catalog, field, lights, SeededRng.new(seed_value), traffic_count)
	return mgr


func _default_field() -> CityField:
	return CityField.new(Db.balance)


## Мини-каталог с одним типом — для сценариев, где важна детерминированная
## агрессивность/шанс проезда на красный, а не реальные 20 типов трафика.
func _single_type_catalog(aggressive_ratio: float, red_chance: float) -> TrafficCatalog:
	var t := TrafficTypeData.new()
	t.id = &"sedan"
	t.silhouette = &"sedan"
	t.radius = 2.0
	t.length = 4.4
	t.width = 1.9
	t.weight = 1.0
	t.colors = PackedColorArray([Color.WHITE])
	var cat := TrafficCatalog.new()
	cat.items = [t]
	cat.aggressive_ratio = aggressive_ratio
	cat.red_light_run_chance = red_chance
	cat.index()
	return cat


func test_setup_spawns_requested_count_with_guaranteed_police() -> void:
	var field := _default_field()
	var lights := TrafficLightController.new(field)
	var mgr := _new_manager(Db.traffic, Db.balance.traffic_count, 42, field, lights)
	mgr.place_all_near(0.0, 0.0)

	assert_int(mgr.count).is_equal(Db.balance.traffic_count)
	var has_police := false
	for i in mgr.count:
		if mgr.type_of(i).id == &"police":
			has_police = true
			break
	assert_bool(has_police)\
		.override_failure_message("в пуле трафика нет ни одной патрульной машины")\
		.is_true()


## Кубическая Безье выбирает направление с той же вероятностью, что и
## оригинал (traffic.js:590-592): 58% прямо, 22% направо, 20% налево.
func test_turn_choice_matches_original_split() -> void:
	var rng := SeededRng.new(2026)
	var straight := 0
	var right := 0
	var left := 0
	var trials := 8000
	for _k in trials:
		var roll := rng.next()
		if roll < TrafficManager.CHOOSE_STRAIGHT_P:
			straight += 1
		elif roll < TrafficManager.CHOOSE_RIGHT_P:
			right += 1
		else:
			left += 1
	assert_float(float(straight) / trials)\
		.override_failure_message("прямо: %.3f вместо 0.58" % (float(straight) / trials))\
		.is_between(0.55, 0.61)
	assert_float(float(right) / trials)\
		.override_failure_message("направо: %.3f вместо 0.22" % (float(right) / trials))\
		.is_between(0.19, 0.25)
	assert_float(float(left) / trials)\
		.override_failure_message("налево: %.3f вместо 0.20" % (float(left) / trials))\
		.is_between(0.17, 0.23)


## Ставит одну машину на подъезде к перекрёстку (1,1) — обе координаты
## нечётные, значит регулируемый (PedGraph.is_signalized) — и выставляет
## на нём красный для оси Z.
func _place_approaching_red_z(mgr: TrafficManager, field: CityField,
		lights: TrafficLightController) -> void:
	const ISEC_INDEX := 1
	mgr.axis[0] = TrafficLightController.Axis.Z_ROAD
	mgr.coord[0] = field.road_axes[ISEC_INDEX]
	mgr.pos[0] = field.road_axes[ISEC_INDEX] - 25.0
	mgr.dir[0] = 1.0
	mgr.speed[0] = 10.0
	mgr.target[0] = 10.0
	mgr.turning[0] = 0
	mgr.turn_t[0] = 0.0
	mgr.run_red[0] = 0
	# Ось Z красная 8..16 в локальном времени перекрёстка (citygen.js:3034).
	lights.time = fposmod(9.8 - lights.phase_offset(ISEC_INDEX), TrafficLightController.CYCLE)


func test_non_aggressive_car_stops_at_red_light() -> void:
	var field := _default_field()
	var lights := TrafficLightController.new(field)
	var cat := _single_type_catalog(0.0, 0.3)
	var mgr := _new_manager(cat, 1, 5, field, lights)
	mgr.place_all_near(0.0, 0.0)
	_place_approaching_red_z(mgr, field, lights)

	var stop_line := field.road_axes[1] - TrafficManager.STOP_LINE
	# Игрок рядом (не респавнит машину), но вбок — не мешает через правило 9.
	var player_x := mgr.coord[0] + 10.0
	var player_z := mgr.pos[0]
	for _i in 300:
		mgr.update(DT, player_x, player_z, 1.0)

	assert_float(mgr.pos[0])\
		.override_failure_message("машина проехала на красный: pos=%.2f, стоп-линия=%.2f"
			% [mgr.pos[0], stop_line])\
		.is_less(stop_line)
	assert_float(mgr.speed_of(0))\
		.override_failure_message("машина не остановилась: скорость=%.2f" % mgr.speed_of(0))\
		.is_less(0.5)


func test_aggressive_car_runs_clear_red_light() -> void:
	var field := _default_field()
	var lights := TrafficLightController.new(field)
	# aggressive_ratio=1 и red_light_run_chance=1 — детерминированно проезжает,
	# перекрёсток пуст (единственная машина в пуле), значит проезд гарантирован.
	var cat := _single_type_catalog(1.0, 1.0)
	var mgr := _new_manager(cat, 1, 7, field, lights)
	mgr.place_all_near(0.0, 0.0)
	_place_approaching_red_z(mgr, field, lights)
	assert_int(mgr.aggressive[0])\
		.override_failure_message("машина должна быть агрессивной для этого сценария")\
		.is_equal(1)

	var player_x := mgr.coord[0] + 10.0
	var player_z := mgr.pos[0]
	for _i in 300:
		mgr.update(DT, player_x, player_z, 1.0)

	assert_float(mgr.pos[0])\
		.override_failure_message("агрессивная машина не проехала пустой перекрёсток: pos=%.2f"
			% mgr.pos[0])\
		.is_greater(field.road_axes[1] + 5.0)


func test_cars_stay_within_map_bounds_over_time() -> void:
	var field := _default_field()
	var lights := TrafficLightController.new(field)
	var mgr := _new_manager(Db.traffic, Db.balance.traffic_count, 11, field, lights)
	mgr.place_all_near(0.0, 0.0)

	for _step in 900:
		mgr.update(DT, 0.0, 0.0, 1.0)
		for c in mgr.count:
			assert_float(absf(mgr.pos[c]))\
				.override_failure_message("машина %d выехала за карту: pos=%.1f" % [c, mgr.pos[c]])\
				.is_less(270.0)


## Бакетизация по (axis, coord) обязана держать апдейт в бюджете даже при
## тройной плотности (архитектура: «выдержать рост плотности до ×3»).
func test_update_fits_frame_budget_at_triple_density() -> void:
	var field := _default_field()
	var lights := TrafficLightController.new(field)
	var triple := Db.balance.traffic_count * 3
	var mgr := _new_manager(Db.traffic, triple, 9, field, lights)
	mgr.place_all_near(0.0, 0.0)

	var t0 := Time.get_ticks_usec()
	for _i in 60:
		mgr.update(DT, 0.0, 0.0, 1.0)
	var us := Time.get_ticks_usec() - t0
	var per_tick_ms := (us / 1000.0) / 60.0
	# Порог — под headless-интерпретатор GDScript в debug-сборке (медленнее
	# экспортированного релиза в разы); цель теста — поймать O(n²)-регресс
	# бакетизации, а не мерить финальный кадровый бюджет.
	assert_float(per_tick_ms)\
		.override_failure_message("апдейт трафика (%d машин) занял %.3f мс/тик"
			% [triple, per_tick_ms])\
		.is_less(10.0)
