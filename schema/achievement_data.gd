class_name AchievementData
extends Resource
## Достижение. Порт ACHIEVEMENTS (achievements.js:18).

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Текст баннера при открытии.
@export var toast: String = ""
@export var icon: StringName = &""
## Все условия должны выполниться (AND).
@export var requirements: Array[AchievementReq] = []

@export_group("Прогресс")
## Поле статистики для прогресс-бара. Улучшение: в оригинале ачивки бинарны.
@export var track_stat: StringName = &""
@export var track_target: float = 0.0


func is_met(stats: Dictionary) -> bool:
	for r in requirements:
		if not r.check(stats):
			return false
	return true


## Прогресс 0..1, или -1 если отслеживание не задано.
func progress(stats: Dictionary) -> float:
	if track_stat.is_empty() or track_target <= 0.0:
		return -1.0
	return clampf(float(stats.get(track_stat, 0.0)) / track_target, 0.0, 1.0)
