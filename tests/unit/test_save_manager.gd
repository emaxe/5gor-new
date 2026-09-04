extends GdUnitTestSuite
## Юнит-тесты сохранений (этап 19): сериализация Garage/AchievementTracker,
## круглый цикл SaveManager.save_slot()/load_slot(), устойчивость к
## отсутствующим ключам (старый формат), атомарная запись через .tmp.

const GarageScript = preload("res://gameplay/economy/garage.gd")
const AchievementTrackerScript = preload("res://gameplay/achievements/achievement_tracker.gd")

## Слот вне пользовательского диапазона (UI использует только 0) — тесты не
## должны зависеть от реального сейва игрока и не должны его портить.
const TEST_SLOT := 97

var _prev_money: int
var _prev_rating: float
var _prev_day: int
var _prev_world_seed: int
var _prev_lifetime: Dictionary
var _prev_garage_dict: Dictionary
var _prev_achievements: Array[StringName]
var _prev_current_slot: int
## Резервная копия реального user://achievements.cfg — один тест ниже пишет
## в него по-настоящему (проверяет, что delete_slot() его не трогает), и
## обязан вернуть файл дев-машины как было, а не оставить тестовый мусор.
var _prev_achievements_file_bytes: PackedByteArray
var _had_achievements_file: bool


func before_test() -> void:
	_prev_money = Game.money
	_prev_rating = Game.rating
	_prev_day = Game.day
	_prev_world_seed = Game.world_seed
	_prev_lifetime = Game.lifetime_stats.duplicate()
	_prev_garage_dict = Game.garage.to_save_dict()
	_prev_achievements = Game.achievements.unlocked.duplicate()
	_prev_current_slot = SaveManager.current_slot
	_had_achievements_file = FileAccess.file_exists(SaveManager.ACHIEVEMENTS_PATH)
	if _had_achievements_file:
		_prev_achievements_file_bytes = FileAccess.get_file_as_bytes(SaveManager.ACHIEVEMENTS_PATH)
	# Garage.buy_car()/buy_upgrade() тратят реальные Game.money/rating — как в
	# test_garage.gd, поднимаем их на время теста, чтобы покупки не отказывали.
	Game.set_money(100000)
	Game.set_rating(100.0)


func after_test() -> void:
	SaveManager.delete_slot(TEST_SLOT)
	Game.set_money(_prev_money)
	Game.set_rating(_prev_rating)
	Game.day = _prev_day
	Game.world_seed = _prev_world_seed
	Game.lifetime_stats.clear()
	Game.lifetime_stats.merge(_prev_lifetime)
	Game.garage.apply_save_dict(_prev_garage_dict)
	Game.achievements.apply_save_dict({"unlocked": _prev_achievements})
	SaveManager.current_slot = _prev_current_slot
	if _had_achievements_file:
		var f := FileAccess.open(SaveManager.ACHIEVEMENTS_PATH, FileAccess.WRITE)
		f.store_buffer(_prev_achievements_file_bytes)
		f.close()
	elif FileAccess.file_exists(SaveManager.ACHIEVEMENTS_PATH):
		DirAccess.remove_absolute(SaveManager.ACHIEVEMENTS_PATH)


# --- Garage: сериализация ------------------------------------------------------

func test_garage_round_trip_preserves_ownership_upgrades_and_tuning() -> void:
	var g := GarageScript.new()
	g.buy_car(&"classic")
	g.buy_upgrade(&"taxi", &"engine")
	g.set_active(&"classic")
	g.set_tuning(&"taxi", &"color", 2)
	g.set_tuning(&"classic", &"spoiler", true)

	var g2 := GarageScript.new()
	g2.apply_save_dict(g.to_save_dict())

	assert_that(g2.owns(&"taxi")).is_true()
	assert_that(g2.owns(&"classic")).is_true()
	assert_that(g2.active_car_id).is_equal(&"classic")
	assert_that(g2.upgrade_level(&"taxi", &"engine")).is_equal(1)
	assert_that(g2.tuning_value(&"taxi", &"color")).is_equal(2)
	assert_that(g2.tuning_value(&"classic", &"spoiler")).is_true()


