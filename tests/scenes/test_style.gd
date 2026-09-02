extends Node3D
## Полигон визуального стиля: палитровый материал, плоские нормали,
## toon-освещение, обводка «героев», пост-обработка.
##
## Проверяется в трёх рендерерах — снимки сравниваются между собой:
##   tools/capture_style.sh

const PALETTE_MAT := preload("res://fx/materials/mat_palette.tres")
const OUTLINE_MAT := preload("res://fx/materials/mat_outline.tres")

# Палитра центра города (config.js:276) — тёплая охра.
const FACADES: PackedColorArray = [
	Color("#e8c98a"), Color("#e0b060"), Color("#d8a050"),
	Color("#f0d8a0"), Color("#d09060"),
]
const ROAD := Color("#3a3f46")
const GRASS := Color("#7fae6a")
const CURB := Color("#bcbcb4")
const TAXI_YELLOW := Color("#f2c12e")
const TREE_LEAF := Color("#5a9a4a")
const TREE_TRUNK := Color("#6a4a34")


## Ракурсы для сравнения между рендерерами. Индекс задаётся через
## `-- --view N` съёмщиком кадров.
const VIEWS: Array[Vector3] = [
	Vector3(26.0, 13.0, 34.0),   # общий план перекрёстка
	Vector3(7.5, 2.6, 15.0),     # уровень глаз у машины
	Vector3(0.0, 55.0, 0.1),     # сверху, планировка
]


func _ready() -> void:
	var rng := SeededRng.new(20260805)
	_build_ground()
	_build_blocks(rng)
	_build_trees(rng)
	_build_hero()
	_place_camera()
	_aim_sun()
	var s := $Sun as DirectionalLight3D
	print("test_style: рендерер=", RenderingServer.get_current_rendering_method(),
		" тени=", s.shadow_enabled, " режим=", s.directional_shadow_mode,
		" bias=", s.shadow_bias, "/", s.shadow_normal_bias,
		" дальность=", s.directional_shadow_max_distance)


func _place_camera() -> void:
	var cam := $Camera3D as Camera3D
	var idx := 0
	var args := OS.get_cmdline_user_args()
	var i := args.find("--view")
	if i >= 0 and i + 1 < args.size():
		idx = clampi(args[i + 1].to_int(), 0, VIEWS.size() - 1)
	cam.position = VIEWS[idx]
	# look_at надёжнее ручного базиса в .tscn: у камеры «вперёд» — это -Z.
	var target := Vector3(3.0, 1.5, 6.0) if idx != 2 else Vector3.ZERO
	cam.look_at(target, Vector3.UP)


func _aim_sun() -> void:
	var sun := $Sun as DirectionalLight3D
	# Тени и постэффекты приводятся к возможностям рендерера: в Compatibility
	# каскадный PSSM не рисуется вовсе, там нужен ортогональный режим.
	var preset := Db.gfx.get_preset(&"high")
	if preset != null:
		RenderCaps.configure_sun(sun, preset)
		RenderCaps.configure_environment(
			($WorldEnvironment as WorldEnvironment).environment, preset)
	sun.position = Vector3(-34.0, 46.0, -30.0)
	# Свет идёт ИЗ-ЗА зданий В СТОРОНУ камеры: тени вытягиваются к зрителю
	# и ложатся поперёк дороги. Если светить от камеры, тени прячутся за
	# объектами и сцена читается плоской.
	sun.look_at(Vector3(22.0, 0.0, 28.0), Vector3.UP)


func _renderer_name() -> String:
	return str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))


## Диагностика: `-- --std` подменяет палитровый шейдер на StandardMaterial3D,
## чтобы отделить проблемы шейдера от проблем сцены и света.
func _material() -> Material:
	if "--std" in OS.get_cmdline_user_args():
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.95
		return m
	return PALETTE_MAT


