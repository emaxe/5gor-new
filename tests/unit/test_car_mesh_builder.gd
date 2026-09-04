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


func _alphas_of(mesh: ArrayMesh) -> PackedFloat32Array:
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var out := PackedFloat32Array()
	for c in colors:
		out.append(c.a)
	return out


func _count_near(alphas: PackedFloat32Array, target: float) -> int:
	var n := 0
	for a in alphas:
		if absf(a - target) < 0.03:
			n += 1
	return n


## Свет машин зажигается сменой материала (core/car_lamp_materials.gd), не
## пересборкой геометрии — поэтому тип поверхности обязан быть закодирован
## в альфе вершинного цвета у каждой лампы, а не только у трафика.
func test_lamp_geometry_tags_alpha_for_every_kind() -> void:
	var spec := CarMeshBuilder.Spec.new()
	spec.silhouette = &"sedan"
	var alphas := _alphas_of(CarMeshBuilder.build_merged(spec))

	assert_int(_count_near(alphas, CarMeshBuilder.ALPHA_HEADLIGHT))\
		.override_failure_message("нет вершин фары").is_greater(0)
	assert_int(_count_near(alphas, CarMeshBuilder.ALPHA_BRAKE))\
		.override_failure_message("нет вершин стоп-сигнала").is_greater(0)
	assert_int(_count_near(alphas, CarMeshBuilder.ALPHA_TURN_A))\
		.override_failure_message("нет вершин поворотника A").is_greater(0)
	assert_int(_count_near(alphas, CarMeshBuilder.ALPHA_TURN_B))\
		.override_failure_message("нет вершин поворотника B").is_greater(0)
	assert_int(_count_near(alphas, CarMeshBuilder.ALPHA_REVERSE))\
		.override_failure_message("нет вершин заднего хода").is_greater(0)


## Стекло — не отдельный материал, а v_kind в шейдере (см. решения плана
## про реализм): без альфы вся «теплица» салона осталась бы обычной панелью
## кузова.
func test_glass_geometry_tags_alpha() -> void:
	var spec := CarMeshBuilder.Spec.new()
	spec.silhouette = &"sedan"
	var alphas := _alphas_of(CarMeshBuilder.build_merged(spec))
	assert_int(_count_near(alphas, CarMeshBuilder.ALPHA_GLASS))\
		.override_failure_message("нет вершин стекла").is_greater(0)


## Кузов, пороги, крыша и т.д. — подавляющее большинство меша — обязаны
## остаться на нейтральной альфе 1.0, иначе шейдер начнёт подсвечивать
## случайные панели кузова как лампы.
func test_body_panels_stay_at_neutral_alpha() -> void:
	var spec := CarMeshBuilder.Spec.new()
	spec.silhouette = &"sedan"
	var alphas := _alphas_of(CarMeshBuilder.build_merged(spec))
	var neutral := _count_near(alphas, CarMeshBuilder.ALPHA_NORMAL)
	assert_bool(neutral * 2 > alphas.size())\
		.override_failure_message("меньше половины вершин кузова остались нейтральными")\
		.is_true()


## Регрессия: build_body() (машина игрока) раньше не вызывал _add_lights() —
## у игрока не было видно ни стопов, ни поворотников, ни заднего хода.
func test_player_body_has_lamp_geometry_too() -> void:
	var spec := CarMeshBuilder.Spec.new()
	spec.silhouette = &"sedan"
	var alphas := _alphas_of(CarMeshBuilder.build_body(spec))
	assert_int(_count_near(alphas, CarMeshBuilder.ALPHA_BRAKE))\
		.override_failure_message("build_body() без ламп — игрок не увидит своих стопов")\
		.is_greater(0)


func test_tuning_catalog_clamps_out_of_range_index() -> void:
	var tc := Db.cars.tuning
	assert_object(tc.color_at(999)).is_not_null()
	assert_that(tc.rim_style_at(999)).is_equal(tc.rim_style_at(tc.rim_styles.size() - 1))
	assert_that(tc.body_kit_at(-5)).is_equal(tc.body_kit_at(0))
	assert_that(tc.decal_at(999)).is_equal(tc.decal_at(tc.decal_ids.size() - 1))
