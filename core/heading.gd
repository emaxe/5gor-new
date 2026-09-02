class_name Heading
extends RefCounted
## Конвертация между соглашением «вперёд» оригинала (Three.js) и Godot.
##
## В JS-оригинале курс — скаляр `heading`, где 0 = +Z и
## `fwd = (sin(h), cos(h))`, `lat = (-cos(h), sin(h))`.
##
## Меши проекта авторятся носом в **+Z**, как в оригинале: тогда
## `basis_of(h)` — это простой поворот вокруг Y, и геометрия, физика и
## данные говорят на одном языке. Плата — `look_at()` для машин не
## применим (он направляет -Z), но он им и не нужен.

## Единичный вектор «вперёд» для курса h (0 = +Z), совпадает с JS fwd.
static func forward(h: float) -> Vector3:
	return Vector3(sin(h), 0.0, cos(h))


## Единичный вектор «вправо» (латеральная ось), совпадает с JS lat.
static func lateral(h: float) -> Vector3:
	return Vector3(-cos(h), 0.0, sin(h))


## Базис для меша, авторенного носом в +Z.
static func basis_of(h: float) -> Basis:
	return Basis(Vector3.UP, h)


## Базис для меша, авторенного носом в -Z (нативная ориентация Godot).
static func basis_of_neg_z(h: float) -> Basis:
	return Basis(Vector3.UP, h + PI)


## Курс из вектора направления в плоскости XZ (обратно к forward()).
static func from_vector(v: Vector3) -> float:
	return atan2(v.x, v.z)


## Кратчайшая разница углов в диапазоне (-PI, PI].
static func delta(from: float, to: float) -> float:
	return wrapf(to - from, -PI, PI)


## Поворот `from` к `to` не более чем на `max_step` радиан.
## Порт turnToward() из utils.js.
static func turn_toward(from: float, to: float, max_step: float) -> float:
	var d := delta(from, to)
	if absf(d) <= max_step:
		return to
	return from + signf(d) * max_step
