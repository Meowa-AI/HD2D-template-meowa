extends Node3D
## HD-2D turn-based battle with Octopath's two signature systems:
##   • BREAK  — every enemy has hidden weaknesses and a shield count. Hit a
##              weakness to chip the shield; at 0 the enemy is Broken: stunned and
##              taking heavy extra damage until it recovers.
##   • BOOST  — each turn a unit banks 1 Boost Point (max 5). Before acting you may
##              spend up to 3 BP to add hits to multi-hit moves, amplify single
##              hits/heals, and shred shields faster.
##
## Combatants are billboarded pixel sprites standing in a 3D world in front of a
## painted backdrop, with a depth-of-field camera — the HD-2D look.

# ----- tuning ---------------------------------------------------------------
const WEAKNESS_MULT := 1.6
const BREAK_MULT := 1.8
const SP_REGEN := 2
const MAX_BP := 5
const MAX_SPEND := 3

# Basic-attack weapon type + a touch of power, per ally id.
const WEAPON := {
	"hero": "sword", "mage": "fire", "cleric": "staff", "hunter": "bow",
}

# ----- combatant ------------------------------------------------------------
class Combatant:
	var id: String
	var name: String
	var is_enemy: bool
	var max_hp: int
	var hp: int
	var max_sp: int
	var sp: int
	var atk: int
	var def: int
	var elm: int
	var spd: int
	var bp: int = 1
	var boosted_last := false
	var skills: Array = []
	var weak: Array = []
	var revealed: Dictionary = {}
	var shield_max: int = 0
	var shield: int = 0
	var broken := false
	var broken_skip := 0
	var defending := false
	var alive := true
	var root: Node3D
	var sprite: Sprite3D
	var home: Vector3

	func is_physical_weak(t: String) -> bool:
		return weak.has(t)

# ----- state ----------------------------------------------------------------
var _allies: Array = []
var _enemies: Array = []
var _all: Array = []
var _cam: Camera3D
var _turn_order: Array = []
var _round := 0
var _busy_action := false

# menu state
var _menu_active := false
var _menu_items: Array = []
var _menu_index := 0
var _menu_enabled: Array = []      # per-item bool (greyed if false)
signal _menu_confirmed(index: int)

# targeting state
var _target_active := false
var _target_list: Array = []
var _target_index := 0
signal _target_confirmed(index: int)

var _cur_boost := 0
var _cur_actor: Combatant

# UI nodes
var _ui: CanvasLayer
var _msg: Label
var _menu_panel: PanelContainer
var _menu_vbox: VBoxContainer
var _boost_label: Label
var _actor_label: Label
var _party_panels: Array = []
var _enemy_info: Array = []        # {combatant, control,...}
var _reticle: Label
var _order_label: Label
var _ended := false

func _ready() -> void:
	randomize()
	_build_world()
	_spawn_combatants()
	_build_camera()
	_build_ui()
	Audio.play_bgm("res://assets/audio/battle_bgm.mp3")
	_battle_loop()

# ----- world / backdrop -----------------------------------------------------
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.0
	sun.rotation_degrees = Vector3(-50, -120, 0)
	add_child(sun)

	# Painted backdrop as a big quad far behind the fighters (gets DoF bokeh).
	var bg := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(46, 26)
	bg.mesh = qm
	var bmat := StandardMaterial3D.new()
	if ResourceLoader.exists("res://assets/textures/battle_bg.jpg"):
		bmat.albedo_texture = load("res://assets/textures/battle_bg.jpg")
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	bg.mesh.material = bmat
	bg.position = Vector3(0, 9, -16)
	add_child(bg)

	# Ground for shadows to land on; tinted to blend with the backdrop floor.
	var ground := HD2D.ground("res://assets/textures/grass.png", 40.0, 10.0)
	var gmat: StandardMaterial3D = ground.material_override
	gmat.albedo_color = Color(0.5, 0.5, 0.45)
	add_child(ground)

