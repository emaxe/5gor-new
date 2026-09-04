class_name CarMeshBuilder
extends RefCounted
## Процедурные модели машин. Порт carmodel.js с повышенной детализацией.
##
## Кузов собирается из усечённых боксов (taperedBox оригинала): днище,
## капот, багажник, «теплица» салона, крыша. Плоские нормали дают гранёный
## low-poly силуэт без единой текстуры.
##
## Для трафика возвращается ОДИН меш с вершинными цветами — одна машина,
## один draw call. Для игрока свет и стёкла выделены в отдельные меши:
## фары и стопы должны зажигаться сменой эмиссии, а не пересборкой геометрии.

const DARK := Color("#2a2a2a")
const CHROME := Color("#c8c8c8")
const GLASS := Color("#9fd8e8")
const GLASS_TINT := Color("#1c2836")
const TYRE := Color("#1a1a1c")
const PLATE := Color("#f4f4f4")
const LAMP_FRONT := Color("#fff8e0")
const LAMP_REAR := Color("#8a1414")
const LAMP_TURN := Color("#e08a20")

## Профиль силуэта. Числа — доли от габаритов кузова, порт CAR_SHAPES
## (carmodel.js:456-486).
const SHAPES := {
	&"sedan": {
		"deck_y": 0.48, "deck_h": 0.38, "belt_w": 0.98,
		"hood": 0.32, "hood_rise": -0.14, "trunk": 0.26, "trunk_rise": -0.08,
		"cab_w": 0.88, "cab_h": 0.46, "cab_y": 0.88, "cab_len": 0.48,
		"roof_w": 0.74, "roof_h": 0.06, "roof_y": 1.15, "roof_len": 0.26,
		"wheel_r": 0.31, "van": false,
	},
	&"hatch": {
		"deck_y": 0.48, "deck_h": 0.38, "belt_w": 0.98,
		"hood": 0.30, "hood_rise": -0.12, "trunk": 0.14, "trunk_rise": -0.04,
		"cab_w": 0.88, "cab_h": 0.48, "cab_y": 0.90, "cab_len": 0.54,
		"roof_w": 0.74, "roof_h": 0.06, "roof_y": 1.17, "roof_len": 0.34,
		"wheel_r": 0.30, "van": false,
	},
	&"wagon": {
		"deck_y": 0.48, "deck_h": 0.38, "belt_w": 0.98,
		"hood": 0.30, "hood_rise": -0.12, "trunk": 0.10, "trunk_rise": -0.02,
		"cab_w": 0.88, "cab_h": 0.48, "cab_y": 0.90, "cab_len": 0.58,
		"roof_w": 0.76, "roof_h": 0.06, "roof_y": 1.18, "roof_len": 0.44,
		"wheel_r": 0.31, "van": false, "rack": true,
	},
	&"coupe": {
		"deck_y": 0.44, "deck_h": 0.36, "belt_w": 0.98,
		"hood": 0.36, "hood_rise": -0.16, "trunk": 0.24, "trunk_rise": -0.10,
		"cab_w": 0.86, "cab_h": 0.40, "cab_y": 0.82, "cab_len": 0.42,
		"roof_w": 0.70, "roof_h": 0.05, "roof_y": 1.05, "roof_len": 0.20,
		"wheel_r": 0.31, "van": false,
	},
	&"suv": {
		"deck_y": 0.58, "deck_h": 0.46, "belt_w": 0.98,
		"hood": 0.28, "hood_rise": -0.08, "trunk": 0.14, "trunk_rise": -0.02,
		"cab_w": 0.90, "cab_h": 0.52, "cab_y": 1.08, "cab_len": 0.56,
		"roof_w": 0.80, "roof_h": 0.07, "roof_y": 1.38, "roof_len": 0.42,
		"wheel_r": 0.36, "van": false, "rack": true,
	},
	&"retro": {
		"deck_y": 0.50, "deck_h": 0.40, "belt_w": 0.96,
		"hood": 0.32, "hood_rise": -0.06, "trunk": 0.26, "trunk_rise": -0.04,
		"cab_w": 0.88, "cab_h": 0.50, "cab_y": 0.94, "cab_len": 0.48,
		"roof_w": 0.76, "roof_h": 0.07, "roof_y": 1.22, "roof_len": 0.28,
		"wheel_r": 0.31, "van": false,
	},
	&"premium": {
		"deck_y": 0.48, "deck_h": 0.38, "belt_w": 0.98,
		"hood": 0.34, "hood_rise": -0.14, "trunk": 0.26, "trunk_rise": -0.08,
		"cab_w": 0.88, "cab_h": 0.44, "cab_y": 0.88, "cab_len": 0.48,
		"roof_w": 0.74, "roof_h": 0.06, "roof_y": 1.15, "roof_len": 0.26,
		"wheel_r": 0.32, "van": false,
	},
	&"van": {
		"deck_y": 0.52, "deck_h": 0.40, "cab_y": 1.15, "roof_y": 1.70,
		"wheel_r": 0.34, "van": true, "type": "van",
	},
	&"bus": {
		"deck_y": 0.58, "deck_h": 0.44, "cab_y": 1.40, "roof_y": 2.15,
		"wheel_r": 0.38, "van": true, "type": "bus",
	},
	&"pickup": {
		"deck_y": 0.54, "deck_h": 0.42, "cab_y": 1.08, "roof_y": 1.42,
		"wheel_r": 0.34, "van": true, "type": "pickup",
	},
	&"truck": {
		"deck_y": 0.68, "deck_h": 0.48, "cab_y": 1.35, "roof_y": 2.05,
		"wheel_r": 0.42, "van": true, "type": "truck",
	},
}


