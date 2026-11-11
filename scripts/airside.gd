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
const MAX_TURN_DOT_SOFT := 0.0  # Flugzeuge biegen je Knoten höchstens 90° ab
const MAX_TURN_DOT := -0.35  # Notfall: bis ~110°, falls es sonst keinen Weg gibt

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
var zone_rwy := PackedInt32Array()   # Index der nächsten Piste (in runways) je Knoten
var in_stand := PackedByteArray()    # 1 = liegt auf einer Standfläche
var runways: Array = []              # [Anfang, Ende, Breite] je Piste
var holds: Array = []                # Rollhalteorte: {"pos", "dir" (zur Piste), "line"}


var line_hold: Dictionary = {}       # Linienindex -> Abstand des selbst gesetzten Rollhalteorts zur Pistenmitte
var guided: Dictionary = {}          # Linienindex von Vorfeld/Rollweg mit gezeichneten Rollführungslinien


func build(lines: Array, stands: Array, markers: Array = []) -> void:
	line_hold = {}
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
			runways.append([s[0], s[s.size() - 1], float(Catalog.LINES["piste"]["width"]), lines.find(l)])
	for li in range(lines.size()):
		var l: Dictionary = lines[li]
		var k: String = l["kind"]
		if not (k in ["piste", "rollweg", "rollweg_breit", "vorfeld", "rolllinie"]):
			continue
		var s: PackedVector3Array = l["samples"]
		var ids := []
		var i := 0
		var step := STEP if k != "rolllinie" else 3
		while true:
			var id := _add(s[i], k, li)
			if not ids.is_empty():
				_link(ids[ids.size() - 1], id)
			ids.append(id)
			if i == s.size() - 1:
				break
			i = mini(i + step, s.size() - 1)
		line_nodes[li] = ids
		if k == "rollweg" or k == "rollweg_breit":
			if not _custom_holds(s, li, markers):
				_find_holds(s, li)
		elif k == "rolllinie":
			_custom_holds(s, li, markers)
	_cross_links()
	_turn_pads(markers)
	# Flächen mit gezeichneten Rollführungslinien: dort nur auf den Linien rollen
	guided = {}
	var line_pts := []
	for i in range(pos.size()):
		if kind[i] == "rolllinie":
			line_pts.append(pos[i])
	# jeder Linienpunkt gehört zu der Fläche, auf deren Mitte er relativ am nächsten liegt
	for q: Vector3 in line_pts:
		var best_li := -1
		var best_f := 1.0
		for li in range(lines.size()):
			var lk: String = lines[li]["kind"]
			if not (lk in ["vorfeld", "rollweg", "rollweg_breit"]):
				continue
			var half := _width(lk) * 0.5
			var b: Rect2 = lines[li].get("bounds", Rect2())
			if b.size != Vector2.ZERO and not b.grow(2.0).has_point(Vector2(q.x, q.z)):
				continue
			var sm: PackedVector3Array = lines[li]["samples"]
			var dmin := INF
			for j in range(0, sm.size(), 2):
				dmin = minf(dmin, Vector2(sm[j].x - q.x, sm[j].z - q.z).length())
			var f := dmin / half
			if f < best_f:
				best_f = f
				best_li = li
		if best_li >= 0:
			guided[best_li] = int(guided.get(best_li, 0)) + 1
	# nur Flächen, auf denen ein guter Teil gezeichnet ist (nicht schon, wenn eine Linie dort nur beginnt)
	for li: int in guided.keys():
		var sm2: PackedVector3Array = lines[li]["samples"]
		var len := 0.0
		for j in range(1, sm2.size()):
			len += sm2[j].distance_to(sm2[j - 1])
		if float(guided[li]) * 3.0 < minf(120.0, len * 0.4):
			guided.erase(li)
		else:
			guided[li] = true
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
	zone_rwy.resize(pos.size())
	for i in range(pos.size()):
		zone_rwy[i] = nearest_runway(pos[i])
		var li := line_idx[i]
		if line_hold.has(li):
			zone[i] = 1 if _rwy_dist(pos[i]) < float(line_hold[li]) - 0.5 else 0
		else:
			zone[i] = 1 if in_zone(pos[i]) else 0
	_near_lists()


