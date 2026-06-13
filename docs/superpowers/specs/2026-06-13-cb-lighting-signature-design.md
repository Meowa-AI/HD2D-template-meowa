# CB Lighting Signature + Lit Sprites — Design

**Date:** 2026-06-13
**Status:** Draft (awaiting review)
**Goal:** Make the game read like **Cassette Beasts** by porting CB's environment/lighting signature and lighting the character sprites — the cheapest, most foundational step toward the CB look.

**Reference:** Techniques reverse-engineered from the decompiled CB project at `/home/pc/hdd/shared/游戏/godotgames/cassetteBeasts/` (Godot 3.x). This spec ports the *technique and values*, authored with our own assets — no CB assets are copied.

## Context

The project already has a centralized, profile-parameterized HD-2D render rig (`scripts/HD2DEnvironment.gd`, `scripts/HD2DStage.gd`, `scripts/HD2D.gd`) from the prior OCTOPATH work, consumed by `Field.gd` and `Battle.gd`. This spec **re-grades** those profiles from the vivid OCTOPATH look toward CB's cooler, indigo-shadowed mood — cooler and **less saturated relative to our current 1.32 (→1.16, still >1, not desaturated)** — and flips character billboards to be lit. It is a values + small-API change on existing files — no new architecture.

CB's look comes from (per research): one animated `DirectionalLight` with an **indigo shadow color**, a **lilac ambient** fill, indigo SSAO, a consistent **contrast/saturation 1.16** grade, strong glow, biome-cool fog — and **sprites rendered lit** (`Sprite3D` spatial shader, not unshaded) so they catch the scene light. CB's ground *geometry* depth and animated grass are **separate later specs**; this one is lighting + lit sprites only.

## Goals

1. The field and battle read with CB's cool, indigo-shadowed, muted-saturation mood.
2. Character sprites are lit by the scene (catch sun color + lilac ambient), grounding them into the world.
3. The change stays within the existing rig files + call sites; the factory value-test is updated and green; Title→Field→Battle still boot.

## Non-Goals (each a later CB spec)

- Day/night cycle (we set a fixed CB-daylight "noon"; animating it is Spec D).
- Animated grass / wind / weather (Spec B).
- 3D tile-mesh terrain with real height (Spec C) — the geometric ground-depth fix.
- Water / clouds (Spec D).
- Reusing CB's decompiled assets — we author our own; this spec ports technique and values only.

## The CB Signature — ported values

Source values from CB's `world_camera_env_daylight.tres` + `WorldDayNightCycle.tscn` (noon), adapted to Godot 4.6.

| Aspect | CB (Godot 3) | Our Godot 4.6 application |
|---|---|---|
| Indigo shadows | `DirectionalLight.shadow_color (0.239,0.235,0.372)` | **Not portable** — verified: GD4 `Light3D` has no `shadow_color` (only `shadow_enabled/opacity/blur/bias/normal_bias/caster_mask`). In GD4 a shadowed region is lit by **ambient only**, so the **lilac ambient below reproduces the indigo-shadow mood directly**. `shadow_opacity` / `shadow_blur` only set shadow strength/softness. |
| Ambient | color `(0.349,0.325,0.420)` lilac, energy 0.5 | field ambient → `AMBIENT_SOURCE_COLOR`, color `(0.349,0.325,0.420)`, energy ~0.5. **This is also the indigo-shadow mechanism** (shadows = ambient-lit). |
| SSAO | `ssao_color (0.2,0.173,0.251)` indigo | `ssao_enabled = true`; tune `ssao_radius/intensity/power`. **Verified: GD4 has no `ssao_color`** — SSAO only darkens; that darkening *reads* indigo because the surrounding ambient is lilac. SSAO needs Forward+ (see Verification). |
| Grade | contrast 1.16, saturation 1.16 | `adjustment_contrast = 1.16`, `adjustment_saturation = 1.16`, brightness 1.0 (down from our 1.15 / **1.32** — cooler/less-saturated, but still >1, **not desaturated**) |
| Glow | intensity 1.0 | `glow_intensity → ~1.0` (from 0.5) |
| Fog | transmit, steel-blue `(0.502,0.600,0.702)`, far begin | **field only**: `fog_light_color → (0.502,0.600,0.702)` (cool, from warm), density tuned for distant haze. **Battle keeps fog off** (see below). |
| Tonemap | Filmic | keep `TONE_MAPPER_FILMIC` |
| Sun (noon) | white, energy 1.0 | key light → near-white `(1.0,0.98,0.95)`, energy ~1.0; keep `shadow_enabled`, tune `shadow_opacity`/`shadow_blur` |

