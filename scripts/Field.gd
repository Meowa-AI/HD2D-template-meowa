extends Node3D
## HD-2D field: a real 3D world (ground, trees, props, lighting, depth-of-field
## camera) populated with billboarded pixel sprites. Walk around, talk to NPCs,
## and step into the tall grass/brush to trigger a random battle.

const HD2DEnvironment := preload("res://scripts/HD2DEnvironment.gd")
const HD2DStage := preload("res://scripts/HD2DStage.gd")
const GrassField := preload("res://scripts/GrassField.gd")
const TieredTerrain := preload("res://scripts/TieredTerrain.gd")
const CloudShadowsScene := preload("res://scripts/CloudShadows.gd")
const DayNightCycleScene := preload("res://scripts/DayNightCycle.gd")
const AnimatedBillboardScene := preload("res://scripts/AnimatedBillboard.gd")
const MonsterScene := preload("res://scripts/Monster.gd")
const DebugTunerScene := preload("res://scripts/DebugTuner.gd")
const WebCompatibility := preload("res://scripts/WebCompatibility.gd")

const GROUND_SIZE := 144.0
const ENCOUNTER_STEP_THRESHOLD := 5.0   # distance walked in grass before a roll
const ENCOUNTER_CHANCE := 0.22

var _player: CharacterBody3D
var _cam: Camera3D
var _cam_offset := Vector3(0.0, 11.5, 24.0)  # flatter ~20deg pitch, ~26 units back (Octopath/Until Then feel)
var _cam_look := Vector3(0.0, 3.5, 0.0)
var _daynight: Node

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
	add_child(GrassField.build(150.0, WebCompatibility.grass_blade_count(46000), 0.9, TieredTerrain.LAKE, 20.0))  # grass blanket (excludes the lake)
	var clouds := CloudShadowsScene.new()
	clouds.setup(GROUND_SIZE * 0.5)
	add_child(clouds)
	_daynight = DayNightCycleScene.new()
	_daynight.sun = _sun
	_daynight.env = _env
	add_child(_daynight)
	_spawn_props()
	_spawn_npcs()
	_spawn_player()
	_spawn_monsters()
	_build_camera()
	if not WebCompatibility.enabled():
		_build_tuner()
	add_child(HD2DStage.dust(GROUND_SIZE))
	add_child(HD2DStage.accent_light(Color(1.0, 0.82, 0.45), 5.0, Vector3(2.0, 2.6, 22.0)))
	_build_ui()
	Audio.play_bgm("res://assets/audio/field_bgm.mp3")

# ---------------------------------------------------------------- environment
var _env: Environment
var _sun: DirectionalLight3D

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	_env = HD2DEnvironment.environment("field")
	we.environment = _env
	add_child(we)

func _build_light() -> void:
	_sun = HD2DStage.key_light("field")
	add_child(_sun)

# --------------------------------------------------------------------- ground
func _build_ground() -> void:
	# Large multi-biome walkable landscape (grassland / flower / forest / highland
	# / lakeside) with rolling slopes and border cliffs.
	add_child(TieredTerrain.build(GROUND_SIZE * 0.5))
	add_child(TieredTerrain.water())

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

# ---------------------------------------------------------------------- props
func _spawn_props() -> void:
	var H := GROUND_SIZE * 0.5 - 8.0
	var spawn := Vector3(0, 0, 22)   # keep the start clearing open
	for i in WebCompatibility.prop_scatter_count(900):
		var x := randf_range(-H, H)
		var z := randf_range(-H, H)
		if TieredTerrain.height_at(x, z) <= TieredTerrain.WATER_LEVEL + 0.2:
			continue
		if Vector2(x, z).distance_to(Vector2(spawn.x, spawn.z)) < 9.0:
			continue
		_scatter_one(TieredTerrain.biome_at(x, z), x, z)

	# Start-clearing camp (grassland).
	_add_billboard_prop("res://assets/sprites/props/well.png", Vector3(-7, 0, 24), 2.0, true)
	_add_billboard_prop("res://assets/sprites/props/barrel.png", Vector3(-9, 0, 25.5), 1.2, true)
	_add_billboard_prop("res://assets/sprites/props/crate.png", Vector3(-10, 0, 24), 1.2, true)
	_add_billboard_prop("res://assets/sprites/props/lamp.png", Vector3(-4.5, 0, 25), 2.4, true)

	var sign_node := _add_billboard_prop("res://assets/sprites/props/signpost.png", Vector3(4, 0, 18), 1.8, true)
	_interactables.append({
		"pos": sign_node.global_position, "prompt": "Read", "name": "Signpost",
		"lines": ["  ↑ Mistral Forest      Highcrag Plateau →", "  ← Still Lake", "Beasts roam the wilds. Step carefully."],
	})
	# Reward chest hidden atop the highland plateau — walk up to reach it.
	var chest_node := _add_billboard_prop("res://assets/sprites/props/chest.png", Vector3(42, 0, -40), 1.3, true)
	_interactables.append({
		"pos": chest_node.global_position, "prompt": "Open", "name": "Treasure Chest",
		"lines": ["You found 300 leaves and a Star Shard!", "(Your party feels emboldened.)"],
	})

