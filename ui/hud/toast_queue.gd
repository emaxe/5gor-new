class_name ToastQueue
extends RefCounted
## Политика ротации тостов HUD: не больше max_size одновременно (макс. 3 —
## см. инвентарь UI в docs/plans/init/plan.md). Кого вытеснять при
## переполнении — чистая логика без дерева сцены; таймеры и анимация самих
## панелей остаются в Hud/ToastStack.
##
## Ранг (0=награда, 1=инфо, 2=критическое, см. HudStyle.level_rank())
## приоритезирует вытеснение: при переполнении уходит самый старый тост
## наименьшего присутствующего ранга, но не выше ранга нового — мелкая
## награда не может сбить с экрана «Заказ провален».

var max_size: int

var _ids: Array[int] = []
var _ranks: Dictionary = {}  # int id -> int rank
var _next_id := 0


func _init(p_max_size: int = 3) -> void:
	max_size = p_max_size


## Регистрирует новый тост. Возвращает [new_id, evicted_id]. evicted_id
## равен -1, если вытеснять было некого; если вытеснять некого, а очередь
## уже полна (все существующие тосты рангом не ниже нового), новый тост
## не помещается вовсе и возвращается [-1, -1].
func push(rank: int = 1) -> Array[int]:
	if _ids.size() >= max_size:
		var victim_idx := _find_eviction_candidate(rank)
		if victim_idx < 0:
			return [-1, -1]
		var evicted: int = _ids[victim_idx]
		_ids.remove_at(victim_idx)
		_ranks.erase(evicted)
		var id := _next_id
		_next_id += 1
		_ids.append(id)
		_ranks[id] = rank
		return [id, evicted]

	var id := _next_id
	_next_id += 1
	_ids.append(id)
	_ranks[id] = rank
	return [id, -1]


## Вызывается, когда тост истёк по своему таймеру (а не был вытеснен push()).
func remove(id: int) -> void:
	_ids.erase(id)
	_ranks.erase(id)


func size() -> int:
	return _ids.size()


## Индекс самого старого тоста с наименьшим рангом среди тех, что не выше
## new_rank; -1, если таких нет (все текущие тосты строго важнее нового).
func _find_eviction_candidate(new_rank: int) -> int:
	var best_idx := -1
	var best_rank := 999
	for i in _ids.size():
		var r: int = _ranks[_ids[i]]
		if r <= new_rank and r < best_rank:
			best_rank = r
			best_idx = i
	return best_idx
