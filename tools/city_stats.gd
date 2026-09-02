extends SceneTree
## Сводка по сгенерированному городу без запуска рендера.
##
## Запуск: godot --headless --path . --script res://tools/city_stats.gd

func _init() -> void:
	# Автолоады в режиме --script недоступны, каталоги грузим напрямую.
	var balance: BalanceData = load("res://data/balance/balance.tres")
	var districts: DistrictCatalog = load("res://data/districts/district_catalog.tres")
	districts.index()
	var t0 := Time.get_ticks_msec()
	var field := CityField.new(balance)
	var graph := PedGraph.new(field)
	var planner := CityPlanner.new(field, graph, districts)
	var plan := planner.plan(balance.world_seed)
	var ms := Time.get_ticks_msec() - t0
	print("план построен за ", ms, " мс")
	var s := plan.summary()
	for k: String in s:
		print("  ", k, ": ", s[k])
	var plan2 := CityPlanner.new(field, graph, districts).plan(balance.world_seed)
	print("детерминизм: ", s == plan2.summary())
	quit(0)
