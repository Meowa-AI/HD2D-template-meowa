extends Node3D
## HD-2D field: a real 3D world (ground, trees, props, lighting, depth-of-field
## camera) populated with billboarded pixel sprites. Walk around, talk to NPCs,
## and step into the tall grass/brush to trigger a random battle.

const HD2DEnvironment := preload("res://scripts/HD2DEnvironment.gd")
const HD2DStage := preload("res://scripts/HD2DStage.gd")
const GrassField := preload("res://scripts/GrassField.gd")

const GROUND_SIZE := 80.0
const ENCOUNTER_STEP_THRESHOLD := 5.0   # distance walked in grass before a roll
const ENCOUNTER_CHANCE := 0.22

var _player: CharacterBody3D
var _cam: Camera3D
var _cam_offset := Vector3(0.0, 10.5, 18.0)
var _cam_look := Vector3(0.0, 1.6, 0.0)

var _interactables: Array = []
var _grass_zones: Array = []
var _in_grass := false
var _step_accum := 0.0
var _encounter_grace := 1.5

# Dialogue UI state
var _dlg_panel: PanelContainer
var _dlg_name: Label
var _dlg_text: Label
var _dlg_lines: Array = []
var _dlg_index := 0
var _dlg_open := false
var _prompt: Label

func _ready() -> void:
	randomize()
	_build_environment()
	_build_light()
	_build_ground()
	add_child(GrassField.build(GROUND_SIZE))
	_build_bounds()
	_spawn_props()
	_spawn_grass_zones()
	_spawn_npcs()
	_spawn_player()
	_build_camera()
	add_child(HD2DStage.dust(GROUND_SIZE))
	add_child(HD2DStage.accent_light(Color(1.0, 0.82, 0.45), 5.0, Vector3(-6.5, 2.6, 9.0)))
	_build_ui()
	Audio.play_bgm("res://assets/audio/field_bgm.mp3")

# ---------------------------------------------------------------- environment
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	we.environment = HD2DEnvironment.environment("field")
	add_child(we)

func _build_light() -> void:
	add_child(HD2DStage.key_light("field"))

# --------------------------------------------------------------------- ground
func _build_ground() -> void:
	var grass := HD2D.ground("res://assets/textures/grass.png", GROUND_SIZE, GROUND_SIZE / 3.0)
	add_child(grass)

	# A winding dirt path: a few overlapping strips of path texture.
	var path_points := [Vector3(-26, 0, 18), Vector3(-8, 0, 6), Vector3(4, 0, -4), Vector3(18, 0, -18)]
	for i in range(path_points.size() - 1):
		_path_strip(path_points[i], path_points[i + 1])

