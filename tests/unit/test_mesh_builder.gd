extends GdUnitTestSuite
## Геометрия строится кодом, поэтому ошибка намотки не падает, а тихо выдаёт
## вывернутый наизнанку мир (пол не виден, у зданий рисуются внутренние грани).
## Эти тесты фиксируют направление нормалей — регрессия сразу видна.

const EPS := 1e-4


func _normals_of(mesh: ArrayMesh) -> PackedVector3Array:
	var arrays := mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_NORMAL]


func _colors_of(mesh: ArrayMesh) -> PackedColorArray:
	var arrays := mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_COLOR]


func test_plane_faces_up() -> void:
	var b := MeshBuilder.new()
	b.plane_xz(Vector3.ZERO, Vector2(4.0, 4.0), Color.RED)
	var normals := _normals_of(b.commit())
	assert_int(normals.size()).is_greater(0)
	for n in normals:
		assert_float(n.dot(Vector3.UP)).is_greater(1.0 - EPS)


func test_box_normals_point_outward() -> void:
	var b := MeshBuilder.new()
	b.box(Vector3.ZERO, Vector3(2.0, 2.0, 2.0), Color.WHITE)
	var mesh := b.commit()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_int(verts.size()).is_equal(normals.size())
	# Каждая нормаль должна смотреть от центра куба наружу.
	for i in verts.size():
		assert_float(normals[i].dot(verts[i].normalized())).is_greater(0.0)


func test_box_covers_all_six_directions() -> void:
	var b := MeshBuilder.new()
	b.box(Vector3.ZERO, Vector3(2.0, 2.0, 2.0), Color.WHITE)
	var normals := _normals_of(b.commit())
	var dirs: Array[Vector3] = [
		Vector3.UP, Vector3.DOWN, Vector3.LEFT,
		Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK,
	]
	for d in dirs:
		var found := false
		for n in normals:
			if n.dot(d) > 1.0 - EPS:
				found = true
				break
		assert_bool(found)\
			.override_failure_message("нет грани с нормалью %s" % d)\
			.is_true()


func test_flat_shading_not_smoothed() -> void:
	# У куба ровно 6 различных нормалей: сглаживания быть не должно.
	var b := MeshBuilder.new()
	b.box(Vector3.ZERO, Vector3(2.0, 2.0, 2.0), Color.WHITE)
	var unique := {}
	for n in _normals_of(b.commit()):
		unique[n.snappedf(0.001)] = true
	assert_int(unique.size()).is_equal(6)


func test_vertex_colors_preserved() -> void:
	# Вершинный цвет хранится как RGBA8, поэтому допуск — шаг квантования 1/255.
	const COLOR_EPS := 1.0 / 255.0
	var b := MeshBuilder.new()
	var c := Color(0.2, 0.6, 0.9)
	b.box(Vector3.ZERO, Vector3(1.0, 1.0, 1.0), c)
	for col in _colors_of(b.commit()):
		assert_float(col.r).is_equal_approx(c.r, COLOR_EPS)
		assert_float(col.g).is_equal_approx(c.g, COLOR_EPS)
		assert_float(col.b).is_equal_approx(c.b, COLOR_EPS)


## Регрессия: COLOR.a кодирует тип поверхности (фары/стёкла машин, см. план
## этапа реализма) — если SurfaceTool.commit()/index() потеряет альфу,
## лампы и стёкла молча перестанут работать без единого падения теста.
func test_vertex_color_alpha_preserved() -> void:
	const COLOR_EPS := 1.0 / 255.0
	var b := MeshBuilder.new()
	var c := Color(0.2, 0.6, 0.9, 0.5)
	b.box(Vector3.ZERO, Vector3(1.0, 1.0, 1.0), c)
	for col in _colors_of(b.commit()):
		assert_float(col.a).is_equal_approx(c.a, COLOR_EPS)


