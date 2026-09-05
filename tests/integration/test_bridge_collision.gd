extends GdUnitTestSuite
## Коллизия путепровода: по деке едут, ПОД декой тоже едут.
##
## Это единственная в проекте коллизия, где по одному (x, z) проходят два
## разных маршрута на разных высотах, поэтому проверяется не «шейпы
## добавлены», а физика: луч сверху упирается в плиту, луч под плитой
## проходит насквозь, луч снизу вверх находит низ деки.
##
## Тесту нужен World3D (пространство физики), поэтому он в integration, а не
## в unit: чистая логика дерева сцены не требует.

var _field: CityField
var _graph: CityGraph
var _bridge: BridgeGeometry
var _collision: CityCollision
var _space: RID
var _deck := -1


func before_test() -> void:
	var balance: BalanceData = load("res://data/balance/balance.tres")
	_field = CityField.new(balance)
	_graph = PyatigorskTopology.new().build(_field)
	_bridge = BridgeGeometry.new(_graph, _field)
	for e in _graph.edge_count():
		if _graph.edge_kind(e) == CityGraph.EdgeKind.BRIDGE:
			_deck = e

	var root := auto_free(Node3D.new()) as Node3D
	add_child(root)
	await get_tree().physics_frame
	_space = root.get_world_3d().space
	_collision = CityCollision.new()
	_collision.build_bridges(_space, _bridge)
	# Шейпы попадают в широкую фазу только после шага физики.
	await get_tree().physics_frame
	await get_tree().physics_frame


func after_test() -> void:
	_collision.clear()


func test_shapes_cover_every_slab_and_pier() -> void:
	assert_int(_collision.shape_count())\
		.override_failure_message(
			"шейпов %d при %d плитах и %d опорах"
			% [_collision.shape_count(), _bridge.deck_count(), _bridge.pier_count()])\
		.is_equal(_bridge.deck_count() + _bridge.pier_count())


func test_ray_from_above_lands_on_the_deck() -> void:
	var mid := _deck_mid()
	var hit := _ray(Vector3(mid.x, 30.0, mid.z), Vector3(mid.x, 0.0, mid.z))
	assert_bool(hit.is_empty())\
		.override_failure_message("луч сверху не нашёл деку в (%.1f, %.1f)" % [mid.x, mid.z])\
		.is_false()
	var y: float = (hit["position"] as Vector3).y
	assert_float(y)\
		.override_failure_message("луч сверху упёрся на %.2f м, полотно деки на %.2f м"
			% [y, mid.y])\
		.is_equal_approx(mid.y, 0.05)


func test_ray_along_the_street_passes_under_the_deck() -> void:
	# Главная проверка этапа: плита — платформа на своей высоте, а не объём
	# от земли до полотна. Луч идёт по оси улицы внизу на высоте кабины
	# грузовика и обязан пройти сквозь развязку.
	var mid := _deck_mid()
	var dir := _street_dir()
	var y := CityGraph.MIN_CLEARANCE - 0.5
	var from := Vector3(mid.x, y, mid.z) - dir * 40.0
	var to := Vector3(mid.x, y, mid.z) + dir * 40.0
	var hit := _ray(from, to)
	assert_bool(hit.is_empty())\
		.override_failure_message(
			"проезд под мостом перекрыт: луч на высоте %.2f м упёрся в %s" % [y, hit.get("position", "")])\
		.is_true()


func test_ray_from_below_finds_the_underside_of_the_deck() -> void:
	var mid := _deck_mid()
	var hit := _ray(Vector3(mid.x, 1.0, mid.z), Vector3(mid.x, 20.0, mid.z))
	assert_bool(hit.is_empty())\
		.override_failure_message("снизу дека не нащупывается — плиты нет вовсе")\
		.is_false()
	var y: float = (hit["position"] as Vector3).y
	assert_float(y)\
		.override_failure_message("низ плиты на %.2f м, ожидался %.2f м"
			% [y, mid.y - BridgeGeometry.DECK_THICKNESS])\
		.is_equal_approx(mid.y - BridgeGeometry.DECK_THICKNESS, 0.05)


func test_piers_are_solid() -> void:
	assert_int(_bridge.pier_count()).is_greater(0)
	for i in _bridge.pier_count():
		var base := _bridge.pier_base[i]
		var probe := base + Vector3(0.0, _bridge.pier_height[i] * 0.5, 0.0)
		var hit := _ray(probe + Vector3(6.0, 0.0, 0.0), probe - Vector3(6.0, 0.0, 0.0))
		assert_bool(hit.is_empty())\
			.override_failure_message("в опору %d в (%.1f, %.1f) нельзя въехать"
				% [i, base.x, base.z])\
			.is_false()


# --- Служебное --------------------------------------------------------------

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var params := PhysicsRayQueryParameters3D.create(from, to,
		CityCollision.LAYER)
	return PhysicsServer3D.space_get_direct_state(_space).intersect_ray(params)


## Середина пролёта.
func _deck_mid() -> Vector3:
	var pts := _graph.edge_polyline(_deck)
	return pts[0].lerp(pts[pts.size() - 1], 0.5)


## Направление улицы под пролётом в плане, единичное.
func _street_dir() -> Vector3:
	var mid := _deck_mid()
	var e := _graph.query_nearest_edge(Vector3(mid.x, 0.0, mid.z), 40.0)
	var pts := _graph.edge_polyline(e)
	var d := pts[pts.size() - 1] - pts[0]
	d.y = 0.0
	return d.normalized()
