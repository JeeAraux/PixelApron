extends Node3D
## Straßennetz als Graph: Knoten (Kreuzungen, Einmündungen, offene Enden) und Abschnitte (Straßen).
## Jede Straße hat Spuren je Richtung. An Kreuzungen werden die Straßen zurückgenommen, damit Platz
## für eine Kreuzungsfläche und für Kurvenbögen zwischen den Spuren bleibt.
## Regelung je Kreuzung: rechts vor links, Vorfahrtsstraße oder Ampel mit Phasen.
##
## Fahrtrichtung d = +1 heißt entlang der Stützpunkte (vom Startknoten zum Endknoten), d = -1 umgekehrt.
## Spur k = 0 ist die innerste (links), höhere k liegen weiter rechts. Es gilt Rechtsverkehr.

const Catalog = preload("res://scripts/catalog.gd")
const Spline = preload("res://scripts/spline.gd")
const Kit = preload("res://scripts/mesh_kit.gd")
const GameState = preload("res://scripts/game_state.gd")
const Streetscape = preload("res://scripts/streetscape.gd")

const LINK := 2.5
const CONTROLS := ["rechts", "vorfahrt", "ampel"]
const CONTROL_NAMES := {"rechts": "Rechts vor links", "vorfahrt": "Vorfahrtsstraße", "ampel": "Ampel", "": "Keine Regelung"}
## Ampelzyklus in Sekunden: Grün A, Gelb A, Rot alle, Grün B, Gelb B, Rot alle
const PHASES := [14.0, 3.0, 2.0, 14.0, 3.0, 2.0]
## Haltebuchten vor Bauteilen: [Bauteil, Aufschrift, Beginn, Ende] in Metern relativ zum Haltepunkt
## auf der Spur (so wie traffic.gd die Fahrzeuge in die Bucht lenkt)
const BAY_SPECS := [["haltestelle", "BUS", -17.0, 14.0], ["taxistand", "TAXI", -3.0, 22.0], ["kissandfly", "KISS FLY", -3.0, 22.0]]

var game: GameState
var nodes: Array = []          # je Knoten: {pos, ends, control, major, radius, lamps, timer}
var line_nodes: Dictionary = {} # Instanz-ID der Straße -> [Knoten am Anfang, Knoten am Ende]
var lane_cache: Dictionary = {}
var conn_cache: Dictionary = {}
var visuals: Node3D
var mat_asphalt: StandardMaterial3D
var lamp_mats: Dictionary = {}
var dirty := true
var bays: Dictionary = {}      # Instanz-ID der Straße -> [[Seite, s0, s1, Tiefe, Aufschrift]] entlang der zurückgenommenen Mitte
var verge_dirty := false
var _bay_sig := ""


func setup(g: GameState) -> void:
	game = g
	game.network_changed.connect(func() -> void: dirty = true)
	game.items_changed.connect(_check_bays)
	visuals = Node3D.new()
	visuals.name = "Kreuzungen"
	add_child(visuals)
	mat_asphalt = StandardMaterial3D.new()
	mat_asphalt.albedo_color = Color(0.23, 0.225, 0.21)
	mat_asphalt.roughness = 1.0
	mat_asphalt.cull_mode = BaseMaterial3D.CULL_DISABLED
	for c: Array in [["rot", Color(1.0, 0.15, 0.1)], ["gelb", Color(1.0, 0.75, 0.1)], ["gruen", Color(0.2, 1.0, 0.35)]]:
		var on := StandardMaterial3D.new()
		on.albedo_color = c[1]
		on.emission_enabled = true
		on.emission = c[1]
		on.emission_energy_multiplier = 2.0
		lamp_mats[c[0]] = on
	var off := StandardMaterial3D.new()
	off.albedo_color = Color(0.12, 0.12, 0.12)
	lamp_mats["aus"] = off


func roads() -> Array:
	var out := []
	for l: Dictionary in game.lines:
		if Catalog.is_road(String(l["kind"])):
			out.append(l)
	return out


static func iid(l: Dictionary) -> int:
	return (l["node"] as Node).get_instance_id()


# ---------------------------------------------------------------- Aufbau

func ensure() -> void:
	if dirty:
		rebuild()
	elif verge_dirty:
		verge_dirty = false
		_compute_bays()
		for l: Dictionary in roads():
			_trim_mesh(l)


## Auch bei Pause sofort neu zeichnen (neue Straße, neue Haltestelle).
func _process(_dt: float) -> void:
	if dirty or verge_dirty:
		ensure()


