extends RefCounted
## Baukasten für detaillierte Modelle: sammelt Quader, Zylinder, Drehkörper und Prismen
## mit Farben pro Fläche in einem einzigen Mesh. Kanten bleiben scharf (flache Normalen),
## Rundungen (Rumpf, Triebwerke, Räder, Tanks) bekommen weiche Normalen.
## Alpha der Farbe markiert Leuchtflächen (siehe shaders/kit.gdshader): 0.6 Fenster, 0.3 Lampe.

const KIT_SHADER = preload("res://shaders/kit.gdshader")

static var _material: ShaderMaterial

var st := SurfaceTool.new()
var count := 0


func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = KIT_SHADER
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


## Dreieck mit eigenen Normalen je Ecke (weiche Rundung); Ausrichtung nach außen wie tri().
func tri_n(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color, center: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot((a + b + c) / 3.0 - center) < 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	var t2 := b
	b = c
	c = t2
	var tn2 := nb
	nb = nc
	nc = tn2
	for e: Array in [[a, na], [b, nb], [c, nc]]:
		st.set_color(col)
		st.set_normal(e[1])
		st.add_vertex(e[0])
	count += 1


## Dreieck unverändert übernehmen (Reihenfolge und Normale wie gegeben), z. B. beim Backen.
func tri_raw(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	for v: Vector3 in [a, b, c]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(v)
	count += 1


## Fertiges Baukasten-Mesh (z. B. ein Auto) mit Farben und Normalen einfügen. still = true
## nimmt Lampen und Scheiben das Leuchten (abgestellte Fahrzeuge).
func add_mesh(mesh: Mesh, xf: Transform3D, still: bool = false) -> void:
	for si in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var cols: PackedColorArray = PackedColorArray()
		if arr[Mesh.ARRAY_COLOR] != null:
			cols = arr[Mesh.ARRAY_COLOR]
		var idx: PackedInt32Array = PackedInt32Array()
		if arr[Mesh.ARRAY_INDEX] != null:
			idx = arr[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx.resize(verts.size())
			for i in range(verts.size()):
				idx[i] = i
		for i in idx:
			var c := cols[i] if cols.size() > i else Color.WHITE
			if still and c.a < 0.75:
				c = Color(c.r, c.g, c.b, 1.0) if c.a < 0.45 else Color(c.r * 0.8, c.g * 0.8, c.b * 0.8, 1.0)
			st.set_color(c)
			st.set_normal((xf.basis * norms[i]).normalized() if norms.size() > i else Vector3.UP)
			st.add_vertex(xf * verts[i])
		count += idx.size() / 3


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, center: Vector3) -> void:
	tri(a, b, c, col, center)
	tri(a, c, d, col, center)


func quad_n(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, col: Color, center: Vector3) -> void:
	tri_n(a, b, c, na, nb, nc, col, center)
	tri_n(a, c, d, na, nc, nd, col, center)


## Achsenparalleler Quader von a nach b, optional gedreht/verschoben über xf.
## Fasen: > 0 rundet alle Quader dieses Baukastens leicht ab (Fahrzeuge, Flugzeuge), damit keine
## harten Kanten entstehen. Der Radius ist höchstens ein Viertel der kleinsten Kantenlänge.
var bevel := 0.0


func box(a: Vector3, b: Vector3, col: Color, xf: Transform3D = Transform3D.IDENTITY) -> void:
	if bevel > 0.0 and xf == Transform3D.IDENTITY:
		var sz := (b - a).abs()
		var r := minf(bevel, minf(sz.x, minf(sz.y, sz.z)) * 0.25)
		if r > 0.008:
			soft_box(a, b, r, col, 8, 4)
			return
	_box_raw(a, b, col, xf)


func _box_raw(a: Vector3, b: Vector3, col: Color, xf: Transform3D = Transform3D.IDENTITY) -> void:
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


## Quader mit abgerundeten senkrechten Kanten (Radius r, steps Segmente je Ecke).
func rounded_box(a: Vector3, b: Vector3, r: float, col: Color, steps: int = 3, top_col: Variant = null) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	r = minf(r, minf(hi.x - lo.x, hi.z - lo.z) * 0.5)
	var ring := []
	var corners := [[hi.x - r, hi.z - r, 0.0], [lo.x + r, hi.z - r, PI * 0.5], [lo.x + r, lo.z + r, PI], [hi.x - r, lo.z + r, PI * 1.5]]
	for c: Array in corners:
		for i in range(steps + 1):
			var ang := float(c[2]) + PI * 0.5 * float(i) / float(steps)
			ring.append(Vector2(float(c[0]) + cos(ang) * r, float(c[1]) + sin(ang) * r))
	var center := (lo + hi) * 0.5
	var n := ring.size()
	var tc: Color = top_col if top_col != null else col
	for i in range(n):
		var p0: Vector2 = ring[i]
		var p1: Vector2 = ring[(i + 1) % n]
		var n0 := Vector3(p0.x - center.x, 0, p0.y - center.z).normalized()
		var n1 := Vector3(p1.x - center.x, 0, p1.y - center.z).normalized()
		quad_n(Vector3(p0.x, lo.y, p0.y), Vector3(p1.x, lo.y, p1.y), Vector3(p1.x, hi.y, p1.y), Vector3(p0.x, hi.y, p0.y),
			n0, n1, n1, n0, col, Vector3(center.x, (lo.y + hi.y) * 0.5, center.z))
		tri(Vector3(center.x, hi.y, center.z), Vector3(p0.x, hi.y, p0.y), Vector3(p1.x, hi.y, p1.y), tc, Vector3(center.x, lo.y, center.z))
		tri(Vector3(center.x, lo.y, center.z), Vector3(p0.x, lo.y, p0.y), Vector3(p1.x, lo.y, p1.y), col, Vector3(center.x, hi.y, center.z))


## Quader mit rundum gerundeten Kanten und Ecken (Radius r), weich schattiert: für Karosserien,
## Kabinen und Gehäuse, damit keine harten Kanten entstehen. Aus einer Kugel, deren Punkte auf den
## inneren Quader geklemmt und um r nach außen versetzt werden.
func soft_box(a: Vector3, b: Vector3, r: float, col: Color, seg: int = 16, rings: int = 8) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var size := hi - lo
	r = minf(r, minf(size.x, minf(size.y, size.z)) * 0.5 - 0.001)
	if r <= 0.005:
		_box_raw(a, b, col)
		return
	var ilo := lo + Vector3(r, r, r)
	var ihi := hi - Vector3(r, r, r)
	var c := (lo + hi) * 0.5
	seg = maxi(4, seg / 4 * 4)
	rings = maxi(2, rings / 2 * 2)
	# Spalten (Winkel um die Hochachse) und Zeilen (Winkel von oben): an den Achsen doppelt, je mit
	# einem kleinen Versatz, der entscheidet, auf welcher Seite des inneren Quaders der Punkt sitzt
	var cols := [[0.0, 0.001]]
	for kk in range(1, seg):
		var th := TAU * float(kk) / float(seg)
		if kk % (seg / 4) == 0:
			cols.append([th, -0.001])
			cols.append([th, 0.001])
		else:
			cols.append([th, 0.0])
	cols.append([TAU, -0.001])
	cols.append([TAU, 0.001])
	var rws := []
	for i in range(rings + 1):
		var phi := PI * float(i) / float(rings)
		if i == rings / 2:
			rws.append([phi, -0.001])
			rws.append([phi, 0.001])
		else:
			rws.append([phi, 0.0])
	var grid := []
	for rw: Array in rws:
		var row := []
		for cl: Array in cols:
			var phi: float = rw[0]
			var th: float = cl[0]
			var d := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th))
			var ph2 := phi + float(rw[1])
			var th2 := th + float(cl[1])
			var dh := Vector3(cos(th2), cos(ph2), sin(th2))
			var base := Vector3(ihi.x if dh.x > 0.0 else ilo.x, ihi.y if dh.y > 0.0 else ilo.y, ihi.z if dh.z > 0.0 else ilo.z)
			row.append([base + d * r, d])
		grid.append(row)
	for i in range(grid.size() - 1):
		for kk in range(cols.size() - 1):
			var p0: Array = grid[i][kk]
			var p1: Array = grid[i][kk + 1]
			var p2: Array = grid[i + 1][kk + 1]
			var p3: Array = grid[i + 1][kk]
			if (p0[0] as Vector3).distance_squared_to(p1[0]) < 1e-10 and (p3[0] as Vector3).distance_squared_to(p2[0]) < 1e-10:
				continue
			quad_n(p0[0], p1[0], p2[0], p3[0], p0[1], p1[1], p2[1], p3[1], col, c)
	# Deckel oben und unten (die Pole der Kugel spannen keine Fläche auf)
	for sy: float in [1.0, -1.0]:
		var y := hi.y if sy > 0.0 else lo.y
		var n := Vector3(0, sy, 0)
		quad_n(Vector3(ilo.x, y, ilo.z), Vector3(ihi.x, y, ilo.z), Vector3(ihi.x, y, ihi.z), Vector3(ilo.x, y, ihi.z), n, n, n, n, col, c)


