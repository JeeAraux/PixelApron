// Lichtkegel eines Landescheinwerfers in der Luft (nachts, bei Nebel und Regen deutlicher): additiv,
// hell an der Lampe, nach vorn und zum Rand hin weich ausblendend. UV.y: 0 an der Lampe, 1 am Ende.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.95, 0.82, 1.0);
uniform float vis = 0.0;

void fragment() {
	float along = clamp(UV.y, 0.0, 1.0);
	float rim = pow(abs(dot(NORMAL, VIEW)), 1.6);
	float a = pow(1.0 - along, 2.2) * smoothstep(0.0, 0.04, along) * rim;
	ALBEDO = tint.rgb * a * vis * 0.35;
}