## Haltestellen, Taxistände, Kiss & Fly verändert? Dann die Buchten neu legen.
func _check_bays() -> void:
	var sig := ""
	for spec: Array in BAY_SPECS:
		for it: Dictionary in game.items_of(String(spec[0])):
			var p: Vector3 = it["pos"]
			sig += "%s%d,%d,%d;" % [spec[0], roundi(p.x), roundi(p.z), int(it["rot"])]
	if sig != _bay_sig:
		_bay_sig = sig
		verge_dirty = true


## Buchten aus den Haltepunkten der Bauteile (nächste rechte Spur wie in traffic.gd).
func _compute_bays() -> void:
	bays = {}
	for spec: Array in BAY_SPECS:
		for it: Dictionary in game.items_of(String(spec[0])):
			var xf := (it["node"] as Node3D).transform
			var hp: Vector3 = xf * Vector3(0, 0, -4.5)
			var best: Array = []
			var bd := 14.0
			for l: Dictionary in roads():
				if not Catalog.has_sides(String(l["kind"])):
					continue
				if not (l["bounds"] as Rect2).grow(14.0).has_point(Vector2(hp.x, hp.z)):
					continue
				for d: int in [1, -1]:
					var n := lanes(l, d)
					if n == 0:
						continue
					var path := lane_path(l, d, n - 1)
					var run := 0.0
					for i in range(path.size()):
						if i > 0:
							run += path[i].distance_to(path[i - 1])
						var dd := Vector2(path[i].x - hp.x, path[i].z - hp.z).length()
						if dd < bd and run > 3.0 and run < Spline.length(path) - 3.0:
							bd = dd
							best = [l, d, n - 1, run]
			if best.is_empty():
				continue
			var l: Dictionary = best[0]
			var d: int = best[1]
			var k: int = best[2]
			var pos: float = best[3]
			var w: float = Catalog.LINES[l["kind"]]["width"]
			var n2 := lanes(l, d)
			var other := lanes(l, -d)
			var lw := w / float(maxi(n2 + other, 1))
			var off := lw * (float(k) + 0.5) if other > 0 else lw * (float(k) + 0.5 - float(n2) * 0.5)
			var shift := 3.2 if spec[0] == "haltestelle" else 3.0
			var depth := clampf(off + shift + 1.4 - w * 0.5, 1.5, 4.0)
			var s0 := pos + float(spec[2])
			var s1 := pos + float(spec[3])
			var s_len := Spline.length(lane_path(l, d, k))
			if d < 0:
				var t := s0
				s0 = s_len - s1
				s1 = s_len - t
			var key := iid(l)
			if not bays.has(key):
				bays[key] = []
			(bays[key] as Array).append([d, s0, s1, depth, String(spec[1])])


func rebuild() -> void:
	dirty = false
	nodes = []
	line_nodes = {}
	lane_cache = {}
	conn_cache = {}
	for c in visuals.get_children():
		c.queue_free()
	for l: Dictionary in roads():
		var s: PackedVector3Array = l["samples"]
		var ids := []
		for at_start: bool in [true, false]:
			var p: Vector3 = s[0] if at_start else s[s.size() - 1]
			var ni := _node_near(p)
			if ni < 0:
				nodes.append({"pos": p, "ends": [], "control": "", "major": [], "radius": 0.0, "lamps": [], "timer": 0.0})
				ni = nodes.size() - 1
			var other: Vector3 = s[mini(6, s.size() - 1)] if at_start else s[maxi(s.size() - 7, 0)]
			var out_dir := Vector3(other.x - p.x, 0, other.z - p.z).normalized()
			(nodes[ni]["ends"] as Array).append({"line": l, "at_start": at_start, "out": out_dir, "w": float(Catalog.LINES[l["kind"]]["width"])})
			ids.append(ni)
		line_nodes[iid(l)] = ids
	for ni in range(nodes.size()):
		_setup_node(ni)
	_check_bays()
	verge_dirty = false
	_compute_bays()
	for l: Dictionary in roads():
		_trim_mesh(l)
	for ni in range(nodes.size()):
		if (nodes[ni]["ends"] as Array).size() >= 3 or float(nodes[ni]["radius"]) > 0.0:
			_build_node_visuals(ni)


func _node_near(p: Vector3) -> int:
	for i in range(nodes.size()):
		if (nodes[i]["pos"] as Vector3).distance_to(p) < LINK:
			return i
	return -1


