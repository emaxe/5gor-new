class_name RainParticles
extends Node3D
## Дождь-частицы на GPUParticles3D: ~1200 точек падают с неба вокруг игрока.
## В оригинале это была чисто шейдерная система на Points; в Godot
## MultiMesh/Particles3D даёт ту же цену в draw call, но физика
## настоящая (даже если считать её не надо, частицы с лёгкостью заменяются).
##
## Узел живёт как child World (или SkyRig) и в _process() обновляет свою
## позицию по позиции игрока, если тот доступен, — иначе дождь идёт в
## точке (0,0,0), что не имеет смысла.

const RAIN_BOX_SIZE := Vector3(50.0, 55.0, 50.0)
const RAIN_FALL_SPEED := -38.0
const RAIN_WIND := Vector3(-4.0, 0.0, -2.0)
const PARTICLE_COUNT := 1200

@onready var particles: GPUParticles3D = $Particles


func _ready() -> void:
	visible = false


## Включает/выключает дождь. При включении — задаёт эмиссию; при
## выключении — гасит узел, чтобы не висел как пустой объект.
func set_enabled(on: bool) -> void:
	visible = on
	if particles != null:
		particles.emitting = on


## Следит за игроком. Вызывается в _process родителя (World) — позиция
## берётся из world.player.global_position, если есть.
func follow(target: Vector3) -> void:
	global_position = target