extends Node3D
## Полигон карт (этап 9): миникарта и большая карта поверх реального города.
##
## Камера — ОРТОГОНАЛЬНАЯ и строго сверху, с вертикальным охватом ровно в
## диаметр миникарты (2 * `Minimap.radius_m`). Благодаря этому снимок можно
## читать как сверку: улицы мира и линии карты обязаны совпасть по форме, а
## не «примерно напоминать» друг друга. Верх экрана — север (-Z), как и на
## большой карте.
##
## Флаги: --panel minimap|map, --at <точка> из списка SPOTS.
##
## Точки привязаны к топологии Пятигорска и выбраны там, где старая сетка
## врала заметнее всего:
##   ring     кольцо Верхнего рынка,
##   mashuk   дуга у подножия Машука и бульвар Гагарина (кривые улицы),
##   center   Кирова x Калинина (регулярный центр — контроль),
##   overpass путепровод улицы Козлова над улицей Крайнего (мост на карте).
const SPOTS: Dictionary[StringName, Vector2] = {
	&"ring": Vector2(96.0, -8.0),
	&"mashuk": Vector2(-70.0, -160.0),
	&"center": Vector2(10.0, 10.0),
	&"overpass": Vector2(82.0, 183.0),
}

## Высота ортокамеры, м: выше самой высокой точки серпантина Машука с запасом.
const CAM_Y := 400.0

## Вертикальный охват ортокамеры, м = 2 * `Minimap.radius_m`: круг миникарты
## и кадр камеры показывают ровно один и тот же кусок города.
const CAM_SPAN := 440.0

## Курс, при котором поворот миникарты `-heading - PI/2` вырождается в ноль и
## она встаёт севером вверх — только так её можно сравнивать с видом камеры.
const NORTH_UP_HEADING := -PI * 0.5

var builder: CityBuilder


func _ready() -> void:
	builder = CityBuilder.new()
	builder.name = "City"
	add_child(builder)
	builder.build(Db.balance, Db.districts, Db.balance.world_seed)
	builder.refresh_signal_lenses()

	var args := OS.get_cmdline_user_args()
	var spot := &"ring"
	var at_i := args.find("--at")
	if at_i >= 0 and at_i + 1 < args.size():
		spot = StringName(args[at_i + 1])
	var pos: Vector2 = SPOTS.get(spot, SPOTS[&"ring"])

	var w := _fake_world(pos)
	_place_camera(pos)

	var panel := &"minimap"
	var p_i := args.find("--panel")
	if p_i >= 0 and p_i + 1 < args.size():
		panel = StringName(args[p_i + 1])
	if panel == &"map":
		_show_map(w)
	else:
		_show_minimap(w)


## World нарочно не добавляется в дерево: World._process() тянет за собой
## погоду, звук и директора — тот же приём, что в test_hud.gd.
func _fake_world(pos: Vector2) -> World:
	var w := World.new()
	w.city = builder
	w.in_car = true
	w.player = PlayerCar.new()
	add_child(w.player)
	w.player.setup(Db.cars.get_car(&"taxi"), Db.upgrades, builder.field)
	var y := builder.field.surface_height_at(pos.x, pos.y)
	w.player.place(Vector3(pos.x, y, pos.y), NORTH_UP_HEADING)
	return w


func _place_camera(pos: Vector2) -> void:
	var cam := $Camera3D as Camera3D
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAM_SPAN
	cam.position = Vector3(pos.x, CAM_Y, pos.y)
	# Вверх экрана — север: у камеры «вверх» это -Z, как ось Y холста карты.
	cam.look_at(Vector3(pos.x, 0.0, pos.y), Vector3(0.0, 0.0, -1.0))


## Две копии миникарты: слева внизу — настоящий размер из HUD (180 px),
## справа — та же карта крупно, иначе на снимке не разобрать ни изгиб улицы,
## ни цвет эстакады.
func _show_minimap(w: World) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	# Слева внизу — ровно та раскладка, что в HUD (hud.gd:_build_minimap).
	_add_minimap(layer, w, Control.PRESET_BOTTOM_LEFT, 16.0, -196.0, 180.0)
	_add_minimap(layer, w, Control.PRESET_BOTTOM_RIGHT, -460.0, -460.0, 440.0)


func _add_minimap(layer: CanvasLayer, w: World, preset: int,
		left: float, top: float, side: float) -> void:
	var mm := Minimap.new()
	mm.world = w
	mm.set_anchors_preset(preset)
	mm.offset_left = left
	mm.offset_top = top
	mm.offset_right = left + side
	mm.offset_bottom = top + side
	layer.add_child(mm)


func _show_map(w: World) -> void:
	Dir.world = w
	var screen := MapScreen.new()
	add_child(screen)
	screen.show_screen()