func _setup_node(ni: int) -> void:
	var n: Dictionary = nodes[ni]
	var ends: Array = n["ends"]
	var deg := ends.size()
	var wmax := 0.0
	var kinds := {}
	for e: Dictionary in ends:
		wmax = maxf(wmax, float(e["w"]))
		kinds[e["line"]["kind"]] = true
	if deg >= 3 or (deg == 2 and kinds.size() > 1):
		# so weit zurücknehmen, dass sich die Straßenbänder spitzwinkliger Zufahrten nicht überlappen
		var min_ang := PI
		for a in range(deg):
			for b in range(a + 1, deg):
				var ang := acos(clampf((ends[a]["out"] as Vector3).dot(ends[b]["out"]), -1.0, 1.0))
				min_ang = minf(min_ang, ang)
		var need := wmax * 0.5 / maxf(tan(min_ang * 0.5), 0.05) + 2.0
		n["radius"] = clampf(maxf(wmax * 0.5 + 3.0, need), wmax * 0.5 + 3.0, 32.0)
	if deg < 3:
		n["control"] = ""
		return
	# Hauptrichtung: zwei Zufahrten mit den meisten Spuren, bei Gleichstand die geradeste Verbindung
	var best := [0, 1]
	var best_score := -INF
	for a in range(deg):
		for b in range(a + 1, deg):
			var ea: Dictionary = ends[a]
			var eb: Dictionary = ends[b]
			var lanes_sum := total_lanes(ea["line"]) + total_lanes(eb["line"])
			var straight := -(ea["out"] as Vector3).dot(eb["out"])
			var score := float(lanes_sum) * 10.0 + straight
			if score > best_score:
				best_score = score
				best = [a, b]
	n["major"] = best
	var key := control_key(n["pos"])
	var ctrl: String = game.junction_controls.get(key, "")
	if ctrl == "":
		var max_l := 0
		var min_l := 99
		for e: Dictionary in ends:
			max_l = maxi(max_l, total_lanes(e["line"]))
			min_l = mini(min_l, total_lanes(e["line"]))
		ctrl = "ampel" if max_l >= 4 and deg >= 3 else ("vorfahrt" if max_l != min_l else "rechts")
	n["control"] = ctrl


static func control_key(p: Vector3) -> String:
	return "%d,%d" % [roundi(p.x), roundi(p.z)]


## Straßenband zwischen den Kreuzungen neu erzeugen (an Kreuzungen zurückgenommen).
func _trim_mesh(l: Dictionary) -> void:
	var mi := l["node"] as MeshInstance3D
	if mi == null:
		return
	var s: PackedVector3Array = l["samples"]
	var length := Spline.length(s)
	var ids: Array = line_nodes[iid(l)]
	var t0: float = nodes[ids[0]]["radius"]
	var t1: float = nodes[ids[1]]["radius"]
	if t0 + t1 > length - 1.0:
		var k := (length - 1.0) / maxf(t0 + t1, 0.01)
		t0 *= k
		t1 *= k
	var sub := Spline.sub(s, t0, length - t1)
	var w: float = Catalog.LINES[l["kind"]]["width"]
	mi.mesh = Spline.ribbon(sub, w, float(l.get("y", 0.06)))
	var sm := mi.material_override as ShaderMaterial
	if sm != null:
		sm.set_shader_parameter("len", Spline.length(sub))
		sm.set_shader_parameter("mark", int(Catalog.LINES[l["kind"]]["mark"]))
		sm.set_shader_parameter("flip", 1 if bool(l.get("flip", false)) else 0)
	# Gehweg, Radweg, Bäume, Laternen und Haltebuchten
	var old := mi.get_node_or_null("Seitenraum")
	if old != null:
		mi.remove_child(old)
		old.queue_free()
	var side := String(l.get("side", "ohne"))
	var my_bays: Array = bays.get(iid(l), [])
	if Catalog.has_sides(String(l["kind"])) and (side != "ohne" or not my_bays.is_empty()):
		var verge := Streetscape.build(sub, w, side, float(l.get("y", 0.06)) - mi.position.y, my_bays)
		mi.add_child(verge)


# ---------------------------------------------------------------- Spuren

func lanes(l: Dictionary, d: int) -> int:
	var spec: Array = Catalog.LINES[l["kind"]].get("lanes", [1, 1])
	var fwd: int = spec[0]
	var bwd: int = spec[1]
	if bool(l.get("flip", false)):
		var t := fwd
		fwd = bwd
		bwd = t
	return fwd if d > 0 else bwd


func total_lanes(l: Dictionary) -> int:
	return lanes(l, 1) + lanes(l, -1)


