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
	cam.fov = 42.0 if profile == "battle" else 46.0
	apply_dof(cam, profile)
	return cam

static func apply_dof(cam: Camera3D, profile: String = "field") -> void:
	var attr := CameraAttributesPractical.new()
	match profile:
		"battle":
			attr.dof_blur_far_enabled = true
			attr.dof_blur_far_distance = 19.0
			attr.dof_blur_far_transition = 6.0
			attr.dof_blur_amount = 0.06
		_:
			attr.dof_blur_far_enabled = true
			attr.dof_blur_far_distance = 24.0
			attr.dof_blur_far_transition = 8.0
			attr.dof_blur_near_enabled = true
			attr.dof_blur_near_distance = 6.0
			attr.dof_blur_near_transition = 3.0
			attr.dof_blur_amount = 0.08
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
