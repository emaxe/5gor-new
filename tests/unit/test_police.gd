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
## Скорость ниже порога превышения (30), но выше RED_LIGHT_MIN_SPEED (3):
## на ней может сработать только проезд на красный, и штраф не спутать.
const SPEED_RED_ONLY := 10.0
## Патруль в 6 м сбоку от игрока — заведомо внутри радиуса детекции.
const COP_OFFSET := 6.0

var _field: CityField
var _grid: CityGraph
var _grid_signals: NodeSignalController


func before() -> void:
	_field = CityField.new(Db.balance)
	_grid = CityGraphGrid.from_field(_field)
	_grid_signals = NodeSignalController.build(
		_grid, CityGraphGrid.signalized_nodes(_field))


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
	mgr.setup(cat, _grid, _grid_signals, SeededRng.new(1), 1)
	mgr.type_ref[0] = t
	mgr.render_x[0] = cop_x
	mgr.render_z[0] = cop_z
	return mgr


func _police(mgr: TrafficManager, plan: CityPlan) -> PoliceManager:
	var p := PoliceManager.new()
	p.setup(mgr, _field, _grid, _grid_signals, Db.balance.wanted, plan)
	return p


func _try_speeding(p: PoliceManager) -> void:
	p.update(DT, PLAYER_X, 0.0, PLAYER_Z, true, SPEED_OVER, 0.0)


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
		p.update(DT, PLAYER_X, 0.0, PLAYER_Z, true, 10.0, 0.0)
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
		p.update(DT, PLAYER_X, 0.0, PLAYER_Z, true, 10.0, 0.0)
		if p.wanted_level == 0:
			break
	assert_array(levels).is_equal([2])


func test_chase_engages_at_chase_level() -> void:
	var mgr := _mgr_with_cop(PLAYER_X, COP_Z)
	var p := _police(mgr, _open_plan())
	_force_wanted(p, Db.balance.wanted.chase_level)
	p.update(DT, PLAYER_X, 0.0, PLAYER_Z, true, 10.0, 0.0)
	assert_int(p.chase_idx)\
		.override_failure_message("на уровне %d патруль должен начать погоню"
			% Db.balance.wanted.chase_level)\
		.is_equal(0)


func test_no_chase_below_chase_level() -> void:
	var mgr := _mgr_with_cop(PLAYER_X, COP_Z)
	var p := _police(mgr, _open_plan())
	_force_wanted(p, Db.balance.wanted.chase_level - 1)
	p.update(DT, PLAYER_X, 0.0, PLAYER_Z, true, 10.0, 0.0)
	assert_int(p.chase_idx)\
		.override_failure_message("ниже порога погони патруль не преследует")\
		.is_equal(-1)


# --- Видимость сквозь повёрнутые здания -------------------------------------
#
# Периметральная застройка по графу (этап 5) ставит дома вдоль улицы, а не по
# осям X/Z, поэтому проверка видимости работает с OBB, а не с AABB. Разница
# видна ровно в углах описанного прямоугольника: у корпуса 20x8, развёрнутого
# на 45°, они отстоят от дома на 6 м, и патруль «видел» бы сквозь двор.

## Корпус 20x8 с центром в нуле, развёрнутый на `yaw`.
func _rotated_plan(yaw: float) -> CityPlan:
	var plan := CityPlan.new()
	plan.add_building(Vector4(-10.0, -4.0, 10.0, 4.0), 12.0,
		Color.BLUE, Color.BLUE, 0, 0, yaw)
	return plan


func _hash_of(plan: CityPlan) -> PoliceManager.BuildingHash:
	var h := PoliceManager.BuildingHash.new()
	h.build(plan)
	return h


func test_rotated_building_blocks_the_line_of_sight() -> void:
	var h := _hash_of(_rotated_plan(PI * 0.25))
	assert_bool(h.segment_hits(-12.0, -12.0, 12.0, 12.0))\
		.override_failure_message("отрезок через центр повёрнутого дома обязан упереться")\
		.is_true()


func test_rotated_building_does_not_block_beside_itself() -> void:
	# Точка (9, 9) лежит внутри описанного AABB (±9.9), но снаружи корпуса:
	# в его осях это 12.7 м от середины при глубине 8 м.
	var h := _hash_of(_rotated_plan(PI * 0.25))
	assert_bool(h.segment_hits(7.0, 7.0, 12.0, 12.0))\
		.override_failure_message(
			"отрезок мимо угла дома (внутри его AABB) не должен считаться перекрытым")\
		.is_false()


func test_zero_yaw_keeps_the_old_behaviour() -> void:
	var h := _hash_of(_rotated_plan(0.0))
	assert_bool(h.segment_hits(0.0, -12.0, 0.0, 12.0))\
		.override_failure_message("отрезок поперёк неповёрнутого дома обязан упереться")\
		.is_true()
	assert_bool(h.segment_hits(-12.0, 6.0, 12.0, 6.0))\
		.override_failure_message("отрезок в 2 м за торцом дома проходит свободно")\
		.is_false()