# ----- combatants -----------------------------------------------------------
func _spawn_combatants() -> void:
	# Allies (front, facing camera).
	var ally_x := [-5.4, -1.8, 1.8, 5.4]
	for i in GameData.party.size():
		var d: Dictionary = GameData.party[i]
		var c := _make_ally(d)
		c.home = Vector3(ally_x[i], 0, 3.4)
		_place(c, c.home, false)
		_allies.append(c)

	# Enemies (back, facing camera).
	var enc := GameData.ENCOUNTER
	var n := enc.size()
	var span := 8.0
	for i in n:
		var key: String = enc[i]
		var c := _make_enemy(key, i)
		var x := lerpf(-span * 0.5, span * 0.5, 0.0 if n == 1 else float(i) / float(n - 1))
		c.home = Vector3(x, 0, -3.2)
		_place(c, c.home, true)
		_enemies.append(c)

	_all = _allies + _enemies

func _make_ally(d: Dictionary) -> Combatant:
	var c := Combatant.new()
	c.id = d["id"]; c.name = d["name"]; c.is_enemy = false
	c.max_hp = d["max_hp"]; c.hp = c.max_hp
	c.max_sp = d["max_sp"]; c.sp = c.max_sp
	c.atk = d["atk"]; c.def = d["def"]; c.elm = d["elm"]; c.spd = d["spd"]
	c.skills = d["skills"]
	c.bp = 1
	if OS.has_environment("AUTO_LOSE"):
		c.max_hp = 6
		c.hp = 6
	return c

func _make_enemy(key: String, idx: int) -> Combatant:
	var d: Dictionary = GameData.ENEMIES[key]
	var c := Combatant.new()
	c.id = key
	c.name = d["name"] if idx == 0 else "%s %s" % [d["name"], char(65 + idx)]
	c.is_enemy = true
	c.max_hp = d["max_hp"]; c.hp = c.max_hp
	c.max_sp = 0; c.sp = 0
	c.atk = d["atk"]; c.def = d["def"]; c.elm = d["atk"]; c.spd = d["spd"]
	c.weak = d["weak"].duplicate()
	c.shield_max = d["shield"]; c.shield = c.shield_max
	c.bp = 0
	if OS.has_environment("AUTO_LOSE"):
		c.max_hp = 9999; c.hp = 9999; c.atk = 999; c.spd = 999
		c.shield_max = 99; c.shield = 99
	c.set_meta("scale", d.get("scale", 1.0))
	c.set_meta("sprite", d["sprite"])
	return c

func _place(c: Combatant, pos: Vector3, enemy: bool) -> void:
	var root := Node3D.new()
	root.position = pos
	var tex: String = c.get_meta("sprite") if enemy else GameData.party_sprite(c.id)
	var height := 2.6
	if enemy:
		height = 2.6 * float(c.get_meta("scale"))
	var spr := HD2D.character(tex, height, false)
	if enemy:
		spr.flip_h = true   # enemies look toward the party
	root.add_child(spr)
	root.add_child(HD2D.blob_shadow(0.6, 0.45))
	add_child(root)
	c.root = root
	c.sprite = spr

func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 42.0
	add_child(_cam)
	_cam.position = Vector3(0, 6.4, 13.5)
	_cam.look_at(Vector3(0, 2.4, -2), Vector3.UP)
	var attr := CameraAttributesPractical.new()
	attr.dof_blur_far_enabled = true
	attr.dof_blur_far_distance = 19.0
	attr.dof_blur_far_transition = 6.0
	attr.dof_blur_amount = 0.06
	_cam.attributes = attr
	_cam.make_current()

# ===========================================================================
#  MAIN BATTLE LOOP
# ===========================================================================
func _battle_loop() -> void:
	await get_tree().create_timer(0.6).timeout
	_flash_message("Monsters attack!", 1.1)
	await get_tree().create_timer(1.0).timeout

	while not _ended:
		_round += 1
		_build_turn_order()
		for c in _turn_order:
			if _ended:
				break
			if not c.alive:
				continue
			# Broken units lose their turn, then recover.
			if c.broken:
				if c.broken_skip > 0:
					c.broken_skip -= 1
					_flash_message("%s is broken!" % c.name, 0.7)
					await get_tree().create_timer(0.5).timeout
					continue
				else:
					_recover_break(c)
			# Start-of-turn banking.
			if not c.boosted_last:
				c.bp = min(MAX_BP, c.bp + 1)
			c.boosted_last = false
			if not c.is_enemy:
				c.sp = min(c.max_sp, c.sp + SP_REGEN)
				c.defending = false

			_bounce(c)
			if c.is_enemy:
				await _enemy_turn(c)
			else:
				await _player_turn(c)

			if _check_end():
				break
		await get_tree().process_frame

