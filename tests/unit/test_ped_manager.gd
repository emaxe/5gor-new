extends GdUnitTestSuite
## Пешеходы — граф уже готов (PedGraph), ИИ ходит по его маршрутам точка за
## точкой и спрашивает гейт перед переходом (см. doc-комментарий класса
## PedManager). Тесты сверяют то, что не видно глазом: ожидание красного,
## респавн, наезд машиной игрока, бюджет апдейта при повышенной плотности.

const DT := 1.0 / 60.0


func _field() -> CityField:
	return CityField.new(Db.balance)


## Светофор строится здесь же и живёт в `mgr.signals`: с этапа 9 пешеходы
## слушают тот же узловой контроллер, что машины и линзы, — тесту достаётся
## роль владельца часов.
func _manager(field: CityField, graph: PedGraph, ped_count: int,
		seed_value: int) -> PedManager:
	var mgr := PedManager.new()
	mgr.setup(Db.peds, graph,
		NodeSignalController.build(CityGraphGrid.from_field(field),
			CityGraphGrid.signalized_nodes(field)),
		PedConfig.new(), SeededRng.new(seed_value), RID(), ped_count)
	return mgr


func test_setup_spawns_requested_count_with_mixed_archetypes() -> void:
	var field := _field()
	var graph := PedGraph.new(field)
	var mgr := _manager(field, graph, Db.balance.ped_count, 7)
	mgr.place_all_near(0.0, 0.0)

	assert_int(mgr.count).is_equal(Db.balance.ped_count)
	var animals := 0
	var humans := 0
	for i in mgr.count:
		if mgr.is_animal_at(i):
			animals += 1
		else:
			humans += 1
	assert_int(animals)\
		.override_failure_message("животных нет вовсе — пул спавна сломан")\
		.is_greater(0)
	assert_int(humans)\
		.override_failure_message("людей нет вовсе — пул спавна сломан")\
		.is_greater(0)


## Ставит одного пешехода на подъезде к перекрёстку (1,1) — обе координаты
## нечётные, значит регулируемый (PedGraph.is_signalized) — с маршрутом
## ЧЕРЕЗ переход поперёк северного рукава (по нему машины едут вдоль Z,
## ровно как в тесте трафика).
func _place_at_gated_crossing(mgr: PedManager, graph: PedGraph,
		car_green_for_z: bool) -> void:
	const ISEC := 1
	# Узлы сетки нумеруются i * 9 + j (CityGraphGrid.from_field), подходы
	# упорядочены по возрастанию угла: 0 — северный рукав (-Z).
	var ends := graph.crossing_ends(ISEC * 9 + ISEC, 0)
	var from_id := ends.x
	var to_id := ends.y
	var from_pos := graph.position_of(from_id)
	mgr.x[0] = from_pos.x
	mgr.z[0] = from_pos.z
	mgr.is_animal[0] = 0
	mgr.violator[0] = 0

	var route: Dictionary = graph.build_route(from_pos, to_id, false)
	mgr.route_points[0] = route["points"]
	mgr.route_gates[0] = route["gates"]
	mgr.route_nodes[0] = route["node_ids"]
	mgr.route_idx[0] = 1
	mgr.mode[0] = PedManager.Mode.WAIT
	mgr.wait_t[0] = 0.0
	# Скорость архетипа не важна для этого теста (проверяем гейт, не темп) —
	# фиксируем её, иначе случайно доставшийся медленный архетип (бабушка
	# 1.3 м/с и т.п.) не успевает перейти 16 м за окно теста.
	mgr.base_speed[0] = 2.2
	mgr.speed[0] = mgr.base_speed[0]

	# Ось Z: 0-6 зелёный для машин (значит красный для пешехода), 8-16 красный
	# (значит зелёный для пешехода) — citygen.js:3034.
	# Фазы узловой модели на сетке совпадают с осевыми (тест паритета этапа 7),
	# поэтому числа те же; адресация — по узлу, а не по индексу оси.
	var local_t := 2.0 if car_green_for_z else 10.0
	mgr.signals.time = fposmod(local_t - mgr.signals.phase_offset(ISEC * 9 + ISEC),
		NodeSignalController.CYCLE)


func test_non_violator_waits_while_car_light_is_green() -> void:
	var field := _field()
	var graph := PedGraph.new(field)
	var mgr := _manager(field, graph, 1, 3)
	mgr.place_all_near(0.0, 0.0)
	_place_at_gated_crossing(mgr, graph, true)

	var start_x := mgr.x[0]
	var start_z := mgr.z[0]
	var player_x := mgr.x[0]
	var player_z := mgr.z[0]
	for _i in 300:
		mgr.update(DT, player_x, player_z, 0.0, 0.0, 0.0, 0.0, false)

	assert_int(mgr.mode[0])\
		.override_failure_message("пешеход не должен переходить на зелёный для машин")\
		.is_equal(PedManager.Mode.WAIT)
	assert_float(MathUtils.dist_2d(mgr.x[0], mgr.z[0], start_x, start_z))\
		.override_failure_message("пешеход сдвинулся, хотя горел зелёный машинам")\
		.is_less(0.05)


