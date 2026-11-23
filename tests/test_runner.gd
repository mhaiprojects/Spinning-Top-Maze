extends SceneTree
## Headless tests. Run: godot --headless --path . --script res://tests/test_runner.gd

const Maze := preload("res://scripts/maze_gen.gd")
const Launch := preload("res://scripts/launch_math.gd")
const TopScript := preload("res://scripts/spinning_top.gd")
const TiltScript := preload("res://scripts/tilt_input.gd")
const MainScript := preload("res://scripts/main.gd")
const Difficulty := preload("res://scripts/difficulty.gd")
const InputModes := preload("res://scripts/input_modes.gd")
const PlayBg := preload("res://scripts/play_background.gd")
const UserSettings := preload("res://scripts/user_settings.gd")
const PhysicsSettings := preload("res://scripts/physics_settings.gd")
const TopPhysics := preload("res://scripts/top_physics.gd")
const PhysicsMenu := preload("res://scripts/physics_menu.gd")

const SETTINGS_TEST := "user://test_stm_settings.cfg"

var passed := 0
var failed := 0


func _initialize() -> void:
	_clear_settings_test()
	_bind_test_settings()
	await _run()
	_clear_settings_test()
	quit(1 if failed > 0 else 0)


func _clear_settings_test() -> void:
	if FileAccess.file_exists(SETTINGS_TEST):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_TEST))


func _bind_test_settings() -> void:
	var tin: Node = root.get_node_or_null("TiltInput")
	if tin and tin.has_method("set_settings_path"):
		tin.call("set_settings_path", SETTINGS_TEST)


func check(cond: bool, name: String) -> void:
	if cond:
		passed += 1
		print("  PASS  ", name)
	else:
		failed += 1
		print("  FAIL  ", name)


func _run() -> void:
	print("== Maze paths ==")
	test_maze_paths()
	print("== Maze no straight line to goal ==")
	test_maze_no_straight_line()
	print("== Top size ==")
	await test_top_size()
	print("== Goal single tile, no pull ==")
	await test_goal_single_tile_no_pull()
	print("== Maze density curve ==")
	test_density_monotonic()
	print("== Launch power mapping ==")
	test_launch_math()
	print("== Top collision power loss ==")
	test_wall_hit_capped()
	await test_top_wall_hit()
	await test_top_physics_wall_hit()
	await test_top_speed_cap()
	print("== Spin axis upright on tip ==")
	await test_spin_axis_upright()
	print("== Input modes ==")
	test_input_mode_logic()
	test_input_vectors()
	test_tilt_sign_mapping()
	test_mode_save_load()
	print("== Play backgrounds ==")
	test_play_backgrounds()
	await test_play_background_settings()
	print("== Tilt keyboard ==")
	test_tilt_keyboard()
	print("== Script load smoke ==")
	test_all_scripts_load()
	print("== Main scene ==")
	await test_main_scene()
	print("== Difficulty ramp ==")
	test_difficulty_ramp()
	print("== Playability flow ==")
	await test_playability_flow()
	print("== Wave overlay flow ==")
	await test_wave_overlay_flow()
	print("== Overlay centering ==")
	await test_overlay_centered()
	print("== Steer after idle ==")
	await test_steer_after_idle()
	print("== Real launch steering ==")
	await test_real_launch_steering()
	print("== Intro and goal fall ==")
	await test_intro_and_goal_fall()
	print("== Drag after board switch ==")
	await test_drag_after_background_switch()
	print("== Board key and button ==")
	await test_board_key_and_button()
	print("== Physics tunables ==")
	test_physics_defaults()
	test_physics_settings_migration()
	test_smooth_alpha_doubled()
	test_tilt_magnitude_preserved()
	test_tier_scales()
	test_lean_and_precession()
	test_physics_save_load()
	await test_physics_live_tuning()
	await test_physics_settings_menu()
	print("\nRESULT: %d passed, %d failed" % [passed, failed])


func test_difficulty_ramp() -> void:
	check(Difficulty.is_easy_wave_1(), "wave 1 is easy")
	var prev_cells := 0
	var prev_walls := 0.0
	for wave in range(1, 11):
		var p: Dictionary = Difficulty.params_for_wave(wave)
		if wave > 1:
			check(p.cells >= prev_cells, "wave %d cells >= prior" % wave)
		prev_cells = int(p.cells)
		for k in Difficulty.metric_keys_monotonic():
			var pk: float = float(Difficulty.params_for_wave(wave - 1).get(k, 0))
			var ck: float = float(p.get(k, 0))
			check(ck + 0.0001 >= pk, "wave %d %s monotonic" % [wave, k])
	for wave in range(1, 16):
		for seed in [3, 9, 17, 42, 99]:
			check(Maze.has_path(Maze.generate(wave, seed)), "path w%d seed %d" % [wave, seed])
	var avg_w1 := 0.0
	var avg_w10 := 0.0
	for s in [1, 2, 3, 5, 8, 13]:
		avg_w1 += Maze.wall_count(Maze.generate(1, s))
		avg_w10 += Maze.wall_count(Maze.generate(10, s))
	avg_w1 /= 6.0
	avg_w10 /= 6.0
	check(avg_w10 > avg_w1 + 5.0, "wall count ramp w1 %.0f -> w10 %.0f" % [avg_w1, avg_w10])
	check(avg_w1 >= 10.0, "wave 1 has readable maze walls (avg %.1f)" % avg_w1)


func test_maze_paths() -> void:
	for wave in range(1, 11):
		for seed in [1, 7, 42, 99, 12345, 555, 9001]:
			var data: Dictionary = Maze.generate(wave, seed)
			check(data.cols >= 3 and data.rows >= 4, "wave %d seed %d has grid" % [wave, seed])
			check(Maze.has_path(data), "wave %d seed %d path start->goal" % [wave, seed])
			check(data.start_cell.y == data.rows - 1, "start on bottom row w%d" % wave)
			check(data.goal_cell.y == 0, "goal on top row w%d" % wave)
			check(
				not data.room_walls[data.start_cell.y][data.start_cell.x][Maze.W_N],
				"start opens north w%d seed %d" % [wave, seed]
			)


func test_maze_no_straight_line() -> void:
	# Sanity: the detector flags an open start->goal column.
	var open := {
		"cols": 3, "rows": 4, "start_cell": Vector2i(1, 3), "goal_cell": Vector2i(1, 0),
		"room_walls": [],
	}
	for y in 4:
		var row: Array = []
		for x in 3:
			row.append([y == 0, x == 2, y == 3, x == 0])
		open.room_walls.append(row)
	check(Maze.has_straight_line(open), "detector flags unobstructed start/goal column")
	check(Maze.min_turns(open) == 0, "open column needs 0 turns")
	var total := 0
	for wave in range(1, 13):
		var need: int = Maze.min_turns_for(wave)
		var bad_path := 0
		var bad_line := 0
		var bad_turns := 0
		var bad_col := 0
		var bad_len := 0
		var min_seen := 999
		for i in 120:
			var seed: int = i * 104729 + wave * 31 + 7
			var d: Dictionary = Maze.generate(wave, seed)
			total += 1
			if not Maze.has_path(d):
				bad_path += 1
			if Maze.has_straight_line(d):
				bad_line += 1
			var t: int = Maze.min_turns(d)
			min_seen = mini(min_seen, t)
			if t < need:
				bad_turns += 1
			if d.start_cell.x == d.goal_cell.x:
				bad_col += 1
			if Maze.shortest_path_len(d) <= int(d.rows) - 1:
				bad_len += 1
		check(bad_path == 0, "w%d: BFS path exists in all 120 seeds" % wave)
		check(bad_line == 0, "w%d: no unobstructed straight row/column start->goal" % wave)
		check(bad_turns == 0, "w%d: every route needs >= %d turns (min seen %d)" % [wave, need, min_seen])
		check(bad_col == 0, "w%d: goal never in the start column" % wave)
		check(bad_len == 0, "w%d: shortest path longer than a straight run" % wave)
	check(total == 1440, "maze property sweep covered %d seeds" % total)
	var a: Dictionary = Maze.generate(5, 4242)
	var b: Dictionary = Maze.generate(5, 4242)
	check(a.room_walls == b.room_walls and a.goal_cell == b.goal_cell, "regeneration is deterministic per seed")


func test_top_size() -> void:
	check(is_equal_approx(SpinningTop.RADIUS, 46.0 * 0.7), "top radius 30%% smaller (%.1f)" % SpinningTop.RADIUS)
	var top: SpinningTop = TopScript.new()
	root.add_child(top)
	await process_frame
	var r := -1.0
	for c in top.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is CircleShape2D:
			r = ((c as CollisionShape2D).shape as CircleShape2D).radius
	check(is_equal_approx(r, SpinningTop.RADIUS), "collision radius matches art radius (%.1f)" % r)
	for wave in range(1, 11):
		var dims: Vector2i = Maze.grid_dims_for_wave(wave)
		var cell: float = minf(700.0 / float(dims.x), 912.0 / float(dims.y))
		var opening: float = cell - 15.6
		print("  fit w%d cell=%.0f opening=%.0f top_d=%.1f fits=%s" % [
			wave, cell, opening, SpinningTop.RADIUS * 2.0, opening > SpinningTop.RADIUS * 2.0])
	top.queue_free()
	await process_frame


