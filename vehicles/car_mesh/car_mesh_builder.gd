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
		"deck_y": 0.72, "deck_h": 0.42, "belt_w": 0.98,
		"hood": 0.32, "hood_rise": -0.30, "trunk": 0.28, "trunk_rise": -0.30,
		"cab_w": 0.90, "cab_h": 0.46, "cab_y": 1.32, "cab_len": 0.46,
		"roof_w": 0.74, "roof_h": 0.09, "roof_y": 1.52, "roof_len": 0.24,
		"wheel_r": 0.38, "van": false,
	},
	&"hatch": {
		"deck_y": 0.70, "deck_h": 0.42, "belt_w": 0.98,
		"hood": 0.30, "hood_rise": -0.28, "trunk": 0.16, "trunk_rise": -0.14,
		"cab_w": 0.88, "cab_h": 0.50, "cab_y": 1.30, "cab_len": 0.50,
		"roof_w": 0.76, "roof_h": 0.09, "roof_y": 1.54, "roof_len": 0.30,
		"wheel_r": 0.36, "van": false,
	},
	&"wagon": {
		"deck_y": 0.72, "deck_h": 0.42, "belt_w": 0.99,
		"hood": 0.28, "hood_rise": -0.28, "trunk": 0.10, "trunk_rise": -0.06,
		"cab_w": 0.88, "cab_h": 0.50, "cab_y": 1.32, "cab_len": 0.58,
		"roof_w": 0.78, "roof_h": 0.09, "roof_y": 1.58, "roof_len": 0.44,
		"wheel_r": 0.37, "van": false, "rack": true,
	},
	&"coupe": {
		"deck_y": 0.66, "deck_h": 0.40, "belt_w": 0.98,
		"hood": 0.36, "hood_rise": -0.34, "trunk": 0.26, "trunk_rise": -0.32,
		"cab_w": 0.88, "cab_h": 0.40, "cab_y": 1.20, "cab_len": 0.40,
		"roof_w": 0.70, "roof_h": 0.08, "roof_y": 1.38, "roof_len": 0.18,
		"wheel_r": 0.37, "van": false,
	},
	&"suv": {
		"deck_y": 0.86, "deck_h": 0.52, "belt_w": 0.99,
		"hood": 0.26, "hood_rise": -0.20, "trunk": 0.12, "trunk_rise": -0.06,
		"cab_w": 0.92, "cab_h": 0.56, "cab_y": 1.56, "cab_len": 0.56,
		"roof_w": 0.82, "roof_h": 0.09, "roof_y": 1.86, "roof_len": 0.42,
		"wheel_r": 0.44, "van": false, "rack": true,
	},
	&"retro": {
		"deck_y": 0.74, "deck_h": 0.46, "belt_w": 0.96,
		"hood": 0.32, "hood_rise": -0.10, "trunk": 0.26, "trunk_rise": -0.10,
		"cab_w": 0.88, "cab_h": 0.52, "cab_y": 1.36, "cab_len": 0.48,
		"roof_w": 0.76, "roof_h": 0.09, "roof_y": 1.60, "roof_len": 0.28,
		"wheel_r": 0.36, "van": false,
	},
	&"premium": {
		"deck_y": 0.74, "deck_h": 0.44, "belt_w": 0.99,
		"hood": 0.34, "hood_rise": -0.26, "trunk": 0.28, "trunk_rise": -0.26,
		"cab_w": 0.90, "cab_h": 0.44, "cab_y": 1.34, "cab_len": 0.48,
		"roof_w": 0.76, "roof_h": 0.09, "roof_y": 1.56, "roof_len": 0.26,
		"wheel_r": 0.39, "van": false,
	},
	&"van": {
		"deck_y": 0.62, "deck_h": 0.40, "cab_len_frac": 0.22,
		"cab_h": 0.90, "cab_y": 1.05, "windshield_rise": -0.28,
		"cargo_len": 0.68, "cargo_h": 1.50, "cargo_y": 1.35,
		"wheel_r": 0.40, "van": true,
	},
	&"bus": {
		"deck_y": 0.70, "deck_h": 0.46, "cab_len_frac": 0.16,
		"cab_h": 1.10, "cab_y": 1.30, "windshield_rise": -0.20,
		"cargo_len": 0.80, "cargo_h": 2.10, "cargo_y": 1.70,
		"wheel_r": 0.46, "van": true,
	},
	&"pickup": {
		"deck_y": 0.80, "deck_h": 0.46, "cab_len_frac": 0.40,
		"cab_h": 0.80, "cab_y": 1.36, "windshield_rise": -0.24,
		"cargo_len": 0.44, "cargo_h": 0.55, "cargo_y": 1.06,
		"wheel_r": 0.42, "van": true, "open_bed": true,
	},
	&"truck": {
		"deck_y": 0.86, "deck_h": 0.52, "cab_len_frac": 0.26,
		"cab_h": 1.40, "cab_y": 1.70, "windshield_rise": -0.16,
		"cargo_len": 0.66, "cargo_h": 2.30, "cargo_y": 2.05,
		"wheel_r": 0.50, "van": true,
	},
}