## Описание конкретной машины.
class Spec extends RefCounted:
	var silhouette: StringName = &"sedan"
	var width := 1.82
	var length := 4.30
	var body_color := Color("#f2c12e")
	var rim_style: StringName = &"spoke"
	var rim_color := Color("#c4c6ca")
	var body_kit: StringName = &"stock"
	var spoiler := false
	## none | stripe | checker | racing (TuningCatalog.decal_ids).
	var decal: StringName = &"none"
	## Ливрея такси: шашечки по борту и плафон на крыше.
	var taxi_livery := false
	## Синяя полоса полиции.
	var police_livery := false
	## Мигалка: "" | "police" | "ambulance"
	var beacon: StringName = &""


static func shape_of(silhouette: StringName) -> Dictionary:
	return SHAPES.get(silhouette, SHAPES[&"sedan"])


## Верх кузова. У легковых это крыша, у автобусов/фургонов — верх крыши.
static func roof_height(s: Dictionary) -> float:
	return float(s.get("roof_y", 1.20))


## Кузов целиком одним мешем — вариант для трафика: одна машина, один draw call.
##
## include_beacon=false опускает статичный маячок: у полиции и скорой в
## трафике он мигает противофазой (TrafficLayer ставит два отдельных
## меша поверх кузова и переключает их видимость), а не горит постоянно.
static func build_merged(spec: Spec, include_beacon: bool = true) -> ArrayMesh:
	var b := MeshBuilder.new()
	_add_body(b, spec)
	_add_details(b, spec, include_beacon)
	_add_wheels(b, spec)
	_add_lights(b, spec, true)
	return b.commit()


## Кузов без света и колёс — вариант для машины игрока.
static func build_body(spec: Spec) -> ArrayMesh:
	var b := MeshBuilder.new()
	_add_body(b, spec)
	_add_details(b, spec, true)
	return b.commit()


static func build_wheel(spec: Spec) -> ArrayMesh:
	var s := shape_of(spec.silhouette)
	var r: float = s["wheel_r"]
	var b := MeshBuilder.new()
	var across := Basis(Vector3.FORWARD, PI * 0.5)

	# 1. Резина шины
	b.cylinder(Vector3.ZERO, r, r, 0.20, TYRE, 16, across)
	b.cylinder(Vector3.ZERO, r * 0.94, r * 0.94, 0.22, Color("#141416"), 14, across)

	# 2. Тормозной диск и суппорт
	b.cylinder(Vector3.ZERO, r * 0.52, r * 0.52, 0.08, Color("#444850"), 8, across)
	b.box(Vector3(0.0, r * 0.28, 0.0), Vector3(0.12, 0.09, 0.07), Color("#cc1824"))

	# 3. Обод и спицы (на обе стороны)
	for side_x: float in [-1.0, 1.0]:
		# Внутренняя полость диска (утоплена)
		b.cylinder(Vector3(side_x * 0.06, 0.0, 0.0), r * 0.64, r * 0.64, 0.04,
			Color("#121416"), 12, across)
		# Внешний металлический кант обода
		b.cylinder(Vector3(side_x * 0.09, 0.0, 0.0), r * 0.72, r * 0.72, 0.02,
			spec.rim_color, 12, across)

		match spec.rim_style:
			&"spoke":
				# Спицы
				for k in 5:
					var a := TAU * k / 5.0
					var rot := Basis(Vector3.RIGHT, a)
					var spoke_center := Vector3(side_x * 0.08, 0.0, 0.0) + rot * Vector3(0.0, r * 0.38, 0.0)
					b.box(spoke_center, Vector3(0.02, r * 0.36, r * 0.08), spec.rim_color, rot)
				# Центральный колпачок ступицы
				b.cylinder(Vector3(side_x * 0.095, 0.0, 0.0), r * 0.22, r * 0.22, 0.02,
					CHROME, 8, across)
			&"chrome":
				b.cylinder(Vector3(side_x * 0.085, 0.0, 0.0), r * 0.60, r * 0.60, 0.025,
					CHROME, 12, across)
				b.cylinder(Vector3(side_x * 0.095, 0.0, 0.0), r * 0.20, r * 0.20, 0.02,
					Color("#16181b"), 6, across)
			_:
				for k in 8:
					var a := TAU * k / 8.0
					var rot := Basis(Vector3.RIGHT, a)
					var spoke_center := Vector3(side_x * 0.08, 0.0, 0.0) + rot * Vector3(0.0, r * 0.38, 0.0)
					b.box(spoke_center, Vector3(0.02, r * 0.36, r * 0.06), spec.rim_color, rot)
				b.cylinder(Vector3(side_x * 0.095, 0.0, 0.0), r * 0.22, r * 0.22, 0.02,
					CHROME, 8, across)

	return b.commit()


