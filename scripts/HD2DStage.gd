extends RefCounted
## Shared HD-2D rig pieces, parameterized by scene profile. Construction only —
## no follow/update logic (that stays in the scene).

static func key_light(profile: String = "field") -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	match profile:
		"battle":
			sun.light_color = Color(1.0, 0.93, 0.8)
			sun.light_energy = 1.0
			sun.rotation_degrees = Vector3(-50, -120, 0)
		_:
			sun.light_color = Color(1.0, 0.94, 0.82)
			sun.light_energy = 1.15
			sun.shadow_enabled = true
			sun.shadow_bias = 0.04
			sun.rotation_degrees = Vector3(-52, -130, 0)
	return sun

static func make_camera(profile: String = "field") -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 42.0 if profile == "battle" else 30.0
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
			attr.dof_blur_far_distance = 26.0
			attr.dof_blur_far_transition = 5.0
			attr.dof_blur_near_enabled = true
			attr.dof_blur_near_distance = 16.5
			attr.dof_blur_near_transition = 5.0
			attr.dof_blur_amount = 0.34
	cam.attributes = attr

static func backdrop(tex_path: String, size: Vector2, pos: Vector3) -> MeshInstance3D:
	var bg := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	bg.mesh = qm
	var bmat := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		bmat.albedo_texture = load(tex_path)
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
