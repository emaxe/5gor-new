shader_type spatial;
// Единый материал для города, пропсов, машин и пешеходов: цвет приходит
// вершинным атрибутом, поэтому батчинг не ломается и всё рисуется одним
// материалом. Это половина low-poly-стиля и главный рычаг по draw calls.
//
// diffuse_toon/specular_toon — встроенные режимы, доступные в Forward+,
// Mobile и Compatibility, поэтому ступенчатый свет не требует своей
// функции light() и одинаково работает на всех трёх рендерерах.
render_mode diffuse_toon, specular_toon, cull_back;

// Затемнение по вертикали: дешёвая замена AO. Низ зданий и основания
// пропсов темнее — глубина читается без единого прохода SSAO.
uniform float ao_strength : hint_range(0.0, 1.0) = 0.0;
uniform float ao_height = 4.0;

// Освещение «неба» снизу, чтобы теневые грани не проваливались в чёрный.
uniform vec3 sky_fill : source_color = vec3(0.42, 0.52, 0.65);
uniform float sky_fill_strength : hint_range(0.0, 1.0) = 0.25;

uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;

// Инстансные униформы: вариация цвета и эмиссии без дублирования материала.
// ЛОВУШКА: `instance uniform` не поддержан в Compatibility/GLES3 (в
// скомпилированном шейдере движка `instance_uniforms_ofs` есть только в
// RD-бэкенде — Forward+/Mobile). Оба поля ниже сейчас нигде не выставляются
// из кода именно поэтому: код, который на них полагается бы, молча ничего
// не делал бы на вебе. Свет ламп машин (ниже) поэтому НЕ инстансный
// униформ, а обычный материальный — таблица готовых ShaderMaterial
// (core/car_lamp_materials.gd), общая для всех рендереров.
instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float emission_boost = 0.0;

// Состояние ламп машины: x=фары, y=стоп-сигнал, z=поворотник A (борт -X),
// w=поворотник B (борт +X). Обычный (не instance) uniform — раз в кадр
// машина получает готовый материал из CarLampMaterials вместо правки
// уникального. Задний ход — отдельный флаг: его лампа не паркуется в тот
// же vec4 просто чтобы не путать порядок компонент по памяти.
uniform vec4 lamp_state = vec4(0.0);
uniform float reverse_on : hint_range(0.0, 1.0) = 0.0;

varying float v_ao;
// flat: тип поверхности одинаков на всех вершинах одной лампы/панели,
// интерполяция не нужна и может размыть границу между обычным кузовом и
// лампой на стыке треугольников.
varying flat float v_kind;

void vertex() {
	// Тип поверхности — из альфы ДО применения tint: `COLOR *= tint`
	// (вместо `.rgb *=`) незаметно исказил бы альфу и тип поверхности
	// поплыл бы вместе с любой будущей правкой tint.
	v_kind = COLOR.a;
	COLOR.rgb *= tint.rgb;
	float h = clamp(VERTEX.y / max(ao_height, 0.001), 0.0, 1.0);
	v_ao = mix(1.0 - ao_strength, 1.0, h);
}

void fragment() {
	vec3 albedo = COLOR.rgb * v_ao;
	ALBEDO = albedo;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	// Заливка «от неба» по нормали вверх — мягкая, не спорит с тонированием.
	float up = clamp(NORMAL.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 emission = sky_fill * albedo * (sky_fill_strength * up)
		+ albedo * emission_boost;

	// Лампы машин: v_kind сравнивается с допуском, а не ==, — альфа проходит
	// RGBA8-квантование при коммите меша (см. test_vertex_color_alpha_preserved).
	// Нейтраль — 1.0 (обычная поверхность), поэтому ветки начинаются с 0.9.
	if (abs(v_kind - 0.9) < 0.03) {
		// Фары: тускло видны выключенными (стекло отражает), ярко — включёнными.
		emission += albedo * mix(0.15, 1.6, lamp_state.x);
	} else if (abs(v_kind - 0.8) < 0.03) {
		// Стоп-сигналы тлеют как габариты всегда, вспыхивают при торможении.
		emission += albedo * mix(0.25, 1.8, lamp_state.y);
	} else if (abs(v_kind - 0.7) < 0.03) {
		emission += albedo * (lamp_state.z * 1.6);
	} else if (abs(v_kind - 0.6) < 0.03) {
		emission += albedo * (lamp_state.w * 1.6);
	} else if (abs(v_kind - 0.4) < 0.03) {
		emission += albedo * (reverse_on * 1.4);
	} else if (abs(v_kind - 0.5) < 0.03) {
		// Стекло: глянец + псевдоотражение неба по фронту (френель), не
		// прозрачность — угол к камере читается движением блика, а не
		// просветом. specular_toon (render_mode выше) даёт жёсткое
		// стилизованное пятно вместо PBR-размазни, что для low-poly уместнее.
		ROUGHNESS = 0.08;
		float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		emission += sky_fill * fresnel * 1.2;
	}
	EMISSION = emission;
	// ALPHA намеренно не пишем: любое присваивание ALPHA переводит материал
	// в прозрачные, а прозрачные не принимают направленные тени и не пишут
	// глубину — город терял все тени на земле. Читать COLOR.a (v_kind выше)
	// можно свободно — это чтение входного атрибута, а не запись ALPHA.
	// Стекло не отдельный материал, а ещё один v_kind (0.5) — без прозрачности,
	// читается по ROUGHNESS/псевдоотражению неба.
}