## Фары, стопы и поворотники — отдельными мешами для машины игрока.
static func build_lamps(spec: Spec, rear: bool) -> ArrayMesh:
	var b := MeshBuilder.new()
	var hw := spec.width * 0.5
	var hl := spec.length * 0.5
	var s := shape_of(spec.silhouette)
	var y: float = s["deck_y"] + s["deck_h"] * 0.12

	if rear:
		var z := -hl - 0.012
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * hw * 0.68, y, z), Vector3(0.36, 0.16, 0.025), DARK)
			b.box(Vector3(sx * hw * 0.66, y, z - 0.012), Vector3(0.20, 0.13, 0.025), LAMP_REAR)
			b.box(Vector3(sx * hw * 0.52, y, z - 0.012), Vector3(0.08, 0.11, 0.025), Color("#f4f4f8"))
			b.box(Vector3(sx * hw * 0.82, y, z - 0.012), Vector3(0.08, 0.13, 0.025), LAMP_TURN)
	else:
		var z := hl + 0.012
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * hw * 0.68, y, z), Vector3(0.36, 0.16, 0.025), DARK)
			b.box(Vector3(sx * hw * 0.64, y, z + 0.012), Vector3(0.22, 0.13, 0.025), LAMP_FRONT)
			b.cylinder(Vector3(sx * hw * 0.64, y, z + 0.025), 0.045, 0.045, 0.015, Color.WHITE, 8,
				Basis(Vector3.RIGHT, PI * 0.5))
			b.box(Vector3(sx * hw * 0.82, y, z + 0.012), Vector3(0.08, 0.13, 0.025), LAMP_TURN)

	return b.commit()


# --- Кузов ------------------------------------------------------------------

static func _add_body(b: MeshBuilder, spec: Spec) -> void:
	var s := shape_of(spec.silhouette)
	if s.get("van", false):
		var vtype: String = s.get("type", "van")
		match vtype:
			"bus":
				_add_bus_body(b, spec, s)
			"pickup":
				_add_pickup_body(b, spec, s)
			"truck":
				_add_truck_body(b, spec, s)
			_:
				_add_van_body(b, spec, s)
	else:
		_add_car_body(b, spec, s)


## Легковой силуэт: нижние пороги, мускулистые колесные арки,
## капот с выштамповкой, салон со стойками и рельефная крыша.
static func _add_car_body(b: MeshBuilder, spec: Spec, s: Dictionary) -> void:
	var w := spec.width
	var l := spec.length
	var hw := w * 0.5
	var hl := l * 0.5
	var deck_y: float = s["deck_y"]
	var deck_h: float = s["deck_h"]
	var deck_top := deck_y + deck_h * 0.5
	var wheel_r: float = s["wheel_r"]

	# Пороги и днище кузова
	b.box(Vector3(0.0, deck_y - deck_h * 0.44, 0.0),
		Vector3(w * 0.94, deck_h * 0.16, l * 0.95), DARK)

	# Основной объем поясной линии
	b.tapered_box(Vector3(0.0, deck_y, 0.0), Vector3(w, deck_h, l),
		spec.body_color, Vector2(s["belt_w"], 1.0))

	# Выштамповки колесных арок (передние и задние)
	for sz: float in [-1.0, 1.0]:
		var arch_z: float = (hl - wheel_r - 0.35) if sz > 0.0 else (-hl + wheel_r + 0.38)
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * (hw + 0.015), deck_y - 0.04, arch_z),
				Vector3(0.04, deck_h * 0.88, wheel_r * 2.3), spec.body_color)
			b.cylinder(Vector3(sx * (hw + 0.01), wheel_r, arch_z),
				wheel_r * 1.15, wheel_r * 1.15, 0.035, DARK, 10,
				Basis(Vector3.FORWARD, PI * 0.5))

	# Капот с наклоном
	var hood_len: float = l * s["hood"]
	var hood_z := hl - hood_len * 0.5
	b.tapered_box(Vector3(0.0, deck_top + 0.04, hood_z),
		Vector3(w * 0.94, 0.10, hood_len), spec.body_color,
		Vector2(0.92, 1.0), 0.0, s["hood_rise"], 0.0)

	# Багажник / задняя часть
	var trunk_len: float = l * s["trunk"]
	var trunk_z := -hl + trunk_len * 0.5
	b.tapered_box(Vector3(0.0, deck_top + 0.03, trunk_z),
		Vector3(w * 0.94, 0.08, trunk_len), spec.body_color,
		Vector2(0.94, 1.0), 0.0, s["trunk_rise"], 0.0)

	# Остекление салона (теплица)
	var cab_len: float = l * s["cab_len"]
	var cab_w: float = w * s["cab_w"]
	var cab_h: float = s["cab_h"]
	var cab_y: float = s["cab_y"]
	var cab_z: float = (hood_z - hood_len * 0.5 + trunk_z + trunk_len * 0.5) * 0.5
	b.tapered_box(Vector3(0.0, cab_y, cab_z), Vector3(cab_w, cab_h, cab_len),
		GLASS, Vector2(s["roof_w"] / s["cab_w"], 0.88), 0.0, -0.06, 0.0)

	# Рельефная крыша
	var roof_len: float = l * s["roof_len"]
	var roof_w: float = w * s["roof_w"]
	var roof_y: float = s["roof_y"]
	b.tapered_box(Vector3(0.0, roof_y, cab_z), Vector3(roof_w, s["roof_h"], roof_len),
		spec.body_color, Vector2(0.96, 0.98))

	# Черные центральные стойки B
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * w * s["cab_w"] * 0.49, cab_y, cab_z + cab_len * 0.03),
			Vector3(0.045, cab_h * 0.96, 0.07), DARK)
		b.box(Vector3(sx * w * s["cab_w"] * 0.495, deck_top + 0.012, cab_z),
			Vector3(0.035, 0.025, cab_len * 0.96), CHROME if spec.rim_style == &"chrome" else DARK)

	# Дворники на лобовом стекле
	b.box(Vector3(-0.16, deck_top + 0.025, cab_z + cab_len * 0.48),
		Vector3(0.34, 0.018, 0.018), DARK, Basis(Vector3.FORWARD, 0.16))
	b.box(Vector3(0.18, deck_top + 0.025, cab_z + cab_len * 0.48),
		Vector3(0.34, 0.018, 0.018), DARK, Basis(Vector3.FORWARD, 0.16))

	if spec.body_kit == &"sport":
		# Спортивный обвес: передний сплиттер, задний диффузор, боковые пороги.
		b.box(Vector3(0.0, deck_y - deck_h * 0.52, hl - 0.05),
			Vector3(w * 0.92, 0.05, 0.10), DARK)
		b.box(Vector3(0.0, deck_y - deck_h * 0.52, -hl + 0.06),
			Vector3(w * 0.88, 0.05, 0.12), DARK)
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * (hw - 0.01), deck_y - deck_h * 0.5, 0.0),
				Vector3(0.05, 0.05, l * 0.68), DARK)


