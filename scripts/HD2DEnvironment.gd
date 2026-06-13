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
			env.ambient_light_color = Color(0.349, 0.325, 0.420)
			env.ambient_light_energy = 0.7
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			env.glow_enabled = true
			env.glow_intensity = 1.0
			env.glow_bloom = 0.18
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
			env.glow_hdr_threshold = 1.0
			env.ssao_enabled = true
			env.ssao_radius = 2.0
			env.ssao_intensity = 2.0
			env.ssao_power = 1.5
			env.adjustment_enabled = true
			env.adjustment_saturation = 1.16
			env.adjustment_contrast = 1.16
			env.fog_enabled = false  # explicit: battle has no volumetric fog
		_:
			env.background_mode = Environment.BG_SKY
			var sky := Sky.new()
			var psm := ProceduralSkyMaterial.new()
			psm.sky_top_color = Color(0.34, 0.46, 0.66)
			psm.sky_horizon_color = Color(0.64, 0.70, 0.78)  # cool steel, not warm
			psm.ground_horizon_color = Color(0.52, 0.58, 0.62)
			psm.ground_bottom_color = Color(0.42, 0.48, 0.50)
			psm.sun_angle_max = 30.0
			sky.sky_material = psm
			env.sky = sky
			# CB signature: lilac ambient fills shadows (GD4 has no shadow_color,
			# so shadowed regions read indigo from this ambient).
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.349, 0.325, 0.420)
			env.ambient_light_energy = 0.6  # lilac fill; sun front-lights the readable side
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			env.tonemap_exposure = 0.97
			env.glow_enabled = true
			env.glow_intensity = 1.0
			env.glow_bloom = 0.2
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
			env.glow_hdr_threshold = 1.0
			env.ssao_enabled = true
			env.ssao_radius = 2.0
			env.ssao_intensity = 2.0
			env.ssao_power = 1.5
			env.fog_enabled = true
			env.fog_light_color = Color(0.502, 0.600, 0.702)  # CB cool steel-blue
			env.fog_density = 0.009
			env.fog_sky_affect = 0.0
			env.fog_aerial_perspective = 0.35
			env.adjustment_enabled = true
			env.adjustment_brightness = 1.0
			env.adjustment_contrast = 1.16
			env.adjustment_saturation = 1.16
	return env
