class_name SeededRng
extends RefCounted
## Побитовый порт mulberry32 из utils.js:252.
##
## RandomNumberGenerator использовать нельзя: у неё другой алгоритм (PCG),
## и планировка города разошлась бы с эталоном оригинала.
##
## Важно: в оригинале сидирована только ЧАСТЬ генерации (this.rng), а размещение
## зданий, деревьев и пропсов идёт через несидированный Math.random() — то есть
## город там на самом деле разный при каждой загрузке. В порте через этот
## генератор проходит ВСЯ генерация: город становится выучиваемым, а сид
## сохраняется в слот (см. план, улучшение «world_seed»).

const MASK32 := 0xFFFFFFFF
const INV32 := 1.0 / 4294967296.0

var _a: int = 0


func _init(seed_value: int = 0) -> void:
	_a = seed_value & MASK32


func get_state() -> int:
	return _a


func set_state(state: int) -> void:
	_a = state & MASK32


## Порт Math.imul: низкие 32 бита произведения.
## Прямое a * b переполнило бы int64 при операндах до 2^32, поэтому
## множитель разбивается на half-words.
static func imul(a: int, b: int) -> int:
	var al := a & 0xFFFF
	var ah := (a >> 16) & 0xFFFF
	return (al * b + (((ah * b) & 0xFFFF) << 16)) & MASK32


## Следующее число в [0, 1). Эквивалент вызова замыкания mulberry32().
func next() -> float:
	_a = (_a + 0x6D2B79F5) & MASK32
	var t := imul(_a ^ (_a >> 15), 1 | _a)
	t = (((t + imul(t ^ (t >> 7), 61 | t)) & MASK32) ^ t) & MASK32
	return float((t ^ (t >> 14)) & MASK32) * INV32


## Псевдоним next() для совместимости со стандартным API RandomNumberGenerator.
func randf() -> float:
	return next()


## Порт rand(a, b) из utils.js (при одном аргументе — [0, a)).
func randf_range(a: float, b: float) -> float:
	return a + next() * (b - a)


func randf_to(a: float) -> float:
	return next() * a


## Целое в [0, n).
func randi_below(n: int) -> int:
	return int(next() * n)


## Целое в [a, b] включительно.
func randi_range(a: int, b: int) -> int:
	return a + int(next() * (b - a + 1))


## Порт choice(arr).
func pick(arr: Array) -> Variant:
	return arr[int(next() * arr.size())]


func pick_color(arr: PackedColorArray) -> Color:
	return arr[int(next() * arr.size())]


## Порт pickWeighted([{v, w}]): values и weights параллельными массивами.
func pick_weighted(values: Array, weights: PackedFloat32Array) -> Variant:
	var total := 0.0
	for w in weights:
		total += w
	var r := next() * total
	for i in values.size():
		r -= weights[i]
		if r <= 0.0:
			return values[i]
	return values[values.size() - 1]


## true с вероятностью p.
func chance(p: float) -> bool:
	return next() < p


## Порождает независимый поток из текущего — чтобы добавление объектов
## в одну фазу генерации не сдвигало результат остальных фаз.
func fork(salt: int) -> SeededRng:
	return SeededRng.new(imul(_a ^ salt, 0x9E3779B1))
