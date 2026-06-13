extends Node
## Global wind clock + body tracker (Cassette-Beasts style, autoload).
## Drives every wind-reactive material (grass, foliage) from one place so they
## sway in unison, and feeds player position(s) for grass push-away.

const MAX_BODIES := 2
const FAR := Vector3(99999, 99999, 99999)

var wind_phase := 0.0
var wind_speed := 1.1
var wind_strength := Vector3(0.13, 0.0, 0.07)  # world direction * magnitude

var _materials: Array[ShaderMaterial] = []
var _bodies := [FAR, FAR]

func register(mat: ShaderMaterial) -> void:
	if mat != null and not _materials.has(mat):
		_materials.append(mat)
		_push_one(mat)

func unregister(mat: ShaderMaterial) -> void:
	_materials.erase(mat)

func set_body(i: int, pos: Vector3) -> void:
	if i >= 0 and i < MAX_BODIES:
		_bodies[i] = pos

func clear_bodies() -> void:
	for i in MAX_BODIES:
		_bodies[i] = FAR

func _process(delta: float) -> void:
	wind_phase += TAU * delta * wind_speed
	if wind_phase > TAU * 1000.0:
		wind_phase = fmod(wind_phase, TAU)
	# Drop freed materials lazily, then push uniforms.
	for m in _materials:
		_push_one(m)

func _push_one(m: ShaderMaterial) -> void:
	m.set_shader_parameter("wind_phase", wind_phase)
	m.set_shader_parameter("wind_strength", wind_strength)
	m.set_shader_parameter("body_0", _bodies[0])
	m.set_shader_parameter("body_1", _bodies[1])