## Rollweg- oder Vorfeldknoten hinter dem Stand, an die die Einrolllinie anschließt.
func _lead_targets(lp: Vector3, fwd: Vector3) -> Array:
	var roll := []
	var apron := []
	var marked := []
	for i in range(pos.size()):
		if i >= in_stand.size() or in_stand[i] == 1 or not (kind[i] in ["rollweg", "rollweg_breit", "vorfeld", "rolllinie"]):
			continue
		var d := pos[i].distance_to(lp)
		if d > 42.0 or (pos[i] - lp).dot(fwd) > 4.0:
			continue
		if kind[i] == "rolllinie":
			marked.append([d, i])
		elif guided.has(line_idx[i]):
			continue
		elif kind[i] == "rollweg" or kind[i] == "rollweg_breit":
			roll.append([d, i])
		else:
			apron.append([d, i])
	var list := marked if not marked.is_empty() else (roll if not roll.is_empty() else apron)
	list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out := []
	for f: Array in list.slice(0, 3 if list == apron else 2):
		out.append(f[1])
	return out


## Selbst gesetzte Rollhalteorte (Bauteil "rollhalt") auf diesem Rollweg: sie ersetzen den gedachten bei
## HOLD_DIST, der Pistenschutzbereich des Rollwegs beginnt dort. false = keiner auf dieser Linie.
func _custom_holds(s: PackedVector3Array, li: int, markers: Array) -> bool:
	if runways.is_empty():
		return false
	var found := false
	for m: Dictionary in markers:
		if String(m.get("id", "rollhalt")) != "rollhalt":
			continue
		var mp: Vector3 = m["pos"]
		var bi := -1
		var bd := 5.0
		for i in range(s.size()):
			var d := Vector2(s[i].x - mp.x, s[i].z - mp.z).length()
			if d < bd:
				bd = d
				bi = i
		if bi < 0:
			continue
		var t := s[mini(bi + 3, s.size() - 1)] - s[maxi(bi - 3, 0)]
		t.y = 0.0
		t = t.normalized()
		# Richtung zur Piste: dorthin, wo der Abstand kleiner wird
		var dd := _rwy_dist(s[mini(bi + 3, s.size() - 1)]) - _rwy_dist(s[maxi(bi - 3, 0)])
		var toward := -t if dd > 0.0 else t
		var hd := _rwy_dist(mp)
		holds.append({"pos": Vector3(s[bi].x, 0.0, s[bi].z), "dir": toward, "line": li, "custom": true})
		line_hold[li] = maxf(float(line_hold.get(li, 0.0)), hd)
		found = true
	return found


var pads: Array = []                 # Wendeplatten: {thr, inward, side, pts (Wendespur), exit (Pistenknoten)}


