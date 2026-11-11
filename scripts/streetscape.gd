extends RefCounted
## Straßenraum neben der Fahrbahn: Hochbord, Gehweg, Radweg, Grünstreifen mit Bäumen, Laternen
## und Haltebuchten (Bus, Taxi, Kiss & Fly). Gezeichnet wird je Straßenseite ein Band, dessen
## Innenkante an Haltebuchten nach außen springt (dort liegt die Bucht auf Fahrbahnhöhe).
##
## Querschnitte (Catalog.SIDES): "ohne" nur Fahrbahn, "gehweg" Hochbord und Gehweg,
## "rad" Sicherheitsstreifen, roter Radweg und Gehweg, "allee" Grünstreifen mit Bäumen und Gehweg.
## UV.x = Abstand von der Fahrbahnkante (m), UV.y = Meter entlang, UV2 = (Abstand zur Innenkante,
## Abstand zur Außenkante) – line.gdshader mark 12 malt daraus die Schichten.

const Catalog = preload("res://scripts/catalog.gd")
const Kit = preload("res://scripts/mesh_kit.gd")
const PixelFont = preload("res://scripts/pixel_font.gd")
const LINE_SHADER = preload("res://shaders/line.gdshader")
const POOL_SHADER = preload("res://shaders/pool.gdshader")

const TOP := 0.16            # Oberkante Bordstein und Gehweg (Fahrbahn liegt bei 0,06)
const TAPER := 7.0           # Länge der Ein- und Ausfahrt einer Haltebucht
const PLATFORM := 2.2        # Wartefläche hinter einer Bucht
const ASPHALT := Color(0.23, 0.225, 0.21)
const CURB := Color(0.62, 0.62, 0.6)
const STEEL := Color(0.4, 0.43, 0.46)
const KINDS := {"ohne": 0, "gehweg": 1, "rad": 2, "allee": 3}

static var _materials: Dictionary = {}
static var _pool_mat: ShaderMaterial


static func width_of(side: String) -> float:
	return float((Catalog.SIDES.get(side, Catalog.SIDES["ohne"]) as Dictionary)["w"])


static func material(side: String) -> ShaderMaterial:
	var k: int = KINDS.get(side, 1)
	if not _materials.has(k):
		var sm := ShaderMaterial.new()
		sm.shader = LINE_SHADER
		sm.set_shader_parameter("mark", 12)
		sm.set_shader_parameter("base_color", Color(0.62, 0.6, 0.56))
		sm.set_shader_parameter("side_kind", maxi(k, 1))
		_materials[k] = sm
	return _materials[k]


## Tiefe der Bucht an Stelle s (0 außerhalb, sanft ein- und ausgefahren).
static func _bay_depth(bays: Array, sg: int, s: float) -> float:
	var best := 0.0
	for b: Array in bays:
		if int(b[0]) != sg:
			continue
		var s0: float = b[1]
		var s1: float = b[2]
		if s <= s0 or s >= s1:
			continue
		var f := minf(clampf((s - s0) / TAPER, 0.0, 1.0), clampf((s1 - s) / TAPER, 0.0, 1.0))
		best = maxf(best, float(b[3]) * smoothstep(0.0, 1.0, f))
	return best


