# Layered-Alpha Dual-Grid Terrain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the field terrain's hard per-cell biome seams with natural transitions, by compositing transparent-edge dual-grid tilesets as stacked alpha layers over an opaque grass base.

**Architecture:** Grass is an opaque base heightfield. Each other biome (forest, flower, rock, sand) is an overlay mesh on a half-cell-offset dual-grid render grid, textured with its own `biome → transparent` dual-grid-15 tileset and alpha-blended; layers are ordered by `render_priority` + a small Y lift. A pure `DualGrid` helper maps a tile's 4 corner booleans to an atlas sub-rect. `height_at`/`biome_at`, camera, DOF, day/night are untouched.

**Tech Stack:** Godot 4.6 GDScript, `SurfaceTool`/`ArrayMesh`, `StandardMaterial3D` alpha; Meowa `tileset-gen-run --tileset-mode dual-grid-15`; headless `xvfb` + lavapipe screenshots; SceneTree assertion tests.

**Spec:** `docs/superpowers/specs/2026-06-14-terrain-layered-alpha-dualgrid-design.md`

---

## File Structure

- **Create `scripts/DualGrid.gd`** — pure helpers: 4-corner mask → tile index, tile index → atlas UV `Rect2`. One responsibility (dual-grid atlas math), no scene/mesh deps, unit-testable.
- **Create `tests/test_dualgrid.gd`** — SceneTree assertions for the `DualGrid` math.
- **Modify `scripts/TieredTerrain.gd`** — split `build()` into an opaque grass base layer + per-biome alpha overlay layers on the offset render grid; add `_overlay_layer()` and overlay-quad helpers; keep cliff handling on the base. `height_at`/`biome_at` unchanged.
- **Create `assets/textures/tilesets/{forest_floor,flower_meadow,rock_ground,sand}_dualgrid.png`** (+ their `.import`) — the four transparent dual-grid sheets.

Layer order (bottom→top): grass base → `forest_floor` → `flower_meadow` → `rock_ground` → `sand` → existing water plane.

Corner bit convention (used everywhere): `bit0=top-left, bit1=top-right, bit2=bottom-left, bit3=bottom-right`; `mask = tl | tr<<1 | bl<<2 | br<<3` (0..15).

---

## Task 1: Generate + verify the four transparent dual-grid tilesets

**Files:**
- Create: `assets/textures/tilesets/forest_floor_dualgrid.png`, `flower_meadow_dualgrid.png`, `rock_ground_dualgrid.png`, `sand_dualgrid.png`

- [ ] **Step 1: Confirm Meowa auth**

Run from project root:
```bash
python3 .agents/skills/game-assets/meowart_api.py credits-balance
```
Expected: a positive credit balance (auth via project `.env`). If it errors, ensure `.env` has `MEOWART_API_KEY=ma_live_...`.

- [ ] **Step 2: Generate the four tilesets (background)**

Run each (launch with run_in_background; they auto-poll). Foreground = the existing biome texture; no `--background-texture` so the background resolves to empty/transparent; prompt states transparent background explicitly:
```bash
cd .agents/skills/game-assets
python3 meowart_api.py tileset-gen-run --tileset-mode dual-grid-15 \
  --job-name forest_dg \
  --foreground-texture ../../../assets/textures/forest_floor.png \
  --prompt "forest floor terrain patch, organic irregular edge fading to a fully transparent (alpha 0) background, top-down" \
  --output-dir ./outputs/forest_dg
python3 meowart_api.py tileset-gen-run --tileset-mode dual-grid-15 \
  --job-name flower_dg \
  --foreground-texture ../../../assets/textures/flower_meadow.png \
  --prompt "flower meadow terrain patch, organic irregular edge fading to a fully transparent (alpha 0) background, top-down" \
  --output-dir ./outputs/flower_dg
python3 meowart_api.py tileset-gen-run --tileset-mode dual-grid-15 \
  --job-name rock_dg \
  --foreground-texture ../../../assets/textures/rock_ground.png \
  --prompt "rocky highland ground patch, organic irregular edge fading to a fully transparent (alpha 0) background, top-down" \
  --output-dir ./outputs/rock_dg
python3 meowart_api.py tileset-gen-run --tileset-mode dual-grid-15 \
  --job-name sand_dg \
  --foreground-texture ../../../assets/textures/sand.png \
  --prompt "sandy lakeshore ground patch, organic irregular edge fading to a fully transparent (alpha 0) background, top-down" \
  --output-dir ./outputs/sand_dg
```
Expected: each run writes generated PNG(s) + a preview into its `outputs/<name>` dir.

