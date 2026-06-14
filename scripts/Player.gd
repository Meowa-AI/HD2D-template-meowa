extends CharacterBody3D
## Field player. Moves on the ground plane as an 8-direction animated billboard:
## the facing sheet is picked from the movement angle and a 6-frame walk cycle
## plays while moving (idle = first frame). Lit so it catches the scene light.

const SPEED := 6.0
const ACCEL := 18.0

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

	var target := Vector3(input.x, 0.0, input.y) * SPEED
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)
	var before := global_position
	move_and_slide()
	moved_this_frame = global_position.distance_to(before)
	is_moving = input.length() > 0.05

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
