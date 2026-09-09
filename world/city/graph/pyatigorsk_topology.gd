class_name PyatigorskTopology
extends RefCounted
## Топология Пятигорска: конкретные узлы и рёбра, которыми заполняется
## `CityGraph` (этап 1) вместо синтетической сетки 9x9
## (`for i in 9: road_axes.append(-256.0 + i * cell)`, city_field.gd:80-81).
##
## [b]Форма — «хребет + сетка + огибание склона»[/b], не радиально-кольцевая:
## кольцевой структуры у реального Пятигорска нет. Хребет — проспект Кирова
## (восток→запад, от привокзальной площади до Цветника и дальше на западную
## окраину). Вторая ось — улица Калинина (север→юг, самая длинная улица
## города), пересекает Кирова в центре. Вокруг их пересечения — регулярная
## сетка кварталов исторического плана 1828-1830-х. К северу улицы
## перестают быть прямоугольными и огибают подножие Машука (бульвар
## Гагарина к Провалу, дуга у подножия), а на саму гору уходит серпантин.
## Периферия (пригород, санатории, вокзал) заметно реже центра.
##
## [b]Литерал, а не генератор.[/b] Вся топология задана руками, ни одного
## обращения к `SeededRng`: это контент («где какая улица»), а не алгоритм.
## Ровно так же заданы девять осей сетки сегодня. Детерминизм отсюда следует
## тривиально: повторный `build()` даёт побитово тот же граф, `world_seed` на
## топологию не влияет вовсе, сравнивать нечего кроме самих литералов. Если
## позже понадобятся процедурные второстепенные проезды, их можно добавить
## поверх, параметризовав `Db.balance.world_seed`; сейчас такой потребности
## нет, а руками заданная топология проще к ревью и к правкам этапов 3-9.
##
## [b]Высоты[/b] узлов и точек полилиний снимаются с `CityField.height_at()`:
## рельеф остаётся за `CityField`, топология его только читает. Исключение —
## путепровод у вокзала: эстакады в поле рельефа нет и быть не должно, её
## высота задана здесь явно.
##
## Отсюда следует решение этапа 3 об [b]источнике профиля уклона[/b]: уклон
## обычных улиц НЕ авторский, а из общего поля рельефа. Так полотно не
## расходится с тротуарами, дворами и посадкой зданий по обе стороны улицы —
## у высоты земли один владелец, а не два спорящих. Авторскими остаются
## ровно те высоты, которых поле выразить не может: одна точка (x, z) в нём
## имеет одну высоту, поэтому пролёт над улицей и пандусы к нему заданы
## литералами (`OVERPASS_DECK_Y`). Улица с настоящим уклоном вне серпантина
## при этом уже есть — «Верхняя Машукская дорога», 13 м подъёма на 170 м
## пути по склону Машука, целиком из поля рельефа.
##
## [b]Названия улиц[/b] лежат в графе обычными строками, а не ключами
## локализации: сегодня ни один экран их не показывает, а
## `.agents/rules/data-pipeline.md` требует `_tr_key()`/CSV именно для
## пользовательских строк. Как только название попадёт игроку на глаза
## (вывеска на перекрёстке, подпись на карте) — перевести в ключи и вынести
## в `assets/i18n/game.csv`. Сами топонимы взяты из исторических справок о
## планировке города и НЕ сверены с актуальной адресной базой (2ГИС/OSM):
## перед показом игроку сверить, ошибка в топониме заметнее неточности формы.
##
## [b]Тоннели этой итерацией не делаются[/b] — сознательно отложены.
## `CityGraph.EdgeKind.TUNNEL` и отрицательные уровни узлов в модели уже
## есть, но в реальном Пятигорске нет очевидного места под автомобильный
## тоннель, а разноуровневых развязок для этапа 3 достаточно одной (путепровод
## у вокзала). Заводить тоннель без места в городе значит проектировать
## геометрию впустую — ровно то, чего этот этап велит избегать.

# --- Ширины полотна, м ------------------------------------------------------
## Проспект Кирова. В полтора раза шире обычной улицы: главная ось обязана
## читаться на схеме города шире прочих.
const W_AVENUE := 18.0
## Улица Калинина — вторая магистральная ось, уже проспекта, шире улицы.
const W_MAIN := 16.0
## Обычная улица: полотно оригинала, 2 * BalanceData.road_half = 2 * 6
## (city_field.gd:39).
const W_STREET := 12.0
## Переулок, подъездной и периферийный проезд.
const W_LANE := 8.0
## Ширина серпантина читается из `CityField.mountain_route_width()` —
## полка в рельефе шире полотна на обочину, а не ровно с ним совпадает, и
## у ширины один владелец. Здесь не дублируется даже как константа.

## Отметка деки путепровода у вокзала над улицей Крайнего, м — высота
## ПРОЕЗЖЕЙ ЧАСТИ пролёта, а не просвет под ним: просвет меньше на толщину
## плиты (`BridgeGeometry.DECK_THICKNESS`) и проверяется тестом против
## `CityGraph.MIN_CLEARANCE`. Отметка выбрана так, чтобы после вычета плиты
## запас над минимумом оставался больше метра, а пандусы по 70 м в плане
## держались уклона 9.3%.
const OVERPASS_DECK_Y := 6.5