**GD3→GD4 correctness notes (verified against the engine's property list):** `DirectionalLight3D.shadow_color` and `Environment.ssao_color` **do not exist in Godot 4.6**. CB's indigo-shadow signature is therefore reproduced *entirely* by **lilac ambient + cool fog + SSAO + the 1.16 grade** — there is no per-light or per-SSAO color to set, and attempting to set one would error. Godot 4 fog is density/volumetric rather than depth begin/end, so CB's "fog begins at 50" becomes a tuned density that reads as distant haze.

**Battle fog strategy:** the battle profile currently uses `BG_COLOR` + a painted backdrop with `fog_enabled = false`. Battle **keeps fog off** and takes only the ambient / grade / glow / SSAO parts of the signature — fog is added there *only* if a screenshot proves it doesn't muddy the backdrop or hurt combat readability.

## Lit Sprites

CB sprites use a `shader_type spatial` material **without `unshaded`**, so Godot's diffuse lighting tints the flat billboard by the scene light — the sprite picks up the sun color and lilac ambient and integrates into the mood.

Our `HD2D.character(tex, height, shaded)` already exposes `shaded` (sets `Sprite3D.shaded`). Today: props and grass bushes already pass `true` (lit); only the **player** (`Player.gd`, uses the default) and **Battle combatants** (`Battle._place`, explicit `false`) are unlit. To avoid a surprising global API behavior change, **keep `HD2D.character()`'s default `shaded = false`** and make the two unlit call sites explicit:
- `Player.gd` → `HD2D.character(sprite_path, 2.4, true)`.
- `Battle._place` → change its `HD2D.character(tex, height, false)` to `true`.

(Props/bushes are unchanged — already lit.) After this, every character/prop billboard is lit; the default is left alone so other/future callers are unaffected.

Readability risk (CB has it too): a lit billboard can go dim when the sun is off-axis. Mitigate with the lilac ambient energy (keeps fill) and sun energy; tune at A2 so sprites never read muddy. Keep `roughness` high (matte diffuse) — no spec-on-pixels.

## Components / Files

| File | Change |
|---|---|
| `scripts/HD2DEnvironment.gd` | field → CB grade (lilac ambient, 1.16 contrast/sat, cool fog, glow ~1.0, SSAO enabled); battle → same minus fog |
| `scripts/HD2DStage.gd` | `key_light` → near-white sun, `shadow_opacity`/`shadow_blur` tuned (**no `shadow_color`** — doesn't exist in GD4) |
| `scripts/HD2D.gd` | **unchanged default** (`shaded = false` stays) |
| `scripts/Player.gd` | player billboard call → `shaded = true` |
| `scripts/Battle.gd` | `_place` billboard call → `shaded = true` |
| `tests/test_hd2d_factories.gd` | update asserted env/light values to the CB set |

Each file keeps its single responsibility; this is a values + two-call-site change, no new units and no API-default change.

## Verification

**Renderer premise:** SSAO in Godot 4.6 is supported only on **Forward+** and Compatibility, not Mobile. The project is Forward+ (`project.godot`), and all screenshot/boot checks fix `--rendering-driver vulkan`. If SSAO renders nothing, confirm the renderer first.

- **Factory value-test** updated to the CB values and green (headless):
  `xvfb-run -a ~/.local/bin/godot --path . --headless --script res://tests/test_hd2d_factories.gd` → `RESULT: PASS` (check `${PIPESTATUS[0]}`).
- **Screenshots** via the `SHOT_OUT` hook, controller-driven iteration (like M2). Per scene:
  `SHOT_OUT=/tmp/x.png SHOT_FRAMES=150 xvfb-run -a ~/.local/bin/godot --path . --rendering-driver vulkan --scene res://scenes/Field.tscn`
  Save milestone references to `docs/superpowers/specs/`: `field-cb-a1.png`, `field-cb-a2.png`, `field-cb-final.png` and `battle-cb-a1.png`, `battle-cb-a2.png`, `battle-cb-final.png`.
- **Acceptance per shot:** cool lilac mood, indigo-reading shadows (from ambient), SSAO contact-shadow depth grounding objects, sprites visibly lit/grounded **and still fully readable** (not muddy).
- **Full flow:** `--scene res://scenes/Title.tscn|Field.tscn|Battle.tscn` all boot under `xvfb` + vulkan with no script/parse errors.

## Milestones

- **A1 — Environment + light signature:** apply CB grade + shadow_color + SSAO to both profiles; screenshot field/battle, tune the cool mood. Update test. Commit.
- **A2 — Lit sprites:** flip characters to `shaded`; tune ambient/sun so they're grounded yet readable; screenshot. Commit.
- **A3 — Converge + verify:** final cool-grade tuning across field/battle; full-flow boot check; document final CB values in this spec. Commit.

## Open Questions (non-blocking)

- Exact ambient energy vs sun energy balance for sprite readability — tuned at A2.
- Whether to cool the procedural sky colors too (currently warm-ish horizon) — decide by screenshot at A1.
- SSAO strength (radius/intensity/power) — tuned at A1.
