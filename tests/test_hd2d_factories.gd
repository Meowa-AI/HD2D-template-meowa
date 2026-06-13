extends SceneTree
## Headless assertions that the extracted factories emit exactly the original
## inline values. Run: godot --headless --script res://tests/test_hd2d_factories.gd
## Uses preload (not class_name) so it works without the global-class cache.

const Env := preload("res://scripts/HD2DEnvironment.gd")

var _fail := 0

func _eq(got, want, label: String) -> void:
	var ok := false
	if got is Color and want is Color:
		ok = got.is_equal_approx(want)
	elif (got is float or got is int) and (want is float or want is int):
		ok = is_equal_approx(float(got), float(want))
	else:
		ok = got == want
	if ok:
		print("ok  %s = %s" % [label, got])
	else:
		push_error("FAIL %s: got %s want %s" % [label, got, want])
		_fail += 1

func _initialize() -> void:
	var f := Env.environment("field")
	_eq(f.background_mode, Environment.BG_SKY, "field.bg")
	_eq(f.tonemap_mode, Environment.TONE_MAPPER_FILMIC, "field.tonemap")
	_eq(f.glow_intensity, 0.45, "field.glow_intensity")
	_eq(f.glow_bloom, 0.18, "field.glow_bloom")
	_eq(f.glow_hdr_threshold, 0.95, "field.glow_hdr")
	_eq(f.fog_enabled, true, "field.fog")
	_eq(f.fog_density, 0.005, "field.fog_density")
	_eq(f.adjustment_saturation, 1.18, "field.saturation")

	var b := Env.environment("battle")
	_eq(b.background_mode, Environment.BG_COLOR, "battle.bg")
	_eq(b.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR, "battle.ambient_src")
	_eq(b.glow_intensity, 0.5, "battle.glow_intensity")
	_eq(b.adjustment_saturation, 1.12, "battle.saturation")
	_eq(b.fog_enabled, false, "battle.fog_off")

	var unknown := Env.environment("bogus")
	_eq(unknown.background_mode, Environment.BG_SKY, "unknown.falls_back_to_field")

	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(_fail)
