extends CharacterBody3D
## Field player. Moves on the ground plane, billboarded pixel sprite that flips
## with facing and does a little squash-bob while walking (we fake a walk cycle
## since the sprite is a single still frame).

const SPEED := 6.0
const ACCEL := 18.0

var sprite_path := "res://assets/sprites/hero.png"
var _sprite: Sprite3D
var _base_scale := Vector3.ONE
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

	_sprite = HD2D.character(sprite_path, 2.4, true)  # CB: lit so it catches the scene light
	add_child(_sprite)
	_base_scale = _sprite.scale

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

	if absf(input.x) > 0.01:
		facing = signf(input.x)
		_sprite.flip_h = facing < 0.0

	_animate(delta)

func _animate(delta: float) -> void:
	if is_moving:
		_walk_t += delta * 12.0
		var bob: float = absf(sin(_walk_t)) * 0.06
		var squash: float = sin(_walk_t * 2.0) * 0.04
		_sprite.position.y = (2.4 * 0.5 - 2.4 * 0.04) + bob
		_sprite.scale = Vector3(_base_scale.x * (1.0 + squash), _base_scale.y * (1.0 - squash), _base_scale.z)
	else:
		_walk_t = 0.0
		_sprite.position.y = lerp(_sprite.position.y, 2.4 * 0.5 - 2.4 * 0.04, delta * 10.0)
		_sprite.scale = _sprite.scale.lerp(_base_scale, delta * 10.0)
