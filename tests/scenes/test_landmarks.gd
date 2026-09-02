extends Node3D
## Витрина всех 14 достопримечательностей в ряд — визуальная проверка
## силуэтов и коллизий без похода за 300 м по городу за каждой.

const IDS: Array[StringName] = [
	&"eagle", &"tram", &"tram_stop", &"bender", &"tower", &"stele",
	&"cvetnik", &"grot", &"narzan", &"rynok", &"vokzal",
	&"cable", &"gazebo", &"proval",
]

const SCENES := {
	&"eagle": preload("res://world/landmarks/eagle.tscn"),
	&"tram": preload("res://world/landmarks/tram.tscn"),
	&"tram_stop": preload("res://world/landmarks/tram_stop.tscn"),
	&"bender": preload("res://world/landmarks/bender.tscn"),
	&"tower": preload("res://world/landmarks/tower.tscn"),
	&"stele": preload("res://world/landmarks/stele.tscn"),
	&"cvetnik": preload("res://world/landmarks/cvetnik.tscn"),
	&"grot": preload("res://world/landmarks/grot.tscn"),
	&"narzan": preload("res://world/landmarks/narzan.tscn"),
	&"rynok": preload("res://world/landmarks/rynok.tscn"),
	&"vokzal": preload("res://world/landmarks/vokzal.tscn"),
	&"cable": preload("res://world/landmarks/cable.tscn"),
	&"gazebo": preload("res://world/landmarks/gazebo.tscn"),
	&"proval": preload("res://world/landmarks/proval.tscn"),
}

## Шаг по X внутри витрины — под самые крупные объекты (вокзал, цветник).
const SPACING := 70.0


func _ready() -> void:
	var field := CityField.new(Db.balance)
	var i := 0
	for id: StringName in IDS:
		var scene: PackedScene = SCENES.get(id)
		if scene == null:
			continue
		var inst := scene.instantiate() as Node3D
		add_child(inst)
		var x := (i - 6) * SPACING
		inst.position = Vector3(x, field.height_at(x, 0.0), 0.0)
		i += 1

	_ground()
	_place_camera()


func _ground() -> void:
	var b := MeshBuilder.new()
	b.plane_xz(Vector3.ZERO, Vector2(1100.0, 200.0), Color("#3a3f46"))
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = preload("res://fx/materials/mat_palette.tres")
	add_child(mi)


func _place_camera() -> void:
	var cam := $Camera3D as Camera3D
	var idx := 0
	var args := OS.get_cmdline_user_args()
	var i := args.find("--view")
	if i >= 0 and i + 1 < args.size():
		idx = args[i + 1].to_int()
	match idx:
		1: # орёл(-420)/трамвай(-350)/остановка(-280)/Бендер(-210)
			cam.position = Vector3(-315.0, 22.0, 110.0)
			cam.look_at(Vector3(-315.0, 2.0, 0.0), Vector3.UP)
		2: # башня(-140)/стела(-70)/цветник(0)
			cam.position = Vector3(-70.0, 14.0, 30.0)
			cam.look_at(Vector3(-70.0, 3.0, 0.0), Vector3.UP)
		3: # грот(70)/нарзан(140)/рынок(210)/вокзал(280)
			cam.position = Vector3(175.0, 18.0, 55.0)
			cam.look_at(Vector3(175.0, 4.0, 0.0), Vector3.UP)
		4: # канатка(350)/беседка(420)/провал(490)
			cam.position = Vector3(420.0, 14.0, 40.0)
			cam.look_at(Vector3(420.0, 3.0, 0.0), Vector3.UP)
		5: # орёл крупным планом
			cam.position = Vector3(-420.0, 6.0, 10.0)
			cam.look_at(Vector3(-420.0, 3.0, 0.0), Vector3.UP)
		6: # Бендер крупным планом
			cam.position = Vector3(-210.0, 3.0, 6.0)
			cam.look_at(Vector3(-210.0, 1.0, 0.0), Vector3.UP)
		_: # общий план всей витрины сверху
			cam.position = Vector3(0.0, 220.0, 260.0)
			cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
