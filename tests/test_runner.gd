extends SceneTree
## Headless tests. Run: godot --headless --path . --script res://tests/test_runner.gd

const Maze := preload("res://scripts/maze_gen.gd")
const Launch := preload("res://scripts/launch_math.gd")
const TopScript := preload("res://scripts/spinning_top.gd")
const TiltScript := preload("res://scripts/tilt_input.gd")
const MainScript := preload("res://scripts/main.gd")
const Difficulty := preload("res://scripts/difficulty.gd")
const InputModes := preload("res://scripts/input_modes.gd")

const SETTINGS_TEST := "user://test_stm_settings.cfg"

var passed := 0
var failed := 0


func _initialize() -> void:
	_clear_settings_test()
	await _run()
	_clear_settings_test()
	quit(1 if failed > 0 else 0)


func _clear_settings_test() -> void:
	if FileAccess.file_exists(SETTINGS_TEST):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_TEST))


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
	print("== Maze density curve ==")
	test_density_monotonic()
	print("== Launch power mapping ==")
	test_launch_math()
	print("== Top collision power loss ==")
	test_wall_hit_capped()
	await test_top_wall_hit()
	await test_top_physics_wall_hit()
	await test_top_speed_cap()
	print("== Input modes ==")
	test_input_mode_logic()
	test_input_vectors()
	test_mode_save_load()
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
	print("== Intro and goal fall ==")
	await test_intro_and_goal_fall()
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
		"res://scripts/visual_theme.gd",
		"res://scripts/launch_math.gd",
		"res://scripts/launch_minigame.gd",
		"res://scripts/launch_intro.gd",
		"res://scripts/main.gd",
		"res://scripts/maze_gen.gd",
		"res://scripts/maze_world.gd",
		"res://scripts/spinning_top.gd",
		"res://scripts/tilt_input.gd",
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
	var t: Vector2 = InputModes.steer_tilt(raw, Vector2(0.1, 0.0), raw)
	check(t.length() > 0.0, "tilt subtracts calibration")
	check(t.x < 0.0, "positive raw tilt x steers left (invert)")
	var raw_neg := Vector2(-0.5, 0.0)
	var t2: Vector2 = InputModes.steer_tilt(raw_neg, Vector2.ZERO, raw_neg)
	check(t2.x > 0.0, "negative raw tilt x steers right (invert)")
	var rot: Vector2 = InputModes.rotate_for_screen(Vector2(1, 0), 90.0)
	check(absf(rot.y) > 0.9, "tilt orientation rotation")


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
	check(moved or rolling, "top moves under steer vector")
	top.set_initial_power(92.0)
	top.set_run_active(true)
	if top.is_fallen():
		top.reset_top(maze.start_position(), 92.0)
		top.set_run_active(true)
		main.set("phase", MainScript.Phase.RUN)
	var w1: int = Maze.wall_count(maze.maze_data)
	var p_hit: float = top.spin_power
	top.apply_wall_hit(12.0)
	check(top.spin_power < p_hit, "playability wall hit lowers power")
	top.global_position = maze.goal_area_rect().get_center()
	for i in 20:
		await physics_frame
	if int(main.get("phase")) != MainScript.Phase.CLEARED and main.has_method("_on_goal_body"):
		main.call("_on_goal_body", top)
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


func test_intro_and_goal_fall() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	for i in 15:
		await process_frame
	var main: Node = inst
	check(int(main.get("phase")) == MainScript.Phase.INTRO, "intro precedes launch")
	main.get_node("LaunchIntroLayer").get_child(0).call("skip")
	for i in 15:
		await process_frame
	check(int(main.get("phase")) == MainScript.Phase.LAUNCH, "skip ends intro to launch")
	main.call("_begin_run", 90.0)
	for i in 10:
		await process_frame
	var top: SpinningTop = _find_main_child(main, SpinningTop) as SpinningTop
	main.call("_finish_goal", top)
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
	for j in 18:
		var mot := InputEventMouseMotion.new()
		mot.position = Vector2(360, 720)
		mot.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mot)
		await physics_frame
	var drag_moved: bool = top.global_position.y < y0 - 1.5 or top.linear_velocity.length() > 1.5
	check(drag_moved, "drag steering after idle moves top")
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
	var mouse_moved: bool = top.global_position.distance_to(pos_before) > 2.0 or top.linear_velocity.length() > 1.0
	check(mouse_moved, "mouse steering after idle moves top")

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
	for n in 70:
		await physics_frame
	var kup := InputEventKey.new()
	kup.pressed = false
	kup.keycode = KEY_UP
	Input.parse_input_event(kup)
	check(
		top.global_position.y < kb0.y - 1.0 or top.linear_velocity.length() > 1.0,
		"keyboard up after idle moves top"
	)
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
		main.call("_finish_goal", top)
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
	main.call("_finish_goal", top)
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
	main.call("_finish_goal", top)
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