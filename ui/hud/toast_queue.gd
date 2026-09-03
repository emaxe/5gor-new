class_name ToastQueue
extends RefCounted
## Политика ротации тостов HUD: не больше max_size одновременно (макс. 3 —
## см. инвентарь UI в docs/plans/init/plan.md). Кого вытеснять при
## переполнении — чистая логика без дерева сцены; таймеры и анимация самих
## панелей остаются в Hud.

var max_size: int

var _ids: Array[int] = []
var _next_id := 0


func _init(p_max_size: int = 3) -> void:
	max_size = p_max_size


## Регистрирует новый тост. Возвращает [new_id, evicted_id] — evicted_id
## равен -1, если вытеснять было некого.
func push() -> Array[int]:
	var id := _next_id
	_next_id += 1
	var evicted := -1
	if _ids.size() >= max_size:
		evicted = _ids.pop_front()
	_ids.append(id)
	return [id, evicted]


## Вызывается, когда тост истёк по своему таймеру (а не был вытеснен push()).
func remove(id: int) -> void:
	_ids.erase(id)


func size() -> int:
	return _ids.size()
