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
	var plan := _plan(balance, districts)
	var ms := Time.get_ticks_msec() - t0
	print("план построен за ", ms, " мс")
	var s := plan.summary()
	for k: String in s:
		print("  ", k, ": ", s[k])
	print("детерминизм: ", s == _plan(balance, districts).summary())
	quit(0)


## Полная фаза A: топология -> граф -> кварталы -> план. Повторяется целиком,
## а не переиспользует граф: детерминизм обязан держаться на всей цепочке.
func _plan(balance: BalanceData, districts: DistrictCatalog) -> CityPlan:
	var field := CityField.new(balance)
	var topology := PyatigorskTopology.new()
	var roads := topology.build(field)
	field.attach_roads(roads)
	var ped := PedGraph.on_graph(roads, topology.signal_nodes, field.sidewalk,
		RoadMesh.new(roads, field).walk_room_flags())
	var signals := NodeSignalController.build(roads, topology.signal_nodes,
		topology.wave_front_nodes)
	var blocks := CityBlocks.new()
	blocks.build(roads, topology.node_district, topology.landmark_node)
	var road_mesh := RoadMesh.new(roads, field)
	var markings := RoadMarkings.new(roads, road_mesh, topology.signal_nodes,
		ped.crossings)
	return CityPlanner.new(field, roads, blocks, topology.node_district,
		districts).plan(balance.world_seed, markings.crossings,
		NodeSignalPlan.build(roads, signals), topology.landmark_node)