# --- Проезд на красный на настоящей топологии --------------------------------
#
# Этап 9: старая проверка сравнивала ОБЕ координаты игрока с одним и тем же
# элементом сеточного массива `TrafficLightController.axes` и потому
# срабатывала только у диагональных точек сетки (ax, ax) — в том числе (0,0)
# и (64,64) внутри живого центра, где нет ни перекрёстка, ни светофора, — а
# ни один из 11 настоящих регулируемых узлов не проверялся вовсе. Тесты ниже
# закрывают обе половины дефекта.

## Дека путепровода Козлова: узел `koz_d1` топологии, ярус 1, +6.5 м.
## Взят именно он, а не середина пролёта: над улицей Крайнего оба яруса
## проецируются в одну точку плана, и дизамбигуация по высоте там не видна.
const DECK_X := 69.0
const DECK_Z := 167.0
## Точка, где срабатывала диагональная адресация: 64 входит в
## `CityField.road_axes`, и старая проверка при курсе на +Z требовала
## |px - 64| <= 8, 0 < 64 - pz <= 13 — то есть ровно окно ниже. В живом
## городе тут полотно Бульварной, а ближайший узел `kra_bua` (64, 66) —
## перекрёсток с Красноармейской, светофора на нём НЕТ.
const PHANTOM_X := 64.0
const PHANTOM_Z := 60.0
## Игрок в 5 м от узла по подходу: внутри окна штрафа (RED_LIGHT_ZONE = 8 м).
const APPROACH_DIST := 5.0
## Шаг перебора цикла светофора при поиске нужной фазы, с. Втрое короче
## самого короткого сигнала (жёлтый — 2 с), значит ни одна фаза не проскочит.
const PHASE_SCAN_STEP := 0.1

var _city: CityField
var _roads: CityGraph
var _signals: NodeSignalController


func _real_city() -> void:
	if _roads != null:
		return
	_city = CityField.new(Db.balance)
	var topo := PyatigorskTopology.new()
	_roads = topo.build(_city)
	_city.attach_roads(_roads)
	_signals = NodeSignalController.build(_roads, topo.signal_nodes,
		topo.wave_front_nodes)


func _police_real(mgr: TrafficManager, plan: CityPlan) -> PoliceManager:
	var p := PoliceManager.new()
	p.setup(mgr, _city, _roads, _signals, Db.balance.wanted, plan)
	return p


## Позиция игрока в 5 м от узла по подходу `k` и курс «носом в узел».
## Курс задан в соглашении `Heading.forward` (0 = +Z), подход — в
## atan2(dz, dx) направления ОТ узла, поэтому обратный вектор —
## (-cos a, -sin a).
func _approach_pose(node: int, k: int) -> Array:
	var np := _roads.node_position(node)
	var a := _roads.approach_angle(node, k)
	var pos := Vector3(np.x + cos(a) * APPROACH_DIST, np.y,
		np.z + sin(a) * APPROACH_DIST)
	return [pos, atan2(-cos(a), -sin(a))]


## Момент цикла, когда на подходе горит нужный сигнал; -1, если не нашлось.
func _time_with_state(node: int, approach: int, want: int) -> float:
	var t := 0.0
	while t < NodeSignalController.CYCLE:
		_signals.time = t
		if _signals.car_state(node, approach) == want:
			return t
		t += PHASE_SCAN_STEP
	return -1.0


func _fined_ids(p: PoliceManager) -> Array[StringName]:
	var out: Array[StringName] = []
	p.violation_fined.connect(func(id: StringName) -> void: out.append(id))
	return out


func test_red_light_fires_at_a_real_regulated_node() -> void:
	_real_city()
	var node: int = _signals.regulated_nodes()[0]
	var t := _time_with_state(node, 0, NodeSignalController.State.RED)
	assert_float(t)\
		.override_failure_message(
			"у узла %d за цикл 16 с обязан быть красный хотя бы на подходе 0" % node)\
		.is_greater_equal(0.0)
	_signals.time = t

	var pose := _approach_pose(node, 0)
	var pos: Vector3 = pose[0]
	var heading: float = pose[1]
	var p := _police_real(_mgr_with_cop(pos.x + COP_OFFSET, pos.z), _open_plan())
	Game.set_money(50000)
	var fined := _fined_ids(p)
	p.update(DT, pos.x, pos.y, pos.z, true, SPEED_RED_ONLY, heading)
	assert_array(fined)\
		.override_failure_message(
			"на красный у регулируемого узла %d (%.0f, %.0f) обязан быть штраф"
			% [node, pos.x, pos.z])\
		.is_equal([&"red_light"])