func _build_turn_order() -> void:
	var living := _all.filter(func(c): return c.alive)
	living.sort_custom(func(a, b): return a.spd > b.spd)
	_turn_order = living

# ===========================================================================
#  PLAYER TURN
# ===========================================================================
func _player_turn(actor: Combatant) -> void:
	_cur_actor = actor
	_cur_boost = 0
	if OS.has_environment("AUTO_BATTLE"):
		await _auto_player(actor)
		return
	while true:
		var cmd := await _command_menu(actor)
		if cmd == "attack":
			var t := await _pick_target(_enemies)
			if t == null:
				continue
			await _do_attack(actor, t, _basic_skill(actor), _cur_boost)
			_spend_boost(actor)
			return
		elif cmd == "skills":
			var skill := await _skill_menu(actor)
			if skill.is_empty():
				continue
			var targets: Array
			if skill["target"] == "ally":
				var t := await _pick_target(_allies)
				if t == null:
					continue
				targets = [t]
			elif skill["target"] == "all_enemies":
				targets = _enemies.filter(func(e): return e.alive)
			else:
				var t := await _pick_target(_enemies)
				if t == null:
					continue
				targets = [t]
			actor.sp -= int(skill["sp"])
			if skill["kind"] == "heal":
				await _do_heal(actor, targets[0], skill, _cur_boost)
			else:
				for t in targets:
					await _do_attack(actor, t, skill, _cur_boost)
			_spend_boost(actor)
			return
		elif cmd == "defend":
			actor.defending = true
			actor.sp = min(actor.max_sp, actor.sp + 6)
			_flash_message("%s takes a defensive stance." % actor.name, 0.8)
			Audio.play_sfx("cancel")
			await get_tree().create_timer(0.6).timeout
			return

# Headless self-play used to verify the full turn loop end-to-end.
func _auto_player(actor: Combatant) -> void:
	var foes := _enemies.filter(func(e): return e.alive)
	if foes.is_empty():
		return
	foes.sort_custom(func(a, b): return a.hp < b.hp)
	var target: Combatant = foes[0]
	var boost: int = min(MAX_SPEND, actor.bp)
	# Prefer an affordable attacking skill (exercises multi-hit + elements).
	var chosen := {}
	for s in actor.skills:
		if s["kind"] == "attack" and actor.sp >= int(s["sp"]):
			chosen = s
			break
	if chosen.is_empty():
		chosen = _basic_skill(actor)
	else:
		actor.sp -= int(chosen["sp"])
	if chosen.get("target", "enemy") == "all_enemies":
		for t in foes:
			await _do_attack(actor, t, chosen, boost)
	else:
		await _do_attack(actor, target, chosen, boost)
	_spend_boost(actor)

func _basic_skill(actor: Combatant) -> Dictionary:
	return {"name": "Attack", "type": WEAPON.get(actor.id, "sword"),
		"power": 9, "sp": 0, "target": "enemy", "kind": "attack", "hits": 1}

func _spend_boost(actor: Combatant) -> void:
	if _cur_boost > 0:
		actor.bp -= _cur_boost
		actor.boosted_last = true
	_cur_boost = 0

# --- command menu (Attack / Skills / Defend) + boost adjust -----------------
func _command_menu(actor: Combatant) -> String:
	_actor_label.text = "▸ %s" % actor.name
	var idx := await _run_menu(["Attack", "Skills", "Defend"], [true, true, true], true, actor)
	match idx:
		0: return "attack"
		1: return "skills"
		2: return "defend"
		_: return "attack"

func _skill_menu(actor: Combatant) -> Dictionary:
	var items: Array = []
	var enabled: Array = []
	for s in actor.skills:
		items.append("%s  %s  (SP %d)" % [_type_icon(s["type"]), s["name"], int(s["sp"])])
		enabled.append(actor.sp >= int(s["sp"]))
	items.append("← Back")
	enabled.append(true)
	var idx := await _run_menu(items, enabled, true, actor)
	if idx < 0 or idx >= actor.skills.size():
		return {}
	return actor.skills[idx]

