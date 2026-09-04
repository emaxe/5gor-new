extends GdUnitTestSuite
## Juice: дрифт, идеальная остановка, near-miss + серии, комбо заказов (Этап 12).
## Пороги и формулы — порт game.js:1491-1690 / config.js:196-229 (StyleConfig).
##
## «Идеальная остановка» в оригинале математически недостижима: условие
## braking требовало скорость >=7.0 непрерывно, поэтому фаза торможения
## обрывалась в момент пересечения порога 7.0, задолго до скорости <=0.8.
## Здесь это осознанно исправлено: порог скорости проверяется один раз, в
## момент НАЧАЛА торможения, а не на каждом кадре (решение пользователя).

const StyleServiceScript = preload("res://gameplay/juice/style_service.gd")

const DT := 1.0 / 60.0

var _cfg: StyleConfig


func before_test() -> void:
	_cfg = Db.balance.style


func _svc() -> RefCounted:
	return StyleServiceScript.new(_cfg)


# --- Дрифт -------------------------------------------------------------------

func test_drift_no_reward_below_min_duration() -> void:
	var svc := _svc()
	# 0.5 c заноса — короче drift_min_duration (0.8 c).
	for i in 30:
		svc.update_drift(DT, true, 0.9, 10.0, true)
	var result: Dictionary = svc.update_drift(DT, false, 0.0, 10.0, true)
	assert_that(result.is_empty()).is_true()


func test_drift_reward_at_threshold_duration() -> void:
	var svc := _svc()
	# Ровно drift_min_duration (0.8 c = 48 кадров при 60 fps).
	for i in 48:
		svc.update_drift(DT, true, 0.9, 10.0, true)
	var result: Dictionary = svc.update_drift(DT, false, 0.0, 10.0, true)
	assert_that(result.get("reward", 0)).is_equal(_cfg.drift_base_reward)


func test_drift_reward_grows_with_duration_and_caps_at_max() -> void:
	var svc := _svc()
	# extra_time нужно >= (200-40)/50 = 3.2 c сверх порога 0.8 c, берём с запасом.
	var frames := ceili((_cfg.drift_min_duration + 5.0) / DT)
	for i in frames:
		svc.update_drift(DT, true, 0.9, 10.0, true)
	var result: Dictionary = svc.update_drift(DT, false, 0.0, 10.0, true)
	assert_that(result.get("reward", 0)).is_equal(_cfg.drift_max_reward)


func test_drift_reward_not_gated_by_passenger() -> void:
	var svc := _svc()
	for i in 48:
		svc.update_drift(DT, true, 0.9, 10.0, false)
	var result: Dictionary = svc.update_drift(DT, false, 0.0, 10.0, false)
	assert_that(result.get("reward", 0)).is_greater(0)
	assert_that(result.get("style_bonus", -1.0)).is_equal(0.0)


func test_drift_style_bonus_only_with_passenger() -> void:
	var svc := _svc()
	for i in 48:
		svc.update_drift(DT, true, 0.9, 10.0, true)
	var result: Dictionary = svc.update_drift(DT, false, 0.0, 10.0, true)
	assert_that(result.get("style_bonus", 0.0)).is_equal_approx(_cfg.drift_style_bonus, 0.001)


func test_drift_requires_handbrake_and_min_speed_and_slip() -> void:
	var svc := _svc()
	for i in 60:
		# Скорость ниже drift_min_speed — не считается заносом.
		svc.update_drift(DT, true, 0.9, 3.0, true)
	var result: Dictionary = svc.update_drift(DT, false, 0.0, 3.0, true)
	assert_that(result.is_empty()).is_true()


# --- Идеальная остановка ------------------------------------------------------

## Симулирует плавное торможение от start_speed до 0 с постоянным замедлением.
func _brake_to_stop(svc: RefCounted, start_speed: float, decel: float, eligible: bool) -> void:
	var speed := start_speed
	while speed > 0.0:
		speed = maxf(0.0, speed - decel * DT)
		svc.update_perfect_stop(DT, speed, true, eligible)
	# отпустили тормоз на скорости 0 — фиксируем завершение
	svc.update_perfect_stop(DT, speed, false, eligible)


