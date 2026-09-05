extends SceneTree
## Сводка по топологии Пятигорска (`PyatigorskTopology`) без запуска рендера.
## Аналог `tools/city_stats.gd`, только про граф улиц, а не про план города.
##
## Запуск: godot --headless --path . --script res://tools/topology_stats.gd
##
## Побочно кладёт схему графа сверху в tools/dump/topology.svg — форму
## «хребет + сетка + огибание склона» проще один раз увидеть, чем вычитать
## из чисел. Каталог tools/dump/ в .gitignore, файл артефактом не считается.

const SVG_PATH := "res://tools/dump/topology.svg"
## Поля вокруг габарита графа в SVG, м.
const SVG_MARGIN := 40.0


func _init() -> void:
	# Автолоады в режиме --script недоступны, каталоги грузим напрямую.
	var balance: BalanceData = load("res://data/balance/balance.tres")
	var districts: DistrictCatalog = load("res://data/districts/district_catalog.tres")
	districts.index()

	var t0 := Time.get_ticks_msec()
	var field := CityField.new(balance)
	var topo := PyatigorskTopology.new()
	var g := topo.build(field)
	var ms := Time.get_ticks_msec() - t0
	print("топология построена за ", ms, " мс")

	_print_nodes(g, topo)
	_print_edges(g)
	_print_streets(g)
	_print_landmarks(topo, districts)
	_print_elevation(g, field)

	# Детерминизм: топология — литерал, `world_seed` на неё не влияет, но
	# повторное построение обязано дать побитово тот же граф.
	var again := PyatigorskTopology.new().build(CityField.new(balance))
	var same := PyatigorskTopology.digest(g) == PyatigorskTopology.digest(again)
	print("детерминизм (world_seed=", balance.world_seed, "): ", same)
	print("слепок: ", PyatigorskTopology.digest(g))

	_write_svg(g)
	quit(0 if same else 1)


func _print_nodes(g: CityGraph, topo: PyatigorskTopology) -> void:
	var rings := 0
	var by_district: Dictionary[StringName, int] = {}
	var by_degree: Dictionary[int, int] = {}
	for n in g.node_count():
		if g.node_kind(n) == CityGraph.NodeKind.ROUNDABOUT:
			rings += 1
		var d := topo.node_district[n]
		by_district[d] = by_district.get(d, 0) + 1
		var deg := g.node_degree(n)
		by_degree[deg] = by_degree.get(deg, 0) + 1
	print("узлов: ", g.node_count(), " (колец: ", rings,
		", со светофором: ", topo.signal_nodes.size(), ")")
	print("  по районам:")
	for d: StringName in by_district:
		print("    ", d, ": ", by_district[d])
	print("  по степени:")
	for deg: int in by_degree:
		print("    степень ", deg, ": ", by_degree[deg])


func _print_edges(g: CityGraph) -> void:
	var kinds := ["street", "avenue", "serpentine", "bridge", "tunnel"]
	var by_kind: Dictionary[int, int] = {}
	var len_by_kind: Dictionary[int, float] = {}
	var total := 0.0
	var levels: Dictionary[int, int] = {}
	for e in g.edge_count():
		var k := g.edge_kind(e)
		by_kind[k] = by_kind.get(k, 0) + 1
		len_by_kind[k] = len_by_kind.get(k, 0.0) + g.edge_length(e)
		total += g.edge_length(e)
		var lv := g.edge_level(e)
		levels[lv] = levels.get(lv, 0) + 1
	print("рёбер: ", g.edge_count(), ", суммарная длина: %.1f м" % total)
	for k: int in by_kind:
		print("    %s: %d рёбер, %.1f м" % [kinds[k], by_kind[k], len_by_kind[k]])
	for lv: int in levels:
		print("    ярус ", lv, ": ", levels[lv], " рёбер")


func _print_streets(g: CityGraph) -> void:
	var length: Dictionary[String, float] = {}
	var width: Dictionary[String, float] = {}
	var unnamed := 0
	for e in g.edge_count():
		var s := g.edge_name(e)
		if s.is_empty():
			unnamed += 1
			continue
		length[s] = length.get(s, 0.0) + g.edge_length(e)
		width[s] = maxf(width.get(s, 0.0), g.edge_width(e))
	var names := length.keys()
	names.sort_custom(func(a: String, b: String) -> bool:
		return length[a] > length[b])
	print("именованных улиц: ", names.size(), ", безымянных рёбер: ", unnamed)
	for s: String in names:
		print("    %-32s %6.1f м, ширина %.1f м" % [s, length[s], width[s]])


