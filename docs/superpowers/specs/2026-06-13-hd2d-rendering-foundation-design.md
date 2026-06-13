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
- Full asset-library regeneration. In scope now: the 4 party sprites + the 36 px/unit density policy applied to props/NPCs. **Enemies stay as placeholders this slice** (their dedicated illustration route is deferred). Net-new environment art is later.
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
| **Uniform target density** | **36 px per world unit, shared by ALL billboards** (chars, NPCs, props) | uniform grain is the HD-2D tell. 72px body ÷ 36 = 2.0 world units tall — matches current scene scale; 44 would give ~1.64u (too small, grain too fine). Per-class canvas is sized from its world height to hit 36 |
| Render | integer scale + nearest filter | crisp |
| Enemies | higher-res 2D illustration + pixel-style filter, **not** 128px pixel art | mirrors OCTOPATH (enemies aren't true pixel art) |

Code note: `HD2D.character()` already derives `pixel_size` from `texture.get_height()` (`HD2D.gd:22-25`); the `256` is only a fallback default. So aligning density is mostly **new textures at the right canvas + chosen world heights**, not code — the fallback can simply track the standard.

Sources: character canvas 128×128 — Aviakesh sprite breakdown (single-source, medium-high confidence); enemies-not-pixel-art — community measurement (GameFAQs); HD-2D — Wikipedia. The Spriters Resource corroborates but was 403 at spec time.

## Architecture & Migration Path (no parallel rig, profile-parameterized)

Both `Field.gd` and `Battle.gd` already build their **own** inline rigs with **scene-appropriate, genuinely different values** (verified):

| | Field (`Field.gd`) | Battle (`Battle.gd`) |
|---|---|---|
| Env background | `BG_SKY` + procedural sky + fog | `BG_COLOR` (0.04,0.05,0.08), no fog |
| Ambient | sky source, energy 0.9 | color source (0.7,0.72,0.8), energy 1.1 |
| Glow / sat | 0.45 / 1.18 | 0.50 / 1.12 |
| Sun | rot (−52,−130), energy 1.15, shadows on | rot (−50,−120), energy 1.0 |
| Camera | **follow**, fov 46, near+far DOF | **fixed** (0,6.4,13.5)→(0,2.4,−2), fov 42, **far-only** DOF |
| Backdrop | none (tree ring) | painted quad `battle_bg.jpg` 46×26 @ (0,9,−16) |

So the unit of sharing is the **factory + a scene `profile`**, NOT a single value set. The factory holds the structure; each profile (`"field"` / `"battle"`) supplies that scene's current values so M1 reproduces both looks exactly.

| New unit | Signature / behavior | Built from | Consumers |
|---|---|---|---|
| `scripts/HD2DEnvironment.gd` | `environment(profile := "field") -> Environment` — **returns the resource only**; the caller wraps it in `WorldEnvironment` and `add_child`s | `Field._build_environment` + `Battle._build_world` env blocks → two profiles | Field, Battle |
| `scripts/HD2DStage.gd` | `key_light(profile) -> DirectionalLight3D` | `Field._build_light` + Battle sun | Field, Battle |
| `scripts/HD2DStage.gd` | `make_camera(profile) -> Camera3D` + `apply_dof(camera, profile)` — **no follow/update logic inside** | `Field._build_camera` + `Battle._build_camera` (DOF attrs) | Field, Battle |
| `scripts/HD2DStage.gd` | `backdrop(profile/params)` — Battle's existing quad migrates here in M1 | `Battle._build_world` backdrop block | Battle (M1); Field far backdrop is **new in M2** |
| `scripts/HD2DStage.gd` | `dust()`, `accent_light()`, `foreground_frame()` — **new** atmosphere layers | new | Field (M2); Battle optional |
| `scripts/HD2D.gd` (existing) | keep `character()/blob_shadow()/ground()`; may add a `billboard()` alias + a density constant — **no large refactor** | unchanged | all |

**Camera follow stays in the scene.** Field's follow/update lives in `Field.gd:345` (`_process` lerp) and must remain there; Battle's camera is fixed (`Battle.gd:222`). The factory only *constructs* the camera + DOF from a profile; runtime motion is the scene's job.

Migration is **behavior-preserving**: M1 extracts structure into the factories and routes both scenes through profiles that emit their *current* values — neither scene's look changes. Tuning happens later (M2+), centrally, by editing the profiles. Explicitly: do **not** impose Field's numbers on Battle, and do **not** leave a second copy of any rig block inline after extraction.

## Verification Method (corrected)

Visual QA needs a real GPU context; `--headless` only reaches resource load. Fresh checkouts have no display, so **xvfb is required**:

```
SHOT_OUT=/tmp/field.png SHOT_FRAMES=120 \
  xvfb-run -a ~/.local/bin/godot --path . --rendering-driver vulkan \
  --scene res://scenes/Field.tscn
```

- Targets the scene with the official `--scene` flag (not a positional arg), so we **never edit `project.godot`** to iterate, and the real main scene stays `Title.tscn`.
- Reuses the existing `SHOT_OUT`/`SHOT_FRAMES` hook in `SceneManager.gd`.
- Same command with `--scene res://scenes/Battle.tscn` for battle parity, and `--scene res://scenes/Title.tscn` once per milestone to confirm the full flow still boots.
- `--headless` is used only for parse/load smoke checks, never as visual sign-off.

## CLI Class-Cache Caveat (point 5)

`Field.gd` / `Player.gd` reference the global class `HD2D` (`class_name HD2D`). On a **fresh repo with no `.godot/` cache**, `godot --check-only --script res://scripts/Field.gd` fails with `Identifier "HD2D" not declared` because the global-class registry hasn't been built.

Mitigations (spec mandates both):
1. **Prerequisite import/cache pass** before any CLI script check: `xvfb-run -a ~/.local/bin/godot --path . --import` (or one `--editor --quit`) to populate `.godot/global_script_class_cache.cfg`.
2. In **new or edited** scripts, reference HD2D via explicit `preload("res://scripts/HD2D.gd")` rather than relying on the ambient `class_name`, so checks are robust even pre-cache.

## Milestones (on existing code; each ends in a screenshot + commit)

- **M0 — Asset density alignment:** regenerate 4 party sprites @128 / ~72px / 1:1 via the `game-assets` (Meowa) skill; size props/NPC canvas to hit the uniform **36 px/unit** target; replace files; re-audit with the density script. **Then capture a fresh post-M0 baseline screenshot** — this becomes the reference M1 must preserve.
- **M1 — Rig extraction (behavior-preserving):** create `HD2DEnvironment.gd` + `HD2DStage.gd` with `"field"`/`"battle"` profiles emitting each scene's *current* values; route Field **and** Battle through them (Battle's backdrop migrates too). Field and Battle screenshots must each match the **post-M0** baseline — no visual change from the refactor. Run the `--import` pass first (caveat above).
- **M2 — Grade elevation:** tune the **profiles** (Field first) toward OCTOPATH — stronger tilt-shift DOF, flatter FOV (~28–35), glow, fog, saturation; add `GPUParticles3D` dust + a distant Field backdrop + a foreground out-of-focus frame + an accent omni light; reconcile the one shading inconsistency (Field props `shaded=true` vs unlit elsewhere). Screenshot-iterate against OCTOPATH reference.
- **M3 — Battle parity:** with the shared rig in place, adjust only the **battle profile's** camera/layout so Battle reads consistently. Do **not** reverse-edit the shared grade or the field profile. Confirm the placeholder enemies don't look jarring under the shared rig.
- **M4 — Polish + full-flow run:** Title→Field→Battle all boot under xvfb; document the final tuned profile values in this spec.

