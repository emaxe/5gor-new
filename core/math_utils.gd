class_name MathUtils
extends RefCounted
## Математика, используемая генератором рельефа и физикой.
## Порт хелперов из utils.js.

## Гладкий минимум (полиномиальный, C¹) — сопряжение форм рельефа без излома.
static func smin(a: float, b: float, k: float) -> float:
	var h: float = maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - h * h * k * 0.25


static func smax(a: float, b: float, k: float) -> float:
	return -smin(-a, -b, k)


## Кадронезависимый экспоненциальный лерп.
##
## В оригинале часть демпферов написана как lerp(x, y, 0.15) — такой шаг
## зависит от частоты кадров. Здесь коэффициент задаётся как доля,
## отрабатываемая за 1/60 с, и корректируется под фактический dt.
static func damp(from: float, to: float, factor_per_60hz: float, delta: float) -> float:
	var t := 1.0 - pow(1.0 - factor_per_60hz, delta * 60.0)
	return from + (to - from) * t


static func damp_vec(from: Vector3, to: Vector3, factor_per_60hz: float,
		delta: float) -> Vector3:
	var t := 1.0 - pow(1.0 - factor_per_60hz, delta * 60.0)
	return from + (to - from) * t


## Демпфер в форме оригинала: lerp(a, b, 1 - k^dt). Уже кадронезависим.
static func damp_pow(from: float, to: float, k: float, delta: float) -> float:
	return from + (to - from) * (1.0 - pow(k, delta))


## Расстояние в плоскости XZ.
static func dist_2d(ax: float, az: float, bx: float, bz: float) -> float:
	var dx := ax - bx
	var dz := az - bz
	return sqrt(dx * dx + dz * dz)


## Числовой ключ пространственного хеша.
##
## Оригинал склеивал строку "cx,cz" — это десятки конкатенаций за кадр
## в горячих циклах коллизий. Диапазон ±512 ячеек покрывает мир с запасом.
static func hash_key(cx: int, cz: int) -> int:
	return (cx + 512) * 1024 + (cz + 512)
