class_name AchievementReq
extends Resource
## Одно условие достижения. Порт замыканий check из achievements.js:18
## в декларативную форму — все 29 условий оригинала имеют вид
## `stat OP value`, конъюнкция 1..3 таких.

enum Op { GE, LE, EQ }

## Имя поля статистики: &"total_orders", &"shift_crashes", ...
@export var stat: StringName = &""
@export var op: Op = Op.GE
@export var value: float = 0.0


func check(stats: Dictionary) -> bool:
	var v: float = stats.get(stat, 0.0)
	match op:
		Op.GE:
			return v >= value
		Op.LE:
			return v <= value
		Op.EQ:
			return is_equal_approx(v, value)
	return false
