# HD-2D Rendering Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise the existing Octopath-style slice to OCTOPATH-grade HD-2D by aligning sprite pixel density and extracting the inline render rig into shared, profile-parameterized factories, then tuning the grade.

**Architecture:** The slice already runs (Title→Field→Battle) with inline rigs in `Field.gd`/`Battle.gd`. We (M0) regenerate party sprites at OCTOPATH density (128px canvas, ~72px body, 36 px/world-unit), (M1) extract the env/light/camera/backdrop into `HD2DEnvironment.gd` + `HD2DStage.gd` parameterized by a `"field"`/`"battle"` profile **without changing either scene's look**, (M2) tune the profiles + add atmosphere layers, (M3) bring Battle into parity, (M4) verify the full flow.

**Tech Stack:** Godot 4.6 (Forward+, Vulkan), GDScript. Verification via headless GDScript assertions + `xvfb-run` screenshots through the existing `SHOT_OUT` hook in `SceneManager.gd`. Asset generation via the `game-assets` (Meowa) skill. Density audit via a committed Python/Pillow script.

**Reference spec:** `docs/superpowers/specs/2026-06-13-hd2d-rendering-foundation-design.md`

---

## File Structure

| File | Responsibility | M |
|---|---|---|
| `tools/audit_sprite_density.py` | Report canvas size, native pixel-block, content bbox, px/world-unit for sprites | M0 |
| `assets/sprites/{hero,mage,cleric,hunter}.png` | Party sprites, **regenerated** at standard | M0 |
| `assets/sprites/props/*.png`, `npc_*.png` | Re-sized to hit 36 px/unit (later sub-step) | M0 |
| `scripts/HD2DEnvironment.gd` | `environment(profile) -> Environment` (resource only) | M1 |
| `scripts/HD2DStage.gd` | `key_light/make_camera/apply_dof/backdrop` + (M2) `dust/accent_light/foreground_frame` | M1/M2 |
| `scripts/Field.gd` | consume factories; keep follow + gameplay | M1 |
| `scripts/Battle.gd` | consume factories; keep combat | M1 |
| `tests/test_hd2d_factories.gd` | Headless assertions that factory output == original values | M1 |
| `scripts/HD2D.gd` | unchanged API; optional density constant | — |

---

## Task 0: Prep — cache, audit tool, baselines

**Files:**
- Create: `tools/audit_sprite_density.py`
- Create: `tests/` (dir)

- [ ] **Step 1: Generate the Godot import/class cache (fixes CLI global-class lookups)**

Run:
```bash
cd /home/pc/hdd/develop/HD2D-template-meowa
xvfb-run -a ~/.local/bin/godot --path . --import --headless 2>&1 | tail -5
```
Expected: imports complete; `.godot/global_script_class_cache.cfg` now exists (`ls .godot/global_script_class_cache.cfg`).

- [ ] **Step 2: Write the density audit tool**

Create `tools/audit_sprite_density.py`:
```python
#!/usr/bin/env python3
"""Audit sprite pixel density. Usage: python3 tools/audit_sprite_density.py <png>..."""
import sys, os
from PIL import Image
import numpy as np

def native_block(im, maxf=16):
    a = np.asarray(im).astype(np.int32); w, h = im.size; best = 1
    for f in range(2, maxf + 1):
        if w % f or h % f:
            continue
        back = im.resize((w // f, h // f), Image.NEAREST).resize((w, h), Image.NEAREST)
        m = a[:, :, 3] > 16
        if m.sum() == 0:
            continue
        if np.abs(np.asarray(back).astype(np.int32) - a)[:, :, :3][m].mean() < 3.0:
            best = f
    return best

def content_bbox(im):
    a = np.asarray(im)
    ys, xs = np.where(a[:, :, 3] > 16)
    if len(xs) == 0:
        return (0, 0, im.size[0], im.size[1])
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)

for p in sys.argv[1:]:
    im = Image.open(p).convert("RGBA")
    w, h = im.size
    f = native_block(im)
    bb = content_bbox(im)
    bw, bh = bb[2] - bb[0], bb[3] - bb[1]
    print(f"{os.path.basename(p):22s} canvas {w}x{h}  native-block={f}  body {bw}x{bh}px")
```