## Городской автобус (ПАЗ / курортный автолайн): цельный кузов,
## двухсекционное лобовое стекло, табло маршрута, пассажирская складная дверь,
## 5 больших окон, люки на крыше.
static func _add_bus_body(b: MeshBuilder, spec: Spec, s: Dictionary) -> void:
	var w := spec.width
	var l := spec.length
	var hl := l * 0.5
	var hw := w * 0.5

	# 1. Нижняя темная юбка кузова
	b.box(Vector3(0.0, 0.46, 0.0), Vector3(w * 0.98, 0.26, l * 0.99), Color("#2b3038"))

	# 2. Основной монолитный кузов автобуса
	b.tapered_box(Vector3(0.0, 1.35, 0.0), Vector3(w, 1.55, l),
		spec.body_color, Vector2(0.96, 0.98))

	# 3. Скругленная обтекаемая крыша
	b.tapered_box(Vector3(0.0, 2.16, 0.0), Vector3(w * 0.94, 0.14, l * 0.98),
		spec.body_color, Vector2(0.92, 0.96))

	# 4. Вентиляционные люки на крыше
	for zh: float in [-2.4, 0.0, 2.4]:
		b.box(Vector3(0.0, 2.26, zh), Vector3(0.75, 0.06, 0.75), Color("#dddddd"))
		b.box(Vector3(0.0, 2.27, zh), Vector3(0.68, 0.05, 0.68), Color("#bbbbbb"))

	# 5. Передняя маска
	# Огромное 2-секционное лобовое стекло
	b.box(Vector3(0.0, 1.48, hl - 0.02), Vector3(w * 0.88, 0.82, 0.05), GLASS)
	# Резиновый вертикальный разделитель
	b.box(Vector3(0.0, 1.48, hl), Vector3(0.04, 0.84, 0.06), DARK)
	# Электронное табло маршрута над лобовым стеклом
	b.box(Vector3(0.0, 1.98, hl - 0.04), Vector3(w * 0.70, 0.18, 0.05), Color("#111620"))
	b.box(Vector3(0.0, 1.98, hl - 0.01), Vector3(w * 0.64, 0.08, 0.02), Color("#f5a623"))
	# Стеклоочистители
	for sx: float in [-0.45, 0.45]:
		b.box(Vector3(sx, 1.15, hl + 0.01), Vector3(0.40, 0.02, 0.02), DARK, Basis(Vector3.FORWARD, 0.2))

	# 6. Пассажирские боковые окна (5 рядов)
	var rows := 5
	var win_span := l * 0.68
	var win_step := win_span / rows
	for k in rows:
		var z := 0.2 + (k - (rows - 1) * 0.5) * win_step
		for sx: float in [-1.0, 1.0]:
			# На правом борту спереди — пассажирская складная дверь
			if sx > 0.0 and k == rows - 1:
				continue
			b.box(Vector3(sx * (hw + 0.005), 1.52, z),
				Vector3(0.03, 0.68, win_step * 0.82), GLASS)
			b.box(Vector3(sx * (hw + 0.008), 1.76, z),
				Vector3(0.025, 0.02, win_step * 0.80), DARK) # планка форточки

	# 7. Пассажирская дверь справа (двухстворчатая гармошка)
	var door_z := hl - 1.4
	b.box(Vector3(hw + 0.005, 1.12, door_z), Vector3(0.03, 1.48, 0.88), Color("#242830"))
	b.box(Vector3(hw + 0.01, 1.35, door_z - 0.22), Vector3(0.025, 0.80, 0.32), GLASS)
	b.box(Vector3(hw + 0.01, 1.35, door_z + 0.22), Vector3(0.025, 0.80, 0.32), GLASS)

	# 8. Заднее стекло
	b.box(Vector3(0.0, 1.55, -hl + 0.02), Vector3(w * 0.82, 0.64, 0.04), GLASS)


