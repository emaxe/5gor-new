extends Node
## Game — единственный владелец игрового состояния: деньги, рейтинг, время,
## погода, статистика смены и за всё время.
##
## Правило проекта: НИКТО не пишет в money/rating напрямую, только через
## add_money()/add_rating(). В оригинале шесть мест правили this.money в обход
## сеттера, из-за чего не эмитился money:changed и не показывался cash-pop.

const GarageScript = preload("res://gameplay/economy/garage.gd")
const AchievementTrackerScript = preload("res://gameplay/achievements/achievement_tracker.gd")

const RATING_MAX := 100.0

## Владение машинами и апгрейды — не сбрасывается start_shift(), гараж не
## привязан к смене (см. gameplay/economy/garage.gd).
var garage := GarageScript.new()
## Разблокированные достижения — мета-прогрессия, как и garage: не
## сбрасывается start_shift() (см. gameplay/achievements/achievement_tracker.gd).
var achievements := AchievementTrackerScript.new()

var money: int = 0
var rating: float = 0.0
var day: int = 1
## Игровой час 0..24. Берётся по модулю 24 — в оригинале модуля не было,
## и после 720 с смены часы показывали 33:00, а «ночь» становилась вечной.
var hour: float = 9.0
var weather_id: StringName = &"clear"
var shift_elapsed: float = 0.0
var world_seed: int = 0

## Статистика текущей смены.
var shift_stats: Dictionary = {}
## Статистика за всё время (мета-прогрессия).
var lifetime_stats: Dictionary = {}

var _running := false
var _last_emit_minute := -1
var _prev_is_night := false

const SHIFT_KEYS: PackedStringArray = [
	"earned", "orders", "tips", "crashes", "peds", "km", "failed", "missions",
	"near_misses", "punches", "drifts", "perfect_stops", "escapes",
	"max_near_miss_streak", "best_combo",
]

const LIFETIME_KEYS: PackedStringArray = [
	"total_orders", "total_earned", "total_tips", "total_crashes", "total_peds",
	"total_km", "total_failed", "total_missions", "total_near_misses",
	"total_punches", "total_drifts", "total_perfect_stops", "total_escapes",
	"max_near_miss_streak", "max_speed_kmh", "max_rating", "night_orders",
	"police_fines", "max_escape_level",
]


func _ready() -> void:
	# Дефолт до первой загрузки слота/новой игры — совпадает с константой
	# Db.balance.world_seed, поэтому поведение без сейва (бенчмарк, автопрогон,
	# тесты) не меняется этапом 19.
	world_seed = _balance().world_seed
	reset_lifetime()
	reset_shift()


# --- Экономика ---------------------------------------------------------------

func add_money(delta: int) -> void:
	if delta == 0:
		return
	money += delta
	if delta > 0:
		shift_stats["earned"] = shift_stats.get("earned", 0) + delta
		lifetime_stats["total_earned"] = lifetime_stats.get("total_earned", 0) + delta
	Bus.money_changed.emit(money, delta)
	achievements.check_unlocks()


func set_money(value: int) -> void:
	add_money(value - money)


func can_afford(cost: int) -> bool:
	return money >= cost


## Списывает cost, если хватает денег. Возвращает успех.
func spend(cost: int) -> bool:
	if not can_afford(cost):
		return false
	add_money(-cost)
	return true


func add_rating(delta: float) -> void:
	if is_zero_approx(delta):
		return
	rating = clampf(rating + delta, 0.0, RATING_MAX)
	lifetime_stats["max_rating"] = maxf(lifetime_stats.get("max_rating", 0.0), rating)
	Bus.rating_changed.emit(rating)
	achievements.check_unlocks()


func set_rating(value: float) -> void:
	add_rating(value - rating)


# --- Время -------------------------------------------------------------------

func start_shift(new_day: int) -> void:
	day = new_day
	shift_elapsed = 0.0
	hour = _balance().shift_start_hour
	_prev_is_night = is_night()
	_last_emit_minute = -1
	reset_shift()
	_running = true


func stop_shift() -> void:
	_running = false


func advance_time(delta: float) -> void:
	if not _running:
		return
	var b := _balance()
	shift_elapsed += delta * maxf(Prefs.shift_speed, 0.01)
	# 12 реальных минут = 24 игровых часа (dayLengthSec = 720).
	var minutes := b.shift_start_hour * 60.0 + (shift_elapsed / b.day_length_sec) * 1440.0
	hour = fmod(minutes / 60.0, 24.0)

	var m := int(minutes)
	if m != _last_emit_minute:
		_last_emit_minute = m
		Bus.time_changed.emit(hour, day, is_night())

	if b.auto_end_shift and shift_elapsed >= b.day_length_sec:
		_running = false
		Dir.push(&"shift_end")