func test_no_red_light_fine_on_green_at_the_same_node() -> void:
	_real_city()
	var node: int = _signals.regulated_nodes()[0]
	var t := _time_with_state(node, 0, NodeSignalController.State.GREEN)
	assert_float(t)\
		.override_failure_message("у узла %d обязан быть и зелёный" % node)\
		.is_greater_equal(0.0)
	_signals.time = t

	var pose := _approach_pose(node, 0)
	var pos: Vector3 = pose[0]
	var heading: float = pose[1]
	var p := _police_real(_mgr_with_cop(pos.x + COP_OFFSET, pos.z), _open_plan())
	Game.set_money(50000)
	var fined := _fined_ids(p)
	p.update(DT, pos.x, pos.y, pos.z, true, SPEED_RED_ONLY, heading)
	assert_array(fined)\
		.override_failure_message("на зелёный у узла %d штрафа быть не должно" % node)\
		.is_empty()


func test_all_regulated_nodes_are_reachable_by_the_check() -> void:
	_real_city()
	var missed := PackedInt32Array()
	for node: int in _signals.regulated_nodes():
		var t := _time_with_state(node, 0, NodeSignalController.State.RED)
		if t < 0.0:
			missed.append(node)
			continue
		_signals.time = t
		var pose := _approach_pose(node, 0)
		var pos: Vector3 = pose[0]
		var heading: float = pose[1]
		var p := _police_real(
			_mgr_with_cop(pos.x + COP_OFFSET, pos.z), _open_plan())
		Game.set_money(50000)
		p.update(DT, pos.x, pos.y, pos.z, true, SPEED_RED_ONLY, heading)
		if p.wanted_level == 0:
			missed.append(node)
	assert_int(missed.size())\
		.override_failure_message(
			"проезд на красный обязан фиксироваться на всех %d регулируемых узлах, не сработал на %s"
			% [_signals.regulated_nodes().size(), str(missed)])\
		.is_equal(0)


func test_no_phantom_fine_at_the_old_grid_diagonal() -> void:
	_real_city()
	# Игрок на полотне Бульварной в 6 м от нерегулируемого узла kra_bua,
	# носом в него: старая диагональная адресация видела здесь «перекрёсток
	# сетки (64, 64)» и штрафовала по фазе несуществующего светофора.
	assert_bool(_city.on_road(PHANTOM_X, PHANTOM_Z, 0.0))\
		.override_failure_message(
			"точка (%.0f, %.0f) обязана быть на полотне — иначе тест ничего не проверяет"
			% [PHANTOM_X, PHANTOM_Z])\
		.is_true()
	var p := _police_real(
		_mgr_with_cop(PHANTOM_X + COP_OFFSET, PHANTOM_Z), _open_plan())
	Game.set_money(50000)
	var fined := _fined_ids(p)
	var t := 0.0
	while t < NodeSignalController.CYCLE:
		_signals.time = t
		p.update(DT, PHANTOM_X, 0.0, PHANTOM_Z, true, SPEED_RED_ONLY, 0.0)
		t += PHASE_SCAN_STEP
	assert_array(fined)\
		.override_failure_message(
			"у узла kra_bua (%.0f, %.0f) светофора нет — за весь цикл 16 с не должно быть ни одного штрафа"
			% [PHANTOM_X, PHANTOM_Z])\
		.is_empty()


# --- Дека путепровода: y_hint для on_road ------------------------------------

func test_deck_reads_as_off_road_without_the_height_hint() -> void:
	_real_city()
	assert_bool(_city.on_road(DECK_X, DECK_Z))\
		.override_failure_message(
			"без y_hint запрос идёт с отметки рельефа, и дека (%.0f, %.0f) читается как «не дорога» — это и есть причина правки"
			% [DECK_X, DECK_Z])\
		.is_false()
	assert_bool(_city.on_road(DECK_X, DECK_Z, PyatigorskTopology.OVERPASS_DECK_Y))\
		.override_failure_message("с y_hint = 6.5 м дека обязана читаться как дорога")\
		.is_true()


func test_speeding_is_caught_on_the_bridge_deck() -> void:
	_real_city()
	var p := _police_real(
		_mgr_with_cop(DECK_X + COP_OFFSET, DECK_Z), _open_plan())
	Game.set_money(50000)
	p.update(DT, DECK_X, PyatigorskTopology.OVERPASS_DECK_Y, DECK_Z, true,
		SPEED_OVER, 0.0)
	assert_int(p.wanted_level)\
		.override_failure_message(
			"превышение на деке путепровода (%.0f, %.0f, +6.5) обязано караться так же, как на земле"
			% [DECK_X, DECK_Z])\
		.is_equal(1)


func test_deck_speeding_is_missed_when_the_height_is_dropped() -> void:
	# Контроль к предыдущему тесту: с высотой рельефа вместо своей игрок на
	# деке снова читается как «не на дороге», и проверка молча выходит.
	_real_city()
	var p := _police_real(
		_mgr_with_cop(DECK_X + COP_OFFSET, DECK_Z), _open_plan())
	Game.set_money(50000)
	p.update(DT, DECK_X, 0.0, DECK_Z, true, SPEED_OVER, 0.0)
	assert_int(p.wanted_level)\
		.override_failure_message(
			"с высотой 0 на деке нарушение не фиксируется — иначе тест выше ничего не доказывает")\
		.is_equal(0)
