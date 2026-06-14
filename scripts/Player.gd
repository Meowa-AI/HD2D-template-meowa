extends CharacterBody3D
## Field player. Moves on the ground plane as an 8-direction animated billboard:
## the facing sheet is picked from the movement angle and a 6-frame walk cycle
## plays while moving (idle = first frame). Lit so it catches the scene light.

const SPEED := 8.0
const ACCEL := 18.0
const MAX_STEP := 1.7   # max walkable height change per step; steeper = blocked (cliffs/water)

const TieredTerrain := preload("res://scripts/TieredTerrain.gd")

const FRAME := 128          # walk-sheet frame size (px)
const FRAMES := 6           # frames per walk sheet (768 / 128)
const WORLD_H := 2.4        # on-screen height in world units
const WALK_FPS := 9.0

# Movement-angle sectors → facing key. Index = round(atan2(vx, vz) / 45deg).
const DIR_KEYS := ["s", "se", "e", "ne", "n", "nw", "w", "sw"]

var sprite_path := "res://assets/sprites/hero.png"  # kept for compatibility (unused)
var _sprite: Sprite3D
var _sheets := {}
var _dir := "s"
var _frame := 0
var _walk_t := 0.0
var is_moving := false
var moved_this_frame := 0.0
var facing := 1.0

func _ready() -> void:
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.4
	col.shape = shape
	col.position.y = 0.7
	add_child(col)

	for k in DIR_KEYS:
		var p := "res://assets/sprites/hero_walk/%s.png" % k
		if ResourceLoader.exists(p):
			_sheets[k] = load(p)

	_sprite = Sprite3D.new()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.shaded = true
	_sprite.double_sided = true
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	_sprite.alpha_scissor_threshold = 0.4
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(0, 0, FRAME, FRAME)
	_sprite.pixel_size = WORLD_H / float(FRAME)
	_sprite.position.y = WORLD_H * 0.5 - WORLD_H * 0.04
	if _sheets.has("s"):
		_sprite.texture = _sheets["s"]
	add_child(_sprite)

	add_child(HD2D.blob_shadow(0.55, 0.45))

func _physics_process(delta: float) -> void:
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	if input.length() > 1.0:
		input = input.normalized()

	# Walk on the terrain surface: axis-separated moves (so we slide along walls),
	# each blocked if the height change is too steep (cliff) or below water.
	var step := input * SPEED * delta
	var pos := global_position
	var base := TieredTerrain.height_at(pos.x, pos.z)
	var hx := TieredTerrain.height_at(pos.x + step.x, pos.z)
	if hx > TieredTerrain.WATER_LEVEL and absf(hx - base) <= MAX_STEP:
		pos.x += step.x
		base = hx
	var hz := TieredTerrain.height_at(pos.x, pos.z + step.y)
	if hz > TieredTerrain.WATER_LEVEL and absf(hz - base) <= MAX_STEP:
		pos.z += step.y
	moved_this_frame = Vector2(pos.x - global_position.x, pos.z - global_position.z).length()
	pos.y = TieredTerrain.height_at(pos.x, pos.z)
	global_position = pos
	is_moving = input.length() > 0.05 and moved_this_frame > 0.0005

	if is_moving:
		_dir = DIR_KEYS[(int(round(atan2(input.x, input.y) / (PI / 4.0))) + 8) % 8]
		if absf(input.x) > 0.01:
			facing = signf(input.x)
	_animate(delta)

func _animate(delta: float) -> void:
	if is_moving:
		_walk_t += delta * WALK_FPS
		_frame = int(_walk_t) % FRAMES
	else:
		_walk_t = 0.0
		_frame = 0
	if _sheets.has(_dir) and _sprite.texture != _sheets[_dir]:
		_sprite.texture = _sheets[_dir]
	_sprite.region_rect = Rect2(_frame * FRAME, 0, FRAME, FRAME)
