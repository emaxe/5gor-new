class_name SfxRecipe
extends Resource
## Рецепт синтеза звукового эффекта. Порт методов audiosfx.js в данные.
## Запекается один раз в AudioStreamWAV и кэшируется в user://sfx_cache_v*/.

enum Wave { SINE, SAW, SQUARE, TRIANGLE, NOISE }
enum Filter { NONE, LOWPASS, HIGHPASS, BANDPASS }

@export var id: StringName = &""
## Шина: &"sfx" | &"ui" | &"engine" | &"ambient" | &"voice".
@export var bus: StringName = &"sfx"
@export var duration: float = 0.3

@export_group("Осциллятор")
@export var wave: Wave = Wave.SINE
@export var freq_start: float = 440.0
@export var freq_end: float = 440.0
## Экспоненциальный (true) или линейный (false) свип частоты.
@export var freq_exponential: bool = true
## Доля шума в миксе 0..1.
@export var noise_mix: float = 0.0
## Расстройка второго голоса в полутонах (0 — второго голоса нет).
@export var detune_semitones: float = 0.0

@export_group("Огибающая")
@export var attack: float = 0.005
@export var decay: float = 0.05
@export var sustain: float = 0.6
@export var release: float = 0.2

@export_group("Фильтр")
@export var filter: Filter = Filter.NONE
@export var cutoff_start: float = 8000.0
@export var cutoff_end: float = 2000.0
@export var resonance: float = 0.7

@export_group("Выход")
@export var gain: float = 0.8
## Зациклить (для непрерывных слоёв: двигатель, скид, ветер).
@export var looping: bool = false
## Сколько вариантов запечь для AudioStreamRandomizer.
@export var variants: int = 1
## Разброс высоты между вариантами, полутонов.
@export var variant_pitch_spread: float = 1.0
