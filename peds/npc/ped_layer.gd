class_name PedLayer
extends Node3D
## Сцена пешеходов: переносит состояние PedManager (RefCounted, без нод) в
## риг из MeshInstance3D-пивотов и анимирует его. Порт `_animate()`
## (peds.js:664-744), упрощённый: пофазный синус вместо покадрового
## Date.now(), без реплик/пузырей (нет UI — придут вместе с этапом juice/UI).
##
## Каждый пешеход — 4-6 узлов (торс+голова / 2 руки / 2 ноги у человека;
## тело+голова+хвост+4 ноги у животного), не MultiMesh: рукам/ногам нужно
## крутиться при ходьбе. При pedCount ~34-120 это не больше по счёту, чем
## трафик — тот же компромисс, что и в world/traffic/traffic_layer.gd.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

var manager := PedManager.new()
var field: CityField

var _roots: Array[Node3D] = []
var _upper: Array[Node3D] = []
var _head_pivot: Array[Node3D] = []
var _arm_pivot: Array[Array] = []
var _leg_pivot: Array[Array] = []
var _tail_pivot: Array[Node3D] = []
var _visible_count := 0


func setup(catalog: PedCatalog, field_: CityField, graph: PedGraph,
		lights: TrafficLightController, config: PedConfig, rng: SeededRng,
		space: RID, ped_count: int, player_x: float, player_z: float) -> void:
	field = field_
	manager.setup(catalog, field, graph, lights, config, rng, space, ped_count)
	manager.place_all_near(player_x, player_z)
	_build_nodes()
	set_visible_count(ped_count)


func _build_nodes() -> void:
	_roots.resize(manager.count)
	_upper.resize(manager.count)
	_head_pivot.resize(manager.count)
	_arm_pivot.resize(manager.count)
	_leg_pivot.resize(manager.count)
	_tail_pivot.resize(manager.count)
	for i in manager.count:
		if manager.is_animal_at(i):
			_build_animal(i)
		else:
			_build_human(i)


func _build_human(i: int) -> void:
	var spec := PedMeshBuilder.Spec.new()
	spec.skin_color = manager.skin_color[i]
	spec.hair_color = manager.hair_color[i]
	spec.shoe_color = manager.shoe_color[i]
	spec.cloth_color = manager.cloth_color[i]
	spec.pants_color = manager.pants_color[i]
	spec.accessories = manager.archetype_of(i).accessories
	var rig := PedMeshBuilder.build_human(spec)

	var root := Node3D.new()
	root.name = "Ped%d" % i
	add_child(root)
	var scale: Vector2 = manager.body_scale[i]
	root.scale = Vector3(scale.y, scale.x, scale.y)

	var upper := Node3D.new()
	root.add_child(upper)
	_add_mesh(upper, rig.torso_mesh)

	var head := Node3D.new()
	head.position = Vector3(0.0, PedMeshBuilder.HEAD_PIVOT_Y, 0.0)
	upper.add_child(head)
	_add_mesh(head, rig.head_mesh)

	var arms: Array[Node3D] = []
	for s: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(s * PedMeshBuilder.HUMAN_ARM_PIVOT.x,
			PedMeshBuilder.HUMAN_ARM_PIVOT.y, PedMeshBuilder.HUMAN_ARM_PIVOT.z)
		upper.add_child(pivot)
		_add_mesh(pivot, rig.arm_mesh)
		arms.append(pivot)

	var legs: Array[Node3D] = []
	for s: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(s * PedMeshBuilder.HUMAN_LEG_PIVOT.x,
			PedMeshBuilder.HUMAN_LEG_PIVOT.y, PedMeshBuilder.HUMAN_LEG_PIVOT.z)
		root.add_child(pivot)
		_add_mesh(pivot, rig.leg_mesh)
		legs.append(pivot)

	_roots[i] = root
	_upper[i] = upper
	_head_pivot[i] = head
	_arm_pivot[i] = arms
	_leg_pivot[i] = legs


