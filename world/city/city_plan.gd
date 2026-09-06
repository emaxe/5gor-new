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
## Габарит в плане: x0, z0, x1, z1 — В СОБСТВЕННЫХ ОСЯХ здания, повёрнутых
## на `building_yaw` вокруг центра прямоугольника. При нулевом повороте это
## тот же AABB в мировых осях, что и раньше, поэтому сеточный `CityPlanner`
## и все его потребители работают без изменений.
var building_rect: PackedVector4Array = PackedVector4Array()
## Поворот вокруг Y: локальная ось X идёт вдоль фасада, локальная +Z — вглубь
## квартала (`yaw = atan2(-tz, tx)` от касательной улицы). Периметральная
## застройка по полигону квартала ставит дома фронтом вдоль улицы, а улицы в
## настоящем городе по осям X/Z не выровнены.
var building_yaw: PackedFloat32Array = PackedFloat32Array()
## Высота земли под четырьмя углами здания в порядке (-x,-z), (+x,-z),
## (+x,+z), (-x,+z) локальных осей. Нужна цоколю: на квартале с уклоном одна
## отметка на центр оставила бы часть дома висеть в воздухе. Весь нынешний
## город плоский (`CityField.height_at` = 0 южнее z = -260), поэтому здесь
## нули — но это ДАННЫЕ рельефа, а не допущение о плоскости.
var building_ground: PackedVector4Array = PackedVector4Array()
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

## Стойки светофоров: позиция и поворот. Кто из них какой подход какого узла
## обслуживает, знает `NodeSignalPlan` — плану города это не нужно, он несёт
## стойки только ради меша и коллизии.
var signal_pos: PackedVector3Array = PackedVector3Array()
var signal_yaw: PackedFloat32Array = PackedFloat32Array()

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
		district: int, roof_kind: int, yaw: float = 0.0,
		ground: Vector4 = Vector4.ZERO) -> void:
	building_rect.append(rect)
	building_yaw.append(yaw)
	building_ground.append(ground)
	building_height.append(height)
	building_facade.append(facade)
	building_roof.append(roof)
	building_district.append(district)
	building_roof_kind.append(roof_kind)


## Габарит в собственных осях здания. При `building_yaw[i] == 0` — он же
## и мировой AABB.
func building_aabb(i: int) -> Rect2:
	var r := building_rect[i]
	return Rect2(r.x, r.y, r.z - r.x, r.w - r.y)


func building_center(i: int) -> Vector2:
	var r := building_rect[i]
	return Vector2((r.x + r.z) * 0.5, (r.y + r.w) * 0.5)


## Габарит в плане: длина фасада по локальному X, глубина корпуса по Z.
func building_size(i: int) -> Vector2:
	var r := building_rect[i]
	return Vector2(r.z - r.x, r.w - r.y)


## Четыре угла в мировых осях, порядок как у `building_ground`.
func building_corners(i: int) -> PackedVector2Array:
	var c := building_center(i)
	var h := building_size(i) * 0.5
	var yaw := building_yaw[i]
	var ex := Vector2(cos(yaw), -sin(yaw)) * h.x
	var ez := Vector2(sin(yaw), cos(yaw)) * h.y
	return PackedVector2Array([
		c - ex - ez, c + ex - ez, c + ex + ez, c - ex + ez])


## Мировой AABB вокруг повёрнутого габарита — для хешей и чанков.
func building_world_aabb(i: int) -> Rect2:
	if is_zero_approx(building_yaw[i]):
		return building_aabb(i)
	var pts := building_corners(i)
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo, hi - lo)


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
