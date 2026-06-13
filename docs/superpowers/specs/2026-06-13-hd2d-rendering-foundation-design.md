# HD-2D Rendering Foundation — Design

**Date:** 2026-06-13
**Status:** Draft (awaiting review)
**Goal:** Make the game's art reach OCTOPATH TRAVELER ("HD-2D") quality, starting from the rendering pipeline.

## Problem & Reframe

The look people call "OCTOPATH-level" is **not** primarily about more detailed sprites. It is a *rendering technique*: ordinary 2D pixel sprites placed inside a real 3D diorama, then transformed by lighting, depth-of-field, bloom, atmospheric fog, and color grading.

Current project state:
- Godot 4.6 stable, Forward+ renderer.
- Asset library exists: 256×256 pixel character sprites (good quality), 64×64 tileable terrain, a 2752×1536 background image, SFX/BGM.
- `scripts/HD2D.gd` has helpers for billboarded `Sprite3D` characters, blob shadows, and a tiled ground plane.
- Autoloads exist: `GameData`, `Audio`, `SceneManager` (the latter points at `res://scenes/Field.tscn`).
- **No scene files exist yet** — `scenes/` is empty; the game does not run.

So the biggest gap is the **render stack**, and the first concrete deliverable is a **runnable Field scene** that establishes that stack. The existing sprites are reused as-is.

## Goals

1. Establish a complete, reusable HD-2D render rig (environment + camera + lighting) as the project's rendering foundation.
2. Deliver one runnable `Field.tscn` exploration scene that showcases the look using existing assets.
3. Validate visually by rendering with the Godot binary and screenshotting, iterating until it reads as "HD-2D".

## Non-Goals (for this spec)

- Gameplay (movement, encounters, battle logic). The scene may have a stub player but combat/exploration mechanics are out of scope.
- Generating new art assets (separate future effort; we prove the look with current sprites first).
- The Battle scene (will inherit this rig in a later spec).
- Title screen.

## Target Look — Decomposition

| Layer | OCTOPATH signature | Godot 4.6 mechanism |
|---|---|---|
| Depth of field | tilt-shift "miniature" — near/far blur, sharp midground | `CameraAttributesPractical` DOF near+far |
| Camera | telephoto compression, fixed ¾ down-angle | low FOV (~28°), pitch ~50° |
| Bloom | strong, near-overexposed highlight glow | `Environment` glow, multi-level, HDR threshold ~0.95 |
| Tonemap & grading | high saturation, filmic contrast | `Environment` tonemap ACES + adjustments (saturation ~1.25) |
| Atmosphere | depth fog, god rays, dust motes | `Environment` fog + `GPUParticles3D` |
| Lighting | sprites/props tinted by scene, real cast shadows | `DirectionalLight3D` (shadows) + colored `OmniLight3D` accents |
| Diorama depth | layered 2D-in-3D, parallax | bg backdrop plane + midground billboard props + foreground blur frame |
| Sprites | hand-drawn pixel, small | reuse existing 256px billboards |

## Architecture

Build the rig as **small, reusable, independently understandable units**, then compose them in `Field.tscn`.

### Components

1. **`scripts/HD2DEnvironment.gd`** — static factory returning a tuned `Environment` resource (glow, tonemap, adjustments, fog). One place to tune the global "grade". Used by every scene.
2. **`scripts/HD2DStage.gd`** — static helpers to build the shared rig:
   - `camera()` → `Camera3D` with low FOV, ¾ pitch, and a `CameraAttributesPractical` with DOF tuned.
   - `key_light()` → warm shadow-casting `DirectionalLight3D`.
   - `accent_light(color, energy)` → colored `OmniLight3D`.
   - `dust(area)` → `GPUParticles3D` drifting motes.
   - `backdrop(tex_path)` → far-plane quad for the background image, placed beyond DOF far-blur so it reads as soft background.
3. **`scripts/HD2D.gd`** (existing) — extended as needed:
   - Keep `character()` billboards (decide shaded vs. unlit during tuning — see Open Questions).
   - Keep `blob_shadow()`, `ground()`.
   - Add `prop(tex_path)` for midground billboard scenery (trees/rocks) reusing enemy/decor sprites if available, else simple placeholders.
4. **`scenes/Field.tscn` + `scripts/Field.gd`** — composes: `WorldEnvironment` (from #1) → ground (#3) → backdrop + midground props + foreground frame (#2/#3) → key + accent lights (#2) → dust (#2) → camera (#2) → a stub party member sprite (#3) standing on the ground. No gameplay logic required for the visual milestone.

### Why this split

- `HD2DEnvironment` and `HD2DStage` are scene-agnostic, so the future Battle scene reuses them verbatim — one consistent style, one place to tune.
- `Field.gd` only *composes*; it holds no rendering knowledge of its own, so changing the grade never means editing scene logic.

## Data Flow

`project.godot` main_scene → (later) Title → Field. For this slice we temporarily set `Field.tscn` as the run target so we can iterate, and restore the intended flow at the end.

`Field.gd._ready()` instantiates the rig from the factories and adds child nodes. All rendering parameters live in the two factory scripts; the scene is just composition.

## Validation Method (the iteration loop)

For each milestone:
1. Run headless render: `~/.local/bin/godot --path . --rendering-driver vulkan` with a short auto-screenshot script (a one-off `@tool`/`_ready` `get_viewport().get_texture().get_image().save_png(...)`), or `--write-movie`/`--quit-after` a few frames.
2. Read the screenshot, compare against OCTOPATH reference mentally, tune the factory params.
3. Repeat until the frame reads as HD-2D.

Screenshots are shown to the user at each milestone for a quality call.

## Milestones (incremental, each independently runnable & screenshotted)

- **M1 — Empty stage runs:** `Field.tscn` with ground + camera + key light + `WorldEnvironment` (tonemap + glow + fog). Proves the project runs and the grade is alive. Restore-point for the render rig.
- **M2 — Sprite in the world:** add stub hero billboard + blob shadow; tune sprite lighting/readability against the graded scene.
- **M3 — Depth & atmosphere:** DOF dialed in, backdrop plane, dust particles, accent light. This is where "miniature diorama" appears.
- **M4 — Diorama dressing:** midground props + foreground out-of-focus frame for real parallax depth.
- **M5 — Polish pass:** final grade/bloom/DOF/fog tuning; document the tuned values; restore intended scene flow.

Each milestone is a commit.

## Open Questions / Tuning Decisions (resolved during implementation, not blocking)

- **Shaded vs. unlit sprites:** OCTOPATH keeps characters highly readable. Likely keep character billboards `shaded=false` (readable) but let bloom + tonemap + color-grade still affect them, with blob + optional cast shadow for grounding. Will A/B both during M2.
- **DOF strength:** strong enough for the miniature feel without making the playable character mushy — tuned at M3.
- **Pixel crispness vs. MSAA/DOF:** keep sprite nearest-filtering; confirm MSAA/DOF don't muddy pixels; adjust at M3.

## Out-of-Scope Follow-ups (future specs)

- Battle scene reusing the rig.
- Asset-quality upgrade pass via Meowa (normal maps for terrain, more props, environment art).
- Gameplay systems.