func trims(l: Dictionary) -> Array:
	var ids: Array = line_nodes.get(iid(l), [-1, -1])
	var s: PackedVector3Array = l["samples"]
	var length := Spline.length(s)
	var t0: float = nodes[ids[0]]["radius"] if ids[0] >= 0 else 0.0
	var t1: float = nodes[ids[1]]["radius"] if ids[1] >= 0 else 0.0
	if t0 + t1 > length - 1.0:
		var k := (length - 1.0) / maxf(t0 + t1, 0.01)
		t0 *= k
		t1 *= k
	return [t0, t1]


## Mittellinie einer Spur in Fahrtrichtung (zwischen den Kreuzungen).
func lane_path(l: Dictionary, d: int, k: int) -> PackedVector3Array:
	var key := "%d|%d|%d" % [iid(l), d, k]
	if lane_cache.has(key):
		return lane_cache[key]
	var s: PackedVector3Array = l["samples"]
	var length := Spline.length(s)
	var tr := trims(l)
	var sub := Spline.sub(s, float(tr[0]), length - float(tr[1]))
	if d < 0:
		sub.reverse()
	var n := lanes(l, d)
	var other := lanes(l, -d)
	var lw: float = float(Catalog.LINES[l["kind"]]["width"]) / float(maxi(n + other, 1))
	var off := lw * (float(k) + 0.5) if other > 0 else lw * (float(k) + 0.5 - float(n) * 0.5)
	var out := PackedVector3Array()
	for i in range(sub.size()):
		var t: Vector3
		if i == 0:
			t = sub[1] - sub[0]
		elif i == sub.size() - 1:
			t = sub[i] - sub[i - 1]
		else:
			t = sub[i + 1] - sub[i - 1]
		t.y = 0.0
		t = t.normalized()
		out.append(sub[i] + t.cross(Vector3.UP) * off)
	lane_cache[key] = out
	return out


## Weg im Seitenraum (Gehweg, Radweg): Mitte der Straße zwischen den Kreuzungen, um off Meter zur
## Seite sg versetzt, auf Gehweghöhe.
func side_path(l: Dictionary, sg: int, off: float) -> PackedVector3Array:
	var s: PackedVector3Array = l["samples"]
	var tr := trims(l)
	var sub := Spline.sub(s, float(tr[0]) + 1.5, Spline.length(s) - float(tr[1]) - 1.5)
	var out := PackedVector3Array()
	for i in range(sub.size()):
		var t := sub[mini(i + 1, sub.size() - 1)] - sub[maxi(i - 1, 0)]
		t.y = 0.0
		if t.length() < 0.001:
			continue
		var q := sub[i] + t.normalized().cross(Vector3.UP) * float(sg) * off
		out.append(Vector3(q.x, Streetscape.TOP + sub[i].y, q.z))
	return out


## Knoten, den man in Richtung d am Ende der Straße erreicht (bzw. von dem man bei d startet).
func node_ahead(l: Dictionary, d: int) -> int:
	var ids: Array = line_nodes.get(iid(l), [-1, -1])
	return ids[1] if d > 0 else ids[0]


func node_behind(l: Dictionary, d: int) -> int:
	var ids: Array = line_nodes.get(iid(l), [-1, -1])
	return ids[0] if d > 0 else ids[1]


## Index der Zufahrt am Knoten, über die Straße l an ihm hängt (Anfang oder Ende).
func end_index(ni: int, l: Dictionary, at_start: bool) -> int:
	var ends: Array = nodes[ni]["ends"]
	for i in range(ends.size()):
		if is_same(ends[i]["line"], l) and bool(ends[i]["at_start"]) == at_start:
			return i
	return -1


## Ankunft am Knoten über (l, d): Zufahrt-Index am Knoten.
func arrival_end(l: Dictionary, d: int) -> int:
	return end_index(node_ahead(l, d), l, d < 0)


## Mögliche Ausfahrten am erreichten Knoten: [Straße, Richtung]. Kein Wenden, außer in der Sackgasse.
func exits(l: Dictionary, d: int) -> Array:
	var ni := node_ahead(l, d)
	if ni < 0:
		return []
	var out := []
	for e: Dictionary in nodes[ni]["ends"]:
		var nl: Dictionary = e["line"]
		var nd := 1 if bool(e["at_start"]) else -1
		if is_same(nl, l) and nd == -d:
			continue
		if lanes(nl, nd) > 0:
			out.append([nl, nd])
	return out