## Seitenraum einer Straße. sub: Mittellinie (an Kreuzungen zurückgenommen), w: Fahrbahnbreite,
## y: Fahrbahnhöhe, bays: [[Seite ±1, s0, s1, Tiefe, Aufschrift]] in Metern entlang sub.
static func build(sub: PackedVector3Array, w: float, side: String, y: float, bays: Array = [], lift: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Seitenraum"
	var n := sub.size()
	if n < 2:
		return root
	var v := width_of(side)
	var top := TOP + lift
	var hw := w * 0.5
	var cum := PackedFloat32Array([0.0])
	var nrm := PackedVector3Array()
	for i in range(n):
		if i > 0:
			cum.append(cum[i - 1] + Vector2(sub[i].x - sub[i - 1].x, sub[i].z - sub[i - 1].z).length())
		var t := sub[mini(i + 1, n - 1)] - sub[maxi(i - 1, 0)]
		t.y = 0.0
		nrm.append(t.normalized().cross(Vector3.UP) if t.length() > 0.001 else Vector3.RIGHT)
	var length := cum[n - 1]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := Kit.new()
	var verts := 0
	for sg: int in [1, -1]:
		var inner := PackedFloat32Array()
		var outer := PackedFloat32Array()
		var bay := PackedFloat32Array()
		for i in range(n):
			var b := _bay_depth(bays, sg, cum[i])
			bay.append(b)
			inner.append(hw + b)
			outer.append(hw + maxf(v, b + PLATFORM * minf(1.0, b / 0.8)))
		for i in range(n - 1):
			var j := i + 1
			var ni := nrm[i] * float(sg)
			var nj := nrm[j] * float(sg)
			var ci := Vector3(sub[i].x, sub[i].y, sub[i].z)
			var cj := Vector3(sub[j].x, sub[j].y, sub[j].z)
			var road_y := y + sub[i].y
			var ii := ci + ni * inner[i]
			var ij := cj + nj * inner[j]
			var oi := ci + ni * outer[i]
			var oj := cj + nj * outer[j]
			if outer[i] - inner[i] > 0.04 or outer[j] - inner[j] > 0.04:
				var q := [[ii, inner[i] - hw, 0.0, outer[i] - inner[i], cum[i]], [oi, outer[i] - hw, outer[i] - inner[i], 0.0, cum[i]],
					[ij, inner[j] - hw, 0.0, outer[j] - inner[j], cum[j]], [oj, outer[j] - hw, outer[j] - inner[j], 0.0, cum[j]]]
				for idx: int in [0, 1, 2, 1, 3, 2]:
					var e: Array = q[idx]
					var p: Vector3 = e[0]
					st.set_normal(Vector3.UP)
					st.set_uv(Vector2(float(e[1]), float(e[4])))
					st.set_uv2(Vector2(float(e[2]), float(e[3])))
					st.add_vertex(Vector3(p.x, top + sub[i].y, p.z))
				verts += 6
				# Bordsteinkante zur Fahrbahn, Böschungskante außen
				k.quad(Vector3(ii.x, road_y, ii.z), Vector3(ij.x, road_y, ij.z), Vector3(ij.x, top + sub[i].y, ij.z), Vector3(ii.x, top + sub[i].y, ii.z),
					CURB, ii + ni * 0.5 + Vector3(0, -1, 0))
				k.quad(Vector3(oi.x, top + sub[i].y, oi.z), Vector3(oj.x, top + sub[i].y, oj.z), Vector3(oj.x, sub[i].y - 0.02, oj.z), Vector3(oi.x, sub[i].y - 0.02, oi.z),
					Color(0.5, 0.48, 0.42), oi - ni * 0.5 + Vector3(0, -1, 0))
			# Haltebucht: Asphalt auf Fahrbahnhöhe, verdeckt die Randlinie der Fahrbahn
			if bay[i] > 0.02 or bay[j] > 0.02:
				var ai := ci + ni * (hw - 0.75)
				var aj := cj + nj * (hw - 0.75)
				var by := road_y + 0.004
				k.quad(Vector3(ai.x, by, ai.z), Vector3(aj.x, by, aj.z), Vector3(ij.x, by, ij.z), Vector3(ii.x, by, ii.z), ASPHALT, ci + Vector3(0, -5, 0))
		_bay_marks(k, sub, cum, nrm, bays, sg, hw, y)
	if verts > 0:
		var mi := MeshInstance3D.new()
		mi.name = "Gehweg"
		mi.mesh = st.commit()
		mi.material_override = material(side if side != "ohne" else "gehweg")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var lamps := _furniture(k, sub, cum, nrm, bays, side, hw, v, top, length)
	if k.count > 0:
		var km := k.instance("Strassenmoebel")
		root.add_child(km)
	if not lamps.is_empty():
		root.add_child(_pools(lamps))
	return root


## Lichtkreise aller Leuchten einer Straße in einem Mesh (nachts sichtbar).
static func _pools(spots: Array) -> MeshInstance3D:
	if _pool_mat == null:
		_pool_mat = ShaderMaterial.new()
		_pool_mat.shader = POOL_SHADER
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := 7.0
	for c: Vector3 in spots:
		var pts := [c + Vector3(-r, 0, -r), c + Vector3(r, 0, -r), c + Vector3(r, 0, r), c + Vector3(-r, 0, r)]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for i: int in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[i])
			st.add_vertex(pts[i])
	var mi := MeshInstance3D.new()
	mi.name = "Lichtkreise"
	mi.mesh = st.commit()
	mi.material_override = _pool_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Markierung der Buchten: unterbrochene breite Randlinie, gelbe Zickzacklinie, Aufschrift.
