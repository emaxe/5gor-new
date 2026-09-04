class_name CarPhysics
extends RefCounted
## Аркадная кинематика машины игрока. Дословный порт PlayerCar.update()
## (player.js:217-299).
##
## VehicleBody3D сознательно не используется: он симулирует подвеску и трение
## колёс, из-за чего занос от ручника при grip 0.28 и мгновенный отклик руля
## воспроизвести невозможно — получилась бы другая игра. Здесь та же
## полу-неявная схема Эйлера, что в оригинале, но с фиксированным шагом
## физики Godot (1/60) вместо переменного dt.
##
## Класс чистый: ни нод, ни рендера. Поэтому телеметрию (разгон, тормозной
## путь, радиус разворота) можно сверять с оригиналом в юнит-тестах.

## Сопротивление качению при отпущенных педалях, м/с².
const COAST_DRAG := 3.5
## Торможение двигателем, когда мотор мёртв.
const DEAD_ENGINE_DRAG := 6.0
## Максимальная скорость заднего хода, м/с.
const REVERSE_MAX := 7.0
## Скорость, при которой руль выходит на полную эффективность, м/с.
const STEER_FULL_SPEED := 12.0
## Ослабление руля на высокой скорости.
const STEER_SPEED_FALLOFF := 1.6
## Ручник обостряет руль.
const HANDBRAKE_STEER_GAIN := 1.5
## И почти отключает боковое сцепление — это и есть занос.
const HANDBRAKE_GRIP := 0.28
## Скорость гашения боковой скорости сцеплением.
const GRIP_DECAY := 2.2
## Самовыравнивание при отпущенном руле.
const SELF_ALIGN := 0.06
## Делитель боковой скорости в формуле пробуксовки.
const SLIP_DIVISOR := 8.0

## Сцепление вне дороги и на склоне.
const OFFROAD_GRIP := 0.55
const SLOPE_GRIP := 0.85
## Высота, выше которой считаем, что машина на склоне.
const SLOPE_HEIGHT := 0.5

## Расход топлива: постоянная составляющая и зависящая от скорости.
const FUEL_IDLE := 0.11
const FUEL_SPEED := 0.10
## Скорость загрязнения кузова.
const DIRT_RATE := 0.0012

## Пороги визуальных кренов кузова (на физику не влияют).
const ROLL_PER_LAT := 0.018
const ROLL_LIMIT := 0.07
const PITCH_PER_ACCEL := 0.0011
const PITCH_LIMIT := 0.06


## Мгновенное состояние движения. Отдельно от CarRuntime: здесь только то,
## что меняется каждый физический тик.
class Motion extends RefCounted:
	var heading := 0.0
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	## Продольная и боковая проекции скорости.
	var forward_speed := 0.0
	var lateral_speed := 0.0
	## Модуль скорости, м/с.
	var speed := 0.0
	## Ускорение этого тика — нужно для клевка кузова и оценки стиля езды.
	var accel_value := 0.0
	## Пробуксовка: |боковая| / 8 плюс вклад ручника.
	var slip := 0.0
	## Цели визуальных кренов.
	var target_roll := 0.0
	var target_pitch := 0.0


## Условия под колёсами.
class Surface extends RefCounted:
	var on_road := true
	## Высота земли в точке — по ней определяется склон.
	var ground_height := 0.0
	## Множитель сцепления от погоды.
	var weather_grip := 1.0


