# Procedural Noise Terrain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the five hand-placed biome regions and the low-amplitude sine heightfield with a fully procedural, fixed-seed noise world (elevation + moisture) so biomes interleave organically and relief is varied but walkable.

**Architecture:** Two cached static `FastNoiseLite` fields (fixed seeds) drive `height_at` (FBM + domain warp) and biome selection (`biome_at` from elevation + moisture). Water becomes one large plane at `WATER_LEVEL`; basins read as water. The grass blanket and a relocated treasure chest follow the procedural surface. The dual-grid overlay rendering is unchanged.

**Tech Stack:** Godot 4.6 GDScript (`FastNoiseLite`, `static var`), the existing dual-grid overlay system, headless `xvfb`+lavapipe screenshots, SceneTree assertion tests.

**Spec:** `docs/superpowers/specs/2026-06-14-procedural-terrain-design.md`

---

## File Structure

- **Modify `scripts/TieredTerrain.gd`** — add cached noise statics + tuning consts; rewrite
  `height_at` and `biome_at`; rewrite `water()` to a map-spanning plane; add
  `highest_walkable()` helper; drop `PLATEAU`/`PLATEAU_Y`/`LAKE_Y`/`LAKE`.
- **Modify `shaders/grass_blade.gdshader`** — add a `water_level` uniform and kill blades on
  underwater cells (reuse the existing heightmap sample + `v_kill`).
- **Modify `scripts/GrassField.gd`** — pass `water_level`; keep the heightmap bake (auto-uses
  the new `height_at`).
- **Modify `scripts/Field.gd`** — grass-blanket call (drop `LAKE` pond arg), chest→peak,
  generic signpost text.
- **Create `tests/test_terrain.gd`** — SceneTree assertions: determinism, height range,
  water + highland present, biome variety, mostly-walkable.

Biome ids (unchanged): `0 grass, 1 flower, 2 forest, 3 rock, 4 sand`.

---

## Task 1: Noise-driven `height_at` + `biome_at` (TDD)

**Files:**
- Modify: `scripts/TieredTerrain.gd`
- Test: `tests/test_terrain.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/test_terrain.gd`:
```gdscript
extends SceneTree
## Assertions for the procedural terrain generators.
## Run: godot --headless --script res://tests/test_terrain.gd
const T := preload("res://scripts/TieredTerrain.gd")

var _fail := 0
func _ok(cond: bool, label: String) -> void:
	if cond: print("ok  %s" % label)
	else:
		push_error("FAIL %s" % label); _fail += 1

func _initialize() -> void:
	# Pure + deterministic (fixed seed)
	_ok(T.height_at(3.0, 7.0) == T.height_at(3.0, 7.0), "height deterministic")
	_ok(T.biome_at(3.0, 7.0) == T.biome_at(3.0, 7.0), "biome deterministic")
	# Border ring is the tall world cliff
	_ok(is_equal_approx(T.height_at(70.0, 0.0), 16.0), "border cliff = 16")

	var minh := 1e9; var maxh := -1e9
	var below := 0; var high := 0; var steep := 0; var cells := 0
	var biomes := {}
	for ix in range(-60, 61, 3):
		for iz in range(-60, 61, 3):
			var x := float(ix); var z := float(iz)
			var h := T.height_at(x, z)
			minh = minf(minh, h); maxh = maxf(maxh, h)
			if h < T.WATER_LEVEL: below += 1
			if h >= 4.8: high += 1
			biomes[T.biome_at(x, z)] = true
			var hx := T.height_at(x + 2.0, z)   # gradient over one CELL (2.0)
			cells += 1
			if absf(hx - h) > T.CLIFF_SPAN: steep += 1
	_ok(below > 0, "has water basins (below WATER_LEVEL)")
	_ok(high > 0, "has highland (>=4.8)")
	_ok(biomes.size() >= 4, "biome variety >= 4 (got %d)" % biomes.size())
	_ok(minh > -6.0 and maxh < 12.0, "interior height in sane range [%.1f,%.1f]" % [minh, maxh])
	_ok(float(steep) / float(cells) < 0.15, "mostly walkable, steep frac=%.2f" % (float(steep)/float(cells)))
	if _fail == 0: print("ALL TERRAIN TESTS PASSED")
	quit(1 if _fail > 0 else 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --script res://tests/test_terrain.gd`
