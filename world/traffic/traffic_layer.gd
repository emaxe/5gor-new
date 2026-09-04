class_name TrafficLayer
extends Node3D
## Сцена трафика: переносит состояние TrafficManager (RefCounted, без нод)
## в MeshInstance3D-пул и в PhysicsServer3D-коллайдеры игрока.
##
## По одному MeshInstance3D на машину, а не MultiMesh: при traffic_count=40
## это на порядок меньше пропсов, чем деревьев/фонарей города, и позволяет
## независимо мигать маячками полиции/скорой без обхода общего материала.
## Пресет графики режет не количество ИИ-агентов (SoA дешёвы), а видимость:
## первые visible_count машин отрисовываются, остальные продолжают ездить
## по ПДД невидимыми — как и в оригинале (game.js:_applyDensity).

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")
## Округление размера коллайдера, м — оправдывает общий BoxShape3D для
## машин с одинаковыми (с точностью до 10 см) габаритами.
const SHAPE_QUANT := 0.1
const COLLIDER_HEIGHT := 1.4

var manager := TrafficManager.new()

var _bodies: Array[RID] = []
var _shape_cache: Dictionary[Vector3i, BoxShape3D] = {}
var _nodes: Array[MeshInstance3D] = []
var _beacon_red: Array[MeshInstance3D] = []
var _beacon_blue: Array[MeshInstance3D] = []
var _visible_count := 0
var _space: RID
var _field: CityField


## Строит SoA-состояние, узлы и коллайдеры. space — get_world_3d().space,
## вызывается после появления игрока (нужна его позиция для первой расстановки).
func setup(catalog: TrafficCatalog, field: CityField, lights: TrafficLightController,
		rng: SeededRng, traffic_count: int, space: RID,
		player_x: float, player_z: float) -> void:
	_space = space
	_field = field
	manager.setup(catalog, field, lights, rng, traffic_count)
	manager.place_all_near(player_x, player_z)
	_build_nodes()
	_build_bodies()
	set_visible_count(traffic_count)


func _build_nodes() -> void:
	for i in manager.count:
		var t := manager.type_of(i)
		var spec := CarMeshBuilder.Spec.new()
		spec.silhouette = t.silhouette
		spec.width = t.width
		spec.length = t.length
		spec.body_color = manager.color_of(i)
		spec.taxi_livery = t.livery
		spec.police_livery = t.police_livery
		spec.body_kit = t.body_kit
		spec.beacon = t.beacon

		var mi := MeshInstance3D.new()
		mi.name = "Traffic%d" % i
		# Маячок — отдельными узлами (ниже, для независимого мигания),
		# кузов всегда печётся без него.
		mi.mesh = CarMeshBuilder.build_merged(spec, false)
		mi.material_override = PALETTE_MAT
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_nodes.append(mi)

		if t.beacon == &"":
			_beacon_red.append(null)
			_beacon_blue.append(null)
			continue
		var red := MeshInstance3D.new()
		red.mesh = CarMeshBuilder.build_beacon_lamp(spec, true)
		red.material_override = PALETTE_MAT
		mi.add_child(red)
		var blue := MeshInstance3D.new()
		blue.mesh = CarMeshBuilder.build_beacon_lamp(spec, false)
		blue.material_override = PALETTE_MAT
		mi.add_child(blue)
		_beacon_red.append(red)
		_beacon_blue.append(blue)


## Коллайдеры трафика — статичные RID-тела без нод (как CityCollision):
## машина сама едет «на рельсах», нам нужно только чтобы игрок в неё не
## проезжал насквозь (PlayerCar._resolve_impacts различает victim &"car"
## по этому слою).
func _build_bodies() -> void:
	for i in manager.count:
		var t := manager.type_of(i)
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_space(body, _space)
		PhysicsServer3D.body_set_collision_layer(body, TrafficManager.COLLISION_LAYER)
		PhysicsServer3D.body_set_collision_mask(body, 0)
		var shape := _box_shape(Vector3(t.width, COLLIDER_HEIGHT, t.length))
		PhysicsServer3D.body_add_shape(body, shape.get_rid(), Transform3D.IDENTITY)
		_bodies.append(body)


func _box_shape(size: Vector3) -> BoxShape3D:
	var key := Vector3i(roundi(size.x / SHAPE_QUANT), roundi(size.y / SHAPE_QUANT),
		roundi(size.z / SHAPE_QUANT))
	if _shape_cache.has(key):
		return _shape_cache[key]
	var shape := BoxShape3D.new()
	shape.size = Vector3(key) * SHAPE_QUANT
	_shape_cache[key] = shape
	return shape


## Сколько первых машин пула рисовать. Остальные продолжают симулироваться
## (SoA дёшев), просто не рендерятся — порт game.js:_applyDensity.
func set_visible_count(n: int) -> void:
	_visible_count = clampi(n, 0, manager.count)
	for i in _bodies.size():
		var visible := i < _visible_count
		PhysicsServer3D.body_set_collision_layer(_bodies[i],
			TrafficManager.COLLISION_LAYER if visible else 0)


## Вызывается миром раз в кадр (не в физическом тике: трафик едет «на
## рельсах», не завязан на move_and_slide, а density/позиция игрока нужны
## актуальными на момент рендера — как dt оригинала).
func tick(delta: float, player_x: float, player_z: float, density: float) -> void:
	if manager.count == 0:
		return
	manager.update(delta, player_x, player_z, density)
	for i in manager.count:
		var visible := i < _visible_count
		var node := _nodes[i]
		node.visible = visible
		if not visible:
			continue
		var wx: float = manager.world_x(i)
		var wz: float = manager.world_z(i)
		var wy: float = ((_field.height_at(wx, wz) if wz <= -260.0 else 0.0) if _field != null else 0.0) + CityMesher.Y_ROAD
		var xform := Transform3D(Heading.basis_of(manager.heading_of(i)), Vector3(wx, wy, wz))
		node.transform = xform
		PhysicsServer3D.body_set_state(_bodies[i], PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
		if _beacon_red[i] != null:
			_beacon_red[i].visible = manager.beacon_red_on
			_beacon_blue[i].visible = not manager.beacon_red_on



func _exit_tree() -> void:
	for body in _bodies:
		PhysicsServer3D.free_rid(body)
	_bodies.clear()
