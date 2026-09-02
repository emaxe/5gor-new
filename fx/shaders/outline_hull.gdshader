shader_type spatial;
// Обводка методом inverted hull: вторым проходом рисуем раздутую копию меша
// с вывернутыми нормалями. Screen-space outline по глубине в Compatibility
// недоступен, а этот приём работает на всех трёх рендерерах.
//
// Применяется ТОЛЬКО к «героям» (машина игрока, пеший игрок, активный
// пассажир, маркер заказа, полиция) — 5-6 объектов, +6 draw calls.
// Городу обводка не нужна: читаемость даёт flat shading и туман.
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.04, 0.05, 0.07, 1.0);
// Толщина в метрах на дистанции 10 м; дальше масштабируется, чтобы
// обводка не съедала силуэт вблизи и не исчезала вдали.
uniform float thickness : hint_range(0.0, 0.2) = 0.025;
uniform float distance_scale : hint_range(0.0, 2.0) = 1.0;

void vertex() {
	vec3 view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(view_pos);
	float scale = mix(1.0, dist / 10.0, distance_scale);
	VERTEX += NORMAL * thickness * scale;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