Expected: FAILs (old `height_at` has no basins below water / no real highland / 5-blob biomes may still pass variety, but `has water basins` fails since the old lake is the only sub-water area and is sparse at step 3). At minimum it is not yet the new generator.

- [ ] **Step 3: Add noise statics + tuning consts**

In `scripts/TieredTerrain.gd`, replace the region-anchor block:
```gdscript
# Region anchors.
const PLATEAU := Vector2(42.0, -40.0)   # rocky highland centre
const LAKE := Vector2(-46.0, 10.0)      # lake centre
const LAKE_Y := -2.0
const WATER_LEVEL := -0.45              # player can't walk below this (into water)
const PLATEAU_Y := 6.5
```
with:
```gdscript
const WATER_LEVEL := -0.45              # player can't walk below this (into water)

# Procedural world (fixed seed → one repeatable, tunable map).
const SEED_H := 1337
const SEED_M := 4242
const H_MIN := -2.5                     # deepest basin floor
const H_MAX := 8.0                      # highest peak (pre-border)
const SHORE := 0.7                      # sand band height above water
const HIGHLAND_Y := 4.8                 # rock above this elevation
static var _noise_h: FastNoiseLite
static var _noise_m: FastNoiseLite

static func _ensure_noise() -> void:
	if _noise_h != null:
		return
	_noise_h = FastNoiseLite.new()
	_noise_h.seed = SEED_H
	_noise_h.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_h.frequency = 0.012
	_noise_h.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_h.fractal_octaves = 4
	_noise_h.domain_warp_enabled = true
	_noise_h.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	_noise_h.domain_warp_amplitude = 30.0
	_noise_h.domain_warp_frequency = 0.01
	_noise_m = FastNoiseLite.new()
	_noise_m.seed = SEED_M
	_noise_m.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_m.frequency = 0.02
	_noise_m.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_m.fractal_octaves = 3
```

- [ ] **Step 4: Rewrite `height_at` and `biome_at`**

Replace the existing `height_at` and `biome_at` bodies with:
```gdscript
static func height_at(x: float, z: float) -> float:
	var edge: float = maxf(absf(x), absf(z))
	if edge > 66.0:
		return 16.0                                   # tall border cliffs
	_ensure_noise()
	var e := _noise_h.get_noise_2d(x, z)              # [-1,1], domain-warped
	return lerpf(H_MIN, H_MAX, (e + 1.0) * 0.5)

static func biome_at(x: float, z: float) -> int:
	var e := height_at(x, z)
	if e <= WATER_LEVEL + SHORE:
		return 4                                      # sand shore around water
	if e >= HIGHLAND_Y:
		return 3                                      # rocky highland
	_ensure_noise()
	var m := _noise_m.get_noise_2d(x, z)
	if m > 0.25:
		return 2                                      # forest (wet)
	if m < -0.25:
		return 1                                      # flower meadow (dry band)
	return 0                                          # grassland
```

- [ ] **Step 5: Run test; tune constants until it passes**

Run: `godot --headless --script res://tests/test_terrain.gd`
Expected: `ALL TERRAIN TESTS PASSED`. If `mostly walkable` fails (too steep), lower
`_noise_h.domain_warp_amplitude` (e.g. 30→18) and/or `H_MAX` (8→6.5). If `has highland`
fails, raise `H_MAX` or lower `HIGHLAND_Y`. If `has water basins` fails, lower `H_MIN`
(−2.5→−3.5). Re-run until green.

- [ ] **Step 6: Commit**

```bash
git add scripts/TieredTerrain.gd tests/test_terrain.gd
git commit -m "feat(field): procedural noise heightfield + elevation/moisture biomes"
```

