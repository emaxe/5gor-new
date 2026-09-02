class_name PlayerCar
extends CharacterBody3D
## Машина игрока: аркадная кинематика из CarPhysics плюс разбор столкновений.
##
## Коллайдер — три капсулы вдоль оси (перед, центр, зад) с радиусом в
## полуширину кузова. Это точный эквивалент «капсулы из трёх кругов»
## оригинала (player.js:302-325): боковая досягаемость равна ширине кузова
## в любой точке, поэтому сбить столб можно только реально задев его.
## Двух кругов мало: у длинной машины между ними образуется провал, сквозь
## который пешеход проходит насквозь.

signal crashed(impact: float, victim: StringName)

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")
## Отскок от статики и от машин (player.js:_resolve).
const BOUNCE_STATIC := 1.5
const BOUNCE_CAR := 1.35
## Порог сближения, ниже которого удар считается столкновением.
const IMPACT_THRESHOLD := 2.0
## Высота капсулы: машина ездит только в плоскости, вертикаль не важна.
const CAPSULE_HEIGHT := 1.4
## Сглаживание визуальных кренов кузова за 1/60 с (player.js: lerp 0.14/0.15).
const BODY_DAMP := 0.14
const STEER_DAMP := 0.15
## Максимальный угол поворота передних колёс, рад.
const WHEEL_STEER := 0.5

var runtime := CarRuntime.new()
var motion := CarPhysics.Motion.new()
var field: CityField

var _body: Node3D
var _wheels: Array[Node3D] = []
var _front_pivots: Array[Node3D] = []
var _shapes: Array[CollisionShape3D] = []
var _surface := CarPhysics.Surface.new()
var _visual_roll := 0.0
var _visual_pitch := 0.0
var _steer_visual := 0.0
var _wheel_spin := 0.0
var _headlights: Array[SpotLight3D] = []
var _lights_on := false


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	up_direction = Vector3.UP
	safe_margin = 0.02
	max_slides = 4
	wall_min_slide_angle = 0.0
	collision_layer = 2
	collision_mask = 1 | TrafficManager.COLLISION_LAYER


## Собирает машину заданного типа: коллайдер, кузов, колёса, фары.
func setup(data: CarData, upgrades: UpgradeCatalog, city_field: CityField) -> void:
	field = city_field
	runtime.setup(data, upgrades)
	_build_collider(data.shape)
	_build_visuals(data)


func _build_collider(shape: CarShapeData) -> void:
	for c in _shapes:
		c.queue_free()
	_shapes.clear()
	var capsule := CapsuleShape3D.new()
	capsule.radius = shape.collider_radius()
	capsule.height = CAPSULE_HEIGHT
	var sep := shape.collider_separation()
	# Один ресурс шейпа на три ноды: смена машины — правка радиуса в одном месте.
	for z: float in [sep, 0.0, -sep]:
		var cs := CollisionShape3D.new()
		cs.shape = capsule
		cs.position = Vector3(0.0, CAPSULE_HEIGHT * 0.5, z)
		add_child(cs)
		_shapes.append(cs)


func _build_visuals(data: CarData) -> void:
	if _body != null:
		_body.queue_free()
	_wheels.clear()
	_front_pivots.clear()
	_headlights.clear()

	var spec := CarMeshBuilder.Spec.new()
	spec.silhouette = data.shape.silhouette
	spec.width = data.shape.width
	spec.length = data.shape.length
	spec.body_color = data.body_color
	spec.taxi_livery = data.is_taxi

	# Крены применяются к этому узлу, а не к телу: иначе вместе с кузовом
	# наклонялся бы коллайдер и машина цеплялась бы за бордюры.
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	var chassis := MeshInstance3D.new()
	chassis.name = "Chassis"
	chassis.mesh = CarMeshBuilder.build_body(spec)
	chassis.material_override = PALETTE_MAT
	_body.add_child(chassis)

	var wheel_mesh := CarMeshBuilder.build_wheel(spec)
	var s := CarMeshBuilder.shape_of(spec.silhouette)
	var r: float = s["wheel_r"]
	var hw := spec.width * 0.5 - 0.12
	var hl := spec.length * 0.5 - r - 0.24
	for sz: float in [1.0, -1.0]:
		for sx: float in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(sx * hw, r, sz * hl)
			_body.add_child(pivot)
			var wheel := MeshInstance3D.new()
			wheel.mesh = wheel_mesh
			wheel.material_override = PALETTE_MAT
			pivot.add_child(wheel)
			_wheels.append(wheel)
			if sz > 0.0:
				_front_pivots.append(pivot)

	# Фары: реальный свет только у машины игрока — в трафике это эмиссия.
	for sx: float in [-1.0, 1.0]:
		var light := SpotLight3D.new()
		light.position = Vector3(sx * spec.width * 0.32, 0.85, spec.length * 0.5)
		light.rotation = Vector3(-0.06, PI, 0.0)
		light.light_color = Color(1.0, 0.95, 0.82)
		light.light_energy = 4.0
		light.spot_range = 45.0
		light.spot_angle = 34.0
		light.spot_attenuation = 0.9
		light.shadow_enabled = false
		light.visible = false
		_body.add_child(light)
		_headlights.append(light)