- [ ] **Step 3: Baseline audit of current sprites**

Run:
```bash
python3 tools/audit_sprite_density.py assets/sprites/hero.png assets/sprites/props/barrel.png
```
Expected: `hero` native-block=1 body ~115x232; `barrel` native-block=1 64x64. (Confirms the too-dense / non-uniform starting point.)

- [ ] **Step 4: Capture pre-change visual baselines (Field + Battle)**

Run:
```bash
SHOT_OUT=/tmp/pre_field.png SHOT_FRAMES=120 xvfb-run -a ~/.local/bin/godot --path . --rendering-driver vulkan --scene res://scenes/Field.tscn >/tmp/g.log 2>&1; echo field=$?
SHOT_OUT=/tmp/pre_battle.png SHOT_FRAMES=120 xvfb-run -a ~/.local/bin/godot --path . --rendering-driver vulkan --scene res://scenes/Battle.tscn >>/tmp/g.log 2>&1; echo battle=$?
ls -la /tmp/pre_field.png /tmp/pre_battle.png
```
Expected: both exit 0, two 1280x720 PNGs. These are the look-of-record before any change.

- [ ] **Step 5: Commit the tool**

```bash
git add tools/audit_sprite_density.py
git commit -m "tools: sprite density audit script + prep cache"
```

---

## Task M0: Align party sprite density (128px / ~72px body / 36 px-unit)

> Art generation is interactive and credit-using via the `game-assets` skill. Each character is generate → audit → review → replace. This task documents the loop for ONE character; repeat for `hero`, `mage`, `cleric`, `hunter`.

**Files:**
- Modify: `assets/sprites/hero.png` (and mage/cleric/hunter)

- [ ] **Step 1: Generate a 128px party sprite via the game-assets skill**

Invoke the `game-assets` skill's pixel generation with a 128×128 canvas and a brief that keeps the character body ~72px tall (lower-center, feet near the bottom edge, transparent background, no internal upscaling). Subject text should match the existing character (e.g. hero = "young male wanderer, brown hair, blue tunic, leather armor, sword at hip, JRPG hero, full body, facing camera"). Save the chosen frame to a temp path, e.g. `/tmp/hero_128.png`.

- [ ] **Step 2: Audit the generated sprite**

Run:
```bash
python3 tools/audit_sprite_density.py /tmp/hero_128.png
```
Expected: `canvas 128x128  native-block=1  body WxH` with H in the 64–80 range. If H is far outside that, regenerate (Step 1) before continuing — do not resize.

- [ ] **Step 3: Visual review**

Read `/tmp/hero_128.png`. Confirm it reads as a chunky HD-2D pixel sprite (visible grain, clean alpha edges, consistent with the OCTOPATH look) and matches the character identity. If not, regenerate.

- [ ] **Step 4: Replace the asset**

```bash
cp /tmp/hero_128.png assets/sprites/hero.png
```
(Repeat Steps 1–4 for mage.png, cleric.png, hunter.png.)

- [ ] **Step 5: Re-import and verify density of all four**

```bash
xvfb-run -a ~/.local/bin/godot --path . --import --headless 2>&1 | tail -2
python3 tools/audit_sprite_density.py assets/sprites/hero.png assets/sprites/mage.png assets/sprites/cleric.png assets/sprites/hunter.png
```
Expected: all four `canvas 128x128 native-block=1`, body height 64–80px.

- [ ] **Step 6: Note the world-height implication**

In `Player.gd:26` the player is created with `HD2D.character(sprite_path, 2.4)`. With a 128px frame and ~72px body, on-screen density = 72 / (2.4 × 72/128 body-fraction)… i.e. body occupies ~2.4 × (72/128) ≈ 1.35u. To hit 36 px/unit for the body, keep `world_height = 2.4` (body 72px ÷ 1.35u ≈ 53/u for the *frame*; the **body** 72px over its ~1.35u span ≈ 53/u — acceptable starting point; final world-height is tuned in M2 against props). No code change required in M0; just record the chosen `world_height` baseline.