func _print_landmarks(topo: PyatigorskTopology, districts: DistrictCatalog) -> void:
	print("лендмарки:")
	for lm in districts.landmarks:
		if lm == null:
			continue
		var node: int = topo.landmark_node.get(lm.id, -1)
		if node < 0:
			print("    ", lm.id, ": НЕ ПРИВЯЗАН")
			continue
		var p := topo.graph.node_position(node)
		var d := lm.position.distance_to(Vector2(p.x, p.z))
		var approach := " (подъездное ребро %d)" % topo.landmark_approach[lm.id] \
			if topo.landmark_approach.has(lm.id) else ""
		print("    %-8s узел %2d, отклонение %.1f м%s" % [lm.id, node, d, approach])


func _print_elevation(g: CityGraph, field: CityField) -> void:
	var best := -1
	var best_gain := 0.0
	for e in g.edge_count():
		if g.edge_kind(e) == CityGraph.EdgeKind.SERPENTINE:
			continue
		var lo := INF
		var hi := -INF
		for k in g.edge_point_count(e):
			var y := g.edge_point(e, k).y
			lo = minf(lo, y)
			hi = maxf(hi, y)
		if hi - lo > best_gain:
			best_gain = hi - lo
			best = e
	print("самый крутой участок вне серпантина: «%s», перепад %.1f м на %.1f м"
		% [g.edge_name(best), best_gain, g.edge_length(best)])

	# `CityField._serp_length` — длина оси в плане (маршем набирается по
	# горизонтали), а `edge_length` — полная 3D-длина полилинии. Сверять надо
	# план с планом, иначе подъём на 58 м даёт «расхождение» в 3.7 м.
	var serp_3d := 0.0
	var serp_plan := 0.0
	for e in g.edge_count():
		if g.edge_kind(e) != CityGraph.EdgeKind.SERPENTINE:
			continue
		serp_3d += g.edge_length(e)
		for k in range(1, g.edge_point_count(e)):
			var p0 := g.edge_point(e, k - 1)
			var p1 := g.edge_point(e, k)
			serp_plan += Vector2(p0.x, p0.z).distance_to(Vector2(p1.x, p1.z))
	print("серпантин: план %.2f м (CityField: %.2f м), по полотну %.2f м"
		% [serp_plan, field.serpentine_length(), serp_3d])


## Схема сверху: узлы и полилинии рёбер в SVG. Ярус 1 рисуется поверх и
## другим цветом — путепровод должен быть виден отдельно от улицы под ним.
func _write_svg(g: CityGraph) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for n in g.node_count():
		var p := g.node_position(n)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	lo -= Vector2(SVG_MARGIN, SVG_MARGIN)
	hi += Vector2(SVG_MARGIN, SVG_MARGIN)
	var size := hi - lo

	var svg := PackedStringArray()
	svg.append('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%.1f %.1f %.1f %.1f">'
		% [lo.x, lo.y, size.x, size.y])
	svg.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#f4f1ea"/>'
		% [lo.x, lo.y, size.x, size.y])
	for e in g.edge_count():
		var pts := PackedStringArray()
		for k in g.edge_point_count(e):
			var p := g.edge_point(e, k)
			pts.append("%.1f,%.1f" % [p.x, p.z])
		var color := "#8a8a84"
		if g.edge_kind(e) == CityGraph.EdgeKind.AVENUE:
			color = "#3a3a34"
		elif g.edge_kind(e) == CityGraph.EdgeKind.SERPENTINE:
			color = "#a06030"
		elif g.edge_level(e) != 0:
			color = "#c02020"
		svg.append('<polyline points="%s" fill="none" stroke="%s" stroke-width="%.1f" stroke-linecap="round"/>'
			% [" ".join(pts), color, g.edge_width(e) * 0.5])
	for n in g.node_count():
		var p := g.node_position(n)
		var r := 3.0
		var color := "#20202a"
		if g.node_kind(n) == CityGraph.NodeKind.ROUNDABOUT:
			r = g.node_radius(n) * 0.5
			color = "#2060c0"
		svg.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s"/>'
			% [p.x, p.z, r, color])
	svg.append("</svg>")

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SVG_PATH.get_base_dir()))
	var f := FileAccess.open(SVG_PATH, FileAccess.WRITE)
	if f == null:
		print("SVG не записан: ", error_string(FileAccess.get_open_error()))
		return
	f.store_string("\n".join(svg))
	f.close()
	print("схема сверху: ", SVG_PATH)