## Wendeplatten: eine tropfenförmige Spur neben dem Pistenende. Von der Pistenmitte schwenkt sie zur Seite
## aus, läuft im Halbkreis um und kommt in Gegenrichtung auf die Mitte zurück (Knoten als Pistenknoten,
## damit Pistenschutz und Freigaben gelten). So kann ein Flugzeug wenden, ohne auf der Stelle zu drehen.
func _turn_pads(markers: Array) -> void:
	pads = []
	for m: Dictionary in markers:
		if String(m.get("id", "")) != "wendeplatte":
			continue
		var mp: Vector3 = m["pos"]
		var best: Array = []
		var bd := 200.0
		for r: Array in runways:
			for e in range(2):
				var thr: Vector3 = r[e]
				var inward := ((r[1 - e] as Vector3) - thr).normalized()
				var lat := inward.cross(Vector3.UP).normalized()
				var side := 1.0 if (mp - thr).dot(lat) >= 0.0 else -1.0
				var d := Vector2(mp.x - thr.x, mp.z - thr.z).length()
				if d < bd:
					bd = d
					best = [thr, inward, lat * side, int(r[3])]
		if best.is_empty():
			continue
		var thr: Vector3 = best[0]
		var inward: Vector3 = best[1]
		var lat: Vector3 = best[2]
		var w := float(Catalog.LINES["piste"]["width"]) * 0.5 + 24.0
		var at := 32.0
		var t1 := thr + inward * (at + 55.0)
		var e_pt := thr + inward * at + lat * w
		var mid := thr + inward * at + lat * w * 0.5
		var pts := PackedVector3Array()
		var c1 := t1 - inward * 28.0
		var c2 := e_pt + inward * 28.0
		for i in range(1, 9):
			var t := float(i) / 8.0
			var u := 1.0 - t
			pts.append(t1 * (u * u * u) + c1 * (3.0 * u * u * t) + c2 * (3.0 * u * t * t) + e_pt * (t * t * t))
		for i in range(1, 13):
			var ph := PI * float(i) / 12.0
			pts.append(mid + lat * w * 0.5 * cos(ph) - inward * w * 0.5 * sin(ph))
		var f_pt := pts[pts.size() - 1]
		var a_rw := _nearest_kind(t1, "piste")
		var b_rw := _nearest_kind(f_pt + inward * 4.0, "piste")
		if a_rw < 0 or b_rw < 0:
			continue
		var prev := a_rw
		var ids := []
		for i in range(pts.size() - 1):
			var id := _add(Vector3(pts[i].x, 0, pts[i].z), "piste", int(best[3]))
			ids.append(id)
			_link(prev, id)
			prev = id
		_link(prev, b_rw)
		pads.append({"thr": thr, "inward": inward, "side": lat, "pts": PackedVector3Array([t1]) + pts, "exit": b_rw, "nodes": ids})