- [ ] **Step 7: Capture post-M0 baseline (the reference M1 must preserve)**

```bash
SHOT_OUT=/tmp/m0_field.png SHOT_FRAMES=120 xvfb-run -a ~/.local/bin/godot --path . --rendering-driver vulkan --scene res://scenes/Field.tscn >/tmp/g.log 2>&1; echo $?
cp /tmp/m0_field.png docs/superpowers/specs/2026-06-13-field-m0-baseline.png
```
Read `/tmp/m0_field.png`; confirm the new party sprite renders correctly in-world.

- [ ] **Step 8: Commit**

```bash
git add assets/sprites/hero.png assets/sprites/mage.png assets/sprites/cleric.png assets/sprites/hunter.png assets/sprites/*.import docs/superpowers/specs/2026-06-13-field-m0-baseline.png
git commit -m "art(M0): regenerate party sprites at OCTOPATH density (128px/~72px body)"
```

> **NPC/prop density sub-step (M0b, optional within M0):** repeat the generate→audit→replace loop for `npc_elder/merchant` (128px) and props (canvas sized so content ÷ world-height ≈ 36/u, e.g. a 1.2u barrel → ~48px canvas). This is a large batch; if deferred, record it as remaining work and proceed to M1 with party-only density. Enemies stay as placeholders (per spec).

---

## Task M1a: Create `HD2DEnvironment.gd` with failing test

**Files:**
- Create: `scripts/HD2DEnvironment.gd`
- Create: `tests/test_hd2d_factories.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/test_hd2d_factories.gd`:
```gdscript
extends SceneTree
## Headless assertions that the extracted factories emit exactly the original
## inline values. Run: godot --headless --script res://tests/test_hd2d_factories.gd
## Uses preload (not class_name) so it works without the global-class cache.

const Env := preload("res://scripts/HD2DEnvironment.gd")

var _fail := 0

func _eq(got, want, label: String) -> void:
	if typeof(got) == TYPE_COLOR or typeof(got) == TYPE_FLOAT:
		if not is_equal_approx(got if got is float else 0.0, want if want is float else 0.0) and not (got is Color and got.is_equal_approx(want)):
			if not (got is Color and got.is_equal_approx(want)):
				push_error("FAIL %s: got %s want %s" % [label, got, want]); _fail += 1; return
	elif got != want:
		push_error("FAIL %s: got %s want %s" % [label, got, want]); _fail += 1; return
	print("ok  %s = %s" % [label, got])

func _initialize() -> void:
	var f := Env.environment("field")
	_eq(f.background_mode, Environment.BG_SKY, "field.bg")
	_eq(f.tonemap_mode, Environment.TONE_MAPPER_FILMIC, "field.tonemap")
	_eq(f.glow_intensity, 0.45, "field.glow_intensity")
	_eq(f.glow_bloom, 0.18, "field.glow_bloom")
	_eq(f.glow_hdr_threshold, 0.95, "field.glow_hdr")
	_eq(f.fog_enabled, true, "field.fog")
	_eq(f.fog_density, 0.005, "field.fog_density")
	_eq(f.adjustment_saturation, 1.18, "field.saturation")

	var b := Env.environment("battle")
	_eq(b.background_mode, Environment.BG_COLOR, "battle.bg")
	_eq(b.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR, "battle.ambient_src")
	_eq(b.glow_intensity, 0.5, "battle.glow_intensity")
	_eq(b.adjustment_saturation, 1.12, "battle.saturation")
	_eq(b.fog_enabled, false, "battle.fog_off")

	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL (%d)" % _fail))
	quit(_fail)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xvfb-run -a ~/.local/bin/godot --path . --headless --script res://tests/test_hd2d_factories.gd 2>&1 | tail -10
```
Expected: FAIL — cannot preload `res://scripts/HD2DEnvironment.gd` (file does not exist yet).

