shader_type spatial;
// Windblown foliage billboard (tree/bush) as a +Z-facing standing quad (the
// field camera looks a fixed -Z). The crown sways; the base is pinned.
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley, shadows_disabled;

uniform sampler2D tex : source_color, filter_nearest;
uniform float wind_phase = 0.0;
uniform vec3 wind_strength = vec3(0.13, 0.0, 0.07);
uniform float prop_height = 3.0;
uniform float sway = 1.0;

void vertex() {
	float hw = clamp(VERTEX.y / prop_height, 0.0, 1.0);
	hw = hw * hw;  // bias sway to the crown
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = wpos.x * 0.3 + wpos.z * 0.3;  // neighbours out of sync
	VERTEX += wind_strength * sin(wind_phase + ph) * hw * sway;
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ROUGHNESS = 1.0;
}