static func _bay_marks(k: Kit, sub: PackedVector3Array, cum: PackedFloat32Array, nrm: PackedVector3Array, bays: Array,
		sg: int, hw: float, y: float) -> void:
	for b: Array in bays:
		if int(b[0]) != sg:
			continue
		var s0: float = float(b[1]) + TAPER
		var s1: float = float(b[2]) - TAPER
		var depth: float = b[3]
		if s1 - s0 < 3.0:
			continue
		var my := y + 0.012
		# breite Leitlinie zwischen Fahrstreifen und Bucht
		var s := float(b[1]) + 2.0
		while s < float(b[2]) - 2.0:
			var p0 := _at(sub, cum, nrm, s, sg, hw - 0.4)
			var p1 := _at(sub, cum, nrm, minf(s + 1.5, float(b[2]) - 2.0), sg, hw - 0.4)
			_strip(k, p0, p1, 0.25, my, Color(0.9, 0.9, 0.86))
			s += 3.0
		# Zickzacklinie im Haltebereich
		var zs := s0
		var out := false
		var last := _at(sub, cum, nrm, zs, sg, hw + 0.4)
		while zs < s1 - 0.01:
			zs = minf(zs + 1.6, s1)
			out = not out
			var p := _at(sub, cum, nrm, zs, sg, hw + (depth - 0.4 if out else 0.4))
			_strip(k, last, p, 0.16, my, Color(0.93, 0.76, 0.18))
			last = p
		# Aufschrift, in Fahrtrichtung lesbar
		var label: String = b[4]
		if label != "":
			var mid := (s0 + s1) * 0.5
			var c := _at(sub, cum, nrm, mid, sg, hw + depth * 0.5)
			var fwd := _at(sub, cum, nrm, mid + 1.0, sg, hw) - _at(sub, cum, nrm, mid, sg, hw)
			fwd = fwd * float(sg)   # Fahrtrichtung auf dieser Seite (Rechtsverkehr)
			PixelFont.draw_ground(k, label, Vector3(c.x, my + 0.002, c.z), fwd, 0.22, Color(0.92, 0.92, 0.88))


static func _strip(k: Kit, a: Vector3, b: Vector3, wd: float, y: float, col: Color) -> void:
	var d := Vector3(b.x - a.x, 0, b.z - a.z)
	if d.length() < 0.02:
		return
	var s := d.normalized().cross(Vector3.UP) * wd * 0.5
	k.quad(Vector3(a.x, y, a.z) - s, Vector3(b.x, y, b.z) - s, Vector3(b.x, y, b.z) + s, Vector3(a.x, y, a.z) + s, col, Vector3(a.x, y - 5.0, a.z))


