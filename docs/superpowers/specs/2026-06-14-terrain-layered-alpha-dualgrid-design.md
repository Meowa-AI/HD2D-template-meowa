# Terrain: layered-alpha dual-grid transitions — design

**Date:** 2026-06-14
**Status:** approved (pre-implementation)

## Problem

The field terrain is a continuous heightfield mesh, but each cell is textured with a
single biome texture chosen by `biome_at(center)`. Adjacent biomes meet along hard,
straight cell seams (grass | rock | sand …), which looks artificial. We want natural,
organic transitions between biomes in the style of Cassette Beasts / Octopath Traveler.

## Approach: layered alpha blending with transparent-edge dual-grid tilesets

Do **not** author pairwise transition tiles between every biome pair. Instead:

1. **Grass is the base layer** — a full-coverage, opaque heightfield (no transparent
   edges). It always fills the whole ground.
2. **Every other biome is an overlay** with its **own dual-grid-15 tileset whose
   background is transparent (alpha = 0)**. The biome texture fills the "on" corners
   and fades to transparent at the border.
3. **Render in layer order** (bottom → top). Where an overlay's edge is transparent,
   the layer beneath shows through, producing the organic border. Adding a new terrain
   later = one more transparent tileset + one more layer. No combinatorial growth.

This is the modern indie-standard technique and resolves the "dual-grid handles only 2
terrains, we have 5" tension: each overlay is `biome → transparent`, composited over
whatever is below it.

## Assets (Meowa `tileset-gen-run`)

- **Base:** reuse existing `assets/textures/grass.png` (opaque, seamless). Regenerate
  only if it does not read well as a full base.
- **Overlays — 4 transparent-edge dual-grid-15 tilesets**, one per non-grass biome:
  `flower_meadow`, `forest_floor`, `rock_ground`, `sand`. Each is "this terrain fading
  to transparent."
- Command shape:
  `tileset-gen-run --tileset-mode dual-grid-15` with the biome texture as the foreground
  and a transparent background. Verify Meowa's transparent-background support and the
  exact transparency flag against `meowart_api.py` at generation time.
- **Per Meowa gotchas:** pass a short `--job-name`; run from project root (`.env` auth);
  launch with `run_in_background`; **Read the generated preview to confirm the atlas
  layout (tile count, grid arrangement, per-tile pixel size) before wiring it in** — the
  dual-grid tile index → atlas sub-rect mapping depends on this layout.
- Output tilesets land in `assets/textures/tilesets/<biome>_dualgrid.png` (clean names),
  committed with their `.import`.

## Rendering: stacked transparent heightfield layers

Geometry and world shape are unchanged. `height_at` and `biome_at` are untouched.
The change is confined to `TieredTerrain.build()` texturing/layering.

### Layers

1. **Grass base layer** — the current shared-corner heightfield mesh (corners sampled
   from `height_at`, smooth normals), textured with `grass.png`, opaque.
2. **One overlay layer per biome** (`forest_floor`, `flower_meadow`, `rock_ground`,
   `sand`) — a mesh on the **dual-grid render grid** (offset half a cell from the data
   grid), `TRANSPARENCY_ALPHA` material with that biome's transparent tileset.
3. **Cliff** — steep cells (corner height span > `CLIFF_SPAN` = 3.0, i.e. the world
   border ring) keep the `cliff.png` texture, on the base layer.
4. **Water** — the existing animated water plane, unchanged, drawn above.

### Dual-grid render grid + tile selection

- **Data grid:** cells as today; each cell's biome = `biome_at(cellCenter)`.
- **Render grid:** vertices at **cell centers**; each render tile is the square between
  four adjacent cell centers — offset half a cell from the data grid.
- For overlay biome `T`, each render tile reads its 4 corner cells' biomes and forms a
  4-bit mask (corner bit = 1 if that cell's biome == `T`). Mask `0` (no corner is `T`) →
  emit nothing (fully transparent). Mask `1..15` → select that tile from the 16-tile
  atlas and map its sub-rect to the quad UVs.
- Quad corner heights come from `height_at(cellCenter)` so overlays follow the same
  surface; per-vertex normals from the height gradient (as the base layer).

### Layer ordering (z-fight avoidance)

- Bottom → top: grass base → `forest_floor` → `flower_meadow` → `rock_ground` → `sand`
  → water plane. (Order is tunable; sand sits highest so it reads at the lakeshore,
  rock paints over grass.)
- Separate layers with increasing `render_priority` **and** a small Y lift (~0.02 per
  layer), reusing the offset trick already used by `_path_strip`. Keeps draw order
  stable on slopes without z-fighting.

### Tile world size

- Keep `CELL = 4.0` for the render tiles initially. If transitions look too coarse,
  drop to `2.0` (4× the tiles — still cheap for this map size).

## What stays the same

- `height_at` — player height-snapping, grass blanket, prop/NPC/monster placement.
- `biome_at` — now also the overlay-membership oracle.
- Camera, DOF, day/night, environment.

## Implementation outline

1. Generate + verify the 4 transparent dual-grid tilesets via Meowa; commit them.
2. Add a dual-grid module/helpers: 4-corner mask → atlas tile index, atlas UV sub-rect.
3. Rework `TieredTerrain.build()` into base layer + per-biome overlay layers on the
   offset render grid; keep cliff handling on the base.
4. Headless screenshot verification (ground-level + elevated overview); compare biome
   borders before/after; confirm no z-fighting, no holes, transitions read naturally.
5. Tune layer order / `CELL` if needed; commit; push.

## Risks / open items

- **Meowa transparent-background support:** confirm the exact flag and that edges are
  true alpha (not matte). Resolve at generation; if unsupported, fall back to generating
  on a flat color key and keying it out in post.
- **Atlas layout:** the tile-index→sub-rect mapping is layout-specific; lock it from the
  generated preview before coding the UV math.
- **3-way junctions** (a render tile touching grass + two overlays): handled naturally by
  layering — each overlay independently decides its own tile; stacking composites them.