func test_goal_single_tile_no_pull() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	for i in 20:
		await process_frame
	var main: Node = inst
	var top: SpinningTop = _find_main_child(main, SpinningTop) as SpinningTop
	var maze: MazeWorld = _find_main_child(main, MazeWorld) as MazeWorld
	var g: Rect2 = maze.goal_area_rect()
	var cell_c: Vector2 = maze.cell_center(maze.maze_data.goal_cell)
	var cell_c2: Vector2 = maze.cell_center(maze.maze_data.goal_cell + Vector2i(0, 1))
	var cell_sz: Vector2 = cell_c2 - cell_c
	check(absf(g.size.y - cell_sz.y) < 0.5 and g.get_center().distance_to(cell_c) < 0.5, "goal rect is exactly one tile")
	check(maze.goal_pad_rect().size.x < g.size.x and g.encloses(maze.goal_pad_rect()), "goal pad art inside the tile")
	check(maze.is_on_goal_tile(cell_c), "tile centre counts as on goal")
	check(not maze.is_on_goal_tile(g.position + Vector2(-2, g.size.y * 0.5)), "just left of tile is not goal")
	check(not maze.is_on_goal_tile(g.position + Vector2(g.size.x * 0.5, g.size.y + 2)), "just below tile is not goal")
	var tin: Node = root.get_node_or_null("TiltInput")
	if tin:
		_release_steer_inputs()
		tin.call("set_mode", InputModes.Mode.KEYBOARD)
		if tin.has_method("clear_test_steer_vector"):
			tin.call("clear_test_steer_vector")
	main.call("_begin_run", 95.0)
	for i in 5:
		await process_frame
	# Park the top on the neighbouring tile below; when that side is open, put it
	# so its edge overlaps the goal tile while its centre stays outside.
	var gc: Vector2i = maze.maze_data.goal_cell
	var near: Vector2 = cell_c2
	if not maze.maze_data.room_walls[gc.y][gc.x][Maze.W_S]:
		near = Vector2(g.get_center().x, g.end.y + SpinningTop.RADIUS * 0.6)
	top.reset_top(near, 95.0)
	top.set_run_active(true)
	main.set("phase", MainScript.Phase.RUN)
	var max_drift := 0.0
	for i in 90:
		await physics_frame
		max_drift = maxf(max_drift, top.global_position.distance_to(near))
	print("  goal-near probe steer=%s vel=%s pos=%s near=%s" % [
		tin.call("get_steer_vector") if tin else Vector2.ZERO, top.linear_velocity, top.global_position, near])
	check(int(main.get("phase")) == MainScript.Phase.RUN, "overlapping edge without centre on tile does not win")
	check(max_drift < 2.0, "no pull toward goal (drift %.2f px)" % max_drift)
	var inside: Vector2 = g.get_center() + Vector2(g.size.x * 0.3, 0)
	top.reset_top(inside, 95.0)
	top.set_run_active(true)
	for i in 3:
		await physics_frame
	check(int(main.get("phase")) == MainScript.Phase.GOAL_FALL, "centre on tile triggers win")
	var p_win: Vector2 = top.global_position
	for i in 30:
		await physics_frame
	check(top.global_position.distance_to(p_win) < 0.5, "victory spin-down stays in place, no glide to centre")
	for i in 60:
		await physics_frame
	check(int(main.get("phase")) == MainScript.Phase.CLEARED, "goal tile win clears wave")
	inst.queue_free()
	await process_frame


func test_density_monotonic() -> void:
	var seeds: Array = [1, 2, 3, 4, 5, 8, 13, 21, 34]
	for wave in range(1, 10):
		var avg_a := 0.0
		var avg_b := 0.0
		var dens_a := 0.0
		var dens_b := 0.0
		for s in seeds:
			var da: Dictionary = Maze.generate(wave, int(s))
			var db: Dictionary = Maze.generate(wave + 1, int(s))
			avg_a += Maze.wall_count(da)
			avg_b += Maze.wall_count(db)
			dens_a += Maze.density(da)
			dens_b += Maze.density(db)
		avg_a /= float(seeds.size())
		avg_b /= float(seeds.size())
		dens_a /= float(seeds.size())
		dens_b /= float(seeds.size())
		check(avg_b >= avg_a, "wave %d avg wall_count %.1f <= wave %d %.1f" % [wave, avg_a, wave + 1, avg_b])
		check(dens_b >= dens_a - 0.02 or avg_b > avg_a, "wave %d density metric tracks difficulty" % wave)


func test_launch_math() -> void:
	check(is_equal_approx(Launch.power_for_offset(0.0), 100.0), "centre is max power")
	check(is_equal_approx(Launch.power_for_offset(1.0), Launch.POWER_MIN), "edge is min power")
	check(is_equal_approx(Launch.power_for_offset(-0.5), Launch.power_for_offset(0.5)), "symmetric offset")
	var mid: float = Launch.power_for_offset(0.5)
	check(mid > Launch.POWER_MIN and mid < 100.0, "mid offset between min and max")
	check(Launch.power_for_offset(0.2) > Launch.power_for_offset(0.8), "monotonic with |offset|")
	check(is_equal_approx(Launch.power_for_offset(2.0), Launch.POWER_MIN), "clamped beyond 1")


func test_all_scripts_load() -> void:
	var paths: Array[String] = [
		"res://scripts/drag_stick_overlay.gd",
		"res://scripts/game_ui.gd",
		"res://scripts/input_modes.gd",
		"res://scripts/difficulty.gd",
		"res://scripts/difficulty_stars.gd",
		"res://scripts/play_background.gd",
		"res://scripts/user_settings.gd",
		"res://scripts/visual_theme.gd",
		"res://scripts/launch_math.gd",
		"res://scripts/launch_minigame.gd",
		"res://scripts/launch_intro.gd",
		"res://scripts/main.gd",
		"res://scripts/maze_gen.gd",
		"res://scripts/maze_world.gd",
		"res://scripts/spinning_top.gd",
		"res://scripts/tilt_input.gd",
		"res://scripts/physics_settings.gd",
		"res://scripts/top_physics.gd",
		"res://scripts/physics_menu.gd",
	]
	for p in paths:
		var res: Resource = load(p)
		check(res != null, "load script %s" % p)
		if res is Script:
			check((res as Script).can_instantiate(), "instantiate script %s" % p)
	var scene: PackedScene = load("res://scenes/main.tscn")
	check(scene != null and scene.can_instantiate(), "main.tscn can instantiate")


func test_wall_hit_capped() -> void:
	var top: SpinningTop = TopScript.new()
	root.add_child(top)
	await process_frame
	top.set_run_active(true)
	top.set_initial_power(100.0)
	var v0 := Vector2(300, 40)
	top.linear_velocity = v0
	top.apply_wall_hit(2000.0)
	check(top.spin_power >= 88.0, "extreme hit leaves >= 88 power")
	var p1: float = top.spin_power
	top.apply_wall_hit(2000.0)
	check(top.spin_power >= p1 - 0.01, "cooldown blocks stacked hit in same frame")
	top.set_initial_power(100.0)
	top.linear_velocity = v0
	for i in 20:
		await physics_frame
	top.apply_wall_hit(80.0)
	var speed_after: float = top.linear_velocity.length()
	check(speed_after < v0.length() - 5.0, "wall hit slows velocity")
	top.queue_free()
	await process_frame


func test_top_wall_hit() -> void:
	var top: SpinningTop = TopScript.new()
	root.add_child(top)
	await process_frame
	top.set_run_active(true)
	await process_frame
	top.set_initial_power(50.0)
	var p0: float = top.spin_power
	top.apply_wall_hit(10.0)
	check(top.spin_power < p0, "wall hit reduces power")
	top.set_initial_power(4.0)
	for i in 120:
		await physics_frame
	check(top.is_fallen() or top.spin_power <= 0.0, "decay to zero triggers fall")
	top.queue_free()
	await process_frame


func test_top_physics_wall_hit() -> void:
	var top: SpinningTop = TopScript.new()
	var wall := StaticBody2D.new()
	wall.add_to_group("maze_wall")
	wall.collision_layer = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 200)
	shape.shape = rect
	wall.add_child(shape)
	wall.position = Vector2(120, 0)
	root.add_child(wall)
	root.add_child(top)
	await process_frame
	top.set_run_active(true)
	await process_frame
	top.set_initial_power(80.0)
	top.position = Vector2(-80, 0)
	top.linear_velocity = Vector2(400, 0)
	var p0: float = top.spin_power
	for i in 45:
		await physics_frame
		if top.spin_power < p0 - 0.5:
			break
	check(top.spin_power < p0, "physics wall contact lowers spin power")
	top.queue_free()
	wall.queue_free()
	await process_frame