## Микроавтобус / ГАЗель / Маршрутка: полукапотная компоновка,
## покатый капот, высокое наклонное лобовое стекло, сдвижная дверь и окна.
static func _add_van_body(b: MeshBuilder, spec: Spec, s: Dictionary) -> void:
	var w := spec.width
	var l := spec.length
	var hl := l * 0.5
	var hw := w * 0.5

	# 1. Нижняя юбка
	b.box(Vector3(0.0, 0.44, 0.0), Vector3(w * 0.96, 0.22, l * 0.98), DARK)

	# 2. Покатый передний капот (aerodynamic nose)
	var hood_len := 1.25
	var hood_z := hl - hood_len * 0.5
	b.tapered_box(Vector3(0.0, 0.72, hood_z), Vector3(w * 0.94, 0.36, hood_len),
		spec.body_color, Vector2(0.90, 1.0), 0.0, -0.08, 0.0)

	# 3. Основной высокий салон / грузовой кузов
	var cabin_len := l - 1.15
	var cabin_z := hl - hood_len - cabin_len * 0.5 + 0.1
	b.tapered_box(Vector3(0.0, 1.22, cabin_z), Vector3(w * 0.98, 1.12, cabin_len),
		spec.body_color, Vector2(0.92, 0.98))

	# 4. Высокая аэродинамическая крыша
	b.tapered_box(Vector3(0.0, 1.82, cabin_z + 0.1), Vector3(w * 0.90, 0.16, cabin_len - 0.2),
		spec.body_color, Vector2(0.88, 0.96))

	# 5. Большое наклонное лобовое стекло
	b.box(Vector3(0.0, 1.26, hl - 1.18), Vector3(w * 0.86, 0.58, 0.05),
		GLASS, Basis(Vector3.RIGHT, -0.36))

	# 6. Боковые окна кабины
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * (hw * 0.96), 1.25, hl - 1.65),
			Vector3(0.04, 0.44, 0.65), GLASS)

	# 7. Пассажирские окна салона (3 секции)
	var rows := 3
	var win_span := cabin_len * 0.60
	var win_step := win_span / rows
	for k in rows:
		var z := -0.3 + (k - (rows - 1) * 0.5) * win_step
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * (hw + 0.004), 1.34, z),
				Vector3(0.03, 0.52, win_step * 0.84), GLASS)

	# 8. Направляющий желоб сдвижной двери на правом борту
	b.box(Vector3(hw + 0.008, 0.95, -0.2), Vector3(0.015, 0.025, cabin_len * 0.65), DARK)

	# 9. Задние распашные двери со стеклами
	b.box(Vector3(0.0, 1.18, -hl + 0.02), Vector3(0.02, 1.10, 0.04), DARK) # шов дверей
	for sx: float in [-0.45, 0.45]:
		b.box(Vector3(sx, 1.40, -hl + 0.025), Vector3(0.60, 0.46, 0.03), GLASS)


## Пикап с кабиной и открытым грузовым кузовом.
static func _add_pickup_body(b: MeshBuilder, spec: Spec, _s: Dictionary) -> void:
	var w := spec.width
	var l := spec.length
	var hl := l * 0.5
	var hw := w * 0.5

	# Кабина
	var cab_len := l * 0.52
	var cab_z := hl - cab_len * 0.5
	b.tapered_box(Vector3(0.0, 0.68, 0.0), Vector3(w, 0.42, l), spec.body_color, Vector2(0.96, 1.0))
	b.tapered_box(Vector3(0.0, 1.15, cab_z), Vector3(w * 0.90, 0.58, cab_len),
		spec.body_color, Vector2(0.85, 0.92))
	# Лобовое и заднее стекла
	b.box(Vector3(0.0, 1.18, cab_z + cab_len * 0.46), Vector3(w * 0.82, 0.44, 0.05),
		GLASS, Basis(Vector3.RIGHT, -0.30))
	b.box(Vector3(0.0, 1.18, cab_z - cab_len * 0.46), Vector3(w * 0.78, 0.38, 0.05), GLASS)

	# Открытый грузовой кузов
	var bed_len := l * 0.44
	var bed_z := -hl + bed_len * 0.5
	var bed_h := 0.42
	var bed_y := 0.89 + bed_h * 0.5
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * (hw - 0.04), bed_y, bed_z), Vector3(0.08, bed_h, bed_len), spec.body_color)
	b.box(Vector3(0.0, bed_y, -hl + 0.04), Vector3(w * 0.92, bed_h, 0.08), spec.body_color)

	# Хромированная дуга безопасности
	b.cylinder(Vector3(0.0, bed_y + bed_h * 0.6, bed_z + bed_len * 0.44),
		0.04, 0.04, w * 0.86, CHROME, 8, Basis(Vector3.FORWARD, PI * 0.5))


## Грузовик с кабиной и закрытым изотермическим фургоном (будкой).
static func _add_truck_body(b: MeshBuilder, spec: Spec, _s: Dictionary) -> void:
	var w := spec.width
	var l := spec.length
	var hl := l * 0.5
	var hw := w * 0.5

	# Рама шасси
	b.box(Vector3(0.0, 0.48, 0.0), Vector3(w * 0.80, 0.24, l * 0.98), DARK)
	# Топливный бак сбоку
	b.cylinder(Vector3(-hw * 0.88, 0.52, -0.4), 0.18, 0.18, 1.10, CHROME, 10,
		Basis(Vector3.FORWARD, PI * 0.5))

	# Кабина грузовика
	var cab_len := 2.0
	var cab_z := hl - cab_len * 0.5
	b.tapered_box(Vector3(0.0, 1.25, cab_z), Vector3(w * 0.95, 1.10, cab_len),
		spec.body_color, Vector2(0.92, 0.98))
	b.box(Vector3(0.0, 1.42, hl - 0.20), Vector3(w * 0.88, 0.62, 0.05),
		GLASS, Basis(Vector3.RIGHT, -0.20))

	# Грузовая будка
	var box_len := l - 2.3
	var box_z := -hl + box_len * 0.5 + 0.1
	b.box(Vector3(0.0, 1.62, box_z), Vector3(w * 1.02, 1.70, box_len), Color("#e4e6ea"))
	# Алюминиевые уголки фургона
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * (hw * 1.02), 1.62, box_z), Vector3(0.04, 1.72, box_len + 0.02), CHROME)
		b.box(Vector3(sx * (hw * 1.02), 2.48, box_z), Vector3(0.06, 0.06, box_len + 0.02), CHROME)


