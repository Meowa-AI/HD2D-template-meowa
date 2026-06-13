shader_type spatial;
// Grass blade for GPUParticles3D draw mesh. Blades are non-rotated quads facing
// +Z (the field camera always looks -Z), so wind/push offsets in world space can
// be added straight to VERTEX. Height-weighted sway + player push-away.
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley, shadows_disabled;

uniform sampler2D tex : source_color, filter_nearest;
uniform float wind_phase = 0.0;
uniform vec3 wind_strength = vec3(0.13, 0.0, 0.07);
uniform vec3 body_0 = vec3(99999.0);
uniform vec3 body_1 = vec3(99999.0);
uniform float avoid_distance = 1.7;
uniform float blade_height = 0.7;

void vertex() {
	float hw = clamp(VERTEX.y / blade_height, 0.0, 1.0); // 0 at base, 1 at tip
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// per-blade phase from world XZ so blades ripple out of sync
	float ph = wpos.x * 0.6 + wpos.z * 0.55;
	vec3 sway = wind_strength * sin(wind_phase + ph) * hw;
	// player push-away (up to two bodies)
	vec3 push = vec3(0.0);
	for (int i = 0; i < 2; i++) {
		vec3 b = (i == 0) ? body_0 : body_1;
		vec3 d = wpos - b;
		d.y = 0.0;
		float dist = length(d);
		if (dist < avoid_distance) {
			push += normalize(d + vec3(0.001, 0.0, 0.0)) * ((avoid_distance - dist) / avoid_distance) * hw * 0.9;
		}
	}
	VERTEX += sway + push;  // no rotation on the quad → world offset == local offset
	NORMAL = normalize(vec3(0.0, 0.8, 0.9));  // catch ambient/sun fairly uniformly
}

void fragment() {
	vec4 t = texture(tex, UV);
	ALBEDO = t.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ROUGHNESS = 1.0;
}
