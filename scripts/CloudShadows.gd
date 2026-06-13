extends Node3D
## Drifting cloud shadows (Cassette-Beasts style). A handful of soft Decals
## project dark cloud blobs straight down onto the terrain (meadow + cliffs),
## sliding across the field in the wind so the ground breathes with light.

const COUNT := 7
const SPEED := 0.9          # world units / sec base drift
const Y := 16.0             # decal height above the field
const SIZE := 30.0          # blob diameter
const STRENGTH := 0.34

var _half := 50.0
var _decals: Array[Decal] = []
var _dir := Vector2(0.7, 0.4).normalized()

func setup(field_half: float) -> void:
	_half = field_half + 10.0

func _ready() -> void:
	var tex: Texture2D = null
	if ResourceLoader.exists("res://assets/textures/cloud_blob.png"):
		tex = load("res://assets/textures/cloud_blob.png")
	seed(11)
	for i in COUNT:
		var d := Decal.new()
		d.texture_albedo = tex
		d.size = Vector3(SIZE * (0.7 + randf() * 0.8), 40.0, SIZE * (0.7 + randf() * 0.8))
		d.modulate = Color(0.16, 0.16, 0.24)  # cool dark shadow
		d.albedo_mix = STRENGTH
		d.cull_mask = 0xFFFFF
		d.position = Vector3(randf_range(-_half, _half), Y, randf_range(-_half, _half))
		add_child(d)
		_decals.append(d)

func _process(delta: float) -> void:
	# Drift with the global wind direction; wrap around the field.
	var wd := Vector2(0.7, 0.4)
	var ml := get_tree()
	if ml != null:
		var ws = ml.root.get_node_or_null("WeatherSystem")
		if ws != null and ws.wind_strength.length() > 0.001:
			wd = Vector2(ws.wind_strength.x, ws.wind_strength.z)
	if wd.length() < 0.001:
		wd = Vector2(0.7, 0.4)
	wd = wd.normalized()
	var step := wd * SPEED * delta
	for d in _decals:
		d.position.x += step.x
		d.position.z += step.y
		if d.position.x > _half: d.position.x -= _half * 2.0
		if d.position.x < -_half: d.position.x += _half * 2.0
		if d.position.z > _half: d.position.z -= _half * 2.0
		if d.position.z < -_half: d.position.z += _half * 2.0
