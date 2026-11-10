extends Node
## Bewegt die Teile eines Einrichtungsstücks. Hängt als Kind am Objekt und sucht seine
## Geschwister nach Namen:
##   Zeiger_h / Zeiger_m  Uhrzeiger nach der Spielzeit (Drehung um die lokale Z-Achse)
##   Dreh*                dreht sich langsam um die Hochachse (Meta "speed", Standard 0.3)
##   Wipp*                schaukelt um die X-Achse (Meta "amp", "speed")
##   Hub*                 hebt und senkt sich (Wasserfontänen, Meta "amp", "speed"; mit Meta "lift" fährt es wie ein Aufzug)
##   Blink*               blinkt (Meta "period")
##   Schieb*              Schiebetür, fährt um Meta "dx"/"dz" auf und zu
##   Schwenk*             pendelt um die Hochachse (Fahnen, Windsäcke; Meta "amp", "speed")
## Läuft nur, solange das Objekt sichtbar ist.

var parts: Array = []
var t := 0.0


func _ready() -> void:
	var p := get_parent()
	for c in p.get_children():
		if c is Node3D:
			var nm := String(c.name)
			if nm.begins_with("Zeiger") or nm.begins_with("Dreh") or nm.begins_with("Wipp") or nm.begins_with("Hub") \
					or nm.begins_with("Blink") or nm.begins_with("Schieb") or nm.begins_with("Schwenk"):
				parts.append([c, (c as Node3D).position, (c as Node3D).rotation])
	t = randf() * 10.0


func _process(dt: float) -> void:
	var p := get_parent() as Node3D
	if p == null or not p.is_visible_in_tree():
		return
	t += dt
	var minutes := float(Engine.get_meta("spielminuten", 0.0))
	for e: Array in parts:
		var n: Node3D = e[0]
		if not is_instance_valid(n):
			continue
		var nm := String(n.name)
		var base_pos: Vector3 = e[1]
		var base_rot: Vector3 = e[2]
		var dirz := float(n.get_meta("dir", 1.0))
		if nm.begins_with("Zeiger_h"):
			n.rotation.z = -fmod(minutes / 720.0, 1.0) * TAU * dirz
		elif nm.begins_with("Zeiger_m"):
			n.rotation.z = -fmod(minutes / 60.0, 1.0) * TAU * dirz
		elif nm.begins_with("Zeiger_s"):
			n.rotation.z = -fmod(float(Time.get_ticks_msec()) / 60000.0, 1.0) * TAU * dirz
		elif nm.begins_with("Dreh"):
			n.rotation.y = base_rot.y + t * float(n.get_meta("speed", 0.3))
		elif nm.begins_with("Wipp"):
			n.rotation.x = base_rot.x + sin(t * float(n.get_meta("speed", 2.0))) * float(n.get_meta("amp", 0.15))
		elif nm.begins_with("Hub") and n.has_meta("lift"):
			# Aufzug: fährt um Meta "lift" Meter hoch, wartet oben und unten
			var cyc := fmod(t * float(n.get_meta("speed", 0.25)), 2.0)
			var up := smoothstep(0.15, 0.85, cyc) if cyc < 1.0 else 1.0 - smoothstep(1.15, 1.85, cyc)
			n.position.y = base_pos.y + float(n.get_meta("lift")) * up
		elif nm.begins_with("Hub"):
			var ph := float(n.get_meta("phase", 0.0))
			n.scale.y = 0.75 + 0.25 * (0.5 + 0.5 * sin(t * float(n.get_meta("speed", 3.0)) + ph))
			n.position.y = base_pos.y
		elif nm.begins_with("Schieb"):
			# Schiebetür: öffnet sich, bleibt kurz offen, schließt wieder (Meta "dx" = Weg, "phase")
			var cyc := fmod(t * 0.45 + float(n.get_meta("phase", 0.0)), 3.0)
			var open := clampf(minf(cyc * 2.0, (2.2 - cyc) * 2.0), 0.0, 1.0)
			n.position = base_pos + Vector3(float(n.get_meta("dx", 0.0)), 0.0, float(n.get_meta("dz", 0.0))) * smoothstep(0.0, 1.0, open)
		elif nm.begins_with("Schwenk"):
			# Wind: langsames Pendeln mit kleinem Flattern darüber
			var sp := float(n.get_meta("speed", 0.6))
			var amp := float(n.get_meta("amp", 0.3))
			n.rotation.y = base_rot.y + sin(t * sp) * amp + sin(t * sp * 4.3 + 1.0) * amp * 0.12
		elif nm.begins_with("Blink"):
			var per := float(n.get_meta("period", 1.2))
			n.visible = fmod(t + float(n.get_meta("phase", 0.0)), per) < per * 0.55