- [ ] **Step 3: Inspect previews — verify transparency + lock the atlas layout**

Use the Read tool on each `outputs/*/...preview*.png` (and the main sheet PNG). Confirm:
1. The sheet is a **4×4 grid of 16 tiles** (15 transitions + 1 empty). Note the per-tile pixel size `T` (e.g. 64 or 128) and that the full sheet is `4T × 4T`.
2. Edges are **truly transparent** (alpha 0), not a solid matte color.

If the background is opaque instead of transparent, FALLBACK: re-run adding `--background-texture` pointing at a transparent 1×1 PNG, or post-process to key out the solid background to alpha (ImageMagick `convert sheet.png -fuzz 5% -transparent '<bgcolor>' sheet.png`). Re-inspect.

Document, for each of the 16 tile positions `(col,row)`, **which corners are filled** with foreground. This is the ground truth for Task 2's `MASK_TO_TILE`.

- [ ] **Step 4: Copy chosen sheets to clean game paths**

```bash
mkdir -p assets/textures/tilesets
cp .agents/skills/game-assets/outputs/forest_dg/<chosen>.png assets/textures/tilesets/forest_floor_dualgrid.png
cp .agents/skills/game-assets/outputs/flower_dg/<chosen>.png assets/textures/tilesets/flower_meadow_dualgrid.png
cp .agents/skills/game-assets/outputs/rock_dg/<chosen>.png   assets/textures/tilesets/rock_ground_dualgrid.png
cp .agents/skills/game-assets/outputs/sand_dg/<chosen>.png   assets/textures/tilesets/sand_dualgrid.png
```
(Replace `<chosen>` with the actual generated filename per preview.)

- [ ] **Step 5: Import + commit the assets**

Let Godot import them (generates `.import`):
```bash
godot --headless --quit-after 5 res://scenes/Field.tscn >/dev/null 2>&1
git add assets/textures/tilesets/
git commit -m "art(field): transparent dual-grid tilesets for biome overlays"
```
Expected: four PNGs + four `.import` files tracked.

---

## Task 2: `DualGrid` atlas math (TDD)

**Files:**
- Create: `scripts/DualGrid.gd`
- Test: `tests/test_dualgrid.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/test_dualgrid.gd`:
```gdscript
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
	_ok(DualGrid.tile_index(true, true, true, true) == 15, "mask all = 15")
	# UV rect for a 4x4 sheet: each tile is 1/4 x 1/4; covers [0,1)
	var r: Rect2 = DualGrid.tile_uv_rect(15)
	_ok(is_equal_approx(r.size.x, 0.25) and is_equal_approx(r.size.y, 0.25), "uv size = 1/4")
	_ok(r.position.x >= 0.0 and r.position.x < 1.0 and r.position.y >= 0.0 and r.position.y < 1.0, "uv in range")
	# every mask maps to a distinct in-range tile
	var seen := {}
	for m in range(16):
		var rr: Rect2 = DualGrid.tile_uv_rect(m)
		var key := "%d,%d" % [int(round(rr.position.x * 4.0)), int(round(rr.position.y * 4.0))]
		_ok(not seen.has(key), "mask %d distinct tile" % m)
		seen[key] = true
	if _fail == 0:
		print("ALL DUALGRID TESTS PASSED")
	quit(1 if _fail > 0 else 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script res://tests/test_dualgrid.gd`
Expected: FAIL — `DualGrid.gd` does not exist / preload error.

- [ ] **Step 3: Write `DualGrid.gd`**