func test_perfect_stop_pending_after_gentle_braking_from_above_threshold() -> void:
	var svc := _svc()
	# 8 м/с -> 0 при замедлении 5 м/с² (меньше потолка 9.5) — должно засчитаться.
	_brake_to_stop(svc, 8.0, 5.0, true)
	assert_that(svc.has_pending_perfect_stop()).is_true()


func test_perfect_stop_not_pending_when_decel_too_harsh() -> void:
	var svc := _svc()
	# Экстренное торможение — пиковое замедление выше потолка 9.5 м/с².
	_brake_to_stop(svc, 8.0, 20.0, true)
	assert_that(svc.has_pending_perfect_stop()).is_false()


func test_perfect_stop_not_pending_when_started_below_min_speed() -> void:
	var svc := _svc()
	# Начали тормозить, уже двигаясь медленно (3 м/с) — "остановка с места" не награждается.
	_brake_to_stop(svc, 3.0, 2.0, true)
	assert_that(svc.has_pending_perfect_stop()).is_false()


func test_perfect_stop_not_pending_without_active_order_or_passenger() -> void:
	var svc := _svc()
	_brake_to_stop(svc, 8.0, 5.0, false)
	assert_that(svc.has_pending_perfect_stop()).is_false()


func test_perfect_stop_consume_returns_reward_once() -> void:
	var svc := _svc()
	_brake_to_stop(svc, 8.0, 5.0, true)
	var result: Dictionary = svc.consume_perfect_stop()
	assert_that(result.get("reward", 0)).is_equal(_cfg.perfect_stop_reward)
	assert_that(svc.has_pending_perfect_stop()).is_false()
	assert_that(svc.consume_perfect_stop().is_empty()).is_true()


func test_perfect_stop_pending_cleared_by_new_braking_phase() -> void:
	var svc := _svc()
	_brake_to_stop(svc, 8.0, 5.0, true)
	assert_that(svc.has_pending_perfect_stop()).is_true()
	# Новая фаза торможения обнуляет ещё не потреблённый флаг (game.js:1553) —
	# резервируется только последняя успешная остановка.
	svc.update_perfect_stop(DT, 5.0, true, true)
	assert_that(svc.has_pending_perfect_stop()).is_false()


func test_perfect_stop_cancel_clears_pending_on_order_failed() -> void:
	var svc := _svc()
	_brake_to_stop(svc, 8.0, 5.0, true)
	assert_that(svc.has_pending_perfect_stop()).is_true()
	svc.cancel_perfect_stop()
	assert_that(svc.has_pending_perfect_stop()).is_false()


# --- Near-miss -----------------------------------------------------------------
# Геометрия общая для всех кейсов: игрок в начале координат смотрит вдоль +X
# (fwd=(1,0)), капсула rc=1.0, sep=2.0; сущность радиусом 0.5 стоит сбоку на
# ez, ex=0 (ближе всего центральный круг капсулы) -> зазор = ez - (rc+e_radius) = ez - 1.5.
const _RC := 1.0
const _SEP := 2.0
const _E_RADIUS := 0.5
const _COMBINED := _RC + _E_RADIUS # 1.5


func test_near_miss_no_trigger_below_min_speed() -> void:
	var svc := _svc()
	var ez := _COMBINED + _cfg.near_miss_car_margin * 0.5 # зазор был бы в окне...
	var r: Dictionary = svc.evaluate_near_miss(0.0, ez, 0.0, 0.0, 1.0, 0.0, _RC, _SEP, _E_RADIUS,
			_cfg.near_miss_car_margin, _cfg.near_miss_min_speed - 1.0, false, false)
	assert_that(r.get("triggered", false)).is_false()


func test_near_miss_triggers_within_margin_without_contact() -> void:
	var svc := _svc()
	var ez := _COMBINED + _cfg.near_miss_car_margin * 0.5 # зазор = margin/2, в окне
	var r: Dictionary = svc.evaluate_near_miss(0.0, ez, 0.0, 0.0, 1.0, 0.0, _RC, _SEP, _E_RADIUS,
			_cfg.near_miss_car_margin, _cfg.near_miss_min_speed, false, false)
	assert_that(r.get("triggered", false)).is_true()
	assert_that(r.get("passed", false)).is_true()
	assert_that(r.get("hit", false)).is_false()