## Две вершины на одной позиции, но с разной альфой не должны схлопнуться
## в одну индексом — иначе соседняя обычная поверхность утянет за собой
## тип "фара"/"стекло" у совпадающей по XYZ вершины.
func test_index_does_not_merge_vertices_with_different_alpha() -> void:
	var b := MeshBuilder.new()
	b.tri(Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), Color(1, 1, 1, 1.0))
	b.tri(Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 0), Color(1, 1, 1, 0.9))
	var mesh := b.commit()
	var colors := _colors_of(mesh)
	var alphas := {}
	for col in colors:
		alphas[col.a] = true
	assert_int(alphas.size())\
		.override_failure_message("index() схлопнул вершины с разной альфой в одну")\
		.is_equal(2)


func test_tapered_box_narrows_at_top() -> void:
	var b := MeshBuilder.new()
	b.tapered_box(Vector3.ZERO, Vector3(2.0, 2.0, 4.0), Color.WHITE, Vector2(0.5, 1.0))
	var arrays := b.commit().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var max_top_x := 0.0
	var max_bottom_x := 0.0
	for v in verts:
		if v.y > 0.0:
			max_top_x = maxf(max_top_x, absf(v.x))
		else:
			max_bottom_x = maxf(max_bottom_x, absf(v.x))
	assert_float(max_bottom_x).is_equal_approx(1.0, EPS)
	assert_float(max_top_x).is_equal_approx(0.5, EPS)


func test_cylinder_side_normals_are_horizontal() -> void:
	var b := MeshBuilder.new()
	b.cylinder(Vector3.ZERO, 1.0, 1.0, 2.0, Color.WHITE, 8)
	var normals := _normals_of(b.commit())
	var horizontal := 0
	for n in normals:
		if absf(n.y) < 0.01:
			horizontal += 1
	assert_int(horizontal).is_greater(0)


func test_cylinder_normals_point_outward() -> void:
	var b := MeshBuilder.new()
	b.cylinder(Vector3.ZERO, 1.0, 1.0, 2.0, Color.WHITE, 8)
	var mesh := b.commit()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		var v_horizontal := Vector3(verts[i].x, 0.0, verts[i].z).normalized()
		if v_horizontal.length() > 0.5 and absf(normals[i].y) < 0.1:
			assert_float(normals[i].dot(v_horizontal))\
				.override_failure_message("нормаль цилиндра в %s смотрит внутрь: %s" % [verts[i], normals[i]])\
				.is_greater(0.0)


func test_cone_normals_point_outward() -> void:
	var b := MeshBuilder.new()
	b.cone(Vector3.ZERO, 1.0, 2.0, Color.WHITE, 8)
	var mesh := b.commit()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		var v := verts[i]
		if v.y > -0.99: # боковые грани (не нижняя крышка)
			var v_horiz := Vector3(v.x, 0.0, v.z).normalized()
			if v_horiz.length() > 0.3:
				assert_float(normals[i].dot(v_horiz))\
					.override_failure_message("боковая нормаль конуса в %s смотрит внутрь: %s" % [v, normals[i]])\
					.is_greater(0.0)
				assert_float(normals[i].y)\
					.override_failure_message("боковая нормаль конуса в %s смотрит вниз: %s" % [v, normals[i]])\
					.is_greater(0.0)




func test_ribbon_follows_points() -> void:
	var b := MeshBuilder.new()
	var pts := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0, 0, 10), Vector3(5, 0, 20),
	])
	b.ribbon(pts, 4.0, Color.WHITE)
	var mesh := b.commit()
	assert_object(mesh).is_not_null()
	var aabb := mesh.get_aabb()
	assert_float(aabb.size.z).is_greater(19.0)
	# Лента шириной 4 м не должна выходить далеко за габарит по X.
	assert_float(aabb.size.x).is_between(4.0, 10.0)


