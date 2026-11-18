# Spinning Top Maze

Top-down maze game for Godot 4.7.2: launch a spinning top with timing skill, steer it with device tilt (or keyboard / drag), keep spin power up while navigating procedurally generated mazes wave by wave. All visuals are vector `_draw()` primitives — no image assets.

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

**Defaults (no saved file):** **Tilt** on mobile / touch Web when sensors are likely available; **Drag** on touch without sensors; **Mouse** on desktop.

**Tilt fallback:** If Tilt is selected but permission is denied or no sensor events arrive within ~1.5 s, a HUD message appears (*“Tilt unavailable — using Drag/Mouse”*). The label still shows **Tilt**; steering uses **Drag** (touch) or **Mouse** (desktop).

**Keyboard override:** Arrow keys / WASD always override the selected mode (documented for accessibility).

**iOS 13+ Web:** Choosing **Tilt** or the first launch tap calls `window.stmRequestTilt()` / `DeviceOrientationEvent.requestPermission()` (must be from a user gesture).

**Calibrate** (Tilt selected): stores current tilt as zero offset.

| Action | Input |
|--------|--------|
| Launch release | Tap / click / **Space** (works in every mode; launch taps ignore steering) |
| Pause / Retry | HUD buttons |

HUD: **Input mode**, **Calibrate** (Tilt), **Pause**, **Retry**, power bar, wave label, status line.

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