## Zylinder oder Kegelstumpf von a nach b, Mantel weich schattiert.
func cyl(a: Vector3, b: Vector3, r1: float, r2: float, col: Color, seg: int = 14, caps: bool = true, cap_col: Variant = null) -> void:
	var axis := b - a
	if axis.length() < 1e-5:
		return
	var w := axis.normalized()
	var u := w.cross(Vector3.UP if absf(w.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := w.cross(u)
	var center := (a + b) * 0.5
	var ra := []
	var rb := []
	var nr := []
	var slope := (r1 - r2) / axis.length()
	for k in range(seg):
		var ang := TAU * float(k) / float(seg)
		var d := u * cos(ang) + v * sin(ang)
		ra.append(a + d * r1)
		rb.append(b + d * r2)
		nr.append((d + w * slope).normalized())
	for k in range(seg):
		var k2 := (k + 1) % seg
		quad_n(ra[k], ra[k2], rb[k2], rb[k], nr[k], nr[k2], nr[k2], nr[k], col, center)
	if caps:
		var cc: Color = cap_col if cap_col != null else col
		for k in range(seg):
			var k2 := (k + 1) % seg
			if r1 > 0.001:
				tri(a, ra[k], ra[k2], cc, center)
			if r2 > 0.001:
				tri(b, rb[k], rb[k2], cc, center)


## Kugel (oder Ellipsoid über scale), weich schattiert.
func sphere(c: Vector3, r: float, col: Color, seg: int = 12, rings: int = 7, scale: Vector3 = Vector3.ONE) -> void:
	var pts := []
	for i in range(rings + 1):
		var phi := PI * float(i) / float(rings)
		var row := []
		for k in range(seg):
			var th := TAU * float(k) / float(seg)
			row.append(Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th)))
		pts.append(row)
	for i in range(rings):
		for k in range(seg):
			var k2 := (k + 1) % seg
			var d0: Vector3 = pts[i][k]
			var d1: Vector3 = pts[i][k2]
			var d2: Vector3 = pts[i + 1][k2]
			var d3: Vector3 = pts[i + 1][k]
			quad_n(c + d0 * r * scale, c + d1 * r * scale, c + d2 * r * scale, c + d3 * r * scale,
				(d0 / scale).normalized(), (d1 / scale).normalized(), (d2 / scale).normalized(), (d3 / scale).normalized(), col, c)


