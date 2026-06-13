# CB Animated Grass + Wind — Design (as-built)

**Date:** 2026-06-13
**Status:** Implemented (Spec B of the CB program)
**Goal:** Make the field feel alive like Cassette Beasts — a swaying grass carpet, windblown foliage, and grass that parts around the player.

## Implemented

- **`scripts/WeatherSystem.gd` (autoload)** — global wind clock + body tracker. Accumulates `wind_phase += TAU·delta·wind_speed`; holds `wind_strength`. `register(mat)` collects wind-reactive `ShaderMaterial`s; each `_process` pushes `wind_phase`, `wind_strength`, `body_0/1` (player positions, ≤2) into all of them. `Field._process` calls `set_body(0, player.global_position)`.
- **`shaders/grass_blade.gdshader`** — draw mesh for the grass particles. Height-weighted sway (tip moves, base pinned), per-blade world-XZ phase offset, radial player push-away within `avoid_distance`, `ALPHA_SCISSOR` crisp edges, `NORMAL` forced up-ish to catch the lilac ambient. Blades are non-rotated +Z quads (field camera looks fixed −Z), so world-space offsets add straight to `VERTEX`.
- **`scripts/GrassField.gd`** — static `GPUParticles3D` blanketing the 80×80 field (24000 blades, zero velocity — motion is all shader), big `visibility_aabb` to avoid culling, registers its material with WeatherSystem.
- **`shaders/windblown.gdshader` + `HD2DStage.windblown_prop`** — trees/bushes as +Z standing quads with crown-biased sway on the same wind clock. Solid props (barrel/crate/well/lamp/fence/signpost/chest) stay static.
- **Asset:** `assets/textures/grass_blade.png` — procedural transparent grass tuft.

## Verification
Two-frame diff: ~34% of grass-band pixels shift over 3 s (sway confirmed). Title→Field→Battle boot clean; factory value-test PASS.

## Non-Goals (later CB specs)
3D tiered terrain (Spec C), water/clouds (Spec D), day/night cycle, leaf/weather particles, grass collision beyond player push.