# Generic keyboard menu. Returns chosen index, or -1 on cancel.
func _run_menu(items: Array, enabled: Array, allow_boost: bool, actor: Combatant) -> int:
	_menu_items = items
	_menu_enabled = enabled
	_menu_index = 0
	while not _menu_enabled[_menu_index]:
		_menu_index = (_menu_index + 1) % items.size()
	_menu_active = true
	_menu_allow_boost = allow_boost
	_redraw_menu()
	_menu_panel.visible = true
	var idx: int = await _menu_confirmed
	_menu_active = false
	_menu_panel.visible = false
	return idx

var _menu_allow_boost := false

func _redraw_menu() -> void:
	for child in _menu_vbox.get_children():
		child.queue_free()
	for i in _menu_items.size():
		var l := Label.new()
		var cursor := "▶ " if i == _menu_index else "   "
		l.text = cursor + str(_menu_items[i])
		l.add_theme_font_size_override("font_size", 22)
		var col := Color(1, 1, 0.7) if i == _menu_index else Color(0.9, 0.9, 0.95)
		if not _menu_enabled[i]:
			col = Color(0.5, 0.5, 0.55)
		l.add_theme_color_override("font_color", col)
		_menu_vbox.add_child(l)
	if _menu_allow_boost and _cur_actor != null:
		_boost_label.visible = true
		_boost_label.text = "BOOST  %s   (← / →)   BP %d/%d" % [_boost_pips(_cur_boost, _cur_actor.bp), _cur_actor.bp, MAX_BP]
	else:
		_boost_label.visible = false

func _boost_pips(spend: int, avail: int) -> String:
	var s := ""
	for i in MAX_SPEND:
		if i < spend:
			s += "◆"
		elif i < avail:
			s += "◇"
		else:
			s += "·"
	return s

# --- target picker ----------------------------------------------------------
func _pick_target(pool: Array) -> Combatant:
	_target_list = pool.filter(func(c): return c.alive)
	if _target_list.is_empty():
		return null
	_target_index = 0
	_target_active = true
	_reticle.visible = true
	var idx: int = await _target_confirmed
	_target_active = false
	_reticle.visible = false
	if idx < 0:
		return null
	return _target_list[idx]

# ===========================================================================
#  RESOLUTION
# ===========================================================================
func _do_attack(actor: Combatant, target: Combatant, skill: Dictionary, boost: int) -> void:
	if not target.alive:
		return
	var t: String = skill["type"]
	var is_phys := t in ["sword", "bow", "staff"]
	var statv := actor.atk if is_phys else actor.elm
	var base_hits := int(skill.get("hits", 1))
	var hits := base_hits
	var single_mult := 1.0
	if base_hits > 1:
		hits = base_hits + boost           # multi-hit: boost adds hits
	else:
		single_mult = 1.0 + 0.6 * boost    # single-hit: boost amplifies

	_flash_message("%s uses %s!%s" % [actor.name, skill["name"], "  ★BOOST" if boost > 0 else ""], 0.9)
	await _lunge(actor, target)
	Audio.play_sfx("attack")

	var is_weak: bool = target.is_enemy and target.weak.has(t)
	if target.is_enemy:
		target.revealed[t] = true

	var total := 0
	for h in hits:
		if not target.alive:
			break
		var mult := single_mult
		if is_weak:
			mult *= WEAKNESS_MULT
		if target.broken:
			mult *= BREAK_MULT
		var dmg: int = max(1, int(round((skill["power"] + statv) * mult)) - int(target.def * 0.5))
		total += dmg
		target.hp = max(0, target.hp - dmg)
		_popup(str(dmg), target, Color(1, 0.85, 0.4) if is_weak else Color(1, 1, 1))
		_hit_flash(target)
		# Shield break: each weakness hit removes one shield.
		if is_weak and not target.broken and target.shield > 0:
			target.shield -= 1
			if target.shield <= 0:
				await _do_break(target)
		await get_tree().create_timer(0.16).timeout

	if is_weak and not target.broken and target.shield > 0:
		_flash_message("Weakness hit!  Shield %d left." % target.shield, 0.7)
	if target.hp <= 0:
		await _kill(target)

