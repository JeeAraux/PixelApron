extends RefCounted
## Baukasten für detaillierte Low-Poly-Modelle: sammelt Quader, Zylinder, Drehkörper und Prismen
## mit Farben pro Fläche in einem einzigen Mesh. Flache Normalen ergeben den kantigen Pixel-Look,
## und ein Modell mit hunderten Teilen kostet trotzdem nur einen Draw-Call.

static var _material: StandardMaterial3D

var st := SurfaceTool.new()
var count := 0


func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.9
		_material.metallic_specular = 0.25
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _material


## Dreieck; die Normale zeigt von center weg.
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, center: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - center) < 0.0:
		n = -n
		var t := b
		b = c
		c = t
	# Godot zählt Dreiecke im Uhrzeigersinn (von außen gesehen) als Vorderseite
	var t2 := b
	b = c
	c = t2
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(c)
	count += 1


## Dreieck unverändert übernehmen (Reihenfolge und Normale wie gegeben), z. B. beim Backen.
func tri_raw(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	for v: Vector3 in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v)
	count += 1


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, center: Vector3) -> void:
	tri(a, b, c, col, center)
	tri(a, c, d, col, center)


## Achsenparalleler Quader von a nach b, optional gedreht/verschoben über xf.
func box(a: Vector3, b: Vector3, col: Color, xf: Transform3D = Transform3D.IDENTITY) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var p := []
	for i in range(8):
		p.append(xf * Vector3(hi.x if i & 1 else lo.x, hi.y if i & 2 else lo.y, hi.z if i & 4 else lo.z))
	var c: Vector3 = xf * ((lo + hi) * 0.5)
	quad(p[0], p[1], p[3], p[2], col, c)  # -z
	quad(p[4], p[5], p[7], p[6], col, c)  # +z
	quad(p[0], p[1], p[5], p[4], col, c)  # -y
	quad(p[2], p[3], p[7], p[6], col, c)  # +y
	quad(p[0], p[2], p[6], p[4], col, c)  # -x
	quad(p[1], p[3], p[7], p[5], col, c)  # +x


## Zylinder oder Kegelstumpf von a nach b.
func cyl(a: Vector3, b: Vector3, r1: float, r2: float, col: Color, seg: int = 10, caps: bool = true, cap_col: Variant = null) -> void:
	var axis := b - a
	if axis.length() < 1e-5:
		return
	var w := axis.normalized()
	var u := w.cross(Vector3.UP if absf(w.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := w.cross(u)
	var center := (a + b) * 0.5
	var ra := []
	var rb := []
	for k in range(seg):
		var ang := TAU * float(k) / float(seg)
		var d := u * cos(ang) + v * sin(ang)
		ra.append(a + d * r1)
		rb.append(b + d * r2)
	for k in range(seg):
		var k2 := (k + 1) % seg
		quad(ra[k], ra[k2], rb[k2], rb[k], col, center)
	if caps:
		var cc: Color = cap_col if cap_col != null else col
		for k in range(seg):
			var k2 := (k + 1) % seg
			if r1 > 0.001:
				tri(a, ra[k], ra[k2], cc, center)
			if r2 > 0.001:
				tri(b, rb[k], rb[k2], cc, center)


## Drehkörper entlang z. rings: Array aus [z, mitte_y, radius_x, radius_y] (optional mitte_x).
## col_fn(z, x, dy, ry) liefert die Farbe einer Fläche, dy = Höhe über der Mittellinie.
func lathe(rings: Array, seg: int, col_fn: Callable, cap_front: bool = true, cap_back: bool = true, ox: float = 0.0) -> void:
	var pts := []
	for r: Array in rings:
		var row := []
		for k in range(seg):
			var ang := TAU * float(k) / float(seg)
			row.append(Vector3(ox + float(r[2]) * sin(ang), float(r[1]) + float(r[3]) * cos(ang), float(r[0])))
		pts.append(row)
	for i in range(rings.size() - 1):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		var c := Vector3(ox, (float(r0[1]) + float(r1[1])) * 0.5, (float(r0[0]) + float(r1[0])) * 0.5)
		for k in range(seg):
			var k2 := (k + 1) % seg
			var a: Vector3 = pts[i][k]
			var b: Vector3 = pts[i][k2]
			var cc: Vector3 = pts[i + 1][k2]
			var d: Vector3 = pts[i + 1][k]
			var m := (a + b + cc + d) * 0.25
			var col: Color = col_fn.call(m.z, m.x - ox, m.y - c.y, (float(r0[3]) + float(r1[3])) * 0.5)
			quad(a, b, cc, d, col, c)
	for e: Array in [[0, cap_front], [rings.size() - 1, cap_back]]:
		if not bool(e[1]):
			continue
		var i: int = e[0]
		var r: Array = rings[i]
		if float(r[2]) < 0.01:
			continue
		var c := Vector3(ox, float(r[1]), float(r[0]))
		var inner := Vector3(ox, float(r[1]), float(r[0]) + (0.1 if i == 0 else -0.1))
		var col: Color = col_fn.call(float(r[0]), 0.0, 0.0, float(r[3]))
		for k in range(seg):
			tri(c, pts[i][k], pts[i][(k + 1) % seg], col, inner)


## Prisma zwischen zwei konvexen Vielecken gleicher Eckenzahl (z. B. Flügel: unten und oben).
func prism(bottom: Array, top: Array, col: Color, side_col: Variant = null) -> void:
	var n := bottom.size()
	var center := Vector3.ZERO
	for p: Vector3 in bottom + top:
		center += p
	center /= float(n * 2)
	for i in range(1, n - 1):
		tri(bottom[0], bottom[i], bottom[i + 1], col, center)
		tri(top[0], top[i], top[i + 1], col, center)
	var sc: Color = side_col if side_col != null else col
	for i in range(n):
		var j := (i + 1) % n
		quad(bottom[i], bottom[j], top[j], top[i], sc, center)


## Flaches Viereck mit fester Blickrichtung (z. B. Fenster), leicht vor der Fläche.
func panel(c: Vector3, right: Vector3, up: Vector3, col: Color, normal: Vector3) -> void:
	var a := c - right - up
	var b := c + right - up
	var d := c - right + up
	var e := c + right + up
	quad(a, b, e, d, col, c - normal)


func commit() -> ArrayMesh:
	if count == 0:
		return ArrayMesh.new()
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	return mesh


func instance(name: String = "Modell") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = commit()
	return mi
