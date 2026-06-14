extends CanvasLayer
## In-game visual tuner (toggle with F2). Live-edits the field's camera rig,
## depth-of-field and environment via sliders, and prints a pastable value dump
## to the Godot console ("Copy values"). Field scene only; wired in Field._ready.
## No persistence beyond the console dump — tune, copy, paste back into source.

var _field: Node3D
var _cam: Camera3D
var _attr: CameraAttributesPractical
var _env: Environment
var _daynight: Node

var _rows: Array = []  # slider rows needing per-frame label refresh: {get, label, fmt, auto, slider}

func setup(field: Node3D, cam: Camera3D, env: Environment, daynight: Node) -> void:
	_field = field
	_cam = cam
	_attr = cam.attributes as CameraAttributesPractical
	_env = env
	_daynight = daynight
	layer = 128
	_build_ui()
	visible = OS.has_environment("TUNER_OPEN")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		visible = not visible
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not visible:
		return
	# Keep day/night-driven sliders (ambient, exposure) honest while the cycle runs.
	for r in _rows:
		if r.get("auto", false):
			var v: float = r["get"].call()
			r["slider"].set_value_no_signal(v)
			r["label"].text = r["fmt"] % v

# ----------------------------------------------------------------------- UI
func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(16, 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.11, 0.9)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.45, 0.5, 0.6, 0.8)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(372, 624)
	panel.add_child(scroll)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	_vb = vb

	var title := Label.new()
	title.text = "VISUAL TUNER  ·  F2 to toggle"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.95, 0.86, 0.55))
	vb.add_child(title)

	_header("CAMERA")
	_slider("FOV", 20.0, 60.0, 0.5, func(): return _cam.fov, func(v): _cam.fov = v)
	_slider("Height (y)", 4.0, 40.0, 0.5,
		func(): return _field._cam_offset.y,
		func(v): var o = _field._cam_offset; o.y = v; _field._cam_offset = o)
	_slider("Distance (z)", 8.0, 60.0, 0.5,
		func(): return _field._cam_offset.z,
		func(v): var o = _field._cam_offset; o.z = v; _field._cam_offset = o)
	_slider("Look height", 0.0, 8.0, 0.1,
		func(): return _field._cam_look.y,
		func(v): var l = _field._cam_look; l.y = v; _field._cam_look = l)

	_header("DEPTH OF FIELD")
	_check("Near blur enabled",
		func(): return _attr.dof_blur_near_enabled,
		func(v): _attr.dof_blur_near_enabled = v)
	_slider("Near distance", 0.0, 60.0, 0.5,
		func(): return _attr.dof_blur_near_distance, func(v): _attr.dof_blur_near_distance = v)
	_slider("Near transition", 0.0, 30.0, 0.5,
		func(): return _attr.dof_blur_near_transition, func(v): _attr.dof_blur_near_transition = v)
	_check("Far blur enabled",
		func(): return _attr.dof_blur_far_enabled,
		func(v): _attr.dof_blur_far_enabled = v)
	_slider("Far distance", 10.0, 120.0, 0.5,
		func(): return _attr.dof_blur_far_distance, func(v): _attr.dof_blur_far_distance = v)
	_slider("Far transition", 0.0, 60.0, 0.5,
		func(): return _attr.dof_blur_far_transition, func(v): _attr.dof_blur_far_transition = v)
	_slider("Blur amount", 0.0, 1.0, 0.01,
		func(): return _attr.dof_blur_amount, func(v): _attr.dof_blur_amount = v)

	_header("ENVIRONMENT")
	_slider("Fog density", 0.0, 0.02, 0.0001,
		func(): return _env.fog_density, func(v): _env.fog_density = v)
	_slider("Fog aerial", 0.0, 1.0, 0.01,
		func(): return _env.fog_aerial_perspective, func(v): _env.fog_aerial_perspective = v)
	_slider("Glow intensity", 0.0, 2.0, 0.02,
		func(): return _env.glow_intensity, func(v): _env.glow_intensity = v)
	_slider("Glow bloom", 0.0, 1.0, 0.01,
		func(): return _env.glow_bloom, func(v): _env.glow_bloom = v)
	_slider("Saturation", 0.0, 2.0, 0.01,
		func(): return _env.adjustment_saturation, func(v): _env.adjustment_saturation = v)
	_slider("Contrast", 0.5, 2.0, 0.01,
		func(): return _env.adjustment_contrast, func(v): _env.adjustment_contrast = v)

	_header("DAY / NIGHT")
	_check("Pause day/night  (needed for the two * sliders to stick)",
		func(): return _daynight.paused, func(v): _daynight.paused = v)
	_slider("Ambient energy *", 0.0, 1.5, 0.01,
		func(): return _env.ambient_light_energy, func(v): _env.ambient_light_energy = v, true)
	_slider("Exposure *", 0.3, 1.5, 0.01,
		func(): return _env.tonemap_exposure, func(v): _env.tonemap_exposure = v, true)

	var copy := Button.new()
	copy.text = "Copy values  →  console"
	copy.focus_mode = Control.FOCUS_NONE
	copy.pressed.connect(_dump)
	vb.add_child(copy)