## Шаг уплотнения полилинии внутри коридора рельефа, м. Профиль высоты
## снимается с `CityField.height_at` в каждой точке; 12 м — компромисс между
## точностью профиля на уклоне до 17% (перепад между соседними точками около
## 2 м) и числом сегментов в пространственном хеше графа.
const TERRAIN_STEP := 12.0

## Шаг уплотнения полилинии рампы и пролёта, м. Мельче рельефного: пандус
## короткий (70 м), а профиль высоты на нём — главное, что он несёт; 10 м
## дают семь промежуточных точек с шагом подъёма 0.93 м.
const RAMP_STEP := 10.0

## Плановая точка лендмарка «Эолова арфа» (data/landmarks/gazebo.tres).
## Она лежит практически на оси серпантина, поэтому узел ставится не рядом с
## ней, а в ближайшую вершину полилинии серпантина: подъездное ребро длиной
## в метр было бы вырожденным, а лендмарк в стороне от полотна — неправдой.
const GAZEBO_ANCHOR := Vector2(12.0, -350.0)

# --- Названия главных осей --------------------------------------------------
const NAME_KIROV := "проспект Кирова"
const NAME_KALININ := "улица Калинина"

# --- Результат --------------------------------------------------------------
var graph := CityGraph.new()
## Узлы со светофором — явные данные для этапа 7 вместо арифметики чётности
## индексов (`PedGraph.is_signalized()`, ped_graph.gd:149-150).
var signal_nodes := PackedInt32Array()
## Узлы фронта зелёной волны — тоже явные данные, а не «полоса у минимального
## x» (`NodeSignalController.FRONT_BAND`). Заполняется `_bind_signals()`.
var wave_front_nodes := PackedInt32Array()
## Район каждого узла, индекс = id узла. Замена `CityPlanner.block_district()`
## по индексам квартала (city_planner.gd:108-120).
var node_district: Array[StringName] = []
## Лендмарк -> узел графа, к которому он привязан.
var landmark_node: Dictionary[StringName, int] = {}
## Лендмарк -> подъездное ребро (для тех, кто стоит в стороне от полотна).
var landmark_approach: Dictionary[StringName, int] = {}

var _field: CityField
var _id: Dictionary[StringName, int] = {}


## Собирает граф. `field` нужен ради рельефа (`height_at`) и готовой оси
## серпантина (`serpentine_points`) — переизобретать математику подъёма
## здесь нельзя, у неё один владелец.
func build(field: CityField) -> CityGraph:
	_field = field
	_place_center_grid()
	_place_kirov_tails()
	_place_kalinin_tails()
	_place_kurort()
	_place_foothill()
	_place_sanatorii()
	_place_mountain()
	_place_vokzal()
	_place_prigorod()

	_kirov()
	_kalinin()
	_center_streets()
	_kurort_streets()
	_foothill_streets()
	_mountain_streets()
	_sanatorii_streets()
	_vokzal_streets()
	_prigorod_streets()

	_bind_landmarks()
	_bind_signals()
	graph.build()
	return graph


# ============================================================================
# Узлы
# ============================================================================
#
# Районы разложены по геометрии хребта, а не по индексам квартала:
#   center     — сетка вокруг пересечения Кирова x Калинина;
#   kurort     — запад и северо-запад центра, начало курортной цепочки;
#   proval     — северо-западная ветвь бульвара Гагарина до Провала;
#   mashuk     — северная дуга у подножия и дороги на гору;
#   sanatorii  — северо-восток, дальше по тому же подъезду к горе;
#   rynok      — восточный участок Кирова и Пирогова у Верхнего рынка;
#   vokzal     — юго-восток: привокзальная площадь и улица Крайнего;
#   prigorod   — южная и западная периферия, самая редкая сеть.
#
# Это тот же взаимный порядок, что в `block_district()` (курорт западнее
# центра, рынок восточнее, вокзал в юго-восточном углу, пригород по южной
# кромке, машук и провал у северной), только выраженный через улицы, а не
# через клетки 8x8.

