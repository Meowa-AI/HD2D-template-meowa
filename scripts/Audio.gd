extends Node
## Audio manager (autoload). Crossfading BGM on one pair of stream players,
## plus a small pool of one-shot SFX players. SFX are referenced by short name.

const SFX := {
	"cursor": "res://assets/sfx/cursor.mp3",
	"confirm": "res://assets/sfx/confirm.mp3",
	"cancel": "res://assets/sfx/cancel.mp3",
	"attack": "res://assets/sfx/attack.mp3",
	"break": "res://assets/sfx/break.mp3",
	"heal": "res://assets/sfx/heal.mp3",
	"boost": "res://assets/sfx/boost.mp3",
	"encounter": "res://assets/sfx/encounter.mp3",
}

var _bgm_a: AudioStreamPlayer
var _bgm_b: AudioStreamPlayer
var _bgm_active: AudioStreamPlayer
var _sfx_pool: Array[AudioStreamPlayer] = []
var _current_bgm_path := ""
var _bgm_volume_db := -6.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bgm_a = _make_player(-80.0)
	_bgm_b = _make_player(-80.0)
	_bgm_active = _bgm_a
	for i in range(8):
		var p := _make_player(0.0)
		_sfx_pool.append(p)

func _make_player(vol: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = vol
	if not p.is_inside_tree():
		add_child(p)
	return p

func play_bgm(path: String, fade: float = 0.8) -> void:
	if path == _current_bgm_path and _bgm_active.playing:
		return
	_current_bgm_path = path
	var stream := _load_looping(path)
	if stream == null:
		return
	var next := _bgm_b if _bgm_active == _bgm_a else _bgm_a
	next.stream = stream
	next.volume_db = -80.0
	next.play()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(next, "volume_db", _bgm_volume_db, fade)
	tw.tween_property(_bgm_active, "volume_db", -80.0, fade)
	var prev := _bgm_active
	tw.chain().tween_callback(func(): prev.stop())
	_bgm_active = next

func stop_bgm(fade: float = 0.6) -> void:
	_current_bgm_path = ""
	var p := _bgm_active
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -80.0, fade)
	tw.tween_callback(func(): p.stop())

func play_sfx(name: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	var path: String = SFX.get(name, "")
	if path == "" or not ResourceLoader.exists(path):
		return
	var stream = load(path)
	for p in _sfx_pool:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = pitch
			p.volume_db = vol_db
			p.play()
			return

func _load_looping(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("BGM missing: %s" % path)
		return null
	var s = load(path)
	if s is AudioStreamMP3:
		s.loop = true
	elif s is AudioStreamOggVorbis or s is AudioStreamWAV:
		s.loop = true
	return s