## Punkt bei Meter s entlang sub, off Meter zur Seite sg.
static func _at(sub: PackedVector3Array, cum: PackedFloat32Array, nrm: PackedVector3Array, s: float, sg: int, off: float) -> Vector3:
	var n := sub.size()
	s = clampf(s, 0.0, cum[n - 1])
	var i := 0
	while i < n - 2 and cum[i + 1] < s:
		i += 1
	var seg := maxf(cum[i + 1] - cum[i], 0.001)
	var f := clampf((s - cum[i]) / seg, 0.0, 1.0)
	var p := sub[i].lerp(sub[i + 1], f)
	var nn := nrm[i].lerp(nrm[i + 1], f).normalized()
	return p + nn * float(sg) * off


## Bäume, Laternen und Poller entlang der Straße (nicht in Buchten und nicht direkt an Kreuzungen).
static func _furniture(k: Kit, sub: PackedVector3Array, cum: PackedFloat32Array, nrm: PackedVector3Array, bays: Array,
		side: String, hw: float, v: float, top: float, length: float) -> Array:
	var spots := []
	if side == "ohne" or length < 10.0:
		return spots
	var lamp_off := hw + v - 0.45
	if side == "rad":
		lamp_off = hw + 0.6
	var step := 34.0 if side != "allee" else 36.0
	var s := 6.0 + fmod(absf(sub[0].x * 0.37 + sub[0].z * 0.61), 8.0)
	var sg := 1
	while s < length - 5.0:
		if _bay_depth(bays, sg, s) <= 0.0 and _bay_depth(bays, sg, s - 4.0) <= 0.0 and _bay_depth(bays, sg, s + 4.0) <= 0.0:
			var p := _at(sub, cum, nrm, s, sg, lamp_off)
			var toward := (_at(sub, cum, nrm, s, sg, 0.0) - p)
			toward.y = 0.0
			_lamp(k, Vector3(p.x, top + p.y, p.z), toward.normalized(), side == "rad")
			var lit := p + toward.normalized() * (2.0 if side != "rad" else 2.8)
			spots.append(Vector3(lit.x, top + p.y + 0.05, lit.z))
		sg = -sg
		s += step * 0.5
	if side == "allee":
		var rng := RandomNumberGenerator.new()
		rng.seed = int(absf(sub[0].x * 131.0 + sub[0].z * 17.0)) + sub.size()
		for tsg: int in [1, -1]:
			var ts := 5.0 + (0.0 if tsg == 1 else 6.0)
			while ts < length - 4.0:
				if _bay_depth(bays, tsg, ts) <= 0.0 and absf(fmod(ts - 6.0 - fmod(absf(sub[0].x * 0.37 + sub[0].z * 0.61), 8.0), 18.0)) > 2.5:
					var tp := _at(sub, cum, nrm, ts, tsg, hw + 1.4)
					_tree(k, Vector3(tp.x, top + tp.y, tp.z), rng)
				ts += 12.0
	return spots


## Straßenleuchte: schlanker Mast, Ausleger über die Fahrbahn, LED-Kopf (leuchtet nachts).
static func _lamp(k: Kit, base: Vector3, toward: Vector3, short: bool) -> void:
	var h := 7.2 if not short else 6.4
	var reach := 1.6 if not short else 2.4
	k.cyl(base, base + Vector3(0, 0.35, 0), 0.13, 0.11, STEEL.darkened(0.25), 8)
	k.cyl(base + Vector3(0, 0.35, 0), base + Vector3(0, h, 0), 0.075, 0.05, STEEL, 8)
	var tip := base + Vector3(0, h + 0.25, 0) + toward * reach
	k.cyl(base + Vector3(0, h - 0.05, 0), tip, 0.045, 0.04, STEEL, 6)
	var right := toward.cross(Vector3.UP).normalized()
	var xf := Transform3D(Basis(right, Vector3.UP, toward), tip)
	k.box(Vector3(-0.17, -0.14, -0.1), Vector3(0.17, 0.02, 0.75), Color(0.3, 0.32, 0.34), xf)
	k.box(Vector3(-0.13, -0.16, -0.02), Vector3(0.13, -0.14, 0.68), Color(0.98, 0.9, 0.66, 0.3), xf)


