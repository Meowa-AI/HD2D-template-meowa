extends Node
## Global data layer (autoload): party roster, enemy templates, skill/weakness
## definitions, and a few shared constants. Also installs WASD/interact input
## actions at runtime so we don't have to hand-author them in project.godot.

# Damage / weakness types. Weapons and elements are both "break" types in
# Octopath: hitting an enemy with a type it is weak to chips its shield.
const TYPES := {
	"sword": "Sword",
	"bow": "Bow",
	"staff": "Staff",
	"fire": "Fire",
	"ice": "Ice",
	"light": "Light",
}

# Small icon glyphs used in the battle UI to show weaknesses/skill types.
const TYPE_ICON := {
	"sword": "🗡", "bow": "🏹", "staff": "✚", "fire": "🔥", "ice": "❄", "light": "✦",
}

# Persistent party definitions. Each becomes a working Combatant in battle.
# skill = {name, type, power, sp, target, kind, hits}
#   target: "enemy" | "ally" | "all_enemies"
#   kind:   "attack" | "heal" | "defend"
var party: Array = [
	{
		"id": "hero", "name": "Aldric", "job": "Warrior",
		"sprite": "res://assets/sprites/hero.png",
		"max_hp": 92, "max_sp": 28,
		"atk": 22, "def": 16, "elm": 10, "spd": 11,
		"skills": [
			{"name": "Slash", "type": "sword", "power": 14, "sp": 0, "target": "enemy", "kind": "attack", "hits": 1},
			{"name": "Cross Strike", "type": "sword", "power": 10, "sp": 6, "target": "enemy", "kind": "attack", "hits": 2},
			{"name": "Guard", "type": "sword", "power": 0, "sp": 0, "target": "ally", "kind": "defend", "hits": 0},
		],
	},
	{
		"id": "mage", "name": "Seraphine", "job": "Sorcerer",
		"sprite": "res://assets/sprites/mage.png",
		"max_hp": 64, "max_sp": 42,
		"atk": 9, "def": 11, "elm": 24, "spd": 12,
		"skills": [
			{"name": "Fireball", "type": "fire", "power": 16, "sp": 5, "target": "enemy", "kind": "attack", "hits": 1},
			{"name": "Ice Lance", "type": "ice", "power": 16, "sp": 5, "target": "enemy", "kind": "attack", "hits": 1},
			{"name": "Inferno", "type": "fire", "power": 12, "sp": 11, "target": "all_enemies", "kind": "attack", "hits": 1},
		],
	},
	{
		"id": "cleric", "name": "Lumen", "job": "Cleric",
		"sprite": "res://assets/sprites/cleric.png",
		"max_hp": 70, "max_sp": 38,
		"atk": 12, "def": 14, "elm": 19, "spd": 10,
		"skills": [
			{"name": "Heal", "type": "light", "power": 34, "sp": 4, "target": "ally", "kind": "heal", "hits": 0},
			{"name": "Radiance", "type": "light", "power": 15, "sp": 6, "target": "enemy", "kind": "attack", "hits": 1},
			{"name": "Smite", "type": "staff", "power": 11, "sp": 0, "target": "enemy", "kind": "attack", "hits": 1},
		],
	},
	{
		"id": "hunter", "name": "Rowan", "job": "Hunter",
		"sprite": "res://assets/sprites/hunter.png",
		"max_hp": 76, "max_sp": 30,
		"atk": 19, "def": 13, "elm": 11, "spd": 15,
		"skills": [
			{"name": "Quick Shot", "type": "bow", "power": 12, "sp": 0, "target": "enemy", "kind": "attack", "hits": 1},
			{"name": "Arrow Volley", "type": "bow", "power": 7, "sp": 7, "target": "enemy", "kind": "attack", "hits": 3},
			{"name": "Mend", "type": "staff", "power": 24, "sp": 5, "target": "ally", "kind": "heal", "hits": 0},
		],
	},
]

# Enemy templates used to populate a battle.
const ENEMIES := {
	"wolf": {
		"name": "Dire Wolf", "sprite": "res://assets/sprites/wolf.png",
		"max_hp": 120, "atk": 18, "def": 10, "spd": 14,
		"shield": 3, "weak": ["bow", "ice", "fire"],
		"scale": 1.25,
	},
	"goblin": {
		"name": "Goblin Brigand", "sprite": "res://assets/sprites/goblin.png",
		"max_hp": 78, "atk": 13, "def": 8, "spd": 9,
		"shield": 2, "weak": ["sword", "fire", "light"],
		"scale": 1.0,
	},
}

# Which enemies appear in the slice's encounter.
const ENCOUNTER := ["wolf", "goblin", "goblin"]

func _ready() -> void:
	_install_inputs()

# Add WASD + interact on top of the built-in ui_* arrow/enter/esc actions so
# both control schemes work without editing project.godot.
func _install_inputs() -> void:
	_add_key("move_up", [KEY_W, KEY_UP])
	_add_key("move_down", [KEY_S, KEY_DOWN])
	_add_key("move_left", [KEY_A, KEY_LEFT])
	_add_key("move_right", [KEY_D, KEY_RIGHT])
	_add_key("interact", [KEY_E, KEY_ENTER, KEY_SPACE])
	_add_key("confirm", [KEY_ENTER, KEY_SPACE, KEY_E, KEY_Z])
	_add_key("cancel", [KEY_ESCAPE, KEY_X, KEY_BACKSPACE])

func _add_key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

func type_label(t: String) -> String:
	return TYPES.get(t, t)

func party_sprite(id: String) -> String:
	for d in party:
		if d["id"] == id:
			return d["sprite"]
	return "res://assets/sprites/hero.png"
