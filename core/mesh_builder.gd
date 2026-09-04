class_name MeshBuilder
extends RefCounted
## Построитель низкополигональной геометрии с вершинными цветами.
##
## Вся геометрия проекта (город, машины, пешеходы, пропсы) строится этим
## классом в ОДИН ArrayMesh с одним палитровым материалом: цвет уходит в
## вершинный атрибут, поэтому батчинг не ломается, а число draw calls
## определяется числом чанков, а не числом объектов.
##
## Нормали считаются пофасетно (грани не сглаживаются) — это и есть
## low-poly-шейдинг, он достаётся бесплатно на этапе меширования.
## Порт mergeColored() и taperedBox() из utils.js/carmodel.js.

var _st := SurfaceTool.new()
var _started := false
## Накопительное вертикальное затемнение (псевдо-AO) применяется шейдером,
## здесь хранится только опорная высота для чанка.
var vertex_count := 0


func _init() -> void:
	begin()


func begin() -> MeshBuilder:
	_st.clear()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Группа сглаживания -1 = «не сглаживать». Без этого generate_normals()
	# усредняет нормали совпадающих вершин, и куб получает мягкие градиенты
	# вместо граней — весь low-poly-шейдинг рассыпается.
	_st.set_smooth_group(-1)
	_started = true
	vertex_count = 0
	return self


## Готовый меш. index() схлопывает одинаковые вершины уже ПОСЛЕ расчёта
## нормалей, поэтому плоский шейдинг сохраняется, а буфер сжимается.
func commit(existing: ArrayMesh = null) -> ArrayMesh:
	# Пустой билдер отдаёт null: генераторы чанков создают MeshInstance3D
	# только если геометрия действительно есть.
	if not _started or vertex_count == 0:
		_started = false
		return existing
	_st.generate_normals()
	_st.index()
	var mesh := _st.commit(existing)
	_started = false
	return mesh


func is_empty() -> bool:
	return vertex_count == 0


# --- Примитивы ---------------------------------------------------------------

## Треугольник a-b-c, заданный ПРОТИВ часовой стрелки при взгляде снаружи.
##
## Godot считает передними грани с намоткой ПО часовой стрелке, поэтому
## вершины укладываются в обратном порядке. Вся геометрия проекта задаётся
## в привычной CCW-нотации, а разворот происходит здесь — один раз.
func tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	_st.set_color(color)
	_st.set_uv(Vector2(0.5, 1.0))
	_st.add_vertex(c)
	_st.set_color(color)
	_st.set_uv(Vector2(1.0, 0.0))
	_st.add_vertex(b)
	_st.set_color(color)
	_st.set_uv(Vector2.ZERO)
	_st.add_vertex(a)
	vertex_count += 3


## Четырёхугольник a-b-c-d (по контуру). Разбивается на два треугольника.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	tri(a, b, c, color)
	tri(a, c, d, color)


## Параллелепипед с центром в `center` и размерами `size`.
func box(center: Vector3, size: Vector3, color: Color,
		basis_rot: Basis = Basis.IDENTITY) -> void:
	var h := size * 0.5
	var corners: Array[Vector3] = [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	for i in corners.size():
		corners[i] = center + basis_rot * corners[i]
	_box_faces(corners, color)


## Усечённый бокс — базовый примитив кузовов (порт taperedBox, carmodel.js:34).
## Верхняя грань может быть уже/короче нижней и смещена по Z, а передний и
## задний край верха — приподняты или опущены (капот, покатый багажник,
## наклон лобового стекла).
func tapered_box(center: Vector3, size: Vector3, color: Color,
		top_scale: Vector2 = Vector2.ONE, top_dz: float = 0.0,
		front_rise: float = 0.0, back_rise: float = 0.0,
		basis_rot: Basis = Basis.IDENTITY) -> void:
	var h := size * 0.5
	var tw := h.x * top_scale.x
	var td := h.z * top_scale.y
	var corners: Array[Vector3] = [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-tw, h.y + back_rise, -td + top_dz),
		Vector3(tw, h.y + back_rise, -td + top_dz),
		Vector3(tw, h.y + front_rise, td + top_dz),
		Vector3(-tw, h.y + front_rise, td + top_dz),
	]
	for i in corners.size():
		corners[i] = center + basis_rot * corners[i]
	_box_faces(corners, color)


## Грани по восьми углам: 0-3 низ (CCW сверху), 4-7 верх.
func _box_faces(c: Array[Vector3], color: Color) -> void:
	quad(c[7], c[6], c[5], c[4], color) # верх
	quad(c[0], c[1], c[2], c[3], color) # низ
	quad(c[3], c[2], c[6], c[7], color) # +Z
	quad(c[1], c[0], c[4], c[5], color) # -Z
	quad(c[2], c[1], c[5], c[6], color) # +X
	quad(c[0], c[3], c[7], c[4], color) # -X