func degree(ni: int) -> int:
	return (nodes[ni]["ends"] as Array).size() if ni >= 0 else 0


## Kurvenbogen durch die Kreuzung von einer Spur zur nächsten.
func conn_path(from_l: Dictionary, fd: int, fk: int, to_l: Dictionary, td: int, tk: int) -> PackedVector3Array:
	var key := "%d|%d|%d>%d|%d|%d" % [iid(from_l), fd, fk, iid(to_l), td, tk]
	if conn_cache.has(key):
		return conn_cache[key]
	var a := lane_path(from_l, fd, fk)
	var b := lane_path(to_l, td, tk)
	var p0: Vector3 = a[a.size() - 1]
	var d0 := (a[a.size() - 1] - a[maxi(a.size() - 3, 0)]).normalized()
	var p3: Vector3 = b[0]
	var d3 := (b[mini(2, b.size() - 1)] - b[0]).normalized()
	var dist := p0.distance_to(p3)
	var out := PackedVector3Array()
	if dist < 0.3:
		out.append(p0)
		out.append(p3)
	else:
		var h := dist * 0.42
		var p1 := p0 + d0 * h
		var p2 := p3 - d3 * h
		var steps := maxi(4, ceili(dist / 0.5))
		for i in range(steps + 1):
			var t := float(i) / float(steps)
			var u := 1.0 - t
			out.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)
	conn_cache[key] = out
	return out


## Abbiegerichtung: -1 links, 0 geradeaus, 1 rechts
func turn_of(from_l: Dictionary, fd: int, to_l: Dictionary, td: int) -> int:
	var ni := node_ahead(from_l, fd)
	var ea: Dictionary = nodes[ni]["ends"][arrival_end(from_l, fd)]
	var eb: Dictionary = nodes[ni]["ends"][end_index(ni, to_l, td > 0)]
	var come := -(ea["out"] as Vector3)
	var go: Vector3 = eb["out"]
	var cr := come.cross(go).y
	if come.dot(go) > 0.7:
		return 0
	return 1 if cr < 0.0 else -1


# ---------------------------------------------------------------- Regelung

func control_of(ni: int) -> String:
	return String(nodes[ni]["control"]) if ni >= 0 else ""


func is_major(ni: int, end_i: int) -> bool:
	return end_i in (nodes[ni]["major"] as Array)


## Ampelzustand für eine Zufahrt: gruen, gelb, rot
func signal_at(ni: int, end_i: int) -> String:
	var n: Dictionary = nodes[ni]
	var t := fmod(float(n["timer"]), _cycle())
	var phase := 0
	var acc := 0.0
	for i in range(PHASES.size()):
		acc += float(PHASES[i])
		if t < acc:
			phase = i
			break
	var group_a := is_major(ni, end_i)
	match phase:
		0:
			return "gruen" if group_a else "rot"
		1:
			return "gelb" if group_a else "rot"
		3:
			return "rot" if group_a else "gruen"
		4:
			return "rot" if group_a else "gelb"
	return "rot"


func _cycle() -> float:
	var total := 0.0
	for p: float in PHASES:
		total += p
	return total


## Zufahrt rechts von dieser (für rechts vor links): Index oder -1
func right_of(ni: int, end_i: int) -> int:
	var ends: Array = nodes[ni]["ends"]
	var come := -(ends[end_i]["out"] as Vector3)
	var best := -1
	var best_dot := 0.5
	for i in range(ends.size()):
		if i == end_i:
			continue
		var o: Vector3 = ends[i]["out"]
		# Zufahrt von rechts: deren Straße liegt rechts der eigenen Fahrtrichtung
		var right := come.cross(Vector3.UP)
		var dt := o.dot(right)
		if dt > best_dot:
			best_dot = dt
			best = i
	return best


func step(dt: float) -> void:
	ensure()
	for ni in range(nodes.size()):
		var n: Dictionary = nodes[ni]
		if n["control"] != "ampel":
			continue
		n["timer"] = float(n["timer"]) + dt
		var lamps: Array = n["lamps"]
		for li in range(lamps.size()):
			var entry: Array = lamps[li]
			var st := signal_at(ni, int(entry[0]))
			(entry[1] as MeshInstance3D).material_override = lamp_mats["rot" if st == "rot" else "aus"]
			(entry[2] as MeshInstance3D).material_override = lamp_mats["gelb" if st == "gelb" else "aus"]
			(entry[3] as MeshInstance3D).material_override = lamp_mats["gruen" if st == "gruen" else "aus"]