## Drehkörper entlang z. rings: Array aus [z, mitte_y, radius_x, radius_y] (optional mitte_x).
## col_fn(z, x, dy, ry) liefert die Farbe einer Fläche, dy = Höhe über der Mittellinie.
## Die Haut wird weich schattiert (Normalen über die Nachbarflächen gemittelt).
func lathe(rings: Array, seg: int, col_fn: Callable, cap_front: bool = true, cap_back: bool = true, ox: float = 0.0) -> void:
	var pts := []
	for r: Array in rings:
		var row := []
		for k in range(seg):
			var ang := TAU * float(k) / float(seg)
			row.append(Vector3(ox + float(r[2]) * sin(ang), float(r[1]) + float(r[3]) * cos(ang), float(r[0])))
		pts.append(row)
	var nrm := []
	for i in range(rings.size()):
		var row := []
		for k in range(seg):
			row.append(Vector3.ZERO)
		nrm.append(row)
	for i in range(rings.size() - 1):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		var c := Vector3(ox, (float(r0[1]) + float(r1[1])) * 0.5, (float(r0[0]) + float(r1[0])) * 0.5)
		for k in range(seg):
			var k2 := (k + 1) % seg
			var a: Vector3 = pts[i][k]
			var b: Vector3 = pts[i][k2]
			var d: Vector3 = pts[i + 1][k]
			var fn := (b - a).cross(d - a)
			if fn.length_squared() < 1e-12:
				fn = (a + b) * 0.5 - c
			if fn.dot((a + b + d) / 3.0 - c) < 0.0:
				fn = -fn
			fn = fn.normalized()
			for e: Array in [[i, k], [i, k2], [i + 1, k], [i + 1, k2]]:
				nrm[e[0]][e[1]] += fn
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
			quad_n(a, b, cc, d, (nrm[i][k] as Vector3).normalized(), (nrm[i][k2] as Vector3).normalized(),
				(nrm[i + 1][k2] as Vector3).normalized(), (nrm[i + 1][k] as Vector3).normalized(), col, c)
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


