class_name CityGraphGrid
extends RefCounted
## Прямоугольная сетка 9x9 как `CityGraph`.
##
## Служила мостом на время миграции (этапы 6-8): трафику нужен был настоящий
## граф раньше, чем живой город перешёл на топологию Пятигорска. Живой город с
## этапа 9 строится по `PyatigorskTopology` и сюда не заглядывает, но сетка
## осталась самым дешёвым способом получить регулярный граф с известными
## наперёд координатами — на ней стоят юнит-тесты трафика, пешеходов и
## полиции, где важна проверяемая руками геометрия, а не форма города.

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
## граф, — чтобы у теста был предсказуемый набор перекрёстков со светофором.
static func signalized_nodes(field: CityField) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := field.road_axes.size()
	for i in n:
		for j in n:
			if PedGraph.is_signalized(i, j):
				out.append(i * n + j)
	return out