- [ ] **Step 3: Implement `HD2DEnvironment.gd`**

Create `scripts/HD2DEnvironment.gd` (values copied verbatim from `Field.gd:45-79` and `Battle.gd:105-118`):
```gdscript
extends RefCounted
## Factory for the shared HD-2D Environment, parameterized by scene profile.
## Returns the Environment resource ONLY — the caller wraps it in a
## WorldEnvironment and adds it to the tree.

static func environment(profile: String = "field") -> Environment:
	var env := Environment.new()
	match profile:
		"battle":
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.04, 0.05, 0.08)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.7, 0.72, 0.8)
			env.ambient_light_energy = 1.1
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			env.glow_enabled = true
			env.glow_intensity = 0.5
			env.glow_bloom = 0.15
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
			env.adjustment_enabled = true
			env.adjustment_saturation = 1.12
			env.adjustment_contrast = 1.05
		_:
			env.background_mode = Environment.BG_SKY
			var sky := Sky.new()
			var psm := ProceduralSkyMaterial.new()
			psm.sky_top_color = Color(0.40, 0.6, 0.85)
			psm.sky_horizon_color = Color(0.86, 0.84, 0.74)
			psm.ground_horizon_color = Color(0.62, 0.72, 0.56)
			psm.ground_bottom_color = Color(0.5, 0.62, 0.42)
			psm.sun_angle_max = 30.0
			sky.sky_material = psm
			env.sky = sky
			env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			env.ambient_light_energy = 0.9
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			env.tonemap_exposure = 1.05
			env.glow_enabled = true
			env.glow_intensity = 0.45
			env.glow_bloom = 0.18
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
			env.glow_hdr_threshold = 0.95
			env.fog_enabled = true
			env.fog_light_color = Color(0.84, 0.86, 0.82)
			env.fog_density = 0.005
			env.fog_sky_affect = 0.0
			env.fog_aerial_perspective = 0.3
			env.adjustment_enabled = true
			env.adjustment_brightness = 1.02
			env.adjustment_contrast = 1.08
			env.adjustment_saturation = 1.18
	return env
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
xvfb-run -a ~/.local/bin/godot --path . --headless --script res://tests/test_hd2d_factories.gd 2>&1 | tail -20
```
Expected: all `ok` lines, `RESULT: PASS`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/HD2DEnvironment.gd tests/test_hd2d_factories.gd
git commit -m "feat(M1): HD2DEnvironment factory (field/battle profiles) + test"
```

---

## Task M1b: Create `HD2DStage.gd` (light, camera, DOF, backdrop)

**Files:**
- Create: `scripts/HD2DStage.gd`
- Modify: `tests/test_hd2d_factories.gd`

- [ ] **Step 1: Extend the test with light + camera assertions**

Add to `tests/test_hd2d_factories.gd` after the `const Env` line:
```gdscript
const Stage := preload("res://scripts/HD2DStage.gd")
```
And before the `RESULT` print in `_initialize()`:
```gdscript
	var fl := Stage.key_light("field")
	_eq(fl.shadow_enabled, true, "field.light.shadow")
	_eq(fl.light_energy, 1.15, "field.light.energy")
	_eq(fl.rotation_degrees, Vector3(-52, -130, 0), "field.light.rot")
	var bl := Stage.key_light("battle")
	_eq(bl.light_energy, 1.0, "battle.light.energy")
	_eq(bl.rotation_degrees, Vector3(-50, -120, 0), "battle.light.rot")

	var fc := Stage.make_camera("field")
	_eq(fc.fov, 46.0, "field.cam.fov")
	_eq((fc.attributes as CameraAttributesPractical).dof_blur_near_enabled, true, "field.cam.near_dof")
	_eq((fc.attributes as CameraAttributesPractical).dof_blur_amount, 0.08, "field.cam.dof_amount")
	var bc := Stage.make_camera("battle")
	_eq(bc.fov, 42.0, "battle.cam.fov")
	_eq((bc.attributes as CameraAttributesPractical).dof_blur_near_enabled, false, "battle.cam.no_near_dof")
	_eq((bc.attributes as CameraAttributesPractical).dof_blur_amount, 0.06, "battle.cam.dof_amount")
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
xvfb-run -a ~/.local/bin/godot --path . --headless --script res://tests/test_hd2d_factories.gd 2>&1 | tail -10
```
Expected: FAIL — cannot preload `res://scripts/HD2DStage.gd`.