func test_pedestrian_crosses_once_car_light_turns_red() -> void:
	var field := _field()
	var graph := PedGraph.new(field)
	var mgr := _manager(field, graph, 1, 3)
	mgr.place_all_near(0.0, 0.0)
	_place_at_gated_crossing(mgr, graph, false)

	var target: Vector3 = mgr.route_points[0][mgr.route_idx[0]]
	var player_x := mgr.x[0]
	var player_z := mgr.z[0]
	for _i in 600:
		mgr.update(DT, player_x, player_z, 0.0, 0.0, 0.0, 0.0, false)

	assert_float(MathUtils.dist_2d(mgr.x[0], mgr.z[0], target.x, target.z))\
		.override_failure_message("пешеход не дошёл до другой стороны перехода за 10 c")\
		.is_less(0.5)


func test_pedestrian_respawns_beyond_respawn_radius() -> void:
	var field := _field()
	var graph := PedGraph.new(field)
	var mgr := _manager(field, graph, 1, 11)
	mgr.place_all_near(0.0, 0.0)
	mgr.x[0] = 1000.0
	mgr.z[0] = 1000.0

	mgr.update(DT, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false)

	assert_float(MathUtils.dist_2d(mgr.x[0], mgr.z[0], 0.0, 0.0))\
		.override_failure_message("пешехода не респавнило рядом с игроком")\
		.is_less(mgr.config.respawn_radius)


func test_player_car_knocks_down_pedestrian_at_speed() -> void:
	var field := _field()
	var graph := PedGraph.new(field)
	var mgr := _manager(field, graph, 1, 5)
	mgr.place_all_near(0.0, 0.0)
	mgr.x[0] = 0.0
	mgr.z[0] = 0.0
	mgr.mode[0] = PedManager.Mode.WALK

	# Игрок наезжает на пешехода на скорости, двигаясь вдоль +Z.
	mgr.update(DT, 0.0, -0.3, 0.0, 8.0, 0.0, 8.0, false)

	assert_int(mgr.mode[0])\
		.override_failure_message("наезд на скорости обязан сбить пешехода")\
		.is_equal(PedManager.Mode.KNOCKED)


## Регрессия: _start_flee() не восстанавливал speed[i], поэтому пешеход,
## застрявший в обходе (_avoid_static зануляет speed при stuck_t > STUCK)
## и затем испугавшийся, убегал с замороженной фазой шага — ноги не
## двигались, хотя позиция реально смещалась через flee_vx/flee_vz.
func test_flee_restores_speed_so_walk_phase_animates() -> void:
	var field := _field()
	var graph := PedGraph.new(field)
	var mgr := _manager(field, graph, 1, 13)
	mgr.place_all_near(0.0, 0.0)
	mgr.is_animal[0] = 1
	mgr.x[0] = 0.0
	mgr.z[0] = 0.0
	mgr.speed[0] = 0.0

	mgr.react_to_punch(0, 1.0, 0.0) # животные всегда убегают, не отвечают

	assert_int(mgr.mode_of(0)).is_equal(PedManager.Mode.FLEE)
	assert_float(mgr.speed_of(0))\
		.override_failure_message("_start_flee не восстановил speed — анимация ног при побеге не пойдёт")\
		.is_greater(0.05)

	# Игрок должен быть достаточно далеко, чтобы не переактивировать реакцию
	# (config.anger_dist/animal_flee_dist ~12 м), но внутри respawn_radius
	# (210 м) — иначе update() посчитает пешехода потерянным и переставит
	# его через place_near(), которая сбрасывает и mode, и walk_phase.
	var phase_before := mgr.walk_phase_of(0)
	mgr.update(DT, 50.0, 50.0, 0.0, 0.0, 0.0, 0.0, false)
	assert_int(mgr.mode_of(0))\
		.override_failure_message("пешеход должен остаться в FLEE, а не быть переставлен респавном")\
		.is_equal(PedManager.Mode.FLEE)
	assert_float(mgr.walk_phase_of(0))\
		.override_failure_message("walk_phase не растёт во время FLEE")\
		.is_greater(phase_before)


func test_update_fits_frame_budget_at_triple_density() -> void:
	var field := _field()
	var graph := PedGraph.new(field)
	var triple := Db.balance.ped_count * 3
	var mgr := _manager(field, graph, triple, 9)
	mgr.place_all_near(0.0, 0.0)

	var t0 := Time.get_ticks_usec()
	for _i in 60:
		mgr.update(DT, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false)
	var us := Time.get_ticks_usec() - t0
	var per_tick_ms := (us / 1000.0) / 60.0
	# Порог — под headless-интерпретатор GDScript в debug-сборке, не под
	# экспортированный релиз; цель — поймать регресс бакетизации, не
	# измерить итоговый кадровый бюджет (см. аналогичный тест трафика).
	assert_float(per_tick_ms)\
		.override_failure_message("апдейт пешеходов (%d) занял %.3f мс/тик"
			% [triple, per_tick_ms])\
		.is_less(15.0)
