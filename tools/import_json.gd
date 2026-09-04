@tool
extends SceneTree
## Генерация res://data/**.tres из дампов tools/dump/*.json.
##
## Запуск:
##   node tools/dump_data.mjs           # выгрузить данные из JS-оригинала
##   godot --headless --path . --script res://tools/import_json.gd
##
## Импорт воспроизводим: правка баланса в оригинале -> перегенерация за секунды.
## Все пользовательские строки уходят в assets/i18n/game.csv, а в ресурсах
## остаются только ключи локализации — иначе ~900 русских реплик были бы
## намертво вшиты в сцены, как в оригинале.

const DUMP := "res://tools/dump/"
const DATA := "res://data/"
const CSV_PATH := "res://assets/i18n/game.csv"

var _loc: Dictionary[String, String] = {}
var _saved := 0
var _errors: PackedStringArray = []


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var cfg := _json("config.json")
	var ord := _json("orders.json")
	var trf := _json("traffic.json")
	var pol := _json("police.json")
	var dlg := _json("dialogues.json")
	var pds := _json("peds.json")
	var ach := _json("achievements.json")
	var aud := _json("audio.json")

	if _errors.size() > 0:
		_report(t0)
		return

	var quote_banks := _import_quotes(dlg, pds, trf, ord)
	_import_balance(cfg, pol)
	_import_gfx(cfg)
	var districts := _import_districts(cfg)
	_import_weather(cfg)
	_import_upgrades(cfg)
	_import_cars(cfg)
	_import_orders(cfg, ord, quote_banks)
	_import_traffic(trf, quote_banks)
	_import_peds(pds, quote_banks)
	_import_achievements(ach)
	_import_audio(aud)
	_write_csv()
	_report(t0, districts)


# --- Инфраструктура ----------------------------------------------------------