func _path_strip(a: Vector3, b: Vector3) -> void:
	var mid := (a + b) * 0.5
	var dir := b - a
	var length := dir.length()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(3.0, length + 3.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	var t = load("res://assets/textures/path.png")
	mat.albedo_texture = t
	mat.uv1_scale = Vector3(1.0, (length + 3.0) / 3.0, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.position = mid + Vector3(0, 0.02, 0)
	mi.rotation.y = atan2(dir.x, dir.z)
	add_child(mi)

func _build_bounds() -> void:
	var h := GROUND_SIZE * 0.5
	for d in [Vector3(0, 0, -h), Vector3(0, 0, h), Vector3(-h, 0, 0), Vector3(h, 0, 0)]:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var horizontal: bool = absf(d.z) > absf(d.x)
		box.size = Vector3(GROUND_SIZE if horizontal else 1.0, 6.0, 1.0 if horizontal else GROUND_SIZE)
		col.shape = box
		body.add_child(col)
		body.position = d + Vector3(0, 3, 0)
		add_child(body)

# ---------------------------------------------------------------------- props
func _spawn_props() -> void:
	# Perimeter forest — ring of trees with a bit of jitter.
	var trees := ["tree_oak", "tree_pine", "tree_birch", "tree_willow", "tree_maple", "tree_blossom", "tree_dead"]
	var ring := GROUND_SIZE * 0.5 - 2.0
	var count := 80
	for i in count:
		var ang := TAU * float(i) / float(count)
		# Two staggered rows of trees so the treeline fully hides the horizon.
		for row in 2:
			var r := ring - row * 3.5 - randf() * 4.0
			var pos := Vector3(cos(ang) * r, 0, sin(ang) * r)
			var name: String = trees[randi() % trees.size()]
			_add_billboard_prop("res://assets/sprites/props/%s.png" % name, pos, 4.2 + randf() * 1.6, true, 0.5 + randf() * 0.4)

	# Scattered inner trees & bushes for depth — kept in the far half so they
	# never block the camera, which sits behind the player (high +Z).
	for i in 16:
		var pos := Vector3(randf_range(-24, 24), 0, randf_range(-24, 6))
		if pos.length() < 6.0:
			continue
		var pick: String = ["tree_oak", "tree_pine", "bush", "bush", "tree_blossom", "tree_maple"][randi() % 6]
		var h := 1.4 if pick == "bush" else 3.4
		_add_billboard_prop("res://assets/sprites/props/%s.png" % pick, pos, h + randf() * 0.6, pick != "bush", 0.8 + randf() * 0.4)

	# A little camp near the path crossing.
	_add_billboard_prop("res://assets/sprites/props/well.png", Vector3(-9, 0, 7), 2.0, true)
	_add_billboard_prop("res://assets/sprites/props/barrel.png", Vector3(-11.5, 0, 8.5), 1.2, true)
	_add_billboard_prop("res://assets/sprites/props/crate.png", Vector3(-12.5, 0, 7.2), 1.2, true)
	_add_billboard_prop("res://assets/sprites/props/lamp.png", Vector3(-6.5, 0, 9.0), 2.4, true)
	_add_billboard_prop("res://assets/sprites/props/fence.png", Vector3(-9, 0, 11.5), 1.3, false)
	_add_billboard_prop("res://assets/sprites/props/fence.png", Vector3(-6, 0, 11.5), 1.3, false)

	# Examinable signpost and treasure chest.
	var sign_node := _add_billboard_prop("res://assets/sprites/props/signpost.png", Vector3(-3, 0, 4), 1.8, true)
	_interactables.append({
		"pos": sign_node.global_position, "prompt": "Read",
		"name": "Signpost",
		"lines": ["  ← Riverford Village    Cobweb Forest →", "Beware: monsters lurk in the tall brush."],
	})
	var chest_node := _add_billboard_prop("res://assets/sprites/props/chest.png", Vector3(16, 0, 14), 1.3, true)
	_interactables.append({
		"pos": chest_node.global_position, "prompt": "Open",
		"name": "Treasure Chest",
		"lines": ["You found 150 leaves and a Healing Grape!", "(Your party feels encouraged.)"],
	})

func _add_billboard_prop(tex_path: String, pos: Vector3, height: float, shadow: bool, sway: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	var spr: Node3D
	if sway > 0.0:
		spr = HD2DStage.windblown_prop(tex_path, height, sway)
	else:
		spr = HD2D.character(tex_path, height, true)
	root.add_child(spr)
	if shadow:
		root.add_child(HD2D.blob_shadow(height * 0.16, 0.4))
	add_child(root)
	return root

# ---------------------------------------------------------------- grass zones
func _spawn_grass_zones() -> void:
	_make_grass_zone(Vector3(10, 0, 2), Vector2(14, 12))
	_make_grass_zone(Vector3(-16, 0, -10), Vector2(12, 12))

func _make_grass_zone(center: Vector3, size: Vector2) -> void:
	# Visual: darker green patch + scattered brush billboards.
	var mesh := PlaneMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	var t = load("res://assets/textures/grass.png")
	mat.albedo_texture = t
	mat.uv1_scale = Vector3(size.x / 2.0, size.y / 2.0, 1.0)
	mat.albedo_color = Color(0.55, 0.78, 0.45)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mi.material_override = mat
	mi.position = center + Vector3(0, 0.03, 0)
	add_child(mi)

	var n := int(size.x * size.y / 8.0)
	for i in n:
		var p := center + Vector3(randf_range(-size.x * 0.5, size.x * 0.5), 0, randf_range(-size.y * 0.5, size.y * 0.5))
		var spr := HD2DStage.windblown_prop("res://assets/sprites/props/bush.png", randf_range(0.7, 1.1), 1.3)
		var holder := Node3D.new()
		holder.position = p
		holder.add_child(spr)
		add_child(holder)

	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 4.0, size.y)
	col.shape = box
	area.add_child(col)
	area.position = center + Vector3(0, 2, 0)
	area.body_entered.connect(_on_grass_entered)
	area.body_exited.connect(_on_grass_exited)
	add_child(area)
	_grass_zones.append(area)

func _on_grass_entered(body: Node) -> void:
	if body == _player:
		_in_grass = true

func _on_grass_exited(body: Node) -> void:
	if body == _player:
		_in_grass = false
		_step_accum = 0.0

# ----------------------------------------------------------------------- NPCs
func _spawn_npcs() -> void:
	var elder := _add_billboard_prop("res://assets/sprites/npc_elder.png", Vector3(-7.5, 0, 5.5), 2.3, true)
	_interactables.append({
		"pos": elder.global_position, "prompt": "Talk",
		"name": "Elder Bramwell",
		"lines": [
			"Ah, a traveler. Welcome to Riverford.",
			"The forest path east is thick with beasts of late.",
			"Should you brave the tall brush, ready your blades — the wild things favor an ambush.",
			"Remember: strike a foe's weakness to shatter its guard. A broken enemy is a helpless one.",
		],
	})
	var merchant := _add_billboard_prop("res://assets/sprites/npc_merchant.png", Vector3(-10.5, 0, 5.0), 2.2, true)
	_interactables.append({
		"pos": merchant.global_position, "prompt": "Talk",
		"name": "Merchant Hana",
		"lines": [
			"Fresh provisions! Best prices this side of the river!",
			"Save your Boost Points for the moment a foe breaks — then unleash everything at once.",
		],
	})

# --------------------------------------------------------------------- player
func _spawn_player() -> void:
	_player = CharacterBody3D.new()
	_player.set_script(load("res://scripts/Player.gd"))
	_player.sprite_path = "res://assets/sprites/hero.png"
	var start := Vector3(2, 0, 16)
	if SceneManager.has_meta("field_return_pos"):
		start = SceneManager.get_meta("field_return_pos")
		SceneManager.remove_meta("field_return_pos")
	_player.position = start
	add_child(_player)

func _build_camera() -> void:
	_cam = HD2DStage.make_camera("field")
	add_child(_cam)
	_cam.global_position = _player.position + _cam_offset
	_cam.look_at(_player.position + _cam_look, Vector3.UP)
	_cam.make_current()

# ------------------------------------------------------------------------- UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_color", Color(1, 1, 1))
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-60, -180)
	_prompt.visible = false
	layer.add_child(_prompt)

	_dlg_panel = PanelContainer.new()
	_dlg_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_dlg_panel.offset_left = 60
	_dlg_panel.offset_right = -60
	_dlg_panel.offset_top = -190
	_dlg_panel.offset_bottom = -40
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.12, 0.92)
	sb.border_color = Color(0.85, 0.78, 0.5)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(18)
	_dlg_panel.add_theme_stylebox_override("panel", sb)
	_dlg_panel.visible = false
	layer.add_child(_dlg_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_dlg_panel.add_child(vb)
	_dlg_name = Label.new()
	_dlg_name.add_theme_font_size_override("font_size", 22)
	_dlg_name.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	vb.add_child(_dlg_name)
	_dlg_text = Label.new()
	_dlg_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dlg_text.add_theme_font_size_override("font_size", 20)
	_dlg_text.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0))
	vb.add_child(_dlg_text)
	var hint := Label.new()
	hint.text = "▸ E / Enter to continue"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	vb.add_child(hint)