Create `scripts/DualGrid.gd`:
```gdscript
extends RefCounted
## Pure dual-grid atlas math. A display tile sits over four data cells; each of
## its four corners is "on" if that data cell belongs to the overlay biome. The
## four corner bits select one of 16 tiles in a 4x4 dual-grid sheet.
##
## Corner bits: bit0=top-left, bit1=top-right, bit2=bottom-left, bit3=bottom-right.
## MASK_TO_TILE maps the 0..15 mask to a Vector2i(col,row) in the 4x4 sheet. The
## values below are the row-major canonical layout; CONFIRM against the generated
## preview (Task 1, Step 3) and edit any entry whose art puts that corner-combo at
## a different (col,row). A wrong entry shows as a mismatched border in the Task 4
## screenshot.

const COLS := 4
const ROWS := 4

const MASK_TO_TILE := [
	Vector2i(0, 0), # 0  ----  empty (never emitted)
	Vector2i(1, 0), # 1  T---  tl
	Vector2i(2, 0), # 2  -T--  tr
	Vector2i(3, 0), # 3  TT--  tl+tr
	Vector2i(0, 1), # 4  --T-  bl
	Vector2i(1, 1), # 5  T-T-  tl+bl
	Vector2i(2, 1), # 6  -TT-  tr+bl
	Vector2i(3, 1), # 7  TTT-  tl+tr+bl
	Vector2i(0, 2), # 8  ---T  br
	Vector2i(1, 2), # 9  T--T  tl+br
	Vector2i(2, 2), # 10 -T-T  tr+br
	Vector2i(3, 2), # 11 TT-T  tl+tr+br
	Vector2i(0, 3), # 12 --TT  bl+br
	Vector2i(1, 3), # 13 T-TT  tl+bl+br
	Vector2i(2, 3), # 14 -TTT  tr+bl+br
	Vector2i(3, 3), # 15 TTTT  all
]

static func tile_index(tl: bool, tr: bool, bl: bool, br: bool) -> int:
	return int(tl) | (int(tr) << 1) | (int(bl) << 2) | (int(br) << 3)

static func tile_uv_rect(mask: int) -> Rect2:
	var c: Vector2i = MASK_TO_TILE[mask]
	return Rect2(float(c.x) / float(COLS), float(c.y) / float(ROWS), 1.0 / float(COLS), 1.0 / float(ROWS))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --script res://tests/test_dualgrid.gd`
Expected: `ALL DUALGRID TESTS PASSED`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/DualGrid.gd tests/test_dualgrid.gd
git commit -m "feat(field): DualGrid atlas math + tests"
```

---

## Task 3: Rework `TieredTerrain.build()` into base + alpha overlay layers

**Files:**
- Modify: `scripts/TieredTerrain.gd`

- [ ] **Step 1: Add the overlay biome table + tileset paths**

After the existing `TEX` constant in `scripts/TieredTerrain.gd`, add:
```gdscript
# Overlay biomes (everything except grassland=0). Rendered bottom→top as alpha
# layers over the opaque grass base; each uses its transparent dual-grid sheet.
const OVERLAYS := [
	{"biome": 2, "tex": "res://assets/textures/tilesets/forest_floor_dualgrid.png"},
	{"biome": 1, "tex": "res://assets/textures/tilesets/flower_meadow_dualgrid.png"},
	{"biome": 3, "tex": "res://assets/textures/tilesets/rock_ground_dualgrid.png"},
	{"biome": 4, "tex": "res://assets/textures/tilesets/sand_dualgrid.png"},
]
const DualGrid := preload("res://scripts/DualGrid.gd")
```

- [ ] **Step 2: Make the grass base layer opaque-only + add overlay layers in `build()`**

Replace the body of `build()` so the per-biome top surfaces collapse to a single
grass base surface (grass texture everywhere on the walkable top) plus the cliff
surface, then append one overlay mesh per `OVERLAYS` entry. Replace the current
`build()` with:
```gdscript
static func build(half: float = 72.0) -> Node3D:
	var root := Node3D.new()
	var base := SurfaceTool.new(); base.begin(Mesh.PRIMITIVE_TRIANGLES)   # opaque grass top
	var cliff := SurfaceTool.new(); cliff.begin(Mesh.PRIMITIVE_TRIANGLES) # steep faces

	var n := int(half * 2.0 / CELL)
	for gx in n:
		for gz in n:
			var x0 := -half + gx * CELL
			var z0 := -half + gz * CELL
			var x1 := x0 + CELL
			var z1 := z0 + CELL
			var h00 := height_at(x0, z0); var h10 := height_at(x1, z0)
			var h11 := height_at(x1, z1); var h01 := height_at(x0, z1)
			var span: float = maxf(maxf(h00, h10), maxf(h11, h01)) - minf(minf(h00, h10), minf(h11, h01))
			var st: SurfaceTool = cliff if span > CLIFF_SPAN else base
			_add_quad(st, x0, z0, x1, z1, h00, h10, h11, h01)

	var mesh := ArrayMesh.new()
	var mats: Array[Material] = []
	var bm := base.commit()
	if bm.get_surface_count() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bm.surface_get_arrays(0))
		mats.append(_mat("res://assets/textures/grass.png", Color(1, 1, 1), 1.0))
	var cm := cliff.commit()
	if cm.get_surface_count() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cm.surface_get_arrays(0))
		mats.append(_mat("res://assets/textures/cliff.png", Color(1.0, 0.98, 0.94), 0.5))
	for i in mats.size():
		mesh.surface_set_material(i, mats[i])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)

	# Alpha overlay layers (dual-grid), bottom→top in OVERLAYS order.
	for i in OVERLAYS.size():
		var layer := _overlay_layer(half, OVERLAYS[i]["biome"], OVERLAYS[i]["tex"], i + 1)
		if layer != null:
			root.add_child(layer)
	return root
