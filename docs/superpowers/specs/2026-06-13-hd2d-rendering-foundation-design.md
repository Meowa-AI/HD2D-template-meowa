# HD-2D Rendering Foundation — Design (v2)

**Date:** 2026-06-13
**Status:** Draft v2 (awaiting review)
**Goal:** Raise the game's art to OCTOPATH TRAVELER ("HD-2D") quality by aligning asset pixel density and elevating + centralizing the existing render rig.

> v2 supersedes v1. v1 assumed an empty project and a from-scratch Field stub. That was based on a stale snapshot — the project was being built by another process concurrently. This version is grounded in the **actual current code**.

## Corrected Current State (verified against code)

The vertical slice **already exists and runs**: `Title.tscn → Field.tscn → Battle.tscn`, with autoloads `GameData` / `Audio` / `SceneManager`.

- `scripts/Field.gd` already builds a full HD-2D scene **inline**: environment (`_build_environment`, lines 45–82: BG_SKY procedural sky, FILMIC tonemap exp 1.05, glow 0.45 / bloom 0.18 / softlight / HDR thr 0.95, fog density 0.005 + aerial 0.3, adjustments contrast 1.08 / saturation 1.18), a shadow-casting sun (`_build_light`, 84–91), ground + winding path, ~80 perimeter trees + props + NPCs, grass encounter zones, dialogue UI, and a **DOF follow-camera** (`_build_camera`, 278–293: fov 46, `CameraAttributesPractical` near+far blur, amount 0.08).
- `scripts/Player.gd` already has movement, facing-flip, and a fake walk-bob.
- `scripts/Battle.gd` (32 KB) and `scripts/Title.gd` exist and are wired (`Field.gd:421-422` transitions to `Battle.tscn`; `project.godot` main scene is `Title.tscn`).
- `scripts/SceneManager.gd:22-34` already has an **offscreen screenshot hook**: env `SHOT_OUT` (+ optional `SHOT_FRAMES`) captures a frame to PNG and quits. This is the visual-verification path.
- Assets now include `assets/sprites/props/*` (trees, bush, rock, barrel, crate, fence, lamp, well, signpost, chest), `npc_elder/merchant`, plus the party + enemies.

So this is **not greenfield**. The work is three things on existing code:
1. **Align asset pixel density** to OCTOPATH (assets are full-detail, not chunky, and inconsistent across classes).
2. **Extract the inline rig** into shared reusable units so Field and Battle share one tuned look (no parallel rig).
3. **Elevate that look** to OCTOPATH grade, verifying via the existing `SHOT_OUT` hook.

## Goals

1. Field (primary showcase) reads as OCTOPATH-grade HD-2D.
2. The render rig (environment grade, lighting, DOF camera, atmosphere) lives in shared factories that both Field and Battle consume.
3. Character/prop assets share one OCTOPATH-aligned pixel density.
4. Title → Field → Battle all still run end-to-end after the changes.

## Non-Goals

- Gameplay changes (movement, encounter rules, dialogue, battle combat logic/layout). Battle **inherits the shared rig's params** but its combat is not redesigned here.
- Full asset-library regeneration. In scope now: the 4 party sprites + a density policy applied to props/NPCs/enemies. Net-new environment art is later.
- Title screen redesign (must keep working; not a polish target).

## Target Look — Decomposition

| Layer | OCTOPATH signature | Godot 4.6 mechanism | Already present? |
|---|---|---|---|
| Depth of field | tilt-shift "miniature" | `CameraAttributesPractical` near+far | ✅ yes (amount 0.08 — likely under-tuned) |
| Camera | telephoto compression, ¾ angle | low FOV, follow | ⚠️ fov 46 (wide-ish; OCTOPATH flatter ~28–35) |
| Bloom | strong overexposed glow | `Environment` glow | ✅ yes (intensity 0.45 — tune) |
| Tonemap & grading | high saturation, filmic | FILMIC + adjustments | ✅ yes (sat 1.18 — tune) |
| Atmosphere | depth fog, god rays, dust | fog + `GPUParticles3D` | ⚠️ fog yes; dust/rays no |
| Lighting | scene-tinted sprites, cast shadows | dir light + colored omni | ⚠️ sun+shadows yes; accent omni no; sprite shading inconsistent |
| Diorama depth | layered 2D-in-3D, parallax | backdrop + mid + foreground | ⚠️ trees ring yes; far backdrop / fg-blur frame no |
| Sprites | chunky hand-drawn pixel | 128px billboards at uniform density | ❌ assets too dense + inconsistent |

The grade already exists and is decent — the gap to OCTOPATH is **tuning + a few missing layers + asset density**, not building from zero.

## Asset Standard (locked) — density + uniform grain

OCTOPATH's tell is one **uniform pixel grain** across the whole frame. Audit of current assets:

| Class | Canvas | native-block | px-per-world-unit (≈) |
|---|---|---|---|
| Party / NPC | 256×256 | 1 (full detail) | ~107 (hero @2.4u, body ~232px) |
| Props | 64×64 | 1 (full detail) | ~53 (barrel @1.2u) |

Two problems: (a) far denser than OCTOPATH's chunky grain; (b) party grain ≈ **2× props grain** — non-uniform.

Locked standard:

| Item | Value | Rationale |
|---|---|---|
| Character frame canvas | **128×128 px** | matches OCTOPATH character sprites |
| Character body height | **~72 px** (64–80) | OCTOPATH chunky density |
| Internal upscaling | **none — 1:1 native** (block = 1) | real grain |
| **Uniform target density** | **~36–44 px per world unit, shared by ALL billboards** (chars, NPCs, props) | uniform grain is the HD-2D tell; per-class canvas is sized from its world height to hit this |
| Render | integer scale + nearest filter | crisp |
| Enemies | higher-res 2D illustration + pixel-style filter, **not** 128px pixel art | mirrors OCTOPATH (enemies aren't true pixel art) |

Code note: `HD2D.character()` already derives `pixel_size` from `texture.get_height()` (`HD2D.gd:22-25`); the `256` is only a fallback default. So aligning density is mostly **new textures at the right canvas + chosen world heights**, not code — the fallback can simply track the standard.

Sources: character canvas 128×128 — Aviakesh sprite breakdown (single-source, medium-high confidence); enemies-not-pixel-art — community measurement (GameFAQs); HD-2D — Wikipedia. The Spriters Resource corroborates but was 403 at spec time.

## Architecture & Migration Path (no parallel rig)

The rig is currently **inline in `Field.gd`**. We extract — not re-invent — those exact blocks:

| New unit | Built from | Consumers |
|---|---|---|
| `scripts/HD2DEnvironment.gd` → `environment()` | move `Field.gd._build_environment` body verbatim, then tune | Field, Battle |
| `scripts/HD2DStage.gd` → `camera()` | move `Field.gd._build_camera` (DOF attrs) | Field, Battle |
| `scripts/HD2DStage.gd` → `key_light()` | move `Field.gd._build_light` | Field, Battle |
| `scripts/HD2DStage.gd` → `accent_light()`, `dust()`, `backdrop()`, `foreground_frame()` | **new** atmosphere layers | Field (Battle optional) |
| `scripts/HD2D.gd` (existing) | keep `character()/blob_shadow()/ground()`; reconcile sprite shading (see Open Qs) | all |

Migration is **behavior-preserving first**: move values verbatim so the screenshot before/after matches, *then* tune centrally. `Battle.gd` is switched to call the same factories (replacing whatever rig it builds inline) so the two scenes can never drift. Explicitly: do **not** leave a second copy of env/camera/light values anywhere.

## Verification Method (corrected)

Visual QA needs a real GPU context; `--headless` only reaches resource load. Fresh checkouts have no display, so **xvfb is required**:

```
SHOT_OUT=/tmp/field.png SHOT_FRAMES=120 \
  xvfb-run -a ~/.local/bin/godot --path . --rendering-driver vulkan \
  res://scenes/Field.tscn
```

- Targets the scene via positional arg / `--scene`, so we **never edit `project.godot`** to iterate, and the real main scene stays `Title.tscn`.
- Reuses the existing `SHOT_OUT`/`SHOT_FRAMES` hook in `SceneManager.gd`.
- Same command with `res://scenes/Battle.tscn` for battle parity, and run `Title.tscn` once per milestone to confirm the full flow still boots.
- `--headless` is used only for parse/load smoke checks, never as visual sign-off.

## CLI Class-Cache Caveat (point 5)

`Field.gd` / `Player.gd` reference the global class `HD2D` (`class_name HD2D`). On a **fresh repo with no `.godot/` cache**, `godot --check-only --script res://scripts/Field.gd` fails with `Identifier "HD2D" not declared` because the global-class registry hasn't been built.

Mitigations (spec mandates both):
1. **Prerequisite import/cache pass** before any CLI script check: `xvfb-run -a ~/.local/bin/godot --path . --import` (or one `--editor --quit`) to populate `.godot/global_script_class_cache.cfg`.
2. In **new or edited** scripts, reference HD2D via explicit `preload("res://scripts/HD2D.gd")` rather than relying on the ambient `class_name`, so checks are robust even pre-cache.

## Milestones (on existing code; each ends in a screenshot + commit)

- **M0 — Asset density alignment:** regenerate 4 party sprites @128 / ~72px / 1:1 via the `game-assets` (Meowa) skill; set props/NPC canvas to hit the uniform ~36–44 px/unit target; decide enemy route; replace files; re-audit with the density script.
- **M1 — Rig extraction (behavior-preserving):** create `HD2DEnvironment.gd` + `HD2DStage.gd` from the inline Field blocks; Field + Battle consume them. Screenshot must match pre-refactor (no visual regression). Run import pass first (caveat above).
- **M2 — Grade elevation:** tune DOF (stronger tilt-shift), FOV (~28–35), glow, fog, saturation toward OCTOPATH; add `GPUParticles3D` dust + a distant backdrop plane + a foreground out-of-focus frame; add an accent omni light; reconcile sprite shading. Screenshot-iterate against OCTOPATH reference.
- **M3 — Battle parity:** confirm Battle renders through the shared rig and reads consistently; tune the battle camera distance/angle only.
- **M4 — Polish + full-flow run:** Title→Field→Battle all boot under xvfb; document the final tuned values in this spec.

## Open Questions (resolved during implementation, non-blocking)

- **Sprite shading consistency:** props use `HD2D.character(..., shaded=true)` (scene-tinted); the player uses the `shaded=false` default (self-lit). Pick one policy (likely: characters unlit-but-graded for readability, environment props lit) and apply uniformly.
- **Exact uniform density** (36 vs 44 px/unit): pick by A/B screenshot at M0.
- **DOF/FOV target:** strong enough for the miniature feel without making the playable character mushy — M2.
- **Enemy illustration route timing:** this slice, or deferred with current enemies as placeholders.

## Out-of-Scope Follow-ups (future specs)

- Battle combat/layout redesign.
- Net-new environment art + normal-mapped terrain via Meowa.
- Additional characters / jobs / animation frames.
