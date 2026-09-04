extends GdUnitTestSuite
## Таблица разделяемых материалов под свет машин — не instance uniform
## (не работает в Compatibility, см. fx/shaders/palette_toon.gdshader),
## поэтому проверяем, что кэш действительно разделяет одинаковые состояния
## и различает разные.

func test_same_state_returns_cached_instance() -> void:
	var a := CarLampMaterials.get_material(true, false, false, false, false)
	var b := CarLampMaterials.get_material(true, false, false, false, false)
	assert_object(a).is_same(b)


func test_different_state_returns_different_instance() -> void:
	var off := CarLampMaterials.get_material(false, false, false, false, false)
	var headlights_on := CarLampMaterials.get_material(true, false, false, false, false)
	assert_object(off).is_not_same(headlights_on)


func test_shader_parameters_match_requested_state() -> void:
	var mat := CarLampMaterials.get_material(true, true, false, true, false)
	var state: Vector4 = mat.get_shader_parameter(&"lamp_state")
	assert_float(state.x).is_equal(1.0) # фары
	assert_float(state.y).is_equal(1.0) # стоп
	assert_float(state.z).is_equal(0.0) # поворотник A
	assert_float(state.w).is_equal(1.0) # поворотник B
	assert_float(mat.get_shader_parameter(&"reverse_on")).is_equal(0.0)


func test_inherits_base_material_uniforms() -> void:
	# Не ShaderMaterial.new() — иначе теряются ao_strength/sky_fill/roughness
	# из mat_palette.tres, и машина светится не так, как весь остальной мир.
	var mat := CarLampMaterials.get_material(false, false, false, false, false)
	var base := preload("res://fx/materials/mat_palette.tres")
	assert_float(mat.get_shader_parameter(&"ao_strength"))\
		.is_equal_approx(base.get_shader_parameter(&"ao_strength"), 0.001)