func _build_animal(i: int) -> void:
	var arch := manager.archetype_of(i)
	var is_dog := arch.id == &"dog"
	var rig := PedMeshBuilder.build_dog(manager.cloth_color[i], manager.hair_color[i]) \
		if is_dog else PedMeshBuilder.build_cat(manager.cloth_color[i], manager.hair_color[i])

	var root := Node3D.new()
	root.name = "Ped%d" % i
	add_child(root)
	root.scale = Vector3.ONE * (PedMeshBuilder.DOG_SCALE if is_dog else PedMeshBuilder.CAT_SCALE)
	_add_mesh(root, rig.body_mesh)

	var head_p: Vector3 = PedMeshBuilder.DOG_HEAD_PIVOT if is_dog else PedMeshBuilder.CAT_HEAD_PIVOT
	var head := Node3D.new()
	head.position = head_p
	root.add_child(head)
	_add_mesh(head, rig.head_mesh)

	var tail_p: Vector3 = PedMeshBuilder.DOG_TAIL_PIVOT if is_dog else PedMeshBuilder.CAT_TAIL_PIVOT
	var tail := Node3D.new()
	tail.position = tail_p
	root.add_child(tail)
	_add_mesh(tail, rig.tail_mesh)

	var pivots: Array[Vector3] = PedMeshBuilder.DOG_LEG_PIVOTS if is_dog else PedMeshBuilder.CAT_LEG_PIVOTS
	var legs: Array[Node3D] = []
	for p in pivots:
		var pivot := Node3D.new()
		pivot.position = p
		root.add_child(pivot)
		_add_mesh(pivot, rig.leg_mesh)
		legs.append(pivot)

	_roots[i] = root
	_head_pivot[i] = head
	_tail_pivot[i] = tail
	_leg_pivot[i] = legs


func _add_mesh(parent: Node3D, mesh: ArrayMesh) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = PALETTE_MAT
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func set_visible_count(n: int) -> void:
	_visible_count = clampi(n, 0, manager.count)


## Вызывается миром раз в кадр — как трафик, пешеходы «на ногах», не в
## физическом тике (см. world/traffic/traffic_layer.gd::tick).
func tick(delta: float, player_x: float, player_z: float, player_heading: float,
		player_speed: float, player_vx: float, player_vz: float, is_night: bool) -> void:
	if manager.count == 0:
		return
	manager.update(delta, player_x, player_z, player_heading, player_speed,
		player_vx, player_vz, is_night)
	for i in manager.count:
		var visible := i < _visible_count
		var root := _roots[i]
		root.visible = visible
		if not visible:
			continue
		var wx := manager.world_x(i)
		var wz := manager.world_z(i)
		root.position = Vector3(wx, field.height_at(wx, wz), wz)
		root.rotation.y = manager.heading_of(i)
		_animate(i, delta)


func _animate(i: int, delta: float) -> void:
	var mode := manager.mode_of(i)
	var moving := mode == PedManager.Mode.WALK and manager.speed_of(i) > 0.05
	var phase := manager.walk_phase_of(i)

	if manager.is_animal_at(i):
		var legs := _leg_pivot[i]
		if moving:
			var sw := sin(phase * 1.4)
			legs[0].rotation.x = sw * 0.6
			legs[1].rotation.x = -sw * 0.6
			legs[2].rotation.x = -sw * 0.6
			legs[3].rotation.x = sw * 0.6
			_tail_pivot[i].rotation.y = sin(phase * 2.0) * 0.35
			_head_pivot[i].rotation.x = sin(phase * 1.4) * 0.08
		else:
			for l in legs:
				l.rotation.x = 0.0
			_tail_pivot[i].rotation.y = 0.0
			_head_pivot[i].rotation.x = 0.0
		return

	var legs := _leg_pivot[i]
	var arms := _arm_pivot[i]
	var head := _head_pivot[i]
	var upper := _upper[i]

	if mode == PedManager.Mode.KICK:
		var k := manager.kick_progress(i)
		var leg_angle := -sin(k * PI) * 1.35
		legs[1].rotation.x = leg_angle
		legs[0].rotation.x = 0.0
		arms[0].rotation.x = -0.8
		arms[1].rotation.x = 0.8
	elif manager.is_angry(i) and not moving:
		var sw := sin(Time.get_ticks_msec() * 0.012)
		arms[0].rotation.x = -1.2 + sw * 0.3
		arms[1].rotation.x = -1.2 - sw * 0.3
		legs[0].rotation.x = 0.0
		legs[1].rotation.x = 0.0
		head.rotation.y = sin(Time.get_ticks_msec() * 0.02) * 0.25
	elif moving:
		var amp := 0.75 if mode == PedManager.Mode.FLEE else 0.55
		var sw := sin(phase)
		legs[0].rotation.x = sw * amp
		legs[1].rotation.x = -sw * amp
		arms[0].rotation.x = -sw * amp * 0.72
		arms[1].rotation.x = sw * amp * 0.72
	else:
		legs[0].rotation.x = 0.0
		legs[1].rotation.x = 0.0
		arms[0].rotation.x = 0.0
		arms[1].rotation.x = 0.0

	if not manager.is_angry(i) or moving:
		if moving:
			head.rotation.x = sin(phase * 2.0) * 0.05
			head.rotation.y = sin(phase * 0.5) * 0.12
		else:
			var t := Time.get_ticks_msec() * 0.001
			head.rotation.x = sin(t * 0.7) * 0.04
			head.rotation.y = sin(t * 0.55) * 0.35

	if upper != null:
		if moving:
			upper.position.y = absf(sin(phase)) * 0.035
		else:
			upper.position.y = sin(Time.get_ticks_msec() * 0.0016) * 0.008