## Kreuzungs-Werkzeug: Regelung am nächsten Knoten weiterschalten.
func cycle_control(p: Vector3) -> String:
	ensure()
	var ni := nearest_junction(p)
	if ni < 0:
		return ""
	var cur: String = nodes[ni]["control"]
	var nxt: String = CONTROLS[(CONTROLS.find(cur) + 1) % CONTROLS.size()]
	game.junction_controls[control_key(nodes[ni]["pos"])] = nxt
	dirty = true
	rebuild()
	return nxt


func nearest_junction(p: Vector3, max_d: float = 14.0) -> int:
	var best := -1
	var bd := max_d
	for i in range(nodes.size()):
		if degree(i) < 3:
			continue
		var d := Vector2((nodes[i]["pos"] as Vector3).x - p.x, (nodes[i]["pos"] as Vector3).z - p.z).length()
		if d < bd:
			bd = d
			best = i
	return best


# ---------------------------------------------------------------- Darstellung der Kreuzungen

func _approach_point(ni: int, e: Dictionary) -> Vector3:
	var l: Dictionary = e["line"]
	var s: PackedVector3Array = l["samples"]
	var length := Spline.length(s)
	var tr := trims(l)
	return Spline.sample_at(s, float(tr[0])) if bool(e["at_start"]) else Spline.sample_at(s, length - float(tr[1]))