## Цилиндр вдоль оси Y. segments=6..12 достаточно для low-poly.
func cylinder(center: Vector3, radius_top: float, radius_bottom: float,
		height: float, color: Color, segments: int = 8,
		basis_rot: Basis = Basis.IDENTITY, capped: bool = true) -> void:
	var hh := height * 0.5
	var prev_t := Vector3.ZERO
	var prev_b := Vector3.ZERO
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		var ca := cos(a)
		var sa := sin(a)
		var t := center + basis_rot * Vector3(ca * radius_top, hh, sa * radius_top)
		var b := center + basis_rot * Vector3(ca * radius_bottom, -hh, sa * radius_bottom)
		if i > 0:
			quad(prev_b, b, t, prev_t, color)
			if capped:
				if radius_top > 0.0001:
					tri(center + basis_rot * Vector3(0.0, hh, 0.0), prev_t, t, color)
				if radius_bottom > 0.0001:
					tri(center + basis_rot * Vector3(0.0, -hh, 0.0), b, prev_b, color)
		prev_t = t
		prev_b = b


func cone(center: Vector3, radius: float, height: float, color: Color,
		segments: int = 8, basis_rot: Basis = Basis.IDENTITY) -> void:
	cylinder(center, 0.0, radius, height, color, segments, basis_rot)


## Треугольная призма (двускатная крыша, фронтон, козырёк, клин).
## Основание лежит в плоскости XZ, конёк направлен вдоль оси Z.
func prism(center: Vector3, size: Vector3, color: Color,
		basis_rot: Basis = Basis.IDENTITY) -> void:
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	var hd := size.z * 0.5
	var c0 := center + basis_rot * Vector3(-hw, -hh, -hd)
	var c1 := center + basis_rot * Vector3(hw, -hh, -hd)
	var c2 := center + basis_rot * Vector3(hw, -hh, hd)
	var c3 := center + basis_rot * Vector3(-hw, -hh, hd)
	var t0 := center + basis_rot * Vector3(0.0, hh, -hd)
	var t1 := center + basis_rot * Vector3(0.0, hh, hd)

	quad(c0, c1, c2, c3, color) # основание (-Y)
	quad(c2, c1, t0, t1, color) # правый скат (+X, +Y)
	quad(c0, c3, t1, t0, color) # левый скат (-X, +Y)
	tri(c3, c2, t1, color)      # передний фронтон (+Z)
	tri(c1, c0, t0, color)      # задний фронтон (-Z)


## Гранёная «сфера» — икосаэдр-подобная форма для голов и крон деревьев.
## rings/segments малы намеренно: силуэт важнее гладкости.
func sphere(center: Vector3, radius: float, color: Color,
		rings: int = 5, segments: int = 8, squash: float = 1.0) -> void:
	for r in rings:
		var v0 := PI * float(r) / float(rings)
		var v1 := PI * float(r + 1) / float(rings)
		var y0 := cos(v0) * radius * squash
		var y1 := cos(v1) * radius * squash
		var r0 := sin(v0) * radius
		var r1 := sin(v1) * radius
		for s in segments:
			var u0 := TAU * float(s) / float(segments)
			var u1 := TAU * float(s + 1) / float(segments)
			var a := center + Vector3(cos(u0) * r0, y0, sin(u0) * r0)
			var b := center + Vector3(cos(u1) * r0, y0, sin(u1) * r0)
			var c := center + Vector3(cos(u1) * r1, y1, sin(u1) * r1)
			var d := center + Vector3(cos(u0) * r1, y1, sin(u0) * r1)
			if r == 0:
				tri(a, c, d, color)
			elif r == rings - 1:
				tri(a, b, c, color)
			else:
				quad(a, b, c, d, color)


## Горизонтальная плоскость (пол, крыша, дорожное полотно).
func plane_xz(center: Vector3, size: Vector2, color: Color) -> void:
	var h := size * 0.5
	quad(
		center + Vector3(-h.x, 0.0, -h.y),
		center + Vector3(-h.x, 0.0, h.y),
		center + Vector3(h.x, 0.0, h.y),
		center + Vector3(h.x, 0.0, -h.y),
		color)


## Лента по массиву точек заданной ширины — дорожное полотно серпантина,
## следы шин, разметка вдоль кривой.
func ribbon(points: PackedVector3Array, width: float, color: Color,
		y_offset: float = 0.0) -> void:
	if points.size() < 2:
		return
	var half := width * 0.5
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in points.size():
		var p := points[i] + Vector3(0.0, y_offset, 0.0)
		var dir: Vector3
		if i == 0:
			dir = points[1] - points[0]
		elif i == points.size() - 1:
			dir = points[i] - points[i - 1]
		else:
			dir = points[i + 1] - points[i - 1]
		dir.y = 0.0
		if dir.length_squared() < 1e-8:
			dir = Vector3.FORWARD
		var side := dir.normalized().cross(Vector3.UP) * half
		var l := p - side
		var r := p + side
		if i > 0:
			quad(prev_l, l, r, prev_r, color)
		prev_l = l
		prev_r = r