## Decisions (locked)

- **Uniform density = 36 px/unit** (see Asset Standard). Not an open question anymore.
- **Enemies: placeholder this slice.** The HD/illustration route is a *separate* asset pipeline (touches Battle composition, alpha edges, pixel-filter, UI readability) — not the M0 pixel-density fix. This spec only reserves the interface/profile; M3 just ensures the current enemy sprites don't look jarring under the shared rig. Full enemy art is a later spec.

## Open Questions (resolved during implementation, non-blocking)

- **Sprite shading consistency:** the only inconsistency is **Field props** (`HD2D.character(..., shaded=true)`, scene-tinted) vs everything else unlit (Field player and *all* Battle sprites use `shaded=false`). Pick one policy at M2 (likely: characters unlit-but-graded for readability; environment props may stay lit) and apply deliberately.
- **DOF/FOV target:** strong enough for the miniature feel without making the playable character mushy — tuned in the field profile at M2.

## Out-of-Scope Follow-ups (future specs)

- Battle combat/layout redesign.
- Net-new environment art + normal-mapped terrain via Meowa.
- Additional characters / jobs / animation frames.

---

## Final tuned values (M4)

Implemented and verified (Title→Field→Battle all boot under `xvfb` + Vulkan/Forward+, no script errors). The rig lives in `scripts/HD2DEnvironment.gd` + `scripts/HD2DStage.gd`, parameterized by profile; the factory value-test `tests/test_hd2d_factories.gd` guards these numbers.

**Asset density (M0):** party sprites regenerated via Meowa `pixel_char_1` at 128×128 canvas (native pixel, ~half the old 256px density), `world_height` 2.4 unchanged. Enemies remain placeholders.

**Field profile:**
- Camera: FOV **30** (telephoto); follow offset `(0, 10.5, 18)`, look `(0, 1.6, 0)` in `Field.gd`.
- DOF (tilt-shift): far enabled dist 26 / transition 5; near enabled dist 16.5 / transition 5; amount **0.34**.
- Environment: `BG_SKY` + procedural sky; ambient sky 0.9; FILMIC exp 1.05; glow 0.5 / bloom 0.2 / softlight / hdr_threshold 1.0; fog density 0.004 / aerial 0.35; adjustments brightness 1.0 / contrast 1.15 / saturation 1.32.
- Key light: warm `(1.0,0.94,0.82)` energy 1.15, shadows on, rot `(-52,-130,0)`.
- Atmosphere: `HD2DStage.dust(GROUND_SIZE)` + warm `accent_light((1.0,0.82,0.45), 5.0, (-6.5,2.6,9.0))`.
- Ground: richer lush seamless grass texture (Meowa `texture-gen-run`).

**Battle profile (parity, field grade untouched):**
- Camera: FOV 42, fixed `(0,6.4,13.5)`→`(0,2.4,-2)`; DOF far-only dist 19 / transition 6 / amount 0.12.
- Environment: `BG_COLOR (0.04,0.05,0.08)`; ambient color `(0.7,0.72,0.8)` energy 1.1; FILMIC; glow 0.55 / bloom 0.18 / hdr 1.0; saturation 1.22 / contrast 1.12; no fog.
- Key light: `(1.0,0.93,0.8)` energy 1.0, rot `(-50,-120,0)`. Backdrop: `battle_bg.jpg` 46×26 @ `(0,9,-16)`.

**Deferred (future specs):** ground normal map + path/dirt texture; enemy HD-illustration pipeline; props/NPC density pass to uniform 36 px/unit; net-new environment art.