```

- [ ] **Step 3: Add the overlay-layer builder**

Add to `scripts/TieredTerrain.gd` (helpers section). The overlay uses the
half-cell-offset render grid: render-tile corners are data-cell centers, so each
render tile reads four `biome_at(center)` values:
```gdscript
# One alpha overlay layer for `biome`, on the half-cell-offset dual-grid render
# grid. Returns null if the biome never appears. `order` drives render_priority
# and a small Y lift so layers stack without z-fighting.
static func _overlay_layer(half: float, biome: int, tex_path: String, order: int) -> MeshInstance3D:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(half * 2.0 / CELL)
	var emitted := false
	# Render-grid nodes sit at data-cell centers: center(i) = -half + (i+0.5)*CELL.
	# A render tile spans centers (i,j)..(i+1,j+1); its 4 corners map to those cells.
	for i in range(n - 1):
		for j in range(n - 1):
			var cxa := -half + (i + 0.5) * CELL
			var cza := -half + (j + 0.5) * CELL
			var cxb := cxa + CELL
			var czb := cza + CELL
			var tl := biome_at(cxa, cza) == biome
			var tr := biome_at(cxb, cza) == biome
			var bl := biome_at(cxa, czb) == biome
			var br := biome_at(cxb, czb) == biome
			var mask := DualGrid.tile_index(tl, tr, bl, br)
			if mask == 0:
				continue
			emitted = true
			_add_overlay_quad(st, cxa, cza, cxb, czb, DualGrid.tile_uv_rect(mask))
	if not emitted:
		return null
	var m := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var lift := 0.02 * float(order)   # stack above grass; avoids z-fighting on slopes
	mi.position.y = lift
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		mat.albedo_texture = load(tex_path)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = order   # higher = drawn later (on top)
	m.surface_set_material(0, mat)
	return mi
```

- [ ] **Step 4: Add the overlay quad helper (UVs from the atlas sub-rect)**

Add to `scripts/TieredTerrain.gd`. Unlike `_add_quad` (which tiles a texture by
world position), overlay quads map the four corners to the chosen atlas sub-rect:
```gdscript
static func _add_overlay_quad(st: SurfaceTool, x0: float, z0: float, x1: float, z1: float, uv: Rect2) -> void:
	var h00 := height_at(x0, z0); var h10 := height_at(x1, z0)
	var h11 := height_at(x1, z1); var h01 := height_at(x0, z1)
	var p00 := Vector3(x0, h00, z0); var p10 := Vector3(x1, h10, z0)
	var p11 := Vector3(x1, h11, z1); var p01 := Vector3(x0, h01, z1)
	var n00 := _normal_at(x0, z0); var n10 := _normal_at(x1, z0)
	var n11 := _normal_at(x1, z1); var n01 := _normal_at(x0, z1)
	var u00 := uv.position
	var u10 := uv.position + Vector2(uv.size.x, 0)
	var u11 := uv.position + uv.size
	var u01 := uv.position + Vector2(0, uv.size.y)
	_vtx(st, p00, n00, u00); _vtx(st, p10, n10, u10); _vtx(st, p11, n11, u11)
	_vtx(st, p00, n00, u00); _vtx(st, p11, n11, u11); _vtx(st, p01, n01, u01)
