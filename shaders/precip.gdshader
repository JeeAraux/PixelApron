shader_type spatial;
// Regen und Schnee: Billboard wie StandardMaterial, aber über Hallen (Dach ab in der Innenansicht)
// und über offenen Garagen verschwinden die Tropfen unterhalb der Dachkante.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 col : source_color = vec4(0.75, 0.82, 0.92, 0.45);
uniform int fixed_y = 1;
uniform vec4 rects[24];      // x0, z0, x1, z1
uniform float tops[24];      // Dachhöhe je Rechteck
uniform int count = 0;

varying vec3 wpos;

void vertex() {
	if (fixed_y == 1) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
			vec4(0.0, 1.0, 0.0, 0.0), vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0), MODEL_MATRIX[3]);
	} else {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	wpos = MODEL_MATRIX[3].xyz;
}

void fragment() {
	for (int i = 0; i < 24; i++) {
		if (i >= count) {
			break;
		}
		vec4 r = rects[i];
		if (wpos.x > r.x && wpos.x < r.z && wpos.z > r.y && wpos.z < r.w && wpos.y < tops[i]) {
			discard;
		}
	}
	ALBEDO = col.rgb * COLOR.rgb;
	ALPHA = col.a * COLOR.a;
}