## Сетка кварталов исторического плана 1828-1830-х: четыре продольные улицы
## (Чкалова, Соборная, Кирова, Красноармейская) и пять поперечных
## (Анисимова, Лермонтова, Калинина, Буачидзе, Пастухова).
##
## Кварталы намеренно НЕ равны 44x44 м (`CityPlanner.BLOCK_SIDE`): ширины
## 44/56/40/32 м и высоты 37/33/42 м — центр плотнее и неровнее окраины,
## как и в настоящем городе.
func _place_center_grid() -> void:
	# Чкалова — самая северная продольная центра.
	_node(&"chk_w", -76.0, -64.0, &"center")
	_node(&"chk_lerm", -32.0, -52.0, &"center")
	_node(&"chk_kal", 24.0, -48.0, &"center")
	_node(&"chk_bua", 64.0, -46.0, &"center")
	_node(&"chk_past", 96.0, -42.0, &"sanatorii")
	# Соборная. Узел на Лермонтова — сам лендмарк «Нарзанные ванны» (-32,-15).
	_node(&"sob_w", -76.0, -27.0, &"kurort")
	_node(&"sob_narzan", -32.0, -15.0, &"center")
	_node(&"sob_kal", 24.0, -11.0, &"center")
	_node(&"sob_bua", 64.0, -9.0, &"center")
	# Верхний рынок: лендмарк «Рынок Лира» (96,-8) стоит площадью, поэтому
	# узел кольцевой — по нему объезжают торговые ряды.
	_ring(&"pir_rynok", 96.0, -8.0, &"rynok", 16.0)
	# Проспект Кирова в пределах центра.
	_node(&"kir_anis", -76.0, 30.0, &"kurort")
	_node(&"kir_cvetnik", -32.0, 18.0, &"center")
	_node(&"kir_kalinin", 24.0, 22.0, &"center")
	_node(&"kir_bua", 64.0, 24.0, &"center")
	_node(&"kir_past", 96.0, 31.0, &"rynok")
	# Красноармейская — южная продольная центра.
	_node(&"kra_w", -76.0, 72.0, &"kurort")
	_node(&"kra_lerm", -32.0, 62.0, &"center")
	_node(&"kra_kal", 24.0, 64.0, &"center")
	_node(&"kra_bua", 64.0, 66.0, &"center")
	_node(&"kra_past", 96.0, 72.0, &"rynok")
	# Грот Лермонтова стоит в парке над Цветником, в стороне от полотна
	# проспекта, — тупиковый узел на конце короткого переулка.
	_node(&"lm_grot", -52.0, 8.0, &"center")


## Концы хребта: западная окраина и привокзальная площадь на востоке.
## Полная длина проспекта — 368 м, три четверти поперечника города: сетка
## оригинала укладывает весь Пятигорск в 512 м, и в этом масштабе 368 м —
## это и есть 2.5 км проспекта Кирова.
func _place_kirov_tails() -> void:
	_node(&"kir_w2", -176.0, 26.0, &"prigorod")
	_node(&"kir_w1", -124.0, 34.0, &"kurort")
	_node(&"kir_e1", 136.0, 62.0, &"vokzal")
	# Привокзальная площадь: кольцо радиусом 22 м вокруг сквера перед
	# вокзалом. Лендмарк «Ж/д вокзал» (160,96) — этот самый узел.
	_ring(&"kir_vokzal", 160.0, 96.0, &"vokzal", 22.0)


## Калинина за пределами центральной сетки: на север к подножию Машука и на
## юг в пригород. Общая протяжённость по z от -202 до 232 — 434 м, самая
## длинная улица графа, как и в реальном городе.
func _place_kalinin_tails() -> void:
	_node(&"kal_n1", 22.0, -104.0, &"center")
	_node(&"kal_n2", 20.0, -160.0, &"mashuk")
	_node(&"kal_n3", 14.0, -202.0, &"mashuk")
	_node(&"kal_s1", 26.0, 112.0, &"center")
	# Кольцо на южном выезде: развязка Калинина с пригородными проездами и
	# съездом на путепровод — четыре направления без светофора.
	_ring(&"kal_s2", 30.0, 172.0, &"prigorod", 18.0)
	_node(&"kal_s3", 34.0, 232.0, &"prigorod")


## Курортная цепочка: от центра на северо-запад к Провалу, плюс редкая сеть
## западнее сетки. Улицы здесь уже заметно кривые — они огибают склон.
func _place_kurort() -> void:
	_node(&"kur_w1", -134.0, -40.0, &"kurort")
	_node(&"kur_n", -116.0, -96.0, &"kurort")
	_node(&"kur_s", -126.0, 112.0, &"kurort")
	_node(&"gag_1", -84.0, -96.0, &"kurort")
	_node(&"gag_2", -98.0, -124.0, &"proval")
	_node(&"gag_3", -92.0, -148.0, &"proval")
	# Лендмарк «Провал» (-72,-160) — тупиковый конец бульвара Гагарина,
	# ровно как в городе: бульвар упирается в вход в пещеру.
	_node(&"lm_proval", -72.0, -160.0, &"proval")


## Дуга у подножия Машука — та самая «естественная кривизна из местности».
## Идёт от Провала на восток мимо северного конца Калинина к санаториям.
func _place_foothill() -> void:
	_node(&"foot_w", -36.0, -182.0, &"mashuk")
	_node(&"foot_e1", 64.0, -190.0, &"mashuk")
	_node(&"foot_e2", 118.0, -166.0, &"sanatorii")


## Санатории: северо-восток, дальше по подъезду к горе. Сеть нерегулярная и
## заметно реже центра — четыре узла на четверть города.
func _place_sanatorii() -> void:
	_node(&"san_a", 140.0, -72.0, &"sanatorii")
	_node(&"san_b", 96.0, -104.0, &"sanatorii")
	_node(&"san_c", 150.0, -134.0, &"sanatorii")
	_node(&"san_d", 188.0, -100.0, &"sanatorii")
	_node(&"pir_e", 134.0, -4.0, &"rynok")


