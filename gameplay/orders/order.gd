class_name Order
extends RefCounted
## Экземпляр заказа такси (обычные поездки, доставка, VIP, сюжетные миссии).

var id: int = 0
var type_id: StringName = &"normal"
var mission_id: StringName = &""
var title: String = ""
var desc: String = ""
var icon: String = "P"
var color: Color = Color("#3e8ede")

var client_name: String = ""
var client_avatar: String = "👨‍💼"

## Точка подачи (мировые координаты XZ).
var pickup_pos := Vector2.ZERO
var pickup_district: StringName = &"center"

## Точки высадки: массив словарей {"pos": Vector2, "name": String, "district": StringName}
var drops: Array[Dictionary] = []
var drop_idx: int = 0

## Состояние: &"open" | &"active" | &"done" | &"failed" | &"expired"
var state: StringName = &"open"

var est_pay: int = 0
var final_pay: int = 0
var tips: int = 0
var stars: int = 5
var review: String = ""

var time_limit: float = 0.0
var timer: float = 0.0
var dist_m: float = 0.0
var drunk_changed: bool = false
var fragile_broken: bool = false
var start_time_msec: int = 0
var age: float = 0.0


func current_drop() -> Dictionary:
	if drop_idx >= 0 and drop_idx < drops.size():
		return drops[drop_idx]
	return {}


func current_target_pos() -> Vector2:
	if state == &"open":
		return pickup_pos
	var d := current_drop()
	return d.get("pos", pickup_pos)


func is_last_drop() -> bool:
	return drop_idx >= drops.size() - 1


func total_stops() -> int:
	return drops.size()