## Описание конкретной машины.
class Spec extends RefCounted:
	var silhouette: StringName = &"sedan"
	var width := 1.9
	var length := 4.3
	var body_color := Color("#f2c12e")
	var rim_style: StringName = &"disc"
	var rim_color := Color("#b8b8b8")
	var body_kit: StringName = &"stock"
	var spoiler := false
	## Ливрея такси: шашечки по борту и плафон на крыше.
	var taxi_livery := false
	## Синяя полоса полиции.
	var police_livery := false
	## Мигалка: "" | "police" | "ambulance"
	var beacon: StringName = &""


static func shape_of(silhouette: StringName) -> Dictionary:
	return SHAPES.get(silhouette, SHAPES[&"sedan"])


## Верх кузова. У легковых это крыша, у фургонов — верх грузового объёма:
## мигалку и багажник надо ставить на них одинаково.
static func roof_height(s: Dictionary) -> float:
	if s.get("van", false):
		return float(s["cargo_y"]) + float(s["cargo_h"]) * 0.5
	return float(s["roof_y"])


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


## Кузов без света и колёс — вариант для машины игрока: свет и колёса
## живут отдельными узлами, чтобы мигать и вращаться.
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
	b.cylinder(Vector3.ZERO, r, r, 0.30, TYRE, 12, across)
	match spec.rim_style:
		&"spoke":
			b.cylinder(Vector3.ZERO, r * 0.45, r * 0.45, 0.34, spec.rim_color, 8, across)
			for k in 5:
				var a := TAU * k / 5.0
				b.box(Vector3(0.0, sin(a) * r * 0.5, cos(a) * r * 0.5),
					Vector3(0.34, r * 0.16, r * 0.94),
					spec.rim_color, Basis(Vector3.RIGHT, a))
		&"chrome":
			b.cylinder(Vector3.ZERO, r * 0.62, r * 0.62, 0.33, CHROME, 12, across)
			b.cylinder(Vector3.ZERO, r * 0.30, r * 0.30, 0.35, spec.rim_color, 8, across)
		_:
			b.cylinder(Vector3.ZERO, r * 0.58, r * 0.58, 0.33, spec.rim_color, 10, across)
	return b.commit()


## Фары, стопы и поворотники — отдельными мешами, чтобы зажигать их
## сменой эмиссии материала, а не пересборкой геометрии.
static func build_lamps(spec: Spec, rear: bool) -> ArrayMesh:
	var b := MeshBuilder.new()
	var hw := spec.width * 0.5
	var hl := spec.length * 0.5
	var s := shape_of(spec.silhouette)
	var y: float = s["deck_y"] + s["deck_h"] * 0.15
	var color := LAMP_REAR if rear else LAMP_FRONT
	var z := (-hl - 0.02) if rear else (hl + 0.02)
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * hw * 0.66, y, z), Vector3(0.30, 0.17, 0.06), color)
	return b.commit()


# --- Кузов ------------------------------------------------------------------

static func _add_body(b: MeshBuilder, spec: Spec) -> void:
	var s := shape_of(spec.silhouette)
	if s.get("van", false):
		_add_van_body(b, spec, s)
	else:
		_add_car_body(b, spec, s)


