extends Node
## Rendert Vorschaubilder für das Baumenü: jedes Teil einmal in einer eigenen kleinen Szene
## aus demselben Iso-Winkel wie das Spiel.

const Catalog = preload("res://scripts/catalog.gd")
const Factory = preload("res://scripts/factory.gd")

const SIZE := 72


func render(ids: Array) -> Dictionary:
	var vps := {}
	var view := Basis.from_euler(Vector3(deg_to_rad(-30.0), deg_to_rad(45.0), 0.0))
	for id: String in ids:
		var vp := SubViewport.new()
		vp.size = Vector2i(SIZE, SIZE)
		vp.transparent_bg = true
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(vp)
		var model: Node3D
		if Catalog.LINES.has(id):
			model = Factory.make_line_thumb(id)
		elif Catalog.TOOLS.has(id):
			model = Factory.make_tool_thumb(id)
		else:
			model = Factory.make_item(id)
		if id == "stand" or id == "stand_aussen" or id == "bushalt":
			Factory.blk(model, Vector3(-24, -0.3, -26), Vector3(24, 0.0, 26), Color(0.47, 0.46, 0.42))
		elif Catalog.is_inside(id):
			var sz: Vector2 = Catalog.ITEMS[id]["size"]
			var k := maxf(sz.x, sz.y) * 0.5 + 0.6
			Factory.blk(model, Vector3(-k, -0.2, -k), Vector3(k, 0.0, k), Factory.FLOOR)
		vp.add_child(model)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.62, 0.66, 0.74)
		env.ambient_light_energy = 0.6
		var we := WorldEnvironment.new()
		we.environment = env
		vp.add_child(we)
		var sun := DirectionalLight3D.new()
		sun.light_energy = 1.15
		sun.basis = Basis.looking_at(Vector3(0.55, -0.75, -0.35).normalized(), Vector3.UP)
		vp.add_child(sun)
		var box := Factory.bounds_of(model)
		var c := box.get_center()
		var reach := 0.5
		for i in range(8):
			var local := box.get_endpoint(i) - c
			reach = maxf(reach, maxf(absf(local.dot(view.x)), absf(local.dot(view.y))))
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = reach * 2.15
		cam.near = 1.0
		cam.far = 2000.0
		cam.transform = Transform3D(view, c + view.z * 500.0)
		vp.add_child(cam)
		cam.make_current()
		vps[id] = vp
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var out := {}
	for id: String in vps:
		var vp: SubViewport = vps[id]
		var img := vp.get_texture().get_image()
		if img != null and not img.is_empty():
			out[id] = ImageTexture.create_from_image(img)
		vp.queue_free()
	return out
