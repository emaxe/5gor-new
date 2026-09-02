class_name SkyRig
extends Node3D
## Небо, солнце и окружение. Один узел на всю игру: и мир, и тестовые сцены
## берут атмосферу отсюда, чтобы «в тесте выглядит иначе» было невозможно.
##
## Порт _updateTime (game.js:1147-1220): цвет неба по таблице часов, тонировка
## погодой, движение солнца по дуге, ночная подсветка.

## Таблица цвета неба по часам (game.js:24-28), RGB 0..255.
const SKY_TABLE: Array[Dictionary] = [
	{"h": 4.0, "c": Color8(13, 18, 30)},
	{"h": 6.0, "c": Color8(96, 118, 148)},
	{"h": 9.0, "c": Color8(135, 176, 216)},
	{"h": 13.0, "c": Color8(156, 200, 232)},
	{"h": 17.0, "c": Color8(150, 160, 180)},
	{"h": 19.0, "c": Color8(206, 132, 84)},
	{"h": 21.0, "c": Color8(62, 50, 78)},
	{"h": 24.0, "c": Color8(13, 18, 30)},
]

## Солнце ходит по дуге, но не в зенит: при вертикальном свете фасады
## получают скользящее освещение и город читается плоским.
const SUN_ELEVATION_MIN := 8.0
const SUN_ELEVATION_MAX := 56.0
const SUN_AZIMUTH_MIN := -75.0
const SUN_AZIMUTH_MAX := 75.0
const SUN_DISTANCE := 60.0

## Ночью ambient нельзя оставлять чёрным: при sky_contribution < 1 остаток
## умножается на ambient_light_color, и город проваливается в чёрное.
const AMBIENT_DAY := Color(0.62, 0.70, 0.82)
const AMBIENT_NIGHT := Color(0.32, 0.40, 0.62)

@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var _preset: GfxPreset


func _ready() -> void:
	apply_preset(Db.gfx.get_preset(Prefs.gfx_preset) if Db.gfx != null else null)
	set_time_of_day(13.0, 0.0, null)


func apply_preset(preset: GfxPreset) -> void:
	if preset == null:
		return
	_preset = preset
	RenderCaps.configure_sun(sun, preset)
	RenderCaps.configure_environment(world_environment.environment, preset)
	sun.directional_shadow_max_distance = preset.shadow_max_distance


## Устанавливает время суток. night_factor 0..1 приходит из GameState,
## weather может быть null (ясно).
func set_time_of_day(hour: float, night_factor: float,
		weather: WeatherData) -> void:
	var env := world_environment.environment
	var sky_color := _sky_color(hour)
	var day := clampf(sin(PI * (hour - 6.0) / 12.0), 0.0, 1.0)

	var dim := 1.0
	if weather != null:
		sky_color = sky_color.lerp(weather.sky_tint, weather.sky_tint_strength)
		dim = 1.0 - (weather.rain * 0.35 + _fog_factor(weather) * 0.45)
		env.fog_depth_begin = weather.fog_near
		env.fog_depth_end = weather.fog_far

	var mat := env.sky.sky_material as ProceduralSkyMaterial
	mat.sky_top_color = sky_color.darkened(0.18)
	mat.sky_horizon_color = sky_color.lightened(0.22)
	env.fog_light_color = sky_color * (1.0 - night_factor * 0.35)

	sun.light_energy = (0.25 + day * 1.2) * dim
	sun.light_color = Color(1.0, 0.94, 0.84).lerp(Color(1.0, 0.72, 0.5),
		clampf(absf(hour - 13.0) / 7.0, 0.0, 1.0))
	sun.visible = sun.light_energy > 0.02
	_aim_sun(day, hour)

	env.ambient_light_color = AMBIENT_DAY.lerp(AMBIENT_NIGHT, night_factor)
	env.ambient_light_energy = (0.30 + day * 0.35) * dim + night_factor * 0.18


## Азимут ведёт солнце с востока на запад, высота — по дневной дуге.
func _aim_sun(day: float, hour: float) -> void:
	var t: float = clampf((hour - 6.0) / 12.0, 0.0, 1.0)
	var azimuth := deg_to_rad(lerpf(SUN_AZIMUTH_MIN, SUN_AZIMUTH_MAX, t))
	var elevation := deg_to_rad(lerpf(SUN_ELEVATION_MIN, SUN_ELEVATION_MAX, day))
	var dir := Vector3(sin(azimuth) * cos(elevation), sin(elevation),
		cos(azimuth) * cos(elevation))
	sun.position = dir * SUN_DISTANCE
	sun.look_at(Vector3.ZERO, Vector3.UP)


static func _sky_color(hour: float) -> Color:
	var h: float = fposmod(hour, 24.0)
	for i in SKY_TABLE.size() - 1:
		var a: Dictionary = SKY_TABLE[i]
		var b: Dictionary = SKY_TABLE[i + 1]
		var ha: float = a["h"]
		var hb: float = b["h"]
		if h >= ha and h <= hb:
			var t := (h - ha) / (hb - ha)
			return (a["c"] as Color).lerp(b["c"] as Color, t)
	return SKY_TABLE[0]["c"] as Color


static func _fog_factor(weather: WeatherData) -> float:
	return 1.0 if weather.id == &"fog" else 0.0