- [ ] **Step 3: Implement `HD2DStage.gd`**

Create `scripts/HD2DStage.gd` (values from `Field.gd:84-91,278-292` and `Battle.gd:123-141,222-234`):
```gdscript
extends RefCounted
## Shared HD-2D rig pieces, parameterized by scene profile. Construction only —
## no follow/update logic (that stays in the scene).

static func key_light(profile: String = "field") -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	match profile:
		"battle":
			sun.light_color = Color(1.0, 0.93, 0.8)
			sun.light_energy = 1.0
			sun.rotation_degrees = Vector3(-50, -120, 0)
		_:
			sun.light_color = Color(1.0, 0.94, 0.82)
			sun.light_energy = 1.15
			sun.shadow_enabled = true
			sun.shadow_bias = 0.04
			sun.rotation_degrees = Vector3(-52, -130, 0)
	return sun

static func make_camera(profile: String = "field") -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 42.0 if profile == "battle" else 46.0
	apply_dof(cam, profile)
	return cam

static func apply_dof(cam: Camera3D, profile: String = "field") -> void:
	var attr := CameraAttributesPractical.new()
	match profile:
		"battle":
			attr.dof_blur_far_enabled = true
			attr.dof_blur_far_distance = 19.0
			attr.dof_blur_far_transition = 6.0
			attr.dof_blur_amount = 0.06
		_:
			attr.dof_blur_far_enabled = true
			attr.dof_blur_far_distance = 24.0
			attr.dof_blur_far_transition = 8.0
			attr.dof_blur_near_enabled = true
			attr.dof_blur_near_distance = 6.0
			attr.dof_blur_near_transition = 3.0
			attr.dof_blur_amount = 0.08
	cam.attributes = attr

static func backdrop(tex_path: String, size: Vector2, pos: Vector3) -> MeshInstance3D:
	var bg := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	bg.mesh = qm
	var bmat := StandardMaterial3D.new()
	if ResourceLoader.exists(tex_path):
		bmat.albedo_texture = load(tex_path)
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	bg.mesh.material = bmat
	bg.position = pos
	return bg
```

- [ ] **Step 4: Run to verify it passes**

Run:
```bash
xvfb-run -a ~/.local/bin/godot --path . --headless --script res://tests/test_hd2d_factories.gd 2>&1 | tail -25
```
Expected: `RESULT: PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/HD2DStage.gd tests/test_hd2d_factories.gd
git commit -m "feat(M1): HD2DStage factory (light/camera/dof/backdrop) + tests"
```

---

## Task M1c: Route `Field.gd` through the factories (no visual change)

**Files:**
- Modify: `scripts/Field.gd`

- [ ] **Step 1: Add preload consts at the top of `Field.gd`**

After line 4 (the header comment block), add:
```gdscript
const HD2DEnvironment := preload("res://scripts/HD2DEnvironment.gd")
const HD2DStage := preload("res://scripts/HD2DStage.gd")
```

- [ ] **Step 2: Replace `_build_environment()` (lines 45-82) body**

Replace the entire function with:
```gdscript
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	we.environment = HD2DEnvironment.environment("field")
	add_child(we)
```

- [ ] **Step 3: Replace `_build_light()` (lines 84-91) body**

```gdscript
func _build_light() -> void:
	add_child(HD2DStage.key_light("field"))
```

- [ ] **Step 4: Replace `_build_camera()` (lines 278-293) body, keeping placement**

```gdscript
func _build_camera() -> void:
	_cam = HD2DStage.make_camera("field")
	add_child(_cam)
	_cam.global_position = _player.position + _cam_offset
	_cam.look_at(_player.position + _cam_look, Vector3.UP)
	_cam.make_current()
```
(The follow lerp in `_process` at lines 345-351 is untouched.)