# --- Детали -----------------------------------------------------------------

static func _add_details(b: MeshBuilder, spec: Spec, include_beacon: bool = true) -> void:
	var s := shape_of(spec.silhouette)
	var w := spec.width
	var l := spec.length
	var hw := w * 0.5
	var hl := l * 0.5
	var deck_y: float = s["deck_y"]
	var deck_h: float = s["deck_h"]

	# Бамперы
	b.box(Vector3(0.0, deck_y - deck_h * 0.38, hl - 0.02),
		Vector3(w * 0.96, 0.16, 0.14), DARK)
	b.box(Vector3(0.0, deck_y - deck_h * 0.38, -hl + 0.02),
		Vector3(w * 0.96, 0.16, 0.14), DARK)

	# Решётка радиатора с хромированной рамкой и шильдиком
	var grille_col := CHROME if spec.rim_style == &"chrome" else DARK
	b.box(Vector3(0.0, deck_y + 0.02, hl + 0.012), Vector3(w * 0.44, 0.18, 0.03), grille_col)
	b.box(Vector3(0.0, deck_y + 0.02, hl + 0.02), Vector3(w * 0.40, 0.14, 0.025), Color("#121418"))
	b.cylinder(Vector3(0.0, deck_y + 0.02, hl + 0.035), 0.035, 0.035, 0.012, CHROME, 6,
		Basis(Vector3.RIGHT, PI * 0.5))

	# Номерные знаки с черной рамкой и регионом 26
	for sz: float in [-1.0, 1.0]:
		b.box(Vector3(0.0, deck_y - 0.18, sz * (hl + 0.025)),
			Vector3(0.48, 0.13, 0.015), DARK)
		b.box(Vector3(0.0, deck_y - 0.18, sz * (hl + 0.032)),
			Vector3(0.44, 0.10, 0.018), PLATE)

	# Зеркала заднего вида. У легковых силуэтов cab_y — центр «теплицы»
	# салона (порт carmodel.js: mirror.y = cabY - cabH*0.3), а не низ окна —
	# без сдвига вниз зеркало повисало в воздухе над капотом, оторванное от
	# кузова. У van/bus/pickup/truck отдельного cab_h нет (кабина строится
	# захардкоженными числами в _add_van_body и т.п.), их s["cab_y"] уже сам
	# по себе лежит у низа кабины — сдвиг там не нужен, поэтому cab_h = 0.
	var mirror_z: float = hl * (0.36 if not s.get("van", false) else 0.42)
	var mirror_y: float = float(s["cab_y"]) - float(s.get("cab_h", 0.0)) * 0.3
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * (hw + 0.03), mirror_y - 0.02, mirror_z),
			Vector3(0.06, 0.04, 0.06), DARK)
		b.box(Vector3(sx * (hw + 0.09), mirror_y, mirror_z),
			Vector3(0.12, 0.09, 0.14), spec.body_color)
		b.box(Vector3(sx * (hw + 0.09), mirror_y, mirror_z - 0.072),
			Vector3(0.10, 0.07, 0.01), Color("#bcd0e0"))

	# Боковой защитный молдинг (для не-автобусов)
	if s.get("type", "") != "bus":
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * (hw - 0.015), deck_y + deck_h * 0.14, 0.0),
				Vector3(0.025, 0.035, l * 0.68), DARK)

	# Дверные ручки под хром
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.box(Vector3(sx * (hw - 0.015), deck_y + deck_h * 0.28, sz * l * 0.14),
				Vector3(0.03, 0.035, 0.12), CHROME)

	# Двойные выхлопные патрубки
	for sx: float in [-0.28, -0.20]:
		b.cylinder(Vector3(sx, deck_y - deck_h * 0.40, -hl - 0.04), 0.03, 0.03, 0.10,
			CHROME, 8, Basis(Vector3.RIGHT, PI * 0.5))
		b.cylinder(Vector3(sx, deck_y - deck_h * 0.40, -hl - 0.095), 0.02, 0.02, 0.02,
			DARK, 6, Basis(Vector3.RIGHT, PI * 0.5))

	if spec.spoiler:
		var sp_y := deck_y + deck_h * 0.5 + 0.12
		var sp_z := -hl + 0.14
		for sx: float in [-0.55, 0.55]:
			b.box(Vector3(sx, sp_y - 0.06, sp_z), Vector3(0.04, 0.12, 0.06), DARK)
		b.box(Vector3(0.0, sp_y, sp_z), Vector3(w * 0.88, 0.03, 0.18), spec.body_color)

	if spec.taxi_livery:
		_add_taxi_livery(b, spec, s)

	if spec.police_livery:
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * (hw + 0.005), deck_y + 0.02, 0.0),
				Vector3(0.02, 0.18, l * 0.68), Color("#183d96"))
			b.box(Vector3(sx * (hw + 0.008), deck_y + 0.02, 0.0),
				Vector3(0.02, 0.035, l * 0.55), Color.WHITE)

	if spec.beacon != &"" and include_beacon:
		_add_beacon(b, spec, s)

	_add_decal(b, spec, s)


