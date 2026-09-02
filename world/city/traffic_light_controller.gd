class_name TrafficLightController
extends RefCounted
## Светофоры города: пофазные перекрёстки с «зелёной волной».
##
## Порт цикла из citygen.js:3032-3060. Цикл 16 с, фаза сдвинута по X, поэтому
## колонна, идущая вдоль проспекта на разрешённой скорости, проходит несколько
## перекрёстков подряд на зелёный.
##
## Отличие от проекта capital: там одна глобальная фаза на весь город. Для
## игры про такси это неприемлемо — исчезает сама возможность «поймать волну».
## Здесь фаза считается из времени и индекса перекрёстка, состояние нигде не
## хранится: 81 перекрёсток стоит один вызов cos/mod, а не 81 таймер.

enum State { GREEN, YELLOW, RED }
## Ось, по которой едут машины: Z_ROAD — вдоль Z (вертикальная дорога).
enum Axis { Z_ROAD, X_ROAD }

const CYCLE := 16.0
## Границы фаз для оси Z: зелёный 0-6, жёлтый 6-8, красный 8-16.
const Z_GREEN_END := 6.0
const Z_YELLOW_END := 8.0
## Для оси X со сдвигом: красный 0-8, зелёный 8-14, жёлтый 14-16.
const X_RED_END := 8.0
const X_GREEN_END := 14.0
## Сдвиг фазы на метр по X — это и есть «зелёная волна» (citygen.js:2750).
const WAVE_PER_CELL := 1.6

var axes: PackedFloat32Array = PackedFloat32Array()
var cell := 64.0
var time := 0.0


func _init(field: CityField = null) -> void:
	if field != null:
		axes = field.road_axes
		cell = field.cell
	else:
		axes = PackedFloat32Array()
		for i in 9:
			axes.append(-256.0 + i * 64.0)


func advance(delta: float) -> void:
	time = fmod(time + delta, CYCLE)


## Сдвиг фазы перекрёстка: чем восточнее, тем позже включается зелёный.
func phase_offset(i: int) -> float:
	return -(axes[i] / cell) * WAVE_PER_CELL


## Положение внутри цикла для перекрёстка (i, j), 0..16.
func local_time(i: int) -> float:
	return fposmod(time + phase_offset(i), CYCLE)


## Сигнал для машин, едущих вдоль указанной оси.
func car_state(i: int, axis: int) -> State:
	var t := local_time(i)
	if axis == Axis.Z_ROAD:
		if t < Z_GREEN_END:
			return State.GREEN
		return State.YELLOW if t < Z_YELLOW_END else State.RED
	if t < X_RED_END:
		return State.RED
	return State.GREEN if t < X_GREEN_END else State.YELLOW


func is_open_for_cars(i: int, axis: int) -> bool:
	return car_state(i, axis) == State.GREEN


## Пешеходный зелёный горит ровно тогда, когда машинам по пересекаемой
## дороге — красный. Жёлтый пешеходу зелёного не даёт.
func is_crossing_open(gate: int) -> bool:
	var isec := PedGraph.gate_intersection(gate)
	return car_state(isec.x, PedGraph.gate_axis(gate)) == State.RED


## Сколько секунд ещё продлится пешеходный зелёный. 0 — уже нельзя идти.
##
## Пешеход обязан спрашивать это ПЕРЕД выходом на зебру: ступать можно, только
## если успеешь дойти (приём из capital) — иначе он застревает посреди дороги
## при смене фазы.
func crossing_green_remaining(gate: int) -> float:
	if not is_crossing_open(gate):
		return 0.0
	var isec := PedGraph.gate_intersection(gate)
	var t := local_time(isec.x)
	if PedGraph.gate_axis(gate) == Axis.Z_ROAD:
		# Машинам вдоль Z красный с 8 до 16.
		return CYCLE - t
	# Машинам вдоль X красный с 0 до 8.
	return X_RED_END - t


## Через сколько секунд загорится пешеходный зелёный (0 — уже горит).
func time_until_crossing_green(gate: int) -> float:
	if is_crossing_open(gate):
		return 0.0
	var isec := PedGraph.gate_intersection(gate)
	var t := local_time(isec.x)
	if PedGraph.gate_axis(gate) == Axis.Z_ROAD:
		return Z_YELLOW_END - t
	return CYCLE - t


## Упаковка состояния для шейдера линз: индекс горящей секции 0..2.
## Менеджер пишет это в INSTANCE_CUSTOM только тем перекрёсткам, у которых
## фаза сменилась, — обход всех линз каждый кадр не нужен.
func lamp_index(i: int, axis: int) -> int:
	match car_state(i, axis):
		State.RED:
			return 0
		State.YELLOW:
			return 1
		_:
			return 2