- [ ] **Step 5: Parse check + factory test still pass**

Run:
```bash
xvfb-run -a ~/.local/bin/godot --path . --headless --script res://tests/test_hd2d_factories.gd 2>&1 | tail -3
xvfb-run -a ~/.local/bin/godot --path . --import --headless 2>&1 | grep -i error | tail -5 || echo "no import errors"
```
Expected: `RESULT: PASS`; no parse/import errors mentioning Field.gd.

- [ ] **Step 6: Visual regression check vs post-M0 baseline**

Run:
```bash
SHOT_OUT=/tmp/m1_field.png SHOT_FRAMES=120 xvfb-run -a ~/.local/bin/godot --path . --rendering-driver vulkan --scene res://scenes/Field.tscn >/tmp/g.log 2>&1; echo $?
```
Read `/tmp/m1_field.png` and compare to `docs/superpowers/specs/2026-06-13-field-m0-baseline.png`. Expected: same grade/lighting/DOF (tree positions differ due to `randomize()` — that is fine; the environment, fog, glow, camera framing must look identical).

- [ ] **Step 7: Commit**

```bash
git add scripts/Field.gd
git commit -m "refactor(M1): Field consumes HD2DEnvironment/HD2DStage (no visual change)"
```

---

## Task M1d: Route `Battle.gd` through the factories (no visual change)

**Files:**
- Modify: `scripts/Battle.gd`

- [ ] **Step 1: Add preload consts near the top of `Battle.gd`**

After the file's header/`extends` block, add:
```gdscript
const HD2DEnvironment := preload("res://scripts/HD2DEnvironment.gd")
const HD2DStage := preload("res://scripts/HD2DStage.gd")
```

- [ ] **Step 2: Replace the env + sun + backdrop blocks in `_build_world()` (lines 105-141)**

Replace lines 105-141 (the `Environment.new()`…`add_child(bg)` span) with:
```gdscript
	var we := WorldEnvironment.new()
	we.environment = HD2DEnvironment.environment("battle")
	add_child(we)

	add_child(HD2DStage.key_light("battle"))

	# Painted backdrop quad far behind the fighters (gets DoF bokeh).
	add_child(HD2DStage.backdrop("res://assets/textures/battle_bg.jpg", Vector2(46, 26), Vector3(0, 9, -16)))
```
(Leave the ground block at lines 143-147 intact.)

- [ ] **Step 3: Replace `_build_camera()` (lines 222-234), keeping placement**

```gdscript
func _build_camera() -> void:
	_cam = HD2DStage.make_camera("battle")
	add_child(_cam)
	_cam.position = Vector3(0, 6.4, 13.5)
	_cam.look_at(Vector3(0, 2.4, -2), Vector3.UP)
	_cam.make_current()
```

- [ ] **Step 4: Parse check**

Run:
```bash
xvfb-run -a ~/.local/bin/godot --path . --import --headless 2>&1 | grep -i error | tail -5 || echo "no import errors"
```
Expected: no errors mentioning Battle.gd.

- [ ] **Step 5: Visual regression check vs pre-change battle baseline**

Run:
```bash
SHOT_OUT=/tmp/m1_battle.png SHOT_FRAMES=120 xvfb-run -a ~/.local/bin/godot --path . --rendering-driver vulkan --scene res://scenes/Battle.tscn >/tmp/g.log 2>&1; echo $?
```
Read `/tmp/m1_battle.png` and compare to `/tmp/pre_battle.png` (Task 0). Expected: identical backdrop, lighting, camera, DOF (party sprites now denser from M0 — that change is expected; the rig must be unchanged).

- [ ] **Step 6: Commit**

```bash
git add scripts/Battle.gd
git commit -m "refactor(M1): Battle consumes shared rig + backdrop (no rig change)"
```

---

## Task M2: Elevate the grade (tune profiles + atmosphere layers)