func _build_node_visuals(ni: int) -> void:
	var n: Dictionary = nodes[ni]
	var ends: Array = n["ends"]
	var c: Vector3 = n["pos"]
	# Kreuzungsfläche aus den Ecken der zurückgenommenen Straßen; zwischen zwei Zufahrten ein
	# gerundeter Bordstein (Bogen über den Schnittpunkt der Straßenränder) mit Randlinie
	var arms := []
	for e: Dictionary in ends:
		var p := _approach_point(ni, e)
		var out: Vector3 = e["out"]
		var ang := atan2(out.z, out.x)
		arms.append([ang, p, out, float(e["w"]), String((e["line"] as Dictionary).get("side", "ohne"))])
	arms.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var ring := []
	var curbs := []
	for i in range(arms.size()):
		var A: Array = arms[i]
		var B: Array = arms[(i + 1) % arms.size()]
		var pa: Vector3 = A[1]
		var oa: Vector3 = A[2]
		var pb: Vector3 = B[1]
		var ob: Vector3 = B[2]
		# Rand von A, der zu B zeigt, und Rand von B, der zu A zeigt
		var sa := oa.cross(Vector3.UP)
		var sb := ob.cross(Vector3.UP)
		var ea := pa + sa * float(A[3]) * 0.5
		var eb := pb - sb * float(B[3]) * 0.5
		var ea2 := pa - sa * float(A[3]) * 0.5
		ring.append(ea2)
		ring.append(ea)
		# Kontrollpunkt: Schnitt der beiden Ränder (sonst die Mitte)
		var ctrl := (ea + eb) * 0.5
		var den := oa.x * ob.z - oa.z * ob.x
		if absf(den) > 0.05:
			var t := ((eb.x - ea.x) * ob.z - (eb.z - ea.z) * ob.x) / den
			if t < 0.0 and t > -40.0:
				ctrl = ea + oa * t
		var arc := []
		for j in range(1, 8):
			var u := float(j) / 8.0
			arc.append(ea * (1.0 - u) * (1.0 - u) + ctrl * 2.0 * (1.0 - u) * u + eb * u * u)
		ring.append_array(arc)
		curbs.append([ea] + arc + [eb])
		# Gehwegecke entlang des Bogens
		var wa := Streetscape.width_of(String(A[4]))
		var wb := Streetscape.width_of(String(B[4]))
		if wa > 0.0 or wb > 0.0:
			var cv: Array = [ea] + arc + [eb]
			var outs := []
			for j in range(cv.size()):
				var tj: Vector3 = (cv[mini(j + 1, cv.size() - 1)] as Vector3) - (cv[maxi(j - 1, 0)] as Vector3)
				tj.y = 0.0
				var oj := tj.normalized().cross(Vector3.UP) if tj.length() > 0.001 else Vector3.ZERO
				var away := (cv[j] as Vector3) - c
				away.y = 0.0
				if oj.dot(away) < 0.0:
					oj = -oj
				outs.append(oj)
			var cside := String(A[4]) if String(A[4]) == String(B[4]) else "gehweg"
			var cm := Streetscape.corner(cv, outs, wa, wb, cside, Streetscape.TOP)
			if cm != null:
				visuals.add_child(cm)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.07
	for i in range(ring.size()):
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % ring.size()]
		for v: Vector3 in [Vector3(c.x, y, c.z), Vector3(b.x, y, b.z), Vector3(a.x, y, a.z)]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var patch := MeshInstance3D.new()
	patch.mesh = st.commit()
	patch.material_override = mat_asphalt
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visuals.add_child(patch)
	# Bordstein und weiße Randlinie entlang der Bögen
	var ck := Kit.new()
	for cv: Array in curbs:
		for j in range(cv.size() - 1):
			var a: Vector3 = cv[j]
			var b: Vector3 = cv[j + 1]
			var d := b - a
			d.y = 0.0
			if d.length() < 0.05:
				continue
			var nrm := d.normalized().cross(Vector3.UP)
			# Randlinie 0,4 m innen, Bordstein außen
			var toward_c := Vector3(c.x - a.x, 0, c.z - a.z)
			if nrm.dot(toward_c) < 0.0:
				nrm = -nrm
			var li0 := a + nrm * 0.35
			var li1 := b + nrm * 0.35
			ck.quad(Vector3(li0.x, 0.082, li0.z) - nrm * 0.08, Vector3(li1.x, 0.082, li1.z) - nrm * 0.08,
				Vector3(li1.x, 0.082, li1.z) + nrm * 0.08, Vector3(li0.x, 0.082, li0.z) + nrm * 0.08, Color(0.9, 0.9, 0.86), Vector3(a.x, -5, a.z))
			ck.quad(Vector3(a.x, 0.16, a.z), Vector3(b.x, 0.16, b.z), Vector3(b.x, 0.16, b.z) - nrm * 0.3, Vector3(a.x, 0.16, a.z) - nrm * 0.3,
				Color(0.72, 0.72, 0.7), Vector3(a.x, -5, a.z))
			ck.quad(Vector3(a.x, 0.07, a.z), Vector3(b.x, 0.07, b.z), Vector3(b.x, 0.16, b.z), Vector3(a.x, 0.16, a.z),
				Color(0.6, 0.6, 0.58), Vector3(a.x, 0.1, a.z) - nrm)
	if ck.count > 0:
		visuals.add_child(ck.instance("Bordstein"))
	if ends.size() < 3:
		return
	# Haltelinien, Schilder, Ampeln je Zufahrt
	var k := Kit.new()
	# Fußgängerüberwege an Zufahrten mit Gehweg (zwischen Haltelinie und Kreuzungsmitte)
	for e: Dictionary in ends:
		if String((e["line"] as Dictionary).get("side", "ohne")) == "ohne":
			continue
		var zo: Vector3 = e["out"]
		var zr := zo.cross(Vector3.UP)
		var zp := _approach_point(ni, e)
		var zw: float = e["w"]
		var x := -zw * 0.5 + 0.35
		while x + 0.5 <= zw * 0.5 - 0.3:
			var q0 := zp + zr * (x + 0.25) - zo * 0.5
			var q1 := zp + zr * (x + 0.25) - zo * 3.0
			_flat_bar(k, q0, q1, zr, 0.5)
			x += 1.0
	var ctrl: String = n["control"]
	var lamps := []
	for ei in range(ends.size()):
		var e: Dictionary = ends[ei]
		var l: Dictionary = e["line"]
		var out: Vector3 = e["out"]
		var come := -out
		var right_in := come.cross(Vector3.UP)
		var p := _approach_point(ni, e)
		var w: float = e["w"]
		var d_in := -1 if bool(e["at_start"]) else 1
		if lanes(l, d_in) == 0:
			continue
		var incoming_w := w * float(lanes(l, d_in)) / float(maxi(total_lanes(l), 1))
		var from_center := 0.0 if lanes(l, -d_in) > 0 else -w * 0.5
		var major := is_major(ni, ei)
		# Haltelinie (durchgezogen bei Ampel, gestrichelt bei Vorfahrt achten)
		if ctrl == "ampel" or (ctrl == "vorfahrt" and not major):
			var steps := 6 if ctrl == "vorfahrt" else 1
			for sgi in range(steps):
				var a0 := from_center + incoming_w * float(sgi) / float(steps)
				var a1 := a0 + incoming_w / float(steps) * (0.6 if steps > 1 else 1.0)
				var q0 := p + right_in * a0 + out * 0.6
				var q1 := p + right_in * a1 + out * 0.6
				_flat_bar(k, q0, q1, out, 0.45 if steps == 1 else 0.3)
		var pole := p + right_in * (w * 0.5 + 0.9) + out * 1.2
		if ctrl == "ampel":
			lamps.append(_traffic_light(k, pole, out, ei))
		elif ctrl == "vorfahrt":
			_sign(k, pole, out, "haupt" if major else "achten")
		else:
			_sign(k, pole, out, "rechts")
	var props := k.instance("Schilder")
	visuals.add_child(props)
	n["lamps"] = lamps
	for entry: Array in lamps:
		for j in range(1, 4):
			visuals.add_child(entry[j])


