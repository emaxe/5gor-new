extends GdUnitTestSuite
## Спецификация пешего режима игрока.
##
## Проверяет ключевые правила оригинала (playerped.js / game.js):
## 1. Выход из машины только на скорости <= 1.5 м/с через левую дверь.
## 2. Посадка в машину в радиусе <= 3.0 м.
## 3. Скорости ходьбы (3.1 м/с) и бега (5.8 м/с).
## 4. Прыжок (6.5 м/с при гравитации 20 м/с²), кулдаун и приземление.
## 5. Удар кулаком: радиус 2.0 м, конус 60°, кулдаун 0.8 с.
## 6. Урон: оглушение 0.6 с, нокаут 2.0 с при 0 HP и автоматическое восстановление.
## 7. Кламп по границам города (±308 м) и серпантина Машука.

const DT := 1.0 / 60.0

var _config: PedConfig
var _logic: PlayerPedLogic


func before_test() -> void:
	_config = PedConfig.new()
	_logic = PlayerPedLogic.new()
	_logic.init_with_config(_config)


# --- Выход и посадка в машину -----------------------------------------------

func test_exit_car_speed_threshold() -> void:
	assert_bool(PlayerPedLogic.can_exit_car(0.0, _config)).is_true()
	assert_bool(PlayerPedLogic.can_exit_car(1.5, _config)).is_true()
	assert_bool(PlayerPedLogic.can_exit_car(-1.5, _config)).is_true()
	assert_bool(PlayerPedLogic.can_exit_car(1.51, _config)).is_false()
	assert_bool(PlayerPedLogic.can_exit_car(10.0, _config)).is_false()


func test_exit_offsets_are_on_left_side_of_vehicle() -> void:
	var car_pos := Vector3(10.0, 0.0, 20.0)
	# Heading = 0 (авто смотрит в +Z). Левая сторона — это -X.
	var offsets: Array[Vector3] = PlayerPedLogic.get_exit_offsets(car_pos, 0.0)
	assert_int(offsets.size()).is_equal(4)

	# Оффсеты должны быть 1.5, 2.0, 2.5, 3.0 м
	var expected_dists := [1.5, 2.0, 2.5, 3.0]
	for i in offsets.size():
		var p: Vector3 = offsets[i]
		assert_float(p.z).is_equal_approx(car_pos.z, 0.001)
		assert_float(p.x).is_equal_approx(car_pos.x - expected_dists[i], 0.001)

	# Heading = PI/2 (авто смотрит в +X). Левая сторона — это +Z.
	var offsets_90: Array[Vector3] = PlayerPedLogic.get_exit_offsets(car_pos, PI * 0.5)
	for i in offsets_90.size():
		var p: Vector3 = offsets_90[i]
		assert_float(p.x).is_equal_approx(car_pos.x, 0.001)
		assert_float(p.z).is_equal_approx(car_pos.z + expected_dists[i], 0.001)


func test_enter_car_distance_threshold() -> void:
	var car_pos := Vector3(0.0, 0.0, 0.0)
	assert_bool(PlayerPedLogic.can_enter_car(Vector3(2.5, 0.0, 0.0), car_pos, _config)).is_true()
	assert_bool(PlayerPedLogic.can_enter_car(Vector3(3.0, 0.0, 0.0), car_pos, _config)).is_true()
	assert_bool(PlayerPedLogic.can_enter_car(Vector3(3.1, 0.0, 0.0), car_pos, _config)).is_false()
	assert_bool(PlayerPedLogic.can_enter_car(Vector3(0.0, 0.0, 5.0), car_pos, _config)).is_false()


# --- Скорости ходьбы и бега -------------------------------------------------

func test_walk_and_run_speeds() -> void:
	_logic.set_pos(0.0, 0.0, 0.0)
	var move_vec := Vector3(0.0, 0.0, 1.0)

	# Обычная ходьба без спринта (Shift = false)
	_logic.step_motion(move_vec, false, _config, DT)
	assert_float(_logic.speed).is_equal_approx(3.1, 0.01)
	assert_bool(_logic.is_running).is_false()

	# Бег со спринтом (Shift = true)
	_logic.step_motion(move_vec, true, _config, DT)
	assert_float(_logic.speed).is_equal_approx(5.8, 0.01)
	assert_bool(_logic.is_running).is_true()


func test_turn_towards_movement_direction() -> void:
	_logic.set_pos(0.0, 0.0, 0.0) # смотрит в +Z (heading = 0)
	var move_right := Vector3(1.0, 0.0, 0.0) # нужно повернуться на +X (heading = PI/2)

	# За 1 кадр поворот ограничен turn_rate * DT = 14.0 * DT ~ 0.233 рад
	_logic.step_motion(move_right, false, _config, DT)
	assert_float(_logic.heading).is_greater(0.2)
	assert_float(_logic.heading).is_less(PI * 0.5)

	# За полсекунды (30 кадров) должен полностью довернуться
	for i in 30:
		_logic.step_motion(move_right, false, _config, DT)
	assert_float(_logic.heading).is_equal_approx(PI * 0.5, 0.01)


# --- Прыжок и вертикальное перемещение ---------------------------------------

