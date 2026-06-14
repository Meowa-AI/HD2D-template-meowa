# Procedural terrain: noise biomes + richer heightfield — design

**Date:** 2026-06-14
**Status:** approved (pre-implementation)

## Problem

The terrain feels monotonous. Root cause is world *generation*, not rendering:
`biome_at` is five large geometric regions (one plateau circle, one lake circle,
two quadrants, grass everywhere else), and `height_at` is a single low-amplitude
sine sum. So ~80% of the map is uniform grass at uniform relief, and the dual-grid
transition system only fires along a few macro seams.

## Goal

Make the world richly varied and fully procedural (fixed seed), so biomes interleave
organically — small patches scattered throughout — and the relief has hills, valleys,
highlands and basins. No river this round. Keep the world walkable and cheap to sample.

## Approach: elevation + moisture noise model

Two cached static `FastNoiseLite` fields with a fixed seed drive everything:

- **Height field** → elevation. **Moisture field** → biome selection together with elevation.

This is the classic biome model and makes biomes interleave naturally. Water becomes a
single plane at `WATER_LEVEL`; wherever the height noise dips below it, you get ponds/a
lake for free. Landmarks become procedural (placed relative to features the noise produces).

## Components

### 1. Height field (`TieredTerrain.height_at`)

- Replace the sine sum with a cached static `FastNoiseLite`: Simplex, **FBM ~4 octaves**,
  base frequency ~`0.012`, with a light **domain warp** (Simplex, amplitude ~30, freq ~0.01)
  for organic ridges/valleys.
- Map noise `e∈[-1,1]` to world height via `lerp(H_MIN, H_MAX, (e+1)/2)` with starting
  `H_MIN≈-2.5`, `H_MAX≈8.0` — so some basins fall below `WATER_LEVEL` (water) and some
  zones rise into highland. Exact constants tuned via screenshots.
- Keep the border ring: `edge>66 → 16.0` (world-boundary cliff).
- **Walkability:** amplitude/frequency chosen so interior gradients stay below the cliff
  threshold (`CLIFF_SPAN/CELL = 3/2 = 1.5`) almost everywhere; genuinely steep spots are
  fine — they get the cliff texture and the player's `MAX_STEP` gate stops only true walls.

### 2. Biome (`TieredTerrain.biome_at`)

From elevation `e = height_at(x,z)` and moisture `m = noise_m(x,z)`:
- `e <= WATER_LEVEL + SHORE` (≈0.7) → **4 sand** (shore/beach band around water)
- `e >= HIGHLAND_Y` (≈4.8) → **3 rock** (highland)
- else by moisture: `m > 0.25` → **2 forest**; `m < -0.25` → **1 flower meadow**;
  otherwise → **0 grass**

Because `e` and `m` both vary continuously, biomes interleave and small patches scatter
into the grass, so dual-grid transitions appear across the whole map. Thresholds tuned via
screenshots.

### 3. Water + downstream coupling

- `TieredTerrain.water()` returns **one large plane at `WATER_LEVEL`** spanning the playable
  area (≈132×132), using the existing water shader, centered at origin. Procedural basins
  read as water. Remove the fixed `LAKE`-position lake.
- **Grass blanket:** exclude blades where baked terrain height `<= WATER_LEVEL` (replaces the
  fixed circular-pond exclusion). Mechanism worked out in the plan against `GrassField`'s
  existing baked heightmap.
- **Monsters / player:** already gate on `WATER_LEVEL` (`Monster.gd`, `Player.gd`) — unchanged.

### 4. Landmarks (now procedural)

- **Treasure chest:** placed at the procedurally-found **highest walkable point** (scan a
  coarse grid of `height_at`, pick the max that isn't a cliff/underwater), instead of the
  hard-coded plateau at `(42,-40)`.
- **Signpost:** kept for flavor, but text becomes generic lore (drop the hard-coded
  "Highcrag Plateau / Still Lake / Mistral Forest" names, which no longer correspond to
  fixed places).
- Start clearing (camp props at spawn) stays.

### 5. Determinism + performance

- Noise instances are `static var`s, lazily created once with a **fixed seed**
  (`SEED_H`, `SEED_M`). `height_at`/`biome_at` remain pure static functions of (x,z).
- One `get_noise_2d` per field (FBM is internal), so per-frame player sampling
  (4× height_at/frame) stays cheap.

## What stays the same

- The dual-grid overlay rendering (`DualGrid.gd`, `TieredTerrain` overlay layers), camera,
  DOF, day/night, encounter mechanics, prop *types*.
- `WATER_LEVEL`, `CELL`, `CLIFF_SPAN`, `TEX`, `OVERLAYS`.

## Files touched

- `scripts/TieredTerrain.gd` — noise statics, `height_at`, `biome_at`, `water()`; drop
  `PLATEAU`/`LAKE`/`LAKE_Y`/`PLATEAU_Y` (and their uses).
- `scripts/Field.gd` — grass-blanket exclusion arg (height-based), chest→peak placement,
  signpost text, remove `TieredTerrain.LAKE` references.
- `scripts/GrassField.gd` — underwater exclusion via the baked heightmap.

## Verification

- Headless top-down (DOF/fog off) — biomes interleave with organic patches across the whole
  map, not 5 blobs; basins show water.
- Elevated overview + gameplay shots — varied relief (hills/valleys/highland), no holes, no
  z-fighting on overlays, terrain reads walkable.
- Lakeshore/pond gameplay shot — water + sand transitions read naturally.
- `test_dualgrid.gd` still passes; field loads with no script errors.
- Tune noise constants/thresholds and re-render until it reads rich and natural.

## Risks / open items

- **Walkability vs richness:** if tuned too steep, interior turns to cliffs / blocks the
  player. Mitigation: keep amplitude moderate, verify by walking shots; raise `MAX_STEP`
  only as a last resort.
- **Grass under water:** ensure the exclusion fully hides blades in basins (no blades poking
  through the water plane).
- **Spawn safety:** the fixed spawn `(0,0,22)` must land on walkable, above-water ground for
  the chosen seed; if not, nudge spawn or seed.
