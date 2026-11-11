extends RefCounted
## Fahrwege der Bodenfahrzeuge als Graph: Betriebsstraßen und Vorfelder, für die Feuerwehr
## zusätzlich die Rollwege. Knoten alle 6 m entlang der Wege, Verbindungen dort, wo sich
## Flächen berühren oder kreuzen. Vorfeld- und Rollwegknoten kosten mehr, damit die Fahrzeuge
## die Betriebsstraßen nehmen, wo es sie gibt.

const Catalog = preload("res://scripts/catalog.gd")

const STEP := 6
const LANE_OFF := 1.75
const CELL := 24.0

var astar := AStar3D.new()
var pos := PackedVector3Array()
var kinds := PackedStringArray()
var line_of := PackedInt32Array()
var grid: Dictionary = {}


var stand_link: Dictionary = {}   # Instanz-ID des Stand-Knotens -> Netzknoten der Zufahrt (oder fehlt)


func build(lines: Array, with_taxi: bool, stands: Array = []) -> void:
	astar.clear()
	stand_link = {}
	pos = PackedVector3Array()
	kinds = PackedStringArray()
	line_of = PackedInt32Array()
	grid = {}
	var allowed := ["betriebsstrasse", "vorfeld"]
	if with_taxi:
		allowed += ["rollweg", "rollweg_breit"]
	for li in range(lines.size()):
		var l: Dictionary = lines[li]
		var k: String = l["kind"]
		if not (k in allowed):
			continue
		var s: PackedVector3Array = l["samples"]
		var prev := -1
		var i := 0
		while true:
			var id := _add(Vector3(s[i].x, 0.0, s[i].z), k, li)
			if prev >= 0:
				astar.connect_points(prev, id)
			prev = id
			if i == s.size() - 1:
				break
			i = mini(i + STEP, s.size() - 1)
	# Querverbindungen zwischen verschiedenen Wegen
	for i in range(pos.size()):
		var c := _cell(pos[i])
		var best := {}
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				var key := c + Vector2i(dx, dz)
				if not grid.has(key):
					continue
				for j: int in grid[key]:
					if line_of[j] == line_of[i]:
						continue
					var limit := (_width(kinds[i]) + _width(kinds[j])) * 0.5 + 3.0
					var d := pos[i].distance_to(pos[j])
					if d > limit:
						continue
					var lj := line_of[j]
					if not best.has(lj) or d < float(best[lj][0]):
						best[lj] = [d, j]
		for lj: int in best:
			var j: int = best[lj][1]
			if not astar.are_points_connected(i, j):
				astar.connect_points(i, j)
	# Knoten auf Standflächen meiden: dort stehen Flugzeuge, quer hindurch fährt niemand (Busse, Schlepper …)
	for st: Dictionary in stands:
		var sr: Rect2 = (st["rect"] as Rect2).grow(-1.0)
		for j in range(pos.size()):
			if kinds[j] != "betriebsstrasse" and sr.has_point(Vector2(pos[j].x, pos[j].z)):
				astar.set_point_weight_scale(j, 40.0)
	# Stände: Zufahrt vom Kopf des Stands (Nasenseite) zur nächsten Betriebsstraße
	for st: Dictionary in stands:
		var node: Node3D = st["node"]
		if not is_instance_valid(node):
			continue
		var fwd := node.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var depth: float = (Catalog.ITEMS[st["id"]]["size"] as Vector2).y
		var head: Vector3 = (st["pos"] as Vector3) + fwd * (depth * 0.5 - 2.0)
		var road := -1
		var bd := 16.0 + 4.0
		for j in range(pos.size()):
			if kinds[j] != "betriebsstrasse":
				continue
			var d := Vector2(pos[j].x - head.x, pos[j].z - head.z).length()
			if d < bd:
				bd = d
				road = j
		if road < 0:
			continue
		var id := _add(Vector3(head.x, 0.0, head.z), "zufahrt", -1)
		astar.set_point_weight_scale(id, 1.0)
		astar.connect_points(id, road)
		stand_link[node.get_instance_id()] = id


func _add(p: Vector3, k: String, li: int) -> int:
	var id := pos.size()
	pos.append(p)
	kinds.append(k)
	line_of.append(li)
	astar.add_point(id, p, 1.0 if k == "betriebsstrasse" else 3.0)
	var key := _cell(p)
	if not grid.has(key):
		grid[key] = []
	(grid[key] as Array).append(id)
	return id


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


static func _width(k: String) -> float:
	return float(Catalog.LINES[k]["width"]) if Catalog.LINES.has(k) else 8.0


## Nächster Knoten bis max_d Meter (oder -1).
func nearest(p: Vector3, max_d: float = 60.0) -> int:
	var c := _cell(p)
	var r := ceili(max_d / CELL)
	var best := -1
	var bd := max_d * max_d
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var key := c + Vector2i(dx, dz)
			if not grid.has(key):
				continue
			for j: int in grid[key]:
				var d := Vector2(pos[j].x - p.x, pos[j].z - p.z).length_squared()
				# Betriebsstraßen bevorzugen
				if kinds[j] != "betriebsstrasse" and kinds[j] != "zufahrt":
					d = d * 1.6 + 25.0
				if d < bd:
					bd = d
					best = j
	return best


## Weg von a nach b über das Netz: [a, Knoten …, b] oder leer, wenn es keinen gibt.
func route(a: Vector3, b: Vector3, max_d: float = 60.0) -> PackedVector3Array:
	var na := nearest(a, max_d)
	var nb := nearest(b, max_d)
	if na < 0 or nb < 0:
		return PackedVector3Array()
	var ids := astar.get_id_path(na, nb)
	if ids.is_empty() and na != nb:
		return PackedVector3Array()
	var out := PackedVector3Array([a])
	for j in range(ids.size()):
		var q := pos[ids[j]]
		# Rechtsverkehr: auf Betriebsstraßen in der rechten Spur (1,75 m neben der Mitte)
		if kinds[ids[j]] == "betriebsstrasse" and ids.size() > 1:
			var pa := pos[ids[maxi(j - 1, 0)]]
			var pb := pos[ids[mini(j + 1, ids.size() - 1)]]
			var dir := pb - pa
			dir.y = 0.0
			if dir.length() > 0.1:
				q += dir.normalized().cross(Vector3.UP) * LANE_OFF
		if out[out.size() - 1].distance_to(q) > 2.0:
			out.append(q)
	if out[out.size() - 1].distance_to(b) > 0.5:
		out.append(b)
	return _trim(out)


## Spitze Umwege am Anfang und Ende kürzen (der erste Knoten liegt oft schon hinter dem Fahrzeug).
static func _trim(pts: PackedVector3Array) -> PackedVector3Array:
	if pts.size() < 4:
		return pts
	var out := PackedVector3Array()
	out.append(pts[0])
	var start := 1
	while start < pts.size() - 2 and pts[0].distance_to(pts[start + 1]) < pts[0].distance_to(pts[start]) + 1.0:
		start += 1
	var stop := pts.size() - 2
	while stop > start and pts[pts.size() - 1].distance_to(pts[stop - 1]) < pts[pts.size() - 1].distance_to(pts[stop]) + 1.0:
		stop -= 1
	for i in range(start, stop + 1):
		out.append(pts[i])
	out.append(pts[pts.size() - 1])
	return out
