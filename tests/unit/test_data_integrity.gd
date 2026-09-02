extends GdUnitTestSuite
## Проверка сгенерированных data/**.tres против чисел JS-оригинала.
##
## Данные генерируются автоматически (tools/dump_data.mjs -> tools/import_json.gd),
## поэтому тест — единственная защита от тихого расхождения с оригиналом:
## ошибка в мэппинге не упадёт при запуске, а тихо сломает баланс.

func before_test() -> void:
	Db.load_all()


# --- Полнота каталогов -------------------------------------------------------

func test_catalogs_loaded() -> void:
	assert_object(Db.balance).is_not_null()
	assert_object(Db.cars).is_not_null()
	assert_object(Db.upgrades).is_not_null()
	assert_object(Db.districts).is_not_null()
	assert_object(Db.weather).is_not_null()
	assert_object(Db.orders).is_not_null()
	assert_object(Db.traffic).is_not_null()
	assert_object(Db.peds).is_not_null()
	assert_object(Db.achievements).is_not_null()
	assert_object(Db.stations).is_not_null()
	assert_object(Db.gfx).is_not_null()


func test_catalog_sizes_match_original() -> void:
	assert_int(Db.cars.size()).is_equal(7)
	assert_int(Db.upgrades.items.size()).is_equal(6)
	assert_int(Db.districts.items.size()).is_equal(8)
	assert_int(Db.districts.landmarks.size()).is_equal(9)
	assert_int(Db.districts.fuel_stations.size()).is_equal(4)
	assert_int(Db.weather.items.size()).is_equal(3)
	assert_int(Db.orders.types.size()).is_equal(8)
	assert_int(Db.orders.missions.size()).is_equal(5)
	assert_int(Db.orders.mood_tiers.size()).is_equal(5)
	assert_int(Db.traffic.items.size()).is_equal(20)
	assert_int(Db.peds.items.size()).is_equal(15)
	assert_int(Db.achievements.size()).is_equal(29)
	assert_int(Db.stations.items.size()).is_equal(6)
	assert_int(Db.gfx.items.size()).is_equal(3)


# --- Числа баланса -----------------------------------------------------------

func test_world_constants() -> void:
	var b := Db.balance
	assert_float(b.cell).is_equal(64.0)
	assert_float(b.road_width).is_equal(12.0)
	assert_float(b.road_half).is_equal(6.0)
	assert_float(b.sidewalk).is_equal(4.0)
	assert_int(b.grid_n).is_equal(4)
	assert_float(b.shadow_half).is_equal(90.0)
	assert_int(b.world_seed).is_equal(20260805)


func test_economy_constants() -> void:
	var b := Db.balance
	assert_int(b.start_money).is_equal(800)
	assert_float(b.start_fuel).is_equal(70.0)
	assert_float(b.fuel_price).is_equal(0.9)
	assert_float(b.base_fare).is_equal(120.0)
	assert_float(b.fare_per_unit).is_equal(1.35)
	assert_float(b.tips_max).is_equal(90.0)
	assert_float(b.night_mult).is_equal(2.0)
	assert_int(b.tow_cost).is_equal(400)
	assert_int(b.wash_cost).is_equal(60)
	assert_float(b.repair_cost_per_damage).is_equal(22.0)


func test_shift_constants() -> void:
	var b := Db.balance
	assert_float(b.shift_start_hour).is_equal(9.0)
	assert_float(b.day_length_sec).is_equal(720.0)
	assert_float(b.night_start_hour).is_equal(22.0)
	assert_float(b.night_end_hour).is_equal(6.0)


func test_wanted_config() -> void:
	var w := Db.balance.wanted
	assert_object(w).is_not_null()
	assert_int(w.max_level).is_equal(5)
	assert_float(w.decay_time).is_equal(25.0)
	assert_float(w.detect_radius).is_equal(60.0)
	assert_float(w.speed_threshold).is_equal(30.0)
	assert_int(w.fine_speeding).is_equal(300)
	assert_int(w.fine_red_light).is_equal(500)
	assert_int(w.fine_hit_ped).is_equal(800)
	assert_int(w.fine_ped_punch).is_equal(500)
	# L2 => x1.5, L5 => x3.0 (config.js:154)
	assert_float(w.fine_mult(1)).is_equal(1.0)
	assert_float(w.fine_mult(2)).is_equal(1.5)
	assert_float(w.fine_mult(5)).is_equal(3.0)
	assert_float(w.effective_detect_radius(1)).is_equal(60.0)
	assert_float(w.effective_detect_radius(3)).is_equal(90.0)


