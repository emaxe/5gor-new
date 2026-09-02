class_name RenderCaps
extends RefCounted
## Возможности текущего рендерера. Проект собирается одним билдом под три
## рендерера (Forward+ / Mobile / Compatibility), и часть эффектов там
## недоступна или ведёт себя иначе — решения принимаются здесь, а не
## россыпью проверок по коду.

enum Method { FORWARD_PLUS, MOBILE, COMPATIBILITY }


static func method() -> Method:
	match RenderingServer.get_current_rendering_method():
		"forward_plus":
			return Method.FORWARD_PLUS
		"mobile":
			return Method.MOBILE
		_:
			return Method.COMPATIBILITY


static func is_compatibility() -> bool:
	return method() == Method.COMPATIBILITY


static func is_forward_plus() -> bool:
	return method() == Method.FORWARD_PLUS


## SSAO и объёмный туман есть только в Forward+.
static func supports_ssao() -> bool:
	return is_forward_plus()


static func supports_volumetric_fog() -> bool:
	return is_forward_plus()


## Каскадные тени (PSSM). В Compatibility доступен только ортогональный
## режим — с 4 сплитами тени там просто не рисуются.
static func supports_shadow_splits() -> bool:
	return not is_compatibility()


## Тени от направленного света реально видны.
##
## Проверено на Godot 4.7.2 / macOS: в Compatibility карта теней сэмплируется
## (виден муар), но кастеры в неё не попадают — тени не появляются ни с
## палитровым шейдером, ни со StandardMaterial3D, ни в ортогональном режиме.
## Это ограничение бэкенда (на macOS Compatibility идёт через ANGLE), а не
## нашего кода. В браузере на честном WebGL2 тени могут работать, поэтому
## сам свет не выключаем — но и не рассчитываем на них: сцена обязана
## читаться без них.
static func directional_shadows_reliable() -> bool:
	return not is_compatibility()


## Нужны ли «поддельные» контактные тени — тёмное пятно под машинами,
## пешеходами и пропсами. Включаются там, где настоящих теней нет:
## в Compatibility и на пресете low.
static func needs_contact_shadows(preset: GfxPreset) -> bool:
	return preset.shadows == &"off" or not directional_shadows_reliable()


## Экранные эффекты, читающие буфер экрана.
static func supports_screen_texture() -> bool:
	return true


## Приводит направленный свет к возможностям рендерера.
static func configure_sun(sun: DirectionalLight3D, preset: GfxPreset) -> void:
	sun.shadow_enabled = preset.shadows != &"off"
	if not sun.shadow_enabled:
		return
	if supports_shadow_splits():
		sun.directional_shadow_mode = \
			DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if preset.shadow_splits >= 4 \
			else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_blend_splits = true
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_blend_splits = false
	sun.directional_shadow_max_distance = preset.shadow_max_distance
	# В Compatibility фильтрация теней грубее — компенсируем большим bias,
	# иначе на длинных плоскостях дороги вылезает муар.
	sun.shadow_bias = 0.06 if supports_shadow_splits() else 0.03
	sun.shadow_normal_bias = 2.5 if supports_shadow_splits() else 1.0


## Приводит окружение к возможностям рендерера и пресету.
static func configure_environment(env: Environment, preset: GfxPreset) -> void:
	env.ssao_enabled = preset.ssao and supports_ssao()
	env.volumetric_fog_enabled = preset.volumetric_fog and supports_volumetric_fog()
	env.glow_enabled = preset.glow
