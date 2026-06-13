extends RefCounted
## CB-style tiered terrain: a flat central meadow ringed by rising grass terraces
## with dirt cliff walls. Built as two surfaces (grass tops, dirt cliff walls) on
## one MeshInstance3D, plus a trimesh StaticBody3D so the player is contained in
## the meadow and the cliffs read as solid geometry catching the light.

const CELL := 4.0       # tile size
const FLAT := 12.0      # chebyshev radius of the flat playable meadow
const STEP := 5.0       # horizontal width of each terrace
const RISE := 3.4       # vertical height per terrace
const MAX_TIER := 3
const TILE_UV := 1.0 / 6.0   # texture repeats per world unit (matches ground feel)

# A sunken pond carved into the meadow.
const POND := Vector2(-9.0, -8.0)
const POND_R := 5.5
const POND_Y := -1.4

# Stepped terraces that rise to the NORTH (-z, ahead of the camera) and the
# sides (|x|), but leave the SOUTH (+z, behind the camera) open and flat so the
# camera looks into the terraced landscape over open ground.
static func height_at(x: float, z: float) -> float:
	if Vector2(x, z).distance_to(POND) < POND_R:
		return POND_Y                   # sunken flat pond bottom
	var north: float = -z - FLAT        # distance past the flat edge to the north
	var side: float = absf(x) - FLAT    # distance past the flat edge to a side
	var d: float = maxf(north, side)
	if d <= 0.0:
		return 0.0
	var tier: int = int(ceil(d / STEP))
	tier = mini(tier, MAX_TIER)
	return float(tier) * RISE

static func build(half: float, grass_tex: String, cliff_tex: String) -> Node3D:
	var root := Node3D.new()

	var tops := SurfaceTool.new()
	tops.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)

	var n := int(half * 2.0 / CELL)
	for gx in n:
		for gz in n:
			var x0 := -half + gx * CELL
			var z0 := -half + gz * CELL
			var x1 := x0 + CELL
			var z1 := z0 + CELL
			var cx := x0 + CELL * 0.5
			var cz := z0 + CELL * 0.5
			var h := height_at(cx, cz)
			_add_top(tops, x0, z0, x1, z1, h)
			_maybe_wall(walls, x1, z0, x1, z1, h, height_at(cx + CELL, cz))  # +x face
			_maybe_wall(walls, x0, z1, x0, z0, h, height_at(cx - CELL, cz))  # -x face
			_maybe_wall(walls, x1, z1, x0, z1, h, height_at(cx, cz + CELL))  # +z face
			_maybe_wall(walls, x0, z0, x1, z0, h, height_at(cx, cz - CELL))  # -z face

	var top_mesh := tops.commit()
	var wall_mesh := walls.commit()

	# Merge both into one ArrayMesh (surface 0 = grass tops, surface 1 = walls).
	var mesh := ArrayMesh.new()
	if top_mesh.get_surface_count() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, top_mesh.surface_get_arrays(0))
	if wall_mesh.get_surface_count() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wall_mesh.surface_get_arrays(0))

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = null
	mesh.surface_set_material(0, _grass_material(grass_tex))
	if mesh.get_surface_count() > 1:
		mesh.surface_set_material(1, _cliff_material(cliff_tex))
	root.add_child(mi)

	# Trimesh collision (walls + tops) keeps the player in the meadow.
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	root.add_child(body)

	return root

# Stylized water surface filling the sunken pond.
static func water() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(POND_R * 2.05, POND_R * 2.05)
	pm.subdivide_width = 14
	pm.subdivide_depth = 14
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	pm.material = mat
	mi.position = Vector3(POND.x, -0.25, POND.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var ws = (ml as SceneTree).root.get_node_or_null("WeatherSystem")
		if ws != null:
			ws.register(mat)
	return mi

static func _add_top(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, y: float) -> void:
	var p00 := Vector3(x0, y, z0)
	var p10 := Vector3(x1, y, z0)
	var p11 := Vector3(x1, y, z1)
	var p01 := Vector3(x0, y, z1)
	var up := Vector3.UP
	_tri(st, p00, p10, p11, up, Vector2(x0, z0) * TILE_UV, Vector2(x1, z0) * TILE_UV, Vector2(x1, z1) * TILE_UV)
	_tri(st, p00, p11, p01, up, Vector2(x0, z0) * TILE_UV, Vector2(x1, z1) * TILE_UV, Vector2(x0, z1) * TILE_UV)

# A vertical cliff face from this cell's edge (a..b at height h) down to nh.
static func _maybe_wall(st: SurfaceTool, ax: float, az: float, bx: float, bz: float, h: float, nh: float) -> void:
	if nh >= h:
		return
	var top_a := Vector3(ax, h, az)
	var top_b := Vector3(bx, h, bz)
	var bot_a := Vector3(ax, nh, az)
	var bot_b := Vector3(bx, nh, bz)
	# outward normal = horizontal perpendicular of the edge
	var edge := (top_b - top_a).normalized()
	var nrm := Vector3(edge.z, 0.0, -edge.x)
	var vspan := h - nh
	_tri(st, top_a, top_b, bot_b, nrm, Vector2(0, 0), Vector2(CELL * TILE_UV, 0), Vector2(CELL * TILE_UV, vspan * TILE_UV))
	_tri(st, top_a, bot_b, bot_a, nrm, Vector2(0, 0), Vector2(CELL * TILE_UV, vspan * TILE_UV), Vector2(0, vspan * TILE_UV))

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	st.set_normal(nrm); st.set_uv(ua); st.add_vertex(a)
	st.set_normal(nrm); st.set_uv(ub); st.add_vertex(b)
	st.set_normal(nrm); st.set_uv(uc); st.add_vertex(c)

static func _grass_material(tex_path: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		var t = load(tex_path)
		t.set_meta("repeat", true)
		m.albedo_texture = t
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_scale = Vector3.ONE
	m.roughness = 0.95
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

static func _cliff_material(tex_path: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		m.albedo_texture = load(tex_path)
	m.albedo_color = Color(1.0, 0.98, 0.94)  # rock texture (already brightened)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_scale = Vector3(0.5, 0.5, 1.0)
	m.roughness = 1.0
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