func test_style_config() -> void:
	var s := Db.balance.style
	assert_object(s).is_not_null()
	assert_float(s.drift_min_slip).is_equal(0.5)
	assert_float(s.drift_min_speed).is_equal(7.0)
	assert_float(s.drift_min_duration).is_equal(0.8)
	assert_int(s.drift_max_reward).is_equal(200)
	assert_float(s.near_miss_min_speed).is_equal(10.0)
	assert_int(s.near_miss_reward).is_equal(35)
	# Пороги серии сближений 2/5/10 -> x2/x5/x10 (config.js:219)
	assert_float(s.near_miss_mult(1)).is_equal(1.0)
	assert_float(s.near_miss_mult(2)).is_equal(2.0)
	assert_float(s.near_miss_mult(7)).is_equal(5.0)
	assert_float(s.near_miss_mult(12)).is_equal(10.0)
	# Комбо заказов: 1 + min(streak, 10) * 0.05, потолок x1.5 (game.js:520)
	assert_float(s.combo_mult(0)).is_equal(1.0)
	assert_float(s.combo_mult(3)).is_equal_approx(1.15, 1e-6)
	assert_float(s.combo_mult(50)).is_equal_approx(1.5, 1e-6)


func test_ped_config() -> void:
	var p := Db.balance.ped
	assert_object(p).is_not_null()
	assert_float(p.active_radius).is_equal(110.0)
	assert_float(p.near_radius).is_equal(150.0)
	assert_float(p.violator_chance).is_equal(0.08)
	assert_float(p.walk_speed).is_equal(3.1)
	assert_float(p.run_speed).is_equal(5.8)
	assert_float(p.punch_radius).is_equal(2.0)
	assert_float(p.punch_arc).is_equal_approx(PI / 3.0, 1e-6)
	assert_int(p.player_max_hp).is_equal(3)
	assert_float(p.gravity).is_equal(20.0)


# --- Машины ------------------------------------------------------------------

func test_taxi_stats_match_original() -> void:
	var c := Db.cars.get_car(&"taxi")
	assert_object(c).is_not_null()
	assert_int(c.price).is_equal(0)
	assert_float(c.max_speed).is_equal(34.0)
	assert_float(c.accel).is_equal(13.0)
	assert_float(c.brake).is_equal(26.0)
	assert_float(c.grip).is_equal(1.0)
	assert_int(c.capacity).is_equal(1)
	assert_bool(c.is_taxi).is_true()
	assert_str(String(c.default_decal)).is_equal("checker")


func test_sport_stats_match_original() -> void:
	var c := Db.cars.get_car(&"sport")
	assert_int(c.price).is_equal(34000)
	assert_int(c.unlock_rating).is_equal(65)
	assert_float(c.max_speed).is_equal(48.0)
	assert_float(c.steer).is_equal(2.7)
	assert_str(String(c.default_decal)).is_equal("none")


func test_every_car_has_shape() -> void:
	for c in Db.cars.items:
		assert_object(c.shape).is_not_null()
		assert_float(c.shape.width).is_greater(1.0)
		assert_float(c.shape.length).is_greater(3.0)


func test_car_collider_geometry_matches_original() -> void:
	# player.js:315-316 для taxi 1.9x4.3: rc = 0.9785, sep = 1.2
	var shape := Db.cars.get_car(&"taxi").shape
	assert_float(shape.collider_radius()).is_equal_approx(0.9785, 1e-4)
	assert_float(shape.collider_separation()).is_equal_approx(1.2, 1e-4)