## Высота верхней поверхности кузова в точке z: капот → (рампа по лобовому) →
## крыша → (рампа по заднему) → багажник. Только для легковых силуэтов —
## у них есть все нужные ключи в SHAPES (hood/trunk/roof_len/*_rise); у
## van/bus/pickup/truck кузов строится захардкоженными числами в отдельных
## _add_*_body(), общего контура нет. Опора для _add_decal(): раньше декаль
## рисовалась одной плоскостью на высоте крыши на всю длину — над капотом
## и багажником, которые заметно ниже крыши, она повисала в воздухе
## (порядка 0.3-0.5 м зазора, см. отчёт по капоту такси).
static func _decal_surface_y(s: Dictionary, l: float, z: float) -> float:
	var deck_top: float = float(s["deck_y"]) + float(s["deck_h"]) * 0.5
	var hl := l * 0.5
	var hood_len: float = l * float(s["hood"])
	var trunk_len: float = l * float(s["trunk"])
	var roof_len: float = l * float(s["roof_len"])
	var hood_back := hl - hood_len
	var trunk_front := -hl + trunk_len
	var cab_z := (hood_back + trunk_front) * 0.5
	var roof_back := cab_z - roof_len * 0.5
	var roof_front := cab_z + roof_len * 0.5
	var roof_h: float = float(s["roof_y"]) + float(s["roof_h"]) * 0.5
	# Высоты концов капота/багажника — те же формулы, что в _add_car_body:
	# верх усечённого бокса = center.y + half_height + rise на нужном конце.
	var trunk_back_h := deck_top + 0.07
	var trunk_front_h := trunk_back_h + float(s["trunk_rise"])
	var hood_back_h := deck_top + 0.09
	var hood_front_h := hood_back_h + float(s["hood_rise"])

	# Опорные точки контура сзади наперёд; между ними — прямая рампа (в т.ч.
	# через лобовое/заднее стекло, где сплошной обшивки нет).
	var points: Array = [
		[-hl, trunk_back_h], [trunk_front, trunk_front_h],
		[roof_back, roof_h], [roof_front, roof_h],
		[hood_back, hood_back_h], [hl, hood_front_h],
	]
	for i in points.size() - 1:
		var a: Array = points[i]
		var seg_b: Array = points[i + 1]
		if z <= float(seg_b[0]) or i == points.size() - 2:
			var span: float = maxf(float(seg_b[0]) - float(a[0]), 0.0001)
			var t := clampf((z - float(a[0])) / span, 0.0, 1.0)
			return lerpf(float(a[1]), float(seg_b[1]), t)
	return hood_front_h


## Режет длинную полосу-декаль на короткие сегменты вдоль z и кладёт каждый
## на актуальную высоту кузова (_decal_surface_y) — иначе одна плоская
## коробка на всю длину парит там, где кузов ниже крыши (капот, багажник).
static func _add_decal_strip(b: MeshBuilder, s: Dictionary, l: float,
		x: float, width: float, span: float, color: Color) -> void:
	const SEGMENTS := 10
	var seg_len := span / SEGMENTS
	for k in SEGMENTS:
		var z := span * 0.5 - seg_len * (k + 0.5)
		b.box(Vector3(x, _decal_surface_y(s, l, z) + 0.006, z),
			# Небольшой нахлёст по Z, чтобы соседние сегменты на разной
			# высоте не оставляли видимую щель на стыке.
			Vector3(width, 0.008, seg_len * 1.05), color)


## Декаль тюнинга — рисуется по верху кузова (капот-крыша-багажник), чтобы не
## конфликтовать с шашечками такси на бортах (_add_taxi_livery). Цвет —
## контрастный к body_color, чтобы декаль было видно на любой окраске.
static func _add_decal(b: MeshBuilder, spec: Spec, s: Dictionary) -> void:
	if spec.decal == &"none":
		return
	var w := spec.width
	var l := spec.length
	var hl := l * 0.5
	var accent := Color.BLACK if spec.body_color.get_luminance() > 0.5 else Color.WHITE
	# van/bus/pickup/truck строят кузов без общего контура (см. комментарий
	# у _decal_surface_y) — оставляем им прежнюю плоскость на высоте крыши,
	# а не падаем на отсутствующих ключах SHAPES.
	var is_van: bool = s.get("van", false)
	var flat_y: float = roof_height(s) + 0.006

	match spec.decal:
		&"stripe":
			if is_van:
				b.box(Vector3(0.0, flat_y, 0.0), Vector3(w * 0.22, 0.008, l * 0.86), accent)
			else:
				_add_decal_strip(b, s, l, 0.0, w * 0.22, l * 0.86, accent)
		&"racing":
			for sx: float in [-0.16, 0.16]:
				if is_van:
					b.box(Vector3(sx * w, flat_y, 0.0), Vector3(w * 0.09, 0.008, l * 0.86), accent)
				else:
					_add_decal_strip(b, s, l, sx * w, w * 0.09, l * 0.86, accent)
		&"checker":
			var hood_len: float = float(s.get("hood", 0.3)) * l
			var cells := 6
			var cell_len := hood_len * 0.86 / cells
			for k in cells:
				if k % 2 == 1:
					continue
				var z := hl - hood_len * 0.07 - k * cell_len - cell_len * 0.5
				var y := flat_y if is_van else _decal_surface_y(s, l, z) + 0.006
				b.box(Vector3(0.0, y, z), Vector3(w * 0.5, 0.006, cell_len), accent)


