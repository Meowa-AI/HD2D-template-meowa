extends RefCounted
## Pure dual-grid atlas math. A display tile sits over four data cells; each of
## its four corners is "on" if that data cell belongs to the overlay biome. The
## four corner bits select one of 16 tiles in a 4x4 dual-grid sheet.
##
## Corner bits: bit0=top-left, bit1=top-right, bit2=bottom-left, bit3=bottom-right.
## MASK_TO_TILE maps the 0..15 mask to a Vector2i(col,row) in the 4x4 sheet. These
## values were AUTO-DERIVED from the generated tileset art (sampling each tile's
## four corner quadrants), so they match the sheet's layout exactly — do not
## hand-edit without re-deriving from the art.

const COLS := 4
const ROWS := 4

const MASK_TO_TILE := [
	Vector2i(0, 3), # 0  ----  empty (never emitted)
	Vector2i(3, 3), # 1  T---  tl
	Vector2i(0, 2), # 2  -T--  tr
	Vector2i(1, 2), # 3  TT--  tl+tr
	Vector2i(0, 0), # 4  --T-  bl
	Vector2i(3, 2), # 5  T-T-  tl+bl
	Vector2i(2, 3), # 6  -TT-  tr+bl
	Vector2i(3, 1), # 7  TTT-  tl+tr+bl
	Vector2i(1, 3), # 8  ---T  br
	Vector2i(0, 1), # 9  T--T  tl+br
	Vector2i(1, 0), # 10 -T-T  tr+br
	Vector2i(2, 2), # 11 TT-T  tl+tr+br
	Vector2i(3, 0), # 12 --TT  bl+br
	Vector2i(2, 0), # 13 T-TT  tl+bl+br
	Vector2i(1, 1), # 14 -TTT  tr+bl+br
	Vector2i(2, 1), # 15 TTTT  all
]

static func tile_index(tl: bool, tr: bool, bl: bool, br: bool) -> int:
	return int(tl) | (int(tr) << 1) | (int(bl) << 2) | (int(br) << 3)

static func tile_uv_rect(mask: int) -> Rect2:
	var c: Vector2i = MASK_TO_TILE[mask]
	return Rect2(float(c.x) / float(COLS), float(c.y) / float(ROWS), 1.0 / float(COLS), 1.0 / float(ROWS))
