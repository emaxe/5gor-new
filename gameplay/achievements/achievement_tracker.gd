class_name AchievementTracker
extends RefCounted
## Разблокировка достижений: сверяет Db.achievements с Game.all_stats() и
## однократно эмитит Bus.achievement_unlocked при выполнении условий.
##
## Живёт в Game.achievements — не сбрасывается start_shift(), как и
## Game.garage (см. комментарий там же): достижения — мета-прогрессия,
## а не состояние смены.

var unlocked: Array[StringName] = []


func is_unlocked(id: StringName) -> bool:
	return id in unlocked


## Вызывается после каждого изменения статистики (Game.bump/track_max/
## track_shift_max/add_money/add_rating) — достижений мало (29), а не
## тысячи, поэтому полный проход по каталогу на каждое изменение дёшево.
func check_unlocks() -> void:
	if Db.achievements == null:
		return
	var stats := Game.all_stats()
	for a: AchievementData in Db.achievements.items:
		if a == null or is_unlocked(a.id):
			continue
		if a.is_met(stats):
			unlocked.append(a.id)
			Bus.achievement_unlocked.emit(a.id)
