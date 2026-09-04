extends GdUnitTestSuite
## Тюнинг-косметика (этап 15): декаль и спортивный боди-кит должны реально
## менять геометрию, иначе выбор в гараже ни на что не влияет.

func _vertex_count(mesh: ArrayMesh) -> int:
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return verts.size()


func test_decal_adds_geometry() -> void:
	var plain := CarMeshBuilder.Spec.new()
	plain.silhouette = &"sedan"
	var decorated := CarMeshBuilder.Spec.new()
	decorated.silhouette = &"sedan"
	decorated.decal = &"stripe"

	var plain_count := _vertex_count(CarMeshBuilder.build_body(plain))
	var decorated_count := _vertex_count(CarMeshBuilder.build_body(decorated))
	assert_int(decorated_count).is_greater(plain_count)


func test_all_decal_ids_build_without_crashing() -> void:
	for decal_id in Db.cars.tuning.decal_ids:
		var spec := CarMeshBuilder.Spec.new()
		spec.silhouette = &"sedan"
		spec.decal = StringName(decal_id)
		assert_object(CarMeshBuilder.build_body(spec)).is_not_null()


func test_sport_body_kit_adds_geometry() -> void:
	var stock := CarMeshBuilder.Spec.new()
	stock.silhouette = &"sedan"
	var sport := CarMeshBuilder.Spec.new()
	sport.silhouette = &"sedan"
	sport.body_kit = &"sport"

	var stock_count := _vertex_count(CarMeshBuilder.build_body(stock))
	var sport_count := _vertex_count(CarMeshBuilder.build_body(sport))
	assert_int(sport_count).is_greater(stock_count)


func test_decal_on_van_silhouette_does_not_crash() -> void:
	# van/bus/truck не имеют ключа "hood" в CAR_SHAPES — декаль должна
	# использовать запасное значение, а не падать на Dictionary.get().
	var spec := CarMeshBuilder.Spec.new()
	spec.silhouette = &"van"
	spec.decal = &"checker"
	assert_object(CarMeshBuilder.build_merged(spec)).is_not_null()


func test_tuning_catalog_clamps_out_of_range_index() -> void:
	var tc := Db.cars.tuning
	assert_object(tc.color_at(999)).is_not_null()
	assert_that(tc.rim_style_at(999)).is_equal(tc.rim_style_at(tc.rim_styles.size() - 1))
	assert_that(tc.body_kit_at(-5)).is_equal(tc.body_kit_at(0))
	assert_that(tc.decal_at(999)).is_equal(tc.decal_at(tc.decal_ids.size() - 1))
