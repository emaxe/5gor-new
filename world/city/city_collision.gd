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
## Перекрытие соседних плит деки по длине, м. Плиты стыкуются торец в торец,
## и просто соприкоснуться им мало: луч, пущенный точно в стык, обязан
## попасть в деку, а не провалиться на улицу под мостом. 5 см — заведомо
## больше погрешности float на координатах города (сотни метров).
const DECK_JOINT_OVERLAP := 0.05
## Размер чанка коллизий.
const CHUNK := 128.0

var _bodies: Array[RID] = []
var _shapes: Dictionary[Vector3i, BoxShape3D] = {}
var _cylinders: Dictionary[int, CylinderShape3D] = {}
## Шейпы точного габарита (плиты деки). Держатся ссылкой, иначе Resource
## освободится и RID в теле станет висячим.
var _exact_shapes: Array[BoxShape3D] = []
## Статик-боди по чанкам. Поле, а не локальная переменная `build()`, чтобы
## коллизии, добавленные после плана (мосты), попадали в те же тела, а не
## заводили второй набор.
var _chunks: Dictionary[Vector2i, RID] = {}
var _shape_count := 0


## Строит коллизии по плану города. space — из get_world_3d().space.
func build(space: RID, plan: CityPlan, field: CityField) -> void:
	clear()

	# Здание — коробка с поворотом, как лавка или припаркованная машина ниже:
	# на улице, идущей по диагонали, дом стоит вдоль неё, и AABB торчал бы
	# углом на проезжую часть. При нулевом повороте `_add_box` берёт
	# `Basis.IDENTITY` и форма та же, что была.
	for i in plan.building_count():
		var c := plan.building_center(i)
		var s := plan.building_size(i)
		var center := Vector3(c.x, BUILDING_HEIGHT * 0.5, c.y)
		_add_box(_chunk_body(space, center), center,
			Vector3(s.x, BUILDING_HEIGHT, s.y), plan.building_yaw[i])

	# Стойки светофоров и фонари — цилиндры: в них можно въехать.
	for p in plan.lamp_pos:
		_add_cylinder(_chunk_body(space, p), p + Vector3(0.0, 2.8, 0.0),
			0.18, 5.6)
	for p in plan.signal_pos:
		_add_cylinder(_chunk_body(space, p), p + Vector3(0.0, 2.2, 0.0),
			0.22, 4.4)
	for i in plan.bin_pos.size():
		_add_cylinder(_chunk_body(space, plan.bin_pos[i]),
			plan.bin_pos[i] + Vector3(0.0, 0.45, 0.0), 0.36, 0.9)
	for i in plan.bench_pos.size():
		var p := plan.bench_pos[i]
		_add_box(_chunk_body(space, p), p + Vector3(0.0, 0.45, 0.0),
			Vector3(1.9, 0.9, 0.6), plan.bench_yaw[i])
	for i in plan.parked_pos.size():
		var p := plan.parked_pos[i]
		_add_box(_chunk_body(space, p), p + Vector3(0.0, 0.75, 0.0),
			Vector3(2.0, 1.5, 4.6), plan.parked_yaw[i])
	# Деревья: только ствол, крона проезжаемой быть не должна, но и
	# цепляться за неё на скорости незачем.
	for p in plan.tree_pos:
		_add_cylinder(_chunk_body(space, p), p + Vector3(0.0, 1.2, 0.0),
			0.42, 2.4)

	# Барьер по границе города: за него выезжать нельзя.
	_add_map_bounds(space)


