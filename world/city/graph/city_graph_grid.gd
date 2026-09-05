class_name CityGraphGrid
extends RefCounted
## Мост «сетка 9x9 -> CityGraph» на время миграции (этапы 6-9).
##
## Настоящий граф Пятигорска собирает этап 2, но в живой конвейер генерации
## города (`CityField`/`CityPlanner`) он попадает только на этапе 9. До тех
## пор трафику (этап 6) нужен НАСТОЯЩИЙ граф, иначе его не на чем катать:
## здесь он строится из тех же девяти осей `CityField.road_axes`, что и
## сегодняшняя рельсовая модель, — те же 81 перекрёсток и 144 ребра, то же
## поведение живой сцены.
##
## Это не заглушка, а обычный поставщик графа: на этапе 9 меняется только то,
## какой граф передаётся в `TrafficManager.setup()`.

## Ширина полотна ребра, м: 2 * `BalanceData.road_half` (city_field.gd:38).
const LANE_WIDTH := 12.0


## Прямоугольная сетка осей поля как граф: узлы в перекрёстках, рёбра между
## соседними по каждой оси.
static func from_field(field: CityField) -> CityGraph:
	var g := CityGraph.new()
	var axes := field.road_axes
	var n := axes.size()
	for i in n:
		for j in n:
			g.add_node(Vector3(axes[i], 0.0, axes[j]))
	for i in n:
		for j in n:
			var id := i * n + j
			if i + 1 < n:
				g.add_edge(id, id + n, PackedVector3Array(), LANE_WIDTH)
			if j + 1 < n:
				g.add_edge(id, id + 1, PackedVector3Array(), LANE_WIDTH)
	g.build()
	return g


## Регулируемые узлы сетки — те же перекрёстки, что регулирует сеточная
## модель (`PedGraph.is_signalized`: чётность индексов осей).
##
## Настоящий список регулируемых узлов задаёт топология (этап 2) явными
## данными; здесь он выводится арифметикой ровно потому же, почему и сам
## граф, — чтобы живой сеточный город до этапа 9 вёл себя как прежде. На
## этапе 9 в `TrafficManager.setup()` уедет `signal_nodes` топологии, и эта
## функция умрёт вместе с остальным мостом.
static func signalized_nodes(field: CityField) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := field.road_axes.size()
	for i in n:
		for j in n:
			if PedGraph.is_signalized(i, j):
				out.append(i * n + j)
	return out
