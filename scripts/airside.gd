extends RefCounted
## Rollnetz als Graph: Knoten alle 5 m entlang von Pisten, Rollwegen und Vorfeldern,
## Verbindungen dort, wo sich Flächen berühren oder kreuzen.
## Je Stand ein Standknoten und ein Zufahrtsknoten am hinteren Rand (Einrolllinie).
## Über Standflächen wird nicht durchgerollt, Knoten näher als HOLD_DIST an einer Pistenmitte
## gehören zum Pistenschutzbereich (dort darf nur, wer die Piste hat).
## Wegsuche mit A*, ohne Wenden auf der Stelle.

const Catalog = preload("res://scripts/catalog.gd")

const STEP := 5
const CELL := 20.0
const NEAR := 30.0
const HOLD_DIST := 90.0      # Rollhalteort: Abstand zur Pistenmitte (ICAO, Instrumentenpiste)
const LEAD_BACK := 24.0      # Zufahrtsknoten so weit hinter der Standmitte
const MAX_TURN_DOT := -0.35  # schärfer als ~110° wird an einem Knoten nicht abgebogen

var pos := PackedVector3Array()
var kind := PackedStringArray()
var line_idx := PackedInt32Array()   # Index in game.lines, -1 für Stände und Zufahrten
var adj: Array = []                  # je Knoten: Array von Nachbarindizes
var line_nodes: Dictionary = {}      # Index in game.lines -> Array der Knoten in Reihenfolge
var stand_node: Dictionary = {}      # Instanz-ID des Stand-Knotens -> Graphknoten
var lead_of: Dictionary = {}         # Standknoten -> Zufahrtsknoten
var stand_of_lead: Dictionary = {}   # Zufahrtsknoten -> Standknoten
var stand_fwd: Dictionary = {}       # Standknoten -> Blickrichtung des geparkten Flugzeugs
var stand_code: Dictionary = {}      # Standknoten -> "C" oder "E" (größtes Flugzeug)
var near: Array = []                 # je Knoten: Knoten im Umkreis von NEAR m (für Reservierungen)
var zone := PackedByteArray()        # 1 = im Pistenschutzbereich
var in_stand := PackedByteArray()    # 1 = liegt auf einer Standfläche
var runways: Array = []              # [Anfang, Ende, Breite] je Piste
var holds: Array = []                # Rollhalteorte: {"pos", "dir" (zur Piste), "line"}


func build(lines: Array, stands: Array) -> void:
	pos = PackedVector3Array()
	kind = PackedStringArray()
	line_idx = PackedInt32Array()
	adj = []
	near = []
	line_nodes = {}
	stand_node = {}
	lead_of = {}
	stand_of_lead = {}
	stand_fwd = {}
	stand_code = {}
	runways = []
	holds = []
	for l: Dictionary in lines:
		if l["kind"] == "piste":
			var s: PackedVector3Array = l["samples"]
			runways.append([s[0], s[s.size() - 1], float(Catalog.LINES["piste"]["width"])])
	for li in range(lines.size()):
		var l: Dictionary = lines[li]
		var k: String = l["kind"]
		if not (k in ["piste", "rollweg", "rollweg_breit", "vorfeld"]):
			continue
		var s: PackedVector3Array = l["samples"]
		var ids := []
		var i := 0
		while true:
			var id := _add(s[i], k, li)
			if not ids.is_empty():
				_link(ids[ids.size() - 1], id)
			ids.append(id)
			if i == s.size() - 1:
				break
			i = mini(i + STEP, s.size() - 1)
		line_nodes[li] = ids
		if k == "rollweg" or k == "rollweg_breit":
			_find_holds(s, li)
	_cross_links()
	# Standflächen sperren
	in_stand.resize(pos.size())
	in_stand.fill(0)
	var rects := []
	for st: Dictionary in stands:
		rects.append((st["rect"] as Rect2).grow(1.0))
	for i in range(pos.size()):
		if kind[i] == "piste":
			continue
		for r: Rect2 in rects:
			if r.has_point(Vector2(pos[i].x, pos[i].z)):
				in_stand[i] = 1
				break
	# Stand- und Zufahrtsknoten
	for st: Dictionary in stands:
		var node: Node3D = st["node"]
		var fwd := node.global_transform.basis.z.normalized()
		fwd.y = 0.0
		fwd = fwd.normalized()
		var p: Vector3 = st["pos"]
		var depth: float = (Catalog.ITEMS[st["id"]]["size"] as Vector2).y
		var sid := _add(p, "stand", -1)
		var lid := _add(p - fwd * (depth * 0.5 + 1.0), "zufahrt", -1)
		stand_code[sid] = String(Catalog.ITEMS[st["id"]].get("code", "C"))
		in_stand.append(0)
		in_stand.append(0)
		_link(sid, lid)
		lead_of[sid] = lid
		stand_of_lead[lid] = sid
		stand_fwd[sid] = fwd
		stand_node[node.get_instance_id()] = sid
		for n: int in _lead_targets(pos[lid], fwd):
			_link(lid, n)
	zone.resize(pos.size())
	for i in range(pos.size()):
		zone[i] = 1 if in_zone(pos[i]) else 0
	_near_lists()


