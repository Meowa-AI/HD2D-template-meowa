extends SceneTree
## Assertions for the pure dual-grid atlas math.
## Run: godot --headless --script res://tests/test_dualgrid.gd
const DualGrid := preload("res://scripts/DualGrid.gd")

var _fail := 0

func _ok(cond: bool, label: String) -> void:
	if cond:
		print("ok  %s" % label)
	else:
		push_error("FAIL %s" % label)
		_fail += 1

func _initialize() -> void:
	# mask packing: tl|tr<<1|bl<<2|br<<3
	_ok(DualGrid.tile_index(false, false, false, false) == 0, "mask none = 0")
	_ok(DualGrid.tile_index(true, false, false, false) == 1, "mask tl = 1")
	_ok(DualGrid.tile_index(false, true, false, false) == 2, "mask tr = 2")
	_ok(DualGrid.tile_index(false, false, true, false) == 4, "mask bl = 4")
	_ok(DualGrid.tile_index(false, false, false, true) == 8, "mask br = 8")
	_ok(DualGrid.tile_index(true, true, true, true) == 15, "mask all = 15")
	# UV rect for a 4x4 sheet: each tile is 1/4 x 1/4
	var r: Rect2 = DualGrid.tile_uv_rect(15)
	_ok(is_equal_approx(r.size.x, 0.25) and is_equal_approx(r.size.y, 0.25), "uv size = 1/4")
	# every mask maps to a distinct, in-range tile (complete 16-tile bijection)
	var seen := {}
	for m in range(16):
		var rr: Rect2 = DualGrid.tile_uv_rect(m)
		_ok(rr.position.x >= 0.0 and rr.position.x < 1.0 and rr.position.y >= 0.0 and rr.position.y < 1.0, "mask %d uv in range" % m)
		var key := "%d,%d" % [int(round(rr.position.x * 4.0)), int(round(rr.position.y * 4.0))]
		_ok(not seen.has(key), "mask %d distinct tile" % m)
		seen[key] = true
	if _fail == 0:
		print("ALL DUALGRID TESTS PASSED")
	quit(1 if _fail > 0 else 0)