## Легковой силуэт: единый объём кузова со скошенными капотом и багажником,
## поверх него салон, сужающийся к крыше.
##
## Отдельными плитами капот и багажник не делаются: они читались полками,
## лежащими на кузове, а не его частью.
static func _add_car_body(b: MeshBuilder, spec: Spec, s: Dictionary) -> void:
	var w := spec.width
	var l := spec.length
	var hl := l * 0.5
	var deck_y: float = s["deck_y"]
	var deck_h: float = s["deck_h"]
	var deck_top := deck_y + deck_h * 0.5

	# Кузов: верх уже низа (завал бортов), нос и корма опущены — отсюда
	# покатый капот и багажник.
	b.tapered_box(Vector3(0.0, deck_y, 0.0), Vector3(w, deck_h, l),
		spec.body_color, Vector2(s["belt_w"], 1.0), 0.0,
		s["hood_rise"] * 0.22, s["trunk_rise"] * 0.22)

	# Салон стоит НА кузове и тянется до крыши — без зазора между объёмами.
	var cab_len: float = l * s["cab_len"]
	var hood_len: float = l * s["hood"]
	var cab_z := (hl - hood_len) - cab_len * 0.5
	var roof_y: float = s["roof_y"]
	var cab_h: float = roof_y - deck_top
	var cab_cy := deck_top + cab_h * 0.5
	b.tapered_box(Vector3(0.0, cab_cy, cab_z),
		Vector3(w * s["cab_w"], cab_h, cab_len), spec.body_color,
		Vector2(s["roof_w"] / s["cab_w"], s["roof_len"] / s["cab_len"]),
		cab_len * 0.10)
	# Крыша — тонкая плита, замыкающая силуэт.
	b.tapered_box(Vector3(0.0, roof_y + s["roof_h"] * 0.5, cab_z + cab_len * 0.10),
		Vector3(w * s["roof_w"], s["roof_h"], l * s["roof_len"]),
		spec.body_color, Vector2(0.97, 0.97))

	_add_greenhouse(b, spec, s, cab_z, cab_len, deck_top, roof_y)


## Остекление: лобовое, заднее и боковые. Тонированное ядро под ними
## не даёт увидеть «пустой» салон насквозь.
static func _add_greenhouse(b: MeshBuilder, spec: Spec, s: Dictionary,
		cab_z: float, cab_len: float, deck_top: float, roof_y: float) -> void:
	var w := spec.width
	var cab_w: float = w * s["cab_w"]
	var roof_w: float = w * s["roof_w"]
	var roof_len: float = spec.length * s["roof_len"]
	# Стёкла занимают верхние две трети салона: снизу остаётся линия борта.
	var glass_bottom := deck_top + (roof_y - deck_top) * 0.26
	var glass_h := (roof_y - glass_bottom) * 0.88
	var y := glass_bottom + glass_h * 0.5

	# Салон сужается кверху, поэтому ширина и длина остекления берутся
	# интерполяцией по высоте: иначе стёкла торчат за борт.
	var t: float = clampf((y - deck_top) / maxf(roof_y - deck_top, 0.001), 0.0, 1.0)
	var half_w := lerpf(cab_w, roof_w, t) * 0.5
	var half_len := lerpf(cab_len, roof_len, t) * 0.5
	# Крыша сдвинута вперёд — центр остекления смещается вместе с ней.
	var z := cab_z + cab_len * 0.10 * t

	# Тонированное ядро, чтобы салон не просвечивал насквозь.
	b.box(Vector3(0.0, y, z),
		Vector3(half_w * 1.80, glass_h * 0.92, half_len * 1.80), GLASS_TINT)
	# Лобовое и заднее.
	b.box(Vector3(0.0, y, z + half_len * 1.0),
		Vector3(half_w * 1.80, glass_h * 0.94, 0.05), GLASS)
	b.box(Vector3(0.0, y, z - half_len * 1.0),
		Vector3(half_w * 1.74, glass_h * 0.88, 0.05), GLASS)
	# Боковые: два окна со стойкой между ними.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.box(Vector3(sx * half_w * 1.0, y, z + sz * half_len * 0.44),
				Vector3(0.05, glass_h * 0.9, half_len * 0.72), GLASS)