# Place one biome-appropriate prop at (x,z).
func _scatter_one(biome: int, x: float, z: float) -> void:
	var p := Vector3(x, 0, z)
	var r := randf()
	match biome:
		2:  # forest — dense conifers/broadleaf + brush
			if r < 0.8:
				var t: String = ["tree_oak", "tree_pine", "tree_birch", "tree_willow", "tree_maple"][randi() % 5]
				_add_billboard_prop("res://assets/sprites/props/%s.png" % t, p, 3.6 + randf() * 1.8, true, 0.55 + randf() * 0.4)
			elif r < 0.95:
				_add_billboard_prop("res://assets/sprites/props/bush.png", p, 1.1 + randf() * 0.5, false, 1.2)
		3:  # highland — rocks + the odd dead tree (sparse)
			if r < 0.4:
				_add_billboard_prop("res://assets/sprites/props/rock.png", p, 1.0 + randf() * 1.3, true)
			elif r < 0.5:
				_add_billboard_prop("res://assets/sprites/props/tree_dead.png", p, 2.8 + randf(), true, 0.7)
		4:  # lakeside — reed clumps + a few willows
			if r < 0.45:
				_add_billboard_prop("res://assets/sprites/props/bush.png", p, 0.8 + randf() * 0.5, false, 1.5)
			elif r < 0.55:
				_add_billboard_prop("res://assets/sprites/props/tree_willow.png", p, 3.2 + randf(), true, 0.7)
		1:  # flower meadow — blossom trees + bushes (open)
			if r < 0.16:
				_add_billboard_prop("res://assets/sprites/props/tree_blossom.png", p, 3.2 + randf(), true, 0.6)
			elif r < 0.32:
				_add_billboard_prop("res://assets/sprites/props/bush.png", p, 1.0 + randf() * 0.4, false, 1.2)
		_:  # grassland — scattered trees + bushes (open)
			if r < 0.13:
				var t2: String = ["tree_oak", "tree_maple", "tree_blossom"][randi() % 3]
				_add_billboard_prop("res://assets/sprites/props/%s.png" % t2, p, 3.4 + randf() * 1.2, true, 0.6)
			elif r < 0.26:
				_add_billboard_prop("res://assets/sprites/props/bush.png", p, 1.1 + randf() * 0.4, false, 1.2)

func _add_billboard_prop(tex_path: String, pos: Vector3, height: float, shadow: bool, sway: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(pos.x, TieredTerrain.height_at(pos.x, pos.z), pos.z)  # sit on the terrain
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

# An NPC that loops an idle animation spritesheet, sitting on the terrain.
func _add_animated_npc(sheet_path: String, frames: int, pos: Vector3, height: float) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(pos.x, TieredTerrain.height_at(pos.x, pos.z), pos.z)
	var spr := AnimatedBillboardScene.new()
	root.add_child(spr)
	spr.setup(load(sheet_path), frames, height, 4.0)
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
	var elder := _add_animated_npc("res://assets/sprites/npc_elder_idle.png", 4, Vector3(-4, 0, 20), 2.3)
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
	var merchant := _add_animated_npc("res://assets/sprites/npc_merchant_idle.png", 4, Vector3(-1, 0, 24), 2.2)
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
	var start := Vector3(0, 0, 22)
	if SceneManager.has_meta("field_return_pos"):
		start = SceneManager.get_meta("field_return_pos")
		SceneManager.remove_meta("field_return_pos")
	start.y = TieredTerrain.height_at(start.x, start.z)
	_player.position = start
	add_child(_player)

func _spawn_monsters() -> void:
	# Monsters spread across the biomes — walk up to them to start a fight.
	var specs := [
		{"s": "goblin_walk", "p": Vector3(14, 0, 4), "h": 1.9},      # grassland
		{"s": "wolf_walk", "p": Vector3(-8, 0, -32), "h": 2.0},      # forest
		{"s": "wolf_walk", "p": Vector3(2, 0, -40), "h": 2.0},       # forest deep
		{"s": "goblin_walk", "p": Vector3(34, 0, -34), "h": 1.9},    # highland slope
		{"s": "goblin_walk", "p": Vector3(-30, 0, 24), "h": 1.9},    # lakeside
		{"s": "wolf_walk", "p": Vector3(28, 0, 26), "h": 2.0},       # flower meadow
	]
	for cfg in specs:
		var m := MonsterScene.new()
		m.sheet_path = "res://assets/sprites/%s.png" % cfg["s"]
		m.world_h = cfg["h"]
		m.bound = 11.0
		m._player = _player
		var p: Vector3 = cfg["p"]
		m.position = Vector3(p.x, TieredTerrain.height_at(p.x, p.z), p.z)
		add_child(m)

func _build_camera() -> void:
	_cam = HD2DStage.make_camera("field")
	add_child(_cam)
	_cam.global_position = _player.position + _cam_offset
	_cam.look_at(_player.position + _cam_look, Vector3.UP)
	_cam.make_current()

func _build_tuner() -> void:
	var tuner := DebugTunerScene.new()
	add_child(tuner)
	tuner.setup(self, _cam, _env, _daynight)

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
	var sb := StyleBoxTexture.new()  # CB-style navy panel with cream border (nine-slice)
	sb.texture = load("res://assets/ui/panel.png")
	sb.set_texture_margin_all(19)
	sb.set_content_margin_all(22)
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
