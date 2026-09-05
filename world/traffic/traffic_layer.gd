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

## Контактная тень (RenderCaps.needs_contact_shadows()) — единственная опора
## машины на асфальт на Compatibility, где направленных теней нет вовсе.
## Эллипс несколько шире кузова — мягкий силуэт, а не точный контур.
const SHADOW_WIDTH_MARGIN := 0.58
const SHADOW_LENGTH_MARGIN := 0.56
const SHADOW_CENTER_COLOR := Color(0.06, 0.06, 0.07)
const SHADOW_EDGE_COLOR := Color(0.28, 0.27, 0.26)
const SHADOW_Y_OFFSET := 0.02 # см. Y_MARKING - Y_ROAD в city_mesher.gd

var manager := TrafficManager.new()
## Граф, по которому едет трафик. Публичный: тестовые полигоны ставят машины
## на конкретные рёбра (tests/scenes/test_traffic.gd).
var graph: CityGraph

var _bodies: Array[RID] = []
var _shape_cache: Dictionary[Vector3i, BoxShape3D] = {}
var _nodes: Array[MeshInstance3D] = []
var _beacon_red: Array[MeshInstance3D] = []
var _beacon_blue: Array[MeshInstance3D] = []
var _visible_count := 0
var _space: RID
var _field: CityField
var _roll: PackedFloat32Array = PackedFloat32Array()
var _pitch: PackedFloat32Array = PackedFloat32Array()
var _shadow_mm: MultiMeshInstance3D


## Строит SoA-состояние, узлы и коллайдеры. space — get_world_3d().space,
## вызывается после появления игрока (нужна его позиция для первой расстановки).
func setup(catalog: TrafficCatalog, field: CityField, lights: TrafficLightController,
		rng: SeededRng, traffic_count: int, space: RID,
		player_x: float, player_z: float) -> void:
	_space = space
	_field = field
	# Граф трафика строится из тех же девяти осей поля, что и прежняя
	# рельсовая модель: настоящий граф Пятигорска попадёт сюда на этапе 9,
	# и тогда изменится только источник этой строки (см. CityGraphGrid).
	graph = CityGraphGrid.from_field(field)
	manager.setup(catalog, field, graph, lights, rng, traffic_count)
	manager.place_all_near(player_x, player_z)
	_roll.resize(manager.count)
	_roll.fill(0.0)
	_pitch.resize(manager.count)
	_pitch.fill(0.0)
	_build_nodes()
	_build_bodies()
	_build_shadows()
	set_visible_count(traffic_count)


## Один MultiMeshInstance3D на весь трафик — эллипс тени растягивается под
## габарит каждой машины через нестандартный масштаб инстанс-трансформа,
## поэтому одного юнит-меша хватает на все 11 силуэтов разом.
func _build_shadows() -> void:
	var disc := MeshBuilder.new()
	disc.shadow_disc(Vector3.ZERO, 1.0, SHADOW_CENTER_COLOR, SHADOW_EDGE_COLOR, 10)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = disc.commit()
	mm.instance_count = manager.count
	_shadow_mm = MultiMeshInstance3D.new()
	_shadow_mm.name = "TrafficShadows"
	_shadow_mm.multimesh = mm
	_shadow_mm.material_override = PALETTE_MAT
	_shadow_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow_mm)


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
	if _shadow_mm != null:
		_shadow_mm.multimesh.visible_instance_count = _visible_count


## Вызывается миром раз в кадр (не в физическом тике: трафик едет «на
## рельсах», не завязан на move_and_slide, а density/позиция игрока нужны
## актуальными на момент рендера — как dt оригинала).
func tick(delta: float, player_x: float, player_z: float, density: float) -> void:
	if manager.count == 0:
		return
	manager.update(delta, player_x, player_z, density)
	# Раз на весь тик, не на машину: Game.is_night() читает Game.hour один
	# и тот же способ для всех 40 машин.
	var headlights_on := Game.is_night()
	for i in manager.count:
		var visible := i < _visible_count
		var node := _nodes[i]
		node.visible = visible
		if not visible:
			continue
		var wx: float = manager.world_x(i)
		var wz: float = manager.world_z(i)
		var wy: float = ((_field.height_at(wx, wz) if wz <= -260.0 else 0.0) if _field != null else 0.0) + CityMesher.Y_ROAD
		var ang_vel := manager.angular_vel_of(i)
		var spd := manager.speed_of(i)
		var acc := manager.accel_of(i)

		# Целевой крен от центробежной силы: при повороте направо (ang_vel > 0)
		# кузов кренится влево (roll < 0).
		var target_roll := clampf(-spd * ang_vel * 0.012, -0.07, 0.07)
		# Целевой клевок: при торможении (acc < 0) нос опускается (pitch > 0),
		# при разгоне — приподнимается.
		var target_pitch := clampf(-acc * 0.006, -0.06, 0.06)

		var blend := minf(1.0, 10.0 * delta)
		_roll[i] = lerpf(_roll[i], target_roll, blend)
		_pitch[i] = lerpf(_pitch[i], target_pitch, blend)

		var base_xform := Transform3D(Heading.basis_of(manager.heading_of(i)), Vector3(wx, wy, wz))
		var visual_basis := base_xform.basis * Basis.from_euler(Vector3(_pitch[i], 0.0, _roll[i]))
		node.transform = Transform3D(visual_basis, Vector3(wx, wy, wz))
		PhysicsServer3D.body_set_state(_bodies[i], PhysicsServer3D.BODY_STATE_TRANSFORM, base_xform)
		if _beacon_red[i] != null:
			_beacon_red[i].visible = manager.beacon_red_on
			_beacon_blue[i].visible = not manager.beacon_red_on

		# Свет: фары по времени суток (у трафика нет ручного тумблера, как
		# у игрока), стоп/поворотники — из кинематики. Задний ход у трафика
		# невозможен (едет только вперёд по полосе), reverse всегда false.
		node.material_override = CarLampMaterials.get_material(
			headlights_on, manager.is_braking(i),
			manager.turn_a_on(i), manager.turn_b_on(i), false)

		var t := manager.type_of(i)
		var shadow_scale := Basis().scaled(
			Vector3(t.width * SHADOW_WIDTH_MARGIN, 1.0, t.length * SHADOW_LENGTH_MARGIN))
		_shadow_mm.multimesh.set_instance_transform(i, Transform3D(
			base_xform.basis * shadow_scale, Vector3(wx, wy + SHADOW_Y_OFFSET, wz)))



func _exit_tree() -> void:
	for body in _bodies:
		PhysicsServer3D.free_rid(body)
	_bodies.clear()