## Один шаг интегрирования. Мутирует motion.
static func step(motion: Motion, axes: Inp.DriveAxes, surface: Surface,
		stats: CarStats, engine_dead: bool, delta: float) -> void:
	var fwd := Heading.forward(motion.heading)
	var lat := Heading.lateral(motion.heading)
	var fwd_speed := motion.velocity.dot(fwd)
	var lat_speed := motion.velocity.dot(lat)

	var grip_mul := (1.0 if surface.on_road else OFFROAD_GRIP) \
		* (SLOPE_GRIP if surface.ground_height > SLOPE_HEIGHT else 1.0)

	# --- Педали ---
	var accel_value := 0.0
	if not engine_dead:
		if axes.throttle > 0.0:
			accel_value += stats.accel * axes.throttle
		if axes.brake > 0.0:
			# Ниже 0.5 м/с тормоз становится задним ходом.
			if fwd_speed > 0.5:
				accel_value -= stats.brake * axes.brake
			else:
				accel_value -= stats.accel * 0.6 * axes.brake
		if is_zero_approx(axes.throttle) and is_zero_approx(axes.brake):
			if absf(fwd_speed) <= COAST_DRAG * delta * 1.5:
				fwd_speed = 0.0
				accel_value = 0.0
			else:
				accel_value -= signf(fwd_speed) * COAST_DRAG
	else:
		if absf(fwd_speed) <= DEAD_ENGINE_DRAG * delta * 1.5:
			fwd_speed = 0.0
			accel_value = 0.0
		else:
			accel_value -= signf(fwd_speed) * DEAD_ENGINE_DRAG

	fwd_speed += accel_value * delta
	if is_zero_approx(axes.throttle) and is_zero_approx(axes.brake) and absf(fwd_speed) < 0.01:
		fwd_speed = 0.0
		accel_value = 0.0
	fwd_speed = clampf(fwd_speed, -REVERSE_MAX, stats.max_speed)

	# --- Руление ---
	var speed_factor: float = clampf(absf(fwd_speed) / STEER_FULL_SPEED, 0.0, 1.0)
	var steer_rate := stats.steer * speed_factor \
		* (1.0 - absf(fwd_speed) / (stats.max_speed * STEER_SPEED_FALLOFF))
	if axes.handbrake and absf(fwd_speed) > 4.0:
		steer_rate *= HANDBRAKE_STEER_GAIN
	# Задним ходом руль инвертируется: корма едет туда, куда «показывает» руль.
	var steer_dir := -1.0 if fwd_speed < -0.1 else 1.0
	motion.heading -= axes.steer * steer_rate * delta * grip_mul * steer_dir
	if is_zero_approx(axes.steer):
		motion.heading += lat_speed * SELF_ALIGN * delta * grip_mul

	# --- Сцепление и занос ---
	var grip := grip_mul * surface.weather_grip * stats.grip \
		* (HANDBRAKE_GRIP if axes.handbrake else 1.0)
	lat_speed *= maxf(0.0, 1.0 - grip * GRIP_DECAY * delta)
	if absf(lat_speed) < 0.005:
		lat_speed = 0.0

	motion.slip = absf(lat_speed) / SLIP_DIVISOR
	if axes.handbrake and absf(fwd_speed) > 5.0:
		motion.slip += 0.5

	# --- Крены кузова (чистая визуализация) ---
	motion.target_roll = clampf(-lat_speed * ROLL_PER_LAT, -ROLL_LIMIT, ROLL_LIMIT)
	motion.target_pitch = clampf(-accel_value * PITCH_PER_ACCEL,
		-PITCH_LIMIT, PITCH_LIMIT)

	# --- Интегрирование ---
	# Скорость собирается по базису, взятому ДО поворота руля — ровно как в
	# оригинале (player.js:270). Пересчёт базиса после поворота даёт более
	# «острый» руль и уводит телеметрию от эталона, а на ней держится всё
	# ощущение управления и калибровка дрифта с near-miss.
	motion.velocity = fwd * fwd_speed + lat * lat_speed
	motion.position += motion.velocity * delta
	motion.forward_speed = fwd_speed
	motion.lateral_speed = lat_speed
	motion.speed = motion.velocity.length()
	motion.accel_value = accel_value


## Расход топлива за тик, в единицах бака.
static func fuel_burn(motion: Motion, stats: CarStats, delta: float) -> float:
	return (FUEL_IDLE + FUEL_SPEED * absf(motion.forward_speed) / stats.max_speed) \
		* delta


## Прирост загрязнения кузова за тик, 0..1.
static func dirt_gain(motion: Motion, delta: float) -> float:
	return delta * DIRT_RATE * (1.0 + motion.speed / 20.0)


## Резкость управления для оценки стиля езды пассажиром (player.js:288).
static func jerk(motion: Motion) -> float:
	return minf(1.0, absf(motion.accel_value) / 40.0) * 0.7 \
		+ minf(1.0, motion.slip) * 0.5
