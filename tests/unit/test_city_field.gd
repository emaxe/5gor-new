extends GdUnitTestSuite
## Рельеф Машука и серпантин обязаны совпадать с оригиналом: на этой функции
## стоит и визуальный меш горы, и высота машины, и позиции пешеходов.
##
## Эталон снят прогоном чистых функций heightAt/_baseHeight/_serp* из
## citygen.js в Node.js (см. tools/dump/terrain_ref.json).

const REF_PATH := "res://tools/dump/terrain_ref.json"
## Допуск: расхождение float64 (JS) и float32 в PackedFloat32Array (Godot)
## накапливается на длине оси серпантина 463 м.
const EPS := 0.02

var _field: CityField
var _ref: Dictionary


func before() -> void:
	_field = CityField.new(Db.balance)
	var f := FileAccess.open(REF_PATH, FileAccess.READ)
	_ref = JSON.parse_string(f.get_as_text()) if f != null else {}


func test_reference_file_present() -> void:
	assert_bool(_ref.is_empty())\
		.override_failure_message(
			"нет эталона %s — запусти node /tmp/terrain_ref.mjs" % REF_PATH)\
		.is_false()


func test_serpentine_axis_matches_original() -> void:
	var pts := _field.serpentine_points()
	assert_int(pts.size()).is_equal(int(_ref["serp_points"]))
	assert_float(_field.serpentine_length())\
		.is_equal_approx(float(_ref["serp_len"]), 0.01)


func test_height_matches_reference_samples() -> void:
	var worst := 0.0
	var worst_at := Vector2.ZERO
	for s: Array in (_ref["samples"] as Array):
		var got := _field.height_at(float(s[0]), float(s[1]))
		var diff := absf(got - float(s[2]))
		if diff > worst:
			worst = diff
			worst_at = Vector2(float(s[0]), float(s[1]))
	assert_float(worst)\
		.override_failure_message(
			"максимальное расхождение с оригиналом %.4f м в точке %s" % [worst, worst_at])\
		.is_less(EPS)


func test_city_area_is_flat() -> void:
	# Весь город южнее z = -260 строго плоский — там нет рельефа.
	for x in [-256.0, -64.0, 0.0, 64.0, 256.0]:
		for z in [-256.0, -128.0, 0.0, 128.0, 256.0]:
			assert_float(_field.height_at(x, z)).is_equal(0.0)


func test_summit_height() -> void:
	# Плато вершины = HILL.top, площадка радиусом 20 м плоская.
	assert_float(_field.height_at(0.0, -448.0)).is_equal_approx(58.0, 0.01)
	assert_float(_field.height_at(15.0, -448.0)).is_equal_approx(58.0, 0.01)
	assert_float(_field.height_at(0.0, -433.0)).is_equal_approx(58.0, 0.01)


func test_serpentine_is_continuous() -> void:
	# Полотно не должно иметь ступеней: соседние точки оси отличаются по
	# высоте не больше, чем допускает уклон.
	var pts := _field.serpentine_points()
	for i in pts.size() - 1:
		var dy := absf(pts[i + 1].y - pts[i].y)
		var dxz := Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
		if dxz > 0.01:
			assert_float(dy / dxz)\
				.override_failure_message("слишком крутой сегмент оси #%d" % i)\
				.is_less(0.25)


func test_serpentine_climbs_from_zero_to_summit() -> void:
	var pts := _field.serpentine_points()
	assert_float(pts[0].y).is_equal(0.0)
	assert_float(pts[pts.size() - 1].y).is_equal_approx(58.0, 0.5)
	# Профиль монотонно неубывающий.
	for i in pts.size() - 1:
		assert_float(pts[i + 1].y).is_greater_equal(pts[i].y - 1e-4)


func test_serpentine_start_connects_to_city_road() -> void:
	# Начало оси — торец проспекта (128, -292), там высота уже нулевая,
	# иначе на въезде был бы уступ.
	assert_float(_field.height_at(128.0, -292.0)).is_less(0.2)


func test_road_grid_geometry() -> void:
	assert_int(_field.road_axes.size()).is_equal(9)
	assert_float(_field.road_axes[0]).is_equal(-256.0)
	assert_float(_field.road_axes[8]).is_equal(256.0)
	assert_int(_field.intersections.size()).is_equal(81)


func test_dist_to_road_on_axis_is_zero() -> void:
	for c in _field.road_axes:
		assert_float(_field.dist_to_road(c, 0.0)).is_equal_approx(0.0, 1e-4)
		assert_float(_field.dist_to_road(0.0, c)).is_equal_approx(0.0, 1e-4)


func test_dist_to_road_between_axes() -> void:
	# Ровно посередине между осями 0 и 64 расстояние равно 32.
	assert_float(_field.dist_to_road(32.0, 32.0)).is_equal_approx(32.0, 1e-3)


func test_on_road_matches_original_threshold() -> void:
	# Порог оригинала: HALF + SIDE + 3 = 13 м от оси.
	assert_bool(_field.on_road(0.0, 0.0)).is_true()
	assert_bool(_field.on_road(12.0, 32.0)).is_true()
	assert_bool(_field.on_road(14.0, 32.0)).is_false()
	assert_bool(_field.on_road(32.0, 32.0)).is_false()


func test_serpentine_counts_as_road() -> void:
	var pts := _field.serpentine_points()
	var mid := pts[int(pts.size() * 0.5)]
	assert_bool(_field.on_road(mid.x, mid.z))\
		.override_failure_message("середина серпантина должна считаться дорогой")\
		.is_true()


func test_nearest_intersection_snaps_to_grid() -> void:
	assert_vector(_field.nearest_intersection(5.0, -3.0)).is_equal(Vector2(0.0, 0.0))
	assert_vector(_field.nearest_intersection(60.0, 70.0)).is_equal(Vector2(64.0, 64.0))
	assert_vector(_field.nearest_intersection(-1000.0, 1000.0))\
		.is_equal(Vector2(-256.0, 256.0))


func test_height_query_is_cheap() -> void:
	# height_at зовётся физикой каждый кадр для машины и пешеходов —
	# он обязан быть O(1), а не обходом оси серпантина.
	var t0 := Time.get_ticks_usec()
	var acc := 0.0
	for i in 20000:
		acc += _field.height_at(float(i % 380) - 190.0, -260.0 - float(i % 380))
	var us := Time.get_ticks_usec() - t0
	assert_float(acc).is_greater(0.0)
	assert_int(us)\
		.override_failure_message("20000 запросов height_at заняли %d мкс" % us)\
		.is_less(200_000)
