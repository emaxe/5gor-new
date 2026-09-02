class_name CityPlan
extends RefCounted
## Результат фазы планирования города: только данные, никаких нод и ресурсов.
##
## Строится в фоновом потоке, поэтому внутри исключительно Packed*Array —
## их можно безопасно готовить вне главного потока, а затем за несколько
## кадров превратить в меши и коллизии.
##
## Порядок полей повторяет порядок фаз генератора, чтобы план читался как
## опись того, из чего состоит город.

## Сид, которым построен план. Пишется в слот сохранения: город должен быть
## один и тот же от смены к смене, иначе игрок не выучит маршруты.
var seed_value := 0

# --- Здания -----------------------------------------------------------------
## AABB в плане: x0, z0, x1, z1.
var building_rect: PackedVector4Array = PackedVector4Array()
var building_height: PackedFloat32Array = PackedFloat32Array()
var building_facade: PackedColorArray = PackedColorArray()
var building_roof: PackedColorArray = PackedColorArray()
## Индекс района, к которому относится здание.
var building_district: PackedInt32Array = PackedInt32Array()
## Тип крыши: 0 — плоская, 1 — четырёхскатная.
var building_roof_kind: PackedByteArray = PackedByteArray()

# --- Повторяющийся пропс ----------------------------------------------------
## Деревья: xz + масштаб в w, вид в building-независимом массиве.
var tree_pos: PackedVector3Array = PackedVector3Array()
var tree_scale: PackedFloat32Array = PackedFloat32Array()
var tree_kind: PackedByteArray = PackedByteArray()
var tree_color: PackedColorArray = PackedColorArray()

var lamp_pos: PackedVector3Array = PackedVector3Array()
## Поворот вокруг Y: фонарь смотрит кронштейном на дорогу.
var lamp_yaw: PackedFloat32Array = PackedFloat32Array()

var bin_pos: PackedVector3Array = PackedVector3Array()
var bench_pos: PackedVector3Array = PackedVector3Array()
var bench_yaw: PackedFloat32Array = PackedFloat32Array()
var planter_pos: PackedVector3Array = PackedVector3Array()
var bush_pos: PackedVector3Array = PackedVector3Array()
var bush_scale: PackedFloat32Array = PackedFloat32Array()

## Припаркованные машины: позиция, поворот, цвет, силуэт.
var parked_pos: PackedVector3Array = PackedVector3Array()
var parked_yaw: PackedFloat32Array = PackedFloat32Array()
var parked_color: PackedColorArray = PackedColorArray()
var parked_kind: PackedByteArray = PackedByteArray()

## Стойки светофоров: позиция, поворот, индексы перекрёстка и оси.
var signal_pos: PackedVector3Array = PackedVector3Array()
var signal_yaw: PackedFloat32Array = PackedFloat32Array()
var signal_intersection: PackedInt32Array = PackedInt32Array()
var signal_axis: PackedByteArray = PackedByteArray()

## Зебры: центр и поворот. Генерируются из списка переходов графа —
## разметка не может разъехаться с логикой.
var crosswalk_pos: PackedVector3Array = PackedVector3Array()
var crosswalk_yaw: PackedFloat32Array = PackedFloat32Array()

# --- Точки геймплея ---------------------------------------------------------
## Точки подачи такси вдоль дорог.
var pickup_pos: PackedVector2Array = PackedVector2Array()
var pickup_district: PackedInt32Array = PackedInt32Array()

# --- Коллизии ---------------------------------------------------------------
## Круглые препятствия: xz + радиус в z-компоненте.
var circle_collider: PackedVector3Array = PackedVector3Array()


func building_count() -> int:
	return building_height.size()


func add_building(rect: Vector4, height: float, facade: Color, roof: Color,
		district: int, roof_kind: int) -> void:
	building_rect.append(rect)
	building_height.append(height)
	building_facade.append(facade)
	building_roof.append(roof)
	building_district.append(district)
	building_roof_kind.append(roof_kind)


func building_aabb(i: int) -> Rect2:
	var r := building_rect[i]
	return Rect2(r.x, r.y, r.z - r.x, r.w - r.y)


## Итоговая сводка для лога и тестов производительности.
func summary() -> Dictionary:
	return {
		"seed": seed_value,
		"buildings": building_height.size(),
		"trees": tree_pos.size(),
		"lamps": lamp_pos.size(),
		"bins": bin_pos.size(),
		"benches": bench_pos.size(),
		"planters": planter_pos.size(),
		"bushes": bush_pos.size(),
		"parked": parked_pos.size(),
		"signals": signal_pos.size(),
		"crosswalks": crosswalk_pos.size(),
		"pickups": pickup_pos.size(),
	}
