extends Control
## Title screen. Painterly backdrop, game logo, blinking prompt. Enter starts.

var _started := false

func _ready() -> void:
	Audio.play_bgm("res://assets/audio/field_bgm.mp3")

	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists("res://assets/textures/battle_bg.jpg"):
		bg.texture = load("res://assets/textures/battle_bg.jpg")
	bg.modulate = Color(0.55, 0.6, 0.7, 1.0)
	add_child(bg)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.06, 0.45)
	add_child(dim)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 10)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vb)

	var title := Label.new()
	title.text = "WANDERERS OF ORSTERRA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.97, 0.88, 0.6))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.03))
	title.add_theme_constant_override("outline_size", 8)
	vb.add_child(title)

	var sub := Label.new()
	sub.text = "An HD-2D Tale  ·  Break & Boost"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	vb.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 60)
	vb.add_child(spacer)

	var prompt := Label.new()
	prompt.name = "Prompt"
	prompt.text = "▸  Press  Enter  to  begin  ◂"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 26)
	prompt.add_theme_color_override("font_color", Color(1, 1, 1))
	vb.add_child(prompt)

	# Blink the prompt.
	var tw := create_tween().set_loops()
	tw.tween_property(prompt, "modulate:a", 0.25, 0.7)
	tw.tween_property(prompt, "modulate:a", 1.0, 0.7)

	var hint := Label.new()
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.position.y -= 40
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "WASD / Arrows: move    E / Enter: interact    Step into tall grass to find battles"
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.8))
	add_child(hint)

func _unhandled_input(event: InputEvent) -> void:
	if _started:
		return
	if event.is_action_pressed("confirm") or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_started = true
		Audio.play_sfx("confirm")
		SceneManager.change_scene("res://scenes/Field.tscn")
