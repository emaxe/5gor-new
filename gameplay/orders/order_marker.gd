class_name OrderMarker
extends Node3D
## Трехмерный визуальный маркер заказа в мире (световой столб + парящий значок).

const MAT_PALETTE := preload("res://fx/materials/mat_palette.tres")

var _beam_mesh: MeshInstance3D
var _badge_mesh: MeshInstance3D
var _time: float = 0.0
var _color: Color = Color("#f2c12e")
var _icon: String = "P"


func setup(color: Color, icon: String = "P", is_dropoff: bool = false) -> void:
	_color = color
	_icon = icon
	_time = randf() * TAU

	# 1. Световой столб (вертикальный многогранник от земли до 14 м)
	var b := MeshBuilder.new()
	var beam_col := _color.lerp(Color.WHITE, 0.3)
	beam_col.a = 0.65
	var r := 0.9 if not is_dropoff else 1.4
	var h := 14.0
	b.cylinder(Vector3(0.0, h * 0.5, 0.0), r * 0.7, r * 1.1, h, beam_col, 8)
	b.cylinder(Vector3(0.0, h * 0.5, 0.0), r * 0.3, r * 0.5, h * 1.1, Color.WHITE, 6)

	_beam_mesh = MeshInstance3D.new()
	_beam_mesh.name = "Beam"
	_beam_mesh.mesh = b.commit()
	_beam_mesh.material_override = MAT_PALETTE
	_beam_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam_mesh)

	# 2. Парящий вращающийся ромб-бейдж на высоте 3.8 м
	var badge_b := MeshBuilder.new()
	var by := 3.8
	badge_b.box(Vector3(0.0, by, 0.0), Vector3(1.2, 1.2, 0.18), _color, Basis(Vector3.FORWARD, PI * 0.25))
	badge_b.box(Vector3(0.0, by, 0.0), Vector3(0.9, 0.9, 0.22), Color.WHITE, Basis(Vector3.FORWARD, PI * 0.25))
	badge_b.box(Vector3(0.0, by, 0.0), Vector3(0.65, 0.65, 0.26), Color("#181c24"), Basis(Vector3.FORWARD, PI * 0.25))

	_badge_mesh = MeshInstance3D.new()
	_badge_mesh.name = "Badge"
	_badge_mesh.mesh = badge_b.commit()
	_badge_mesh.material_override = MAT_PALETTE
	_badge_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_badge_mesh)


func tick(delta: float) -> void:
	_time += delta
	if _badge_mesh != null:
		_badge_mesh.rotation.y = _time * 1.8
		_badge_mesh.position.y = sin(_time * 3.0) * 0.25
	if _beam_mesh != null:
		var s := 1.0 + sin(_time * 4.0) * 0.18
		_beam_mesh.scale = Vector3(s, 1.0, s)