## Rollweg- oder Vorfeldknoten hinter dem Stand, an die die Einrolllinie anschließt.
func _lead_targets(lp: Vector3, fwd: Vector3) -> Array:
	var roll := []
	var apron := []
	for i in range(pos.size()):
		if in_stand[i] == 1 or not (kind[i] in ["rollweg", "rollweg_breit", "vorfeld"]):
			continue
		var d := pos[i].distance_to(lp)
		if d > 42.0 or (pos[i] - lp).dot(fwd) > 4.0:
			continue
		if kind[i] == "rollweg" or kind[i] == "rollweg_breit":
			roll.append([d, i])
		else:
			apron.append([d, i])
	var list := roll if not roll.is_empty() else apron
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out := []
	for f: Array in list.slice(0, 2 if list == roll else 3):
		out.append(f[1])
	return out


## Wo ein Rollweg den Abstand HOLD_DIST zu einer Pistenmitte unterschreitet, liegt ein Rollhalteort.
func _find_holds(s: PackedVector3Array, li: int) -> void:
	if runways.is_empty():
		return
	var prev := _rwy_dist(s[0])
	for i in range(1, s.size()):
		var d := _rwy_dist(s[i])
		if (prev >= HOLD_DIST) != (d >= HOLD_DIST):
			var t := s[i] - s[i - 1]
			t.y = 0.0
			var toward := t.normalized() if d < prev else -t.normalized()
			holds.append({"pos": Vector3(s[i].x, 0.0, s[i].z), "dir": toward, "line": li})
		prev = d


func _rwy_dist(p: Vector3) -> float:
	var best := INF
	for r: Array in runways:
		best = minf(best, _seg_dist(p, r[0], r[1]))
	return best


## Abstand zur nächsten Pistenmitte (für Rollhalteorte und den Pistenschutzbereich).
func runway_distance(p: Vector3) -> float:
	return _rwy_dist(p)


func in_zone(p: Vector3) -> bool:
	return _rwy_dist(p) < HOLD_DIST - 0.5


static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * t).length()


func _near_lists() -> void:
	var grid := {}
	for i in range(pos.size()):
		var key := Vector2i(floori(pos[i].x / CELL), floori(pos[i].z / CELL))
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(i)
	for i in range(pos.size()):
		var c := Vector2i(floori(pos[i].x / CELL), floori(pos[i].z / CELL))
		var list := []
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				for j: int in grid.get(c + Vector2i(dx, dz), []):
					if j != i and pos[i].distance_to(pos[j]) < NEAR:
						list.append(j)
		near.append(list)


func _add(p: Vector3, k: String, li: int) -> int:
	pos.append(Vector3(p.x, 0.0, p.z))
	kind.append(k)
	line_idx.append(li)
	adj.append([])
	return pos.size() - 1


func _link(a: int, b: int) -> void:
	if a == b or (adj[a] as Array).has(b):
		return
	(adj[a] as Array).append(b)
	(adj[b] as Array).append(a)


func _width(k: String) -> float:
	if Catalog.LINES.has(k):
		return float(Catalog.LINES[k]["width"])
	return 0.0


