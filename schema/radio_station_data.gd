class_name RadioStationData
extends Resource
## Радиостанция. Порт STATIONS (audiomusic.js:41).
## Музыка синтезируется: сэмплы инструментов запекаются в AudioStreamWAV,
## а секвенсор расписывает их по BPM (см. audio/radio/).

@export var id: StringName = &""
@export var display_name: String = ""
@export var genre: String = ""
@export var frequency: String = ""
@export var bpm: float = 100.0
@export var color: Color = Color.WHITE

@export_group("Музыкальный материал")
## Корневая нота, Гц.
@export var root_hz: float = 110.0
## Квинта, Гц (fallback-дрон оригинала).
@export var fifth_hz: float = 164.81
## Ступени лада относительно корня, в полутонах.
@export var scale_steps: PackedInt32Array = PackedInt32Array([0, 2, 3, 5, 7, 8, 10])
## Инструменты станции: kick|snare|hat|bass|lead|pad|arp.
@export var instruments: PackedStringArray = PackedStringArray()
## Плотность ударных 0..1.
@export var drum_density: float = 0.5
## Насыщенность текстуры 0..1.
@export var texture: float = 0.5