func _do_heal(actor: Combatant, target: Combatant, skill: Dictionary, boost: int) -> void:
	var amt := int(round((skill["power"] + actor.elm * 0.5) * (1.0 + 0.7 * boost)))
	target.hp = min(target.max_hp, target.hp + amt)
	_flash_message("%s casts %s!" % [actor.name, skill["name"]], 0.9)
	Audio.play_sfx("heal")
	_popup("+%d" % amt, target, Color(0.5, 1, 0.6))
	await get_tree().create_timer(0.7).timeout

func _do_break(target: Combatant) -> void:
	target.broken = true
	target.broken_skip = 1
	target.shield = 0
	Audio.play_sfx("break")
	_flash_message("✦ BREAK!  %s's guard is shattered!" % target.name, 1.0)
	# Visual: stagger + grey tint.
	if is_instance_valid(target.sprite):
		target.sprite.modulate = Color(0.7, 0.7, 0.8)
		var tw := create_tween()
		tw.tween_property(target.root, "rotation_degrees:z", 12.0, 0.12)
		tw.tween_property(target.root, "rotation_degrees:z", 0.0, 0.5).set_trans(Tween.TRANS_ELASTIC)
	await get_tree().create_timer(0.5).timeout

func _recover_break(c: Combatant) -> void:
	c.broken = false
	c.shield = c.shield_max
	if is_instance_valid(c.sprite):
		c.sprite.modulate = Color(1, 1, 1)
	_flash_message("%s recovers." % c.name, 0.5)

func _kill(c: Combatant) -> void:
	c.alive = false
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(c.sprite, "modulate:a", 0.0, 0.5)
	tw.tween_property(c.root, "position:y", c.home.y + 0.6, 0.5)
	await tw.finished
	c.root.visible = false

# ===========================================================================
#  ENEMY AI
# ===========================================================================
func _enemy_turn(enemy: Combatant) -> void:
	var targets := _allies.filter(func(a): return a.alive)
	if targets.is_empty():
		return
	# Prefer the lowest-HP ally sometimes; otherwise random.
	var target: Combatant
	if randf() < 0.5:
		targets.sort_custom(func(a, b): return a.hp < b.hp)
		target = targets[0]
	else:
		target = targets[randi() % targets.size()]

	_flash_message("%s attacks!" % enemy.name, 0.8)
	await _lunge(enemy, target)
	Audio.play_sfx("attack")
	var dmg: int = max(1, int(enemy.atk * 1.1) - int(target.def * 0.4))
	if target.defending:
		dmg = int(dmg * 0.5)
	target.hp = max(0, target.hp - dmg)
	_popup(str(dmg), target, Color(1, 0.5, 0.5))
	_hit_flash(target)
	await get_tree().create_timer(0.4).timeout
	if target.hp <= 0:
		await _kill(target)

# ===========================================================================
#  END / RESULT
# ===========================================================================
func _check_end() -> bool:
	if _enemies.all(func(e): return not e.alive):
		_ended = true
		_victory()
		return true
	if _allies.all(func(a): return not a.alive):
		_ended = true
		_defeat()
		return true
	return false

func _victory() -> void:
	if OS.has_environment("AUTO_BATTLE"):
		print("AUTO_RESULT: VICTORY (round %d)" % _round)
	SceneManager.last_battle_won = true
	_flash_message("", 0.01)
	_banner("VICTORY!", "The party prevailed.  +120 EXP   +85 Leaves", Color(0.97, 0.88, 0.5))
	await get_tree().create_timer(2.6).timeout
	SceneManager.change_scene(SceneManager.return_scene)

func _defeat() -> void:
	if OS.has_environment("AUTO_BATTLE"):
		print("AUTO_RESULT: DEFEAT (round %d)" % _round)
	SceneManager.last_battle_won = false
	_banner("DEFEAT", "The party has fallen...", Color(0.9, 0.4, 0.4))
	await get_tree().create_timer(2.6).timeout
	SceneManager.change_scene("res://scenes/Title.tscn")

