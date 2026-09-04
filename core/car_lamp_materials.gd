class_name CarLampMaterials
extends RefCounted
## Разделяемые материалы под состояние ламп машины.
##
## `instance uniform` не поддержан в Compatibility/GLES3 (см. комментарий в
## fx/shaders/palette_toon.gdshader), поэтому вместо правки уникального
## инстансного параметра каждая машина раз в кадр получает готовый
## `material_override` из этой таблицы. Draw calls не растут — материал
## общий на все машины с одинаковым состоянием ламп, присваивание ссылки
## почти бесплатно. Комбинаций ограниченно (фары × стоп × поворотник A ×
## поворотник B × задний ход = 32), кэш растёт лениво по мере встречаемых
## состояний, а не строится заранее целиком.

const BASE_MATERIAL := preload("res://fx/materials/mat_palette.tres")

static var _cache: Dictionary[int, ShaderMaterial] = {}


## headlights/brake/turn_a/turn_b/reverse — булевы состояния ламп машины.
## turn_a — борт -X («сторона A» в терминологии оригинала, player.js),
## turn_b — борт +X.
static func get_material(headlights: bool, brake: bool, turn_a: bool,
		turn_b: bool, reverse: bool) -> ShaderMaterial:
	var key := (1 if headlights else 0) | (2 if brake else 0) \
		| (4 if turn_a else 0) | (8 if turn_b else 0) | (16 if reverse else 0)
	var cached: ShaderMaterial = _cache.get(key)
	if cached != null:
		return cached
	# duplicate(), не ShaderMaterial.new(): нужны те же ao_strength/sky_fill/
	# roughness, что заданы в mat_palette.tres, а не дефолты шейдера.
	var mat: ShaderMaterial = BASE_MATERIAL.duplicate()
	mat.set_shader_parameter(&"lamp_state", Vector4(
		1.0 if headlights else 0.0,
		1.0 if brake else 0.0,
		1.0 if turn_a else 0.0,
		1.0 if turn_b else 0.0))
	mat.set_shader_parameter(&"reverse_on", 1.0 if reverse else 0.0)
	_cache[key] = mat
	return mat
