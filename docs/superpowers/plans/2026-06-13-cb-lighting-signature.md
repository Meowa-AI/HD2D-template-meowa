# CB Lighting Signature + Lit Sprites Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or subagent-driven-development. Steps use checkbox (`- [ ]`). This plan is largely iterative screenshot tuning, best executed inline (controller reads the screenshots).

**Goal:** Re-grade the field & battle profiles toward Cassette Beasts' cool, indigo-shadowed, 1.16-saturation mood and light the character billboards, on the existing rig.

**Architecture:** Values + two-call-site change on `HD2DEnvironment.gd` / `HD2DStage.gd` / `Player.gd` / `Battle.gd`, guarded by the factory value-test. Indigo shadows come from a lilac ambient (GD4 has no `shadow_color`); SSAO + cool fog + 1.16 grade complete the mood. Iterative screenshot tuning per milestone.

**Tech Stack:** Godot 4.6 Forward+ (Vulkan), GDScript. Verify via `tests/test_hd2d_factories.gd` + `xvfb-run … --rendering-driver vulkan` screenshots through the `SHOT_OUT` hook.

**Reference spec:** `docs/superpowers/specs/2026-06-13-cb-lighting-signature-design.md`

---

## File Structure

| File | Change |
|---|---|
| `scripts/HD2DEnvironment.gd` | field: lilac ambient, 1.16 grade, glow 1.0, cool fog, SSAO. battle: same minus fog. |
| `scripts/HD2DStage.gd` | `key_light`: near-white sun, `shadow_opacity`/`shadow_blur` (no `shadow_color`). |
| `scripts/Player.gd` | player billboard → `shaded=true`. |
| `scripts/Battle.gd` | `_place` billboard → `shaded=true`. |
| `tests/test_hd2d_factories.gd` | assert the CB env/light values. |

---

## Task A1: Environment + light signature

**Files:** `scripts/HD2DEnvironment.gd`, `scripts/HD2DStage.gd`, `tests/test_hd2d_factories.gd`

- [ ] **Step 1: Field profile → CB grade.** In `HD2DEnvironment.gd` field branch, set: ambient source `AMBIENT_SOURCE_COLOR`, `ambient_light_color = Color(0.349,0.325,0.420)`, `ambient_light_energy = 0.5`; `glow_intensity = 1.0`; `fog_light_color = Color(0.502,0.600,0.702)`; `adjustment_contrast = 1.16`; `adjustment_saturation = 1.16`. Add SSAO: `ssao_enabled = true`, `ssao_radius = 2.0`, `ssao_intensity = 2.0`, `ssao_power = 1.5`. (Keep BG_SKY, FILMIC, fog_enabled true, density 0.004, aerial 0.35, glow_bloom 0.2, hdr 1.0.)

- [ ] **Step 2: Battle profile → CB grade minus fog.** In the battle branch set: `ambient_light_color = Color(0.349,0.325,0.420)`, `ambient_light_energy = 0.7`; `glow_intensity = 1.0`; `adjustment_contrast = 1.16`; `adjustment_saturation = 1.16`; `ssao_enabled = true`, `ssao_radius = 2.0`, `ssao_intensity = 2.0`, `ssao_power = 1.5`. Leave `fog_enabled = false`.

- [ ] **Step 3: Sun → near-white, no shadow_color.** In `HD2DStage.key_light`, field branch: `light_color = Color(1.0,0.98,0.95)`, `light_energy = 1.0`, keep `shadow_enabled = true`, add `shadow_opacity = 0.85`, `shadow_blur = 1.5` (remove the old warm color/energy). Battle branch: `light_color = Color(1.0,0.98,0.95)`, `light_energy = 1.0`, `shadow_opacity = 0.85`. Do NOT reference `shadow_color` (absent in GD4.6).

- [ ] **Step 4: Update the factory test** `tests/test_hd2d_factories.gd` to the new values: field `glow_intensity 1.0`, `adjustment_saturation 1.16`; add `field` ambient assertions (`f.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR`, `f.ambient_light_color.is_equal_approx(Color(0.349,0.325,0.420))`, `f.ambient_light_energy == 0.5`) and `f.ssao_enabled == true`; battle `glow_intensity 1.0`, `adjustment_saturation 1.16`, `b.ssao_enabled == true`. Run:
  `xvfb-run -a ~/.local/bin/godot --path . --headless --script res://tests/test_hd2d_factories.gd` → `RESULT: PASS` (check `${PIPESTATUS[0]}`).