## Straßenbaum mit Baumscheibe: Stamm, Astansätze, Krone aus Kugeln (Laub wiegt sich, Alpha 0.8).
static func _tree(k: Kit, base: Vector3, rng: RandomNumberGenerator) -> void:
	var s := rng.randf_range(0.8, 1.05)
	k.box(base + Vector3(-0.7, -0.01, -0.7), base + Vector3(0.7, 0.012, 0.7), Color(0.33, 0.26, 0.19))
	k.cyl(base, base + Vector3(0, 3.0 * s, 0), 0.22, 0.16, Color(0.33, 0.25, 0.18), 7)
	var g := Color.from_hsv(rng.randf_range(0.22, 0.3), rng.randf_range(0.45, 0.6), rng.randf_range(0.34, 0.44))
	var leaf := Color(g.r, g.g, g.b, 0.8)
	k.sphere(base + Vector3(0, 4.4 * s, 0), 1.9 * s, leaf, 10, 6)
	for i in range(3):
		var off := Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(3.9, 5.4) * s, rng.randf_range(-1.2, 1.2))
		k.sphere(base + off, rng.randf_range(1.0, 1.4) * s, Color(leaf.r, leaf.g, leaf.b, 0.8).lightened(rng.randf() * 0.07), 9, 5)


## Ecke an einer Kreuzung: Gehwegband entlang des Bordsteinbogens (arc, nrm_out zeigen nach außen),
## Breite gleitet von wa auf wb. side bestimmt die Schichten.
static func corner(arc: Array, outs: Array, wa: float, wb: float, side: String, y: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := arc.size()
	var run := 0.0
	var verts := 0
	var k := Kit.new()
	# Außenkante: die geraden Außenkanten beider Straßen bis zu ihrem Schnittpunkt P (eckiger Abschluss wie an
	# echten Ecken). Jeder Punkt des Bordsteinbogens reicht entlang seiner Normalen bis zu dieser Kante; so
	# überschlägt sich das Band bei engen Bögen nicht (keine Zacken).
	var widths := PackedFloat32Array()
	var q0: Vector3 = (arc[0] as Vector3) + (outs[0] as Vector3) * wa
	var qn: Vector3 = (arc[n - 1] as Vector3) + (outs[n - 1] as Vector3) * wb
	var d0: Vector3 = ((arc[mini(1, n - 1)] as Vector3) - (arc[0] as Vector3))
	var dn: Vector3 = ((arc[n - 1] as Vector3) - (arc[maxi(n - 2, 0)] as Vector3))
	d0.y = 0.0
	dn.y = 0.0
	var pc: Variant = null
	if d0.length() > 0.001 and dn.length() > 0.001:
		pc = Geometry2D.line_intersects_line(Vector2(q0.x, q0.z), Vector2(d0.x, d0.z).normalized(), Vector2(qn.x, qn.z), Vector2(dn.x, dn.z).normalized())
	for i in range(n):
		var fi := float(i) / float(maxi(n - 1, 1))
		var wdef := lerpf(wa, wb, fi)
		var a2 := Vector2((arc[i] as Vector3).x, (arc[i] as Vector3).z)
		var n2 := Vector2((outs[i] as Vector3).x, (outs[i] as Vector3).z)
		var best := wdef
		if pc != null:
			var p2: Vector2 = pc
			best = INF
			for sg: Array in [[Vector2(q0.x, q0.z), p2], [p2, Vector2(qn.x, qn.z)]]:
				var hit: Variant = Geometry2D.segment_intersects_segment(a2, a2 + n2 * 60.0, (sg[0] as Vector2) - ((sg[1] as Vector2) - (sg[0] as Vector2)).normalized() * 0.05, (sg[1] as Vector2) + ((sg[1] as Vector2) - (sg[0] as Vector2)).normalized() * 0.05)
				if hit != null:
					best = minf(best, a2.distance_to(hit))
			if best == INF or best > maxf(wa, wb) * 3.0:
				best = wdef
		widths.append(best)
	for i in range(n - 1):
		var a: Vector3 = arc[i]
		var b: Vector3 = arc[i + 1]
		var na: Vector3 = outs[i]
		var nb: Vector3 = outs[i + 1]
		var wa_i := widths[i]
		var wb_i := widths[i + 1]
		var seg := a.distance_to(b)
		if wa_i < 0.35 and wb_i < 0.35:
			run += seg
			continue
		var q := [[a + na * 0.3, 0.3, 0.3, wa_i - 0.3, run], [a + na * wa_i, wa_i, wa_i, 0.0, run],
			[b + nb * 0.3, 0.3, 0.3, wb_i - 0.3, run + seg], [b + nb * wb_i, wb_i, wb_i, 0.0, run + seg]]
		for idx: int in [0, 1, 2, 1, 3, 2]:
			var e: Array = q[idx]
			var p: Vector3 = e[0]
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(float(e[1]), float(e[4])))
			st.set_uv2(Vector2(float(e[2]), float(e[3])))
			# etwas über den Seitenbändern der Straßen, sonst flimmert die Ecke (gleiche Höhe)
			st.add_vertex(Vector3(p.x, y + 0.008, p.z))
		verts += 6
		var oa := a + na * wa_i
		var ob := b + nb * wb_i
		k.quad(Vector3(oa.x, y, oa.z), Vector3(ob.x, y, ob.z), Vector3(ob.x, -0.02, ob.z), Vector3(oa.x, -0.02, oa.z),
			Color(0.5, 0.48, 0.42), oa - na + Vector3(0, -1, 0))
		run += seg
	if verts == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Ecke"
	mi.mesh = st.commit()
	mi.material_override = material(side)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if k.count > 0:
		mi.add_child(k.instance("Kante"))
	return mi


