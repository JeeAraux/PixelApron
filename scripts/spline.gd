extends RefCounted
## Kurven-Werkzeuge: Catmull-Rom durch die geklickten Punkte, gleichmäßige
## Stützpunkte im Meterabstand, engster Radius und das Band-Mesh für Wege.


## Liefert Stützpunkte im Abstand von 1 m entlang des Weges.
static func path(points: Array, straight: bool) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for p: Vector3 in points:
		pts.append(Vector3(p.x, 0.0, p.z))
	if pts.size() < 2:
		return pts
	if straight:
		var line := PackedVector3Array([pts[0], pts[pts.size() - 1]])
		return resample(line, 1.0)
	return resample(rounded(pts), 1.0)


## Gerade Stücke zwischen den Klickpunkten, jede Ecke wird so weit wie möglich ausgerundet.
## So bleiben lange Geraden gerade und die Kurven lassen sich gut vorhersagen.
static func rounded(pts: PackedVector3Array) -> PackedVector3Array:
	var n := pts.size()
	var out := PackedVector3Array([pts[0]])
	for i in range(1, n - 1):
		var prev := pts[i - 1]
		var cur := pts[i]
		var nxt := pts[i + 1]
		var la := prev.distance_to(cur)
		var lb := cur.distance_to(nxt)
		if la < 0.01 or lb < 0.01:
			continue
		var fa := 1.0 if i == 1 else 0.5
		var fb := 1.0 if i == n - 2 else 0.5
		var t := minf(la * fa, lb * fb)
		var a := cur + (prev - cur) / la * t
		var b := cur + (nxt - cur) / lb * t
		var steps := maxi(4, ceili(t * 2.0 / 2.0))
		for k in range(steps + 1):
			var u := float(k) / float(steps)
			out.append(a.lerp(cur, u).lerp(cur.lerp(b, u), u))
	out.append(pts[n - 1])
	return out


static func catmull_dense(pts: PackedVector3Array) -> PackedVector3Array:
	var dense := PackedVector3Array()
	var n := pts.size()
	for i in range(n - 1):
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p0: Vector3 = pts[i - 1] if i > 0 else p1 + (p1 - p2)
		var p3: Vector3 = pts[i + 2] if i + 2 < n else p2 + (p2 - p1)
		var steps := maxi(2, ceili(p1.distance_to(p2) / 0.5))
		for s in range(steps):
			dense.append(_centripetal(p0, p1, p2, p3, float(s) / float(steps)))
	dense.append(pts[n - 1])
	return dense


