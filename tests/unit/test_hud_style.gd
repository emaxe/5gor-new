extends GdUnitTestSuite
## Карта уровней сообщений HUD (HudStyle): полнота и монотонность
## длительности показа — критическое должно висеть дольше награды.

const HudStyleScript = preload("res://ui/theme/hud_style.gd")

const LEVELS := [
	HudStyleScript.LEVEL_REWARD, HudStyleScript.LEVEL_INFO, HudStyleScript.LEVEL_CRITICAL,
]


func test_every_level_has_a_distinct_color() -> void:
	var colors: Array[Color] = []
	for id: StringName in LEVELS:
		colors.append(HudStyleScript.level_color(id))
	assert_that(colors[0]).is_not_equal(colors[1])
	assert_that(colors[1]).is_not_equal(colors[2])
	assert_that(colors[0]).is_not_equal(colors[2])


func test_duration_grows_from_reward_to_critical() -> void:
	var reward_d := HudStyleScript.level_duration(HudStyleScript.LEVEL_REWARD)
	var info_d := HudStyleScript.level_duration(HudStyleScript.LEVEL_INFO)
	var critical_d := HudStyleScript.level_duration(HudStyleScript.LEVEL_CRITICAL)

	assert_float(reward_d).is_less(info_d)
	assert_float(info_d).is_less(critical_d)


func test_rank_orders_reward_below_info_below_critical() -> void:
	var reward_r := HudStyleScript.level_rank(HudStyleScript.LEVEL_REWARD)
	var info_r := HudStyleScript.level_rank(HudStyleScript.LEVEL_INFO)
	var critical_r := HudStyleScript.level_rank(HudStyleScript.LEVEL_CRITICAL)

	assert_int(reward_r).is_less(info_r)
	assert_int(info_r).is_less(critical_r)


## Неизвестный уровень (например, опечатка в data["level"]) не должен
## падать — трактуется как LEVEL_INFO.
func test_unknown_level_falls_back_to_info() -> void:
	var unknown := &"typo"
	assert_int(HudStyleScript.level_rank(unknown)).is_equal(HudStyleScript.level_rank(HudStyleScript.LEVEL_INFO))
	assert_that(HudStyleScript.level_color(unknown)).is_equal(HudStyleScript.level_color(HudStyleScript.LEVEL_INFO))


func test_toast_style_border_matches_level_color() -> void:
	for id: StringName in LEVELS:
		var style := HudStyleScript.toast_style(id)
		assert_that(style.border_color).is_equal(HudStyleScript.level_color(id))
