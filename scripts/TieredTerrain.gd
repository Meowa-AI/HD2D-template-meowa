extends RefCounted
## Large explorable multi-biome terrain (CB-style). A rolling walkable landscape
## with distinct biome regions — grassland, flower meadow, forest, rocky highland
## plateau, and a lakeside basin — connected by gentle slopes, ringed by tall
## border cliffs. The surface is a continuous heightfield (corners sampled from
## height_at and shared between cells) so slopes are smooth, not stepped; tops are
## textured per biome and steep cells get the cliff texture. The player walks the
## surface (height-snapped).

const CELL := 4.0
const TILE_UV := 1.0 / 6.0

# Region anchors.
const PLATEAU := Vector2(42.0, -40.0)   # rocky highland centre
const LAKE := Vector2(-46.0, 10.0)      # lake centre
const LAKE_Y := -2.0
const WATER_LEVEL := -0.45              # player can't walk below this (into water)
const PLATEAU_Y := 6.5

# Biome ids → ground textures.
const TEX := [
	"res://assets/textures/grass.png",          # 0 grassland
	"res://assets/textures/flower_meadow.png",   # 1 flower meadow
	"res://assets/textures/forest_floor.png",    # 2 forest
	"res://assets/textures/rock_ground.png",     # 3 highland
	"res://assets/textures/sand.png",            # 4 lakeside
]

# ---- world shape -----------------------------------------------------------

static func height_at(x: float, z: float) -> float:
	var edge: float = maxf(absf(x), absf(z))
	if edge > 66.0:
		return 16.0                                   # tall border cliffs
	# gentle rolling base
	var h := 1.5 * sin(x * 0.045) * cos(z * 0.05) + 1.0 * sin(x * 0.08 + 1.3) * sin(z * 0.06 + 0.7) + 1.6
	# rocky highland plateau (radial ramp)
	var pd: float = Vector2(x, z).distance_to(PLATEAU)
	var up: float = clampf((26.0 - pd) / 14.0, 0.0, 1.0)
	h = lerpf(h, PLATEAU_Y, up)
	# lake basin (radial dip)
	var ld: float = Vector2(x, z).distance_to(LAKE)
	if ld < 17.0:
		h = lerpf(h, LAKE_Y, clampf((17.0 - ld) / 7.0, 0.0, 1.0))
	return h

static func biome_at(x: float, z: float) -> int:
	if Vector2(x, z).distance_to(PLATEAU) < 19.0:
		return 3                                      # rocky highland
	if Vector2(x, z).distance_to(LAKE) < 21.0:
		return 4                                      # lakeside sand
	if z < -24.0 and x < 16.0:
		return 2                                      # forest
	if x > 18.0 and z > 16.0:
		return 1                                      # flower meadow
	return 0                                          # grassland

# ---- mesh build ------------------------------------------------------------

const CLIFF_SPAN := 3.0   # a cell whose corner heights span more than this is textured as cliff

static func build(half: float = 72.0) -> Node3D:
	var root := Node3D.new()
	var tops: Array[SurfaceTool] = []
	for i in TEX.size():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tops.append(st)
	var cliff := SurfaceTool.new(); cliff.begin(Mesh.PRIMITIVE_TRIANGLES)   # steep faces (border, sharp drops)

	var n := int(half * 2.0 / CELL)
	for gx in n:
		for gz in n:
			var x0 := -half + gx * CELL
			var z0 := -half + gz * CELL
			var x1 := x0 + CELL
			var z1 := z0 + CELL
			# Shared-corner heightfield: adjacent cells read the same height_at at a
			# shared corner, so the surface is continuous (no steps).
			var h00 := height_at(x0, z0); var h10 := height_at(x1, z0)
			var h11 := height_at(x1, z1); var h01 := height_at(x0, z1)
			var span: float = maxf(maxf(h00, h10), maxf(h11, h01)) - minf(minf(h00, h10), minf(h11, h01))
			var st: SurfaceTool = cliff if span > CLIFF_SPAN else tops[biome_at(x0 + CELL * 0.5, z0 + CELL * 0.5)]
			_add_quad(st, x0, z0, x1, z1, h00, h10, h11, h01)

	var mesh := ArrayMesh.new()
	var mats: Array[Material] = []
	for i in TEX.size():
		var m := tops[i].commit()
		if m.get_surface_count() > 0:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(0))
			mats.append(_mat(TEX[i], Color(1, 1, 1), 1.0))
	var cm := cliff.commit()
	if cm.get_surface_count() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cm.surface_get_arrays(0))
		mats.append(_mat("res://assets/textures/cliff.png", Color(1.0, 0.98, 0.94), 0.5))
	for i in mats.size():
		mesh.surface_set_material(i, mats[i])

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	return root

static func water() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(34.0, 34.0)
	pm.subdivide_width = 24
	pm.subdivide_depth = 24
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	pm.material = mat
	mi.position = Vector3(LAKE.x, WATER_LEVEL, LAKE.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var ws = (ml as SceneTree).root.get_node_or_null("WeatherSystem")
		if ws != null:
			ws.register(mat)
	return mi

# ---- helpers ---------------------------------------------------------------

# One terrain cell as two triangles, using the four corner heights. Normals are
# sampled analytically from the height gradient so shading is smooth and matches
# across biome/cliff surface seams.
static func _add_quad(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, h00: float, h10: float, h11: float, h01: float) -> void:
	var p00 := Vector3(x0, h00, z0); var p10 := Vector3(x1, h10, z0)
	var p11 := Vector3(x1, h11, z1); var p01 := Vector3(x0, h01, z1)
	var n00 := _normal_at(x0, z0); var n10 := _normal_at(x1, z0)
	var n11 := _normal_at(x1, z1); var n01 := _normal_at(x0, z1)
	var u00 := Vector2(x0, z0) * TILE_UV; var u10 := Vector2(x1, z0) * TILE_UV
	var u11 := Vector2(x1, z1) * TILE_UV; var u01 := Vector2(x0, z1) * TILE_UV
	_vtx(st, p00, n00, u00); _vtx(st, p10, n10, u10); _vtx(st, p11, n11, u11)
	_vtx(st, p00, n00, u00); _vtx(st, p11, n11, u11); _vtx(st, p01, n01, u01)

# Surface normal from the height_at gradient (central differences).
static func _normal_at(x: float, z: float) -> Vector3:
	const E := 0.5
	var dhx := height_at(x + E, z) - height_at(x - E, z)
	var dhz := height_at(x, z + E) - height_at(x, z - E)
	return Vector3(-dhx, 2.0 * E, -dhz).normalized()

static func _vtx(st: SurfaceTool, p: Vector3, nrm: Vector3, uv: Vector2) -> void:
	st.set_normal(nrm); st.set_uv(uv); st.add_vertex(p)

static func _mat(tex_path: String, tint: Color, uv: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		m.albedo_texture = load(tex_path)
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_scale = Vector3(uv, uv, 1.0)
	m.roughness = 1.0
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
