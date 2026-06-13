extends RefCounted
## Builds a static GPUParticles3D that blankets an area with grass-blade quads.
## Blades don't move via the particle system (zero velocity) — all motion is the
## sway shader. Registers the material with WeatherSystem so wind drives it.

static func build(area: float = 80.0, count: int = 24000, blade_h: float = 0.9) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = 1000.0
	p.preprocess = 1.0
	p.explosiveness = 1.0          # emit all at once; they then sit still
	p.fixed_fps = 0
	p.interpolate = false
	# Big visibility AABB so the field isn't culled when the emitter origin is off-screen.
	p.visibility_aabb = AABB(Vector3(-area * 0.5, 0, -area * 0.5), Vector3(area, blade_h + 3.0, area))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(area * 0.5, 0.01, area * 0.5)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.angular_velocity_min = 0.0
	pm.angular_velocity_max = 0.0
	pm.scale_min = 0.8
	pm.scale_max = 1.4
	p.process_material = pm

	var qm := QuadMesh.new()
	qm.size = Vector2(0.6, blade_h)
	qm.center_offset = Vector3(0, blade_h * 0.5, 0)  # stand up from the ground (y=0 base)
	var smat := ShaderMaterial.new()
	smat.shader = load("res://shaders/grass_blade.gdshader")
	smat.set_shader_parameter("tex", load("res://assets/textures/grass_blade.png"))
	smat.set_shader_parameter("blade_height", blade_h)
	qm.material = smat
	p.draw_pass_1 = qm

	# Reach the WeatherSystem autoload via the tree (not the global identifier) so
	# this static helper compiles even when autoloads aren't registered as globals.
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var ws = (ml as SceneTree).root.get_node_or_null("WeatherSystem")
		if ws != null:
			ws.register(smat)
	return p