> Tuning is iterative-by-screenshot; exact final numbers are discovered, not pre-set. Each sub-step: change one thing in the **profile** (or add one layer), screenshot Field, read it, keep or revert. Commit when a visible improvement lands. Reference: OCTOPATH frames (strong tilt-shift, flatter telephoto, bloomy, dust, layered depth).

**Files:**
- Modify: `scripts/HD2DStage.gd` (add `dust`, `accent_light`, `foreground_frame`)
- Modify: `scripts/HD2DEnvironment.gd` (field profile tuning)
- Modify: `scripts/Field.gd` (instantiate new layers)

- [ ] **Step 1: Add `dust()` to `HD2DStage.gd`**

Append:
```gdscript
static func dust(area_size: float = 40.0, amount: int = 220) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.randomness = 1.0
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(area_size * 0.5, 4.0, area_size * 0.5)
	mat.gravity = Vector3(0, -0.05, 0)
	mat.initial_velocity_min = 0.05
	mat.initial_velocity_max = 0.25
	mat.scale_min = 0.01
	mat.scale_max = 0.04
	var draw := QuadMesh.new()
	draw.size = Vector2(0.06, 0.06)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color = Color(1, 0.97, 0.85, 0.5)
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw.material = dmat
	p.draw_pass_1 = draw
	p.process_material = mat
	p.position = Vector3(0, 3, 0)
	return p
```

- [ ] **Step 2: Add `accent_light()` and `foreground_frame()` to `HD2DStage.gd`**

Append:
```gdscript
static func accent_light(color: Color, energy: float, pos: Vector3, rng: float = 9.0) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.light_color = color
	o.light_energy = energy
	o.omni_range = rng
	o.position = pos
	return o

# A pair of out-of-focus near-camera bushes that frame the shot (DOF blurs them).
static func foreground_frame(tex_path: String, cam_pos: Vector3) -> Node3D:
	var root := Node3D.new()
	for sx in [-1.0, 1.0]:
		var s := Sprite3D.new()
		if ResourceLoader.exists(tex_path):
			s.texture = load(tex_path)
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.pixel_size = 0.02
		s.position = cam_pos + Vector3(sx * 4.5, -1.5, -4.0)
		root.add_child(s)
	return root
```

- [ ] **Step 3: Instantiate dust + accent in `Field.gd._ready()`**

Add to `_ready()` after `_build_camera()`:
```gdscript
	add_child(HD2DStage.dust(GROUND_SIZE))
	add_child(HD2DStage.accent_light(Color(1.0, 0.85, 0.5), 4.0, Vector3(-6.5, 2.5, 9.0)))
```
Run the Field screenshot; read it; confirm dust motes + a warm pool near the lamp are visible. Commit: `feat(M2): atmosphere — dust motes + accent light`.

- [ ] **Step 4: Tune the field profile toward OCTOPATH (iterate)**

In `HD2DEnvironment.environment("field")` and `HD2DStage.make_camera("field")`, iterate these one at a time, screenshotting after each (keep if better, revert if worse):
- Camera FOV 46 → try 32 (telephoto compression). Field follow offset `_cam_offset`/`_cam_look` in `Field.gd:12-13` may need to move further back to keep framing — adjust together.
- `dof_blur_amount` 0.08 → try 0.12–0.16 (stronger miniature blur).
- `glow_intensity` 0.45 → try 0.6–0.8; `glow_bloom` 0.18 → 0.25.
- `adjustment_saturation` 1.18 → try 1.25.
- `fog_aerial_perspective` 0.3 → try 0.5.

After each change: `SHOT_OUT=/tmp/m2.png … --scene res://scenes/Field.tscn`, read `/tmp/m2.png`, compare against the OCTOPATH target. Commit each kept improvement with a message naming the change and value.

- [ ] **Step 5: Reconcile sprite shading**

Decide policy (per spec Open Question): keep characters unlit-but-graded; for props, confirm `shaded=true` looks right under the new lighting or switch to false. Apply in `Field.gd._add_billboard_prop` (line 185) consistently. Screenshot, commit.