func test_spin_axis_upright() -> void:
	PhysicsSettings.reset_all()
	var top: SpinningTop = TopScript.new()
	var wall := StaticBody2D.new()
	wall.add_to_group("maze_wall")
	wall.collision_layer = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 400)
	shape.shape = rect
	wall.add_child(shape)
	wall.position = Vector2(420, 400)
	root.add_child(wall)
	root.add_child(top)
	await physics_frame
	top.set_run_active(true)
	top.set_initial_power(100.0)
	top.global_position = Vector2(200, 400)
	var tin: Node = root.get_node_or_null("TiltInput")
	if tin:
		if tin.has_method("set_steer_blocked"):
			tin.call("set_steer_blocked", false)
		if tin.has_method("set_test_steer_vector"):
			tin.call("set_test_steer_vector", Vector2(1, -0.3))
	var max_art := 0.0
	var max_tilt := 0.0
	var max_tip_drift := 0.0
	var a_prev: float = top.spin_angle()
	var advanced := 0.0
	for i in 240:
		await physics_frame
		var up_w: Vector2 = top.visual_up_world()
		max_art = maxf(max_art, absf(Vector2.UP.angle_to(up_w)))
		max_tilt = maxf(max_tilt, absf(top.visual_tilt()))
		# Where the drawn tip lands in world space vs the expected floor contact.
		var vt: Transform2D = top.visual_transform()
		var tip_w: Vector2 = top.global_transform * (vt * top.tip_local())
		# Tip sits straight below the body centre in world space (up to the lean shift).
		var expect_w: Vector2 = top.global_position + top.tip_local()
		max_tip_drift = maxf(max_tip_drift, (tip_w - expect_w).length())
		advanced += wrapf(top.spin_angle() - a_prev, -PI, PI)
		a_prev = top.spin_angle()
		if i % 60 == 59:
			print(
				"  SPIN t=%d rot=%.3f spin_rate=%.2f art_up=%s tilt=%.3f tip_w=%s pos=%s"
				% [i + 1, top.rotation, top.spin_rate(), up_w, top.visual_tilt(), tip_w,
					top.global_position]
			)
	if tin and tin.has_method("clear_test_steer_vector"):
		tin.call("clear_test_steer_vector")
	check(top.spin_rate() > 8.0, "spins about own vertical axis (%.1f rad/s)" % top.spin_rate())
	check(advanced > 30.0, "physics spin advances and drives stripes (%.1f rad)" % advanced)
	check(max_art < 0.6, "art stays upright on screen despite body spin (max %.3f rad)" % max_art)
	check(max_tilt > 0.05, "lean tilts the top around its tip (%.3f rad)" % max_tilt)
	check(top.tip_local().y > SpinningTop.RADIUS * 0.5, "pointy tip is the bottom pivot")
	check(
		max_tip_drift <= SpinningTop.RADIUS * 0.4,
		"drawn tip stays planted below the top while it spins (max drift %.1f px)" % max_tip_drift
	)
	top.queue_free()
	wall.queue_free()
	await process_frame


func test_top_speed_cap() -> void:
	var top: SpinningTop = TopScript.new()
	root.add_child(top)
	await physics_frame
	top.set_run_active(true)
	top.set_initial_power(100.0)
	top.global_position = Vector2(200, 400)
	var tin: Node = root.get_node_or_null("TiltInput")
	if tin:
		if tin.has_method("set_steer_blocked"):
			tin.call("set_steer_blocked", false)
		if tin.has_method("set_test_steer_vector"):
			tin.call("set_test_steer_vector", Vector2(0, -1))
	var peak := 0.0
	for i in 220:
		await physics_frame
		peak = maxf(peak, top.linear_velocity.length())
	check(peak > 90.0, "full steer reaches higher speed (peak %.0f)" % peak)
	check(peak <= TopScript.MAX_LINEAR_SPEED + 8.0, "speed capped at MAX_LINEAR_SPEED")
	if tin and tin.has_method("clear_test_steer_vector"):
		tin.call("clear_test_steer_vector")
	top.queue_free()
	await process_frame


func test_input_mode_logic() -> void:
	check(InputModes.next_mode(InputModes.Mode.TILT) == InputModes.Mode.MOUSE, "mode cycle wrap tilt->mouse")
	check(InputModes.next_mode(InputModes.Mode.MOUSE) == InputModes.Mode.KEYBOARD, "mode cycle mouse->keyboard")
	check(InputModes.next_mode(InputModes.Mode.DRAG) == InputModes.Mode.TILT, "mode cycle drag->tilt")
	check(InputModes.default_mode(true, true) == InputModes.Mode.TILT, "default touch+sensor tilt")
	check(InputModes.default_mode(true, false) == InputModes.Mode.DRAG, "default touch no sensor drag")
	check(InputModes.default_mode(false, true) == InputModes.Mode.MOUSE, "default desktop mouse")
	check(InputModes.tilt_fallback_mode(true) == InputModes.Mode.DRAG, "tilt fallback touch drag")
	check(InputModes.tilt_fallback_mode(false) == InputModes.Mode.MOUSE, "tilt fallback desktop mouse")


func test_input_vectors() -> void:
	var m: Vector2 = InputModes.steer_mouse(Vector2(100, 0), Vector2(0, 0))
	check(m.x > 0.4 and m.length() <= 1.01, "mouse steer toward cursor")
	check(InputModes.steer_mouse(Vector2(5, 0), Vector2(0, 0)) == Vector2.ZERO, "mouse deadzone")
	var kb: Vector2 = InputModes.steer_keyboard(true, false, true, false)
	check(is_equal_approx(kb.length(), 1.0) and kb.x < 0.0 and kb.y < 0.0, "keyboard diagonal normalised")
	var d: Vector2 = InputModes.steer_drag(Vector2(300, 0), Vector2(100, 0), true)
	check(is_equal_approx(d.length(), 1.0), "drag clamped to 1")
	check(InputModes.steer_drag(Vector2(50, 0), Vector2(0, 0), false) == Vector2.ZERO, "drag zero when released")
	var raw := Vector2(0.5, 0.0)
	var t: Vector2 = InputModes.steer_tilt(raw, Vector2(0.1, 0.0))
	check(t.length() > 0.0, "tilt subtracts calibration")
	check(t.x > 0.0, "positive raw tilt x steers right")
	var raw_neg := Vector2(-0.5, 0.0)
	var t2: Vector2 = InputModes.steer_tilt(raw_neg, Vector2.ZERO)
	check(t2.x < 0.0, "negative raw tilt x steers left")
	var rot: Vector2 = InputModes.rotate_for_screen(Vector2(0.0, 1.0), 90.0)
	check(rot.x > 0.9 and absf(rot.y) < 0.1, "device +y at 90 maps to screen +x (right edge down)")


func test_tilt_sign_mapping() -> void:
	var full: float = 35.0
	var sens: float = 1.0
	var tip: float = 18.0
	for ang in [0, 90, 180, 270]:
		var a := float(ang)
		var d_right: Vector2 = InputModes.device_vector_from_screen_tip(tip, 0.0, a)
		var s_right: Vector2 = InputModes.tilt_steer_pipeline(
			d_right.x, d_right.y, a, Vector2.ZERO, full, sens
		)
		check(s_right.x > 0.05 and absf(s_right.y) < 0.35, "screen-right down angle %d => +x (%.2f,%.2f)" % [ang, s_right.x, s_right.y])
		var d_left: Vector2 = InputModes.device_vector_from_screen_tip(-tip, 0.0, a)
		var s_left: Vector2 = InputModes.tilt_steer_pipeline(
			d_left.x, d_left.y, a, Vector2.ZERO, full, sens
		)
		check(s_left.x < -0.05, "screen-left down angle %d => -x" % ang)
		var d_top_away: Vector2 = InputModes.device_vector_from_screen_tip(0.0, -tip, a)
		var s_up: Vector2 = InputModes.tilt_steer_pipeline(
			d_top_away.x, d_top_away.y, a, Vector2.ZERO, full, sens
		)
		check(s_up.y < -0.05 and absf(s_up.x) < 0.35, "screen-top away angle %d => -y" % ang)
		var d_top_raise: Vector2 = InputModes.device_vector_from_screen_tip(0.0, tip, a)
		var s_down: Vector2 = InputModes.tilt_steer_pipeline(
			d_top_raise.x, d_top_raise.y, a, Vector2.ZERO, full, sens
		)
		check(s_down.y > 0.05, "screen-top raised angle %d => +y" % ang)
		var d_off: Vector2 = InputModes.device_vector_from_screen_tip(8.0, -6.0, a)
		var cal: Vector2 = InputModes.map_device_tilt(
			InputModes.device_angles_to_screen_steer(d_off.x, d_off.y, a),
			full,
			sens
		)
		var zeroed: Vector2 = InputModes.tilt_steer_pipeline(
			d_off.x, d_off.y, a, cal, full, sens
		)
		check(zeroed.length() < 0.02, "calibration cancels offset at angle %d" % ang)
	var r90: Vector2 = InputModes.device_vector_to_screen_steer(Vector2(1.0, 0.0), 90.0)
	check(is_equal_approx(r90.x, 0.0) and is_equal_approx(r90.y, -1.0), "rotation 90: (d.x,d.y)->(d.y,-d.x)")
	var accel_android: Vector2 = InputModes.tilt_steer_from_accel_pipeline(
		Vector2(-3.0, 0.0), 0.0, Vector2.ZERO, sens
	)
	check(accel_android.x > 0.05, "Android ax=-3 portrait right-edge-down => +steer.x")
	var g_hi: Vector2 = InputModes.map_device_tilt(Vector2(10.0, 0.0), full, sens)
	var g_lo: Vector2 = InputModes.map_device_tilt(Vector2(40.0, 0.0), full, sens)
	check(g_hi.x > 0.0 and g_lo.x > g_hi.x, "map_device_tilt preserves gamma magnitude")


