extends Node
## SaveManager — слоты сохранения игры + отдельный глобальный профиль достижений.
##
## Архитектурное решение (план противоречит сам себе на этот счёт — секции
## `[settings][driver]` упомянуты и в слоте, и отдельно в user://settings.cfg):
## настройки/водитель уже полностью живут в Prefs (user://settings.cfg),
## реализованном раньше этого этапа — здесь они НЕ дублируются. Слот хранит
## только то, что реально принадлежит конкретной игре: прогресс, гараж,
## lifetime-статистику. Достижения — тоже отдельно от слота (user://
## achievements.cfg): это профиль-глобальная мета-прогрессия, удаление слота
## её не стирает.
##
## Автолоад идёт в project.godot ПОСЛЕ Game — читает/пишет уже существующие
## Game.garage/Game.achievements при загрузке.

const SLOT_PATH_FMT := "user://slot_%d.save"
const ACHIEVEMENTS_PATH := "user://achievements.cfg"
const SAVE_VERSION := 1
const AUTOSAVE_INTERVAL_SEC := 30.0
## Слоты нумеруются 0..SLOT_COUNT-1; API SaveManager уже работал с
## произвольным индексом, явная константа фиксирует UX-решение
## (1 → 3 слота в главном меню).
const SLOT_COUNT := 3

## Состояния Dir, на входе в которые стоит сохраниться независимо от таймера —
## моменты, когда игрок ожидаемо может закрыть игру или потерять прогресс.
const _AUTOSAVE_STATES: Array[StringName] = [&"driving", &"pause", &"shift_end", &"menu"]

## Отметка времени последней записи achievements.cfg. Сравнивается с
## Bus.achievement_unlocked — между разблокировкой и сохранением есть окно
## (append + запись на диск), при краш-выходе в нём можно потерять последнюю
## ачивку. Периодический автосейв закрывает окно, без него единственная
## страховка — подписка на сигнал, которая не срабатывает на NOTIFICATION_WM_CLOSE_REQUEST.
var _last_achievements_save_ms: int = 0

## -1 — ни один слот не активен (главное меню до выбора «Продолжить»/«Новая игра»).
var current_slot: int = -1

var _autosave_timer: Timer


func _ready() -> void:
	_load_achievements()
	Bus.achievement_unlocked.connect(func(_id: StringName) -> void: _save_achievements())
	Bus.game_state_changed.connect(_on_state_changed)

	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL_SEC
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(_autosave)
	add_child(_autosave_timer)

	# Веб: IndexedDB-бэкенд user:// не гарантированно переживает закрытие
	# вкладки — предупреждаем один раз, реальное сохранение всё равно
	# подстраховано NOTIFICATION_WM_CLOSE_REQUEST/APPLICATION_PAUSED ниже.
	if OS.has_feature("web") and not OS.is_userfs_persistent():
		push_warning("SaveManager: user:// не персистентен в этом браузере — "
			+ "сейв может не пережить закрытие вкладки")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_autosave()


func _on_state_changed(state: StringName) -> void:
	if state in _AUTOSAVE_STATES:
		_autosave()


func _autosave() -> void:
	if current_slot >= 0:
		save_slot(current_slot)
	# Ачивки пишем каждый тик автосейва (30 с) — дешёвая операция
	# (ConfigFile в user://achievements.cfg, обычно < 1 КБ) и закрывает окно
	# между unlocked.append() и записью по сигналу, в которое можно попасть
	# при краш-выходе на WM_CLOSE_REQUEST.
	_save_achievements()


# --- Слоты --------------------------------------------------------------------

func has_slot(index: int) -> bool:
	return FileAccess.file_exists(_slot_path(index))


func delete_slot(index: int) -> void:
	var path := _slot_path(index)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if current_slot == index:
		current_slot = -1


## Лёгкая сводка слота без применения его к Game — для превью в UI («Продолжить,
## День 3, 4200 ₽») и для того, чтобы main.gd мог узнать world_seed слота ДО
## постройки мира (сам мир строится один раз за запуск процесса, см. комментарий
## в world.gd, поэтому сид нужно знать раньше, чем Dir.load_world() его создаст).
func slot_summary(index: int) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(_slot_path(index)) != OK:
		return {}
	return {
		"day": int(cfg.get_value("progress", "day", 1)),
		"money": int(cfg.get_value("progress", "money", 0)),
		"world_seed": int(cfg.get_value("progress", "world_seed", Db.balance.world_seed)),
	}


