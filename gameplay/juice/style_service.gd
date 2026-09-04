class_name StyleService
extends RefCounted
## Бонусные механики вождения: дрифт, идеальная остановка, опасное сближение
## (near-miss), комбо заказов. Порт game.js:1491-1690 поверх StyleConfig.
##
## Чистая логика без нод и сцены — как CarPhysics/PoliceManager, чтобы формулы
## можно было сверять юнит-тестами напрямую с оригиналом.
##
## Идеальная остановка сознательно исправлена относительно оригинала: там
## условие `braking` требовало скорость >= perfect_stop_min_speed КАЖДЫЙ
## кадр, поэтому фаза торможения обрывалась в момент пересечения этого
## порога — задолго до скорости <= 0.8, и награда была математически
## недостижима. Здесь порог проверяется один раз, в момент начала
## торможения (решение пользователя, см. tests/unit/test_style_service.gd).

var cfg: StyleConfig

var _drift_duration := 0.0
var _drift_dist := 0.0

var _ps_active := false
var _ps_max_decel := 0.0
var _ps_prev_speed := 0.0
var _ps_pending := false
var _ps_pending_decel := 0.0

var _nm_streak := 0
var _nm_last_time := 0.0

var _combo_streak := 0


func _init(config: StyleConfig) -> void:
	cfg = config


# --- Дрифт -------------------------------------------------------------------

## Возвращает {} пока занос продолжается или не набрал минимальную длительность;
## иначе {"reward", "duration", "dist", "style_bonus"} в кадре завершения заноса.
func update_drift(dt: float, handbrake: bool, slip: float, speed: float,
		has_passenger: bool) -> Dictionary:
	var is_drifting := handbrake and slip >= cfg.drift_min_slip and speed >= cfg.drift_min_speed
	if is_drifting:
		_drift_duration += dt
		_drift_dist += speed * dt
		return {}

	var result := {}
	if _drift_duration >= cfg.drift_min_duration:
		var extra_time := _drift_duration - cfg.drift_min_duration
		var reward := mini(cfg.drift_max_reward,
			roundi(cfg.drift_base_reward + extra_time * cfg.drift_reward_per_sec))
		result = {
			"reward": reward,
			"duration": _drift_duration,
			"dist": _drift_dist,
			"style_bonus": cfg.drift_style_bonus if has_passenger else 0.0,
		}
	_drift_duration = 0.0
	_drift_dist = 0.0
	return result


# --- Идеальная остановка -------------------------------------------------------

## eligible — есть активный заказ с пассажиром на борту (гейт применяется в
## момент фиксации остановки, как в оригинале).
func update_perfect_stop(dt: float, speed: float, braking: bool, eligible: bool) -> void:
	if dt <= 0.0001:
		_ps_prev_speed = speed
		return

	var decel := (_ps_prev_speed - speed) / dt
	if braking:
		# Новая фаза торможения обнуляет ещё не потреблённый флаг вне
		# зависимости от того, наберёт ли эта фаза порог скорости.
		_ps_pending = false
		if not _ps_active:
			if speed < cfg.perfect_stop_min_speed:
				# Тормозить начали, уже двигаясь медленно — "остановка с
				# места" не считается (game.js CFG.perfectStopMinSpeed).
				_ps_prev_speed = speed
				return
			_ps_active = true
			_ps_max_decel = 0.0
		if decel > _ps_max_decel:
			_ps_max_decel = decel
	elif _ps_active:
		_ps_active = false
		if speed <= 0.8 and _ps_max_decel > 0.0 and _ps_max_decel <= cfg.perfect_stop_max_decel \
				and eligible:
			_ps_pending = true
			_ps_pending_decel = _ps_max_decel

	_ps_prev_speed = speed


func has_pending_perfect_stop() -> bool:
	return _ps_pending


## Списывает и возвращает {"reward", "decel"}; {} если наградить нечего.
func consume_perfect_stop() -> Dictionary:
	if not _ps_pending:
		return {}
	_ps_pending = false
	return {"reward": cfg.perfect_stop_reward, "decel": _ps_pending_decel}


## Заказ провалился — заслуженная, но ещё не выданная остановка сгорает.
func cancel_perfect_stop() -> void:
	_ps_pending = false


# --- Near-miss -----------------------------------------------------------------

## Геометрическая проверка одной сущности (машина или пешеход) на близкий
## проезд без касания. rc/sep — половина ширины и продольное смещение
## передней/задней точек капсулы игрока (CarShapeData.capsule_radius/sep).
## Возвращает {} (ничего не изменилось), {"hit": true} (контакт — гасим
## детектор), {"triggered": true, "passed": true} (свежий near-miss) или
## {"clear_flags": true} (сущность ушла достаточно далеко — можно засчитать
## сближение с ней заново при следующем проезде).
func evaluate_near_miss(ex: float, ez: float, px: float, pz: float, fwd_x: float, fwd_z: float,
		rc: float, sep: float, e_radius: float, margin: float, player_speed: float,
		was_passed: bool, was_hit: bool) -> Dictionary:
	if player_speed < cfg.near_miss_min_speed:
		return {}

	var e := Vector2(ex, ez)
	var d0 := e.distance_to(Vector2(px + fwd_x * sep, pz + fwd_z * sep))
	var d1 := e.distance_to(Vector2(px, pz))
	var d2 := e.distance_to(Vector2(px - fwd_x * sep, pz - fwd_z * sep))
	var min_d := minf(d0, minf(d1, d2))
	var clearance := min_d - (rc + e_radius)

	if clearance <= 0.0:
		return {"hit": true}
	if clearance > margin + cfg.near_miss_reset_dist:
		if was_passed or was_hit:
			return {"clear_flags": true}
		return {}
	if not was_passed and not was_hit and clearance <= margin:
		return {"triggered": true, "passed": true}
	return {}


## Начисление за подтверждённый near-miss + серия. now — shift_elapsed на
## момент вызова (единица времени серии, как shiftElapsed в оригинале).
func trigger_near_miss(is_ped: bool, now: float) -> Dictionary:
	if _nm_streak > 0 and (now - _nm_last_time) <= cfg.near_miss_streak_window:
		_nm_streak += 1
	else:
		_nm_streak = 1
	_nm_last_time = now

	var mult := cfg.near_miss_mult(_nm_streak)
	return {
		"is_ped": is_ped,
		"streak": _nm_streak,
		"mult": mult,
		"reward": cfg.near_miss_reward * mult,
		"level": cfg.near_miss_level(_nm_streak),
	}


# --- Комбо заказов --------------------------------------------------------------

## Заказ завершён — инкремент серии и бонус-оплата поверх базовой (pay).
func register_order_completed(pay: int) -> Dictionary:
	_combo_streak += 1
	var mult := cfg.combo_mult(_combo_streak)
	return {
		"streak": _combo_streak,
		"mult": mult,
		"bonus_pay": roundi(pay * mult) - pay,
	}


## Только серия заказов — используется при штрафе полиции (game.js:472).
func reset_combo() -> void:
	_combo_streak = 0


## Полный сброс: авария/наезд на пешехода обрывают все текущие серии и
## недособранные бонусы (game.js:380-401).
func reset_streaks() -> void:
	_combo_streak = 0
	_drift_duration = 0.0
	_drift_dist = 0.0
	_ps_active = false
	_ps_max_decel = 0.0
	_ps_pending = false
	_nm_streak = 0
	_nm_last_time = 0.0
