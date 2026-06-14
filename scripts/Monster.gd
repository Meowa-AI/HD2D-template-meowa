extends Node3D
## A roaming overworld monster (Cassette-Beasts style): wanders the meadow with a
## walk animation, flips to face its travel direction, and starts a battle when
## the player touches it.

const AnimatedBillboardScene := preload("res://scripts/AnimatedBillboard.gd")
const TieredTerrain := preload("res://scripts/TieredTerrain.gd")

var sheet_path := "res://assets/sprites/wolf_walk.png"
var frames := 6
var world_h := 2.0
var speed := 2.3
var bound := 10.0

var _spr: Sprite3D
var _target := Vector3.ZERO
var _repick_t := 0.0
var _player: Node3D
var _grace := 1.5

func _ready() -> void:
	_spr = AnimatedBillboardScene.new()
	add_child(_spr)
	_spr.setup(load(sheet_path), frames, world_h, 7.0)
	add_child(HD2D.blob_shadow(world_h * 0.22, 0.4))
	_pick_target()

func _pick_target() -> void:
	_target = Vector3(randf_range(-bound, bound), 0.0, randf_range(-bound, bound))
	_repick_t = randf_range(2.5, 5.0)

func _process(delta: float) -> void:
	_grace = maxf(0.0, _grace - delta)
	var to := _target - global_position
	to.y = 0.0
	if to.length() < 0.6:
		_pick_target()
	var step := to.normalized() * speed * delta
	global_position += step
	position.y = TieredTerrain.height_at(global_position.x, global_position.z)
	if absf(step.x) > 0.0005:
		_spr.flip_h = step.x < 0.0
	_repick_t -= delta
	if _repick_t <= 0.0:
		_pick_target()

	# Touch-to-fight.
	if _player != null and _grace <= 0.0 and global_position.distance_to(_player.global_position) < 1.4:
		_grace = 999.0
		SceneManager.set_meta("field_return_pos", _player.global_position)
		SceneManager.return_scene = "res://scenes/Field.tscn"
		SceneManager.encounter_transition("res://scenes/Battle.tscn")