## Гора: подъезд к канатной дороге, верхняя траверсная дорога и серпантин.
## Координаты — опорные точки соответствующих трасс `CityField`
## (`mountain_route_points`), а не литералы: у формы и подъёма горных дорог
## один владелец, топология их только читает — тот же приём, каким уже был
## заведён серпантин. Узлы серпантина по-прежнему ставятся в вершины его
## полилинии, чтобы `CityGraph._snap_endpoints()` не сдвигал полотно с оси.
func _place_mountain() -> void:
	var road := _field.mountain_route_points(CityField.ROUTE_MASHUK_ROAD)
	_node_at(&"mash_1", road[0], &"mashuk")
	# Лендмарк «Канатная дорога» (20,-288) — узел на конце подъезда.
	_node_at(&"lm_cable", road[road.size() - 1], &"mashuk")

	var approach := _field.mountain_route_points(CityField.ROUTE_SERP_APPROACH)
	_node_at(&"mash_e", approach[0], &"mashuk")

	# Верхняя Машукская дорога: траверс по западному склону. Профиль высоты
	# снимается с рельефа — единственная негорная трасса с заметным подъёмом
	# (13 м на 172 м пути), требуемая этапом 3.
	var upper := _field.mountain_route_points(CityField.ROUTE_UPPER_MASHUK)
	_node_at(&"mash_w1",
		upper[_field.mountain_route_anchor(CityField.ROUTE_UPPER_MASHUK, 1)], &"mashuk")
	_node_at(&"mash_w2",
		upper[_field.mountain_route_anchor(CityField.ROUTE_UPPER_MASHUK, 2)], &"mashuk")
	_node_at(&"mash_w3", upper[upper.size() - 1], &"mashuk")

	var serp := _field.serpentine_points()
	_node_at(&"serp_bot", serp[0], &"mashuk")
	_node_at(&"lm_gazebo", serp[_gazebo_index(serp)], &"mashuk")
	# Торец серпантина отстоит от лендмарка «Смотровая башня» (0,-448)
	# примерно на 2 м — это одна и та же площадка на вершине, отдельного
	# узла и подъездного ребра ей не нужно.
	_node_at(&"lm_tower", serp[serp.size() - 1], &"mashuk")


## Вокзал: улица Крайнего вдоль путей и путепровод через них.
##
## Разноуровневое пересечение здесь одно и оно осмысленное: улица Козлова
## переходит в путепровод и проходит НАД улицей Крайнего, идущей вдоль
## железнодорожных путей. Общего узла у них нет — в этом и смысл развязки;
## `CityGraph` разводит их по высоте (LEVEL_TOLERANCE).
func _place_vokzal() -> void:
	_node(&"krn_nn", 60.0, 196.0, &"prigorod")
	_node(&"krn_n", 96.0, 168.0, &"vokzal")
	_node(&"krn_m", 140.0, 132.0, &"vokzal")
	_node(&"krn_e", 200.0, 66.0, &"vokzal")
	_node(&"vok_e", 188.0, 26.0, &"vokzal")
	# Пролёт путепровода: ярус 1, отметка +6.5 м над улицей Крайнего.
	_deck_node(&"koz_d1", 69.0, 167.0, &"vokzal")
	_deck_node(&"koz_d2", 94.0, 199.0, &"vokzal")
	# Южный устой: пандусы длиной 70 м в плане дают уклон 9.3%.
	_node(&"koz_b", 137.0, 254.0, &"prigorod")


## Пригород: три узла на всю южную кромку — плотность сети падает от центра
## к окраине, а не одинакова по городу, как в сетке 9x9 сегодня.
func _place_prigorod() -> void:
	_node(&"pri_w", -70.0, 192.0, &"prigorod")
	_node(&"pri_e", 86.0, 236.0, &"prigorod")
	_node(&"pri_s", -20.0, 254.0, &"prigorod")


# ============================================================================
# Рёбра
# ============================================================================

## Хребет: от западной окраины через Цветник и центр к привокзальной площади.
func _kirov() -> void:
	_chain(NAME_KIROV, [
		&"kir_w2", &"kir_w1", &"kir_anis", &"kir_cvetnik", &"kir_kalinin",
		&"kir_bua", &"kir_past", &"kir_e1", &"kir_vokzal",
	], W_AVENUE, CityGraph.EdgeKind.AVENUE)


## Вторая ось: от подножия Машука на севере до южного края пригорода.
func _kalinin() -> void:
	_chain(NAME_KALININ, [
		&"kal_n3", &"kal_n2", &"kal_n1", &"chk_kal", &"sob_kal",
		&"kir_kalinin", &"kra_kal", &"kal_s1", &"kal_s2", &"kal_s3",
	], W_MAIN, CityGraph.EdgeKind.AVENUE)