func test_mode_save_load() -> void:
	_clear_settings_test()
	check(InputModes.save_mode(SETTINGS_TEST, InputModes.Mode.DRAG), "save input mode")
	check(InputModes.load_mode(SETTINGS_TEST) == InputModes.Mode.DRAG, "load input mode round-trip")
	var tilt: Node = TiltScript.new()
	tilt.call("set_settings_path", SETTINGS_TEST)
	root.add_child(tilt)
	await process_frame
	check(int(tilt.call("selected_mode")) == InputModes.Mode.DRAG, "tilt_input restores saved mode")
	tilt.queue_free()
	await process_frame


func test_play_backgrounds() -> void:
	check(PlayBg.default_id() == PlayBg.Id.TABLETOP, "default tabletop background")
	var expect: Array[int] = [PlayBg.Id.CHOPPING, PlayBg.Id.PLANKS, PlayBg.Id.STONE, PlayBg.Id.TABLETOP]
	var id: int = PlayBg.Id.TABLETOP
	for i in 4:
		id = PlayBg.next_id(id)
		check(id == expect[i], "background cycle step %d" % i)
	for bg in PlayBg.ORDER:
		var tex: ImageTexture = PlayBg.texture_for_size(bg, Vector2(400, 700))
		check(tex != null and tex.get_width() > 0, "texture for %s" % PlayBg.name_for(bg))


func test_play_background_settings() -> void:
	_clear_settings_test()
	check(UserSettings.load_background(SETTINGS_TEST) == PlayBg.Id.TABLETOP, "missing key defaults tabletop")
	check(UserSettings.save_background(SETTINGS_TEST, PlayBg.Id.PLANKS), "save background")
	check(UserSettings.load_background(SETTINGS_TEST) == PlayBg.Id.PLANKS, "load background round-trip")
	check(InputModes.save_mode(SETTINGS_TEST, InputModes.Mode.KEYBOARD), "save mode with bg on file")
	check(UserSettings.load_background(SETTINGS_TEST) == PlayBg.Id.PLANKS, "bg survives mode save")
	check(InputModes.load_mode(SETTINGS_TEST) == InputModes.Mode.KEYBOARD, "mode on merged file")
	check(UserSettings.save_background(SETTINGS_TEST, PlayBg.Id.STONE), "save bg again")
	check(InputModes.load_mode(SETTINGS_TEST) == InputModes.Mode.KEYBOARD, "mode survives bg save")
	var maze: MazeWorld = MazeWorld.new()
	root.add_child(maze)
	await process_frame
	var data: Dictionary = Maze.generate(1, 77)
	var play := Rect2(10, 220, 700, 900)
	for bg in PlayBg.ORDER:
		maze.set_play_background(bg)
		maze.build(data, play)
		check(maze.play_background_id == bg, "maze theme %s" % PlayBg.name_for(bg))
	maze.queue_free()
	await process_frame


func test_tilt_keyboard() -> void:
	var tilt: Node = TiltScript.new()
	root.add_child(tilt)
	await process_frame
	var ev := InputEventKey.new()
	ev.keycode = KEY_D
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	var v: Vector2 = tilt.keyboard_override_from_arrows()
	check(v.x > 0.5, "keyboard right sets tilt x")
	tilt.queue_free()
	await process_frame


func test_main_scene() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	check(scene != null, "main scene loads")
	var inst := scene.instantiate()
	root.add_child(inst)
	for i in 5:
		await process_frame
	check(inst.get_child_count() >= 2, "main scene children present")
	inst.queue_free()
	await process_frame
	check(true, "main scene ran frames without error")


func _skip_intro(main: Node) -> void:
	if main.has_node("LaunchIntroLayer"):
		main.get_node("LaunchIntroLayer").get_child(0).call("skip")
	for i in 12:
		await process_frame


func _find_main_child(main: Node, type) -> Node:
	for c in main.get_children():
		if is_instance_of(c, type):
			return c
	return null


func test_playability_flow() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	for i in 20:
		await process_frame
	var main: Node = inst
	var launch = _find_main_child(main, LaunchMinigame)
	var top: SpinningTop = _find_main_child(main, SpinningTop) as SpinningTop
	var maze: MazeWorld = _find_main_child(main, MazeWorld) as MazeWorld
	check(launch != null and top != null and maze != null, "playability scene parts present")
	await _skip_intro(main)
	var rel: float = Launch.power_for_offset(0.0)
	if main.has_method("_begin_run"):
		main.call("_begin_run", rel)
	else:
		main.call("_on_launch_released", rel)
	for i in 15:
		await process_frame
	check(int(main.get("phase")) == MainScript.Phase.RUN, "launch advances to run")
	check(top.spin_power > 90.0, "centre launch power ~100 (got %.1f)" % top.spin_power)
	var tin: Node = root.get_node_or_null("TiltInput")
	check(tin != null, "TiltInput autoload present for playability")
	if tin:
		if tin.has_method("set_steer_blocked"):
			tin.call("set_steer_blocked", false)
		if tin.has_method("set_test_steer_vector"):
			tin.call("set_test_steer_vector", Vector2(0, -1))
		var steer: Vector2 = tin.call("get_steer_vector") as Vector2
		check(steer.y < -0.3, "test steer vector points up")
	var y0: float = top.global_position.y
	for i in 120:
		await physics_frame
	var moved: bool = top.global_position.y < y0 - 0.5
	var rolling: bool = top.linear_velocity.length() > 2.0
	check(moved, "top moves under steer vector (position must change, not just velocity)")
	top.set_initial_power(92.0)
	top.set_run_active(true)
	if top.is_fallen():
		top.reset_top(maze.start_position(), 92.0)
		top.set_run_active(true)
		main.set("phase", MainScript.Phase.RUN)
	var w1: int = Maze.wall_count(maze.maze_data)
	var p_hit: float = top.spin_power
	# The stronger high tier can bump a real wall during the steer phase;
	# clear the 150 ms hit cooldown so this synthetic hit is deterministic.
	top.set("_last_hit_ms", -100000)
	top.apply_wall_hit(12.0)
	check(top.spin_power < p_hit, "playability wall hit lowers power")
	top.global_position = maze.goal_area_rect().get_center()
	for i in 20:
		await physics_frame
	if int(main.get("phase")) != MainScript.Phase.CLEARED and main.has_method("_check_goal_reached"):
		main.call("_check_goal_reached")
		for i in 80:
			await physics_frame
	check(int(main.get("phase")) == MainScript.Phase.CLEARED, "goal clears wave")
	if main.has_method("advance_wave"):
		main.call("advance_wave")
	for i in 25:
		await process_frame
	check(int(main.get("wave")) == 2, "wave advances to 2")
	var w2: int = Maze.wall_count(maze.maze_data)
	check(w2 >= w1, "wave 2 maze wall_count >= wave 1 (%d vs %d)" % [w2, w1])
	top.set_initial_power(3.0)
	top.set_run_active(true)
	main.set("phase", MainScript.Phase.RUN)
	for i in 100:
		await physics_frame
	check(top.is_fallen(), "playability power zero fell over")
	if tin.has_method("clear_test_steer_vector"):
		tin.call("clear_test_steer_vector")
	inst.queue_free()
	await process_frame


func _main_key(main: Node, key: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.pressed = pressed
	e.keycode = key
	Input.parse_input_event(e)
	main.call("_unhandled_input", e)


func _release_steer_inputs() -> void:
	for key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_A, KEY_S, KEY_D]:
		var ev := InputEventKey.new()
		ev.pressed = false
		ev.keycode = key
		Input.parse_input_event(ev)
	var up := InputEventMouseButton.new()
	up.pressed = false
	up.button_index = MOUSE_BUTTON_LEFT
	Input.parse_input_event(up)


func _tin_drag(_main: Node, tin: Node, from: Vector2, to: Vector2, steps: int) -> void:
	# Warp the real cursor so TiltInput._process (which reads get_mouse_position)
	# cannot overwrite the synthetic drag pointer with a stale cursor.
	DisplayServer.warp_mouse(Vector2i(int(from.x), int(from.y)))
	var down := InputEventMouseButton.new()
	down.pressed = true
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = from
	down.global_position = from
	Input.parse_input_event(down)
	tin.call("handle_input", down)
	for j in steps:
		var t: float = float(j + 1) / float(steps)
		var p: Vector2 = from.lerp(to, t)
		DisplayServer.warp_mouse(Vector2i(int(p.x), int(p.y)))
		var mot := InputEventMouseMotion.new()
		mot.position = p
		mot.global_position = p
		mot.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mot)
		tin.call("handle_input", mot)
		await physics_frame
	var up := InputEventMouseButton.new()
	up.pressed = false
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = to
	Input.parse_input_event(up)
	tin.call("handle_input", up)


