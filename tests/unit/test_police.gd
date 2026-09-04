extends GdUnitTestSuite
## Полиция: штрафы и розыск, проверка видимости, погоня (police.js + WantedConfig).
## Сценарные тесты: одно нарушение = +1 уровень розыска при наличии патруля
## в радиусе с прямой видимостью; здание между машиной и игроком гасит видимость;
## спад розыска с наградой за побег; погоня включается с WantedConfig.chase_level.

const DT := 1.0 / 60.0
# Игрок стоит на дороге (x=66 близко к оси дороги x=64, внутри полосы 6 м).
const PLAYER_X := 66.0
const PLAYER_Z := 150.0
const COP_Z := 120.0
const SPEED_OVER := 34.0  # > speed_threshold 30

var _field: CityField
var _lights: TrafficLightController


func before() -> void:
	_field = CityField.new(Db.balance)
	_lights = TrafficLightController.new(_field)


## План с одним зданием, перекрывающим коридор (66,120)-(66,150) на середине.
func _occluding_plan() -> CityPlan:
	var plan := CityPlan.new()
	plan.add_building(Vector4(58.0, 130.0, 74.0, 142.0), 12.0,
		Color.BLUE, Color.BLUE, 0, 0)
	return plan


func _open_plan() -> CityPlan:
	return CityPlan.new()


## Патруль одной полицейской машиной на (x, z).
func _mgr_with_cop(cop_x: float, cop_z: float) -> TrafficManager:
	var cat := TrafficCatalog.new()
	var t := TrafficTypeData.new()
	t.id = &"police"
	cat.items = [t]
	cat.index()
	var mgr := TrafficManager.new()
	mgr.setup(cat, _field, _lights, SeededRng.new(1), 1)
	mgr.type_ref[0] = t
	mgr.render_x[0] = cop_x
	mgr.render_z[0] = cop_z
	return mgr


func _police(mgr: TrafficManager, plan: CityPlan) -> PoliceManager:
	var p := PoliceManager.new()
	p.setup(mgr, _field, _lights, Db.balance.wanted, plan)
	return p


func _try_speeding(p: PoliceManager) -> void:
	p.update(DT, PLAYER_X, PLAYER_Z, true, SPEED_OVER, 0.0)


func test_no_fine_when_no_police_nearby() -> void:
	var mgr := _mgr_with_cop(999.0, 999.0)  # полиции рядом нет
	var p := _police(mgr, _open_plan())
	for _k in 5:
		_try_speeding(p)
	assert_int(p.wanted_level)\
		.override_failure_message("без патруля в радиусе розыск не должен расти")\
		.is_equal(0)


func test_speeding_fine_raises_wanted_once() -> void:
	var mgr := _mgr_with_cop(PLAYER_X, COP_Z)
	var p := _police(mgr, _open_plan())
	Game.set_money(5000)  # чтобы штраф мог списаться
	var money0 := Game.money
	_try_speeding(p)
	assert_int(p.wanted_level)\
		.override_failure_message("превышение при патруле рядом должно дать +1 розыск")\
		.is_equal(1)
	assert_int(Game.money).is_less(money0)

	# Повторное нарушение за кулдаун не даёт второй уровень.
	for _k in 3:
		_try_speeding(p)
	assert_int(p.wanted_level)\
		.override_failure_message("повтор в кулдауне не поднимает розыск")\
		.is_equal(1)


func test_fine_emits_violation_fined_signal() -> void:
	var mgr := _mgr_with_cop(PLAYER_X, COP_Z)
	var p := _police(mgr, _open_plan())
	Game.set_money(5000)
	var fined: Array[StringName] = []
	p.violation_fined.connect(func(id: StringName) -> void: fined.append(id))
	_try_speeding(p)
	assert_array(fined).is_equal([&"speeding"])


func test_building_between_blocks_los() -> void:
	var mgr := _mgr_with_cop(PLAYER_X, COP_Z)
	var p := _police(mgr, _occluding_plan())
	for _k in 5:
		_try_speeding(p)
	assert_int(p.wanted_level)\
		.override_failure_message("здание между патрулём и игроком гасит все штрафы")\
		.is_equal(0)


func _force_wanted(p: PoliceManager, level: int) -> void:
	p.wanted_level = level
	p._wanted_decay = Db.balance.wanted.decay_time
	# В реальном потоке _peak_wanted растёт вместе с wanted_level внутри
	# _fine(); здесь розыск выставляется напрямую, так что синхронизируем
	# его вручную — иначе побег всегда считает peak_level == 1.
	p._peak_wanted = maxi(p._peak_wanted, level)


func test_escape_reward_when_wanted_decays_to_zero() -> void:
	var mgr := _mgr_with_cop(999.0, 999.0)  # патруль вне радиуса — спад не заморожен
	var p := _police(mgr, _open_plan())
	_force_wanted(p, 2)
	var money0 := Game.money
	for _i in 4000:
		p.update(DT, PLAYER_X, PLAYER_Z, true, 10.0, 0.0)
		if p.wanted_level == 0:
			break
	assert_int(p.wanted_level)\
		.override_failure_message("розыск должен спасть до нуля")\
		.is_equal(0)
	assert_int(Game.money)\
		.override_failure_message("побег должен начислить награду")\
		.is_greater(money0)


func test_escape_emits_escaped_signal_with_peak_level() -> void:
	var mgr := _mgr_with_cop(999.0, 999.0)
	var p := _police(mgr, _open_plan())
	_force_wanted(p, 2)
	var levels: Array[int] = []
	p.escaped.connect(func(peak: int) -> void: levels.append(peak))
	for _i in 4000:
		p.update(DT, PLAYER_X, PLAYER_Z, true, 10.0, 0.0)
		if p.wanted_level == 0:
			break
	assert_array(levels).is_equal([2])


func test_chase_engages_at_chase_level() -> void:
	var mgr := _mgr_with_cop(PLAYER_X, COP_Z)
	var p := _police(mgr, _open_plan())
	_force_wanted(p, Db.balance.wanted.chase_level)
	p.update(DT, PLAYER_X, PLAYER_Z, true, 10.0, 0.0)
	assert_int(p.chase_idx)\
		.override_failure_message("на уровне %d патруль должен начать погоню"
			% Db.balance.wanted.chase_level)\
		.is_equal(0)


func test_no_chase_below_chase_level() -> void:
	var mgr := _mgr_with_cop(PLAYER_X, COP_Z)
	var p := _police(mgr, _open_plan())
	_force_wanted(p, Db.balance.wanted.chase_level - 1)
	p.update(DT, PLAYER_X, PLAYER_Z, true, 10.0, 0.0)
	assert_int(p.chase_idx)\
		.override_failure_message("ниже порога погони патруль не преследует")\
		.is_equal(-1)