func test_garage_apply_save_dict_defaults_on_empty_dict() -> void:
	var g := GarageScript.new()
	g.apply_save_dict({})
	assert_that(g.owns(&"taxi")).is_true()
	assert_that(g.active_car_id).is_equal(&"taxi")


# --- AchievementTracker: сериализация ------------------------------------------

func test_achievement_tracker_round_trip() -> void:
	var a := AchievementTrackerScript.new()
	a.unlocked.append(&"km_500")
	a.unlocked.append(&"night_owl")

	var a2 := AchievementTrackerScript.new()
	a2.apply_save_dict(a.to_save_dict())

	assert_that(a2.is_unlocked(&"km_500")).is_true()
	assert_that(a2.is_unlocked(&"night_owl")).is_true()
	assert_that(a2.is_unlocked(&"combo_king")).is_false()


# --- SaveManager: круглый цикл слота --------------------------------------------

func test_save_and_load_slot_round_trip() -> void:
	# Покупки сначала (тратят деньги по реальной цене), контрольное значение
	# денег/рейтинга выставляем после — иначе сумма после load_slot() не
	# сойдётся с тем, что реально было списано.
	Game.garage.buy_car(&"classic")
	Game.garage.buy_upgrade(&"taxi", &"engine")
	Game.set_money(12345)
	Game.set_rating(42.5)
	Game.day = 7
	Game.world_seed = 999111
	Game.lifetime_stats["total_orders"] = 30
	Game.lifetime_stats["total_km"] = 12.5

	SaveManager.current_slot = TEST_SLOT
	SaveManager.save_slot(TEST_SLOT)

	# Мутируем всё, чтобы load_slot() не мог случайно совпасть без реальной загрузки.
	Game.set_money(1)
	Game.set_rating(0.0)
	Game.day = 1
	Game.world_seed = 1
	Game.lifetime_stats["total_orders"] = 0
	Game.lifetime_stats["total_km"] = 0.0
	Game.garage.apply_save_dict({})

	assert_that(SaveManager.load_slot(TEST_SLOT)).is_true()
	assert_that(Game.money).is_equal(12345)
	assert_that(Game.rating).is_equal_approx(42.5, 0.001)
	assert_that(Game.day).is_equal(7)
	assert_that(Game.world_seed).is_equal(999111)
	assert_that(Game.lifetime_stats["total_orders"]).is_equal(30)
	assert_that(Game.lifetime_stats["total_km"]).is_equal_approx(12.5, 0.001)
	assert_that(Game.garage.owns(&"classic")).is_true()
	assert_that(Game.garage.upgrade_level(&"taxi", &"engine")).is_equal(1)
	assert_that(SaveManager.current_slot).is_equal(TEST_SLOT)


func test_load_slot_returns_false_for_missing_file() -> void:
	SaveManager.delete_slot(TEST_SLOT)
	assert_that(SaveManager.load_slot(TEST_SLOT)).is_false()


func test_has_slot_and_delete_slot() -> void:
	SaveManager.current_slot = TEST_SLOT
	SaveManager.save_slot(TEST_SLOT)
	assert_that(SaveManager.has_slot(TEST_SLOT)).is_true()

	SaveManager.delete_slot(TEST_SLOT)
	assert_that(SaveManager.has_slot(TEST_SLOT)).is_false()
	assert_that(SaveManager.current_slot).is_equal(-1)


## Симулирует старый формат сейва (без поля progress/world_seed и без секции
## garage вовсе) — чтение через get_value(section, key, default) не должно падать.
func test_load_slot_tolerates_missing_fields() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "save_version", 1)
	cfg.set_value("progress", "money", 500)
	cfg.save("user://slot_%d.save" % TEST_SLOT)

	assert_that(SaveManager.load_slot(TEST_SLOT)).is_true()
	assert_that(Game.money).is_equal(500)
	assert_that(Game.rating).is_equal_approx(0.0, 0.001)
	assert_that(Game.day).is_equal(1)
	assert_that(Game.world_seed).is_equal(Db.balance.world_seed)
	assert_that(Game.garage.owns(&"taxi")).is_true()


