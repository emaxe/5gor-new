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
