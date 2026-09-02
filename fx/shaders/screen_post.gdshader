shader_type canvas_item;
// Экранный слой на ColorRect в CanvasLayer. Только SCREEN_TEXTURE, без
// depth — иначе не соберётся в Compatibility.
//
// Заменяет DOM-эффекты оригинала: красную виньетку аварии (style.css:444)
// и добавляет то, чего там не было — постеризацию под low-poly-стиль
// и хроматическую аберрацию на скорости.

// В Godot 4 экранный буфер приходит через hint_screen_texture, а не
// встроенный SCREEN_TEXTURE. filter_linear без mipmap — эффектам они не нужны.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

uniform float vignette_strength : hint_range(0.0, 1.5) = 0.35;
uniform vec3 vignette_color : source_color = vec3(0.0, 0.0, 0.0);
// Отдельный красный слой аварии поверх обычной виньетки.
uniform float damage_flash : hint_range(0.0, 1.0) = 0.0;
uniform float aberration : hint_range(0.0, 0.02) = 0.0;
// 0 — выключено; иначе число уровней на канал.
uniform float posterize_levels : hint_range(0.0, 64.0) = 0.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centered = uv - vec2(0.5);
	float r2 = dot(centered, centered);

	vec3 col;
	if (aberration > 0.0001) {
		// Расхождение каналов усиливается к краям кадра.
		vec2 offset = centered * aberration * r2 * 4.0;
		col.r = texture(screen_tex, uv + offset).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - offset).b;
	} else {
		col = texture(screen_tex, uv).rgb;
	}

	if (posterize_levels > 0.5) {
		col = floor(col * posterize_levels + 0.5) / posterize_levels;
	}

	if (abs(saturation - 1.0) > 0.001) {
		float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
		col = mix(vec3(luma), col, saturation);
	}

	float vig = smoothstep(0.18, 0.72, r2);
	col = mix(col, vignette_color, vig * vignette_strength);
	col = mix(col, vec3(0.85, 0.13, 0.13), vig * damage_flash);

	COLOR = vec4(col, 1.0);
}