# --- Симуляция --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if runtime.stats == null or field == null:
		return
	_sample_surface()
	var axes := Inp.drive_axes()
	motion.position = global_position
	CarPhysics.step(motion, axes, _surface, runtime.stats,
		runtime.engine_dead(), delta)

	# Позиция считается собственной интеграцией, а move_and_slide только
	# разрешает столкновения: velocity здесь — не «куда двигать», а
	# «с какой скоростью мы уже летим».
	velocity = motion.velocity
	move_and_slide()
	_resolve_impacts()

	# Машина едет по рельефу, а не по физическому полу.
	global_position.y = field.height_at(global_position.x, global_position.z)
	motion.position = global_position
	basis = Heading.basis_of(motion.heading)

	runtime.tick(motion, _surface.on_road, delta)
	_update_visuals(axes, delta)


func _sample_surface() -> void:
	_surface.on_road = field.on_road(global_position.x, global_position.z)
	_surface.ground_height = field.height_at(global_position.x, global_position.z)


## Разбор столкновений: направление и коэффициент отскока взяты из оригинала,
## движковый отклик их бы не воспроизвёл.
func _resolve_impacts() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var normal := c.get_normal()
		var vn := motion.velocity.dot(normal)
		if vn >= -IMPACT_THRESHOLD:
			continue
		# Трафик отличается от застройки по слою коллизии, а не по типу
		# ноды: TrafficLayer ставит машины NPC как RID-тела без узлов.
		var rid := c.get_collider_rid()
		var is_car := rid.is_valid() and \
			(PhysicsServer3D.body_get_collision_layer(rid) & TrafficManager.COLLISION_LAYER) != 0
		var victim: StringName = &"car" if is_car else &"static"
		motion.velocity -= normal * vn * (BOUNCE_CAR if is_car else BOUNCE_STATIC)
		var impact := -vn
		runtime.apply_impact(impact, victim)
		crashed.emit(impact, victim)
	velocity = motion.velocity


func _update_visuals(axes: Inp.DriveAxes, delta: float) -> void:
	# Крен и клевок кузова — чистая визуализация, на физику не влияют.
	_visual_roll = MathUtils.damp(_visual_roll, motion.target_roll, BODY_DAMP, delta)
	_visual_pitch = MathUtils.damp(_visual_pitch, motion.target_pitch, BODY_DAMP, delta)
	_body.rotation = Vector3(_visual_pitch, 0.0, _visual_roll)

	_steer_visual = MathUtils.damp(_steer_visual, axes.steer, STEER_DAMP, delta)
	for pivot in _front_pivots:
		pivot.rotation.y = -_steer_visual * WHEEL_STEER

	var r: float = CarMeshBuilder.shape_of(
		runtime.stats.shape.silhouette)["wheel_r"]
	_wheel_spin -= motion.forward_speed / maxf(r, 0.01) * delta
	for wheel in _wheels:
		wheel.rotation.x = _wheel_spin


func set_lights(on: bool) -> void:
	_lights_on = on
	for light in _headlights:
		light.visible = on


func lights_on() -> bool:
	return _lights_on


## Ставит машину в точку и разворачивает по курсу, гася скорость.
func place(pos: Vector3, heading: float) -> void:
	motion.position = pos
	motion.velocity = Vector3.ZERO
	motion.heading = heading
	motion.speed = 0.0
	global_position = Vector3(pos.x, field.height_at(pos.x, pos.z), pos.z)
	basis = Heading.basis_of(heading)


## Скорость в км/ч для HUD.
func speed_kmh() -> float:
	return motion.speed * 3.6
