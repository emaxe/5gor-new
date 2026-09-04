class_name SfxCache
extends RefCounted
## Кэш запечённых SfxRecipe. Порт «синтезировать один раз, кэшировать, дальше
## только читать» (план, «Аудио — уточнения», п.10).
##
## `user://sfx_cache_v1/<hash>.res`, хэш = id рецепта + CACHE_VERSION —
## поднять версию при изменении формата запекания инвалидирует весь кэш
## разом, не трогая сами .tres рецептов.

const CACHE_DIR := "user://sfx_cache_v1/"
const CACHE_VERSION := 1


## Возвращает готовый к проигрыванию AudioStream: AudioStreamWAV при одном
## варианте, AudioStreamRandomizer при нескольких (audiosfx.js квирк
## случайного выбора тембра/частоты — здесь N вариантов вместо синтеза на лету).
static func get_stream(recipe: SfxRecipe) -> AudioStream:
	if recipe == null or recipe.layers.is_empty():
		return null
	var path := _cache_path(recipe)
	if ResourceLoader.exists(path):
		var cached: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if cached is AudioStream:
			return cached
	var stream := _bake(recipe)
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	ResourceSaver.save(stream, path)
	return stream


## Синтез в память без чтения/записи диска — для тестов детерминизма и для
## случаев, где кэш заведомо не нужен (короткоживущие тестовые рецепты).
static func bake_uncached(recipe: SfxRecipe) -> AudioStream:
	return _bake(recipe)


static func _bake(recipe: SfxRecipe) -> AudioStream:
	var variants := maxi(1, recipe.variants)
	if variants == 1:
		return SfxSynth.synthesize(recipe, 0, 1)
	var rnd := AudioStreamRandomizer.new()
	for v in variants:
		rnd.add_stream(v, SfxSynth.synthesize(recipe, v, variants))
	return rnd


static func _cache_path(recipe: SfxRecipe) -> String:
	var h := absi(hash("%s:%d" % [String(recipe.id), CACHE_VERSION]))
	return CACHE_DIR + str(h) + ".res"
