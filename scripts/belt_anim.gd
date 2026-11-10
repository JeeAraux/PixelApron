extends MultiMeshInstance3D
## Koffer, die auf einem Förderband entlanglaufen (Gepäcktunnel, Gepäckband im Terminal).
## Läuft nur, solange das Band sichtbar ist.

var path := PackedVector3Array()
var cum := PackedFloat32Array()
var total := 0.0
var speed := 1.6
var offsets := PackedFloat32Array()
var loop := false


## pts: Mittellinie auf Bandhöhe. gap: mittlerer Abstand der Koffer. loop: geschlossenes Band.
func setup(pts: PackedVector3Array, bag: Mesh, spd: float, gap: float, closed: bool = false) -> void:
	path = pts
	loop = closed
	if loop and pts.size() > 1:
		path.append(pts[0])
	cum = PackedFloat32Array([0.0])
	total = 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
		cum.append(total)
	speed = spd
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bag
	var n := maxi(1, int(total / gap))
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = int(total * 100.0)
	var cols := [Color(0.62, 0.18, 0.16), Color(0.18, 0.28, 0.5), Color(0.12, 0.12, 0.13), Color(0.5, 0.4, 0.27),
		Color(0.25, 0.45, 0.3), Color(0.75, 0.72, 0.68), Color(0.85, 0.6, 0.15), Color(0.35, 0.2, 0.42)]
	offsets.resize(n)
	for i in range(n):
		offsets[i] = (float(i) + rng.randf_range(-0.3, 0.3)) * total / float(n)
		mm.set_instance_color(i, cols[rng.randi() % cols.size()])
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_update()


func _point(d: float) -> Array:
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if cum[mid] <= d:
			lo = mid
		else:
			hi = mid
	var seg := maxf(cum[hi] - cum[lo], 0.0001)
	var p := path[lo].lerp(path[hi], (d - cum[lo]) / seg)
	var dir := path[hi] - path[lo]
	return [p, dir]


func _update() -> void:
	if multimesh == null or total < 0.5:
		return
	var t := float(Time.get_ticks_msec()) / 1000.0
	for i in range(multimesh.instance_count):
		var d := fposmod(offsets[i] + t * speed, total)
		var pd: Array = _point(d)
		var dir: Vector3 = pd[1]
		dir.y = 0.0
		var b := Basis.IDENTITY
		if dir.length_squared() > 0.0001:
			b = Basis.looking_at(dir.normalized(), Vector3.UP).rotated(Vector3.UP, float(i % 3) * 0.35 - 0.35)
		multimesh.set_instance_transform(i, Transform3D(b, pd[0]))


func _process(_dt: float) -> void:
	if is_visible_in_tree():
		_update()
