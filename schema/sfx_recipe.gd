class_name SfxRecipe
extends Resource
## Рецепт синтеза звукового эффекта. Порт методов SfxLibrary (audiosfx.js) —
## один рецепт = одна именованная функция оригинала (`horn`, `crash`, ...).
##
## Многослойные эффекты (несколько одновременных/последовательных `tone()`
## в одном методе оригинала) — несколько `SfxRecipeLayer` в `layers`.
## Запекается один раз в `AudioStreamWAV` (`audio/synth/sfx_synth.gd`) и
## кэшируется в `user://sfx_cache_v1/<hash>.res` (`audio/synth/sfx_cache.gd`).

enum Wave { SINE, SAW, SQUARE, TRIANGLE, NOISE }
enum Filter { NONE, LOWPASS, HIGHPASS, BANDPASS }

@export var id: StringName = &""
## Шина воспроизведения: &"SFX" | &"UI" | &"Engine" | &"Ambient" | &"Voice".
@export var bus: StringName = &"SFX"
## Суммарная длительность эффекта (хвост самого длинного/позднего слоя).
@export var duration: float = 0.3
@export var layers: Array[SfxRecipeLayer] = []

@export_group("Выход")
## Общий множитель громкости поверх gain отдельных слоёв.
@export var gain: float = 1.0
@export var looping: bool = false
## Сколько вариантов запечь для AudioStreamRandomizer (audiosfx.js квирк:
## случайный выбор типа/частоты каждый раз — здесь заменён на N вариантов,
## выбираемых плеером в рантайме, вместо синтеза на лету).
@export var variants: int = 1
## Разброс высоты между вариантами, полутонов.
@export var variant_pitch_spread: float = 1.0

@export_group("Голосовой бюджет")
## Порт alloc(budgetTag, cooldownTag) (audiocore.js). Пусто — без ограничений.
@export var budget_tag: StringName = &""
@export var cooldown_tag: StringName = &""