---

## Task 2: Map-spanning water + underwater grass exclusion

**Files:**
- Modify: `shaders/grass_blade.gdshader`
- Modify: `scripts/GrassField.gd`
- Modify: `scripts/TieredTerrain.gd` (`water()`, drop `LAKE`)
- Modify: `scripts/Field.gd` (grass call)

- [ ] **Step 1: Add `water_level` kill to the grass shader**

In `shaders/grass_blade.gdshader`, add after the `pond_radius` uniform (line ~15):
```glsl
uniform float water_level = -9999.0;  // kill blades on cells at/below this terrain height
```
Then in `vertex()`, replace the two lines that lift the blade and set `v_kill`:
```glsl
	// lift the blade onto the terrain surface
	VERTEX.y += texture(heightmap, (wpos.xz - hm_min) / hm_size).r;
```
and
```glsl
	v_kill = distance(wpos.xz, pond_center) < pond_radius ? 1.0 : 0.0;  // no grass in the pond
```
with:
```glsl
	// lift the blade onto the terrain surface
	float th = texture(heightmap, (wpos.xz - hm_min) / hm_size).r;
	VERTEX.y += th;
```
and
```glsl
	// kill grass in ponds (legacy) or anywhere underwater
	v_kill = (distance(wpos.xz, pond_center) < pond_radius || th <= water_level) ? 1.0 : 0.0;
```

- [ ] **Step 2: Pass `water_level` from `GrassField`**

In `scripts/GrassField.gd`, after the `pond_radius` shader parameter line (~51) add:
```gdscript
	smat.set_shader_parameter("water_level", TieredTerrain.WATER_LEVEL)
```

- [ ] **Step 3: Rewrite `water()` to a map-spanning plane; drop `LAKE`**

