extends Sprite3D
## A billboarded pixel sprite that loops a horizontal spritesheet (idle/ambient
## animation). Frame width is inferred from the sheet width / frame count. Used
## for NPCs and other ambient animated props.

var _frames := 1
var _fw := 0
var _fh := 0
var _fps := 5.0
var _t := 0.0

func setup(sheet: Texture2D, frames: int, world_h: float, fps: float = 5.0) -> void:
	texture = sheet
	_frames = maxi(1, frames)
	_fw = int(sheet.get_width() / _frames)
	_fh = sheet.get_height()
	_fps = fps
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	shaded = true
	double_sided = true
	alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	alpha_scissor_threshold = 0.4
	centered = true
	region_enabled = true
	region_rect = Rect2(0, 0, _fw, _fh)
	pixel_size = world_h / float(_fh)
	position.y = world_h * 0.5 - world_h * 0.04
	# desync identical sheets so NPCs don't breathe in lockstep
	_t = float(int(world_h * 97.0) % 100) * 0.03

func _process(delta: float) -> void:
	_t += delta * _fps
	region_rect.position.x = float((int(_t) % _frames) * _fw)
