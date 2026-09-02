class_name SkidConfig
extends Resource
## Следы шин. Порт config.js:189.

## slip = |latSpeed|/8 + ручник; 0.45 ↔ латеральная скорость 3.6 м/с.
@export var min_slip: float = 0.45
## Ниже этой скорости следы не рисуем, м/с.
@export var min_speed: float = 6.0
## Минимальный шаг сегмента ленты, м.
@export var seg_len: float = 0.4
## Кольцевой буфер: 256 шагов × 2 квада ≈ 100 м непрерывного дрифта.
@export var max_segments: int = 256
## Ширина следа одного колеса, м.
@export var width: float = 0.3
@export var color: Color = Color(0.078, 0.086, 0.102, 0.5)
