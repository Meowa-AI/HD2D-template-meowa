# CB Tiered Terrain + Cliffs + Clouds + Water — Design (as-built)

**Date:** 2026-06-13 → 2026-06-14
**Status:** Implemented (Specs C + D of the CB program)
**Goal:** Give the field Cassette Beasts' ground depth and atmosphere — tiered terrain with cliffs, rock faces, drifting cloud shadows, and water.

## Implemented

**Tiered terrain (`scripts/TieredTerrain.gd`)**
- `height_at(x,z)` — a flat playable meadow (chebyshev radius `FLAT`) that steps up into terraces to the north and sides, open to the south (camera) so the view looks *into* the landscape. Carves a sunken pond.
- `build()` — SurfaceTool builds grass-textured flat tops + dirt cliff walls (where a neighbour is lower) into one mesh (two surfaces/materials), double-sided, with a trimesh `StaticBody3D` that contains the player in the meadow.
- Props sit on terrain height; the grass blanket is restricted to the meadow.
- Cliffs use a generated, brightened rock/dirt texture (`assets/textures/cliff.png`).

**Cloud shadows (`scripts/CloudShadows.gd`)**
- A handful of soft `Decal` cloud blobs project straight down onto the terrain and drift across the field in the `WeatherSystem` wind direction, wrapping — dappled moving light on grass and cliffs.

**Water (`shaders/water.gdshader` + `TieredTerrain.water()`)**
- A subdivided water plane fills the carved pond: cool translucent surface, gentle vertex ripple, animated binary glints on the shared `wind_phase`. The grass shader discards blades inside the pond radius so the water reads.

## Key engineering notes
- **Camera-facing trick:** the field camera looks a fixed −Z, so grass blades and foliage are +Z standing quads (no per-blade billboard math); world-space wind offsets add straight to `VERTEX`.
- **Robust autoload access:** shared static helpers (`HD2DStage`, `GrassField`, terrain water) reach `WeatherSystem` via the scene tree, not the global identifier — referencing the autoload global made the helpers fail to compile (and hang) in headless/test loads.
- **Readability vs mood:** softened fog (0.0045) and DOF (amount 0.20) from the earlier OCTOPATH grade so the cliff geometry reads while keeping the CB tilt-shift feel.

## Verification
Factory value-test PASS; Title→Field→Battle boot clean under xvfb+vulkan; grass-sway two-frame diff confirmed motion. Reference shots: `field-cb-{terrain,clouds,water}.png`.

## Remaining (future)
Day/night cycle, more biomes, in-world monsters, water shore foam, terrace-conforming grass.