## Knoten verschiedener Flächen werden verbunden, wenn sich die Flächen berühren.
func _cross_links() -> void:
	var grid := {}
	for i in range(pos.size()):
		var key := Vector2i(floori(pos[i].x / CELL), floori(pos[i].z / CELL))
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(i)
	for i in range(pos.size()):
		var c := Vector2i(floori(pos[i].x / CELL), floori(pos[i].z / CELL))
		var best := {}   # Linienindex -> [Abstand, Knoten]
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				var key := c + Vector2i(dx, dz)
				if not grid.has(key):
					continue
				for j: int in grid[key]:
					if line_idx[j] == line_idx[i]:
						continue
					var limit := (_width(kind[i]) + _width(kind[j])) * 0.5 + 2.0
					var d := pos[i].distance_to(pos[j])
					if d > limit:
						continue
					var li := line_idx[j]
					if not best.has(li) or d < float(best[li][0]):
						best[li] = [d, j]
		for li in best:
			_link(i, int(best[li][1]))


func nearest(p: Vector3, k: String = "") -> int:
	var best := -1
	var bd := INF
	for i in range(pos.size()):
		if k != "" and kind[i] != k:
			continue
		if k == "" and (kind[i] in ["stand", "zufahrt"] or in_stand[i] == 1):
			continue
		var d := pos[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


## Nächster freier Rollknoten (kein Stand, keine Standfläche) in der Nähe von p, sonst -1.
func nearest_taxi(p: Vector3, max_d: float) -> int:
	var best := -1
	var bd := max_d
	for i in range(pos.size()):
		if in_stand[i] == 1 or not (kind[i] in ["rollweg", "rollweg_breit", "vorfeld"]):
			continue
		var d := pos[i].distance_to(p)
		if d < bd:
			bd = d
			best = i
	return best


## Kürzester Weg von a nach b als Knotenliste (leer, wenn es keinen gibt).
## blocked: gemiedene Knoten (z. B. von anderen reserviert). Stände, Zufahrten und Standflächen
## nur als Start oder Ziel. heading: Fahrtrichtung am Start (kein Wenden).
## wide = Großraumflugzeug (Code E): schmale Rollwege (Code C) sind gesperrt.
func path(a: int, b: int, blocked: Dictionary = {}, heading: Vector3 = Vector3.ZERO, wide: bool = false) -> Array:
	var out := _search(a, b, blocked, heading, true, wide)
	if out.is_empty():
		out = _search(a, b, blocked, heading, false, wide)
	return out


func _search(a: int, b: int, blocked: Dictionary, heading: Vector3, no_uturn: bool, wide: bool) -> Array:
	if a < 0 or b < 0:
		return []
	var allow := {a: true, b: true}
	if lead_of.has(b):
		allow[lead_of[b]] = true
	if lead_of.has(a):
		allow[lead_of[a]] = true
	var g := {a: 0.0}
	var came := {}
	var open := [a]
	var closed := {}
	while not open.is_empty():
		var best_i := 0
		var best_f := INF
		for k in range(open.size()):
			var n: int = open[k]
			var f: float = float(g[n]) + pos[n].distance_to(pos[b])
			if f < best_f:
				best_f = f
				best_i = k
		var cur: int = open[best_i]
		open.remove_at(best_i)
		if cur == b:
			var out := [b]
			while came.has(out[0]):
				out.push_front(came[out[0]])
			return out
		closed[cur] = true
		var din := Vector3.ZERO
		if came.has(cur):
			din = (pos[cur] - pos[came[cur]]).normalized()
		elif heading.length_squared() > 0.01:
			din = heading.normalized()
		for nb: int in adj[cur]:
			if closed.has(nb):
				continue
			if not allow.has(nb):
				if kind[nb] == "stand" or kind[nb] == "zufahrt" or in_stand[nb] == 1 or blocked.has(nb):
					continue
			if wide and kind[nb] == "rollweg":
				continue
			var step := pos[nb] - pos[cur]
			if no_uturn and din != Vector3.ZERO and step.length() > 0.01 and din.dot(step.normalized()) < MAX_TURN_DOT:
				continue
			var w := 1.0
			if kind[nb] == "piste":
				w = 1.6
			elif kind[nb] == "vorfeld":
				w = 1.4
			var cost := float(g[cur]) + step.length() * w
			if not g.has(nb) or cost < float(g[nb]):
				g[nb] = cost
				came[nb] = cur
				if not open.has(nb):
					open.append(nb)
	return []
