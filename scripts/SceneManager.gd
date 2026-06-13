extends CanvasLayer
## Scene transitions (autoload). Owns a full-screen fade rect and swaps scenes
## with a fade-out / fade-in. Also remembers where to return after a battle.

var _fade: ColorRect
var _busy := false

# Where to go back to after a battle ends, and how the last battle resolved.
var return_scene := "res://scenes/Field.tscn"
var last_battle_won := false

func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	# Offscreen screenshot hook (dev verification only; inert during normal play).
	if OS.has_environment("SHOT_OUT"):
		_auto_capture.call_deferred()

func _auto_capture() -> void:
	var frames := 90
	if OS.has_environment("SHOT_FRAMES"):
		frames = int(OS.get_environment("SHOT_FRAMES"))
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()

func change_scene(path: String, fade_time: float = 0.5) -> void:
	if _busy:
		return
	_busy = true
	await fade_to_black(fade_time)
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await fade_from_black(fade_time)
	_busy = false

# A punchier transition used when an encounter starts.
func encounter_transition(path: String) -> void:
	if _busy:
		return
	_busy = true
	Audio.play_sfx("encounter")
	# Quick double flash, then to black.
	for i in 2:
		_fade.color = Color(1, 1, 1, 0.0)
		var t := create_tween()
		t.tween_property(_fade, "color", Color(1, 1, 1, 0.85), 0.08)
		t.tween_property(_fade, "color", Color(1, 1, 1, 0.0), 0.10)
		await t.finished
	await fade_to_black(0.35)
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await fade_from_black(0.5)
	_busy = false

func fade_to_black(t: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color", Color(0, 0, 0, 1), t)
	await tw.finished

func fade_from_black(t: float) -> void:
	_fade.color = Color(0, 0, 0, 1)
	var tw := create_tween()
	tw.tween_property(_fade, "color", Color(0, 0, 0, 0), t)
	await tw.finished
