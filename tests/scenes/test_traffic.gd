extends Node3D
## Полигон трафика: восемь машин в ряд (включая полицию и скорую) — визуальная
## проверка мержнутого меша, ливрей и раздельных ламп мигалки, плюс реально
## едущий трафик поверх настоящего города для проверки правил ПДД глазами.

const ROW_COUNT := 8

var _field: CityField
var _lights: TrafficLightController
var _layer: TrafficLayer
var _city: CityBuilder


func _ready() -> void:
	_city = CityBuilder.new()
	_city.name = "City"
	add_child(_city)
	_city.build(Db.balance, Db.districts)
	_city.refresh_signal_lenses()
	_field = _city.field
	_lights = _city.lights

	_layer = TrafficLayer.new()
	_layer.name = "Traffic"
	add_child(_layer)
	var rng := SeededRng.new(1234)
	_layer.setup(Db.traffic, _field, _lights, rng, Db.balance.traffic_count,
		get_world_3d().space, 0.0, 20.0)
	_place_showcase_row()
	_place_camera()


## Перезаписывает ROW_COUNT машин в ровный ряд лицом к камере — случайная
## расстановка setup() для витрины неудобна. Полиция и скорая берутся
## намеренно (не первые попавшиеся индексы), чтобы мигалка попала в кадр.
func _place_showcase_row() -> void:
	var mgr := _layer.manager
	var slots := PackedInt32Array()
	for i in mgr.count:
		if mgr.type_of(i).id == &"police" or mgr.type_of(i).id == &"ambulance":
			slots.append(i)
	for i in mgr.count:
		if slots.size() >= ROW_COUNT:
			break
		if not slots.has(i):
			slots.append(i)

	for k in slots.size():
		var i: int = slots[k]
		mgr.axis[i] = TrafficLightController.Axis.X_ROAD
		mgr.coord[i] = 0.0
		mgr.pos[i] = (k - slots.size() * 0.5) * 7.0
		mgr.dir[i] = 1.0
		mgr.speed[i] = 4.0
		mgr.target[i] = 4.0
		mgr.turning[i] = 0


func _process(delta: float) -> void:
	_city.lights.advance(delta)
	_city.refresh_signal_lenses()
	if _layer != null:
		_layer.tick(delta, 0.0, 20.0, 1.0)


func _place_camera() -> void:
	var cam := $Camera3D as Camera3D
	var idx := 0
	var args := OS.get_cmdline_user_args()
	var i := args.find("--view")
	if i >= 0 and i + 1 < args.size():
		idx = args[i + 1].to_int()
	match idx:
		1: # перекрёсток со светофором, где реально едет трафик
			cam.position = Vector3(50.0, 26.0, 50.0)
			cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
		_: # витрина: 8 машин в ряд, включая полицию и скорую
			cam.position = Vector3(0.0, 7.0, 26.0)
			cam.look_at(Vector3(0.0, 1.2, 0.0), Vector3.UP)