func _add_mesh(mesh: ArrayMesh, name_hint: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_hint
	mi.mesh = mesh
	mi.material_override = _material()
	add_child(mi)
	return mi


func _build_ground() -> void:
	var b := MeshBuilder.new()
	b.plane_xz(Vector3.ZERO, Vector2(120.0, 120.0), GRASS)
	# Крестообразный перекрёсток: полотно 12 м, бордюр по краям.
	b.plane_xz(Vector3(0.0, 0.05, 0.0), Vector2(12.0, 120.0), ROAD)
	b.plane_xz(Vector3(0.0, 0.05, 0.0), Vector2(120.0, 12.0), ROAD)
	for s in [-1.0, 1.0]:
		b.box(Vector3(s * 6.25, 0.07, 0.0), Vector3(0.5, 0.16, 120.0), CURB)
		b.box(Vector3(0.0, 0.07, s * 6.25), Vector3(120.0, 0.16, 0.5), CURB)
	_add_mesh(b.commit(), "Ground")


func _build_blocks(rng: SeededRng) -> void:
	var b := MeshBuilder.new()
	for i in 14:
		var qx: float = 1.0 if rng.chance(0.5) else -1.0
		var qz: float = 1.0 if rng.chance(0.5) else -1.0
		var w := rng.randf_range(8.0, 16.0)
		var d := rng.randf_range(8.0, 16.0)
		var h := rng.randf_range(6.0, 26.0)
		var x := qx * rng.randf_range(11.0, 46.0)
		var z := qz * rng.randf_range(11.0, 46.0)
		var facade := rng.pick_color(FACADES)
		b.box(Vector3(x, h * 0.5, z), Vector3(w, h, d), facade)
		# Крыша темнее фасада в 0.62 раза (utils.js:107).
		var roof := Color(facade.r * 0.62, facade.g * 0.62, facade.b * 0.62)
		b.plane_xz(Vector3(x, h + 0.01, z), Vector2(w, d), roof)
		if rng.chance(0.25):
			b.cone(Vector3(x, h + h * 0.11, z), w * 0.62, h * 0.22, roof, 4)
	_add_mesh(b.commit(), "Blocks")


func _build_trees(rng: SeededRng) -> void:
	var b := MeshBuilder.new()
	for i in 22:
		var x := rng.randf_range(-52.0, 52.0)
		var z := rng.randf_range(-52.0, 52.0)
		if absf(x) < 9.0 or absf(z) < 9.0:
			continue
		var s := rng.randf_range(0.8, 1.3)
		b.cylinder(Vector3(x, 1.2 * s, z), 0.3 * s, 0.45 * s, 2.4 * s, TREE_TRUNK, 5)
		b.sphere(Vector3(x, 2.9 * s, z), 1.7 * s, TREE_LEAF, 4, 7, 1.1)
	_add_mesh(b.commit(), "Trees")


## «Герой» — объект с обводкой inverted hull. Так выделяются машина игрока,
## пеший игрок, активный пассажир, маркер заказа и полиция.
func _build_hero() -> void:
	var b := MeshBuilder.new()
	var dark := Color("#20242c")
	var glass := Color("#9fd8e8")
	# Кузов седана усечёнными боксами: днище, капот, салон, крыша.
	b.tapered_box(Vector3(0.0, 0.72, 0.0), Vector3(1.9, 0.42, 4.3), TAXI_YELLOW,
		Vector2(0.98, 1.0))
	b.tapered_box(Vector3(0.0, 1.10, -0.15), Vector3(1.64, 0.46, 1.9), TAXI_YELLOW,
		Vector2(0.90, 0.62), -0.12, -0.28, -0.10)
	b.tapered_box(Vector3(0.0, 1.34, -0.15), Vector3(1.48, 0.10, 1.2), glass,
		Vector2(0.95, 0.9))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.cylinder(Vector3(sx * 0.86, 0.38, sz * 1.34), 0.38, 0.38, 0.30,
				dark, 10, Basis(Vector3.FORWARD, PI * 0.5))
	b.box(Vector3(0.0, 0.60, 2.16), Vector3(1.98, 0.16, 0.16), dark)
	b.box(Vector3(0.0, 0.60, -2.16), Vector3(1.98, 0.16, 0.16), dark)
	b.box(Vector3(0.0, 1.62, -0.15), Vector3(0.62, 0.20, 0.26), Color("#f5b020"))

	var mesh := b.commit()
	var hero := _add_mesh(mesh, "HeroCar")
	hero.position = Vector3(3.2, 0.0, 8.0)
	hero.rotation.y = -0.35

	# Второй проход обводки — отдельная нода с тем же мешем.
	var outline := MeshInstance3D.new()
	outline.name = "HeroOutline"
	outline.mesh = mesh
	outline.material_override = OUTLINE_MAT
	hero.add_child(outline)