```

- [ ] **Step 5: Verify it loads headless without errors**

Run: `godot --headless --quit-after 120 res://scenes/Field.tscn 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Nonexistent|Invalid"`
Expected: no output (no script/parse errors). The benign "resources still in use at exit" line is fine.

- [ ] **Step 6: Commit**

```bash
git add scripts/TieredTerrain.gd
git commit -m "feat(field): layered alpha dual-grid biome overlays on the heightfield"
```

---

## Task 4: Visual verification + tuning

**Files:** none (verification); possibly re-tune constants in `scripts/TieredTerrain.gd` / `scripts/DualGrid.gd`.

- [ ] **Step 1: Render a ground-level screenshot**

```bash
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json
SHOT_OUT=/tmp/dg_ground.png SHOT_FRAMES=150 \
  xvfb-run -a godot --rendering-driver vulkan --resolution 1280x720 res://scenes/Field.tscn >/dev/null 2>&1
```
Read `/tmp/dg_ground.png`.

- [ ] **Step 2: Render an elevated overview**

Temporarily set `_cam_offset := Vector3(0.0, 58.0, 70.0)` and `_cam_look := Vector3(0.0, 0.0, 0.0)` in `scripts/Field.gd` (back up first: `cp scripts/Field.gd /tmp/Field.gd.bak`), render to `/tmp/dg_overview.png` (same command), Read it, then restore: `mv /tmp/Field.gd.bak scripts/Field.gd`.

- [ ] **Step 3: Judge against acceptance criteria**

Confirm in both shots:
- Biome borders are **organic transition bands**, not straight cell seams.
- **No z-fighting / flicker** between layers; **no holes**; overlays sit flush on the surface.
- Each overlay's tile picks look correct (no obviously wrong corner tile). If a
  corner combo is consistently wrong, fix that entry in `DualGrid.MASK_TO_TILE`
  (per the Task-1 preview notes) and re-render.

- [ ] **Step 4: Tune if needed**

- Transitions too coarse → set `CELL := 2.0` (4× tiles; still cheap) and re-render.
- Layer order wrong (e.g. sand should sit under rock) → reorder `OVERLAYS`.
- Overlay z-fighting on steep slopes → raise the per-layer `lift` factor (e.g. `0.04`).

- [ ] **Step 5: Run the dual-grid unit test once more**

Run: `godot --headless --script res://tests/test_dualgrid.gd`
Expected: `ALL DUALGRID TESTS PASSED`.

- [ ] **Step 6: Commit any tuning + push the whole feature**

```bash
git add -A
git commit -m "tune(field): dual-grid terrain layer order / cell size"
git push origin main
```
(Per the user's standing preference, push once the feature is complete.)

---

## Self-Review

**Spec coverage:**
- Grass base + 4 transparent overlays → Task 1 (assets), Task 3 (layers). ✓
- Dual-grid corner-mask selection → Task 2 (`DualGrid`), Task 3 (`_overlay_layer`). ✓
- Offset render grid → Task 3 Step 3 (centers grid). ✓
- Layer order + z-fight avoidance → Task 3 (`render_priority` + Y lift), Task 4 tuning. ✓
- Cliff/border preserved → Task 3 Step 2 (`span > CLIFF_SPAN` → cliff). ✓
- `height_at`/`biome_at` untouched → only `build()`/helpers change. ✓
- Verification via screenshots + unit test → Task 4, Task 2. ✓
- Meowa transparency risk + fallback → Task 1 Step 3. ✓
- Atlas-layout risk → Task 1 Step 3 documents it; Task 2 `MASK_TO_TILE` comment + Task 4 Step 3 fix path. ✓

**Placeholder scan:** `<chosen>` in Task 1 Step 4 is an explicit "replace with the real generated filename" instruction, resolved by the Step-3 preview inspection — not a code placeholder. No "TBD"/"handle edge cases"/etc.

**Type consistency:** `tile_index`/`tile_uv_rect`/`MASK_TO_TILE` names match between `DualGrid.gd`, the test, and `_overlay_layer`. `_add_quad`/`_normal_at`/`_vtx`/`_mat`/`CLIFF_SPAN` already exist in `TieredTerrain.gd` from the prior heightfield commit and are reused as-is. `OVERLAYS` shape (`biome`,`tex`) matches its use in `build()` and `_overlay_layer()`.