## Сетка центра. Названия — «ермоловские» улицы плана 1828 года и улицы
## плана Окружного города 1828-1830-х.
func _center_streets() -> void:
	_chain("улица Чкалова",
		[&"chk_w", &"chk_lerm", &"chk_kal", &"chk_bua", &"chk_past"], W_STREET)
	_chain("улица Соборная",
		[&"sob_w", &"sob_narzan", &"sob_kal", &"sob_bua"], W_STREET)
	# Восточное продолжение Соборной у Верхнего рынка носит своё имя.
	_chain("улица Пирогова", [&"sob_bua", &"pir_rynok", &"pir_e"], W_STREET)
	_chain("улица Красноармейская",
		[&"kra_w", &"kra_lerm", &"kra_kal", &"kra_bua", &"kra_past"], W_STREET)
	_chain("улица Анисимова",
		[&"chk_w", &"sob_w", &"kir_anis", &"kra_w"], W_STREET)
	_chain("улица Лермонтова",
		[&"chk_lerm", &"sob_narzan", &"kir_cvetnik", &"kra_lerm"], W_STREET)
	_chain("улица Буачидзе",
		[&"chk_bua", &"sob_bua", &"kir_bua", &"kra_bua"], W_STREET)
	_chain("улица Пастухова",
		[&"chk_past", &"pir_rynok", &"kir_past", &"kra_past"], W_STREET)
	_chain("переулок к Гроту Лермонтова", [&"kir_cvetnik", &"lm_grot"], W_LANE)


## Курортная цепочка на северо-западном подходе к Машуку. Бульвар Гагарина
## заведён кривыми полилиниями: улицы у подножия отклоняются от прямых
## углов, огибая рельеф, — это и отличает форму города от решётки.
func _kurort_streets() -> void:
	_link("бульвар Гагарина", &"chk_w", &"gag_1", W_STREET,
		CityGraph.EdgeKind.STREET, PackedVector2Array([Vector2(-82.0, -80.0)]))
	_link("бульвар Гагарина", &"gag_1", &"gag_2", W_STREET,
		CityGraph.EdgeKind.STREET, PackedVector2Array([Vector2(-94.0, -108.0)]))
	_link("бульвар Гагарина", &"gag_2", &"gag_3", W_STREET,
		CityGraph.EdgeKind.STREET, PackedVector2Array([Vector2(-101.0, -137.0)]))
	_link("бульвар Гагарина", &"gag_3", &"lm_proval", W_STREET,
		CityGraph.EdgeKind.STREET, PackedVector2Array([Vector2(-84.0, -157.0)]))
	_chain("улица Хетагурова", [&"kur_w1", &"kur_n", &"gag_1"], W_STREET)
	_chain("улица Октябрьская", [&"kir_w2", &"kur_w1", &"sob_w"], W_STREET)
	_chain("улица Октябрьская", [&"kur_w1", &"kir_w1"], W_STREET)
	_chain("улица Дунаевского", [&"kir_w1", &"kur_s", &"pri_w"], W_LANE)
	_chain("улица 40 лет Октября", [&"kra_w", &"kur_s"], W_LANE)


## Дуга у подножия и подъезды к горе.
func _foothill_streets() -> void:
	_link("улица Машукская", &"lm_proval", &"foot_w", W_STREET,
		CityGraph.EdgeKind.STREET, PackedVector2Array([Vector2(-56.0, -176.0)]))
	_link("улица Машукская", &"foot_w", &"kal_n3", W_STREET,
		CityGraph.EdgeKind.STREET, PackedVector2Array([Vector2(-12.0, -196.0)]))
	_link("улица Машукская", &"kal_n3", &"foot_e1", W_STREET,
		CityGraph.EdgeKind.STREET, PackedVector2Array([Vector2(38.0, -200.0)]))
	_link("улица Машукская", &"foot_e1", &"foot_e2", W_STREET,
		CityGraph.EdgeKind.STREET, PackedVector2Array([Vector2(94.0, -184.0)]))


## Дороги горы. Внутри коридора рельефа (kal_n3->mash_1, foot_e2->mash_e —
## ещё вне него) каждое ребро заведено готовой полилинией одной из
## `CityField.mountain_route_points()` — своей математики подъёма и своей
## ширины здесь нет и быть не должно, у полки один владелец (`CityField`).
func _mountain_streets() -> void:
	_link("дорога на Машук", &"kal_n3", &"mash_1", W_STREET)
	_route_edge("дорога на Машук", &"mash_1", &"lm_cable",
		CityField.ROUTE_MASHUK_ROAD, 0, -1)

	_link("подъезд к серпантину", &"foot_e2", &"mash_e", W_STREET)
	_route_edge("подъезд к серпантину", &"mash_e", &"serp_bot",
		CityField.ROUTE_SERP_APPROACH, 0, -1)

	# Траверс по западному склону: единственная улица с настоящим профилем
	# высоты вне серпантина (0 -> 13 м на 172 м пути). Три ребра одной
	# трассы — каждое своя часть общей полилинии (см. _place_mountain).
	_route_edge("Верхняя Машукская дорога", &"lm_cable", &"mash_w1",
		CityField.ROUTE_UPPER_MASHUK, 0, 1)
	_route_edge("Верхняя Машукская дорога", &"mash_w1", &"mash_w2",
		CityField.ROUTE_UPPER_MASHUK, 1, 2)
	_route_edge("Верхняя Машукская дорога", &"mash_w2", &"mash_w3",
		CityField.ROUTE_UPPER_MASHUK, 2, 3)

	var serp := _field.serpentine_points()
	var mid := _gazebo_index(serp)
	_serpentine_link(&"serp_bot", &"lm_gazebo", serp.slice(0, mid + 1))
	_serpentine_link(&"lm_gazebo", &"lm_tower", serp.slice(mid))


