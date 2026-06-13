shader_type spatial;
// Stylized CB-ish water: cool translucent surface with a gentle vertex ripple
// and animated binary glints, driven by the shared WeatherSystem wind_phase.
render_mode cull_disabled, depth_draw_always, diffuse_burley;

uniform float wind_phase = 0.0;
uniform vec3 shallow_col : source_color = vec3(0.26, 0.55, 0.62);
uniform vec3 deep_col : source_color = vec3(0.07, 0.20, 0.36);

void vertex() {
	float w = sin(wind_phase * 0.7 + VERTEX.x * 1.4) * cos(wind_phase * 0.5 + VERTEX.z * 1.2);
	VERTEX.y += 0.05 * w;
}

void fragment() {
	float g = sin(VERTEX.x * 5.5 + wind_phase * 2.0) * sin(VERTEX.z * 5.5 - wind_phase * 1.6);
	float glint = smoothstep(0.86, 0.97, g);
	ALBEDO = mix(deep_col, shallow_col, 0.55);
	EMISSION = vec3(0.7, 0.85, 0.95) * glint * 0.5;
	ALPHA = 0.80;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
}
