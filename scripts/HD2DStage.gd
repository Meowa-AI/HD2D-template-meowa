extends RefCounted
## Shared HD-2D rig pieces, parameterized by scene profile. Construction only —
## no follow/update logic (that stays in the scene).

static func key_light(profile: String = "field") -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	match profile:
		"battle":
			sun.light_color = Color(1.0, 0.98, 0.95)  # CB near-white noon
			sun.light_energy = 1.0
			sun.rotation_degrees = Vector3(-45, -20, 0)  # front-light combatants (readable)
		_:
			# CB: near-white sun; indigo shadow mood comes from the lilac ambient,
			# not a shadow_color (which does not exist in Godot 4.6).
			sun.light_color = Color(1.0, 0.98, 0.95)
			sun.light_energy = 1.0
			sun.shadow_enabled = true
			sun.shadow_bias = 0.04
			sun.shadow_opacity = 0.85
			sun.shadow_blur = 1.5
			# Angled from behind/above the camera (+Z) so it front-lights the
			# camera-facing billboards (keeps sprites readable); slight side for shadow.
			sun.rotation_degrees = Vector3(-48, -28, 0)
	return sun

static func make_camera(profile: String = "field") -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 42.0 if profile == "battle" else 30.0  # CB world FOV = 30
	apply_dof(cam, profile)
	return cam

static func apply_dof(cam: Camera3D, profile: String = "field") -> void:
	var attr := CameraAttributesPractical.new()
	match profile:
		"battle":
			attr.dof_blur_far_enabled = true
			attr.dof_blur_far_distance = 19.0
			attr.dof_blur_far_transition = 6.0
			attr.dof_blur_amount = 0.12
		_:
			attr.dof_blur_far_enabled = true
			# Exact Cassette Beasts daylight DOF (far 51/20, near 37/5).
			attr.dof_blur_far_distance = 51.0
			attr.dof_blur_far_transition = 20.0
			attr.dof_blur_near_enabled = true
			attr.dof_blur_near_distance = 12.0  # closer camera: keep hero (~26u) in focus
			attr.dof_blur_near_transition = 5.0
			attr.dof_blur_amount = 0.12
	cam.attributes = attr

static func backdrop(tex_path: String, size: Vector2, pos: Vector3, modulate: Color = Color.WHITE) -> MeshInstance3D:
	var bg := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	bg.mesh = qm
	var bmat := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		bmat.albedo_texture = load(tex_path)
	bmat.albedo_color = modulate  # cool tint to harmonize a warm backdrop with the CB grade
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	bg.mesh.material = bmat
	bg.position = pos
	return bg

# Drifting dust motes that catch the light — cheap, high-impact atmosphere.
static func dust(area_size: float = 40.0, amount: int = 220) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.randomness = 1.0
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(area_size * 0.5, 4.0, area_size * 0.5)
	mat.gravity = Vector3(0, -0.05, 0)
	mat.initial_velocity_min = 0.05
	mat.initial_velocity_max = 0.25
	mat.scale_min = 0.01
	mat.scale_max = 0.04
	var draw := QuadMesh.new()
	draw.size = Vector2(0.06, 0.06)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color = Color(1, 0.97, 0.85, 0.5)
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw.material = dmat
	p.draw_pass_1 = draw
	p.process_material = mat
	p.position = Vector3(0, 3, 0)
	return p

# A swaying foliage billboard (tree/bush): a +Z-facing standing quad with the
# windblown shader, registered with WeatherSystem so the crown sways in the wind.
static func windblown_prop(tex_path: String, world_height: float, sway: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var aspect := 1.0
	var tex: Texture2D = null
	if ResourceLoader.exists(tex_path):
		tex = load(tex_path)
		aspect = float(tex.get_width()) / float(tex.get_height())
	var qm := QuadMesh.new()
	qm.size = Vector2(world_height * aspect, world_height)
	qm.center_offset = Vector3(0, world_height * 0.5, 0)  # base at y=0
	mi.mesh = qm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/windblown.gdshader")
	mat.set_shader_parameter("tex", tex)
	mat.set_shader_parameter("prop_height", world_height)
	mat.set_shader_parameter("sway", sway)
	qm.material = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Reach the WeatherSystem autoload via the tree (not the global identifier) so
	# this static helper still compiles in contexts where autoloads aren't globals
	# (e.g. headless tool/test loads).
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var ws = (ml as SceneTree).root.get_node_or_null("WeatherSystem")
		if ws != null:
			ws.register(mat)
	return mi

# A small colored point light for local warmth (torch, lamp, magic).
static func accent_light(color: Color, energy: float, pos: Vector3, rng: float = 9.0) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.light_color = color
	o.light_energy = energy
	o.omni_range = rng
	o.position = pos
	return o

# A pair of out-of-focus near-camera bushes that frame the shot (DOF blurs them).
static func foreground_frame(tex_path: String, cam_pos: Vector3) -> Node3D:
	var root := Node3D.new()
	for sx in [-1.0, 1.0]:
		var s := Sprite3D.new()
		if ResourceLoader.exists(tex_path):
			s.texture = load(tex_path)
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.pixel_size = 0.02
		s.position = cam_pos + Vector3(sx * 4.5, -1.5, -4.0)
		root.add_child(s)
	return root
