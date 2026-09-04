extends GdUnitTestSuite
## Шины AudioServer (autoload/audio_director.gd) и их применение Prefs.
##
## Регрессия на баг из отчёта этапа 17: раньше `Prefs` автозагружался ДО
## `Audio`, поэтому на старте `AudioServer.get_bus_index()` возвращал -1 для
## всех шин, и `Prefs._apply_bus()` тихо становился no-op. Починка — шины
## теперь создаются в `Audio._ready()` программно, а `Audio` в
## `project.godot` идёт раньше `Prefs`.


func test_all_seven_buses_exist() -> void:
	var names := ["Master", "Music", "SFX", "Engine", "Ambient", "UI", "Voice"]
	for n in names:
		assert_int(AudioServer.get_bus_index(n)).is_greater_equal(0)
	assert_int(AudioServer.bus_count).is_equal(names.size())


func test_prefs_volumes_are_actually_applied_to_buses() -> void:
	for bus_name: StringName in Prefs.DEFAULT_VOLUMES:
		var idx := AudioServer.get_bus_index(String(bus_name))
		assert_int(idx).is_greater_equal(0)
		var linear: float = maxf(Prefs.volumes.get(bus_name, 0.0), 0.0001)
		var expected_db := linear_to_db(linear)
		assert_float(AudioServer.get_bus_volume_db(idx)).is_equal_approx(expected_db, 0.01)


func test_music_bus_has_sidechain_compressor_on_voice() -> void:
	var idx := AudioServer.get_bus_index("Music")
	var found := false
	for i in AudioServer.get_bus_effect_count(idx):
		var fx := AudioServer.get_bus_effect(idx, i)
		if fx is AudioEffectCompressor and (fx as AudioEffectCompressor).sidechain == &"Voice":
			found = true
	assert_bool(found).is_true()


func test_master_bus_has_limiter() -> void:
	var idx := AudioServer.get_bus_index("Master")
	var found := false
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectLimiter:
			found = true
	assert_bool(found).is_true()