# ===========================================================================
#  INPUT
# ===========================================================================
func _unhandled_input(event: InputEvent) -> void:
	if _menu_active:
		if event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
			_move_menu(-1)
		elif event.is_action_pressed("move_down") or event.is_action_pressed("ui_down"):
			_move_menu(1)
		elif _menu_allow_boost and _cur_actor != null and (event.is_action_pressed("move_right") or event.is_action_pressed("ui_right")):
			_adjust_boost(1)
		elif _menu_allow_boost and _cur_actor != null and (event.is_action_pressed("move_left") or event.is_action_pressed("ui_left")):
			_adjust_boost(-1)
		elif event.is_action_pressed("confirm") or event.is_action_pressed("ui_accept"):
			if _menu_enabled[_menu_index]:
				Audio.play_sfx("confirm")
				emit_signal("_menu_confirmed", _menu_index)
		elif event.is_action_pressed("cancel"):
			Audio.play_sfx("cancel")
			emit_signal("_menu_confirmed", -1)
	elif _target_active:
		if event.is_action_pressed("move_left") or event.is_action_pressed("move_up") or event.is_action_pressed("ui_left"):
			_move_target(-1)
		elif event.is_action_pressed("move_right") or event.is_action_pressed("move_down") or event.is_action_pressed("ui_right"):
			_move_target(1)
		elif event.is_action_pressed("confirm") or event.is_action_pressed("ui_accept"):
			Audio.play_sfx("confirm")
			emit_signal("_target_confirmed", _target_index)
		elif event.is_action_pressed("cancel"):
			Audio.play_sfx("cancel")
			emit_signal("_target_confirmed", -1)

func _move_menu(dir: int) -> void:
	var n := _menu_items.size()
	for _i in n:
		_menu_index = (_menu_index + dir + n) % n
		if _menu_enabled[_menu_index]:
			break
	Audio.play_sfx("cursor")
	_redraw_menu()

func _move_target(dir: int) -> void:
	_target_index = (_target_index + dir + _target_list.size()) % _target_list.size()
	Audio.play_sfx("cursor")

func _adjust_boost(dir: int) -> void:
	var maxv: int = min(MAX_SPEND, _cur_actor.bp)
	var old := _cur_boost
	_cur_boost = clampi(_cur_boost + dir, 0, maxv)
	if _cur_boost != old:
		Audio.play_sfx("boost")
	_redraw_menu()

# ===========================================================================
#  ANIMATION HELPERS
# ===========================================================================
func _lunge(actor: Combatant, target: Combatant) -> void:
	if not is_instance_valid(actor.root):
		return
	var dir := (target.root.global_position - actor.root.global_position).normalized()
	var tw := create_tween()
	tw.tween_property(actor.root, "position", actor.home + dir * 1.1, 0.12).set_trans(Tween.TRANS_BACK)
	tw.tween_property(actor.root, "position", actor.home, 0.18)
	await tw.finished

func _bounce(c: Combatant) -> void:
	if not is_instance_valid(c.root):
		return
	var tw := create_tween()
	tw.tween_property(c.root, "position:y", c.home.y + 0.18, 0.15)
	tw.tween_property(c.root, "position:y", c.home.y, 0.18)

func _hit_flash(c: Combatant) -> void:
	if not is_instance_valid(c.sprite):
		return
	var base: Color = c.sprite.modulate
	var tw := create_tween()
	c.sprite.modulate = Color(1, 0.4, 0.4)
	tw.tween_property(c.sprite, "modulate", base, 0.25)
	var shake := create_tween()
	shake.tween_property(c.root, "position:x", c.home.x + 0.15, 0.04)
	shake.tween_property(c.root, "position:x", c.home.x, 0.08)

func _popup(text: String, c: Combatant, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	_ui.add_child(l)
	var sp := _cam.unproject_position(c.root.global_position + Vector3(0, 2.4, 0))
	l.position = sp + Vector2(randf_range(-12, 12), -10)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 55, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)