## Кабина над двигателем: фургон, автобус, пикап, грузовик.
static func _add_van_body(b: MeshBuilder, spec: Spec, s: Dictionary) -> void:
	var w := spec.width
	var l := spec.length
	var hl := l * 0.5
	b.tapered_box(Vector3(0.0, s["deck_y"], 0.0), Vector3(w, s["deck_h"], l),
		spec.body_color, Vector2(0.99, 1.0))

	var cab_len: float = l * s["cab_len_frac"]
	var cab_z := hl - cab_len * 0.5
	b.tapered_box(Vector3(0.0, s["cab_y"], cab_z),
		Vector3(w * 0.97, s["cab_h"], cab_len), spec.body_color,
		Vector2(0.96, 1.0), 0.0, s["windshield_rise"] * 0.3, 0.0)
	# Лобовое стекло кабины.
	b.box(Vector3(0.0, s["cab_y"] + s["cab_h"] * 0.18, cab_z + cab_len * 0.46),
		Vector3(w * 0.86, s["cab_h"] * 0.52, 0.06), GLASS)

	var cargo_len: float = l * s["cargo_len"]
	var cargo_z := hl - cab_len - cargo_len * 0.5
	if s.get("open_bed", false):
		# Открытый кузов пикапа: борта, а не коробка.
		var h: float = s["cargo_h"]
		var y: float = s["deck_y"] + s["deck_h"] * 0.5 + h * 0.5
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * w * 0.46, y, cargo_z),
				Vector3(0.09, h, cargo_len), spec.body_color)
		b.box(Vector3(0.0, y, cargo_z - cargo_len * 0.5),
			Vector3(w * 0.94, h, 0.09), spec.body_color)
	else:
		b.tapered_box(Vector3(0.0, s["cargo_y"], cargo_z),
			Vector3(w * 0.98, s["cargo_h"], cargo_len), spec.body_color,
			Vector2(0.98, 0.99))
		# Окна пассажирского салона.
		if spec.silhouette == &"bus" or spec.silhouette == &"van":
			var rows := maxi(2, int(cargo_len / 1.3))
			for k in rows:
				var z := cargo_z + (k - (rows - 1) * 0.5) * (cargo_len / rows)
				for sx: float in [-1.0, 1.0]:
					b.box(Vector3(sx * w * 0.49, s["cargo_y"] + s["cargo_h"] * 0.22, z),
						Vector3(0.05, s["cargo_h"] * 0.34, cargo_len / rows * 0.72),
						GLASS)


# --- Детали -----------------------------------------------------------------

static func _add_details(b: MeshBuilder, spec: Spec, include_beacon: bool = true) -> void:
	var s := shape_of(spec.silhouette)
	var w := spec.width
	var l := spec.length
	var hw := w * 0.5
	var hl := l * 0.5
	var deck_y: float = s["deck_y"]
	var deck_h: float = s["deck_h"]
	var wheel_r: float = s["wheel_r"]

	# Бамперы — узкая полоса по низу носа и кормы.
	for sz: float in [-1.0, 1.0]:
		b.box(Vector3(0.0, deck_y - deck_h * 0.42, sz * (hl - 0.05)),
			Vector3(w * 0.94, 0.13, 0.14), DARK)
	# Решётка радиатора и номерные знаки.
	b.box(Vector3(0.0, deck_y, hl + 0.01), Vector3(w * 0.4, 0.16, 0.05), DARK)
	for sz: float in [-1.0, 1.0]:
		b.box(Vector3(0.0, deck_y - 0.22, sz * (hl + 0.03)),
			Vector3(0.42, 0.14, 0.03), PLATE)
	# Колёсных арок отдельными брусками нет: на такой детализации они читались
	# чёрными палками, торчащими из борта. Колесо и так утоплено в кузов.
	# Зеркала.
	var mirror_z: float = hl * (0.36 if not s.get("van", false) else 0.42)
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * (hw + 0.06), s["cab_y"], mirror_z),
			Vector3(0.14, 0.09, 0.16), spec.body_color)
	# Молдинг по борту — тонкая линия на уровне ручек, ломает однотонность.
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * (hw - 0.02), deck_y + deck_h * 0.18, 0.0),
			Vector3(0.03, 0.04, l * 0.66), DARK)
	# Дверные ручки.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.box(Vector3(sx * (hw - 0.02), deck_y + deck_h * 0.3, sz * l * 0.12),
				Vector3(0.04, 0.045, 0.14), CHROME)
	# Выхлоп.
	b.cylinder(Vector3(hw * 0.5, deck_y - 0.26, -hl - 0.03), 0.05, 0.05, 0.12,
		CHROME, 6, Basis(Vector3.RIGHT, PI * 0.5))

	if spec.body_kit == &"sport":
		b.box(Vector3(0.0, deck_y - 0.22, hl - 0.04),
			Vector3(w * 1.06, wheel_r * 0.22, 0.22), DARK)
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * hw, deck_y - 0.24, 0.0),
				Vector3(0.12, wheel_r * 0.3, l * 0.52), DARK)
	if spec.spoiler:
		var sy: float = deck_y + 0.6
		b.box(Vector3(0.0, sy + 0.24, -hl + 0.35), Vector3(w * 0.9, 0.08, 0.42),
			spec.body_color)
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * w * 0.32, sy + 0.1, -hl + 0.35),
				Vector3(0.07, 0.28, 0.14), DARK)
	if s.get("rack", false):
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * w * 0.34, roof_height(s) + 0.07, 0.0),
				Vector3(0.05, 0.05, l * 0.5), DARK)

	if spec.taxi_livery:
		_add_taxi_livery(b, spec, s)
	if spec.police_livery:
		for sx: float in [-1.0, 1.0]:
			b.box(Vector3(sx * (hw + 0.005), deck_y, 0.0),
				Vector3(0.02, 0.22, l * 0.66), Color("#1a3a8a"))
	if spec.beacon != &"" and include_beacon:
		_add_beacon(b, spec, s)