func _flat_bar(k: Kit, a: Vector3, b: Vector3, along: Vector3, thick: float) -> void:
	var y := 0.085
	var h := along * thick * 0.5
	k.quad(Vector3(a.x, y, a.z) - h, Vector3(b.x, y, b.z) - h, Vector3(b.x, y, b.z) + h, Vector3(a.x, y, a.z) + h,
		Color(0.9, 0.9, 0.86), Vector3(a.x, -5, a.z))


func _sign(k: Kit, pos: Vector3, face: Vector3, kind: String) -> void:
	var grey := Color(0.5, 0.52, 0.55)
	k.cyl(pos, pos + Vector3(0, 2.3, 0), 0.05, 0.05, grey, 6)
	var c := pos + Vector3(0, 2.1, 0) + face * 0.08
	var right := face.cross(Vector3.UP).normalized()
	var n := face
	match kind:
		"haupt":
			k.panel(c, (right + Vector3.UP) * 0.3, (Vector3.UP - right) * 0.3, Color(0.95, 0.95, 0.92), n)
			k.panel(c + n * 0.01, (right + Vector3.UP) * 0.2, (Vector3.UP - right) * 0.2, Color(0.95, 0.78, 0.15), n)
		"achten":
			_triangle(k, c, right, n, -1.0, 0.5, Color(0.85, 0.12, 0.1))
			_triangle(k, c + n * 0.01, right, n, -1.0, 0.33, Color(0.95, 0.95, 0.92))
		_:
			_triangle(k, c, right, n, 1.0, 0.5, Color(0.85, 0.12, 0.1))
			_triangle(k, c + n * 0.01, right, n, 1.0, 0.33, Color(0.95, 0.95, 0.92))


func _triangle(k: Kit, c: Vector3, right: Vector3, n: Vector3, up_sign: float, size: float, col: Color) -> void:
	var top := c + Vector3.UP * size * 0.6 * up_sign
	var a := c - Vector3.UP * size * 0.4 * up_sign - right * size * 0.55
	var b := c - Vector3.UP * size * 0.4 * up_sign + right * size * 0.55
	k.tri(top, a, b, col, c - n)


## Ampel mit Mast und Ausleger. Gibt [Zufahrt, Lampe rot, gelb, grün] zurück.
## face zeigt zu den ankommenden Autos.
func _traffic_light(k: Kit, pos: Vector3, face: Vector3, ei: int) -> Array:
	var dark := Color(0.16, 0.17, 0.18)
	var grey := Color(0.45, 0.47, 0.5)
	k.cyl(pos, pos + Vector3(0, 4.6, 0), 0.09, 0.07, grey, 8)
	var right := face.cross(Vector3.UP).normalized()
	var arm_end := pos + Vector3(0, 4.5, 0) + right * 2.6
	k.cyl(pos + Vector3(0, 4.5, 0), arm_end, 0.05, 0.05, grey, 6)
	var head := arm_end + Vector3(0, -0.6, 0)
	k.box(head - Vector3(0.22, 0.55, 0.22), head + Vector3(0.22, 0.55, 0.22), dark, Transform3D(Basis.looking_at(-face, Vector3.UP), Vector3.ZERO))
	# zweite Signalgruppe am Mast
	var low := pos + Vector3(0, 2.5, 0)
	k.box(low - Vector3(0.18, 0.45, 0.18) + face * 0.15, low + Vector3(0.18, 0.45, 0.18) + face * 0.15, dark)
	var entry := [ei]
	var cols := ["rot", "gelb", "gruen"]
	for j in range(3):
		var lamp := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.24, 0.24, 0.08)
		lamp.mesh = bm
		lamp.basis = Basis.looking_at(-face, Vector3.UP)
		lamp.position = head + Vector3(0, 0.33 - 0.33 * float(j), 0) + face * 0.24
		lamp.material_override = lamp_mats["aus"]
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.name = cols[j]
		entry.append(lamp)
	return entry