var _vb: VBoxContainer

func _header(text: String) -> void:
	var sep := HSeparator.new()
	_vb.add_child(sep)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.6, 0.78, 0.95))
	_vb.add_child(l)

# digits for the value label: tiny ranges (fog density) need more precision
func _fmt_for(max_val: float) -> String:
	if max_val <= 0.05:
		return "%.4f"
	elif max_val <= 2.0:
		return "%.2f"
	return "%.1f"

func _slider(label: String, lo: float, hi: float, step: float, getter: Callable, setter: Callable, auto: bool = false) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Label.new()
	name_lbl.text = label
	name_lbl.custom_minimum_size = Vector2(150, 0)
	name_lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(name_lbl)

	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = clampf(getter.call(), lo, hi)
	s.focus_mode = Control.FOCUS_NONE  # don't steal arrow keys from player movement
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(140, 0)
	row.add_child(s)

	var fmt := _fmt_for(hi)
	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(54, 0)
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.text = fmt % s.value
	row.add_child(val_lbl)

	s.value_changed.connect(func(v):
		setter.call(v)
		val_lbl.text = fmt % v)
	_vb.add_child(row)
	_rows.append({"get": getter, "label": val_lbl, "fmt": fmt, "auto": auto, "slider": s})

func _check(label: String, getter: Callable, setter: Callable) -> void:
	var c := CheckBox.new()
	c.text = label
	c.button_pressed = getter.call()
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 12)
	c.toggled.connect(func(p): setter.call(p))
	_vb.add_child(c)

# --------------------------------------------------------------- value dump
func _dump() -> void:
	var o = _field._cam_offset
	var lk = _field._cam_look
	var s := "\n========== VISUAL TUNER VALUES ==========\n"
	s += "# --- Field.gd (camera rig) ---\n"
	s += "var _cam_offset := Vector3(%.1f, %.2f, %.2f)\n" % [o.x, o.y, o.z]
	s += "var _cam_look := Vector3(%.1f, %.2f, %.1f)\n" % [lk.x, lk.y, lk.z]
	s += "\n# --- HD2DStage.make_camera (field branch) ---\n"
	s += "cam.fov = %.1f\n" % _cam.fov
	s += "\n# --- HD2DStage.apply_dof (field branch) ---\n"
	s += "attr.dof_blur_near_enabled = %s\n" % str(_attr.dof_blur_near_enabled).to_lower()
	s += "attr.dof_blur_near_distance = %.1f\n" % _attr.dof_blur_near_distance
	s += "attr.dof_blur_near_transition = %.1f\n" % _attr.dof_blur_near_transition
	s += "attr.dof_blur_far_enabled = %s\n" % str(_attr.dof_blur_far_enabled).to_lower()
	s += "attr.dof_blur_far_distance = %.1f\n" % _attr.dof_blur_far_distance
	s += "attr.dof_blur_far_transition = %.1f\n" % _attr.dof_blur_far_transition
	s += "attr.dof_blur_amount = %.3f\n" % _attr.dof_blur_amount
	s += "\n# --- HD2DEnvironment.environment (field branch) ---\n"
	s += "env.fog_density = %.4f\n" % _env.fog_density
	s += "env.fog_aerial_perspective = %.2f\n" % _env.fog_aerial_perspective
	s += "env.glow_intensity = %.2f\n" % _env.glow_intensity
	s += "env.glow_bloom = %.2f\n" % _env.glow_bloom
	s += "env.adjustment_saturation = %.2f\n" % _env.adjustment_saturation
	s += "env.adjustment_contrast = %.2f\n" % _env.adjustment_contrast
	s += "env.ambient_light_energy = %.2f  # DayNightCycle AMB_DAY lerp top\n" % _env.ambient_light_energy
	s += "env.tonemap_exposure = %.2f  # DayNightCycle exposure lerp top\n" % _env.tonemap_exposure
	s += "=========================================\n"
	print(s)