func test_real_launch_steering() -> void:
	_release_steer_inputs()
	var tin0: Node = root.get_node_or_null("TiltInput")
	if tin0 and tin0.has_method("set_mode"):
		tin0.call("set_mode", InputModes.Mode.KEYBOARD)
		if tin0.has_method("clear_test_steer_vector"):
			tin0.call("clear_test_steer_vector")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	for i in 20:
		await process_frame
	var main: Node = inst
	check(int(main.get("phase")) == MainScript.Phase.LAUNCH, "real flow starts at launch timing bar")
	var intro_node: Node = main.get_node("LaunchIntroLayer").get_child(0)
	check(not bool(intro_node.call("is_active")), "no hand animation before the timing bar")
	_main_key(main, KEY_SPACE, true)
	_main_key(main, KEY_SPACE, false)
	for i in 130:
		await process_frame
		if int(main.get("phase")) != MainScript.Phase.LAUNCH:
			break
	check(int(main.get("phase")) == MainScript.Phase.INTRO, "bar result leads into hand release")
	check(bool(intro_node.call("is_active")), "hand release animation playing after bar")
	_main_key(main, KEY_SPACE, true)
	_main_key(main, KEY_SPACE, false)
	for i in 30:
		await process_frame
		if int(main.get("phase")) == MainScript.Phase.RUN:
			break
	check(int(main.get("phase")) == MainScript.Phase.RUN, "launch release enters run")
	var top: SpinningTop = _find_main_child(main, SpinningTop) as SpinningTop
	var maze: MazeWorld = _find_main_child(main, MazeWorld) as MazeWorld
	check(top.is_run_active(), "run active immediately after launch release")
	var p_idle: float = top.spin_power
	for i in 180:
		await physics_frame
	check(int(main.get("phase")) == MainScript.Phase.RUN, "still in run after idle")
	var spawn_p: Vector2 = maze.run_spawn_position()
	check(
		top.global_position.distance_to(spawn_p) < 24.0,
		"top parked at run spawn (d=%.1f)" % top.global_position.distance_to(spawn_p)
	)
	check(top.spin_power < p_idle - 0.4, "power decays during idle (%.1f -> %.1f)" % [p_idle, top.spin_power])
	var up_rel: Vector2 = top.visual_up_world()
	print(
		"  SPIN after release: rot=%.3f spin_rate=%.2f art_up=%s art_angle=%.3f tilt=%.3f"
		% [top.rotation, top.spin_rate(), up_rel, Vector2.UP.angle_to(up_rel), top.visual_tilt()]
	)
	check(top.spin_rate() > 5.0, "after release top spins about its vertical axis")
	check(absf(top.rotation) > 1.0, "after release physics spin has advanced")
	check(
		absf(Vector2.UP.angle_to(up_rel)) < 0.6,
		"after release art stays upright on its tip (%.3f rad)" % Vector2.UP.angle_to(up_rel)
	)
	var y0: float = top.global_position.y
	check(not top.freeze, "top unfrozen after real launch path")
	check(not top.is_fallen(), "top not fallen after real launch path")
	check(top.is_run_active(), "run active flag after real launch path")
	check(top.collision_layer == 1, "collision layer active after real launch")
	var tin: Node = root.get_node_or_null("TiltInput")
	main.set("phase", MainScript.Phase.RUN)
	main.set("_overlay_busy", false)
	tin.call("set_steer_blocked", false)
	tin.call("set_mode", InputModes.Mode.DRAG)
	y0 = top.global_position.y
	DisplayServer.warp_mouse(Vector2i(360, 900))
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(360, 900)
	Input.parse_input_event(down)
	tin.call("handle_input", down)
	for j in 60:
		DisplayServer.warp_mouse(Vector2i(360, 680))
		var mot := InputEventMouseMotion.new()
		mot.position = Vector2(360, 680)
		mot.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mot)
		tin.call("handle_input", mot)
		await physics_frame
	var drag_dy: float = y0 - top.global_position.y
	check(
		drag_dy > 20.0,
		"drag after real launch moves top up %.1f px vel %.1f"
		% [drag_dy, top.linear_velocity.length()]
	)
	var dup := InputEventMouseButton.new()
	dup.button_index = MOUSE_BUTTON_LEFT
	dup.pressed = false
	dup.position = Vector2(360, 680)
	Input.parse_input_event(dup)
	tin.call("handle_input", dup)
	tin.call("set_mode", InputModes.Mode.KEYBOARD)
	top.reset_top(maze.start_position(), 95.0)
	top.set_run_active(true)
	main.set("phase", MainScript.Phase.RUN)
	tin.call("set_steer_blocked", false)
	for i in 60:
		await physics_frame
	var kb0: float = top.global_position.y
	var kdown := InputEventKey.new()
	kdown.pressed = true
	kdown.keycode = KEY_UP
	Input.parse_input_event(kdown)
	for n in 90:
		await physics_frame
	var kup := InputEventKey.new()
	kup.pressed = false
	kup.keycode = KEY_UP
	Input.parse_input_event(kup)
	var kb_dy: float = kb0 - top.global_position.y
	check(
		kb_dy > 20.0,
		"keyboard up after real launch moves top %.1f px vel %.1f"
		% [kb_dy, top.linear_velocity.length()]
	)
	inst.queue_free()
	await process_frame


func test_intro_and_goal_fall() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	for i in 15:
		await process_frame
	var main: Node = inst
	check(int(main.get("phase")) == MainScript.Phase.LAUNCH, "launch bar comes first")
	var intro_node: Node = main.get_node("LaunchIntroLayer").get_child(0)
	check(not bool(intro_node.call("is_active")), "hand idle while bar runs")
	main.call("_on_launch_released", 90.0)
	await process_frame
	check(int(main.get("phase")) == MainScript.Phase.INTRO, "bar release starts hand release")
	check(bool(intro_node.call("is_active")), "hand animation active after bar")
	var t_wait: int = Time.get_ticks_msec()
	while int(main.get("phase")) != MainScript.Phase.RUN and Time.get_ticks_msec() - t_wait < 6000:
		await process_frame
	check(int(main.get("phase")) == MainScript.Phase.RUN, "unskipped hand release ends in run")
	var top0: SpinningTop = _find_main_child(main, SpinningTop) as SpinningTop
	check(absf(top0.spin_power - 90.0) < 2.0, "run uses bar power after hand (%.1f)" % top0.spin_power)
	for i in 10:
		await process_frame
	var top: SpinningTop = _find_main_child(main, SpinningTop) as SpinningTop
	main.call("_finish_goal")
	await process_frame
	check(int(main.get("phase")) == MainScript.Phase.GOAL_FALL, "goal enters fall before cleared")
	for i in 80:
		await physics_frame
	check(int(main.get("phase")) == MainScript.Phase.CLEARED, "overlay phase after goal fall")
	top.set_initial_power(5.0)
	top.set_run_active(true)
	main.set("phase", MainScript.Phase.RUN)
	for i in 150:
		await physics_frame
	check(top.spin_power <= 0.1 or top.is_fallen(), "power drains toward fall")
	for i in 70:
		await physics_frame
	check(int(main.get("phase")) == MainScript.Phase.FELL, "power zero leads to fell phase")
	inst.queue_free()
	await process_frame


func test_steer_after_idle() -> void:
	var tin: Node = root.get_node_or_null("TiltInput")
	check(tin != null, "TiltInput for steer idle tests")
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	for i in 20:
		await process_frame
	var main: Node = inst
	var top: SpinningTop = _find_main_child(main, SpinningTop) as SpinningTop
	tin.call("set_mode", InputModes.Mode.DRAG)
	main.call("_begin_run", 95.0)
	for i in 15:
		await process_frame
	var y0: float = top.global_position.y
	for i in 180:
		await physics_frame
	check(not top.sleeping, "top not sleeping after idle on run")
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(360, 900)
	Input.parse_input_event(down)
	for j in 50:
		var mot := InputEventMouseMotion.new()
		mot.position = Vector2(360, 720)
		mot.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mot)
		await physics_frame
	var drag_moved: bool = top.global_position.y < y0 - 15.0
	check(drag_moved, "drag steering after idle moves top (position %.1f -> %.1f)" % [y0, top.global_position.y])
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(360, 720)
	Input.parse_input_event(up)
	tin.call("handle_input", up)
	await process_frame
	check(not bool(tin.call("drag_active")), "drag steer stops after release")

	tin.call("set_mode", InputModes.Mode.MOUSE)
	top.reset_top(
		_find_main_child(main, MazeWorld).call("start_position"),
		95.0
	)
	top.set_run_active(true)
	main.set("phase", MainScript.Phase.RUN)
	var pos_before: Vector2 = top.global_position
	for i in 150:
		await physics_frame
	check(not top.sleeping, "top not sleeping before mouse steer")
	var vp: Viewport = inst.get_viewport()
	var screen_above: Vector2 = vp.get_canvas_transform() * (pos_before + Vector2(0, -160))
	DisplayServer.warp_mouse(Vector2i(int(screen_above.x), int(screen_above.y)))
	var mm := InputEventMouseMotion.new()
	mm.position = screen_above
	Input.parse_input_event(mm)
	for k in 70:
		await physics_frame
	var mouse_moved: bool = top.global_position.distance_to(pos_before) > 8.0
	check(mouse_moved, "mouse steering after idle moves top (dist %.1f)" % top.global_position.distance_to(pos_before))

	tin.call("set_mode", InputModes.Mode.KEYBOARD)
	top.reset_top(
		_find_main_child(main, MazeWorld).call("start_position"),
		95.0
	)
	top.set_run_active(true)
	var kb0: Vector2 = top.global_position
	for i in 150:
		await physics_frame
	var kdown := InputEventKey.new()
	kdown.pressed = true
	kdown.keycode = KEY_UP
	Input.parse_input_event(kdown)
	for n in 90:
		await physics_frame
	var kup := InputEventKey.new()
	kup.pressed = false
	kup.keycode = KEY_UP
	Input.parse_input_event(kup)
	check(
		top.global_position.y < kb0.y - 15.0,
		"keyboard up after idle moves top (dy %.1f)" % (kb0.y - top.global_position.y)
	)
	inst.queue_free()
	await process_frame




