# Spinning Top Maze

Top-down maze game for Godot 4.7.2: launch a spinning top with timing skill, steer it with device tilt (or keyboard / drag), keep spin power up while navigating procedurally generated mazes wave by wave. Visuals are code-generated: vector `_draw()` for entities and HUD, plus cached procedural `ImageTexture` floors for the play area (no downloaded image assets).

**Live:** [mhaiprojects.github.io/Spinning-Top-Maze](https://mhaiprojects.github.io/Spinning-Top-Maze/)  
**Repo:** [github.com/mhaiprojects/Spinning-Top-Maze](https://github.com/mhaiprojects/Spinning-Top-Maze)

## How to play

1. **Launch** — A marker slides along a bar. Tap, click, or press Space when it is near the centre for maximum starting spin (100). Edges give minimum power (~25).
2. **Steer** — Tilt your phone or use keyboard / drag so the top is pushed through corridors toward the green goal pad at the top of the maze.
3. **Spin power** — Drains slowly and drops on wall hits. At 0 the top falls over; choose **Retry** to replay the wave (launch mini-game again).
4. **Goal** — Reach the landing pad to clear the wave. A **Wave N cleared!** overlay appears with **Next Wave** (click/tap, **Space**, or **Enter**). The next wave uses a larger, denser maze and the launch mini-game again.
5. **Fell over** — **Retry** on the overlay restarts the **same** wave number with a **new maze seed** (launch mini-game again).

## Difficulty ramp

Wave parameters are centralized in `scripts/difficulty.gd` (`params_for_wave`). Wave 1 stays easy; grid size, wall density, spin decay, launch marker speed, sweet-spot width, wall-hit loss, and optional maze hazards all ramp with the wave (capped for 720×1280 portrait). The HUD shows **Wave N** and a star rating.

Regenerate this table:

```bash
godot --headless --path . --script res://tests/difficulty_table.gd
```

| Wave | Grid | Cells | Hit mult | Decay | Marker spd | Sweet spot | Hazards | Label |
|------|------|-------|----------|-------|------------|------------|-----------|-------|
| 1 | 3x4 | 12 | 1.00 | 2.20 | 1.45 | 20% | 0 | Easy |
| 2 | 3x5 | 15 | 1.06 | 2.32 | 1.53 | 19% | 0 | Easy+ |
| 3 | 4x6 | 24 | 1.12 | 2.44 | 1.61 | 18% | 0 | Medium |
| 4 | 5x7 | 35 | 1.18 | 2.56 | 1.69 | 18% | 0 | Medium+ |
| 5 | 6x8 | 48 | 1.24 | 2.68 | 1.77 | 17% | 1 | Hard |
| 6 | 6x9 | 54 | 1.30 | 2.80 | 1.85 | 16% | 1 | Hard+ |
| 7 | 7x10 | 70 | 1.36 | 2.92 | 1.93 | 15% | 2 | Expert |
| 8 | 8x11 | 88 | 1.42 | 3.04 | 2.01 | 14% | 2 | Expert+ |
| 9 | 9x12 | 108 | 1.48 | 3.16 | 2.09 | 14% | 3 | Master |
| 10 | 10x14 | 140 | 1.54 | 3.28 | 2.17 | 13% | 3 | Master+ |

## Controls

### Input modes (pick one primary steer mode)

| Mode | How it steers | Best on |
|------|----------------|---------|
| **Mouse** | Top is pulled toward the cursor; strength grows with distance (dead zone near the top) | Desktop |
| **Keyboard** | Arrow keys + WASD | Desktop / all |
| **Drag** | Touch or hold left mouse and drag (virtual stick); vector clamped to length 1 | Phones, tablets, touch laptops |
| **Tilt** | Device orientation / accelerometer (web: JS `deviceorientation` / `devicemotion`; native: `Input.get_accelerometer()`) | Phones / tablets |

**Switch mode:** HUD button **Input: … [M]** or press **M** / **Tab** to cycle Mouse → Keyboard → Drag → Tilt. Choice is saved in `user://settings.cfg`.

### Play-area boards

The maze floor and wall colours follow a selectable **board** theme (procedural texture, cached per size):

| Board | Look |
|-------|------|
| **Tabletop** (default) | Warm honey/oak wood grain |
| **Chopping** | End-grain butcher block with light knife scratches |
| **Planks** | Long boards with seams and nail heads |
| **Stone** | Grey carved stone with subtle cracks |

**Switch board:** HUD button **Board: … [B]** or press **B** to cycle Tabletop → Chopping → Planks → Stone. Applies immediately (no wave restart). Stored as `[visual] background = <0–3>` in the same `user://settings.cfg` as input mode (merge save — changing one does not erase the other).

**Defaults (no saved file):** **Tilt** on mobile / touch Web when sensors are likely available; **Drag** on touch without sensors; **Mouse** on desktop.

**Tilt fallback:** If Tilt is selected but permission is denied or no sensor events arrive within ~1.5 s, a HUD message appears (*“Tilt unavailable — using Drag/Mouse”*). The label still shows **Tilt**; steering uses **Drag** (touch) or **Mouse** (desktop).

**Keyboard override:** Arrow keys / WASD always override the selected mode (documented for accessibility).

**iOS 13+ Web:** Choosing **Tilt** or the first launch tap calls `window.stmRequestTilt()` / `DeviceOrientationEvent.requestPermission()` (must be from a user gesture).

**Calibrate** (Tilt selected): stores current tilt as zero offset.

| Action | Input |
|--------|--------|
| Launch release | Tap / click / **Space** (works in every mode; launch taps ignore steering) |
| Pause / Retry | HUD buttons |

HUD: **Input mode**, **Board theme**, **Settings**, **Calibrate** (Tilt), **Pause**, **Retry**, power bar, wave label, status line.

### Physics settings (in-game)

Open **Settings** on the HUD (pauses play, blocks steering). Adjust sliders or type in the numeric fields; **Reset** per row or **Reset all**; **Close** or **Escape** saves to `user://settings.cfg` under `[physics]` with `physics_version` (other sections are preserved). On Web, `[physics]` is also mirrored to `localStorage` key `stm_physics`. Older saves without a version auto-migrate only unchanged legacy defaults for tilt response, sensitivity, and max lean.

| Key | Label (menu) | Default | Range | Role |
|-----|----------------|---------|-------|------|
| `tilt_response` | Tilt response | 3.0 | 0.5–4 | Frame-rate-independent input smoothing |
| `tilt_sensitivity` | Tilt sensitivity | 3.0 | 0.25–3 | Tilt input gain |
| `tilt_full_scale_deg` | Tilt full scale (deg) | 35 | 10–90 | Device angle mapped to full deflection |
| `lean_max_deg` | Max lean (deg) | 45 | 5–60 | Max top lean (steer + visuals) |
| `lean_stiffness` | Lean stiffness | 10 | 1–30 | How fast lean follows input |
| `precession_rate` | Precession rate | 2.5 | 0–10 | Gyroscopic wobble (faster when spin is low) |
| `low_scale` | Gentle tier scale | 0.35 | 0.05–1.5 | Movement scale for light input |
| `high_scale` | Hard tier scale | 1.6 | 0.5–4 | Movement scale for strong input (full input drives up to high_scale × steer_force) |
| `tier_threshold` | Tier threshold | 0.5 | 0.1–0.9 | Input magnitude where tiers blend |
| `tier_blend` | Tier blend width | 0.18 | 0.02–0.4 | Smoothstep width at tier cross |
| `steer_force` | Steer force | 480 | 100–1500 | Central force at full lean |
| `max_speed` | Max speed | 520 | 150–1500 | Linear speed cap |
| `linear_damp` | Linear damp | 2.2 | 0–8 | Rigid-body linear damping |
| `spin_decay_mult` | Spin decay mult | 1.0 | 0–3 | Multiplier on wave spin decay |
| `wall_hit_slowdown` | Wall hit slowdown | 0.6 | 0.1–1 | Velocity kept after a wall hit |
| `wall_hit_loss_mult` | Wall hit loss mult | 1.0 | 0–3 | Multiplier on wall power loss |
| `fall_threshold` | Fall threshold (%) | 0 | 0–40 | Fall when power ≤ threshold (0 = off) |

Code: `scripts/physics_settings.gd` (tunables + save/load), `scripts/top_physics.gd` (tiers / lean math), `scripts/physics_menu.gd` (UI).

## Run locally

```bash
godot --path .
```

Headless import check:

```bash
timeout 120 godot --headless --path . --import --quit
```

Tests (exit 0 = all pass):

```bash
timeout 300 godot --headless --path . --script res://tests/test_runner.gd
```

Web export (requires export templates 4.7.2):

```bash
godot --headless --path . --export-release "Web" build/web/index.html
```

## Project structure

| Path | Role |
|------|------|
| `scenes/main.tscn` | Root scene (`main.gd` + `game_ui.gd`) |
| `scripts/maze_gen.gd` | Procedural mazes, BFS path check, density helpers |
| `scripts/launch_math.gd` | Launch power mapping (`power_for_offset`) |
| `scripts/launch_minigame.gd` | Pre-run timing mini-game |
| `scripts/spinning_top.gd` | `RigidBody2D` top, power, wall hits, `_draw()` |
| `scripts/maze_world.gd` | Wall bodies + maze drawing |
| `scripts/input_modes.gd` | Pure logic: mode cycle, defaults, steer vectors, save/load |
| `scripts/tilt_input.gd` | Autoload: four modes + keyboard override / web tilt |
| `scripts/physics_settings.gd` | Central physics tunables, `[physics]` persistence |
| `scripts/top_physics.gd` | Tier shaping, lean spring, precession helpers |
| `scripts/physics_menu.gd` | In-game Settings panel |
| `scripts/drag_stick_overlay.gd` | On-screen virtual stick while dragging |
| `scripts/difficulty.gd` | Per-wave maze and gameplay tuning |
| `scripts/visual_theme.gd` | HUD/overlay StyleBox helpers |
| `scripts/main.gd` | Wave flow and game phases |
| `scripts/game_ui.gd` | CanvasLayer HUD and overlays |
| `tests/test_runner.gd` | Headless test suite |
| `tests/difficulty_table.gd` | Prints waves 1–10 difficulty table |
| `tests/screenshot.gd` | GUI shots; `--flow` on `DISPLAY=:2` |
| `export_presets.cfg` | Web preset (`build/web/index.html`, no threads) |
| `.github/workflows/deploy-web.yml` | GitHub Pages deploy on `main` |

## Development

This repo was built with Cursor Agent. To continue the same thread:

```bash
cursor-agent -p --trust --resume e8277a71-7e00-46e6-88a4-24f531b272f6 "<request>"
```

Chat ID: `e8277a71-7e00-46e6-88a4-24f531b272f6`