## Атомарность: после успешной записи временного файла быть не должно —
## save_slot() обязан переименовать его в целевой путь через rename_absolute().
func test_save_slot_leaves_no_tmp_file_behind() -> void:
	SaveManager.current_slot = TEST_SLOT
	SaveManager.save_slot(TEST_SLOT)
	assert_that(FileAccess.file_exists("user://slot_%d.save" % TEST_SLOT)).is_true()
	assert_that(FileAccess.file_exists("user://slot_%d.save.tmp" % TEST_SLOT)).is_false()


# --- Достижения: не стираются удалением слота -----------------------------------

func test_deleting_slot_does_not_touch_achievements_file() -> void:
	Game.achievements.unlocked.append(&"km_500")
	SaveManager._save_achievements()
	SaveManager.current_slot = TEST_SLOT
	SaveManager.save_slot(TEST_SLOT)

	SaveManager.delete_slot(TEST_SLOT)

	assert_that(FileAccess.file_exists(SaveManager.ACHIEVEMENTS_PATH)).is_true()
	var cfg := ConfigFile.new()
	assert_that(cfg.load(SaveManager.ACHIEVEMENTS_PATH)).is_equal(OK)
	var unlocked: Array = cfg.get_value("achievements", "unlocked", [])
	assert_that(unlocked).contains("km_500")


# --- world_seed: сохранённый сид доходит до генератора мира ---------------------

func test_slot_summary_exposes_saved_world_seed_before_load() -> void:
	Game.world_seed = 777333
	SaveManager.current_slot = TEST_SLOT
	SaveManager.save_slot(TEST_SLOT)

	var summary := SaveManager.slot_summary(TEST_SLOT)
	assert_that(summary["world_seed"]).is_equal(777333)


func test_apply_boot_seed_sets_game_world_seed_from_slot() -> void:
	Game.world_seed = 424242
	SaveManager.current_slot = TEST_SLOT
	SaveManager.save_slot(TEST_SLOT)
	Game.world_seed = 1

	SaveManager.apply_boot_seed(TEST_SLOT)
	assert_that(Game.world_seed).is_equal(424242)


func test_apply_boot_seed_is_noop_without_a_slot() -> void:
	SaveManager.delete_slot(TEST_SLOT)
	Game.world_seed = 555
	SaveManager.apply_boot_seed(TEST_SLOT)
	assert_that(Game.world_seed).is_equal(555)


# --- Новая игра ------------------------------------------------------------------

func test_new_game_resets_progress_and_persists_slot() -> void:
	Game.garage.buy_car(&"classic")
	Game.lifetime_stats["total_orders"] = 99

	SaveManager.new_game(TEST_SLOT, 123456)

	assert_that(Game.day).is_equal(1)
	assert_that(Game.rating).is_equal_approx(0.0, 0.001)
	assert_that(Game.money).is_equal(Db.balance.start_money)
	assert_that(Game.world_seed).is_equal(123456)
	assert_that(Game.lifetime_stats["total_orders"]).is_equal(0)
	assert_that(Game.garage.owns(&"classic")).is_false()
	assert_that(SaveManager.has_slot(TEST_SLOT)).is_true()


# --- Страховка: автосейв ачивок закрывает окно между unlock и записью ----------

## Если процесс падает посреди unlocked.append() и записи achievements.cfg,
## последняя ачивка теряется. _autosave() пишет их раз в AUTOSAVE_INTERVAL_SEC
## (30 с) — дёргаем его напрямую и убеждаемся, что неподписанный на сигнал
## unlock всё равно сохраняется.
func test_achievements_persist_via_autosave_without_unlock_signal() -> void:
	# Чтобы не зависеть от других тестов — убираем всё из файла и из памяти.
	SaveManager._save_achievements() # записать текущее пустое состояние
	Game.achievements.apply_save_dict({"unlocked": []})

	Game.achievements.unlocked.append(&"km_500")
	Game.achievements.unlocked.append(&"night_owl")

	# Сигнал НЕ эмитим — имитируем «потерянную» разблокировку, которую
	# подхватит только периодический автосейв.
	SaveManager._autosave()

	var cfg := ConfigFile.new()
	assert_that(cfg.load(SaveManager.ACHIEVEMENTS_PATH)).is_equal(OK)
	var unlocked: Array = cfg.get_value("achievements", "unlocked", [])
	assert_that(unlocked).contains(&"km_500")
	assert_that(unlocked).contains(&"night_owl")