## Вызывается только из main.gd (реальный запуск игры) до Dir.load_world() —
## headless-тесты строят мир напрямую и в этот путь не попадают, поэтому их
## world_seed остаётся детерминированным дефолтом Db.balance.world_seed.
func apply_boot_seed(index: int) -> void:
	var summary := slot_summary(index)
	if summary.has("world_seed"):
		Game.world_seed = summary["world_seed"]


## Полная загрузка слота в Game/Game.garage. false — файла нет или он битый.
func load_slot(index: int) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(_slot_path(index)) != OK:
		return false
	_migrate(cfg)

	Game.apply_save_snapshot({
		"money": cfg.get_value("progress", "money", 0),
		"rating": cfg.get_value("progress", "rating", 0.0),
		"day": cfg.get_value("progress", "day", 1),
		"world_seed": cfg.get_value("progress", "world_seed", Db.balance.world_seed),
		"lifetime_stats": cfg.get_value("stats", "lifetime", {}),
	})
	Game.garage.apply_save_dict(cfg.get_value("garage", "data", {}))
	# Ачивки — профильный файл, не слот-привязанный, но Game.achievements
	# хранит разблокировки в памяти. Без явной перезагрузки после «Новая
	# игра в слоте 1 → разблокировали что-то → Продолжить слот 0» память
	# продолжает показывать разблокировки слота 1, а файл (общий) их не
	# содержит. _load_achievements() читает user://achievements.cfg и
	# перезатирает Game.achievements.unlocked тем, что на диске — а на диске
	# всегда актуальное состояние, потому что _save_achievements() пишет
	# туда и по сигналу, и в _autosave().
	_load_achievements()

	current_slot = index
	return true


## Атомарная запись: сначала во временный файл, затем rename_absolute() —
## убийство процесса/вкладки посреди записи не должно портить уже
## существующий слот (план, п. 12).
func save_slot(index: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "save_version", SAVE_VERSION)
	cfg.set_value("meta", "saved_at_unix", Time.get_unix_time_from_system())

	var snapshot := Game.save_snapshot()
	cfg.set_value("progress", "money", snapshot["money"])
	cfg.set_value("progress", "rating", snapshot["rating"])
	cfg.set_value("progress", "day", snapshot["day"])
	cfg.set_value("progress", "world_seed", snapshot["world_seed"])
	cfg.set_value("stats", "lifetime", snapshot["lifetime_stats"])
	cfg.set_value("garage", "data", Game.garage.to_save_dict())

	var path := _slot_path(index)
	var tmp_path := path + ".tmp"
	var err := cfg.save(tmp_path)
	if err != OK:
		push_error("SaveManager: не удалось записать %s (код %d)" % [tmp_path, err])
		return
	err = DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		push_error("SaveManager: не удалось переименовать %s -> %s (код %d)"
			% [tmp_path, path, err])


## Сброс прогресса и создание нового слота: свежий гараж, переданный
## world_seed (main.gd решает — сохранить текущий уже построенный мир при
## первой игре или перегенерировать город для нового с новым сидом),
## немедленно сохраняется, чтобы has_slot() сразу видел слот занятым.
func new_game(index: int, world_seed: int) -> void:
	current_slot = index
	Game.reset_progress(world_seed)
	save_slot(index)


# --- Достижения (профиль-глобальные, отдельно от слотов) ----------------------

func _load_achievements() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(ACHIEVEMENTS_PATH) != OK:
		return
	Game.achievements.apply_save_dict({
		"unlocked": cfg.get_value("achievements", "unlocked", []),
	})


func _save_achievements() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "save_version", SAVE_VERSION)
	var dict := Game.achievements.to_save_dict()
	cfg.set_value("achievements", "unlocked", dict["unlocked"])
	var err := cfg.save(ACHIEVEMENTS_PATH)
	if err != OK:
		push_error("SaveManager: не удалось записать %s (код %d)" % [ACHIEVEMENTS_PATH, err])
		return
	_last_achievements_save_ms = Time.get_ticks_msec()


# --- Миграции -------------------------------------------------------------------

## Версия одна — мигрировать пока не с чего. Цепочка заготовлена, чтобы
## добавление v2 не потребовало переписывать load_slot(): пиши
## _migrate_v1_to_v2(cfg), которая правит cfg на месте до чтения значений.
func _migrate(cfg: ConfigFile) -> void:
	var version: int = int(cfg.get_value("meta", "save_version", SAVE_VERSION))
	if version < 2:
		_migrate_v1_to_v2(cfg)


func _migrate_v1_to_v2(_cfg: ConfigFile) -> void:
	pass


func _slot_path(index: int) -> String:
	return SLOT_PATH_FMT % index
