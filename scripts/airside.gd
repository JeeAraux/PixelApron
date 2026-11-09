extends RefCounted
## Rollnetz als Graph: Knoten alle 5 m entlang von Pisten, Rollwegen und Vorfeldern,
## Verbindungen dort, wo sich Flächen berühren oder kreuzen, dazu ein Knoten je Stand.
## Wegsuche mit A*.

const Catalog = preload("res://scripts/catalog.gd")

const STEP := 5
const CELL := 20.0

var pos := PackedVector3Array()
var kind := PackedStringArray()
var line_idx := PackedInt32Array()   # Index in game.lines, -1 für Stände
var adj: Array = []                  # je Knoten: Array von Nachbarindizes
var line_nodes: Dictionary = {}      # Index in game.lines -> Array der Knoten in Reihenfolge
var stand_node: Dictionary = {}      # Stand-Datensatz (Instanz-ID des Knotens) -> Knoten
var near: Array = []                 # je Knoten: Knoten im Umkreis von NEAR m (für Reservierungen)

const NEAR := 30.0


func build(lines: Array, stands: Array) -> void:
	pos = PackedVector3Array()
	kind = PackedStringArray()
	line_idx = PackedInt32Array()
	adj = []
	near = []
	line_nodes = {}
	stand_node = {}
	for li in range(lines.size()):
		var l: Dictionary = lines[li]
		var k: String = l["kind"]
		if not (k in ["piste", "rollweg", "vorfeld"]):
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
	_cross_links()
	for st: Dictionary in stands:
		var p: Vector3 = st["pos"]
		var id := _add(p, "stand", -1)
		var near := _nearest_of_kind(p, "vorfeld", 45.0, 3)
		for n: int in near:
			_link(id, n)
		stand_node[(st["node"] as Node).get_instance_id()] = id
	_near_lists()


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


func _nearest_of_kind(p: Vector3, k: String, max_d: float, count: int) -> Array:
	var found := []
	for i in range(pos.size()):
		if kind[i] != k:
			continue
		var d := pos[i].distance_to(p)
		if d <= max_d:
			found.append([d, i])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out := []
	for f: Array in found.slice(0, count):
		out.append(f[1])
	return out


func nearest(p: Vector3, k: String = "") -> int:
	var best := -1
	var bd := INF
	for i in range(pos.size()):
		if k != "" and kind[i] != k:
			continue
		var d := pos[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


## Kürzester Weg von a nach b als Knotenliste (leer, wenn es keinen gibt).
## blocked: Knoten, die gemieden werden (z. B. von anderen reserviert). Stände sind nur Start oder Ziel.
func path(a: int, b: int, blocked: Dictionary = {}) -> Array:
	if a < 0 or b < 0:
		return []
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
		for nb: int in adj[cur]:
			if closed.has(nb):
				continue
			if nb != b and (kind[nb] == "stand" or blocked.has(nb)):
				continue
			var cost := float(g[cur]) + pos[cur].distance_to(pos[nb]) * (1.6 if kind[nb] == "piste" else 1.0)
			if not g.has(nb) or cost < float(g[nb]):
				g[nb] = cost
				came[nb] = cur
				if not open.has(nb):
					open.append(nb)
	return []