In `scripts/TieredTerrain.gd`, replace the body of `water()`:
```gdscript
static func water() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(132.0, 132.0)        # spans the playable area; basins read as water
	pm.subdivide_width = 48
	pm.subdivide_depth = 48
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	pm.material = mat
	mi.position = Vector3(0.0, WATER_LEVEL, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var ws = (ml as SceneTree).root.get_node_or_null("WeatherSystem")
		if ws != null:
			ws.register(mat)
	return mi
```
(The `LAKE` constant was removed in Task 1's edit; this removes its last use in `water()`.)

- [ ] **Step 4: Update the grass-blanket call in `Field`**

In `scripts/Field.gd` `_ready`, replace:
```gdscript
	add_child(GrassField.build(150.0, 46000, 0.9, TieredTerrain.LAKE, 20.0))  # grass blanket (excludes the lake)
```
with:
```gdscript
	add_child(GrassField.build(150.0, 46000, 0.9))  # grass blanket; underwater cells excluded via water_level
```

- [ ] **Step 5: Verify it loads headless without errors**

Run: `godot --headless --quit-after 120 res://scenes/Field.tscn 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Nonexistent|Invalid" | grep -ivE "resources still in use|leaked"`
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add shaders/grass_blade.gdshader scripts/GrassField.gd scripts/TieredTerrain.gd scripts/Field.gd
git commit -m "feat(field): map-spanning water plane + underwater grass exclusion"
```

---

## Task 3: Procedural landmark placement

**Files:**
- Modify: `scripts/TieredTerrain.gd` (add `highest_walkable()`)
- Modify: `scripts/Field.gd` (chest→peak, signpost text)

- [ ] **Step 1: Add a peak-finder helper**

Add to `scripts/TieredTerrain.gd` (helpers section):
```gdscript
# Coarse scan for the highest interior point that is not a border-cliff cell —
# used to place a landmark (treasure) on the procedural highland.
static func highest_walkable(half: float = 60.0) -> Vector3:
	var best := Vector3(0.0, -1e9, 0.0)
	var step := 4.0
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			if maxf(absf(x), absf(z)) <= 62.0:
				var h := height_at(x, z)
				if h > best.y:
					best = Vector3(x, h, z)
			z += step
		x += step
	return best
```

- [ ] **Step 2: Place the chest at the peak + genericize the signpost**

In `scripts/Field.gd` `_spawn_props`, replace the signpost interactable block's lines and the chest placement. Replace:
```gdscript
	var sign_node := _add_billboard_prop("res://assets/sprites/props/signpost.png", Vector3(4, 0, 18), 1.8, true)
	_interactables.append({
		"pos": sign_node.global_position, "prompt": "Read", "name": "Signpost",
		"lines": ["  ↑ Mistral Forest      Highcrag Plateau →", "  ← Still Lake", "Beasts roam the wilds. Step carefully."],
	})
	# Reward chest hidden atop the highland plateau — walk up to reach it.
	var chest_node := _add_billboard_prop("res://assets/sprites/props/chest.png", Vector3(42, 0, -40), 1.3, true)
```
with:
```gdscript
	var sign_node := _add_billboard_prop("res://assets/sprites/props/signpost.png", Vector3(4, 0, 18), 1.8, true)
	_interactables.append({
		"pos": sign_node.global_position, "prompt": "Read", "name": "Signpost",
		"lines": ["The wilds stretch out in every direction.", "Climb high — treasure waits at the summit.", "Beasts roam the grass. Step carefully."],
	})
	# Reward chest on the procedural highland summit — walk up to reach it.
	var peak := TieredTerrain.highest_walkable()
	var chest_node := _add_billboard_prop("res://assets/sprites/props/chest.png", Vector3(peak.x, 0, peak.z), 1.3, true)
```

- [ ] **Step 2b: Confirm no remaining `LAKE`/`PLATEAU` references**

Run: `grep -rn "TieredTerrain.LAKE\|TieredTerrain.PLATEAU\|\.LAKE_Y\|\.PLATEAU_Y" scripts/`
Expected: no output. (If any remain, they are stale reads of removed consts — fix them.)

- [ ] **Step 3: Verify headless load**

Run: `godot --headless --quit-after 120 res://scenes/Field.tscn 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Nonexistent|Invalid" | grep -ivE "resources still in use|leaked"`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add scripts/TieredTerrain.gd scripts/Field.gd
git commit -m "feat(field): procedural landmark placement (chest at noise peak) + generic signpost"
```

---

## Task 4: Visual verification + tuning + push

**Files:** none (verification); possibly re-tune noise consts in `scripts/TieredTerrain.gd`.

- [ ] **Step 1: Clean top-down map view**

Back up Field, set a high top-down camera with DOF+fog off, render, restore:
```bash
cp scripts/Field.gd /tmp/Field.gd.bak
sed -i 's/var _cam_offset := Vector3(0.0, 11.5, 24.0).*/var _cam_offset := Vector3(0.0, 110.0, 0.01)/' scripts/Field.gd
sed -i 's/var _cam_look := Vector3(0.0, 3.5, 0.0)/var _cam_look := Vector3(0.0, 0.0, 0.0)/' scripts/Field.gd
sed -i 's/\t_cam = HD2DStage.make_camera("field")/\t_cam = HD2DStage.make_camera("field")\n\t_cam.attributes = null/' scripts/Field.gd
sed -i 's/\t_env = HD2DEnvironment.environment("field")/\t_env = HD2DEnvironment.environment("field")\n\t_env.fog_enabled = false/' scripts/Field.gd
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json
SHOT_OUT=/tmp/pt_topdown.png SHOT_FRAMES=150 xvfb-run -a godot --rendering-driver vulkan --resolution 1280x720 res://scenes/Field.tscn >/dev/null 2>&1
mv /tmp/Field.gd.bak scripts/Field.gd
```
Read `/tmp/pt_topdown.png`. Confirm: biomes interleave with scattered patches (not 5 blobs), 1–2 water basins, organic dual-grid borders.

- [ ] **Step 2: Gameplay + walk shots**

Render the normal gameplay view (`SHOT_OUT=/tmp/pt_gameplay.png`, no edits). Then a shot from a basin edge to check water/sand + walkability: temporarily `sed -i 's/\tvar start := Vector3(0, 0, 22)/\tvar start := Vector3(<bx>, 0, <bz>)/'` where `(<bx>,<bz>)` is a basin-edge spot read off the top-down, render `/tmp/pt_basin.png`, restore. Confirm: varied relief, no holes, no overlay z-fighting, grass stops at the waterline.

- [ ] **Step 3: Confirm spawn is safe**

Run:
```bash
godot --headless --script res://tests/test_terrain.gd 2>&1 | grep -iE "PASSED|FAIL"
python3 -c "print('spawn check: run game, ensure (0,22) above water')"
```
Then verify in `/tmp/pt_gameplay.png` the hero stands on dry walkable ground. If the spawn is underwater/on a cliff for this seed, change `SEED_H`/`SEED_M` (Task 1) and re-run from Task 1 Step 5, or nudge the spawn in `Field.gd`.

- [ ] **Step 4: Tune for "moderate rolling hills, a couple rocky rises, 1–2 basins"**

If too flat → raise `H_MAX` / `_noise_h.fractal_octaves`. Too spiky/steep → lower
`domain_warp_amplitude` / `H_MAX`. Too many lakes → raise `H_MIN` toward −1.5. Too many
rocky rises → raise `HIGHLAND_Y`. Re-render Step 1 until it reads right; re-run the terrain
test after any const change.

- [ ] **Step 5: Final test sweep + commit + push**

```bash
godot --headless --script res://tests/test_terrain.gd 2>&1 | grep -iE "PASSED|FAIL"
godot --headless --script res://tests/test_dualgrid.gd 2>&1 | grep -iE "PASSED|FAIL"
git add -A
git commit -m "tune(field): procedural terrain noise constants"
git push origin main
```
Expected: both `ALL ... TESTS PASSED`; push succeeds. (Per the user's standing preference, push when the feature is complete.)

---

## Self-Review

**Spec coverage:**
- Noise heightfield (FBM + domain warp, walkable, border ring) → Task 1 Steps 3–5. ✓
- Elevation+moisture biome model → Task 1 Step 4. ✓
- Map-spanning water plane at WATER_LEVEL → Task 2 Step 3. ✓
- Grass underwater exclusion → Task 2 Steps 1–2. ✓
- Monster/player gating unchanged (WATER_LEVEL) → no task needed (verified by load + shots). ✓
- Chest at procedural peak + generic signpost → Task 3. ✓
- Determinism (static cached noise, fixed seed) → Task 1 Step 3; asserted in test. ✓
- Drop PLATEAU/LAKE/LAKE_Y/PLATEAU_Y → Task 1 Step 3 (removes block) + Task 2 Step 3 + Task 3 Step 2b grep. ✓
- Verification (top-down, gameplay, basin, tests, spawn safety) → Task 4. ✓
- Risks (walkability, grass under water, spawn safety) → test `mostly walkable`, Task 2 Step 1, Task 4 Step 3. ✓

**Placeholder scan:** `<bx>,<bz>` in Task 4 Step 2 is an explicit "read a basin-edge coordinate off the top-down image" instruction (a value produced by Step 1), not an unfilled code placeholder. All code steps show complete code. No "TBD"/"handle edge cases".

**Type consistency:** `_ensure_noise`, `_noise_h`, `_noise_m`, `WATER_LEVEL`, `CLIFF_SPAN`,
`H_MIN/H_MAX/SHORE/HIGHLAND_Y`, `highest_walkable()` are defined in Task 1/Task 3 and used
consistently. The test references `T.WATER_LEVEL` and `T.CLIFF_SPAN` (both existing/defined).
Grass shader uniform `water_level` set in `GrassField` matches the uniform name. `biome_at`
returns ids matching `OVERLAYS`/`TEX` (unchanged from prior work).
