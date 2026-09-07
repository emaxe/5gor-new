class_name LandmarkLayer
extends Node3D
## Уникальные объекты города: 9 из данных (`Db.districts.landmarks`) плюс
## 5 «специальных» без POI-записи — порт `LANDMARKS` (config.js:378) и
## `_specials()` (citygen.js:1004-1333).
##
## Каждый объект — отдельная сцена в этой же папке (`world/landmarks/<id>.tscn`),
## которая строит свою low-poly геометрию в локальных координатах.
##
## Разделение дорожной точки и положения здания:
## - В `Db.districts.landmarks` (`data/landmarks/*.tres`) хранятся координаты
##   высадки у тротуара / навигационные точки (curbside dropoff) — по ним едет такси.
## - В `SITE_OFFSETS` заданы смещения фактического расположения 3D-моделей
##   на их участках/парках/площадях, чтобы проезжая часть и перекрёстки
##   были полностью свободны для движения.

const SCENES := {
	&"proval": preload("res://world/landmarks/proval.tscn"),
	&"cvetnik": preload("res://world/landmarks/cvetnik.tscn"),
	&"grot": preload("res://world/landmarks/grot.tscn"),
	&"narzan": preload("res://world/landmarks/narzan.tscn"),
	&"rynok": preload("res://world/landmarks/rynok.tscn"),
	&"vokzal": preload("res://world/landmarks/vokzal.tscn"),
	&"cable": preload("res://world/landmarks/cable.tscn"),
	&"gazebo": preload("res://world/landmarks/gazebo.tscn"),
	&"tower": preload("res://world/landmarks/tower.tscn"),
}

const EAGLE_SCENE := preload("res://world/landmarks/eagle.tscn")
const TRAM_SCENE := preload("res://world/landmarks/tram.tscn")
const TRAM_STOP_SCENE := preload("res://world/landmarks/tram_stop.tscn")
const BENDER_SCENE := preload("res://world/landmarks/bender.tscn")
const STELE_SCENE := preload("res://world/landmarks/stele.tscn")

## Смещения 3D-моделей от дорожных точек (м в плане).
## Здания размещены на своих реальных исторических участках вне проезжей части.
const SITE_OFFSETS: Dictionary[StringName, Vector2] = {
	&"narzan": Vector2(-20.0, -18.0),
	&"cvetnik": Vector2(-22.0, 29.0),
	&"rynok": Vector2(-16.0, 19.0),
	&"vokzal": Vector2(0.0, 36.0),
	&"proval": Vector2(-20.0, 0.0),
	&"cable": Vector2(14.0, 0.0),
	&"gazebo": Vector2(12.0, 6.0),
	&"tower": Vector2(0.0, -14.0),
	&"grot": Vector2(0.0, -5.0),
}

## Поворот 3D-моделей вокруг оси Y (радианы) для ориентации главных фасадов.
const SITE_ROTATIONS: Dictionary[StringName, float] = {
	&"narzan": PI * 0.75,
	&"cvetnik": -PI * 0.5,
	&"rynok": PI,
	&"vokzal": 0.0,
	&"proval": 0.0,
	&"cable": 0.0,
	&"gazebo": 0.0,
	&"tower": 0.0,
	&"grot": 0.0,
}

## Памятник Орлу на скале Горячей горы (citygen.js:1019).
const EAGLE_POS := Vector2(-40.0, -340.0)
const EAGLE_ROT := 0.0

## Трамвай паркуется на месте своей стоянки (citygen.js:1209).
const TRAM_POS := Vector2(-200.0, 0.0)
const TRAM_ROT := 0.0

## Остановки «Цветник», «Вокзал», «Лира» на тротуарах улиц (вне проезжей части).
const TRAM_STOP_POS: Array[Vector2] = [
	Vector2(-41.0, -7.5),
	Vector2(138.0, 86.0),
	Vector2(88.0, -17.5),
]
const TRAM_STOP_ROT: Array[float] = [
	PI * 0.5,
	-0.6,
	PI,
]

## Памятник Остапу Бендеру у входа в Провал на площади перед порталом.
const BENDER_POS := Vector2(-82.0, -158.0)
const BENDER_ROT := PI * 0.5

## Въездная стела «ПЯТИГОРСК» на островке безопасности южного въезда.
const STELE_POS := Vector2(20.0, 245.0)
const STELE_ROT := 0.0

var _placed: Array[Node3D] = []


## landmarks обычно Db.districts.landmarks.
func build(field: CityField, landmarks: Array[LandmarkData]) -> void:
	for l in landmarks:
		if l == null:
			continue
		var scene: PackedScene = SCENES.get(l.id)
		if scene == null:
			push_warning("LandmarkLayer: нет сцены для %s" % l.id)
			continue
		var site_pos: Vector2 = l.position + SITE_OFFSETS.get(l.id, Vector2.ZERO)
		var rot_y: float = SITE_ROTATIONS.get(l.id, 0.0)
		_place(scene, site_pos, field, String(l.id).capitalize(), rot_y)

	_place(EAGLE_SCENE, EAGLE_POS, field, "Eagle", EAGLE_ROT)
	_place(TRAM_SCENE, TRAM_POS, field, "Tram", TRAM_ROT)
	for i in TRAM_STOP_POS.size():
		_place(TRAM_STOP_SCENE, TRAM_STOP_POS[i], field, "TramStop%d" % i, TRAM_STOP_ROT[i])
	_place(BENDER_SCENE, BENDER_POS, field, "Bender", BENDER_ROT)
	_place(STELE_SCENE, STELE_POS, field, "Stele", STELE_ROT)


func _place(scene: PackedScene, pos: Vector2, field: CityField,
		node_name: String, rot_y: float = 0.0) -> void:
	var inst := scene.instantiate() as Node3D
	inst.name = node_name
	add_child(inst)
	inst.position = Vector3(pos.x, field.height_at(pos.x, pos.y), pos.y)
	inst.rotation.y = rot_y
	_placed.append(inst)


func count() -> int:
	return _placed.size()


## Мировая позиция уже расставленного объекта — для тестов и GPS/POI.
func position_of(index: int) -> Vector3:
	return _placed[index].position