func test_jump_mechanics_and_gravity() -> void:
	_logic.set_pos(0.0, 0.0, 0.0)
	assert_bool(_logic.jump(_config)).is_true()
	assert_float(_logic.vy).is_equal_approx(6.5, 0.01)
	assert_float(_logic.jump_cd).is_equal_approx(0.25, 0.01)

	# Повторный прыжок в воздухе не срабатывает
	assert_bool(_logic.jump(_config)).is_false()

	# Симулируем полёт вверх и падение вниз
	var peak_height := 0.0
	for i in 60: # 1 секунда полёта
		_logic.step_vertical(_config, DT)
		peak_height = maxf(peak_height, _logic.y_off)

	# Пик высоты: v^2 / (2g) = 6.5^2 / 40 = 1.056 м
	assert_float(peak_height).is_between(1.0, 1.1)

	# После 1 секунды персонаж обязан вернуться на землю
	assert_float(_logic.y_off).is_equal_approx(0.0, 0.001)
	assert_float(_logic.vy).is_equal_approx(0.0, 0.001)


# --- Удар кулаком и сектор поражения -----------------------------------------

func test_punch_cooldown_and_timing() -> void:
	_logic.set_pos(0.0, 0.0, 0.0)
	assert_bool(_logic.punch(_config)).is_true()
	assert_float(_logic.punch_cd).is_equal_approx(0.8, 0.01)
	assert_float(_logic.punch_anim_t).is_equal_approx(0.3, 0.01)

	# Повторный удар во время кулдауна отклонён
	assert_bool(_logic.punch(_config)).is_false()

	# Проматываем время кулдауна
	_logic.advance_timers(0.8)
	assert_float(_logic.punch_cd).is_equal_approx(0.0, 0.001)
	assert_bool(_logic.punch(_config)).is_true()


func test_punch_cone_angle_and_distance() -> void:
	var attacker_pos := Vector3(0.0, 0.0, 0.0)
	var attacker_heading := 0.0 # смотрит в +Z

	# 1. Прямо перед игроком на дистанции 1.5 м (< 2.0 м) -> ПОПАДАНИЕ
	assert_bool(PlayerPedLogic.is_target_in_punch_cone(attacker_pos, attacker_heading,
		Vector3(0.0, 0.0, 1.5), 2.0, PI / 3.0)).is_true()

	# 2. Под углом 45° (< 60°) на дистанции 1.5 м -> ПОПАДАНИЕ
	var p_45 := Vector3(sin(PI * 0.25), 0.0, cos(PI * 0.25)) * 1.5
	assert_bool(PlayerPedLogic.is_target_in_punch_cone(attacker_pos, attacker_heading,
		p_45, 2.0, PI / 3.0)).is_true()

	# 3. Под углом 75° (> 60°) на дистанции 1.5 м -> ПРОМАХ (вне конуса)
	var p_75 := Vector3(sin(PI * 0.41), 0.0, cos(PI * 0.41)) * 1.5
	assert_bool(PlayerPedLogic.is_target_in_punch_cone(attacker_pos, attacker_heading,
		p_75, 2.0, PI / 3.0)).is_false()

	# 4. Прямо перед игроком, но на дистанции 2.5 м (> 2.0 м) -> ПРОМАХ (слишком далеко)
	assert_bool(PlayerPedLogic.is_target_in_punch_cone(attacker_pos, attacker_heading,
		Vector3(0.0, 0.0, 2.5), 2.0, PI / 3.0)).is_false()


# --- Урон, оглушение и нокаут ------------------------------------------------

func test_damage_stun_and_knockout() -> void:
	_logic.set_pos(0.0, 0.0, 0.0)
	assert_int(_logic.hp).is_equal(3)

	# 1 урон: стан 0.6 с, не нокаут
	var ko1: bool = _logic.take_hit(0.0, -1.0, 1, _config)
	assert_bool(ko1).is_false()
	assert_int(_logic.hp).is_equal(2)
	assert_float(_logic.stun_t).is_equal_approx(0.6, 0.01)
	assert_float(_logic.knock_t).is_equal_approx(0.25, 0.01)
	assert_float(_logic.knock_vz).is_greater(0.0) # отбросило в +Z

	# Во время стана персонаж не может двигаться или прыгать
	assert_bool(_logic.jump(_config)).is_false()
	assert_bool(_logic.punch(_config)).is_false()

	# Смертельный урон: нокаут 2.0 с
	var ko2: bool = _logic.take_hit(0.0, -1.0, 2, _config)
	assert_bool(ko2).is_true()
	assert_int(_logic.hp).is_equal(0)
	assert_bool(_logic.is_knocked_out).is_true()
	assert_float(_logic.stun_t).is_equal_approx(2.0, 0.01)

	# После истечения времени нокаута здоровье восстанавливается до максимума
	_logic.advance_timers(2.0)
	assert_bool(_logic.is_knocked_out).is_false()
	assert_int(_logic.hp).is_equal(3)


# --- Границы мира ------------------------------------------------------------

func test_bounds_clamping() -> void:
	# Центр города ограничен [-308, 308]
	var c1: Vector2 = PlayerPedLogic.clamp_bounds(350.0, 0.0)
	assert_float(c1.x).is_equal(308.0)
	assert_float(c1.y).is_equal(0.0)

	var c2: Vector2 = PlayerPedLogic.clamp_bounds(0.0, -350.0) # внутри коридора Машука (|x| <= 85)
	assert_float(c2.x).is_equal(0.0)
	assert_float(c2.y).is_equal(-350.0)

	var c3: Vector2 = PlayerPedLogic.clamp_bounds(120.0, -350.0) # вне коридора Машука
	assert_float(c3.x).is_equal(120.0)
	assert_float(c3.y).is_equal(-308.0)