# --------------------------------------------------------------------- update
func _process(delta: float) -> void:
	if _player == null:
		return
	WeatherSystem.set_body(0, _player.global_position)
	# Camera follow.
	var target := _player.global_position + _cam_offset
	_cam.global_position = _cam.global_position.lerp(target, clampf(delta * 6.0, 0, 1))
	_cam.look_at(_player.global_position + _cam_look, Vector3.UP)

	if _encounter_grace > 0.0:
		_encounter_grace -= delta

	if _dlg_open:
		return

	# Nearest interactable.
	var nearest = _nearest_interactable()
	if nearest != null:
		_prompt.text = "[ E ]  %s" % nearest["prompt"]
		_prompt.visible = true
	else:
		_prompt.visible = false

	# Encounter accumulation.
	if _in_grass and _player.is_moving and _encounter_grace <= 0.0:
		_step_accum += _player.moved_this_frame
		if _step_accum >= ENCOUNTER_STEP_THRESHOLD:
			_step_accum = 0.0
			if randf() < ENCOUNTER_CHANCE:
				_trigger_encounter()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") or event.is_action_pressed("confirm"):
		if _dlg_open:
			_advance_dialogue()
		else:
			var n = _nearest_interactable()
			if n != null:
				_open_dialogue(n["name"], n["lines"])

func _nearest_interactable():
	var best = null
	var best_d := 3.0
	for it in _interactables:
		var d: float = _player.global_position.distance_to(it["pos"])
		if d < best_d:
			best_d = d
			best = it
	return best

func _open_dialogue(name: String, lines: Array) -> void:
	_dlg_open = true
	_dlg_lines = lines
	_dlg_index = 0
	_dlg_name.text = name
	_dlg_text.text = lines[0]
	_dlg_panel.visible = true
	_prompt.visible = false
	Audio.play_sfx("confirm")
	if _player.has_method("set_physics_process"):
		_player.set_physics_process(false)

func _advance_dialogue() -> void:
	_dlg_index += 1
	if _dlg_index >= _dlg_lines.size():
		_close_dialogue()
	else:
		_dlg_text.text = _dlg_lines[_dlg_index]
		Audio.play_sfx("cursor")

func _close_dialogue() -> void:
	_dlg_open = false
	_dlg_panel.visible = false
	_player.set_physics_process(true)

func _trigger_encounter() -> void:
	SceneManager.set_meta("field_return_pos", _player.global_position)
	SceneManager.return_scene = "res://scenes/Field.tscn"
	SceneManager.encounter_transition("res://scenes/Battle.tscn")