## Коллизии путепроводов поверх уже построенных (`build()` их стирает, так
## что порядок вызовов — сперва план, потом мосты).
##
## Дека — ТОНКАЯ плита на своей высоте, а не объём от земли до полотна: под
## мостом обязано остаться проезжим, это два разных прохода по одному (x, z).
## Единственные тела между землёй и декой — опоры, они же и видны глазу.
##
## Перила физического барьера не получают намеренно: машина держится на
## поверхности запросом высоты (`CityGraph.surface_y_at`), а не контактом,
## и «съехать» с деки вбок ей нечем. Появится физический контакт с полотном
## (этап 9) — барьер добавляется сюда же, к плите.
##
## Плиты — единственные тела города, которые обязаны стыковаться в сплошное
## полотно, поэтому им не годится кэш округлённых форм: на 8-метровом
## сегменте `_box_shape` даёт 8.00 м вместо 8.12, и каждый стык становится
## 12-сантиметровой сквозной щелью. Отсюда точный габарит плюс перекрытие.
func build_bridges(space: RID, bridges: BridgeGeometry) -> void:
	for i in bridges.deck_count():
		var c := bridges.deck_center[i]
		var size := bridges.deck_size[i] + Vector3(0.0, 0.0, DECK_JOINT_OVERLAP)
		_add_exact_box(_chunk_body(space, c), c, size, bridges.deck_yaw[i])
	for i in bridges.pier_count():
		var base := bridges.pier_base[i]
		var h := bridges.pier_height[i]
		_add_cylinder(_chunk_body(space, base),
			base + Vector3(0.0, h * 0.5, 0.0), BridgeGeometry.PIER_RADIUS, h)


func clear() -> void:
	for body in _bodies:
		PhysicsServer3D.free_rid(body)
	_bodies.clear()
	_shapes.clear()
	_cylinders.clear()
	_exact_shapes.clear()
	_chunks.clear()
	_shape_count = 0


func shape_count() -> int:
	return _shape_count


func body_count() -> int:
	return _bodies.size()


func _chunk_body(space: RID, pos: Vector3) -> RID:
	var key := Vector2i(floori(pos.x / CHUNK), floori(pos.z / CHUNK))
	if _chunks.has(key):
		return _chunks[key]
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, space)
	PhysicsServer3D.body_set_collision_layer(body, LAYER)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	_chunks[key] = body
	_bodies.append(body)
	return body


func _add_box(body: RID, center: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var shape := _box_shape(size)
	var basis := Basis.IDENTITY if is_zero_approx(yaw) \
		else Basis.from_euler(Vector3(0.0, yaw, 0.0))
	PhysicsServer3D.body_add_shape(body, shape.get_rid(), Transform3D(basis, center))
	_shape_count += 1


## Бокс точного габарита, мимо кэша округлённых форм. Кэш экономит сотни
## одинаковых шейпов на застройке и пропсе; плит деки на весь город единицы,
## и точность размера им важнее экономии.
func _add_exact_box(body: RID, center: Vector3, size: Vector3,
		yaw: float) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	_exact_shapes.append(shape)
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
func _add_map_bounds(space: RID) -> void:
	const LIMIT := 312.0
	const THICK := 8.0
	const HEIGHT := 12.0
	for s: float in [-1.0, 1.0]:
		var wall_x := Vector3(s * (LIMIT + THICK * 0.5), HEIGHT * 0.5, 0.0)
		_add_box(_chunk_body(space, wall_x), wall_x,
			Vector3(THICK, HEIGHT, LIMIT * 2.0 + THICK * 2.0))
		# Южная стена сплошная, северная — с проёмом под серпантин на Машук.
		var wall_z := Vector3(0.0, HEIGHT * 0.5, s * (LIMIT + THICK * 0.5))
		if s > 0.0:
			_add_box(_chunk_body(space, wall_z), wall_z,
				Vector3(LIMIT * 2.0 + THICK * 2.0, HEIGHT, THICK))
		else:
			for side: float in [-1.0, 1.0]:
				var seg := Vector3(side * (LIMIT + 85.0) * 0.5, HEIGHT * 0.5, wall_z.z)
				_add_box(_chunk_body(space, seg), seg,
					Vector3(LIMIT - 85.0, HEIGHT, THICK))