- [ ] **Step 5: Screenshot + tune (iterative).** For field and battle:
  `SHOT_OUT=/tmp/a1_field.png SHOT_FRAMES=150 xvfb-run -a ~/.local/bin/godot --path . --rendering-driver vulkan --scene res://scenes/Field.tscn`
  Read each shot. Target: cool lilac mood, indigo-reading shadows (from ambient), SSAO grounding objects. Tune ambient energy / SSAO radius+intensity / glow / fog density by re-editing the profile and re-shooting until it reads CB. Re-run the test after each value change. Save `docs/superpowers/specs/field-cb-a1.png`, `battle-cb-a1.png`.

- [ ] **Step 6: Commit.** `git add scripts/HD2DEnvironment.gd scripts/HD2DStage.gd tests/test_hd2d_factories.gd docs/superpowers/specs/field-cb-a1.png docs/superpowers/specs/battle-cb-a1.png && git commit -m "feat(cb-A1): CB environment + light signature (lilac ambient, SSAO, 1.16 grade)"`

---

## Task A2: Lit sprites

**Files:** `scripts/Player.gd`, `scripts/Battle.gd`

- [ ] **Step 1: Light the player.** In `Player.gd` (the `_ready` that does `_sprite = HD2D.character(sprite_path, 2.4)`), change to `_sprite = HD2D.character(sprite_path, 2.4, true)`.

- [ ] **Step 2: Light battle combatants.** In `Battle.gd._place`, change `var spr := HD2D.character(tex, height, false)` to `var spr := HD2D.character(tex, height, true)`.

- [ ] **Step 3: Import + screenshot.** `xvfb-run -a ~/.local/bin/godot --path . --import --headless` then screenshot field + battle (commands as A1, `/tmp/a2_*.png`). Read them: sprites should be tinted/grounded by the scene light, not flat-bright — **and still fully readable**.

- [ ] **Step 4: Readability tune (iterative).** If sprites read muddy/dark, raise field `ambient_light_energy` (0.5→0.6–0.8) and/or sun `light_energy` in the profiles, re-shoot until grounded yet clearly legible. Keep the lilac hue. Re-run the factory test after any profile value change and update the asserted value. Save `field-cb-a2.png`, `battle-cb-a2.png`.

- [ ] **Step 5: Commit.** `git add scripts/Player.gd scripts/Battle.gd docs/superpowers/specs/field-cb-a2.png docs/superpowers/specs/battle-cb-a2.png [+ any tuned profile/test files] && git commit -m "feat(cb-A2): light character billboards; tune ambient for readability"`

---

## Task A3: Converge + verify

**Files:** any final profile tuning; `docs/superpowers/specs/2026-06-13-cb-lighting-signature-design.md`

- [ ] **Step 1: Final convergence pass.** Compare field + battle side by side; do a last tuning round so both read consistently CB (cool, indigo shadows, grounded lit sprites, SSAO depth). Re-run the factory test green after any value change.

- [ ] **Step 2: Full-flow boot check.**
  ```bash
  for S in Title Field Battle; do SHOT_OUT=/tmp/flow_$S.png SHOT_FRAMES=90 xvfb-run -a ~/.local/bin/godot --path . --rendering-driver vulkan --scene res://scenes/$S.tscn >/tmp/g_$S.log 2>&1; echo "$S=$? $(grep -iE 'SCRIPT ERROR|Parse Error' /tmp/g_$S.log | grep -vi 'leaked\|still in use' | head -1)"; done
  ```
  Expected: all exit 0, no script errors.

- [ ] **Step 3: Document final values.** Append a "Final CB values (A3)" section to the spec with the locked field/battle ambient/glow/grade/SSAO/sun numbers. Save `field-cb-final.png`, `battle-cb-final.png`.

- [ ] **Step 4: Commit.** `git add -A && git commit -m "docs(cb-A3): record final CB lighting values; full-flow verified"` then offer `superpowers:finishing-a-development-branch`.

---

## Self-Review Notes
- **Spec coverage:** lilac ambient + 1.16 grade + glow + cool fog + SSAO (A1); near-white sun, no shadow_color (A1 step 3); battle fog-off (A1 step 2); lit sprites via call sites, default unchanged (A2); Forward+/vulkan + named screenshots + full-flow (A1/A2/A3). All spec sections covered.
- **GD4.6 correctness:** no `shadow_color` / `ssao_color` referenced anywhere. SSAO under Forward+/vulkan only.
- **Determinism:** Field `randomize()` → visual checks are look-judgment; the deterministic guard is the factory value-test.