func test_car_unlock_ratings_are_monotonic_with_price() -> void:
	var sorted_cars := Db.cars.items.duplicate()
	sorted_cars.sort_custom(func(a: CarData, b: CarData) -> bool:
		return a.price < b.price)
	var prev := -1
	for c in sorted_cars:
		assert_int(c.unlock_rating).is_greater_equal(prev)
		prev = c.unlock_rating


# --- Апгрейды ----------------------------------------------------------------

func test_upgrade_costs_match_original() -> void:
	# costOf = round(base * mult^level), upgrades.js:22
	var engine := Db.upgrades.get_upgrade(&"engine")
	assert_int(engine.max_level).is_equal(4)
	assert_int(engine.cost_at(0)).is_equal(600)
	assert_int(engine.cost_at(1)).is_equal(1020)
	assert_int(engine.cost_at(2)).is_equal(1734)
	assert_int(engine.cost_at(3)).is_equal(2948)
	assert_int(engine.cost_at(4)).is_equal(-1)


func test_upgrade_effects_present() -> void:
	assert_float(Db.upgrades.get_upgrade(&"engine").max_speed_per_level).is_equal(3.2)
	assert_float(Db.upgrades.get_upgrade(&"engine").accel_per_level).is_equal(1.6)
	assert_float(Db.upgrades.get_upgrade(&"suspension").grip_per_level).is_equal(0.05)
	assert_float(Db.upgrades.get_upgrade(&"suspension").steer_per_level).is_equal(0.18)
	assert_float(Db.upgrades.get_upgrade(&"brakes").brake_per_level).is_equal(5.0)
	assert_float(Db.upgrades.get_upgrade(&"armor").armor_per_level).is_equal(0.35)
	assert_float(Db.upgrades.get_upgrade(&"tank").tank_per_level).is_equal(50.0)
	assert_int(Db.upgrades.get_upgrade(&"capacity").capacity_per_level).is_equal(1)


# --- Районы и заказы ---------------------------------------------------------

func test_district_unlocks_match_original() -> void:
	var expected := {
		&"center": 0, &"kurort": 0, &"prigorod": 0, &"proval": 15,
		&"rynok": 30, &"sanatorii": 45, &"mashuk": 60, &"vokzal": 75,
	}
	for id: StringName in expected:
		var d := Db.districts.get_district(id)
		assert_object(d).is_not_null()
		assert_int(d.unlock_rating).is_equal(expected[id])


func test_every_district_has_palette() -> void:
	for d in Db.districts.items:
		assert_object(d.palette).is_not_null()
		assert_int(d.palette.facades.size()).is_equal(5)


func test_order_types_match_original() -> void:
	var mults := {
		&"normal": 1.0, &"urgent": 1.6, &"vip": 1.5, &"package": 1.15,
		&"drunk": 1.35, &"group": 0.9, &"race": 1.9, &"tour": 2.0,
	}
	for id: StringName in mults:
		var t := Db.orders.get_type(id)
		assert_object(t).is_not_null()
		assert_float(t.pay_mult).is_equal_approx(mults[id], 1e-6)


func test_order_rating_rewards_have_no_fallback_gap() -> void:
	# В оригинале ratingPerOrder.tourist не совпадал с типом tour и срабатывал
	# скрытый fallback `|| 8`. Здесь у каждого типа своя явная награда.
	var expected := {
		&"normal": 4, &"urgent": 6, &"vip": 7, &"group": 9,
		&"tour": 10, &"package": 5, &"drunk": 6, &"race": 12,
	}
	for id: StringName in expected:
		assert_int(Db.orders.get_type(id).rating_reward).is_equal(expected[id])


func test_order_time_limits() -> void:
	assert_float(Db.orders.get_type(&"urgent").time_limit).is_equal(75.0)
	assert_float(Db.orders.get_type(&"race").time_limit).is_equal(90.0)
	assert_float(Db.orders.get_type(&"normal").time_limit).is_equal(0.0)


func test_order_spawn_weights_sum_to_one() -> void:
	var day := 0.0
	var night := 0.0
	for t in Db.orders.types:
		day += t.day_weight
		night += t.night_weight
	assert_float(day).is_equal_approx(1.0, 1e-6)
	assert_float(night).is_equal_approx(1.0, 1e-6)


