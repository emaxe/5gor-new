class_name SfxRecipeLayer
extends Resource
## Один слой SFX-рецепта: один осциллятор/шумовой источник + огибающая
## + фильтр. Порт одного вызова `tone()`/`noiseBurst()` (audiosfx.js).
##
## Многослойные эффекты оригинала (например `horn()` типа 'player' — 4
## одновременных `tone()`, или арпеджио `policeEscape()` — несколько
## последовательных `tone()` со сдвигом `when`) собираются как несколько
## `SfxRecipeLayer` в `SfxRecipe.layers`, каждый со своим `start_offset`.

@export var wave: SfxRecipe.Wave = SfxRecipe.Wave.SINE
## Сдвиг старта слоя относительно начала эффекта, с («when» в оригинале).
@export var start_offset: float = 0.0
@export var duration: float = 0.3

@export_group("Частота")
@export var freq_start: float = 440.0
## Для NOISE не используется (частота фильтра берётся из cutoff_*).
@export var freq_end: float = 440.0
## Экспоненциальный свип (exponentialRampToValueAtTime) или линейный.
@export var freq_exponential: bool = true

@export_group("Огибающая")
## Порт `tone()`: атака фиксирована 0.015 с, дальше единая эксп.-декей-стадия
## без sustain-плато. `noiseBurst()`: атака 0 (мгновенный онсет).
@export var attack: float = 0.015
@export var decay: float = 0.2
## Уровень плато 0..1 (у большинства портируемых эффектов — 0, см. выше).
@export var sustain: float = 0.0
@export var release: float = 0.02

@export_group("Фильтр")
@export var filter: SfxRecipe.Filter = SfxRecipe.Filter.NONE
@export var cutoff_start: float = 8000.0
@export var cutoff_end: float = 8000.0
@export var resonance: float = 0.7

@export_group("Выход")
@export var gain: float = 0.2
## Порт `playbackRate = 0.92 + random()*0.16` у noiseBurst — джиттер скорости
## воспроизведения шума в пределах ±доли. 0 — джиттера нет (детерминированный
## слой, например синус-тон).
@export var noise_rate_jitter: float = 0.0