func test_slot_count_is_three() -> void:
	assert_that(SaveManager.SLOT_COUNT).is_equal(3)


## Карточка слота N>0 должна подхватывать сохранённые данные: новая игра в
## слоте 1 → прогресс не виден в слоте 0 → возврат к слоту 0 сохраняет его
## прежним. Гарантия, что UI с 3 слотами не перезатирает чужие сохранения.
func test_three_slots_isolate_progress() -> void:
	SaveManager.delete_slot(0)
	SaveManager.delete_slot(1)
	SaveManager.delete_slot(2)

	# Заполняем слот 0.
	SaveManager.new_game(0, 111)
	Game.set_money(1234)
	SaveManager.save_slot(0)

	# Заполняем слот 1 другими данными.
	SaveManager.new_game(1, 222)
	Game.set_money(5678)
	SaveManager.save_slot(1)

	# Слот 0 — деньги 1234, сид 111.
	assert_that(SaveManager.slot_summary(0)["money"]).is_equal(1234)
	assert_that(SaveManager.slot_summary(0)["world_seed"]).is_equal(111)

	# Слот 1 — деньги 5678, сид 222.
	assert_that(SaveManager.slot_summary(1)["money"]).is_equal(5678)
	assert_that(SaveManager.slot_summary(1)["world_seed"]).is_equal(222)

	# Слот 2 пуст.
	assert_that(SaveManager.slot_summary(2)).is_empty()
	assert_that(SaveManager.has_slot(2)).is_false()


## UI гаража читает Game.garage — один instance на все слоты. load_slot()
## обязан перезатирать его содержимым указанного слота, не оставляя хвостов
## от предыдущего. Иначе открытие гаража после «Продолжить» слота 1 при
## последнем сейве в слоте 0 показало бы чужой прогресс.
##
## Примечание про ачивки: AchievementTracker привязан к профилю, а не к
## слоту, поэтому здесь мы проверяем только гараж — ачивки остаются
## общими на весь профиль (по дизайну плана).
func test_loading_different_slot_replaces_garage() -> void:
	SaveManager.delete_slot(0)
	SaveManager.delete_slot(1)

	# Слот 0: такси + апгрейд.
	SaveManager.new_game(0, 100)
	Game.set_rating(50.0)
	Game.set_money(100000)
	Game.garage.buy_upgrade(&"taxi", &"engine")
	SaveManager.save_slot(0)

	# Слот 1: classic без апгрейдов.
	SaveManager.new_game(1, 200)
	Game.set_rating(50.0)
	Game.set_money(100000)
	Game.garage.buy_car(&"classic")
	SaveManager.save_slot(1)

	# Переключаемся на слот 0 — не должно остаться хвостов от слота 1.
	SaveManager.load_slot(0)
	assert_that(Game.garage.owns(&"taxi")).is_true()
	assert_that(Game.garage.owns(&"classic")).is_false()
	assert_that(Game.garage.upgrade_level(&"taxi", &"engine")).is_equal(1)

	# Переключаемся на слот 1 — обратная картина.
	SaveManager.load_slot(1)
	assert_that(Game.garage.owns(&"taxi")).is_true()
	assert_that(Game.garage.owns(&"classic")).is_true()
	assert_that(Game.garage.upgrade_level(&"taxi", &"engine")).is_equal(0)

	# И обратно — переключение должно быть идемпотентным.
	SaveManager.load_slot(0)
	assert_that(Game.garage.owns(&"taxi")).is_true()
	assert_that(Game.garage.owns(&"classic")).is_false()
	assert_that(Game.garage.upgrade_level(&"taxi", &"engine")).is_equal(1)
