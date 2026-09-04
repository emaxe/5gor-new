extends Node3D
## Полигон пешеходов: ряд архетипов крупным планом + живой ИИ поверх
## настоящего города (обход/переходы/светофоры) для визуальной проверки.

const ROW_ARCHETYPES: Array[StringName] = [
	&"regular", &"gopnik", &"grandma", &"runner", &"student", &"businessman",
	&"tourist", &"child", &"elder", &"mom", &"worker", &"musician", &"nurse",
	&"dog", &"cat",
]

var _city: CityBuilder
var _layer: PedLayer


func _ready() -> void:
	_city = CityBuilder.new()
	_city.name = "City"
	add_child(_city)
	_city.build(Db.balance, Db.districts)
	_city.refresh_signal_lenses()

	var poi_pos := PackedVector2Array()
	var poi_tags := PackedStringArray()
	for l in Db.districts.landmarks:
		if l == null:
			continue
		poi_pos.append(l.position)
		poi_tags.append(String(l.id))
	_city.graph.set_pois(poi_pos, poi_tags)

	_layer = PedLayer.new()
	_layer.name = "Pedestrians"
	add_child(_layer)
	var rng := SeededRng.new(2026)
	_layer.setup(Db.peds, _city.field, _city.graph, _city.lights, Db.balance.ped, rng,
		get_world_3d().space, Db.balance.ped_count, 0.0, 20.0)
	_place_showcase_row()
	_place_camera()


## Перезаписывает первые 15 пешеходов в ровный ряд с нужными архетипами —
## случайная расстановка setup() для витрины неудобна.
func _place_showcase_row() -> void:
	var mgr := _layer.manager
	var slots: Dictionary[StringName, int] = {}
	for i in mgr.count:
		var id: StringName = mgr.archetype_of(i).id
		if not slots.has(id):
			slots[id] = i
		if slots.size() >= ROW_ARCHETYPES.size():
			break

	for k in ROW_ARCHETYPES.size():
		var arch_id := ROW_ARCHETYPES[k]
		if not slots.has(arch_id):
			continue
		var i: int = slots[arch_id]
		mgr.x[i] = (k - ROW_ARCHETYPES.size() * 0.5) * 5.0
		mgr.z[i] = 40.0
		mgr.mode[i] = PedManager.Mode.IDLE
		mgr.idle_t[i] = 999.0
		mgr.heading[i] = 0.0


func _process(delta: float) -> void:
	_city.lights.advance(delta)
	_city.refresh_signal_lenses()
	if _layer != null:
		_layer.tick(delta, 0.0, 20.0, 0.0, 0.0, 0.0, 0.0, false)


func _place_camera() -> void:
	var cam := $Camera3D as Camera3D
	var idx := 0
	var args := OS.get_cmdline_user_args()
	var i := args.find("--view")
	if i >= 0 and i + 1 < args.size():
		idx = args[i + 1].to_int()
	match idx:
		1: # живой ИИ на перекрёстке со светофором
			cam.position = Vector3(20.0, 22.0, 44.0)
			cam.look_at(Vector3(0.0, 1.0, 20.0), Vector3.UP)
		2: # крупный план на головы туриста и студента в изометрии
			cam.position = Vector3(-5.0, 3.2, 45.0)
			cam.look_at(Vector3(-5.0, 1.4, 40.0), Vector3.UP)
		3: # вид сверху-сзади (как в геймплее)
			cam.position = Vector3(-6.0, 4.5, 45.5)
			cam.look_at(Vector3(-6.0, 1.3, 40.0), Vector3.UP)
		_: # витрина архетипов в ряд
			cam.position = Vector3(0.0, 3.0, 52.0)
			cam.look_at(Vector3(0.0, 1.4, 40.0), Vector3.UP)
