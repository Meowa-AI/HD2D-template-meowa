extends Node
## Cassette-Beasts-style day/night cycle. Drives the field sun + environment over
## a normalized time-of-day (0..1). Keeps the sun's yaw front-lit (so billboards
## stay readable) and animates colour, energy, ambient, fog and sky brightness —
## dawn gold, noon cool-white, dusk gold, night blue.

var sun: DirectionalLight3D
var env: Environment

var time := 0.34          # start mid-morning (full day)
var day_length := 150.0   # seconds per full 24h cycle
var paused := false

const SUN_DAY := Color(1.0, 0.98, 0.95)
const SUN_GOLD := Color(1.0, 0.66, 0.42)
const SUN_NIGHT := Color(0.45, 0.58, 0.95)
const AMB_DAY := Color(0.349, 0.325, 0.420)
const AMB_NIGHT := Color(0.12, 0.14, 0.27)
const FOG_DAY := Color(0.502, 0.600, 0.702)
const FOG_NIGHT := Color(0.10, 0.13, 0.23)

func _ready() -> void:
	if OS.has_environment("DAY_TIME"):
		time = clampf(float(OS.get_environment("DAY_TIME")), 0.0, 1.0)
	_apply()

func _process(delta: float) -> void:
	if paused:
		return
	time = fmod(time + delta / day_length, 1.0)
	_apply()

func _apply() -> void:
	# daylight: 1 during day, 0 at night, ramped at dawn (~0.27) and dusk (~0.72)
	var d := clampf(smoothstep(0.22, 0.32, time) - smoothstep(0.68, 0.78, time), 0.0, 1.0)
	# golden hour: peaks near sunrise and sunset
	var gold := clampf(1.0 - absf(time - 0.27) / 0.055, 0.0, 1.0)
	gold = maxf(gold, clampf(1.0 - absf(time - 0.72) / 0.055, 0.0, 1.0)) * d

	if sun != null:
		var c := SUN_NIGHT.lerp(SUN_DAY, d)
		c = c.lerp(SUN_GOLD, gold * 0.85)
		sun.light_color = c
		sun.light_energy = lerpf(0.35, 1.0, d)
		sun.rotation_degrees.x = lerpf(-26.0, -52.0, d)  # lower at dawn/dusk, high at noon; yaw stays front-lit

	if env != null:
		env.ambient_light_color = AMB_NIGHT.lerp(AMB_DAY, d)
		env.ambient_light_energy = lerpf(0.30, 0.6, d)
		env.fog_light_color = FOG_NIGHT.lerp(FOG_DAY, d)
		env.background_energy_multiplier = lerpf(0.18, 1.0, d)
		env.tonemap_exposure = lerpf(0.62, 0.97, d)