func _nearest_kind(p: Vector3, k: String) -> int:
	var best := -1
	var bd := INF
	for i in range(pos.size()):
		if kind[i] != k:
			continue
		var d := pos[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


## Ausfahrt der Wendeplatte am Pistenende bei thr (Pistenknoten auf der Mitte), sonst -1.
func pad_exit(thr: Vector3) -> int:
	for pd: Dictionary in pads:
		if (pd["thr"] as Vector3).distance_to(thr) < 30.0:
			return int(pd["exit"])
	return -1


## Abstand zur Pistenmitte, ab dem Knoten n zum Pistenschutzbereich gehört.
func hold_limit(n: int) -> float:
	if n >= 0 and n < line_idx.size() and line_hold.has(line_idx[n]):
		return float(line_hold[line_idx[n]])
	return HOLD_DIST


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


## Abstand zur Mitte einer bestimmten Piste (Index in runways).
func runway_distance_i(p: Vector3, ri: int) -> float:
	if ri < 0 or ri >= runways.size():
		return INF
	return _seg_dist(p, runways[ri][0], runways[ri][1])


func nearest_runway(p: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in range(runways.size()):
		var d := _seg_dist(p, runways[i][0], runways[i][1])
		if d < bd:
			bd = d
			best = i
	return best


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
		if in_stand[i] == 1 or not (kind[i] in ["rollweg", "rollweg_breit", "vorfeld", "rolllinie"]):
			continue
		if guided.has(line_idx[i]):
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
## Flugzeuge biegen höchstens 90° je Knoten ab und wenden nie auf der Stelle; nur wenn es so
## gar keinen Weg gibt, werden schärfere Kurven erlaubt.
func path(a: int, b: int, blocked: Dictionary = {}, heading: Vector3 = Vector3.ZERO, wide: bool = false, end_dir: Vector3 = Vector3.ZERO) -> Array:
	# end_dir: gewünschte Fahrtrichtung am Ziel (Startrichtung auf der Piste); gibt es so keinen Weg, gilt sie nicht
	if end_dir != Vector3.ZERO:
		for md: float in [MAX_TURN_DOT_SOFT, MAX_TURN_DOT]:
			var o := _search(a, b, blocked, heading, md, wide, end_dir)
			if not o.is_empty():
				return o
	var out := _search(a, b, blocked, heading, MAX_TURN_DOT_SOFT, wide)
	if out.is_empty():
		out = _search(a, b, blocked, heading, MAX_TURN_DOT, wide)
	if out.is_empty():
		out = _search(a, b, blocked, heading, -2.0, wide)
	return out


## A* über gerichtete Kanten (Zustand = Knoten und woher man kommt), damit die Kurvenregel
## auch Schleifen über Nachbarflächen findet.
func _search(a: int, b: int, blocked: Dictionary, heading: Vector3, min_dot: float, wide: bool, end_dir: Vector3 = Vector3.ZERO) -> Array:
	if a < 0 or b < 0:
		return []
	var allow := {a: true, b: true}
	if lead_of.has(b):
		allow[lead_of[b]] = true
	if lead_of.has(a):
		allow[lead_of[a]] = true
	var n_all := pos.size() + 1
	var start := a * n_all + n_all - 1   # Zustand: Knoten * n_all + Vorgänger (n_all-1 = keiner)
	var g := {start: 0.0}
	var came := {}
	var heap: Array = [[pos[a].distance_to(pos[b]), start]]
	var closed := {}
	var h0 := heading.normalized() if heading.length_squared() > 0.01 else Vector3.ZERO
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var key: int = top[1]
		if closed.has(key):
			continue
		closed[key] = true
		var cur := key / n_all
		var prev := key % n_all
		var arrive_ok := true
		if cur == b and end_dir != Vector3.ZERO and prev != n_all - 1:
			var dl := pos[cur] - pos[prev]
			dl.y = 0.0
			arrive_ok = dl.length() < 0.01 or dl.normalized().dot(end_dir) > 0.3
		if cur == b and arrive_ok:
			var out := [b]
			var k := key
			while came.has(k):
				k = came[k]
				out.push_front(k / n_all)
			return out
		var din := h0
		if prev != n_all - 1:
			din = pos[cur] - pos[prev]
			din.y = 0.0
			din = din.normalized() if din.length_squared() > 0.0001 else h0
		for nb: int in adj[cur]:
			if nb == prev:
				continue
			if not allow.has(nb):
				if kind[nb] == "stand" or kind[nb] == "zufahrt" or in_stand[nb] == 1 or blocked.has(nb):
					continue
				# auf Flächen mit gezeichneten Linien nur entlang der Linien
				if line_idx[nb] >= 0 and guided.has(line_idx[nb]):
					continue
			if wide and kind[nb] == "rollweg":
				continue
			var step := pos[nb] - pos[cur]
			step.y = 0.0
			var sl := step.length()
			if sl < 0.01:
				continue
			if din != Vector3.ZERO and din.dot(step / sl) < min_dot:
				continue
			var nkey := nb * n_all + cur
			if closed.has(nkey):
				continue
			# Wie Lotsen und Piloten rollen: lange gerade Rollwege (der Parallelrollweg zuerst), über Vorfelder
			# nur wenn nötig, auf der Piste so wenig wie möglich (nur zum Zurückrollen oder Kreuzen)
			var w := 1.0
			match kind[nb]:
				"piste":
					w = 3.5
				"vorfeld":
					w = 1.8
				"rolllinie":
					w = 1.15
				"rollweg_breit":
					w = 0.92
			# Kurven kosten, scharfe Kurven deutlich mehr: gerade Wege werden bevorzugt
			var turn := 0.0
			if din != Vector3.ZERO:
				var cd := din.dot(step / sl)
				turn = (1.0 - cd) * 10.0 + (14.0 if cd < 0.5 else 0.0)
			var cost := float(g[key]) + sl * w + turn
			if not g.has(nkey) or cost < float(g[nkey]):
				g[nkey] = cost
				came[nkey] = key
				_heap_push(heap, [cost + pos[nb].distance_to(pos[b]), nkey])
	return []


static func _heap_push(h: Array, e: Array) -> void:
	h.append(e)
	var i := h.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if float(h[parent][0]) <= float(e[0]):
			break
		h[i] = h[parent]
		i = parent
	h[i] = e


static func _heap_pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if h.is_empty():
		return top
	var i := 0
	var n := h.size()
	while true:
		var l := i * 2 + 1
		if l >= n:
			break
		var c := l
		if l + 1 < n and float(h[l + 1][0]) < float(h[l][0]):
			c = l + 1
		if float(h[c][0]) >= float(last[0]):
			break
		h[i] = h[c]
		i = c
	h[i] = last
	return top
