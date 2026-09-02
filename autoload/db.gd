extends Node
## Db — реестр каталогов-ресурсов. Всё в data/*.tres грузится один раз здесь
## и дальше доступно как Db.cars.get_car(&"taxi").
##
## Все *Data — read-only во время игры. Мутируемое состояние живёт в отдельных
## RefCounted (CarRuntime, OrderRuntime, ...). Присваивание полю *Data вне
## tools/ и tests/ — ошибка код-ревью (см. план, ловушка «@export Resource shared»).

const DATA_ROOT := "res://data"

var balance: BalanceData
var cars: CarCatalog
var upgrades: UpgradeCatalog
var districts: DistrictCatalog
var weather: WeatherCatalog
var orders: OrderCatalog
var traffic: TrafficCatalog
var peds: PedCatalog
var achievements: AchievementCatalog
var stations: RadioCatalog
var gfx: GfxCatalog

var _loaded := false


func _ready() -> void:
	load_all()


func load_all() -> void:
	if _loaded:
		return
	balance = _load("balance/balance.tres") as BalanceData
	cars = _load("cars/car_catalog.tres") as CarCatalog
	upgrades = _load("upgrades/upgrade_catalog.tres") as UpgradeCatalog
	districts = _load("districts/district_catalog.tres") as DistrictCatalog
	weather = _load("weather/weather_catalog.tres") as WeatherCatalog
	orders = _load("orders/order_catalog.tres") as OrderCatalog
	traffic = _load("traffic/traffic_catalog.tres") as TrafficCatalog
	peds = _load("peds/ped_catalog.tres") as PedCatalog
	achievements = _load("achievements/achievement_catalog.tres") as AchievementCatalog
	stations = _load("audio/radio_catalog.tres") as RadioCatalog
	gfx = _load("gfx/gfx_catalog.tres") as GfxCatalog

	for c: Variant in [cars, upgrades, districts, weather, orders, traffic, peds,
			achievements, stations, gfx]:
		if c != null:
			(c as Object).call(&"index")
	_loaded = true


## Каталоги могут отсутствовать до прогона tools/import_json.gd — на ранних
## этапах это норма, поэтому отсутствие файла не валит запуск.
func _load(rel: String) -> Resource:
	var path := DATA_ROOT.path_join(rel)
	if not ResourceLoader.exists(path):
		push_warning("Db: каталог не найден, пропущен: %s" % path)
		return null
	return load(path)