func test_ribbon_normals_point_up() -> void:
	# Лента — это дорожное полотно (полотно моста, серпантина, следы шин):
	# её видно сверху. Обратная намотка с фронтальным cull_back делает полосу
	# невидимой целиком и без единой ошибки в консоли — та же ловушка, что
	# закрыта `test_shadow_disc_normals_point_up`.
	var b := MeshBuilder.new()
	var pts := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0, 0, 10), Vector3(5, 2, 20),
	])
	b.ribbon(pts, 4.0, Color.WHITE)
	var normals := _normals_of(b.commit())
	assert_int(normals.size()).is_greater(0)
	for n in normals:
		assert_float(n.dot(Vector3.UP))\
			.override_failure_message("нормаль ленты %s смотрит не вверх" % n)\
			.is_greater(0.5)


func test_empty_builder_commits_null() -> void:
	var b := MeshBuilder.new()
	assert_bool(b.is_empty()).is_true()
	assert_object(b.commit()).is_null()


func test_shadow_disc_is_flat_and_darker_at_center() -> void:
	var b := MeshBuilder.new()
	b.shadow_disc(Vector3.ZERO, 1.0, Color(0.0, 0.0, 0.0), Color(0.5, 0.5, 0.5), 8)
	var mesh := b.commit()
	assert_object(mesh).is_not_null()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for v in verts:
		assert_float(v.y).is_equal_approx(0.0, EPS)
	var center_found := false
	var edge_found := false
	for i in verts.size():
		var r := Vector2(verts[i].x, verts[i].z).length()
		if r < EPS:
			center_found = true
			assert_float(colors[i].r).is_equal_approx(0.0, 0.01)
		elif r > 1.0 - EPS:
			edge_found = true
			assert_float(colors[i].r).is_equal_approx(0.5, 0.01)
	assert_bool(center_found).is_true()
	assert_bool(edge_found).is_true()


## Регрессия: shadow_disc() строил веер с обратной намоткой (нормаль вниз),
## поэтому cull_back в palette_toon.gdshader показывал тень только при
## взгляде СНИЗУ — то есть никогда. Без этой проверки тест выше зелёный,
## а на экране пусто (см. историю правки).
func test_shadow_disc_normals_point_up() -> void:
	var b := MeshBuilder.new()
	b.shadow_disc(Vector3.ZERO, 1.0, Color.BLACK, Color.GRAY, 8)
	var normals := _normals_of(b.commit())
	assert_int(normals.size()).is_greater(0)
	for n in normals:
		assert_float(n.dot(Vector3.UP)).is_greater(1.0 - EPS)


func test_prism_normals_point_outward() -> void:
	var b := MeshBuilder.new()
	b.prism(Vector3.ZERO, Vector3(2.0, 1.0, 4.0), Color.WHITE)
	var mesh := b.commit()
	assert_object(mesh).is_not_null()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_int(verts.size()).is_equal(normals.size())
	for i in verts.size():
		# Нормали смотрят наружу от центра призмы (с небольшим допуском)
		assert_float(normals[i].dot(verts[i])).is_greater_equal(-EPS)


func test_sphere_normals_point_outward() -> void:
	var b := MeshBuilder.new()
	b.sphere(Vector3.ZERO, 1.0, Color.WHITE, 5, 8)
	var mesh := b.commit()
	assert_object(mesh).is_not_null()
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_int(verts.size()).is_equal(normals.size())
	for i in verts.size():
		assert_float(normals[i].dot(verts[i].normalized()))\
			.override_failure_message("нормаль сферы в %s смотрит внутрь: %s" % [verts[i], normals[i]])\
			.is_greater(0.0)


