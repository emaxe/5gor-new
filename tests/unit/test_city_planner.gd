extends GdUnitTestSuite
## Генерация города обязана быть детерминированной и укладываться в бюджеты.
## Сид пишется в слот сохранения, поэтому «тот же сид — тот же город» это
## не оптимизация, а часть игрового дизайна: город должен запоминаться.

var _field: CityField
var _graph: PedGraph
var _plan: CityPlan


func before() -> void:
	_field = CityField.new(Db.balance)
	_graph = PedGraph.new(_field)
	_plan = CityPlanner.new(_field, _graph, Db.districts).plan(Db.balance.world_seed)


func test_same_seed_gives_identical_plan() -> void:
	var again := CityPlanner.new(_field, _graph, Db.districts).plan(Db.balance.world_seed)
	assert_dict(_plan.summary()).is_equal(again.summary())
	assert_int(again.building_count()).is_equal(_plan.building_count())
	for i in _plan.building_count():
		assert_vector(again.building_rect[i]).is_equal(_plan.building_rect[i])
		assert_float(again.building_height[i]).is_equal(_plan.building_height[i])


func test_different_seed_gives_different_city() -> void:
	var other := CityPlanner.new(_field, _graph, Db.districts).plan(12345)
	assert_int(other.building_count()).is_not_equal(_plan.building_count())


func test_city_is_densely_built() -> void:
	# Периметральная застройка: в оригинале выходило 1-2 дома на квартал и
	# город читался редким макетом.
	assert_int(_plan.building_count()).is_greater(180)
	var per_block := {}
	for i in _plan.building_count():
		var r := _plan.building_rect[i]
		var key := Vector2i(floori((r.x + 246.0) / 64.0), floori((r.y + 246.0) / 64.0))
		per_block[key] = per_block.get(key, 0) + 1
	assert_int(per_block.size()).is_greater(50)
	for k: Vector2i in per_block:
		assert_int(per_block[k]).is_greater_equal(2)


func test_buildings_are_pyatigorsk_scale() -> void:
	# Пятигорск малоэтажный: башен выше 25 м в городе нет.
	for h in _plan.building_height:
		assert_float(h).is_between(6.0, 25.0)


func test_buildings_never_stand_on_the_roadway() -> void:
	for i in _plan.building_count():
		var r := _plan.building_rect[i]
		for cx: float in [r.x, r.z]:
			for cz: float in [r.y, r.w]:
				assert_float(_field.dist_to_road(cx, cz))\
					.override_failure_message(
						"угол здания %d стоит на дороге: %s" % [i, Vector2(cx, cz)])\
					.is_greater_equal(_field.road_half)


func test_props_are_not_on_the_roadway() -> void:
	for p in _plan.tree_pos:
		assert_float(_field.dist_to_road(p.x, p.z)).is_greater(_field.road_half)
	for p in _plan.lamp_pos:
		assert_float(_field.dist_to_road(p.x, p.z)).is_greater(_field.road_half)
	for p in _plan.bin_pos:
		assert_float(_field.dist_to_road(p.x, p.z)).is_greater(_field.road_half)


func test_pickup_points_are_on_sidewalks() -> void:
	assert_int(_plan.pickup_pos.size()).is_greater(200)
	var side := _field.road_half + _field.sidewalk * 0.5
	for p in _plan.pickup_pos:
		var d := _field.dist_to_road(p.x, p.y)
		# Точка стоит на тротуаре: не на проезжей части и не в глубине квартала.
		assert_float(d).is_between(_field.road_half - 0.01, side + 0.01)


func test_every_district_has_pickup_points() -> void:
	var seen := {}
	for d in _plan.pickup_district:
		seen[d] = true
	assert_int(seen.size()).is_equal(Db.districts.items.size())


func test_crosswalks_come_from_the_graph() -> void:
	# Разметка генерируется из списка переходов: она физически не может
	# разъехаться с логикой ПДД.
	assert_int(_plan.crosswalk_pos.size()).is_equal(_graph.crossings.size())


func test_signals_only_on_signalized_intersections() -> void:
	assert_int(_plan.signal_pos.size()).is_equal(16 * 4)
	for i in _plan.signal_intersection.size():
		var idx: int = _plan.signal_intersection[i]
		@warning_ignore("integer_division")
		var gi: int = idx / PedGraph.AXES
		var gj: int = idx % PedGraph.AXES
		assert_bool(PedGraph.is_signalized(gi, gj)).is_true()


func test_special_blocks_stay_empty() -> void:
	# Парк, озеро, рынок, вокзал и Нарзанные ванны застройке не подлежат.
	for i in _plan.building_count():
		var r := _plan.building_rect[i]
		var bi := clampi(floori((r.x + 246.0) / 64.0), 0, 7)
		var bj := clampi(floori((r.y + 246.0) / 64.0), 0, 7)
		assert_str(String(CityPlanner.block_special(bi, bj)))\
			.override_failure_message("здание в особом квартале %d,%d" % [bi, bj])\
			.is_empty()


func test_planning_fits_the_frame_budget() -> void:
	# Фаза планирования уходит в фоновый поток, но и там она не должна
	# растягиваться: это блокирует показ загрузочного экрана.
	var t0 := Time.get_ticks_msec()
	CityPlanner.new(_field, _graph, Db.districts).plan(Db.balance.world_seed)
	var ms := Time.get_ticks_msec() - t0
	assert_int(ms).override_failure_message("планирование заняло %d мс" % ms)\
		.is_less(250)