func test_board_key_and_button() -> void:
	# KEY_B and the HUD Board button must actually cycle the theme (not get
	# swallowed by a full-rect Control / focus / unhandled-input order).
	_release_steer_inputs()
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	for i in 25:
		await process_frame
	var ui: Node = inst.get_node_or_null("UI")
	var tin: Node = root.get_node_or_null("TiltInput")
	var btn: Button = ui.get("_btn_board") as Button if ui else null
	check(btn != null and tin != null, "Board button and TiltInput present")
	tin.call("set_background", PlayBg.Id.TABLETOP)
	for i in 6:
		await process_frame
	check(int(tin.call("selected_background")) == PlayBg.Id.TABLETOP, "start on tabletop")
	check(str(btn.text).contains("Tabletop"), "HUD label starts Tabletop")

	var vp: Viewport = inst.get_viewport()
	var key_b := InputEventKey.new()
	key_b.pressed = true
	key_b.echo = false
	key_b.keycode = KEY_B
	vp.push_input(key_b)
	var key_up := InputEventKey.new()
	key_up.pressed = false
	key_up.keycode = KEY_B
	vp.push_input(key_up)
	for i in 8:
		await process_frame
	check(
		int(tin.call("selected_background")) == PlayBg.Id.CHOPPING,
		"B key cycles to chopping (now %s)" % tin.call("background_name")
	)
	check(str(btn.text).contains("Chopping"), "HUD label updates after B key")

	# No full-rect overlay should swallow HUD clicks, and the Board button's
	# pressed handler must cycle the theme (same path as a player click).
	var r: Rect2 = btn.get_global_rect()
	check(r.size.x > 8.0 and r.size.y > 8.0, "Board button has a clickable rect %s" % r)
	var overlay: Control = ui.get("_overlay") as Control
	if overlay:
		check(
			(not overlay.visible) or overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"wave overlay does not swallow Board button clicks"
		)
	var intro: Node = inst.get_node_or_null("LaunchIntroLayer")
	if intro and intro.get_child_count() > 0:
		var intro_c: Node = intro.get_child(0)
		if intro_c is Control:
			check(
				(not (intro_c as Control).visible) or (intro_c as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"intro layer does not swallow Board button clicks"
			)
	var before_click: int = int(tin.call("selected_background"))
	btn.pressed.emit()
	for i in 8:
		await process_frame
	var after_click: int = int(tin.call("selected_background"))
	check(
		after_click == PlayBg.next_id(before_click),
		"Board button click cycles theme %s -> %s" % [before_click, after_click]
	)
	check(str(btn.text).contains(str(tin.call("background_name"))), "HUD label updates after Board click")
	inst.queue_free()
	await process_frame


func test_drag_after_background_switch() -> void:
	# Fails without the Main._process parent-transform fix: velocity can be
	# non-zero while the top stays glued to the spawn pose.
	_release_steer_inputs()
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	for i in 20:
		await process_frame
	var main: Node = inst
	var ui: Node = inst.get_node_or_null("UI")
	check(ui != null and ui.get("_btn_board") != null, "HUD Board button is present")
	await _skip_intro(main)
	main.call("_begin_run", 95.0)
	for i in 20:
		await process_frame
	var top: SpinningTop = _find_main_child(main, SpinningTop) as SpinningTop
	var maze: MazeWorld = _find_main_child(main, MazeWorld) as MazeWorld
	var tin: Node = root.get_node_or_null("TiltInput")
	check(top != null and tin != null, "top and TiltInput ready after launch")
	main.set("phase", MainScript.Phase.RUN)
	main.set("_overlay_busy", false)
	tin.call("set_steer_blocked", false)
	tin.call("set_mode", InputModes.Mode.DRAG)
	_release_steer_inputs()
	var btn: Button = ui.get("_btn_board") as Button
	if btn:
		check(btn.focus_mode == Control.FOCUS_NONE, "Board button does not take keyboard focus")
	for bg_i in PlayBg.ORDER.size():
		if bg_i > 0:
			if tin.has_method("cycle_background"):
				tin.call("cycle_background")
			for i in 8:
				await process_frame
		var bg_name: String = str(tin.call("background_name")) if tin.has_method("background_name") else str(bg_i)
		top.reset_top(maze.run_spawn_position(), 95.0)
		top.set_run_active(true)
		main.set("phase", MainScript.Phase.RUN)
		tin.call("set_steer_blocked", false)
		for i in 12:
			await physics_frame
		# Parent must not be snapping the rigid body every idle frame.
		check(
			main.position == main.get("_base_position"),
			"main is at rest pose on %s (not rewriting position every frame)" % bg_name
		)
		var y0: float = top.global_position.y
		await _tin_drag(main, tin, Vector2(360, 900), Vector2(360, 680), 60)
		var dy: float = y0 - top.global_position.y
		check(
			dy > 20.0,
			"drag after board=%s moves top up %.1f px (velocity loophole not accepted)"
			% [bg_name, dy]
		)
		# Keyboard after the Board button has been used.
		top.reset_top(maze.run_spawn_position(), 95.0)
		top.set_run_active(true)
		main.set("phase", MainScript.Phase.RUN)
		tin.call("set_steer_blocked", false)
		tin.call("set_mode", InputModes.Mode.KEYBOARD)
		for i in 8:
			await physics_frame
		var kb0: float = top.global_position.y
		var kdown := InputEventKey.new()
		kdown.pressed = true
		kdown.keycode = KEY_UP
		Input.parse_input_event(kdown)
		for n in 90:
			await physics_frame
		var kup := InputEventKey.new()
		kup.pressed = false
		kup.keycode = KEY_UP
		Input.parse_input_event(kup)
		check(
			kb0 - top.global_position.y > 20.0,
			"keyboard up after board=%s moves top %.1f px" % [bg_name, kb0 - top.global_position.y]
		)
		tin.call("set_mode", InputModes.Mode.DRAG)
	inst.queue_free()
	await process_frame


func test_overlay_centered() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	for sz in [Vector2i(720, 1280), Vector2i(450, 800)]:
		DisplayServer.window_set_size(sz)
		var inst := scene.instantiate()
		root.add_child(inst)
		for i in 20:
			await process_frame
		var main: Node = inst
		var ui: Node = inst.get_node("UI")
		if main.has_method("_on_viewport_changed"):
			main.call("_on_viewport_changed")
		for i in 10:
			await process_frame
		main.call("_begin_run", 90.0)
		for i in 8:
			await process_frame
		var top: SpinningTop = _find_main_child(main, SpinningTop) as SpinningTop
		main.call("_finish_goal")
		for i in 80:
			await physics_frame
		check(ui.overlay_visible(), "overlay visible at %s" % sz)
		var vp: Rect2 = inst.get_viewport().get_visible_rect()
		var card: Rect2 = ui.call("overlay_card_rect") as Rect2
		var err: float = card.get_center().distance_to(vp.get_center())
		check(err < 8.0, "overlay cleared centered %dx%d err=%.1f" % [sz.x, sz.y, err])
		inst.queue_free()
		await process_frame
	for sz in [Vector2i(720, 1280), Vector2i(450, 800)]:
		DisplayServer.window_set_size(sz)
		var inst2 := scene.instantiate()
		root.add_child(inst2)
		for i in 15:
			await process_frame
		var ui2: Node = inst2.get_node("UI")
		ui2.call("on_fell_over")
		for i in 8:
			await process_frame
		var vp2: Rect2 = inst2.get_viewport().get_visible_rect()
		var card2: Rect2 = ui2.call("overlay_card_rect") as Rect2
		var err2: float = card2.get_center().distance_to(vp2.get_center())
		check(err2 < 8.0, "overlay fell centered %dx%d err=%.1f" % [sz.x, sz.y, err2])
		inst2.queue_free()
		await process_frame
	DisplayServer.window_set_size(Vector2i(720, 1280))


func test_wave_overlay_flow() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	for i in 25:
		await process_frame
	var main: Node = inst
	var ui: Node = inst.get_node("UI")
	var top: SpinningTop = _find_main_child(main, SpinningTop) as SpinningTop
	var maze: MazeWorld = _find_main_child(main, MazeWorld) as MazeWorld
	main.call("_begin_run", 95.0)
	for i in 15:
		await process_frame
	main.call("_finish_goal")
	for i in 80:
		await physics_frame
	check(ui.overlay_visible(), "cleared overlay visible")
	check(int(main.get("phase")) == MainScript.Phase.CLEARED, "phase cleared")
	main.call("advance_wave")
	for i in 25:
		await process_frame
	check(int(main.get("wave")) == 2, "next wave advances to 2")
	var w2: int = Maze.wall_count(maze.maze_data)
	main.call("_begin_run", 90.0)
	for i in 15:
		await process_frame
	main.call("_finish_goal")
	for i in 80:
		await physics_frame
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_ENTER
	check(ui.call("handle_overlay_input", ev), "enter handled on overlay")
	Input.parse_input_event(ev)
	for i in 25:
		await process_frame
	check(int(main.get("wave")) == 3, "enter starts wave 3")
	check(Maze.wall_count(maze.maze_data) >= w2, "wave 3 maze denser")
	main.set("phase", MainScript.Phase.FELL)
	ui.on_fell_over()
	for i in 5:
		await process_frame
	check(ui.overlay_visible(), "fell overlay visible")
	ui.call("_activate_overlay_action")
	for i in 25:
		await process_frame
	check(int(main.get("wave")) == 3, "retry keeps wave 3 (new seed)")
	inst.queue_free()
	await process_frame


func test_physics_defaults() -> void:
	PhysicsSettings.reset_all()
	check(
		is_equal_approx(PhysicsSettings.get_value("steer_force"), TopScript.STEER_FORCE),
		"steer_force default matches STEER_FORCE"
	)
	check(
		is_equal_approx(PhysicsSettings.get_value("max_speed"), TopScript.MAX_LINEAR_SPEED),
		"max_speed default matches MAX_LINEAR_SPEED"
	)
	check(
		is_equal_approx(PhysicsSettings.get_value("wall_hit_slowdown"), TopScript.HIT_VEL_SCALE),
		"wall_hit_slowdown default matches HIT_VEL_SCALE"
	)
	check(
		is_equal_approx(PhysicsSettings.get_value("tilt_response"), 3.0),
		"tilt_response default is 3.0"
	)
	check(
		is_equal_approx(PhysicsSettings.get_value("tilt_sensitivity"), 3.0),
		"tilt_sensitivity default is 3.0"
	)
	check(
		is_equal_approx(PhysicsSettings.get_value("lean_max_deg"), 45.0),
		"lean_max_deg default is 45.0"
	)
	for d in PhysicsSettings.DEFS:
		var dv: float = float(d.default)
		check(dv >= float(d.min) and dv <= float(d.max), "default %s within range" % d.key)


func test_physics_settings_migration() -> void:
	var migrate_path := SETTINGS_TEST + ".physics_migrate"
	if FileAccess.file_exists(migrate_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(migrate_path))
	var cfg := ConfigFile.new()
	cfg.set_value("physics", "tilt_response", 2.0)
	cfg.set_value("physics", "tilt_sensitivity", 1.0)
	cfg.set_value("physics", "lean_max_deg", 28.0)
	cfg.set_value("physics", "steer_force", 610.0)
	cfg.save(migrate_path)
	PhysicsSettings.reset_all()
	PhysicsSettings.load_from_path(migrate_path)
	check(
		is_equal_approx(PhysicsSettings.get_value("tilt_response"), 3.0),
		"legacy file migrates tilt_response from old default"
	)
	check(
		is_equal_approx(PhysicsSettings.get_value("tilt_sensitivity"), 3.0),
		"legacy file migrates tilt_sensitivity from old default"
	)
	check(
		is_equal_approx(PhysicsSettings.get_value("lean_max_deg"), 45.0),
		"legacy file migrates lean_max_deg from old default"
	)
	check(
		is_equal_approx(PhysicsSettings.get_value("steer_force"), 610.0),
		"legacy file keeps custom steer_force"
	)
	var cfg2 := UserSettings.load_config(migrate_path)
	check(
		int(cfg2.get_value("physics", "physics_version", 0)) == PhysicsSettings.PHYSICS_VERSION,
		"migration writes physics_version"
	)
	if FileAccess.file_exists(migrate_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(migrate_path))
	cfg = ConfigFile.new()
	cfg.set_value("physics", "tilt_response", 2.0)
	cfg.set_value("physics", "tilt_sensitivity", 1.7)
	cfg.set_value("physics", "lean_max_deg", 28.0)
	cfg.save(migrate_path)
	PhysicsSettings.reset_all()
	PhysicsSettings.load_from_path(migrate_path)
	check(
		is_equal_approx(PhysicsSettings.get_value("tilt_sensitivity"), 1.7),
		"legacy file keeps customised tilt_sensitivity"
	)
	check(
		is_equal_approx(PhysicsSettings.get_value("tilt_response"), 3.0),
		"legacy file still migrates other old-default keys"
	)
	if FileAccess.file_exists(migrate_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(migrate_path))
	cfg = ConfigFile.new()
	cfg.set_value("physics", "physics_version", PhysicsSettings.PHYSICS_VERSION)
	cfg.set_value("physics", "tilt_response", 2.5)
	cfg.set_value("physics", "tilt_sensitivity", 1.0)
	cfg.set_value("physics", "lean_max_deg", 30.0)
	cfg.save(migrate_path)
	PhysicsSettings.reset_all()
	PhysicsSettings.load_from_path(migrate_path)
	check(
		is_equal_approx(PhysicsSettings.get_value("tilt_sensitivity"), 1.0),
		"version-2 file keeps saved tilt_sensitivity 1.0"
	)
	check(
		is_equal_approx(PhysicsSettings.get_value("tilt_response"), 2.5),
		"version-2 file keeps saved tilt_response"
	)
	if FileAccess.file_exists(migrate_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(migrate_path))
	PhysicsSettings.reset_all()


func test_smooth_alpha_doubled() -> void:
	var dt: float = 1.0 / 60.0
	var a2: float = InputModes.smooth_alpha(dt, 2.0)
	var expect: float = 1.0 - pow(1.0 - InputModes.SMOOTH, 2.0)
	check(is_equal_approx(a2, expect), "smooth_alpha rate 2 at 60fps")
	check(a2 > InputModes.SMOOTH, "doubled response alpha > legacy SMOOTH")
	var slow := 0.0
	var fast := 0.0
	for i in 12:
		slow = lerpf(slow, 1.0, InputModes.smooth_alpha(dt, 1.0))
		fast = lerpf(fast, 1.0, InputModes.smooth_alpha(dt, 2.0))
	check(fast > slow + 0.02, "rate 2 smoothing closer to target (%.3f vs %.3f)" % [fast, slow])


func test_tilt_magnitude_preserved() -> void:
	var gentle: Vector2 = InputModes.map_device_tilt(Vector2(10.0, 0.0), 35.0, 1.0)
	var hard: Vector2 = InputModes.map_device_tilt(Vector2(40.0, 0.0), 35.0, 1.0)
	check(gentle.length() > 0.05, "gentle tilt nonzero")
	check(hard.length() > gentle.length() + 0.05, "hard tilt magnitude > gentle (%.3f vs %.3f)" % [hard.length(), gentle.length()])


func test_tier_scales() -> void:
	PhysicsSettings.reset_all()
	var low_s: float = PhysicsSettings.get_value("low_scale")
	var high_s: float = PhysicsSettings.get_value("high_scale")
	var g: float = TopPhysics.tier_scale(0.2)
	var h: float = TopPhysics.tier_scale(0.9)
	check(absf(g - 0.2 * low_s) < 0.06, "gentle tier ~ m*low_scale")
	check(absf(h - 0.9 * high_s) < 0.15, "hard tier ~ m*high_scale")
	check(h > g * 2.5, "hard/gentle tier ratio large")
	var prev: float = -0.01
	var jump_eps: float = 0.2
	for i in 201:
		var m: float = float(i) / 200.0
		var out: float = TopPhysics.tier_scale(m)
		check(out >= prev - 0.0001, "tier_scale monotonic at m=%.2f" % m)
		if i > 0:
			check(out - prev < jump_eps, "tier_scale continuous step %d" % i)
		prev = out


func test_lean_and_precession() -> void:
	PhysicsSettings.reset_all()
	var shaped: Vector2 = TopPhysics.shape_input(Vector2(1.0, 0.0))
	var lean_max: float = deg_to_rad(PhysicsSettings.get_value("lean_max_deg"))
	var hi_scale: float = maxf(PhysicsSettings.get_value("high_scale"), 0.01)
	var target: Vector2 = shaped * (lean_max / hi_scale)
	var lean := Vector2.ZERO
	for i in 180:
		lean = TopPhysics.spring_lean(
			lean,
			target,
			PhysicsSettings.get_value("lean_stiffness"),
			1.0 / 60.0
		)
	check(lean.length() <= lean_max + 0.02, "lean bounded by lean_max")
	check(lean.length() > lean_max * 0.65, "lean reaches most of target magnitude")
	if lean.length() > 0.001 and target.length() > 0.001:
		check(lean.normalized().dot(target.normalized()) > 0.9, "lean converges toward input direction")
	var l0 := Vector2(0.15, 0.08)
	var with_p := l0
	var no_p := l0
	for j in 120:
		with_p = TopPhysics.apply_precession(with_p, 0.35, 4.0, 1.0 / 60.0, 1.0)
		no_p = TopPhysics.apply_precession(no_p, 0.4, 0.0, 1.0 / 60.0, 1.0)
	check(with_p.angle_to(l0) > 0.01, "precession rotates lean")
	var rate: float = 2.5
	var ll: float = l0.length()
	var omega_low: float = rate * ll / maxf(0.2, 0.15)
	var omega_high: float = rate * ll / maxf(1.0, 0.15)
	check(omega_low > omega_high, "lower spin_norm implies faster precession omega")


func test_physics_save_load() -> void:
	PhysicsSettings.reset_all()
	var path := SETTINGS_TEST
	InputModes.save_mode(path, InputModes.Mode.DRAG)
	UserSettings.save_background(path, PlayBg.Id.CHOPPING)
	PhysicsSettings.set_value("tier_threshold", 0.62)
	PhysicsSettings.set_value("steer_force", 610.0)
	PhysicsSettings.save_to_path(path)
	PhysicsSettings.reset_all()
	PhysicsSettings.load_from_path(path)
	check(
		is_equal_approx(PhysicsSettings.get_value("tier_threshold"), 0.62),
		"physics load tier_threshold"
	)
	check(
		is_equal_approx(PhysicsSettings.get_value("steer_force"), 610.0),
		"physics load steer_force"
	)
	var cfg := UserSettings.load_config(path)
	check(
		int(cfg.get_value("input", "mode", -1)) == InputModes.Mode.DRAG,
		"save physics preserves input section"
	)
	check(
		int(cfg.get_value("visual", "background", -1)) == PlayBg.Id.CHOPPING,
		"save physics preserves visual section"
	)
	PhysicsSettings.reset("steer_force")
	check(
		is_equal_approx(PhysicsSettings.get_value("steer_force"), TopScript.STEER_FORCE),
		"reset(key) restores default"
	)
	PhysicsSettings.reset_all()
	check(
		is_equal_approx(PhysicsSettings.get_value("tier_threshold"), 0.5),
		"reset_all restores defaults"
	)


func test_physics_live_tuning() -> void:
	PhysicsSettings.reset_all()
	var top: SpinningTop = TopScript.new()
	root.add_child(top)
	await process_frame
	top.set_run_active(true)
	top.set_initial_power(100.0)
	top.global_position = Vector2(360, 640)
	var tin: Node = root.get_node_or_null("TiltInput")
	if tin and tin.has_method("set_steer_blocked"):
		tin.call("set_steer_blocked", false)
	if tin and tin.has_method("set_test_steer_vector"):
		tin.call("set_test_steer_vector", Vector2(0, -1))
	var start: Vector2 = top.global_position
	for i in 200:
		await physics_frame
	var dist_base: float = start.distance_to(top.global_position)
	PhysicsSettings.set_value("steer_force", 1300.0)
	top.reset_top(start, 100.0)
	top.set_run_active(true)
	var start2: Vector2 = top.global_position
	for i in 200:
		await physics_frame
	var dist_high: float = start2.distance_to(top.global_position)
	check(dist_high > dist_base * 1.15, "higher steer_force moves further (%.0f vs %.0f)" % [dist_high, dist_base])
	PhysicsSettings.reset("steer_force")
	var tier_dist := {}
	for tier in [["gentle", 0.2, 1.6], ["hard", 1.0, 1.6], ["hard_hi", 1.0, 3.0]]:
		PhysicsSettings.set_value("high_scale", tier[2])
		top.reset_top(start, 100.0)
		top.set_run_active(true)
		tin.call("set_test_steer_vector", Vector2(0, -tier[1]))
		var s0: Vector2 = top.global_position
		for i in 90:
			await physics_frame
		tier_dist[tier[0]] = s0.distance_to(top.global_position)
	PhysicsSettings.reset("high_scale")
	tin.call("set_test_steer_vector", Vector2(0, -1))
	check(tier_dist["hard"] > tier_dist["gentle"] * 4.0, "hard tilt moves far more than gentle (%.0f vs %.0f)" % [tier_dist["hard"], tier_dist["gentle"]])
	check(tier_dist["gentle"] > 0.5, "gentle tilt still moves a little (%.1f)" % tier_dist["gentle"])
	check(tier_dist["hard_hi"] > tier_dist["hard"] * 1.1, "higher high_scale moves further live (%.0f vs %.0f)" % [tier_dist["hard_hi"], tier_dist["hard"]])
	PhysicsSettings.set_value("max_speed", 180.0)
	top.set_run_active(true)
	top.linear_velocity = Vector2(600, 0)
	for cap_i in 8:
		await physics_frame
	check(top.linear_velocity.length() <= 182.0, "max_speed cap respected")
	PhysicsSettings.set_value("fall_threshold", 50.0)
	top.reset_top(Vector2(300, 400), 40.0)
	top.set_run_active(true)
	for j in 12:
		await physics_frame
	check(top.is_fallen() or top.fall_kind() != TopScript.FallKind.NONE, "fall_threshold triggers fall at 40% power")
	if tin and tin.has_method("clear_test_steer_vector"):
		tin.call("clear_test_steer_vector")
	top.queue_free()
	await process_frame
	PhysicsSettings.reset_all()


func test_physics_settings_menu() -> void:
	PhysicsSettings.reset_all()
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	for i in 30:
		await process_frame
	var ui: Node = inst.get_node_or_null("UI")
	var tin: Node = root.get_node_or_null("TiltInput")
	var menu: PhysicsMenu = ui.call("physics_menu_node") as PhysicsMenu
	var settings_btn: Button = ui.call("settings_button") as Button
	check(menu != null and settings_btn != null, "physics menu and Settings button present")
	settings_btn.pressed.emit()
	for i in 8:
		await process_frame
	check(menu.is_open(), "gear opens settings menu")
	check(paused, "settings menu pauses tree")
	var steer_def: Dictionary = {}
	for d in PhysicsSettings.DEFS:
		if d.key == "steer_force":
			steer_def = d
			break
	var slider: HSlider = menu.slider_for_key("steer_force")
	var spin: SpinBox = menu.spinbox_for_key("steer_force")
	check(slider != null and spin != null, "menu row steer_force controls")
	slider.value = 700.0
	for i in 3:
		await process_frame
	check(is_equal_approx(spin.value, 700.0), "slider syncs to spinbox")
	spin.value = 820.0
	for i in 3:
		await process_frame
	check(is_equal_approx(slider.value, 820.0), "spinbox syncs to slider")
	spin.value = 50.0
	for i in 3:
		await process_frame
	check(
		spin.value >= float(steer_def.get("min", 100.0)),
		"spinbox clamps low to min (steer row was %.1f)" % spin.value
	)
	var bg_before: int = int(tin.call("selected_background"))
	var line: LineEdit = spin.get_line_edit()
	line.grab_focus()
	for k in 4:
		await process_frame
	var key_b := InputEventKey.new()
	key_b.pressed = true
	key_b.echo = false
	key_b.keycode = KEY_B
	ui.call("_unhandled_input", key_b)
	var key_b_up := InputEventKey.new()
	key_b_up.pressed = false
	key_b_up.keycode = KEY_B
	ui.call("_unhandled_input", key_b_up)
	for i in 6:
		await process_frame
	check(int(tin.call("selected_background")) == bg_before, "B ignored while spinbox focused in menu")
	PhysicsSettings.reset("steer_force")
	menu.call("_refresh_row", "steer_force")
	check(is_equal_approx(spin.value, TopScript.STEER_FORCE), "per-row reset in menu")
	menu.call("_on_reset_all")
	await process_frame
	check(is_equal_approx(PhysicsSettings.get_value("steer_force"), TopScript.STEER_FORCE), "reset all in menu")
	menu.close()
	for i in 10:
		await process_frame
	check(not menu.is_open(), "menu closes")
	check(not paused, "tree unpaused after menu close")
	var main: Node = inst
	var top: SpinningTop = _find_main_child(main, SpinningTop) as SpinningTop
	main.call("_begin_run", 95.0)
	tin.call("set_mode", InputModes.Mode.DRAG)
	tin.call("set_steer_blocked", false)
	for i in 20:
		await physics_frame
	var y0: float = top.global_position.y
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(360, 900)
	Input.parse_input_event(down)
	tin.call("handle_input", down)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(360, 720)
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	for j in 60:
		Input.parse_input_event(move)
		await physics_frame
	check(top.global_position.y < y0 - 10.0, "drag works after closing settings menu")
	var key_b2 := InputEventKey.new()
	key_b2.pressed = true
	key_b2.echo = false
	key_b2.keycode = KEY_B
	ui.call("_unhandled_input", key_b2)
	var key_b2_up := InputEventKey.new()
	key_b2_up.pressed = false
	key_b2_up.keycode = KEY_B
	ui.call("_unhandled_input", key_b2_up)
	for i in 8:
		await process_frame
	check(int(tin.call("selected_background")) != bg_before, "B cycles board after menu closed")
	inst.queue_free()
	await process_frame
	PhysicsSettings.reset_all()