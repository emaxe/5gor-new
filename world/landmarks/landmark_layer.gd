class_name LandmarkLayer
extends Node3D
## Уникальные объекты города: 9 из данных (`Db.districts.landmarks`) плюс
## 5 «специальных» без POI-записи — порт `LANDMARKS` (config.js:378) и
## `_specials()` (citygen.js:1004-1333).
##
## Каждый объект — отдельная сохранённая сцена в этой же папке
## (`world/landmarks/<id>.tscn`), которая сама строит свою low-poly геометрию
## в локальных координатах вокруг (0,0,0). Здесь только расстановка по
## мировым координатам и высоте рельефа — геометрия и позиция(данные) не
## смешиваются: сцены не знают, где они стоят, `LandmarkLayer` не знает,
## как они выглядят.
##
## Специальные объекты (орёл, трамвай, три остановки, Бендер, стела) не
## заведены как `LandmarkData`: в оригинале это декор из `_specials()`,
## а не POI из конфига `LANDMARKS` — координаты хардкодятся здесь же,
## взяты из мест вызова в citygen.js.

## Сцены для landmark-ов, у которых есть запись в Db.districts.landmarks —
## геометрия и данные независимы, связь только по id.
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

## Памятник Орлу (citygen.js:1019).
const EAGLE_POS := Vector2(-40.0, -340.0)
## Трамвай паркуется на месте своей стоянки, а не едет по рельсам
## (citygen.js:1209) — анимация вдоль X сознательно не портирована.
const TRAM_POS := Vector2(-200.0, 0.0)
## Остановки «Цветник», «Вокзал», «Лира» (citygen.js:1215-1217).
const TRAM_STOP_POS: Array[Vector2] = [
	Vector2(-36.0, -7.5), Vector2(148.0, 7.5), Vector2(88.0, -7.5),
]
## Памятник Остапу Бендеру у Провала (citygen.js:1251).
const BENDER_POS := Vector2(-74.0, -137.0)
## Въездная стела «ПЯТИГОРСК — КУРОРТ» (citygen.js:1312).
const STELE_POS := Vector2(20.0, 245.0)

var _placed: Array[Node3D] = []


## landmarks обычно Db.districts.landmarks — вынесен параметром, чтобы
## тесты могли подсунуть свой список без похода в автолоады.
func build(field: CityField, landmarks: Array[LandmarkData]) -> void:
	for l in landmarks:
		if l == null:
			continue
		var scene: PackedScene = SCENES.get(l.id)
		if scene == null:
			push_warning("LandmarkLayer: нет сцены для %s" % l.id)
			continue
		_place(scene, l.position, field, String(l.id).capitalize())

	_place(EAGLE_SCENE, EAGLE_POS, field, "Eagle")
	_place(TRAM_SCENE, TRAM_POS, field, "Tram")
	for i in TRAM_STOP_POS.size():
		_place(TRAM_STOP_SCENE, TRAM_STOP_POS[i], field, "TramStop%d" % i)
	_place(BENDER_SCENE, BENDER_POS, field, "Bender")
	_place(STELE_SCENE, STELE_POS, field, "Stele")


func _place(scene: PackedScene, pos: Vector2, field: CityField,
		node_name: String) -> void:
	var inst := scene.instantiate() as Node3D
	inst.name = node_name
	add_child(inst)
	inst.position = Vector3(pos.x, field.height_at(pos.x, pos.y), pos.y)
	_placed.append(inst)


func count() -> int:
	return _placed.size()


## Мировая позиция уже расставленного объекта — для тестов и GPS/POI.
func position_of(index: int) -> Vector3:
	return _placed[index].position
