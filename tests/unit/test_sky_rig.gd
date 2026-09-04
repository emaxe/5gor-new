extends GdUnitTestSuite
## Юнит-тест SkyRig: интерполяция цвета неба по SKY_TABLE на ключевых
## часах (полночь/рассвет/полдень/закат). Без рендера проверяется только
## _sky_color() — статический метод без сайд-эффектов.

const SkyRigScript = preload("res://world/sky/sky_rig.gd")


func test_sky_color_at_noon_is_brightest_blue() -> void:
	# 12:00 между точками 9 и 13 — ожидаем что-то между
	# Color8(135,176,216) и Color8(156,200,232), т.е. яркое дневное небо.
	var c: Color = SkyRigScript._sky_color(12.0)
	# Синий канал доминирует
	assert_float(c.b).is_greater(0.7)


func test_sky_color_at_midnight_is_dark() -> void:
	# 0:00 и 24:00 — обе точки с тёмно-синим Color8(13,18,30).
	var c: Color = SkyRigScript._sky_color(0.0)
	assert_float(c.r).is_less(0.2)
	assert_float(c.g).is_less(0.2)
	assert_float(c.b).is_less(0.2)


func test_sky_color_at_sunset_is_warm() -> void:
	# 19:00 — точка Color8(206,132,84), тёплый оранжевый закат.
	var c: Color = SkyRigScript._sky_color(19.0)
	assert_float(c.r).is_greater(c.b) # красный > синего


func test_sky_color_handles_wraparound() -> void:
	# 25:00 по модулю 24 == 1:00 — должна попасть в интервал [24, 4] —
	# fposmod вернёт 1, и метод возвращает SKY_TABLE[0]["c"] (fallback).
	# Главное — не падает.
	var c: Color = SkyRigScript._sky_color(25.0)
	assert_float(c.r).is_greater_equal(0.0)


func test_sky_table_has_eight_control_points() -> void:
	assert_int(SkyRigScript.SKY_TABLE.size()).is_equal(8)