func test_near_miss_marks_hit_on_contact_instead_of_trigger() -> void:
	var svc := _svc()
	var ez := _COMBINED - 0.5 # капсулы перекрываются -> контакт
	var r: Dictionary = svc.evaluate_near_miss(0.0, ez, 0.0, 0.0, 1.0, 0.0, _RC, _SEP, _E_RADIUS,
			_cfg.near_miss_car_margin, _cfg.near_miss_min_speed, false, false)
	assert_that(r.get("triggered", false)).is_false()
	assert_that(r.get("hit", false)).is_true()


func test_near_miss_does_not_retrigger_while_passed_flag_set() -> void:
	var svc := _svc()
	var ez := _COMBINED + _cfg.near_miss_car_margin * 0.5
	var r: Dictionary = svc.evaluate_near_miss(0.0, ez, 0.0, 0.0, 1.0, 0.0, _RC, _SEP, _E_RADIUS,
			_cfg.near_miss_car_margin, _cfg.near_miss_min_speed, true, false)
	assert_that(r.get("triggered", false)).is_false()


func test_near_miss_flags_reset_after_leaving_reset_distance() -> void:
	var svc := _svc()
	var ez := _COMBINED + _cfg.near_miss_car_margin + _cfg.near_miss_reset_dist + 1.0
	var r: Dictionary = svc.evaluate_near_miss(0.0, ez, 0.0, 0.0, 1.0, 0.0, _RC, _SEP, _E_RADIUS,
			_cfg.near_miss_car_margin, _cfg.near_miss_min_speed, true, true)
	assert_that(r.get("clear_flags", false)).is_true()


func test_near_miss_streak_multiplier_grows_with_tiers() -> void:
	var svc := _svc()
	var last: Dictionary = {}
	for i in _cfg.near_miss_streak_counts[-1]:
		last = svc.trigger_near_miss(false, float(i) * 0.1)
	assert_that(last.get("streak", 0)).is_equal(_cfg.near_miss_streak_counts[-1])
	assert_that(last.get("mult", 0.0)).is_equal_approx(_cfg.near_miss_streak_mults[-1], 0.001)
	assert_that(last.get("reward", 0.0)).is_equal_approx(
		_cfg.near_miss_reward * _cfg.near_miss_streak_mults[-1], 0.001)


func test_near_miss_streak_resets_after_window_expires() -> void:
	var svc := _svc()
	svc.trigger_near_miss(false, 0.0)
	svc.trigger_near_miss(false, 0.0)
	# Разрыв больше near_miss_streak_window (8 c) — серия обнуляется до 1.
	var r: Dictionary = svc.trigger_near_miss(false, _cfg.near_miss_streak_window + 1.0)
	assert_that(r.get("streak", 0)).is_equal(1)


# --- Комбо заказов -------------------------------------------------------------

func test_combo_streak_increments_and_applies_multiplier() -> void:
	var svc := _svc()
	svc.register_order_completed(1000)
	var r: Dictionary = svc.register_order_completed(1000)
	assert_that(r.get("streak", 0)).is_equal(2)
	assert_that(r.get("bonus_pay", 0)).is_equal(
		roundi(1000 * _cfg.combo_mult(2)) - 1000)


func test_combo_reset_clears_streak() -> void:
	var svc := _svc()
	svc.register_order_completed(1000)
	svc.reset_streaks()
	var r: Dictionary = svc.register_order_completed(1000)
	assert_that(r.get("streak", 0)).is_equal(1)


func test_reset_streaks_clears_near_miss_streak_too() -> void:
	var svc := _svc()
	svc.trigger_near_miss(false, 0.0)
	svc.reset_streaks()
	var r: Dictionary = svc.trigger_near_miss(false, 0.0)
	assert_that(r.get("streak", 0)).is_equal(1)


## Штраф полиции (police:fine) обрывает только комбо заказов, а не остальные
## серии стиля — game.js:472 сбрасывает исключительно comboStreak.
func test_reset_combo_does_not_touch_near_miss_streak() -> void:
	var svc := _svc()
	svc.register_order_completed(1000)
	svc.trigger_near_miss(false, 0.0)
	svc.reset_combo()
	var order_r: Dictionary = svc.register_order_completed(1000)
	var nm_r: Dictionary = svc.trigger_near_miss(false, 0.0)
	assert_that(order_r.get("streak", 0)).is_equal(1)
	assert_that(nm_r.get("streak", 0)).is_equal(2)