## Ребро горной трассы: план, профиль высоты и ширина берутся целиком из
## `CityField.mountain_route_points`/`mountain_route_width` — здесь не
## пересчитываются, у полки один владелец. `anchor_from`/`anchor_to` — номера
## опорных точек плана трассы (`-1` — последняя).
func _route_edge(street: String, a: StringName, b: StringName, route: int,
		anchor_from: int, anchor_to: int) -> void:
	var pts := _field.mountain_route_points(route)
	var i0 := _field.mountain_route_anchor(route, anchor_from)
	var i1 := pts.size() - 1 if anchor_to < 0 \
		else _field.mountain_route_anchor(route, anchor_to)
	graph.add_edge(_id[a], _id[b], pts.slice(i0, i1 + 1),
		_field.mountain_route_width(route), CityGraph.EdgeKind.STREET, 0, street)


func _sanatorii_streets() -> void:
	_chain("улица Университетская",
		[&"pir_e", &"san_a", &"san_d", &"san_c"], W_LANE)
	_chain("улица Университетская", [&"chk_past", &"san_a"], W_LANE)
	_chain("улица Дзержинского",
		[&"chk_past", &"san_b", &"san_c", &"foot_e2"], W_LANE)


## Вокзал, улица Крайнего вдоль путей и путепровод улицы Козлова над ними.
func _vokzal_streets() -> void:
	_chain("улица Крайнего",
		[&"krn_nn", &"krn_n", &"krn_m", &"kir_vokzal", &"krn_e"], W_STREET)
	# Связка `kir_e1 - krn_m` заведена ДУГОЙ, а не хордой. Прямая между этими
	# узлами проходила в 22.0 м от центра привокзального кольца, радиус которого
	# ровно 22 м: её полотно физически накрывало аннулюс, а тротуар кольца
	# пересекал проезжую часть. Заодно она расходилась с проспектом Кирова
	# всего на 32°, и места тротуару между двумя полотнами не оставалось.
	#
	# Промежуточных точек ТРИ, а не одна, и лежат они на окружности радиусом
	# 39 м вокруг центра кольца. Снизу границу задаёт тротуарная окружность
	# кольца (радиус 30 м, см. `PedGraph._ring_radius`) плюс полуполотно самой
	# улицы: ближе 36 м к центру заходить нельзя. Сверху — излом полилинии:
	# одной точкой тот же обход даёт поворот на 94°, а на изломе острее
	# прямого угла внутренняя кромка тротуара уходит в бесконечность
	# (`PedGraph._push_out`). Три точки дают повороты по 23-28° и запас 3 м
	# до тротуара кольца.
	_link("", &"kir_e1", &"krn_m", W_STREET, CityGraph.EdgeKind.STREET,
		PackedVector2Array([
			Vector2(122.0, 82.0), Vector2(120.0, 98.0), Vector2(125.0, 116.0),
		]))
	_chain("", [&"kir_e1", &"vok_e", &"krn_e"], W_STREET)
	_chain("", [&"pir_e", &"vok_e"], W_LANE)
	_chain("", [&"kra_past", &"kir_e1"], W_LANE)
	# Пандусы — рёбра RAMP: нижний конец на земле, верхний на эстакаде, между
	# ними полилиния с нарастающей высотой (шаг RAMP_STEP). Уровень ребра
	# один на всё ребро, поэтому у рампы он равен ярусу НИЖНЕГО конца, а сам
	# переход между ярусами и есть рампа. У пролёта оба конца на ярусе 1.
	_link("улица Козлова", &"kal_s1", &"koz_d1", W_STREET,
		CityGraph.EdgeKind.RAMP)
	_link("путепровод на улице Козлова", &"koz_d1", &"koz_d2", W_STREET,
		CityGraph.EdgeKind.BRIDGE, PackedVector2Array(), 1)
	_link("улица Козлова", &"koz_d2", &"koz_b", W_STREET,
		CityGraph.EdgeKind.RAMP)


func _prigorod_streets() -> void:
	_chain("", [&"kal_s2", &"krn_nn", &"pri_e"], W_LANE)
	_chain("", [&"kal_s2", &"pri_w", &"pri_s", &"kal_s3"], W_LANE)
	_chain("", [&"kal_s3", &"pri_e", &"koz_b"], W_LANE)


# ============================================================================
# Привязки
# ============================================================================