## Шашечки по борту и плафон «ТАКСИ» на крыше.
static func _add_taxi_livery(b: MeshBuilder, spec: Spec, s: Dictionary) -> void:
	var hw := spec.width * 0.5
	var l := spec.length
	var deck_y: float = s["deck_y"]
	var cells := 10
	for sx: float in [-1.0, 1.0]:
		for k in cells:
			if k % 2 == 1:
				continue
			var z := (k - (cells - 1) * 0.5) * (l * 0.62 / cells)
			b.box(Vector3(sx * (hw + 0.006), deck_y - 0.02, z),
				Vector3(0.02, 0.12, l * 0.62 / cells), Color("#1a1a1a"))
	b.box(Vector3(0.0, roof_height(s) + 0.14, 0.1),
		Vector3(0.62, 0.20, 0.26), Color("#f5b020"))


## Полиция и скорая обе несут красно-синюю мигалку (carmodel.js:744-776) —
## различается только форма плафона, не набор цветов.
static func _add_beacon(b: MeshBuilder, spec: Spec, s: Dictionary) -> void:
	_add_beacon_half(b, spec, s, true)
	_add_beacon_half(b, spec, s, false)


## Одна половина мигалки (красная или синяя) — вынесена отдельно, чтобы
## TrafficLayer мог собрать её самостоятельным мешем и мигать им в
## противофазе, не трогая статичный кузов.
static func _add_beacon_half(b: MeshBuilder, spec: Spec, s: Dictionary,
		red: bool) -> void:
	var y := roof_height(s) + 0.12
	var color := Color("#d02020") if red else Color("#2040d0")
	if spec.beacon == &"police":
		var sx := -0.22 if red else 0.22
		b.box(Vector3(sx, y, 0.0), Vector3(0.44, 0.14, 0.28), color)
	else:
		var sx := -0.2 if red else 0.2
		b.box(Vector3(sx, y, 0.0), Vector3(0.36, 0.13, 0.2), color)


## Одна половина мигалки как отдельный меш — для независимого мигания в
## трафике (build_merged печёт маячок статично, здесь он на отдельном узле).
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
			var p := Vector3(sx * (hw - 0.12), r, sz * (hl - r - 0.24))
			b.cylinder(p, r, r, 0.32, TYRE, 12, across)
			b.cylinder(p, r * 0.58, r * 0.58, 0.34, spec.rim_color, 8, across)


static func _add_lights(b: MeshBuilder, spec: Spec, unlit: bool) -> void:
	var s := shape_of(spec.silhouette)
	var hw := spec.width * 0.5
	var hl := spec.length * 0.5
	var y: float = s["deck_y"] + s["deck_h"] * 0.15
	for sx: float in [-1.0, 1.0]:
		b.box(Vector3(sx * hw * 0.66, y, hl + 0.02), Vector3(0.30, 0.17, 0.06),
			LAMP_FRONT)
		b.box(Vector3(sx * hw * 0.66, y, -hl - 0.02), Vector3(0.30, 0.17, 0.06),
			LAMP_REAR)
		b.box(Vector3(sx * hw * 0.9, y, hl - 0.02), Vector3(0.12, 0.12, 0.06),
			LAMP_TURN)
