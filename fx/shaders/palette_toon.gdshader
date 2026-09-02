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
instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float emission_boost = 0.0;

varying float v_ao;

void vertex() {
	// COLOR приходит из SurfaceTool.set_color() — это и есть палитра.
	COLOR *= tint;
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
	EMISSION = sky_fill * albedo * (sky_fill_strength * up)
		+ albedo * emission_boost;
	// ALPHA намеренно не пишем: любое присваивание ALPHA переводит материал
	// в прозрачные, а прозрачные не принимают направленные тени и не пишут
	// глубину — город терял все тени на земле. Для стекла заведён отдельный
	// материал (fx/materials/mat_glass.tres).
}