func test_mood_tiers_sorted_and_cover_full_range() -> void:
	var prev := -1.0
	for t in Db.orders.mood_tiers:
		assert_float(t.min_style).is_greater(prev)
		prev = t.min_style
	assert_float(Db.orders.mood_tiers[0].min_style).is_equal(0.0)
	assert_object(Db.orders.mood_for(0.0)).is_not_null()
	assert_object(Db.orders.mood_for(1.0)).is_not_null()
	assert_float(Db.orders.mood_for(0.5).min_style).is_equal(0.45)


func test_missions_unlock_progression() -> void:
	var expected := {
		&"grandma": 10, &"doctor": 25, &"race": 35, &"tour": 45, &"night": 60,
	}
	for id: StringName in expected:
		var m := Db.orders.get_mission(id)
		assert_object(m).is_not_null()
		assert_int(m.required_rating).is_equal(expected[id])
	assert_int(Db.orders.get_mission(&"tour").drops.size()).is_equal(3)


# --- Трафик и пешеходы -------------------------------------------------------

func test_traffic_has_police_and_ambulance() -> void:
	assert_object(Db.traffic.get_type(&"police")).is_not_null()
	assert_object(Db.traffic.get_type(&"ambulance")).is_not_null()
	assert_str(String(Db.traffic.get_type(&"police").beacon)).is_equal("police")
	assert_bool(Db.traffic.get_type(&"police").police_livery).is_true()
	assert_bool(Db.traffic.get_type(&"taxi").livery).is_true()


func test_traffic_dimensions_are_sane() -> void:
	for t in Db.traffic.items:
		assert_float(t.width).is_between(1.5, 2.5)
		assert_float(t.length).is_between(3.5, 9.0)
		assert_float(t.weight).is_greater(0.0)
		assert_int(t.colors.size()).is_greater(0)


func test_ped_archetypes_include_animals() -> void:
	assert_bool(Db.peds.get_archetype(&"dog").is_animal).is_true()
	assert_bool(Db.peds.get_archetype(&"cat").is_animal).is_true()
	assert_bool(Db.peds.get_archetype(&"gopnik").is_animal).is_false()


func test_ped_speeds_match_original() -> void:
	# peds.js:834-845
	var expected := {
		&"runner": [4.0, 5.0], &"dog": [3.0, 4.2], &"cat": [2.2, 3.5],
		&"gopnik": [2.3, 2.9], &"grandma": [1.3, 1.7], &"elder": [1.2, 1.6],
		&"child": [2.0, 2.6], &"mom": [1.6, 2.0],
	}
	for id: StringName in expected:
		var a := Db.peds.get_archetype(id)
		assert_float(a.speed_min).is_equal(expected[id][0])
		assert_float(a.speed_max).is_equal(expected[id][1])


func test_every_ped_archetype_has_quote_banks() -> void:
	for a in Db.peds.items:
		assert_object(a.quotes_idle).is_not_null()
		assert_bool(a.quotes_idle.is_empty()).is_false()


# --- Достижения --------------------------------------------------------------

func test_achievement_requirements_are_declarative() -> void:
	for a in Db.achievements.items:
		assert_array(a.requirements).is_not_empty()
		for r in a.requirements:
			assert_str(String(r.stat)).is_not_empty()


func test_compound_achievement_clean_shift() -> void:
	var a := Db.achievements.get_achievement(&"clean_shift")
	assert_object(a).is_not_null()
	assert_int(a.requirements.size()).is_equal(3)
	assert_bool(a.is_met({
		"shift_orders": 5.0, "shift_crashes": 0.0, "shift_peds": 0.0,
	})).is_true()
	assert_bool(a.is_met({
		"shift_orders": 5.0, "shift_crashes": 1.0, "shift_peds": 0.0,
	})).is_false()
	assert_bool(a.is_met({
		"shift_orders": 4.0, "shift_crashes": 0.0, "shift_peds": 0.0,
	})).is_false()