# ===========================================================================
#  UI
# ===========================================================================
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)

	_msg = Label.new()
	_msg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.position.y = 24
	_msg.add_theme_font_size_override("font_size", 28)
	_msg.add_theme_color_override("font_color", Color(1, 1, 1))
	_msg.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_msg.add_theme_constant_override("outline_size", 7)
	_ui.add_child(_msg)

	_order_label = Label.new()
	_order_label.position = Vector2(20, 70)
	_order_label.add_theme_font_size_override("font_size", 15)
	_order_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	_order_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_order_label.add_theme_constant_override("outline_size", 4)
	_ui.add_child(_order_label)

	# Command menu panel (bottom-left).
	_menu_panel = PanelContainer.new()
	_menu_panel.position = Vector2(40, 430)
	_menu_panel.custom_minimum_size = Vector2(330, 0)
	var sb := _panel_style()
	_menu_panel.add_theme_stylebox_override("panel", sb)
	_menu_panel.visible = false
	_ui.add_child(_menu_panel)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 4)
	_menu_panel.add_child(mv)
	_actor_label = Label.new()
	_actor_label.add_theme_font_size_override("font_size", 18)
	_actor_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	mv.add_child(_actor_label)
	_menu_vbox = VBoxContainer.new()
	_menu_vbox.add_theme_constant_override("separation", 2)
	mv.add_child(_menu_vbox)
	_boost_label = Label.new()
	_boost_label.add_theme_font_size_override("font_size", 17)
	_boost_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	mv.add_child(_boost_label)

	# Party status panels (bottom row).
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hb.offset_top = -96
	hb.offset_left = 16
	hb.offset_right = -16
	hb.add_theme_constant_override("separation", 10)
	hb.alignment = BoxContainer.ALIGNMENT_END
	_ui.add_child(hb)
	for c in _allies:
		var p := _make_party_panel(c)
		hb.add_child(p["panel"])
		_party_panels.append(p)

	# Enemy floating info.
	for c in _enemies:
		_enemy_info.append(_make_enemy_info(c))

	# Target reticle.
	_reticle = Label.new()
	_reticle.text = "▼"
	_reticle.add_theme_font_size_override("font_size", 34)
	_reticle.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	_reticle.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_reticle.add_theme_constant_override("outline_size", 6)
	_reticle.visible = false
	_ui.add_child(_reticle)

func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.12, 0.92)
	sb.border_color = Color(0.85, 0.78, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	return sb

func _make_party_panel(c: Combatant) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 84)
	panel.add_theme_stylebox_override("panel", _panel_style())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	panel.add_child(vb)
	var name := Label.new()
	name.add_theme_font_size_override("font_size", 17)
	name.add_theme_color_override("font_color", Color(0.97, 0.92, 0.7))
	vb.add_child(name)
	var hp := _bar(Color(0.4, 0.85, 0.4))
	var sp := _bar(Color(0.45, 0.6, 1.0))
	vb.add_child(hp["root"])
	vb.add_child(sp["root"])
	var bp := Label.new()
	bp.add_theme_font_size_override("font_size", 15)
	bp.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	vb.add_child(bp)
	return {"combatant": c, "panel": panel, "name": name, "hp": hp, "sp": sp, "bp": bp}

func _bar(color: Color) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(196, 16)
	var bg := ColorRect.new()
	bg.color = Color(0.15, 0.15, 0.2)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var fill := ColorRect.new()
	fill.color = color
	fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	fill.custom_minimum_size = Vector2(196, 16)
	root.add_child(fill)
	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	root.add_child(lbl)
	return {"root": root, "fill": fill, "label": lbl, "w": 196.0}

func _make_enemy_info(c: Combatant) -> Dictionary:
	var panel := PanelContainer.new()
	var sb := _panel_style()
	sb.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	panel.add_child(vb)
	var name := Label.new()
	name.add_theme_font_size_override("font_size", 15)
	name.add_theme_color_override("font_color", Color(1, 0.85, 0.8))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(name)
	var hp := _bar(Color(0.85, 0.4, 0.4))
	hp["root"].custom_minimum_size = Vector2(140, 12)
	hp["fill"].custom_minimum_size = Vector2(140, 12)
	hp["w"] = 140.0
	vb.add_child(hp["root"])
	var shield := Label.new()
	shield.add_theme_font_size_override("font_size", 14)
	shield.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(shield)
	var weak := Label.new()
	weak.add_theme_font_size_override("font_size", 13)
	weak.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	weak.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(weak)
	_ui.add_child(panel)
	return {"combatant": c, "panel": panel, "name": name, "hp": hp, "shield": shield, "weak": weak}