func test_tree_meshes_normals() -> void:
	for mesh_name in ["deciduous_tree", "pine_tree"]:
		var mesh: ArrayMesh
		if mesh_name == "deciduous_tree":
			mesh = PropMeshes.deciduous_tree()
		else:
			mesh = PropMeshes.pine_tree()
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var zero_normals := 0
		var nan_normals := 0
		for i in normals.size():
			var n := normals[i]
			if n.is_zero_approx():
				zero_normals += 1
			if is_nan(n.x) or is_nan(n.y) or is_nan(n.z):
				nan_normals += 1
		print("%s: verts=%d, indices=%d, zero_normals=%d, nan_normals=%d"
			% [mesh_name, verts.size(), indices.size(), zero_normals, nan_normals])
		assert_int(zero_normals)\
			.override_failure_message("%s имеет нулевые нормали (%d шт)" % [mesh_name, zero_normals])\
			.is_equal(0)
		assert_int(nan_normals)\
			.override_failure_message("%s имеет NaN нормали (%d шт)" % [mesh_name, nan_normals])\
			.is_equal(0)




# --- Модельный трансформ ----------------------------------------------------
#
# Повёрнутые здания (этап 5) строятся в собственных осях, а место в городе
# задаёт трансформ билдера. Значит две вещи обязаны быть верны: перенос без
# поворота не меняет НИЧЕГО в сравнении с прямой укладкой в мировых
# координатах, и поворот применяется ко всем примитивам, а не только к боксу.

func _verts_of(mesh: ArrayMesh) -> PackedVector3Array:
	var arrays := mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX]


func test_model_translation_matches_direct_world_coordinates() -> void:
	var offset := Vector3(37.0, 0.0, -19.0)
	var direct := MeshBuilder.new()
	direct.box(offset + Vector3(1.5, 2.0, -0.5), Vector3(4.0, 6.0, 3.0), Color.WHITE)
	var moved := MeshBuilder.new()
	moved.set_model(Transform3D(Basis.IDENTITY, offset))
	moved.box(Vector3(1.5, 2.0, -0.5), Vector3(4.0, 6.0, 3.0), Color.WHITE)
	var a := _verts_of(direct.commit())
	var b := _verts_of(moved.commit())
	assert_int(b.size()).is_equal(a.size())
	for i in a.size():
		assert_vector(b[i])\
			.override_failure_message(
				"вершина %d разошлась: %s против %s" % [i, b[i], a[i]])\
			.is_equal(a[i])


func test_model_rotation_turns_every_primitive() -> void:
	# Цилиндр и призма идут мимо box(), но через tri() — а трансформ живёт
	# именно там, поэтому поворачивается и они.
	var yaw := PI * 0.5
	var b := MeshBuilder.new()
	b.set_model(Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO))
	b.box(Vector3(10.0, 0.0, 0.0), Vector3(2.0, 2.0, 2.0), Color.WHITE)
	b.prism(Vector3(20.0, 0.0, 0.0), Vector3(2.0, 2.0, 2.0), Color.WHITE)
	b.cylinder(Vector3(30.0, 0.0, 0.0), 1.0, 1.0, 2.0, Color.WHITE, 6)
	# Поворот на +90° вокруг Y уводит ось X в -Z (city_plan.gd: локальный +X
	# ложится в мир как (cos yaw, -sin yaw)).
	for v in _verts_of(b.commit()):
		assert_float(v.x)\
			.override_failure_message("вершина %s осталась на оси X после поворота" % v)\
			.is_less(2.0)
		assert_float(v.z)\
			.override_failure_message("вершина %s не ушла в -Z после поворота" % v)\
			.is_less(1.0)


func test_clear_model_returns_to_world_coordinates() -> void:
	var b := MeshBuilder.new()
	b.set_model(Transform3D(Basis.IDENTITY, Vector3(100.0, 0.0, 0.0)))
	b.clear_model()
	b.box(Vector3.ZERO, Vector3(2.0, 2.0, 2.0), Color.WHITE)
	for v in _verts_of(b.commit()):
		assert_float(absf(v.x))\
			.override_failure_message("после clear_model() вершина уехала в %s" % v)\
			.is_less_equal(1.0 + EPS)
