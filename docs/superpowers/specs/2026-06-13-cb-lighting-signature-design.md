# CB Lighting Signature + Lit Sprites — Design

**Date:** 2026-06-13
**Status:** Draft (awaiting review)
**Goal:** Make the game read like **Cassette Beasts** by porting CB's environment/lighting signature and lighting the character sprites — the cheapest, most foundational step toward the CB look.

**Reference:** Techniques reverse-engineered from the decompiled CB project at `/home/pc/hdd/shared/游戏/godotgames/cassetteBeasts/` (Godot 3.x). This spec ports the *technique and values*, authored with our own assets — no CB assets are copied.

## Context

The project already has a centralized, profile-parameterized HD-2D render rig (`scripts/HD2DEnvironment.gd`, `scripts/HD2DStage.gd`, `scripts/HD2D.gd`) from the prior OCTOPATH work, consumed by `Field.gd` and `Battle.gd`. This spec **re-grades** those profiles from the vivid OCTOPATH look toward CB's cooler, muted, indigo-shadowed mood, and flips character billboards to be lit. It is a values + small-API change on existing files — no new architecture.

CB's look comes from (per research): one animated `DirectionalLight` with an **indigo shadow color**, a **lilac ambient** fill, indigo SSAO, a consistent **contrast/saturation 1.16** grade, strong glow, biome-cool fog — and **sprites rendered lit** (`Sprite3D` spatial shader, not unshaded) so they catch the scene light. CB's ground *geometry* depth and animated grass are **separate later specs**; this one is lighting + lit sprites only.

## Goals

1. The field and battle read with CB's cool, indigo-shadowed, muted-saturation mood.
2. Character sprites are lit by the scene (catch sun color + lilac ambient), grounding them into the world.
3. The change stays within the existing rig files + call sites; the factory value-test is updated and green; Title→Field→Battle still boot.

## Non-Goals (each a later CB spec)

- Day/night cycle (we set a fixed CB-daylight "noon"; animating it is Spec D).
- Animated grass / wind / weather (Spec B).
- 3D tile-mesh terrain with real height (Spec C) — the geometric ground-depth fix.
- Water / clouds. Decompiled-CB asset reuse (we author our own).

## The CB Signature — ported values

Source values from CB's `world_camera_env_daylight.tres` + `WorldDayNightCycle.tscn` (noon), adapted to Godot 4.6.

| Aspect | CB (Godot 3) | Our Godot 4.6 application |
|---|---|---|
| Shadow tint | `DirectionalLight.shadow_color (0.239,0.235,0.372)` indigo | `DirectionalLight3D.shadow_color = (0.239,0.235,0.372)` — both profiles |
| Ambient | color `(0.349,0.325,0.420)` lilac, energy 0.5 | field ambient → `AMBIENT_SOURCE_COLOR`, color `(0.349,0.325,0.420)`, energy ~0.5 |
| SSAO | `ssao_color (0.2,0.173,0.251)` indigo | `ssao_enabled = true` (tune radius/intensity/power). **GD4 has no `ssao_color`** — the indigo tint comes from `shadow_color` + lilac ambient instead |
| Grade | contrast 1.16, saturation 1.16 | `adjustment_contrast = 1.16`, `adjustment_saturation = 1.16`, brightness 1.0 (down from our 1.15 / **1.32**) |
| Glow | intensity 1.0 | `glow_intensity → ~1.0` (from 0.5) |
| Fog | transmit, steel-blue `(0.502,0.600,0.702)`, far begin | `fog_light_color → (0.502,0.600,0.702)` (cool, from warm), density tuned for distant haze |
| Tonemap | Filmic | keep `TONE_MAPPER_FILMIC` |
| Sun (noon) | white, energy 1.0 | key light → near-white `(1.0,0.98,0.95)`, energy ~1.0 |

GD3→GD4 notes: `ssao_color` removed (rely on shadow_color + ambient); Godot 4 fog is density/volumetric rather than depth-begin/end, so CB's "fog begins at 50" becomes a tuned light density that reads as distant haze.

## Lit Sprites

CB sprites use a `shader_type spatial` material **without `unshaded`**, so Godot's diffuse lighting tints the flat billboard by the scene light — the sprite picks up the sun color and lilac ambient and integrates into the mood.

Our `HD2D.character(tex, height, shaded)` already exposes `shaded` (sets `Sprite3D.shaded`). Today the player is `shaded=false` (self-lit) and Battle combatants pass `false`; props pass `true`. Change so **all characters are lit**:
- `HD2D.character()` default `shaded = true`.
- Update Battle's explicit `false` call sites (`Battle._place`) to lit.
- Player/Field already get the default.

Readability risk (CB has it too): a lit billboard can go dim when the sun is off-axis. Mitigate with the lilac ambient energy (keeps fill) and sun energy; tune at A2 so sprites never read muddy. Keep `roughness` high (matte diffuse) — no spec-on-pixels.

## Components / Files

| File | Change |
|---|---|
| `scripts/HD2DEnvironment.gd` | field + battle profiles → CB grade (lilac ambient, 1.16 contrast/sat, cool fog, glow ~1.0, SSAO enabled) |
| `scripts/HD2DStage.gd` | `key_light` → add `shadow_color` indigo; near-white sun |
| `scripts/HD2D.gd` | `character()` default `shaded = true` |
| `scripts/Battle.gd` | `_place` billboard calls → lit |
| `tests/test_hd2d_factories.gd` | update asserted env/light values to the CB set |

Each file keeps its single responsibility; this is a values + one-default change, no new units.

## Verification

- Factory value-test updated to the CB values and green (headless).
- Iterative screenshots (controller-driven, like M2) for field + battle via the `SHOT_OUT` hook under `xvfb`, tuned until: indigo-tinted shadows, cool lilac mood, sprites visibly grounded/lit, SSAO contact-shadow depth, sprites still fully readable.
- Title→Field→Battle all boot with no script errors.

## Milestones

- **A1 — Environment + light signature:** apply CB grade + shadow_color + SSAO to both profiles; screenshot field/battle, tune the cool mood. Update test. Commit.
- **A2 — Lit sprites:** flip characters to `shaded`; tune ambient/sun so they're grounded yet readable; screenshot. Commit.
- **A3 — Converge + verify:** final cool-grade tuning across field/battle; full-flow boot check; document final CB values in this spec. Commit.

## Open Questions (non-blocking)

- Exact ambient energy vs sun energy balance for sprite readability — tuned at A2.
- Whether to cool the procedural sky colors too (currently warm-ish horizon) — decide by screenshot at A1.
- SSAO strength (radius/intensity/power) — tuned at A1.
