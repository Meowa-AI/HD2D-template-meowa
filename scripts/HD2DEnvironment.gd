extends RefCounted
## Factory for the shared HD-2D Environment, parameterized by scene profile.
## Returns the Environment resource ONLY — the caller wraps it in a
## WorldEnvironment and adds it to the tree.

## Returns a configured Environment for the given profile ("field" or "battle").
## Unknown profiles fall back to "field".
static func environment(profile: String = "field") -> Environment:
	var env := Environment.new()
	match profile:
		"battle":
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.04, 0.05, 0.08)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.7, 0.72, 0.8)
			env.ambient_light_energy = 1.1
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			env.glow_enabled = true
			env.glow_intensity = 0.5
			env.glow_bloom = 0.15
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
			env.adjustment_enabled = true
			env.adjustment_saturation = 1.12
			env.adjustment_contrast = 1.05
			env.fog_enabled = false  # explicit: battle has no volumetric fog
		_:
			env.background_mode = Environment.BG_SKY
			var sky := Sky.new()
			var psm := ProceduralSkyMaterial.new()
			psm.sky_top_color = Color(0.40, 0.6, 0.85)
			psm.sky_horizon_color = Color(0.86, 0.84, 0.74)
			psm.ground_horizon_color = Color(0.62, 0.72, 0.56)
			psm.ground_bottom_color = Color(0.5, 0.62, 0.42)
			psm.sun_angle_max = 30.0
			sky.sky_material = psm
			env.sky = sky
			env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			env.ambient_light_energy = 0.9
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			env.tonemap_exposure = 1.05
			env.glow_enabled = true
			env.glow_intensity = 0.45
			env.glow_bloom = 0.18
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
			env.glow_hdr_threshold = 0.95
			env.fog_enabled = true
			env.fog_light_color = Color(0.84, 0.86, 0.82)
			env.fog_density = 0.005
			env.fog_sky_affect = 0.0
			env.fog_aerial_perspective = 0.3
			env.adjustment_enabled = true
			env.adjustment_brightness = 1.02
			env.adjustment_contrast = 1.08
			env.adjustment_saturation = 1.18
	return env
