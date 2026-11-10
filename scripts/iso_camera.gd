extends Node3D
## Feste Iso-Kamera im 2:1-Pixelraster (30 Grad Neigung, orthografisch).
## Verschieben mit WASD/Pfeiltasten oder mittlerer Maustaste, Zoom mit dem Mausrad,
## Q/E dreht in 90-Grad-Schritten. Die Position rastet auf Bildpixel ein, damit nichts flimmert.

const PITCH := -30.0
const DIST := 400.0
const MIN_ZOOM := 35.0
const MAX_ZOOM := 5200.0   # reicht für das ganze Spielfeld
const BOUND := 3000.0

var cam: Camera3D
var target := Vector3(20, 0, -10)
var yaw := 45.0
var yaw_goal := 45.0
var zoom := 190.0
var zoom_goal := 190.0
var dragging := false
var pan_speed := 1.0       # Einstellung Kamera-Tempo
var invert_zoom := false   # Einstellung Mausrad umkehren
var edge_scroll := false   # Einstellung Am Bildrand scrollen
var enabled := true        # aus, solange das Menü offen ist


func _ready() -> void:
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = zoom
	cam.near = 1.0
	cam.far = 2000.0
	add_child(cam)
	cam.make_current()
	_place()


func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN) and mb.pressed:
			var zoom_in := (mb.button_index == MOUSE_BUTTON_WHEEL_UP) != invert_zoom
			if zoom_in:
				zoom_goal = maxf(MIN_ZOOM, zoom_goal / 1.15)
			else:
				zoom_goal = minf(MAX_ZOOM, zoom_goal * 1.15)
			return true
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = mb.pressed
			return true
	elif event is InputEventMouseMotion and dragging:
		var mm := event as InputEventMouseMotion
		var k := zoom / maxf(1.0, get_tree().root.get_visible_rect().size.y)
		target -= _right() * mm.relative.x * k
		target += _fwd() * mm.relative.y * k * 2.0
		return true
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_Q:
				yaw_goal += 90.0
				return true
			if key.keycode == KEY_E:
				yaw_goal -= 90.0
				return true
	return false


func _right() -> Vector3:
	var a := deg_to_rad(yaw)
	return Vector3(cos(a), 0.0, -sin(a))


func _fwd() -> Vector3:
	var a := deg_to_rad(yaw)
	return Vector3(-sin(a), 0.0, -cos(a))


func _process(delta: float) -> void:
	var pan := Vector2.ZERO
	if not enabled:
		pass
	elif Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.y += 1.0
	if enabled:
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			pan.y -= 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			pan.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			pan.x += 1.0
		if edge_scroll and DisplayServer.window_is_focused():
			var vp := get_viewport()
			var m := vp.get_mouse_position()
			var size := vp.get_visible_rect().size
			if m.x >= 0.0 and m.y >= 0.0 and m.x <= size.x and m.y <= size.y:
				if m.x < 8.0:
					pan.x -= 1.0
				elif m.x > size.x - 8.0:
					pan.x += 1.0
				if m.y < 8.0:
					pan.y += 1.0
				elif m.y > size.y - 8.0:
					pan.y -= 1.0
	if pan != Vector2.ZERO:
		target += (_right() * pan.x + _fwd() * pan.y * 1.6) * zoom * 0.8 * pan_speed * delta
	target.x = clampf(target.x, -BOUND, BOUND)
	target.z = clampf(target.z, -BOUND, BOUND)
	var t := 1.0 - pow(0.0005, delta)
	yaw = lerpf(yaw, yaw_goal, t)
	if absf(yaw - yaw_goal) < 0.05:
		yaw = yaw_goal
	zoom = lerpf(zoom, zoom_goal, t)
	if absf(zoom - zoom_goal) < 0.05:
		zoom = zoom_goal
	_place()


func _place() -> void:
	var b := Basis.from_euler(Vector3(deg_to_rad(PITCH), deg_to_rad(yaw), 0.0))
	var dist := maxf(DIST, zoom * 1.1)
	cam.far = dist + zoom * 1.4 + 300.0
	var pos := Vector3(target.x, 0.0, target.z) + b.z * dist
	var vh := float(cam.get_viewport().get_visible_rect().size.y)
	if vh > 0.0 and yaw == yaw_goal:
		var texel := zoom / vh
		var pr := snappedf(pos.dot(b.x), texel)
		var pu := snappedf(pos.dot(b.y), texel)
		pos = b.x * pr + b.y * pu + b.z * pos.dot(b.z)
	cam.size = zoom
	cam.global_transform = Transform3D(b, pos)


## Reichweite für Schatten, damit auch weit herausgezoomt alles Schatten wirft.
func shadow_range() -> float:
	return maxf(DIST, zoom * 1.1) + zoom * 1.2 + 60.0


## Ausschnitt so wählen, dass das Rechteck (Boden, x/z) ganz zu sehen ist.
func frame(r: Rect2, aspect: float) -> void:
	target = Vector3(r.get_center().x, 0.0, r.get_center().y)
	# Diagonale der Iso-Projektion: Breite und Tiefe gehen je zur Hälfte in beide Bildachsen
	var a := deg_to_rad(yaw)
	var w := absf(r.size.x * cos(a)) + absf(r.size.y * sin(a))
	var d := absf(r.size.x * sin(a)) + absf(r.size.y * cos(a))
	zoom_goal = clampf(maxf(w / maxf(aspect, 0.5), d * 0.5) * 1.12, MIN_ZOOM, MAX_ZOOM)