func test_simple_achievement_progress() -> void:
	var a := Db.achievements.get_achievement(&"orders_100")
	assert_str(String(a.track_stat)).is_equal("total_orders")
	assert_float(a.track_target).is_equal(100.0)
	assert_float(a.progress({"total_orders": 25.0})).is_equal_approx(0.25, 1e-6)
	assert_float(a.progress({"total_orders": 999.0})).is_equal(1.0)
	# У составного условия прогресс-бара нет.
	assert_float(Db.achievements.get_achievement(&"clean_shift")
		.progress({})).is_equal(-1.0)


func test_achievement_stats_exist_in_game_state() -> void:
	# Каждое поле статистики, на которое ссылается ачивка, должно реально
	# считаться игрой — иначе достижение недостижимо.
	var known := Game.all_stats()
	for a in Db.achievements.items:
		for r in a.requirements:
			assert_bool(known.has(String(r.stat)))\
				.override_failure_message(
					"ачивка %s ссылается на несуществующее поле %s"
					% [a.id, r.stat])\
				.is_true()


# --- Погода, радио, графика --------------------------------------------------

func test_weather_matches_original() -> void:
	var clear := Db.weather.get_weather(&"clear")
	assert_float(clear.grip).is_equal(1.0)
	assert_float(clear.fog_far).is_equal(1600.0)
	var rain := Db.weather.get_weather(&"rain")
	assert_float(rain.grip).is_equal(0.78)
	assert_float(rain.traffic).is_equal(0.7)
	assert_float(rain.fog_near).is_equal(120.0)
	var fog := Db.weather.get_weather(&"fog")
	assert_float(fog.grip).is_equal(0.95)
	assert_float(fog.fog_far).is_equal(220.0)


func test_radio_stations_match_original() -> void:
	var bpm := {
		&"pyatigorsk": 84.0, &"synth": 116.0, &"kavkaz": 128.0,
		&"rock": 140.0, &"chanson": 104.0, &"chilled": 72.0,
	}
	for id: StringName in bpm:
		var s := Db.stations.get_station(id)
		assert_object(s).is_not_null()
		assert_float(s.bpm).is_equal(bpm[id])
		assert_int(s.instruments.size()).is_greater(0)


func test_radio_cycles_through_off() -> void:
	var id := Db.stations.next_station(&"off")
	var seen := 0
	while id != &"off" and seen < 20:
		id = Db.stations.next_station(id)
		seen += 1
	assert_int(seen).is_equal(6)


func test_gfx_presets_match_original() -> void:
	var low := Db.gfx.get_preset(&"low")
	assert_str(String(low.shadows)).is_equal("off")
	assert_float(low.draw_distance).is_equal(600.0)
	assert_int(low.pixel_budget).is_equal(1_600_000)
	var high := Db.gfx.get_preset(&"high")
	assert_str(String(high.shadows)).is_equal("high")
	assert_float(high.draw_distance).is_equal(1400.0)
	assert_bool(high.ssao).is_true()


func test_gfx_scale_respects_pixel_budget() -> void:
	var high := Db.gfx.get_preset(&"high")
	# 3.2 Мпикс бюджета: 1280x720 (0.92 Мпикс) укладывается на полном масштабе.
	assert_float(high.effective_scale(Vector2i(1280, 720))).is_equal(1.0)
	# 4K (8.29 Мпикс) должен быть урезан.
	assert_float(high.effective_scale(Vector2i(3840, 2160))).is_less(1.0)


# --- Локализация -------------------------------------------------------------

func test_all_display_strings_are_translation_keys() -> void:
	# В ресурсах должны лежать только ключи; русский текст живёт в CSV.
	for c in Db.cars.items:
		assert_str(c.display_name).is_equal(c.display_name.to_upper())
		assert_str(tr(c.display_name)).is_not_equal(c.display_name)
	for a in Db.achievements.items:
		assert_str(tr(a.display_name)).is_not_equal(a.display_name)


func test_quote_banks_resolve_to_text() -> void:
	var bank := Db.peds.get_archetype(&"gopnik").quotes_idle
	assert_int(bank.lines.size()).is_greater(0)
	for key in bank.lines:
		assert_str(tr(key))\
			.override_failure_message("нет перевода для ключа %s" % key)\
			.is_not_equal(key)