## Девять лендмарков (`data/landmarks/*.tres`). Координаты лендмарков —
## данные оригинала, топология строилась вокруг них, а не наоборот.
##
## Восемь стоят у полотна и стали узлами графа ровно в своих координатах.
## Девятый — Грот Лермонтова — стоит в парке над Цветником, поэтому получил
## не место на магистрали, а собственный тупиковый узел и подъездное ребро
## («переулок к Гроту Лермонтова»), записанное в `landmark_approach`.
## Смотровая башня и Эолова арфа лежат на самой оси серпантина: их узлы
## поставлены в ближайшие вершины его полилинии, отклонение 2.4 и 0.4 м.
func _bind_landmarks() -> void:
	landmark_node[&"cvetnik"] = _id[&"kir_cvetnik"]
	landmark_node[&"narzan"] = _id[&"sob_narzan"]
	landmark_node[&"rynok"] = _id[&"pir_rynok"]
	landmark_node[&"vokzal"] = _id[&"kir_vokzal"]
	landmark_node[&"proval"] = _id[&"lm_proval"]
	landmark_node[&"cable"] = _id[&"lm_cable"]
	landmark_node[&"gazebo"] = _id[&"lm_gazebo"]
	landmark_node[&"tower"] = _id[&"lm_tower"]
	landmark_node[&"grot"] = _id[&"lm_grot"]
	landmark_approach[&"grot"] = _edge_between(&"kir_cvetnik", &"lm_grot")


## Регулируемые узлы. Правило одно и явное: светофор стоит там, где
## магистральная ось (Кирова, Калинина) сходится минимум с тремя
## направлениями. На кольцах светофора нет по определению; на изломах оси
## (`kal_n1`, `kal_n2`) регулировать нечего — это не перекрёстки; на
## периферии — приоритетные развязки, там поток редкий и светофор только
## тормозил бы игрока.
##
## Фронт зелёной волны — ОДИН узел: западный въезд в город по проспекту
## Кирова (`kir_w2`). Волна задумана вдоль хребта города, а расстояние от
## `kir_w2` по рёбрам графа вдоль проспекта в точности равно пройденному по
## нему пути, поэтому колонна, идущая с запада по Кирова на разрешённой
## скорости, проходит все его перекрёстки на зелёный — ровно то, что делала
## осевая модель на сетке. Брать вместо него «все западные концы продольных
## улиц» нельзя: их x различаются на сотню метров (Кирова уходит на -176,
## остальные обрываются на -76), и такой «фронт» был бы не линией, а рваным
## множеством, от которого волна пошла бы рывками.
func _bind_signals() -> void:
	for id: StringName in [
		&"kir_anis", &"kir_cvetnik", &"kir_kalinin", &"kir_bua", &"kir_past",
		&"kir_e1", &"chk_kal", &"sob_kal", &"kra_kal", &"kal_s1", &"krn_m",
	]:
		signal_nodes.append(_id[id])
	wave_front_nodes.append(_id[&"kir_w2"])


# ============================================================================
# Служебное
# ============================================================================

## Узел на рельефе: высота берётся из поля, а не задаётся руками.
func _node(id: StringName, x: float, z: float, district: StringName) -> void:
	_add(id, Vector3(x, _field.height_at(x, z), z), district,
		CityGraph.NodeKind.INTERSECTION, 0.0, 0)


## Узел с готовой позицией — для вершин серпантина, где высота уже посчитана
## профилем подъёма и переснимать её с поля нельзя.
func _node_at(id: StringName, pos: Vector3, district: StringName) -> void:
	_add(id, pos, district, CityGraph.NodeKind.INTERSECTION, 0.0, 0)


func _ring(id: StringName, x: float, z: float, district: StringName,
		radius: float) -> void:
	_add(id, Vector3(x, _field.height_at(x, z), z), district,
		CityGraph.NodeKind.ROUNDABOUT, radius, 0)


## Узел пролёта путепровода: ярус 1, высота задана явно — рельеф про
## эстакаду ничего не знает и знать не должен.
func _deck_node(id: StringName, x: float, z: float, district: StringName) -> void:
	_add(id, Vector3(x, OVERPASS_DECK_Y, z), district,
		CityGraph.NodeKind.INTERSECTION, 0.0, 1)


func _add(id: StringName, pos: Vector3, district: StringName, kind: int,
		radius: float, level: int) -> void:
	if _id.has(id):
		push_error("PyatigorskTopology: узел %s объявлен дважды" % id)
		return
	_id[id] = graph.add_node(pos, level, kind, radius)
	node_district.append(district)


## Цепочка узлов одной улицы: последовательные пары становятся рёбрами.
func _chain(street: String, ids: Array, width: float,
		kind: int = CityGraph.EdgeKind.STREET) -> void:
	for i in ids.size() - 1:
		var a: StringName = ids[i]
		var b: StringName = ids[i + 1]
		_link(street, a, b, width, kind)


## Ребро между двумя узлами. `via` — промежуточные точки плана (кривизна
## улицы), высота вдоль полилинии достраивается сама.
func _link(street: String, a: StringName, b: StringName, width: float,
		kind: int = CityGraph.EdgeKind.STREET,
		via: PackedVector2Array = PackedVector2Array(),
		level: int = 0) -> int:
	var na := _id[a]
	var nb := _id[b]
	return graph.add_edge(na, nb, _polyline(na, nb, via), width, kind,
		level, street)