## Freiformfläche aus Querschnitten (Rumpf, Flügel, Karosserie): rings ist eine Liste gleich langer
## Punktlisten. Normalen werden über die Nachbarflächen gemittelt (weich), außer an Punkten, die
## doppelt hintereinander stehen (dort bleibt eine Kante, z. B. Flügelhinterkante, Farbgrenze).
## col_fn(Mitte: Vector3, i: int, j: int) -> Color färbt jedes Viereck. closed: Ring schließt sich.
## cap0/cap1: Enden mit einem Fächer zum Mittelpunkt schließen.
func loft(rings: Array, col_fn: Callable, closed: bool = true, cap0: bool = false, cap1: bool = false) -> void:
	var nr := rings.size()
	if nr < 2:
		return
	var np: int = (rings[0] as PackedVector3Array).size()
	var nseg := np if closed else np - 1
	# Flächennormalen in Laufrichtung (i: entlang, j: um den Ring)
	var nrm := []
	for i in range(nr):
		var row := []
		row.resize(np)
		row.fill(Vector3.ZERO)
		nrm.append(row)
	var fns := []
	for i in range(nr - 1):
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[i + 1]
		var frow := []
		for j in range(nseg):
			var j2 := (j + 1) % np
			var d1 := (r0[j2] - r0[j]) + (r1[j2] - r1[j])
			var d2 := (r1[j] - r0[j]) + (r1[j2] - r0[j2])
			var fn := d1.cross(d2)
			frow.append(fn)
			if fn.length_squared() < 1e-12:
				continue
			fn = fn.normalized()
			for e: Array in [[i, j], [i, j2], [i + 1, j], [i + 1, j2]]:
				nrm[e[0]][e[1]] += fn
		fns.append(frow)
	# Ausrichtung: zeigen die Normalen überwiegend zur Mitte, umdrehen
	var cen := Vector3.ZERO
	var cnt := 0
	for r: PackedVector3Array in rings:
		for q: Vector3 in r:
			cen += q
			cnt += 1
	cen /= float(cnt)
	var score := 0.0
	for i in range(nr - 1):
		for j in range(nseg):
			var mid: Vector3 = ((rings[i] as PackedVector3Array)[j] + (rings[i + 1] as PackedVector3Array)[j]) * 0.5
			score += (fns[i][j] as Vector3).dot(mid - cen)
	var flip := score < 0.0
	# harte Kanten an doppelten Punkten im Ring: Normale nur von der eigenen Seite
	for i in range(nr):
		var r: PackedVector3Array = rings[i]
		for j in range(np):
			var jn := (j + 1) % np
			if (closed or j < np - 1) and r[j].distance_squared_to(r[jn]) < 1e-10:
				var a := Vector3.ZERO
				var b := Vector3.ZERO
				for ii: int in [i - 1, i]:
					if ii < 0 or ii >= nr - 1:
						continue
					var jp := (j - 1 + np) % np
					if closed or j > 0:
						var f1: Vector3 = fns[ii][jp] if jp < nseg else Vector3.ZERO
						if f1.length_squared() > 1e-12:
							a += f1.normalized()
					var jq := (jn + 1) % np
					if jn < nseg and (closed or jn < np - 1):
						var f2: Vector3 = fns[ii][jn]
						if f2.length_squared() > 1e-12:
							b += f2.normalized()
				nrm[i][j] = a
				nrm[i][jn] = b
	for i in range(nr - 1):
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[i + 1]
		for j in range(nseg):
			var fn: Vector3 = fns[i][j]
			if fn.length_squared() < 1e-12:
				continue
			var j2 := (j + 1) % np
			var na: Vector3 = nrm[i][j]
			var nb: Vector3 = nrm[i][j2]
			var nc: Vector3 = nrm[i + 1][j2]
			var nd: Vector3 = nrm[i + 1][j]
			var o := fn.normalized() * (-1.0 if flip else 1.0)
			var m := (r0[j] + r0[j2] + r1[j] + r1[j2]) * 0.25
			var col: Color = col_fn.call(m, i, j)
			var ns := []
			for nn: Vector3 in [na, nb, nc, nd]:
				var u := nn * (-1.0 if flip else 1.0)
				ns.append(u.normalized() if u.length_squared() > 1e-12 else o)
			quad_n(r0[j], r0[j2], r1[j2], r1[j], ns[0], ns[1], ns[2], ns[3], col, m - o)
	for e: Array in [[0, cap0, 1], [nr - 1, cap1, nr - 2]]:
		if not bool(e[1]):
			continue
		var r: PackedVector3Array = rings[e[0]]
		var c := Vector3.ZERO
		for q: Vector3 in r:
			c += q
		c /= float(r.size())
		var inner: Vector3 = c + ((rings[e[2]] as PackedVector3Array)[0] - r[0]) * 0.1 + (c - cen) * -0.0
		var other_c := Vector3.ZERO
		for q: Vector3 in (rings[e[2]] as PackedVector3Array):
			other_c += q
		other_c /= float(r.size())
		var col: Color = col_fn.call(c, int(e[0]), -1)
		for j in range(nseg):
			tri(c, r[j], r[(j + 1) % np], col, other_c)


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
