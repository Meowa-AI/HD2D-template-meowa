class_name HD2D
extends RefCounted
## Helpers for the HD-2D look: pixel-perfect billboarded Sprite3D characters that
## stand in a real 3D world, plus soft grounded "blob" shadows. Used by both the
## field and the battle scenes so the two share one consistent style.

const WebCompatibility := preload("res://scripts/WebCompatibility.gd")

static var _shadow_tex: ImageTexture

# Build a Y-billboard pixel sprite. The node origin sits at the character's feet
# so you can place it directly on the ground plane (y = 0).
static func character(tex_path: String, world_height: float = 2.4, shaded: bool = false) -> Sprite3D:
	var s := Sprite3D.new()
	if ResourceLoader.exists(tex_path):
		s.texture = load(tex_path)
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = shaded
	s.double_sided = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	s.alpha_scissor_threshold = 0.4
	s.centered = true
	var tex_h := 256
	if s.texture != null:
		tex_h = s.texture.get_height()
	s.pixel_size = world_height / float(tex_h)
	# Lift so the feet (bottom of the 256px frame, character standing on it) rest
	# near y=0. Generated frames have a little empty space at the bottom.
	s.position.y = world_height * 0.5 - world_height * 0.04
	return s

# Soft circular shadow projected onto the ground beneath a character.
static func blob_shadow(radius: float = 0.55, strength: float = 0.5) -> Node3D:
	if WebCompatibility.enabled():
		return _flat_shadow(radius, strength)
	var d := Decal.new()
	d.texture_albedo = _get_shadow_texture()
	d.size = Vector3(radius * 2.0, 1.2, radius * 2.0)
	d.modulate = Color(0, 0, 0, strength)
	d.albedo_mix = 1.0
	d.position.y = 0.02
	d.cull_mask = 0xFFFFF
	return d

static func _flat_shadow(radius: float, strength: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = qm
	mi.rotation_degrees.x = -90.0
	mi.position.y = 0.025
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _get_shadow_texture()
	mat.albedo_color = Color(0, 0, 0, strength)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	qm.material = mat
	return mi

static func _get_shadow_texture() -> ImageTexture:
	if _shadow_tex != null:
		return _shadow_tex
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size) * 0.5
	for y in size:
		for x in size:
			var dx := (float(x) - c) / c
			var dy := (float(y) - c) / c
			var dist := sqrt(dx * dx + dy * dy)
			var a: float = clampf(1.0 - dist, 0.0, 1.0)
			a = a * a  # softer falloff
			img.set_pixel(x, y, Color(0, 0, 0, a))
	_shadow_tex = ImageTexture.create_from_image(img)
	return _shadow_tex

# A flat ground patch tiled with a pixel texture (nearest-filtered).
static func ground(tex_path: String, size: float, tile_repeat: float) -> MeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		var t = load(tex_path)
		t.set_meta("repeat", true)
		mat.albedo_texture = t
		mat.uv1_scale = Vector3(tile_repeat, tile_repeat, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.roughness = 0.95
	mat.metallic = 0.0
	mi.material_override = mat
	return mi