## Ребро серпантина: полилиния приходит готовой из `CityField`, трогать её
## нельзя — это та же ось, по которой врезана полка в рельефе.
func _serpentine_link(a: StringName, b: StringName,
		points: PackedVector3Array) -> void:
	graph.add_edge(_id[a], _id[b], points,
		_field.mountain_route_width(CityField.ROUTE_SERPENTINE),
		CityGraph.EdgeKind.SERPENTINE, 0, "серпантин на Машук")


## Полилиния ребра: план из концов и `via`, высота — с рельефа.
##
## Внутри коридора рельефа (`CityField.TERRAIN_Z_MAX`) полилиния уплотняется
## шагом TERRAIN_STEP, иначе прямая между двумя точками срезала бы склон.
## Южнее коридора рельеф плоский, и две точки на ребро — ровно то, что нужно
## пространственному хешу графа.
##
## Ребро, у которого хотя бы один конец на другом ярусе (пандус, пролёт),
## рельеф не читает вовсе: его высота линейно интерполируется между концами.
## Уплотняется оно тоже — шагом RAMP_STEP: без промежуточных точек пандус
## был бы одним 70-метровым сегментом, который в хеше графа накрывает габарит
## во всю развязку, а мешеру этапа 4 не даёт ни одной точки профиля.
func _polyline(a: int, b: int, via: PackedVector2Array) -> PackedVector3Array:
	var pa := graph.node_position(a)
	var pb := graph.node_position(b)
	var plan := PackedVector2Array([Vector2(pa.x, pa.z)])
	plan.append_array(via)
	plan.append(Vector2(pb.x, pb.z))

	var elevated := graph.node_level(a) != 0 or graph.node_level(b) != 0
	var terrain := not elevated and _touches_terrain(plan)
	var dense := plan
	if elevated:
		dense = _densify(plan, RAMP_STEP)
	elif terrain:
		dense = _densify(plan, TERRAIN_STEP)

	var out := PackedVector3Array()
	if elevated:
		# Линейно по накопленной длине плана: пандус даёт постоянный уклон.
		var total := _plan_length(dense)
		var acc := 0.0
		for i in dense.size():
			if i > 0:
				acc += dense[i - 1].distance_to(dense[i])
			var t := 0.0 if total <= 0.0 else acc / total
			out.append(Vector3(dense[i].x, lerpf(pa.y, pb.y, t), dense[i].y))
		return out
	for p in dense:
		out.append(Vector3(p.x, _field.height_at(p.x, p.y), p.y))
	return out


func _touches_terrain(plan: PackedVector2Array) -> bool:
	for p in plan:
		if p.y <= CityField.TERRAIN_Z_MAX:
			return true
	return false


func _densify(plan: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([plan[0]])
	for i in range(1, plan.size()):
		var from := plan[i - 1]
		var to := plan[i]
		var n := maxi(1, ceili(from.distance_to(to) / step))
		for k in range(1, n + 1):
			out.append(from.lerp(to, float(k) / float(n)))
	return out


func _plan_length(plan: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, plan.size()):
		total += plan[i - 1].distance_to(plan[i])
	return total


## Индекс вершины серпантина, ближайшей к «Эоловой арфе».
func _gazebo_index(serp: PackedVector3Array) -> int:
	var best := 0
	var best_d := INF
	for i in serp.size():
		var d := GAZEBO_ANCHOR.distance_squared_to(Vector2(serp[i].x, serp[i].z))
		if d < best_d:
			best_d = d
			best = i
	return best


func _edge_between(a: StringName, b: StringName) -> int:
	var na := _id[a]
	var nb := _id[b]
	for e in graph.edge_count():
		var ends := graph.edge_ends(e)
		if (ends.x == na and ends.y == nb) or (ends.x == nb and ends.y == na):
			return e
	return -1


## Слепок графа для проверки детерминизма: любое расхождение в позициях,
## ярусах, ширинах или полилиниях меняет строку.
static func digest(g: CityGraph) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for n in g.node_count():
		var p := g.node_position(n)
		ctx.update(("%d|%.6f,%.6f,%.6f|%d|%d|%.4f;" % [n, p.x, p.y, p.z,
			g.node_level(n), g.node_kind(n), g.node_radius(n)]).to_utf8_buffer())
	for e in g.edge_count():
		var ends := g.edge_ends(e)
		var head := "%d|%d,%d|%.4f|%d|%d|%s|" % [e, ends.x, ends.y,
			g.edge_width(e), g.edge_kind(e), g.edge_level(e), g.edge_name(e)]
		ctx.update(head.to_utf8_buffer())
		for k in g.edge_point_count(e):
			var p := g.edge_point(e, k)
			ctx.update(("%.6f,%.6f,%.6f;" % [p.x, p.y, p.z]).to_utf8_buffer())
	return ctx.finish().hex_encode()
