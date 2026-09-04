extends GdUnitTestSuite
## Каталог SFX-рецептов (data/audio/radio_catalog.tres, tools/sfx_recipe_data.gd)
## — числа сверены с audiosfx.js в отчёте по этапу 17.


func test_catalog_has_53_recipes() -> void:
	assert_int(Db.stations.sfx.size()).is_equal(53)


func test_horn_player_is_four_layers_on_major_third() -> void:
	var r := Db.stations.get_sfx(&"horn_player")
	assert_object(r).is_not_null()
	assert_int(r.layers.size()).is_equal(4)
	# Две пилы на большую терцию D4/F#4 + два суб-баса октавой/двумя ниже.
	assert_float(r.layers[0].freq_start).is_equal_approx(293.66, 0.01)
	assert_float(r.layers[1].freq_start).is_equal_approx(369.99, 0.01)
	assert_float(r.layers[2].freq_start).is_equal_approx(146.83, 0.01)
	assert_float(r.layers[3].freq_start).is_equal_approx(73.415, 0.001)
	assert_str(String(r.bus)).is_equal("SFX")
	assert_str(String(r.budget_tag)).is_equal("horn")
	assert_str(String(r.cooldown_tag)).is_equal("horn")


func test_crash_tiers_scale_gain_with_impact() -> void:
	var light := Db.stations.get_sfx(&"crash_light")
	var heavy := Db.stations.get_sfx(&"crash_heavy")
	assert_object(light).is_not_null()
	assert_object(heavy).is_not_null()
	# noiseBurst gain = 0.4+k*0.4 -> heavy (k=0.85) громче light (k=0.15).
	assert_float(heavy.layers[0].gain).is_greater(light.layers[0].gain)
	assert_str(String(light.budget_tag)).is_equal("crash")


func test_ped_hit_and_thud_share_ped_budget() -> void:
	var ped_hit := Db.stations.get_sfx(&"ped_hit")
	var thud := Db.stations.get_sfx(&"thud")
	assert_str(String(ped_hit.budget_tag)).is_equal("ped")
	assert_str(String(thud.budget_tag)).is_equal("ped")
	assert_str(String(ped_hit.cooldown_tag)).is_equal("ped_hit")
	assert_str(String(thud.cooldown_tag)).is_equal("thud")


func test_police_escape_level_3_adds_fourth_layer() -> void:
	var lvl1 := Db.stations.get_sfx(&"police_escape_1")
	var lvl3 := Db.stations.get_sfx(&"police_escape_3")
	assert_int(lvl1.layers.size()).is_equal(4) # 3 тона + шумовой свист
	assert_int(lvl3.layers.size()).is_equal(5) # + слой saw на уровне >=3


func test_cash_tiers_have_matching_coin_count() -> void:
	assert_int(Db.stations.get_sfx(&"cash_small").layers.size()).is_equal(2)
	assert_int(Db.stations.get_sfx(&"cash_medium").layers.size()).is_equal(4)
	assert_int(Db.stations.get_sfx(&"cash_large").layers.size()).is_equal(6)


func test_all_recipes_have_at_least_one_layer_and_positive_duration() -> void:
	for r: SfxRecipe in Db.stations.sfx:
		assert_bool(r.layers.is_empty()).is_false()
		assert_float(r.duration).is_greater(0.0)
