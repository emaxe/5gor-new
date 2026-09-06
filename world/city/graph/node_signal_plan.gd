class_name NodeSignalPlan
extends RefCounted
## Стойки светофоров и их линзы для узлов графа: N стоек по числу подходов.
##
## Обобщение `CityPlanner._plan_signals()` (city_planner.gd:186-211), который
## ставит ровно четыре стойки по углам перекрёстка и приписывает каждой одну
## из двух осей. У узла степени 3 или 5 углов не четыре, а осей нет вовсе,
## поэтому стойка привязывается к ПОДХОДУ: сколько подходов у регулируемого
## узла, столько и стоек.
##
## Раскладка полей — та же, что у плана города: параллельные `Packed*Array`
## (позиция, курс, узел, подход), а не массив словарей, чтобы план оставался
## плоскими данными и мог собираться в рабочем потоке.
##
## С этапа 9 по этому плану живой город и ставит стойки: `CityPlanner`
## переносит позиции в `CityPlan`, `CityBuilder._build_signals()` собирает из
## них MultiMesh, а `refresh_signal_lenses()` красит линзы через
## `lens_index()`.

## Секций в линзе: красная, жёлтая, зелёная — сверху вниз, как в
## `CityBuilder._build_signals()` (city_builder.gd:179-184).
const SECTIONS := 3

## Вынос стойки от центра узла, м — то же число, что `CityPlanner.SIGNAL_OFFSET`
## (8.2). Прикладывается дважды: вдоль подхода и вбок вправо, поэтому стойка
## встаёт в ближний правый угол перекрёстка. На сетке 9x9 четыре стойки узла
## попадают ровно в четыре угла осевого планировщика.
const SIGNAL_OFFSET := 8.2

## Позиция стойки, мир.
var post_pos: PackedVector3Array = PackedVector3Array()
## Курс стойки: линза смотрит НАВСТРЕЧУ подъезжающему по этому подходу.
var post_yaw: PackedFloat32Array = PackedFloat32Array()
## Узел графа, который обслуживает стойка.
var post_node: PackedInt32Array = PackedInt32Array()
## Номер подхода этого узла.
var post_approach: PackedInt32Array = PackedInt32Array()

## (узел, подход) -> индекс стойки. Ключ числовой (`MathUtils.hash_key`), а не
## строковый: индексация линз идёт в цикле перекраски.
var _post_of: Dictionary[int, int] = {}


## Планирует стойки для всех узлов, регулируемых контроллером.
##
## Источник списка узлов — сам контроллер, а не отдельный аргумент: стойка
## без фазы бессмысленна, и два независимых списка рано или поздно разъехались
## бы (кольцо в одном есть, в другом нет).
static func build(graph: CityGraph, signals: NodeSignalController) -> NodeSignalPlan:
	var plan := NodeSignalPlan.new()
	plan._build(graph, signals)
	return plan


func _build(graph: CityGraph, signals: NodeSignalController) -> void:
	for node in signals.regulated_nodes():
		var center := graph.node_position(node)
		for k in graph.node_degree(node):
			var a := graph.approach_angle(node, k)
			# Направление подхода ОТ узла; подъезжающий едет ему навстречу.
			var along := Vector3(cos(a), 0.0, sin(a))
			# Правая сторона подъезжающего: правая нормаль к его курсу
			# (-along) в плане (x, z) — то есть (sin a, -cos a). Стойка стоит
			# справа у стоп-линии (ближняя сторона, ПДД РФ), а не на дальней.
			var right := Vector3(sin(a), 0.0, -cos(a))
			post_pos.append(center + (along + right) * SIGNAL_OFFSET)
			# Линзы вынесены по локальному +Z стойки (city_builder.gd:181),
			# значит «лицо» стойки — её курс: разворачиваем его на подъезжающего.
			post_yaw.append(Heading.from_vector(along))
			post_node.append(node)
			post_approach.append(k)
			_post_of[MathUtils.hash_key(node, k)] = post_pos.size() - 1


func post_count() -> int:
	return post_pos.size()


## Индекс линзы в общем MultiMesh: стойки идут подряд, внутри стойки —
## секции сверху вниз. Та же упаковка, что `CityBuilder._lens_index`.
func lens_index(post: int, section: int) -> int:
	return post * SECTIONS + section


## Линза по (узел, подход, секция) — замена индексации по (перекрёсток, ось,
## секция) осевого сборщика. -1, если такой стойки в плане нет.
func lens_of(node: int, approach: int, section: int) -> int:
	var key := MathUtils.hash_key(node, approach)
	if not _post_of.has(key):
		return -1
	return lens_index(_post_of[key], section)


## Стойка по (узел, подход) или -1.
func post_of(node: int, approach: int) -> int:
	var key := MathUtils.hash_key(node, approach)
	return _post_of[key] if _post_of.has(key) else -1