func _json(name: String) -> Dictionary:
	var path := DUMP + name
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_errors.append("нет файла %s — сначала запусти node tools/dump_data.mjs" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null:
		_errors.append("не разобран JSON: %s" % path)
		return {}
	# achievements.json — массив; заворачиваем, чтобы тип возврата был единым.
	if parsed is Array:
		return {"items": parsed}
	return parsed


func _save(res: Resource, rel: String) -> Resource:
	var path := DATA + rel
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := ResourceSaver.save(res, path)
	if err != OK:
		_errors.append("не сохранён %s (код %d)" % [path, err])
		return res
	# take_over_path проставляет resource_path, иначе родительский ресурс
	# встроит копию вместо ссылки ext_resource.
	res.take_over_path(path)
	_saved += 1
	return res


## Регистрирует строку в таблице локализации и возвращает её ключ.
func _tr_key(key: String, text: String) -> String:
	if text.is_empty():
		return ""
	if _loc.has(key) and _loc[key] != text:
		_errors.append("конфликт ключа локализации %s" % key)
	_loc[key] = text
	return key


## Цвет из JS-числа 0xRRGGBB.
static func _color_int(v: int) -> Color:
	return Color(((v >> 16) & 255) / 255.0, ((v >> 8) & 255) / 255.0, (v & 255) / 255.0)


## Цвет из '#rrggbb' или числа.
static func _color_any(v: Variant) -> Color:
	if v is String:
		return Color(v as String)
	return _color_int(int(v))


static func _slug(s: String) -> String:
	return s.to_lower().replace(" ", "_")


func _report(t0: int, districts: Variant = null) -> void:
	if not _errors.is_empty():
		for e in _errors:
			printerr("ОШИБКА: ", e)
		quit(1)
		return
	print("Импорт завершён за %d мс" % (Time.get_ticks_msec() - t0))
	print("  ресурсов сохранено: %d" % _saved)
	print("  строк локализации:  %d" % _loc.size())
	if districts != null:
		print("  районов:            %d" % (districts as Array).size())
	quit(0)


# --- Пулы реплик -------------------------------------------------------------

## Создаёт QuoteBank из массива строк: строки уходят в CSV, в ресурсе — ключи.
func _bank(id: String, lines: Array, key_prefix: String) -> QuoteBank:
	var b := QuoteBank.new()
	b.id = StringName(id)
	var keys := PackedStringArray()
	for i in lines.size():
		var text := String(lines[i])
		keys.append(_tr_key("%s_%02d" % [key_prefix, i + 1], text))
	b.lines = keys
	return _save(b, "quotes/%s.tres" % id) as QuoteBank


## Все пулы реплик проекта, по id.
func _import_quotes(dlg: Dictionary, pds: Dictionary, trf: Dictionary,
		ord: Dictionary) -> Dictionary:
	var banks: Dictionary[String, QuoteBank] = {}

	# Пешеходы: 46 пулов из peds.js (idle/curse/panic/flee/retaliate по архетипам).
	for name: String in (pds.get("quotes", {}) as Dictionary):
		var id := _slug(name).trim_suffix("_quotes")
		banks["ped_" + id] = _bank("ped_" + id, pds["quotes"][name],
			"QUOTE_PED_" + id.to_upper())

	# Водители трафика.
	for name: String in (trf.get("quotes", {}) as Dictionary):
		banks["driver_" + name] = _bank("driver_" + name, trf["quotes"][name],
			"QUOTE_DRIVER_" + name.to_upper())

	# Реплики из dialogues.js.
	banks["ped_shout"] = _bank("ped_shout", dlg["PEDESTRIAN_SHOUTS"], "QUOTE_PED_SHOUT")
	banks["driver_shout"] = _bank("driver_shout", dlg["DRIVER_SHOUTS"], "QUOTE_DRIVER_SHOUT")
	banks["drift_reaction"] = _bank("drift_reaction", dlg["PASSENGER_DRIFT_REACTIONS"],
		"QUOTE_DRIFT")
	banks["passenger_names"] = _bank("passenger_names", dlg["PASSENGER_NAMES"], "NAME_PASSENGER")

	for k: String in (dlg["WEATHER_DIALOGUES"] as Dictionary):
		banks["weather_" + k] = _bank("weather_" + k, dlg["WEATHER_DIALOGUES"][k],
			"QUOTE_WEATHER_" + k.to_upper())
	for k: String in (dlg["DISPATCHER_BRIEFS"] as Dictionary):
		banks["dispatcher_" + k] = _bank("dispatcher_" + k, dlg["DISPATCHER_BRIEFS"][k],
			"QUOTE_DISPATCH_" + k.to_upper())
	for k: String in (dlg["DRIVER_DAY_NOTES"] as Dictionary):
		var id := _slug_camel(k)
		banks["day_note_" + id] = _bank("day_note_" + id, dlg["DRIVER_DAY_NOTES"][k],
			"QUOTE_DAYNOTE_" + id.to_upper())

	# Диалоги пассажиров: тип заказа x событие (pickup/dropoff/detour/crash).
	# Ключи crash/fast/offroad — плоские списки реакций на событие вождения,
	# а не разбивка по типу заказа.
	for order_id: String in (dlg["DIALOGUES"] as Dictionary):
		var entry: Variant = dlg["DIALOGUES"][order_id]
		if entry is Array:
			var flat_id := "dialog_" + order_id
			banks[flat_id] = _bank(flat_id, entry as Array,
				"QUOTE_DIALOG_" + order_id.to_upper())
			continue
		for event: String in (entry as Dictionary):
			var id := "dialog_%s_%s" % [order_id, event]
			banks[id] = _bank(id, (entry as Dictionary)[event],
				"QUOTE_DIALOG_%s_%s" % [order_id.to_upper(), event.to_upper()])

	# Отзывы пассажиров по числу звёзд.
	for stars: String in (ord["REVIEWS"] as Dictionary):
		banks["review_" + stars] = _bank("review_" + stars, ord["REVIEWS"][stars],
			"REVIEW_" + stars)

	return banks


## lowEarned -> low_earned
static func _slug_camel(s: String) -> String:
	var out := ""
	for i in s.length():
		var c := s[i]
		if c == c.to_upper() and c != c.to_lower() and i > 0:
			out += "_"
		out += c.to_lower()
	return out


# --- Баланс ------------------------------------------------------------------

func _import_balance(cfg: Dictionary, pol: Dictionary) -> void:
	var c: Dictionary = cfg["CFG"]
	var w: Dictionary = c["WANTED"]
	var v: Dictionary = pol["VIOLATIONS"]

	var wanted := WantedConfig.new()
	wanted.max_level = int(w["maxLevel"])
	wanted.decay_time = float(w["decayTime"])
	wanted.fine_mult_per_level = float(w["fineMultPerLevel"])
	wanted.rating_mult_per_level = float(w["ratingMultPerLevel"])
	wanted.detect_radius = 60.0 # POLICE_DETECT_RADIUS (police.js:27)
	wanted.detect_radius_bonus = float(w["detectRadiusBonus"])
	wanted.chase_level = int(w["chaseLevel"])
	wanted.intercept_level = wanted.max_level
	wanted.escape_reward_per_level = int(w["escapeRewardPerLevel"])
	wanted.escape_rating_bonus = int(w["escapeRatingBonus"])
	wanted.speed_threshold = 30.0 # SPEED_THRESHOLD (police.js:29)
	wanted.fine_speeding = int(v["speeding"]["fine"])
	wanted.fine_red_light = int(v["redLight"]["fine"])
	wanted.fine_hit_ped = int(v["hitPed"]["fine"])
	wanted.fine_ped_punch = int(v["pedPunch"]["fine"])
	wanted.rating_speeding = int(v["speeding"]["ratingLoss"])
	wanted.rating_red_light = int(v["redLight"]["ratingLoss"])
	wanted.rating_hit_ped = int(v["hitPed"]["ratingLoss"])
	wanted.rating_ped_punch = int(v["pedPunch"]["ratingLoss"])
	wanted.cooldown_speeding = float(v["speeding"]["cooldown"])
	wanted.cooldown_red_light = float(v["redLight"]["cooldown"])
	wanted.cooldown_hit_ped = float(v["hitPed"]["cooldown"])
	wanted.cooldown_ped_punch = float(v["pedPunch"]["cooldown"])
	_save(wanted, "balance/wanted.tres")

	var ped := PedConfig.new()
	ped.active_radius = float(c["pedActiveRadius"])
	ped.near_radius = float(c["pedNearRadius"])
	ped.violator_chance = float(c["pedViolatorChance"])
	ped.idle_time_min = float(c["pedIdleTime"][0])
	ped.idle_time_max = float(c["pedIdleTime"][1])
	ped.walk_speed = float(c["pedWalkSpeed"])
	ped.run_speed = float(c["pedRunSpeed"])
	ped.car_enter_dist = float(c["carEnterDist"])
	ped.car_exit_max_speed = float(c["carExitMaxSpeed"])
	ped.jump_speed = float(c["pedJumpSpeed"])
	ped.gravity = float(c["pedGravity"])
	ped.jump_cooldown = float(c["pedJumpCooldown"])
	ped.punch_radius = float(c["pedPunchRadius"])
	ped.punch_arc = float(c["pedPunchArc"])
	ped.punch_cooldown = float(c["pedPunchCooldown"])
	ped.punch_knock_speed = float(c["pedPunchKnockSpeed"])
	ped.punch_panic_radius = float(c["pedPunchPanicRadius"])
	ped.punch_fine = int(c["pedPunchFine"])
	ped.punch_rating_loss = int(c["pedPunchRatingLoss"])
	ped.player_max_hp = int(c["pedPlayerMaxHp"])
	ped.player_stun_duration = float(c["pedPlayerStunDuration"])
	ped.player_down_duration = float(c["pedPlayerDownDuration"])
	_save(ped, "balance/ped.tres")

	var style := StyleConfig.new()
	style.drift_min_slip = float(c["driftMinSlip"])
	style.drift_min_speed = float(c["driftMinSpeed"])
	style.drift_min_duration = float(c["driftMinDuration"])
	style.drift_base_reward = int(c["driftBaseReward"])
	style.drift_reward_per_sec = float(c["driftRewardPerSec"])
	style.drift_max_reward = int(c["driftMaxReward"])
	style.drift_style_bonus = float(c["driftStyleBonus"])
	style.perfect_stop_min_speed = float(c["perfectStopMinSpeed"])
	style.perfect_stop_max_decel = float(c["perfectStopMaxDecel"])
	style.perfect_stop_reward = int(c["perfectStopBaseReward"])
	style.perfect_stop_style_bonus = float(c["perfectStopStyleBonus"])
	style.near_miss_min_speed = float(c["nearMissMinSpeed"])
	style.near_miss_car_margin = float(c["nearMissCarMargin"])
	style.near_miss_ped_margin = float(c["nearMissPedMargin"])
	style.near_miss_reset_dist = float(c["nearMissResetDist"])
	style.near_miss_reward = int(c["nearMissReward"])
	style.near_miss_style_bonus = float(c["nearMissStyleBonus"])
	style.near_miss_streak_window = float(c["nearMissStreakWindow"])
	var nm_counts := PackedInt32Array()
	var nm_mults := PackedFloat32Array()
	for tier: Dictionary in (c["nearMissStreakTiers"] as Array):
		nm_counts.append(int(tier["count"]))
		nm_mults.append(float(tier["mult"]))
	style.near_miss_streak_counts = nm_counts
	style.near_miss_streak_mults = nm_mults
	var combo_counts := PackedInt32Array()
	for tier: Dictionary in (c["comboStreakTiers"] as Array):
		combo_counts.append(int(tier["count"]))
	style.combo_streak_counts = combo_counts
	_save(style, "balance/style.tres")

	var skid := SkidConfig.new()
	skid.min_slip = float(c["skidMinSlip"])
	skid.min_speed = float(c["skidMinSpeed"])
	skid.seg_len = float(c["skidSegLen"])
	skid.max_segments = int(c["skidMaxSegments"])
	skid.width = float(c["skidWidth"])
	_save(skid, "balance/skid.tres")

	var b := BalanceData.new()
	b.cell = float(c["CELL"])
	b.road_width = float(c["ROAD_W"])
	b.road_half = float(c["HALF"])
	b.sidewalk = float(c["SIDE"])
	b.grid_n = int(c["N"])
	b.grid_ext = float(c["GRID_EXT"])
	b.shadow_half = float(c["SHADOW_HALF"])
	b.world_seed = 20260805 # mulberry32(20260805) в citygen.js:66
	b.start_money = int(c["startMoney"])
	b.start_fuel = float(c["startFuel"])
	b.fuel_price = float(c["fuelPrice"])
	b.base_fare = float(c["baseFare"])
	b.fare_per_unit = float(c["farePerUnit"])
	b.time_bonus_max = float(c["timeBonusMax"])
	b.tips_max = float(c["tipsMax"])
	b.night_mult = float(c["nightMult"])
	b.repair_cost_per_damage = float(c["repairCostPerDmg"])
	b.wash_cost = int(c["washCost"])
	b.tow_cost = int(c["towCost"])
	b.tow_repair = float(c["towRepair"])
	b.tow_fuel = float(c["towFuel"])
	b.refuel_dist = float(c["refuelDist"])
	b.low_fuel_ratio = float(c["lowFuelRatio"])
	b.rating_loss_hit_ped = int(c["ratingFail"]["hitPed"])
	b.rating_loss_fail_order = int(c["ratingFail"]["failOrder"])
	b.rating_loss_vip_leave = int(c["ratingFail"]["vipLeave"])
	b.shift_start_hour = float(c["shiftStartHour"])
	b.day_length_sec = float(c["dayLengthSec"])
	b.night_start_hour = float(c["nightStartHour"])
	b.night_end_hour = float(c["nightEndHour"])
	b.max_open_orders = int(c["maxOpenOrders"])
	b.order_expire_sec = float(c["orderExpireSec"])
	b.order_spawn_every_sec = float(c["orderSpawnEverySec"])
	# Оригинал: trafficCount 14, pedCount 34 — это следствие O(n²) переборов,
	# а не дизайна. Data-oriented менеджеры с бакетизацией держат втрое больше
	# той же ценой; слабые платформы срезаются множителями в GfxPreset.
	b.traffic_count = 40
	b.ped_count = 120
	b.wanted = wanted
	b.ped = ped
	b.style = style
	b.skid = skid
	_save(b, "balance/balance.tres")


# --- Графические пресеты -----------------------------------------------------

func _import_gfx(cfg: Dictionary) -> void:
	# Порт CFG_GFX_PRESETS + параметры, которых в оригинале не было
	# (тени по каскадам, glow, SSAO, пул ночных фонарей, обводка героев).
	var extra := {
		"low": {
			"atlas": 2048, "splits": 1, "dist": 60.0, "msaa": 0,
			"glow": true, "ssao": false, "vol_fog": false,
			"outline": false, "lights": 12, "traffic": 0.35, "ped": 0.3,
		},
		"medium": {
			"atlas": 2048, "splits": 2, "dist": 80.0, "msaa": 0,
			"glow": true, "ssao": false, "vol_fog": false,
			"outline": true, "lights": 24, "traffic": 0.6, "ped": 0.6,
		},
		"high": {
			"atlas": 4096, "splits": 4, "dist": 150.0, "msaa": 1,
			"glow": true, "ssao": true, "vol_fog": true,
			"outline": true, "lights": 40, "traffic": 1.0, "ped": 1.0,
		},
	}
	var titles := {"low": "Низкое", "medium": "Среднее", "high": "Высокое"}
	var presets: Array[GfxPreset] = []

	for id: String in (cfg["CFG_GFX_PRESETS"] as Dictionary):
		var src: Dictionary = cfg["CFG_GFX_PRESETS"][id]
		var e: Dictionary = extra[id]
		var p := GfxPreset.new()
		p.id = StringName(id)
		p.display_name = _tr_key("GFX_PRESET_" + id.to_upper(), titles[id])
		p.shadows = StringName(src["shadows"])
		p.shadow_actors = bool(src["shadowActors"])
		p.shadow_atlas = int(e["atlas"])
		p.shadow_splits = int(e["splits"])
		p.shadow_max_distance = float(e["dist"])
		# pixelRatio оригинала -> scaling_3d_scale: 1.75 там означал
		# суперсэмплинг ретины, здесь потолок 1.0 + бюджет пикселей.
		p.scale_3d = minf(float(src["pixelRatio"]), 1.0)
		p.pixel_budget = int(src["pixelBudget"])
		p.msaa = int(e["msaa"])
		p.draw_distance = float(src["drawDistance"])
		p.traffic_density = float(e["traffic"])
		p.ped_density = float(e["ped"])
		p.rain = bool(src["rain"])
		p.glow = bool(e["glow"])
		p.ssao = bool(e["ssao"])
		p.volumetric_fog = bool(e["vol_fog"])
		p.hero_outline = bool(e["outline"])
		p.light_pool_size = int(e["lights"])
		presets.append(_save(p, "gfx/presets/%s.tres" % id) as GfxPreset)

	var cat := GfxCatalog.new()
	cat.items = presets
	_save(cat, "gfx/gfx_catalog.tres")


# --- Районы, палитры, достопримечательности ----------------------------------

func _import_districts(cfg: Dictionary) -> Array:
	var palettes: Dictionary[String, PaletteData] = {}
	for id: String in (cfg["PALETTES"] as Dictionary):
		var p := PaletteData.new()
		p.id = StringName(id)
		var colors := PackedColorArray()
		for hex: String in (cfg["PALETTES"][id] as Array):
			colors.append(Color(hex))
		p.facades = colors
		palettes[id] = _save(p, "districts/palettes/%s.tres" % id) as PaletteData

	# Спрос по времени суток: улучшение относительно оригинала, где заказы
	# распределялись по районам равномерно и смена шла без ритма.
	# утро — вокзал/привокзальный, день — рынок/центр, вечер — санатории/курорт,
	# ночь — Машук/центр/провал.
	var demand := {
		"center":    [1.0, 1.3, 1.1, 1.2],
		"kurort":    [0.8, 1.1, 1.4, 0.9],
		"prigorod":  [1.4, 1.0, 0.9, 0.8],
		"proval":    [0.7, 1.2, 1.0, 1.2],
		"rynok":     [1.2, 1.5, 0.7, 0.4],
		"sanatorii": [0.9, 0.9, 1.4, 0.8],
		"mashuk":    [0.8, 1.1, 1.0, 1.5],
		"vokzal":    [1.6, 1.0, 1.1, 1.0],
	}

	# Этажность приведена к реальному Пятигорску. В оригинале «Центр» имел
	# 20-55 м (до 18 этажей) — это башни, которых в городе нет: Пятигорск
	# малоэтажный курорт, доминанты только у вокзала и на проспекте.
	var heights := {
		"center":    [11.0, 24.0],
		"kurort":    [8.0, 15.0],
		"prigorod":  [8.0, 17.0],
		"proval":    [7.0, 13.0],
		"rynok":     [6.0, 11.0],
		"sanatorii": [10.0, 19.0],
		"mashuk":    [6.0, 11.0],
		"vokzal":    [9.0, 18.0],
	}

	var items: Array[DistrictData] = []
	for src: Dictionary in (cfg["DISTRICTS"] as Array):
		var id := String(src["id"])
		var d := DistrictData.new()
		d.id = StringName(id)
		d.display_name = _tr_key("DISTRICT_%s_NAME" % id.to_upper(), String(src["name"]))
		d.unlock_rating = int(src["unlock"])
		d.weight = float(src["weight"])
		d.palette = palettes.get(String(src["palette"]))
		var hr: Array = heights.get(id, [float(src["height"][0]), float(src["height"][1])])
		d.height_min = float(hr[0])
		d.height_max = float(hr[1])
		d.density = int(src["dens"])
		d.map_color = _color_int(int(src["color"]))
		var dm: Array = demand.get(id, [1.0, 1.0, 1.0, 1.0])
		d.demand_morning = dm[0]
		d.demand_day = dm[1]
		d.demand_evening = dm[2]
		d.demand_night = dm[3]
		items.append(_save(d, "districts/%s.tres" % id) as DistrictData)

	var landmarks: Array[LandmarkData] = []
	for src: Dictionary in (cfg["LANDMARKS"] as Array):
		var id := String(src["id"])
		var l := LandmarkData.new()
		l.id = StringName(id)
		l.display_name = _tr_key("LANDMARK_%s_NAME" % id.to_upper(), String(src["name"]))
		l.description = _tr_key("LANDMARK_%s_DESC" % id.to_upper(), String(src["desc"]))
		l.position = Vector2(float(src["x"]), float(src["z"]))
		landmarks.append(_save(l, "landmarks/%s.tres" % id) as LandmarkData)

	var fuel := PackedVector2Array()
	for src: Dictionary in (cfg["FUEL_STATIONS"] as Array):
		fuel.append(Vector2(float(src["x"]), float(src["z"])))

	var cat := DistrictCatalog.new()
	cat.items = items
	cat.landmarks = landmarks
	cat.fuel_stations = fuel
	_save(cat, "districts/district_catalog.tres")
	return items


# --- Погода ------------------------------------------------------------------

func _import_weather(cfg: Dictionary) -> void:
	# Веса выбора погоды на смену — из game.js (clear 55 / rain 25 / fog 20).
	var weights := {"clear": 55.0, "rain": 25.0, "fog": 20.0}
	var icons := {"clear": "sun", "rain": "rain", "fog": "fog"}
	# Тонировка неба погодой (game.js:29-30).
	var tints := {
		"clear": [Color.WHITE, 0.0],
		"rain": [_color_int(0x3a4856), 0.72],
		"fog": [_color_int(0x8a95a2), 0.78],
	}
	var items: Array[WeatherData] = []
	for id: String in (cfg["WEATHER_DEFS"] as Dictionary):
		var src: Dictionary = cfg["WEATHER_DEFS"][id]
		var w := WeatherData.new()
		w.id = StringName(id)
		w.display_name = _tr_key("WEATHER_%s_NAME" % id.to_upper(), String(src["name"]))
		w.icon = StringName(icons.get(id, ""))
		w.rain = float(src["rain"])
		w.fog_near = float(src["fogNear"])
		w.fog_far = float(src["fogFar"])
		w.grip = float(src["grip"])
		w.traffic = float(src["traffic"])
		w.spawn_weight = float(weights.get(id, 1.0))
		w.sky_tint = tints[id][0]
		w.sky_tint_strength = tints[id][1]
		items.append(_save(w, "weather/%s.tres" % id) as WeatherData)

	var cat := WeatherCatalog.new()
	cat.items = items
	_save(cat, "weather/weather_catalog.tres")


# --- Апгрейды ----------------------------------------------------------------

func _import_upgrades(cfg: Dictionary) -> void:
	# Эффекты за уровень захардкожены в upgrades.js:41-48 — в данных их нет,
	# поэтому таблица переносится сюда явно.
	var effects := {
		"engine":     {"max_speed": 3.2, "accel": 1.6},
		"suspension": {"grip": 0.05, "steer": 0.18},
		"brakes":     {"brake": 5.0},
		"armor":      {"armor": 0.35},
		"tank":       {"tank": 50.0},
		"capacity":   {"capacity": 1},
	}
	var items: Array[UpgradeData] = []
	for id: String in (cfg["UPGRADES"] as Dictionary):
		var src: Dictionary = cfg["UPGRADES"][id]
		var e: Dictionary = effects.get(id, {})
		var u := UpgradeData.new()
		u.id = StringName(id)
		u.display_name = _tr_key("UPGRADE_%s_NAME" % id.to_upper(), String(src["name"]))
		u.description = _tr_key("UPGRADE_%s_DESC" % id.to_upper(), String(src["desc"]))
		u.icon = StringName(id)
		u.max_level = int(src["max"])
		u.base_cost = int(src["base"])
		u.cost_mult = float(src["mult"])
		u.max_speed_per_level = float(e.get("max_speed", 0.0))
		u.accel_per_level = float(e.get("accel", 0.0))
		u.brake_per_level = float(e.get("brake", 0.0))
		u.grip_per_level = float(e.get("grip", 0.0))
		u.steer_per_level = float(e.get("steer", 0.0))
		u.armor_per_level = float(e.get("armor", 0.0))
		u.tank_per_level = float(e.get("tank", 0.0))
		u.capacity_per_level = int(e.get("capacity", 0))
		items.append(_save(u, "upgrades/%s.tres" % id) as UpgradeData)

	var cat := UpgradeCatalog.new()
	cat.items = items
	_save(cat, "upgrades/upgrade_catalog.tres")


# --- Машины и тюнинг ---------------------------------------------------------

func _import_cars(cfg: Dictionary) -> void:
	var shapes: Dictionary[String, CarShapeData] = {}
	for car_type: String in (cfg["CAR_TYPE_SHAPE"] as Dictionary):
		var src: Dictionary = cfg["CAR_TYPE_SHAPE"][car_type]
		var s := CarShapeData.new()
		s.silhouette = StringName(src["shape"])
		s.width = float(src["w"])
		s.length = float(src["len"])
		shapes[car_type] = _save(s, "cars/shapes/%s.tres" % car_type) as CarShapeData

	var items: Array[CarData] = []
	for id: String in (cfg["CARS"] as Dictionary):
		var src: Dictionary = cfg["CARS"][id]
		var base: Dictionary = src["base"]
		var c := CarData.new()
		c.id = StringName(id)
		c.display_name = _tr_key("CAR_%s_NAME" % id.to_upper(), String(src["name"]))
		c.description = _tr_key("CAR_%s_DESC" % id.to_upper(), String(src["desc"]))
		c.price = int(src["price"])
		c.unlock_rating = int(src["unlockRating"])
		c.max_speed = float(base["maxSpeed"])
		c.accel = float(base["accel"])
		c.brake = float(base["brake"])
		c.grip = float(base["grip"])
		c.armor = float(base["armor"])
		c.tank = float(base["tank"])
		c.capacity = int(base["capacity"])
		c.steer = float(base["steer"])
		c.shape = shapes.get(String(base["carType"]))
		c.body_color = Color(String(src["bodyColor"]))
		c.is_taxi = id == "taxi"
		# upgrades.js: у такси декаль по умолчанию 'checker', у остальных 'none'.
		c.default_decal = &"checker" if c.is_taxi else &"none"
		items.append(_save(c, "cars/%s.tres" % id) as CarData)

	var t: Dictionary = cfg["TUNING"]
	var tuning := TuningCatalog.new()
	var color_names := PackedStringArray()
	var colors := PackedColorArray()
	for entry: Dictionary in (t["colors"] as Array):
		var key := "TUNING_COLOR_" + _slug(String(entry["name"])).to_upper()
		color_names.append(_tr_key(key, String(entry["name"])))
		colors.append(Color(String(entry["c"])))
	tuning.color_names = color_names
	tuning.colors = colors

	var rim_names := PackedStringArray()
	var rim_colors := PackedColorArray()
	var rim_styles := PackedStringArray()
	for entry: Dictionary in (t["rims"] as Array):
		var key := "TUNING_RIM_" + String(entry["style"]).to_upper()
		rim_names.append(_tr_key(key, String(entry["name"])))
		rim_colors.append(Color(String(entry["c"])))
		rim_styles.append(String(entry["style"]))
	tuning.rim_names = rim_names
	tuning.rim_colors = rim_colors
	tuning.rim_styles = rim_styles

	var kit_names := PackedStringArray()
	var kit_ids := PackedStringArray()
	for entry: Dictionary in (t["bodyKits"] as Array):
		kit_names.append(_tr_key("TUNING_KIT_" + String(entry["id"]).to_upper(),
			String(entry["name"])))
		kit_ids.append(String(entry["id"]))
	tuning.body_kit_names = kit_names
	tuning.body_kit_ids = kit_ids

	var decal_names := PackedStringArray()
	var decal_ids := PackedStringArray()
	for entry: Dictionary in (t["decals"] as Array):
		decal_names.append(_tr_key("TUNING_DECAL_" + String(entry["id"]).to_upper(),
			String(entry["name"])))
		decal_ids.append(String(entry["id"]))
	tuning.decal_names = decal_names
	tuning.decal_ids = decal_ids
	_save(tuning, "cars/tuning.tres")

	var cat := CarCatalog.new()
	cat.items = items
	cat.tuning = tuning
	_save(cat, "cars/car_catalog.tres")


# --- Заказы, миссии, настроение ----------------------------------------------

func _import_orders(cfg: Dictionary, ord: Dictionary, banks: Dictionary) -> void:
	# Веса типов выведены из кумулятивных порогов orders.js:221-239.
	# race в случайном спавне не участвует — только как сюжетная миссия.
	var weights := {
		"normal":  {"day": 0.30, "night": 0.22},
		"urgent":  {"day": 0.20, "night": 0.30},
		"vip":     {"day": 0.12, "night": 0.12},
		"package": {"day": 0.12, "night": 0.10},
		"drunk":   {"day": 0.08, "night": 0.20},
		"group":   {"day": 0.10, "night": 0.00},
		"tour":    {"day": 0.08, "night": 0.06},
		"race":    {"day": 0.00, "night": 0.00},
	}
	# ratingPerOrder (config.js:133). Ключ tourist в оригинале не совпадал
	# с типом tour, из-за чего срабатывал скрытый fallback `|| 8`.
	var rating := {
		"normal": 4, "urgent": 6, "vip": 7, "group": 9,
		"tour": 10, "package": 5, "drunk": 6, "race": 12,
	}
	var flags := {
		"vip": {"leaves_on_crash": true, "tip_mult": 1.5},
		"package": {"is_parcel": true},
		"drunk": {"may_change_destination": true},
		"group": {"required_capacity": 2, "stops": 2},
		"tour": {"is_tour": true, "required_rating": 15, "stops": 2},
	}

	var items: Array[OrderTypeData] = []
	for id: String in (ord["ORDER_META"] as Dictionary):
		var src: Dictionary = ord["ORDER_META"][id]
		var f: Dictionary = flags.get(id, {})
		var o := OrderTypeData.new()
		o.id = StringName(id)
		o.display_name = _tr_key("ORDER_%s_NAME" % id.to_upper(), String(src["name"]))
		o.description = _tr_key("ORDER_%s_DESC" % id.to_upper(), String(src["desc"]))
		o.icon = String(src["icon"])
		o.color = Color(String(src["color"]))
		o.pay_mult = float(src["mult"])
		o.time_limit = float(src["time"])
		o.rating_reward = int(rating.get(id, 4))
		o.day_weight = float(weights[id]["day"])
		o.night_weight = float(weights[id]["night"])
		o.required_capacity = int(f.get("required_capacity", 1))
		o.required_rating = int(f.get("required_rating", 0))
		o.stops = int(f.get("stops", 1))
		o.is_parcel = bool(f.get("is_parcel", false))
		o.leaves_on_crash = bool(f.get("leaves_on_crash", false))
		o.may_change_destination = bool(f.get("may_change_destination", false))
		o.is_tour = bool(f.get("is_tour", false))
		o.tip_mult = float(f.get("tip_mult", 1.0))
		o.quotes_pickup = banks.get("dialog_%s_pickup" % id)
		o.quotes_dropoff = banks.get("dialog_%s_dropoff" % id)
		o.quotes_detour = banks.get("dialog_%s_detour" % id)
		o.quotes_crash = banks.get("dialog_crash")
		items.append(_save(o, "orders/types/%s.tres" % id) as OrderTypeData)

	# Сюжетные миссии: в оригинале это MISSION_TEMPLATES с функциями make(world),
	# которые нельзя сериализовать. Точки перенесены явно (orders.js:18-63).
	var mission_defs := [
		{
			"id": "grandma", "kind": "mission", "rating": 10, "pay": 900, "time": 0.0,
			"icon": "Б", "color": "#e87a3a", "pickup": "center",
			"title": "Бабушка на рынок",
			"desc": "Бабушка Зинаида просит отвезти её на рынок «Лира». Она щедрая!",
			"drops": [Vector2(96, -8)], "drop_names": ["Рынок «Лира»"], "final": "",
		},
		{
			"id": "doctor", "kind": "mission", "rating": 25, "pay": 1200, "time": 100.0,
			"icon": "+", "color": "#d94040", "pickup": "vokzal",
			"title": "Врач в санаторий",
			"desc": "Доктор Соколова опаздывает на обход. Домчите до санатория!",
			"drops": [Vector2(140, -80)], "drop_names": ["Санаторий «Лесной»"], "final": "",
		},
		{
			"id": "race", "kind": "race", "rating": 35, "pay": 1600, "time": 85.0,
			"icon": "R", "color": "#e86020", "pickup": "kurort",
			"title": "Гонка с бомбилой",
			"desc": "Конкурент вызвался наперегонки до вокзала. Успеешь — премия!",
			"drops": [], "drop_names": ["Ж/д вокзал"], "final": "vokzal",
		},
		{
			"id": "tour", "kind": "tour", "rating": 45, "pay": 2400, "time": 0.0,
			"icon": "Т", "color": "#2e9ec8", "pickup": "center",
			"title": "Экскурсия по Пятигорску",
			"desc": "Туристы хотят увидеть Провал, Эолову арфу и смотровую башню.",
			"drops": [Vector2(-72, -160), Vector2(12, -350), Vector2(0, -448)],
			"drop_names": ["Озеро Провал", "Эолова арфа", "Смотровая башня"], "final": "",
		},
		{
			"id": "night", "kind": "mission", "rating": 60, "pay": 1900, "time": 130.0,
			"icon": "М", "color": "#6a6ac8", "pickup": "prigorod",
			"title": "Ночной рейс на Машук",
			"desc": "Клиент хочет встретить рассвет на Машуке. Ночью платят вдвойне!",
			"drops": [Vector2(0, -448)], "drop_names": ["Смотровая башня"], "final": "",
		},
	]
	var missions: Array[MissionData] = []
	for def: Dictionary in mission_defs:
		var id := String(def["id"])
		var m := MissionData.new()
		m.id = StringName(id)
		m.title = _tr_key("MISSION_%s_TITLE" % id.to_upper(), String(def["title"]))
		m.description = _tr_key("MISSION_%s_DESC" % id.to_upper(), String(def["desc"]))
		m.icon = String(def["icon"])
		m.color = Color(String(def["color"]))
		m.required_rating = int(def["rating"])
		m.pay = int(def["pay"])
		m.time_limit = float(def["time"])
		m.kind = StringName(def["kind"])
		m.pickup_district = StringName(def["pickup"])
		var drops := PackedVector2Array()
		for v: Vector2 in (def["drops"] as Array):
			drops.append(v)
		m.drops = drops
		var names := PackedStringArray()
		var raw_names: Array = def["drop_names"]
		for i in raw_names.size():
			names.append(_tr_key("MISSION_%s_DROP_%d" % [id.to_upper(), i + 1],
				String(raw_names[i])))
		m.drop_names = names
		m.final_drop_from_district = StringName(def["final"])
		missions.append(_save(m, "orders/missions/%s.tres" % id) as MissionData)

	var tiers: Array[MoodTier] = []
	for i in (cfg["MOOD_TIERS"] as Array).size():
		var src: Dictionary = cfg["MOOD_TIERS"][i]
		var t := MoodTier.new()
		t.min_style = float(src["minStyle"])
		t.icon = StringName("mood_%d" % i)
		t.display_name = _tr_key("MOOD_%d_LABEL" % i, String(src["label"]))
		t.color = Color(String(src["color"]))
		tiers.append(_save(t, "orders/mood_%d.tres" % i) as MoodTier)

	var cat := OrderCatalog.new()
	cat.types = items
	cat.missions = missions
	cat.mood_tiers = tiers
	cat.reviews_1 = banks.get("review_1")
	cat.reviews_2 = banks.get("review_2")
	cat.reviews_3 = banks.get("review_3")
	cat.reviews_4 = banks.get("review_4")
	cat.reviews_5 = banks.get("review_5")
	cat.passenger_names = banks.get("passenger_names")
	cat.drift_reactions = banks.get("drift_reaction")
	cat.dispatcher_general = banks.get("dispatcher_general")
	cat.dispatcher_rain = banks.get("dispatcher_rain")
	cat.dispatcher_fog = banks.get("dispatcher_fog")
	cat.dispatcher_night = banks.get("dispatcher_night")
	cat.day_note_good = banks.get("day_note_good")
	cat.day_note_crashes = banks.get("day_note_crashes")
	cat.day_note_low_earned = banks.get("day_note_low_earned")
	cat.day_note_general = banks.get("day_note_general")
	cat.weather_clear = banks.get("weather_clear")
	cat.weather_rain = banks.get("weather_rain")
	cat.weather_fog = banks.get("weather_fog")
	_save(cat, "orders/order_catalog.tres")


# --- Трафик ------------------------------------------------------------------

func _import_traffic(trf: Dictionary, banks: Dictionary) -> void:
	var items: Array[TrafficTypeData] = []
	for src: Dictionary in (trf["TRAFFIC_TYPES"] as Array):
		var id := String(src["name"])
		var t := TrafficTypeData.new()
		t.id = StringName(id)
		t.silhouette = StringName(src["shape"])
		t.radius = float(src["r"])
		t.length = float(src["len"])
		t.width = float(src["w"])
		t.weight = float(src["weight"])
		var colors := PackedColorArray()
		for c: Variant in (src["colors"] as Array):
			colors.append(_color_any(c))
		t.colors = colors
		t.force_color = bool(src.get("forceColor", false))
		t.beacon = StringName(src.get("beacon", ""))
		t.livery = bool(src.get("livery", false))
		t.police_livery = bool(src.get("policeLivery", false))
		t.body_kit = StringName(src.get("bodyKit", "stock"))
		items.append(_save(t, "traffic/types/%s.tres" % id) as TrafficTypeData)

	var cat := TrafficCatalog.new()
	cat.items = items
	cat.quotes_ram = banks.get("driver_ram")
	cat.quotes_ped = banks.get("driver_ped")
	cat.quotes_ped_jwalk = banks.get("driver_ped_jwalk")
	cat.quotes_hit_ped = banks.get("driver_hit_ped")
	cat.quotes_ped_reply = banks.get("driver_ped_reply")
	cat.quotes_ped_reply_jwalk = banks.get("driver_ped_reply_jwalk")
	_save(cat, "traffic/traffic_catalog.tres")


# --- Пешеходы ----------------------------------------------------------------

func _import_peds(pds: Dictionary, banks: Dictionary) -> void:
	# Скорости, масштабы и веса пула — из peds.js:746-750 и 834-845,
	# палитры одежды — из buildPedMesh (utils.js:543+).
	var defs := [
		{"id": "regular", "w": 3.0, "spd": [1.8, 2.7], "sy": [0.92, 1.08], "sxz": [0.92, 1.08],
			"cloth": [], "pants": [], "acc": []},
		{"id": "gopnik", "w": 1.0, "spd": [2.3, 2.9], "sy": [0.95, 1.05], "sxz": [0.92, 1.08],
			"cloth": [0x1e222a, 0x1a2e40, 0x2b382b, 0x111115], "pants": [],
			"acc": ["cap", "shoulder_bag", "stripes"]},
		{"id": "grandma", "w": 1.0, "spd": [1.3, 1.7], "sy": [0.84, 0.92], "sxz": [1.02, 1.15],
			"cloth": [0x604050, 0x4a5a40, 0x5a4a3a, 0x703848], "pants": [0x3a2a3a, 0x2a2a2a],
			"acc": ["headscarf", "string_bag"]},
		{"id": "runner", "w": 1.0, "spd": [4.0, 5.0], "sy": [1.0, 1.12], "sxz": [0.88, 0.96],
			"cloth": [0xee3322, 0x22ee44, 0xeecc00, 0x00ccee, 0xff22aa],
			"pants": [0x111111, 0x222233], "acc": []},
		{"id": "student", "w": 1.0, "spd": [1.8, 2.7], "sy": [0.92, 1.08], "sxz": [0.92, 1.08],
			"cloth": [0xd86030, 0x3090d8, 0x9040d8, 0xe0a020],
			"pants": [0x3a4a5a, 0x2a2a3a, 0x223344], "acc": ["headphones", "backpack"]},
		{"id": "businessman", "w": 1.0, "spd": [1.8, 2.7], "sy": [1.02, 1.10], "sxz": [0.92, 1.08],
			"cloth": [0x1c2430, 0x2a2e36, 0x383430, 0x151c24], "pants": [], "acc": ["briefcase"]},
		{"id": "tourist", "w": 1.0, "spd": [1.8, 2.7], "sy": [0.96, 1.06], "sxz": [0.92, 1.08],
			"cloth": [0xccaa33, 0xdd6633, 0x33aa99, 0x77bb44],
			"pants": [0x998877, 0x445566, 0xaa9988], "acc": ["panama", "camera"]},
		{"id": "child", "w": 1.0, "spd": [2.0, 2.6], "sy": [0.70, 0.78], "sxz": [0.92, 1.08],
			"cloth": [0xff5555, 0x33bbff, 0xffcc00, 0x44dd66],
			"pants": [0x224488, 0x882244], "acc": []},
		{"id": "elder", "w": 1.0, "spd": [1.2, 1.6], "sy": [0.82, 0.90], "sxz": [0.92, 1.08],
			"cloth": [], "pants": [], "acc": ["beard", "cane"]},
		{"id": "mom", "w": 1.0, "spd": [1.6, 2.0], "sy": [0.92, 1.08], "sxz": [0.92, 1.08],
			"cloth": [], "pants": [], "acc": ["stroller"]},
		{"id": "worker", "w": 1.0, "spd": [2.2, 2.8], "sy": [0.92, 1.08], "sxz": [0.92, 1.08],
			"cloth": [], "pants": [], "acc": ["helmet", "hi_vis", "wrench"]},
		{"id": "musician", "w": 1.0, "spd": [1.5, 2.0], "sy": [0.92, 1.08], "sxz": [0.92, 1.08],
			"cloth": [], "pants": [], "acc": ["beret", "instrument"]},
		{"id": "nurse", "w": 1.0, "spd": [2.0, 2.6], "sy": [0.92, 1.08], "sxz": [0.92, 1.08],
			"cloth": [], "pants": [], "acc": ["nurse_cap", "stethoscope"]},
		{"id": "dog", "w": 2.0, "spd": [3.0, 4.2], "sy": [1.0, 1.0], "sxz": [1.0, 1.0],
			"cloth": [], "pants": [], "acc": [], "animal": true},
		{"id": "cat", "w": 2.0, "spd": [2.2, 3.5], "sy": [1.0, 1.0], "sxz": [1.0, 1.0],
			"cloth": [], "pants": [], "acc": [], "animal": true},
	]
	# Шанс ответить ударом вместо бегства — по темпераменту архетипа.
	var retaliate := {
		"gopnik": 0.75, "worker": 0.5, "businessman": 0.3, "elder": 0.25,
		"mom": 0.35, "tourist": 0.15, "runner": 0.1, "student": 0.2,
		"child": 0.0, "grandma": 0.2, "musician": 0.15, "nurse": 0.2, "regular": 0.3,
	}

	var items: Array[PedArchetypeData] = []
	for def: Dictionary in defs:
		var id := String(def["id"])
		var p := PedArchetypeData.new()
		p.id = StringName(id)
		p.is_animal = bool(def.get("animal", false))
		p.speed_min = float(def["spd"][0])
		p.speed_max = float(def["spd"][1])
		p.weight = float(def["w"])
		p.scale_y_min = float(def["sy"][0])
		p.scale_y_max = float(def["sy"][1])
		p.scale_xz_min = float(def["sxz"][0])
		p.scale_xz_max = float(def["sxz"][1])
		var cloth := PackedColorArray()
		for c: int in (def["cloth"] as Array):
			cloth.append(_color_int(c))
		p.cloth_colors = cloth
		var pants := PackedColorArray()
		for c: int in (def["pants"] as Array):
			pants.append(_color_int(c))
		p.pants_colors = pants
		var acc := PackedStringArray()
		for a: String in (def["acc"] as Array):
			acc.append(a)
		p.accessories = acc
		p.retaliate_chance = float(retaliate.get(id, 0.3))
		# Пулы реплик: у животных свои (ANIMAL_DOG/CAT), у людей — по архетипу.
		var idle_key := "ped_animal_" + id if p.is_animal else "ped_" + id
		p.quotes_idle = banks.get(idle_key, banks.get("ped_idle"))
		p.quotes_curse = banks.get("ped_curse_" + id, banks.get("ped_curse"))
		p.quotes_panic = banks.get("ped_punch_witness")
		p.quotes_flee = banks.get("ped_punch_flee_" + id,
			banks.get("ped_punch_flee_default"))
		p.quotes_retaliate = banks.get("ped_punch_retaliate_" + id,
			banks.get("ped_punch_retaliate_default"))
		items.append(_save(p, "peds/archetypes/%s.tres" % id) as PedArchetypeData)

	var cat := PedCatalog.new()
	cat.items = items
	cat.quotes_idle = banks.get("ped_idle")
	cat.quotes_curse = banks.get("ped_curse")
	cat.quotes_curse_sidewalk = banks.get("ped_curse_sidewalk")
	cat.quotes_curse_redlight = banks.get("ped_curse_redlight")
	cat.quotes_shout = banks.get("ped_shout")
	var skins := PackedColorArray()
	for c: int in [0xf5d0b0, 0xd8a878, 0x8a5a3a, 0xc89060, 0xa87850, 0xb08058,
			0x6a4a30, 0xffdbac, 0xecd0b8, 0x9c6b45, 0x523320]:
		skins.append(_color_int(c))
	cat.skin_colors = skins
	var hair := PackedColorArray()
	for c: int in [0x1a1a1a, 0x3a2a1a, 0x6a4a2a, 0xd8c8a8, 0x8a2a2a, 0x2a2a4a,
			0x995522, 0xdcdde1, 0x718093, 0xb0885a, 0x4a4a4a]:
		hair.append(_color_int(c))
	cat.hair_colors = hair
	var shoes := PackedColorArray()
	for c: int in [0x202020, 0x111111, 0xeeeeee, 0x5a3a20, 0x3a3a3a, 0x8a4a2a]:
		shoes.append(_color_int(c))
	cat.shoe_colors = shoes
	var cloth_all := PackedColorArray()
	for c: int in [0x4060a0, 0xa04040, 0x409060, 0xa08040, 0x604080, 0x888888,
			0xc07830, 0x3090a0, 0xe05566, 0x22aa88, 0x2b4c7e, 0x5b6d5b,
			0x6e263c, 0xc2a649, 0x4d5d36, 0xd2b48c]:
		cloth_all.append(_color_int(c))
	cat.cloth_colors = cloth_all
	var pants_all := PackedColorArray()
	for c: int in [0x2a2a3a, 0x3a3a4a, 0x4a3a2a, 0x5a5a5a, 0x1a2430, 0xd0c0aa,
			0x1e3799, 0x2c2c54, 0x384030, 0x484848]:
		pants_all.append(_color_int(c))
	cat.pants_colors = pants_all
	_save(cat, "peds/ped_catalog.tres")


# --- Достижения --------------------------------------------------------------

func _import_achievements(ach: Dictionary) -> void:
	var items: Array[AchievementData] = []
	for src: Dictionary in (ach["items"] as Array):
		var id := String(src["id"])
		var a := AchievementData.new()
		a.id = StringName(id)
		a.display_name = _tr_key("ACH_%s_NAME" % id.to_upper(), String(src["name"]))
		a.description = _tr_key("ACH_%s_DESC" % id.to_upper(), String(src["desc"]))
		a.toast = _tr_key("ACH_%s_TOAST" % id.to_upper(), String(src["toast"]))
		a.icon = StringName(id)
		var reqs: Array[AchievementReq] = []
		for r: Dictionary in (src["requirements"] as Array):
			var req := AchievementReq.new()
			req.stat = StringName(r["stat"])
			match String(r["op"]):
				"LE": req.op = AchievementReq.Op.LE
				"EQ": req.op = AchievementReq.Op.EQ
				_: req.op = AchievementReq.Op.GE
			req.value = float(r["value"])
			reqs.append(req)
		a.requirements = reqs
		a.track_stat = StringName(src["track_stat"])
		a.track_target = float(src["track_target"])
		items.append(_save(a, "achievements/%s.tres" % id) as AchievementData)

	var cat := AchievementCatalog.new()
	cat.items = items
	_save(cat, "achievements/achievement_catalog.tres")


# --- Аудио -------------------------------------------------------------------

func _import_audio(aud: Dictionary) -> void:
	# Музыкальный материал станций: в оригинале он зашит в код секвенсора
	# (audiomusic.js), поэтому лад, инструменты и плотность задаются здесь —
	# так их можно крутить, не трогая код.
	var material := {
		"pyatigorsk": {"scale": [0, 3, 5, 7, 10], "instr": ["kick", "hat", "bass", "pad", "lead"],
			"drums": 0.45, "tex": 0.7, "color": "#8ab4d8"},
		"synth": {"scale": [0, 2, 3, 5, 7, 8, 10], "instr": ["kick", "snare", "hat", "bass", "arp", "pad"],
			"drums": 0.8, "tex": 0.85, "color": "#d264c8"},
		"kavkaz": {"scale": [0, 1, 4, 5, 7, 8, 11], "instr": ["kick", "snare", "hat", "bass", "lead"],
			"drums": 0.9, "tex": 0.6, "color": "#e0a040"},
		"rock": {"scale": [0, 3, 5, 6, 7, 10], "instr": ["kick", "snare", "hat", "bass", "lead"],
			"drums": 1.0, "tex": 0.9, "color": "#d84030"},
		"chanson": {"scale": [0, 2, 3, 5, 7, 8, 10], "instr": ["kick", "bass", "lead", "pad"],
			"drums": 0.35, "tex": 0.5, "color": "#c0a060"},
		"chilled": {"scale": [0, 2, 4, 7, 9], "instr": ["hat", "bass", "pad"],
			"drums": 0.2, "tex": 0.4, "color": "#6a8ab0"},
	}
	var fallback: Dictionary = aud["RADIO_FALLBACK_FREQS"]

	var items: Array[RadioStationData] = []
	for src: Dictionary in (aud["STATIONS"] as Array):
		var id := String(src["id"])
		if id == "off":
			continue # «Радио ВЫКЛ» — состояние, а не станция
		var mat: Dictionary = material.get(id, {})
		var fb: Dictionary = fallback.get(id, {"root": 110.0, "fifth": 164.81})
		var s := RadioStationData.new()
		s.id = StringName(id)
		s.display_name = _tr_key("RADIO_%s_NAME" % id.to_upper(), String(src["name"]))
		s.genre = _tr_key("RADIO_%s_GENRE" % id.to_upper(), String(src["genre"]))
		s.frequency = "%.1f FM" % float(src["freq"])
		s.bpm = float(src["bpm"])
		s.color = Color(String(mat.get("color", "#ffffff")))
		s.root_hz = float(fb["root"])
		s.fifth_hz = float(fb["fifth"])
		var steps := PackedInt32Array()
		for st: int in (mat.get("scale", [0, 2, 3, 5, 7, 8, 10]) as Array):
			steps.append(st)
		s.scale_steps = steps
		var instr := PackedStringArray()
		for i: String in (mat.get("instr", []) as Array):
			instr.append(i)
		s.instruments = instr
		s.drum_density = float(mat.get("drums", 0.5))
		s.texture = float(mat.get("tex", 0.5))
		items.append(_save(s, "audio/stations/%s.tres" % id) as RadioStationData)

	var cat := RadioCatalog.new()
	cat.items = items
	# Числа функций SfxLibrary.* (audiosfx.js) хранятся буквально в теле
	# методов, а не в вынесенных top-level константах — извлечь их
	# balanced-brace дампером (как STATIONS/AU_* выше) невозможно, поэтому
	# они перенесены вручную в tools/sfx_recipe_data.gd по отчёту сверки.
	cat.sfx = SfxRecipeData.build_all()
	_save(cat, "audio/radio_catalog.tres")


# --- Локализация -------------------------------------------------------------

func _write_csv() -> void:
	DirAccess.make_dir_recursive_absolute(CSV_PATH.get_base_dir())
	var f := FileAccess.open(CSV_PATH, FileAccess.WRITE)
	if f == null:
		_errors.append("не открыть на запись %s" % CSV_PATH)
		return
	f.store_line("keys,ru")
	var keys := _loc.keys()
	keys.sort()
	for key: String in keys:
		f.store_line("%s,%s" % [key, _csv_escape(_loc[key])])
	f.close()


static func _csv_escape(s: String) -> String:
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		return "\"%s\"" % s.replace("\"", "\"\"")
	return s