# ----- per-frame UI update --------------------------------------------------
func _process(_delta: float) -> void:
	if _cam == null:
		return
	for p in _party_panels:
		var c: Combatant = p["combatant"]
		p["name"].text = ("%s" % c.name) + ("  ☗" if c.defending else "")
		_set_bar(p["hp"], float(c.hp) / float(c.max_hp), "%d/%d" % [c.hp, c.max_hp])
		_set_bar(p["sp"], float(c.sp) / float(maxi(1, c.max_sp)), "SP %d" % c.sp)
		p["bp"].text = "BP " + _boost_pips_full(c.bp)
		p["panel"].modulate = Color(1, 1, 1) if c.alive else Color(0.5, 0.4, 0.4)
		p["panel"].self_modulate = Color(1, 1, 0.7) if (c == _cur_actor and (_menu_active or _target_active)) else Color(1, 1, 1)

	for e in _enemy_info:
		var c: Combatant = e["combatant"]
		if not c.alive:
			e["panel"].visible = false
			continue
		e["panel"].visible = true
		var sp := _cam.unproject_position(c.root.global_position + Vector3(0, 3.2 * float(c.get_meta("scale")), 0))
		e["panel"].position = sp - Vector2(e["panel"].size.x * 0.5, e["panel"].size.y)
		e["name"].text = c.name
		_set_bar(e["hp"], float(c.hp) / float(c.max_hp), "%d" % c.hp)
		if c.broken:
			e["shield"].text = "✦ BREAK ✦"
			e["shield"].add_theme_color_override("font_color", Color(1, 0.5, 0.3))
		else:
			e["shield"].text = "Shield " + "◆".repeat(c.shield) + "◇".repeat(c.shield_max - c.shield)
			e["shield"].add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		# Revealed weaknesses.
		var ws := ""
		for t in c.weak:
			ws += (_type_icon(t) + " ") if c.revealed.get(t, false) else "? "
		e["weak"].text = "Weak: " + ws

	# Reticle over current target.
	if _target_active and _target_index < _target_list.size():
		var t: Combatant = _target_list[_target_index]
		var sp := _cam.unproject_position(t.root.global_position + Vector3(0, 3.6, 0))
		_reticle.position = sp - Vector2(_reticle.size.x * 0.5, 0)

	# Turn order preview.
	if not _turn_order.is_empty():
		var names := []
		for c in _turn_order:
			if c.alive:
				names.append(c.name.substr(0, 6))
		_order_label.text = "Turn order:  " + " → ".join(names)

func _set_bar(bar: Dictionary, ratio: float, text: String) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	bar["fill"].custom_minimum_size.x = bar["w"] * ratio
	bar["fill"].size.x = bar["w"] * ratio
	bar["label"].text = text

func _boost_pips_full(bp: int) -> String:
	return "◆".repeat(bp) + "◇".repeat(MAX_BP - bp)

# ----- messages / banner ----------------------------------------------------
func _flash_message(text: String, hold: float) -> void:
	_msg.text = text
	_msg.modulate.a = 1.0

func _banner(title: String, subtitle: String, color: Color) -> void:
	_menu_panel.visible = false
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var sb := _panel_style()
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.95)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	_ui.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 52)
	t.add_theme_color_override("font_color", color)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	t.add_theme_constant_override("outline_size", 8)
	vb.add_child(t)
	var s := Label.new()
	s.text = subtitle
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_theme_font_size_override("font_size", 22)
	s.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0))
	vb.add_child(s)
	panel.scale = Vector2(0.7, 0.7)
	panel.pivot_offset = panel.size * 0.5
	var tw := create_tween()
	tw.tween_property(panel, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK)

func _type_icon(t: String) -> String:
	return GameData.TYPE_ICON.get(t, "?") + GameData.type_label(t)
