extends SceneTree
## Headless assertions that the factories emit the expected per-profile values
## (field values are the M2-tuned grade; battle is the original).
## Run: godot --headless --script res://tests/test_hd2d_factories.gd
## Uses preload (not class_name) so it works without the global-class cache.

const Env := preload("res://scripts/HD2DEnvironment.gd")
const Stage := preload("res://scripts/HD2DStage.gd")

var _fail := 0

func _eq(got, want, label: String) -> void:
	var ok := false
	if got is Color and want is Color:
		ok = got.is_equal_approx(want)
	elif got is Vector3 and want is Vector3:
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
	_eq(f.glow_intensity, 1.0, "field.glow_intensity")
	_eq(f.glow_bloom, 0.2, "field.glow_bloom")
	_eq(f.glow_hdr_threshold, 1.0, "field.glow_hdr")
	_eq(f.fog_enabled, true, "field.fog")
	_eq(f.fog_density, 0.0045, "field.fog_density")
	_eq(f.adjustment_saturation, 1.16, "field.saturation")
	# CB signature: lilac ambient (the GD4 indigo-shadow mechanism) + SSAO.
	_eq(f.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR, "field.ambient_src")
	_eq(f.ambient_light_color, Color(0.349, 0.325, 0.420), "field.ambient_color")
	_eq(f.ambient_light_energy, 0.5, "field.ambient_energy")
	_eq(f.ssao_enabled, true, "field.ssao")

	var b := Env.environment("battle")
	_eq(b.background_mode, Environment.BG_COLOR, "battle.bg")
	_eq(b.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR, "battle.ambient_src")
	_eq(b.ambient_light_color, Color(0.349, 0.325, 0.420), "battle.ambient_color")
	_eq(b.glow_intensity, 1.0, "battle.glow_intensity")
	_eq(b.adjustment_saturation, 1.16, "battle.saturation")
	_eq(b.ssao_enabled, true, "battle.ssao")
	_eq(b.fog_enabled, false, "battle.fog_off")

	var unknown := Env.environment("bogus")
	_eq(unknown.background_mode, Environment.BG_SKY, "unknown.falls_back_to_field")

	var fl := Stage.key_light("field")
	_eq(fl.shadow_enabled, true, "field.light.shadow")
	_eq(fl.light_energy, 1.0, "field.light.energy")
	_eq(fl.rotation_degrees, Vector3(-48, -28, 0), "field.light.rot")
	var bl := Stage.key_light("battle")
	_eq(bl.light_energy, 1.0, "battle.light.energy")
	_eq(bl.rotation_degrees, Vector3(-45, -20, 0), "battle.light.rot")

	var fc := Stage.make_camera("field")
	_eq(fc.fov, 30.0, "field.cam.fov")
	_eq((fc.attributes as CameraAttributesPractical).dof_blur_near_enabled, true, "field.cam.near_dof")
	_eq((fc.attributes as CameraAttributesPractical).dof_blur_amount, 0.12, "field.cam.dof_amount")
	var bc := Stage.make_camera("battle")
	_eq(bc.fov, 42.0, "battle.cam.fov")
	_eq((bc.attributes as CameraAttributesPractical).dof_blur_near_enabled, false, "battle.cam.no_near_dof")
	_eq((bc.attributes as CameraAttributesPractical).dof_blur_amount, 0.12, "battle.cam.dof_amount")

	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(_fail)
