# CB Character Animation + World Systems — As-Built

**Date:** 2026-06-14
**Status:** Implemented
**Goal:** Bring the game to a complete Cassette-Beasts feel — animated characters in all 8 directions, animated NPCs/monsters, day/night, and animated battle.

## Implemented

**8-direction animated player (`Player.gd`, `assets/sprites/hero_walk/`)**
- 8 facing sheets: 4 cardinals via Meowa `pixel_char_1` `direction` config (one fixed character description for consistency) + 2 generated diagonals + 2 mirrored.
- Per facing, a 6-frame walk-cycle spritesheet via `animate-run` (768×128).
- Player is an 8-direction animated billboard: facing from `round(atan2(vx,vz)/45°)`, 6-frame walk while moving, idle = frame 0.

**Day/night cycle (`DayNightCycle.gd`)**
- Drives the field sun + environment over a normalized time-of-day (150s/cycle): dawn gold, noon cool-white, dusk gold, night blue. Animates sun colour/energy/elevation, ambient colour/energy, fog colour, sky brightness, exposure. Yaw stays front-lit so billboards stay readable; the lamp accent light glows at night. `DAY_TIME` env pins a time.

**Animated NPCs (`AnimatedBillboard.gd`)**
- Reusable billboard that loops a horizontal spritesheet. Elder/merchant use generated 4-frame idle sheets, desynced.

**Roaming monsters (`Monster.gd`)**
- Wander the meadow with generated 6-frame walk animations (wolf/goblin), flip to face travel, sit on terrain height, and start a battle on contact (CB touch encounter, with spawn grace).

**Animated battle combatants (`Battle.gd`)**
- `_place` uses `AnimatedBillboard`: party loop 4-frame idle sheets, enemies use 6-frame walk sheets (falls back to static billboard if no sheet).

## Meowa pipeline notes
- API exposes 4 `direction` values (front/left/right/back); 8 facings built from those + 2 diagonal prompts + mirroring.
- `animate-run --output-format spritesheet --is-pixel` → horizontal N-frame sheet (frame = sheet_w / frames). Used for all walk/idle animations.
- Long prompts overflow the local download path → use short prompts (`"walk"`, `"idle"`).

## Verification
Factory value-test PASS; Title→Field→Battle boot clean under xvfb+vulkan; player walk verified in-engine (NE, W); day/night verified at dawn/noon/dusk/night; battle renders animated combatants.

## The full CB program (A–D + animation), all on `main`
A lighting signature + lit sprites · B grass+wind · C tiered terrain · D cliffs/clouds/water · 8-direction animated player · day/night · animated NPCs · roaming monsters · animated battle.
