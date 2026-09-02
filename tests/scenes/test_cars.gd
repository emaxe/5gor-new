extends Node3D
## Витрина процедурных моделей: 7 машин игрока в первом ряду,
## силуэты трафика во втором.

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")

const TRAFFIC_SHOWCASE: Array[StringName] = [
	&"wagon", &"coupe", &"van", &"pickup", &"bus", &"truck", &"retro",
]


func _ready() -> void:
	var i := 0
	for car in Db.cars.items:
		var spec := CarMeshBuilder.Spec.new()
		spec.silhouette = car.shape.silhouette
		spec.width = car.shape.width
		spec.length = car.shape.length
		spec.body_color = car.body_color
		spec.taxi_livery = car.is_taxi
		spec.rim_style = &"chrome" if i % 3 == 0 else &"disc"
		spec.spoiler = car.id == &"sport"
		spec.body_kit = &"sport" if car.id == &"sport" else &"stock"
		_place(CarMeshBuilder.build_merged(spec),
			Vector3((i - 3) * 6.0, 0.0, 0.0), String(car.id))
		i += 1

	i = 0
	for silhouette in TRAFFIC_SHOWCASE:
		var t := Db.traffic.items[0]
		for item in Db.traffic.items:
			if item.silhouette == silhouette:
				t = item
				break
		var spec := CarMeshBuilder.Spec.new()
		spec.silhouette = silhouette
		spec.width = t.width
		spec.length = t.length
		spec.body_color = t.colors[0] if t.colors.size() > 0 else Color.WHITE
		spec.beacon = t.beacon
		spec.police_livery = t.police_livery
		_place(CarMeshBuilder.build_merged(spec),
			Vector3((i - 3) * 7.5, 0.0, 11.0), String(silhouette))
		i += 1

	# Полиция и скорая — отдельно, ради мигалок.
	var police := Db.traffic.get_type(&"police")
	var ps := CarMeshBuilder.Spec.new()
	ps.silhouette = police.silhouette
	ps.width = police.width
	ps.length = police.length
	ps.body_color = police.colors[0]
	ps.beacon = police.beacon
	ps.police_livery = true
	_place(CarMeshBuilder.build_merged(ps), Vector3(-6.0, 0.0, 21.0), "police")

	var amb := Db.traffic.get_type(&"ambulance")
	var as_ := CarMeshBuilder.Spec.new()
	as_.silhouette = amb.silhouette
	as_.width = amb.width
	as_.length = amb.length
	as_.body_color = amb.colors[0]
	as_.beacon = amb.beacon
	_place(CarMeshBuilder.build_merged(as_), Vector3(4.0, 0.0, 21.0), "ambulance")

	_ground()
	_place_camera()


func _place(mesh: ArrayMesh, pos: Vector3, node_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = PALETTE_MAT
	mi.position = pos
	add_child(mi)


func _ground() -> void:
	var b := MeshBuilder.new()
	b.plane_xz(Vector3.ZERO, Vector2(120.0, 120.0), Color("#3a3f46"))
	_place(b.commit(), Vector3.ZERO, "Ground")


func _place_camera() -> void:
	var cam := $Camera3D as Camera3D
	var idx := 0
	var args := OS.get_cmdline_user_args()
	var i := args.find("--view")
	if i >= 0 and i + 1 < args.size():
		idx = args[i + 1].to_int()
	match idx:
		1: # такси в три четверти
			cam.position = Vector3(-13.5, 1.9, -4.6)
			cam.look_at(Vector3(-18.0, 0.7, 0.0), Vector3.UP)
		2: # ряд трафика
			cam.position = Vector3(0.0, 6.0, 26.0)
			cam.look_at(Vector3(0.0, 1.0, 11.0), Vector3.UP)
		_:
			cam.position = Vector3(0.0, 9.0, -16.0)
			cam.look_at(Vector3(0.0, 1.0, 6.0), Vector3.UP)