static func _centripetal(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t0 := 0.0
	var t1 := t0 + sqrt(maxf(p0.distance_to(p1), 0.001))
	var t2 := t1 + sqrt(maxf(p1.distance_to(p2), 0.001))
	var t3 := t2 + sqrt(maxf(p2.distance_to(p3), 0.001))
	var tt := lerpf(t1, t2, t)
	var a1 := p0 * (t1 - tt) / (t1 - t0) + p1 * (tt - t0) / (t1 - t0)
	var a2 := p1 * (t2 - tt) / (t2 - t1) + p2 * (tt - t1) / (t2 - t1)
	var a3 := p2 * (t3 - tt) / (t3 - t2) + p3 * (tt - t2) / (t3 - t2)
	var b1 := a1 * (t2 - tt) / (t2 - t0) + a2 * (tt - t0) / (t2 - t0)
	var b2 := a2 * (t3 - tt) / (t3 - t1) + a3 * (tt - t1) / (t3 - t1)
	return b1 * (t2 - tt) / (t2 - t1) + b2 * (tt - t1) / (t2 - t1)


static func resample(pts: PackedVector3Array, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts.is_empty():
		return out
	out.append(pts[0])
	var carry := 0.0
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		var seg := a.distance_to(b)
		if seg < 0.00001:
			continue
		var pos := 0.0
		while carry + (seg - pos) >= step:
			pos += step - carry
			out.append(a.lerp(b, pos / seg))
			carry = 0.0
		carry += seg - pos
	var last: Vector3 = pts[pts.size() - 1]
	if out[out.size() - 1].distance_to(last) > 0.05:
		out.append(last)
	return out


static func length(s: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, s.size()):
		total += s[i - 1].distance_to(s[i])
	return total


## Engster Kurvenradius in Metern (INF bei einer Geraden).
static func min_radius(s: PackedVector3Array) -> float:
	var best := INF
	var k := 3
	for i in range(k, s.size() - k):
		var a: Vector3 = s[i - k]
		var b: Vector3 = s[i]
		var c: Vector3 = s[i + k]
		var area2 := absf((b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x))
		if area2 < 0.0001:
			continue
		var r := a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (2.0 * area2)
		best = minf(best, r)
	return best


static func sample_at(s: PackedVector3Array, d: float) -> Vector3:
	var n := s.size()
	if n == 0:
		return Vector3.ZERO
	if d <= 0.0:
		return s[0]
	var i := floori(d)
	if i >= n - 1:
		return s[n - 1]
	return s[i].lerp(s[i + 1], d - float(i))


## Teilstück zwischen den Abständen d0 und d1 (in Metern ab dem Anfang).
static func sub(s: PackedVector3Array, d0: float, d1: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := s.size()
	if n < 2:
		return s
	d1 = maxf(d1, d0 + 0.1)
	out.append(sample_at(s, d0))
	var i := floori(d0) + 1
	while i < n and float(i) < d1:
		if s[i].distance_to(out[out.size() - 1]) > 0.05:
			out.append(s[i])
		i += 1
	var last := sample_at(s, d1)
	if last.distance_to(out[out.size() - 1]) > 0.05:
		out.append(last)
	elif out.size() == 1:
		out.append(last + Vector3(0.05, 0, 0))
	return out


static func dir_at(s: PackedVector3Array, d: float) -> Vector3:
	var n := s.size()
	if n < 2:
		return Vector3.FORWARD
	var i := clampi(floori(d), 0, n - 2)
	var t := s[i + 1] - s[i]
	if t.length_squared() < 0.000001:
		return Vector3.FORWARD
	return t.normalized()


## Flaches Band entlang der Stützpunkte. UV.x quer (0..1), UV.y in Metern.
static func ribbon(s: PackedVector3Array, width: float, y: float) -> ArrayMesh:
	var n := s.size()
	if n < 2:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var dist := PackedFloat32Array()
	var run := 0.0
	for i in range(n):
		var t: Vector3
		if i == 0:
			t = s[1] - s[0]
		elif i == n - 1:
			t = s[n - 1] - s[n - 2]
		else:
			t = s[i + 1] - s[i - 1]
		t.y = 0.0
		t = t.normalized()
		var side := t.cross(Vector3.UP)
		if i > 0:
			run += s[i].distance_to(s[i - 1])
		var c := Vector3(s[i].x, y + s[i].y, s[i].z)
		left.append(c - side * width * 0.5)
		right.append(c + side * width * 0.5)
		dist.append(run)
	for i in range(n - 1):
		_vert(st, left[i], 0.0, dist[i])
		_vert(st, right[i], 1.0, dist[i])
		_vert(st, left[i + 1], 0.0, dist[i + 1])
		_vert(st, right[i], 1.0, dist[i])
		_vert(st, right[i + 1], 1.0, dist[i + 1])
		_vert(st, left[i + 1], 0.0, dist[i + 1])
	return st.commit()


static func _vert(st: SurfaceTool, p: Vector3, u: float, v: float) -> void:
	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(u, v))
	st.add_vertex(p)


static func bounds(s: PackedVector3Array, grow: float) -> Rect2:
	if s.is_empty():
		return Rect2()
	var r := Rect2(Vector2(s[0].x, s[0].z), Vector2.ZERO)
	for p: Vector3 in s:
		r = r.expand(Vector2(p.x, p.z))
	return r.grow(grow)