## Fahrrad mit Rahmen, Speichenrädern, Lenker und Sattel (Fahrtrichtung -Z, Mitte zwischen den Achsen).
static func bike_mesh(col: Color) -> ArrayMesh:
	var k := Kit.new()
	var tire := Color(0.1, 0.1, 0.11)
	var rim := Color(0.7, 0.72, 0.74)
	for z: float in [-0.52, 0.52]:
		k.cyl(Vector3(-0.025, 0.34, z), Vector3(0.025, 0.34, z), 0.34, 0.34, tire, 16)
		k.cyl(Vector3(-0.03, 0.34, z), Vector3(0.03, 0.34, z), 0.27, 0.27, rim, 16)
		k.cyl(Vector3(-0.035, 0.34, z), Vector3(0.035, 0.34, z), 0.24, 0.24, Color(0.2, 0.2, 0.22, 1.0), 16)
	var bb := Vector3(0, 0.32, 0.02)
	var seat := Vector3(0, 0.86, 0.22)
	var head := Vector3(0, 0.84, -0.4)
	for seg: Array in [[bb, seat], [bb, head], [seat, head], [bb, Vector3(0, 0.34, 0.52)], [seat, Vector3(0, 0.34, 0.52)],
			[head, Vector3(0, 0.34, -0.52)]]:
		k.cyl(seg[0], seg[1], 0.025, 0.025, col, 6)
	k.cyl(head, head + Vector3(0, 0.18, 0.05), 0.022, 0.022, STEEL, 6)
	k.cyl(head + Vector3(-0.25, 0.18, 0.05), head + Vector3(0.25, 0.18, 0.05), 0.02, 0.02, Color(0.15, 0.15, 0.15), 6)
	k.box(seat + Vector3(-0.07, 0.0, -0.12), seat + Vector3(0.07, 0.05, 0.08), Color(0.12, 0.12, 0.12))
	k.box(Vector3(-0.1, 0.36, -0.62), Vector3(0.1, 0.42, -0.58), Color(1.0, 0.95, 0.8, 0.3))
	return k.commit()