## Фирменный световой короб «ТАКСИ» и шашечки на бортах.
static func _add_taxi_livery(b: MeshBuilder, spec: Spec, s: Dictionary) -> void:
	var hw := spec.width * 0.5
	var l := spec.length
	var deck_y: float = s["deck_y"]
	var cells := 12
	# Контрастный пояс шашечек по борту
	for sx: float in [-1.0, 1.0]:
		for k in cells:
			if k % 2 == 1:
				continue
			var z := (k - (cells - 1) * 0.5) * (l * 0.64 / cells)
			b.box(Vector3(sx * (hw + 0.006), deck_y + 0.02, z),
				Vector3(0.02, 0.07, l * 0.64 / cells), Color("#141414"))

	# Аэродинамический световой короб "ТАКСИ" на крыше
	var sign_y := roof_height(s) + 0.11
	for sx: float in [-0.20, 0.20]:
		b.cylinder(Vector3(sx, sign_y - 0.07, 0.05), 0.035, 0.035, 0.03, DARK, 6)

	b.tapered_box(Vector3(0.0, sign_y, 0.05), Vector3(0.58, 0.14, 0.20),
		Color("#f8b818"), Vector2(0.85, 0.85))
	b.box(Vector3(0.0, sign_y, 0.152), Vector3(0.44, 0.035, 0.01), DARK)
	b.box(Vector3(0.0, sign_y, -0.052), Vector3(0.44, 0.035, 0.01), DARK)


## Аэродинамическая светосигнальная балка полиции/скорой.
static func _add_beacon(b: MeshBuilder, spec: Spec, s: Dictionary) -> void:
	var y := roof_height(s) + 0.04
	b.box(Vector3(0.0, y, 0.0), Vector3(spec.width * 0.64, 0.025, 0.10), DARK)
	b.box(Vector3(0.0, y + 0.05, 0.0), Vector3(0.16, 0.08, 0.16), CHROME)
	_add_beacon_half(b, spec, s, true)
	_add_beacon_half(b, spec, s, false)


static func _add_beacon_half(b: MeshBuilder, spec: Spec, s: Dictionary,
		red: bool) -> void:
	var y := roof_height(s) + 0.09
	var color := Color("#e01818") if red else Color("#1850e0")
	var sx := -0.22 if red else 0.22
	b.tapered_box(Vector3(sx, y, 0.0), Vector3(0.32, 0.10, 0.18), color, Vector2(0.9, 0.9))
	b.box(Vector3(sx, y, 0.0), Vector3(0.16, 0.06, 0.10), Color.WHITE)


static func build_beacon_lamp(spec: Spec, red: bool) -> ArrayMesh:
	var b := MeshBuilder.new()
	_add_beacon_half(b, spec, shape_of(spec.silhouette), red)
	return b.commit()


static func _add_wheels(b: MeshBuilder, spec: Spec) -> void:
	var s := shape_of(spec.silhouette)
	var r: float = s["wheel_r"]
	var hw := spec.width * 0.5
	var hl := spec.length * 0.5
	var across := Basis(Vector3.FORWARD, PI * 0.5)

	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var arch_z: float = (hl - r - 0.35) if sz > 0.0 else (-hl + r + 0.38)
			var p := Vector3(sx * (hw - 0.08), r, arch_z)

			# 1. Резина шины
			b.cylinder(p, r, r, 0.20, TYRE, 16, across)
			b.cylinder(p, r * 0.94, r * 0.94, 0.22, Color("#141416"), 14, across)

			# 2. Внутренняя полость диска (утоплена)
			var rim_inner := p + Vector3(sx * 0.06, 0.0, 0.0)
			b.cylinder(rim_inner, r * 0.64, r * 0.64, 0.04, Color("#121416"), 12, across)

			# 3. Внешний металлический кант обода
			var rim_p := p + Vector3(sx * 0.09, 0.0, 0.0)
			b.cylinder(rim_p, r * 0.72, r * 0.72, 0.02, spec.rim_color, 12, across)

			# 4. Спицы
			for k in 5:
				var a := TAU * k / 5.0
				var rot := Basis(Vector3.RIGHT, a)
				var spoke_center := p + Vector3(sx * 0.08, 0.0, 0.0) + rot * Vector3(0.0, r * 0.38, 0.0)
				b.box(spoke_center, Vector3(0.02, r * 0.36, r * 0.08), spec.rim_color, rot)

			# 5. Центральный колпачок ступицы
			b.cylinder(p + Vector3(sx * 0.095, 0.0, 0.0), r * 0.22, r * 0.22, 0.02,
				CHROME, 8, across)


static func _add_lights(b: MeshBuilder, spec: Spec, _unlit: bool) -> void:
	var s := shape_of(spec.silhouette)
	var hw := spec.width * 0.5
	var hl := spec.length * 0.5
	var y: float = s["deck_y"] + s["deck_h"] * 0.12

	# Передние фары
	var z_f := hl + 0.012
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * hw * 0.68, y, z_f), Vector3(0.36, 0.16, 0.025), DARK)
		b.box(Vector3(sx * hw * 0.64, y, z_f + 0.012), Vector3(0.22, 0.13, 0.025), LAMP_FRONT)
		b.cylinder(Vector3(sx * hw * 0.64, y, z_f + 0.025), 0.045, 0.045, 0.015, Color.WHITE, 8,
			Basis(Vector3.RIGHT, PI * 0.5))
		b.box(Vector3(sx * hw * 0.82, y, z_f + 0.012), Vector3(0.08, 0.13, 0.025), LAMP_TURN)

	# Задние фонари
	var z_r := -hl - 0.012
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * hw * 0.68, y, z_r), Vector3(0.36, 0.16, 0.025), DARK)
		b.box(Vector3(sx * hw * 0.66, y, z_r - 0.012), Vector3(0.20, 0.13, 0.025), LAMP_REAR)
		b.box(Vector3(sx * hw * 0.52, y, z_r - 0.012), Vector3(0.08, 0.11, 0.025), Color("#f4f4f8"))
		b.box(Vector3(sx * hw * 0.82, y, z_r - 0.012), Vector3(0.08, 0.13, 0.025), LAMP_TURN)
