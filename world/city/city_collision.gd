class_name CityCollision
extends RefCounted
## Коллизии города через PhysicsServer3D, без единой ноды.
##
## Зданий и пропсов около тысячи. StaticBody3D + CollisionShape3D на каждый —
## это две тысячи узлов в дереве только ради того, чтобы машина не проехала
## сквозь дом. Здесь один статик-боди на чанк и тысячи шейпов в нём.
##
## Форма шейпа кэшируется по округлённым габаритам: на весь город выходит
## пара сотен уникальных BoxShape3D вместо тысячи.

## Слой физики города.
const LAYER := 1
## Высота коллизии зданий: выше машина всё равно не поднимется.
const BUILDING_HEIGHT := 40.0
## Шаг округления габаритов для кэша шейпов, м.
const SHAPE_QUANT := 0.25
## Размер чанка коллизий.
const CHUNK := 128.0

var _bodies: Array[RID] = []
var _shapes: Dictionary[Vector3i, BoxShape3D] = {}
var _cylinders: Dictionary[int, CylinderShape3D] = {}
var _shape_count := 0


## Строит коллизии по плану города. space — из get_world_3d().space.
func build(space: RID, plan: CityPlan, field: CityField) -> void:
	clear()
	var chunks: Dictionary[Vector2i, RID] = {}

	for i in plan.building_count():
		var r := plan.building_rect[i]
		var center := Vector3((r.x + r.z) * 0.5, BUILDING_HEIGHT * 0.5, (r.y + r.w) * 0.5)
		var size := Vector3(r.z - r.x, BUILDING_HEIGHT, r.w - r.y)
		_add_box(_chunk_body(space, chunks, center), center, size)

	# Стойки светофоров и фонари — цилиндры: в них можно въехать.
	for p in plan.lamp_pos:
		_add_cylinder(_chunk_body(space, chunks, p), p + Vector3(0.0, 2.8, 0.0),
			0.18, 5.6)
	for p in plan.signal_pos:
		_add_cylinder(_chunk_body(space, chunks, p), p + Vector3(0.0, 2.2, 0.0),
			0.22, 4.4)
	for i in plan.bin_pos.size():
		_add_cylinder(_chunk_body(space, chunks, plan.bin_pos[i]),
			plan.bin_pos[i] + Vector3(0.0, 0.45, 0.0), 0.36, 0.9)
	for i in plan.bench_pos.size():
		var p := plan.bench_pos[i]
		_add_box(_chunk_body(space, chunks, p), p + Vector3(0.0, 0.45, 0.0),
			Vector3(1.9, 0.9, 0.6), plan.bench_yaw[i])
	for i in plan.parked_pos.size():
		var p := plan.parked_pos[i]
		_add_box(_chunk_body(space, chunks, p), p + Vector3(0.0, 0.75, 0.0),
			Vector3(2.0, 1.5, 4.6), plan.parked_yaw[i])
	# Деревья: только ствол, крона проезжаемой быть не должна, но и
	# цепляться за неё на скорости незачем.
	for p in plan.tree_pos:
		_add_cylinder(_chunk_body(space, chunks, p), p + Vector3(0.0, 1.2, 0.0),
			0.42, 2.4)

	# Барьер по границе города: за него выезжать нельзя.
	_add_map_bounds(space, chunks)


func clear() -> void:
	for body in _bodies:
		PhysicsServer3D.free_rid(body)
	_bodies.clear()
	_shapes.clear()
	_cylinders.clear()
	_shape_count = 0


func shape_count() -> int:
	return _shape_count


func body_count() -> int:
	return _bodies.size()


func _chunk_body(space: RID, chunks: Dictionary[Vector2i, RID],
		pos: Vector3) -> RID:
	var key := Vector2i(floori(pos.x / CHUNK), floori(pos.z / CHUNK))
	if chunks.has(key):
		return chunks[key]
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, space)
	PhysicsServer3D.body_set_collision_layer(body, LAYER)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	chunks[key] = body
	_bodies.append(body)
	return body


func _add_box(body: RID, center: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var shape := _box_shape(size)
	var basis := Basis.IDENTITY if is_zero_approx(yaw) \
		else Basis.from_euler(Vector3(0.0, yaw, 0.0))
	PhysicsServer3D.body_add_shape(body, shape.get_rid(), Transform3D(basis, center))
	_shape_count += 1


func _add_cylinder(body: RID, center: Vector3, radius: float,
		height: float) -> void:
	var shape := _cylinder_shape(radius, height)
	PhysicsServer3D.body_add_shape(body, shape.get_rid(),
		Transform3D(Basis.IDENTITY, center))
	_shape_count += 1


## Кэш по округлённым габаритам: сотни одинаковых домов делят один шейп.
func _box_shape(size: Vector3) -> BoxShape3D:
	var key := Vector3i(
		roundi(size.x / SHAPE_QUANT), roundi(size.y / SHAPE_QUANT),
		roundi(size.z / SHAPE_QUANT))
	if _shapes.has(key):
		return _shapes[key]
	var shape := BoxShape3D.new()
	shape.size = Vector3(key) * SHAPE_QUANT
	_shapes[key] = shape
	return shape


func _cylinder_shape(radius: float, height: float) -> CylinderShape3D:
	var key := roundi(radius / SHAPE_QUANT) * 1000 + roundi(height / SHAPE_QUANT)
	if _cylinders.has(key):
		return _cylinders[key]
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	_cylinders[key] = shape
	return shape


## Невидимая стена по краю карты. В оригинале выезд ограничивался проверкой
## координат в коде; здесь это обычная коллизия — машина упирается, а не
## телепортируется обратно.
func _add_map_bounds(space: RID, chunks: Dictionary[Vector2i, RID]) -> void:
	const LIMIT := 312.0
	const THICK := 8.0
	const HEIGHT := 12.0
	for s: float in [-1.0, 1.0]:
		var wall_x := Vector3(s * (LIMIT + THICK * 0.5), HEIGHT * 0.5, 0.0)
		_add_box(_chunk_body(space, chunks, wall_x), wall_x,
			Vector3(THICK, HEIGHT, LIMIT * 2.0 + THICK * 2.0))
		# Южная стена сплошная, северная — с проёмом под серпантин на Машук.
		var wall_z := Vector3(0.0, HEIGHT * 0.5, s * (LIMIT + THICK * 0.5))
		if s > 0.0:
			_add_box(_chunk_body(space, chunks, wall_z), wall_z,
				Vector3(LIMIT * 2.0 + THICK * 2.0, HEIGHT, THICK))
		else:
			for side: float in [-1.0, 1.0]:
				var seg := Vector3(side * (LIMIT + 85.0) * 0.5, HEIGHT * 0.5, wall_z.z)
				_add_box(_chunk_body(space, chunks, seg), seg,
					Vector3(LIMIT - 85.0, HEIGHT, THICK))