func is_night() -> bool:
	var b := _balance()
	return hour >= b.night_start_hour or hour < b.night_end_hour


## Плавный коэффициент ночи 0..1 (порт nightFactor из game.js).
func night_factor() -> float:
	var b := _balance()
	if hour >= b.night_start_hour:
		return 1.0
	if hour >= b.night_start_hour - 0.5:
		return (hour - (b.night_start_hour - 0.5)) / 0.5
	if hour < b.night_end_hour:
		return clampf((b.night_end_hour - hour) / 1.5, 0.0, 1.0)
	return 0.0


## Дневной коэффициент освещённости 0..1 (порт dayFactor).
func day_factor() -> float:
	return clampf(sin(PI * (hour - 6.0) / 12.0), 0.0, 1.0)


func set_weather(id: StringName) -> void:
	if id == weather_id:
		return
	weather_id = id
	Bus.weather_changed.emit(id)


# --- Статистика --------------------------------------------------------------

func reset_shift() -> void:
	shift_stats.clear()
	for k in SHIFT_KEYS:
		shift_stats[k] = 0


func reset_lifetime() -> void:
	lifetime_stats.clear()
	for k in LIFETIME_KEYS:
		lifetime_stats[k] = 0


func bump(shift_key: String, lifetime_key: String, amount: float = 1.0) -> void:
	if not shift_key.is_empty():
		shift_stats[shift_key] = shift_stats.get(shift_key, 0) + amount
	if not lifetime_key.is_empty():
		lifetime_stats[lifetime_key] = lifetime_stats.get(lifetime_key, 0) + amount
	achievements.check_unlocks()


func track_max(key: String, value: float) -> void:
	lifetime_stats[key] = maxf(lifetime_stats.get(key, 0.0), value)
	achievements.check_unlocks()


## Максимум за смену (best_combo, max_near_miss_streak) — симметрично track_max,
## но пишет в shift_stats, который каждую смену обнуляется reset_shift().
func track_shift_max(key: String, value: float) -> void:
	shift_stats[key] = maxi(shift_stats.get(key, 0), roundi(value))
	achievements.check_unlocks()


## Слитая статистика для проверки условий достижений.
func all_stats() -> Dictionary:
	var out := lifetime_stats.duplicate()
	for k: String in shift_stats:
		out["shift_" + k] = shift_stats[k]
	out["rating"] = rating
	out["money"] = money
	out["day"] = day
	return out


# --- Сохранения (SaveManager) -------------------------------------------------
# SaveManager не пишет в money/rating/day/world_seed/lifetime_stats напрямую —
# тот же принцип единственного владельца, что и для add_money()/add_rating().

## Снимок для записи в слот.
func save_snapshot() -> Dictionary:
	return {
		"money": money,
		"rating": rating,
		"day": day,
		"world_seed": world_seed,
		"lifetime_stats": lifetime_stats.duplicate(),
	}


## Восстанавливает снимок из слота. Не эмитит money_changed/rating_changed —
## это не игровое событие, а восстановление состояния до его начала.
func apply_save_snapshot(dict: Dictionary) -> void:
	money = int(dict.get("money", 0))
	rating = clampf(float(dict.get("rating", 0.0)), 0.0, RATING_MAX)
	day = int(dict.get("day", 1))
	world_seed = int(dict.get("world_seed", _balance().world_seed))
	var loaded: Dictionary = dict.get("lifetime_stats", {})
	reset_lifetime()
	for k: String in LIFETIME_KEYS:
		if loaded.has(k):
			lifetime_stats[k] = loaded[k]


## Сброс прогресса для новой игры: свежий гараж, обнулённая lifetime-
## статистика, стартовые деньги. Достижения НЕ трогает — они профиль-
## глобальные (SaveManager.ACHIEVEMENTS_PATH), не привязаны к слоту.
func reset_progress(new_world_seed: int) -> void:
	garage = GarageScript.new()
	reset_lifetime()
	day = 1
	world_seed = new_world_seed
	rating = 0.0
	money = 0
	add_money(_balance().start_money)


func _balance() -> BalanceData:
	if Db.balance != null:
		return Db.balance
	# До прогона импортёра данных работаем на дефолтах схемы.
	return BalanceData.new()