- [ ] **Step 6: Optional foreground frame**

If depth still reads flat, add in `_ready()`:
```gdscript
	add_child(HD2DStage.foreground_frame("res://assets/sprites/props/bush.png", _cam_offset))
```
Screenshot; keep only if it improves framing without obscuring gameplay. Commit or revert.

---

## Task M3: Battle parity

**Files:**
- Modify: `scripts/HD2DStage.gd` (battle profile only) and/or `scripts/Battle.gd` placement

- [ ] **Step 1: Screenshot battle under the shared rig**

```bash
SHOT_OUT=/tmp/m3_battle.png SHOT_FRAMES=120 xvfb-run -a ~/.local/bin/godot --path . --rendering-driver vulkan --scene res://scenes/Battle.tscn >/tmp/g.log 2>&1
```
Read it. Identify only what reads inconsistently with the elevated Field look (e.g. camera too flat/close, backdrop bokeh).

- [ ] **Step 2: Adjust ONLY the battle profile / battle placement**

Tune the `"battle"` branch of `make_camera`/`apply_dof` (fov, far DOF distance/transition) and/or `Battle._build_camera` position. Do **not** edit the field profile or the shared grade. Confirm placeholder enemies don't look jarring; if they clash badly, note it for the future enemy-art spec rather than fixing art here.

- [ ] **Step 3: Screenshot, keep improvements, commit**

```bash
git add scripts/HD2DStage.gd scripts/Battle.gd
git commit -m "tune(M3): battle profile parity with elevated field grade"
```

---

## Task M4: Full-flow verification + document final values

- [ ] **Step 1: Boot each scene under xvfb**

```bash
for S in Title Field Battle; do
  SHOT_OUT=/tmp/flow_$S.png SHOT_FRAMES=90 xvfb-run -a ~/.local/bin/godot --path . --rendering-driver vulkan --scene res://scenes/$S.tscn >/tmp/g_$S.log 2>&1
  echo "$S exit=$? ; errors:"; grep -iE "error|script" /tmp/g_$S.log | grep -vi "still in use\|leaked" | tail -3
done
ls -la /tmp/flow_*.png
```
Expected: all three exit 0, three PNGs, no script/parse errors.

- [ ] **Step 2: Visual sign-off**

Read `/tmp/flow_Field.png` and `/tmp/flow_Battle.png`. Confirm both read as OCTOPATH-grade HD-2D and are stylistically consistent. Read `/tmp/flow_Title.png` to confirm the title still boots.

- [ ] **Step 3: Record the final tuned values in the spec**

In `docs/superpowers/specs/2026-06-13-hd2d-rendering-foundation-design.md`, append a "Final tuned values (M4)" section listing the locked field/battle profile numbers (FOV, DOF, glow, fog, saturation, accent light) and the chosen party `world_height` / density.

- [ ] **Step 4: Commit + finish**

```bash
git add docs/superpowers/specs/2026-06-13-hd2d-rendering-foundation-design.md
git commit -m "docs(M4): record final tuned HD-2D profile values; full-flow verified"
```
Then invoke `superpowers:finishing-a-development-branch` to decide integration.

---

## Self-Review Notes

- **Spec coverage:** asset density (M0), rig extraction as profile factories with `environment()` returning a resource and no follow logic in the camera factory (M1a–d), Battle backdrop migration (M1d), grade elevation + atmosphere + shading reconcile (M2), battle-profile-only parity (M3), full-flow run + xvfb + `--scene` + `SHOT_OUT` verification throughout, CLI cache via `--import` + preload (Task 0 / M1 preload consts). Enemies deferred (noted in M0b/M3) per spec.
- **Determinism caveat:** Field uses `randomize()`, so M1 visual checks are look-comparison not pixel-diff; the deterministic guarantee for the refactor is the headless factory-value test (M1a/M1b).
- **Type consistency:** factory names `HD2DEnvironment.environment`, `HD2DStage.key_light/make_camera/apply_dof/backdrop/dust/accent_light/foreground_frame` used identically in tests and consumers.
