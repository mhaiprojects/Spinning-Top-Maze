extends SceneTree
## Headless tests. Run: godot --headless --path . --script res://tests/test_runner.gd

const Maze := preload("res://scripts/maze_gen.gd")
const Launch := preload("res://scripts/launch_math.gd")
const TopScript := preload("res://scripts/spinning_top.gd")
const TiltScript := preload("res://scripts/tilt_input.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	await _run()
	quit(1 if failed > 0 else 0)


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
	await test_top_wall_hit()
	await test_top_physics_wall_hit()
	print("== Tilt keyboard ==")
	test_tilt_keyboard()
	print("== Main scene ==")
	await test_main_scene()
	print("\nRESULT: %d passed, %d failed" % [passed, failed])


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


func test_top_wall_hit() -> void:
	var top: SpinningTop = TopScript.new()
	root.add_child(top)
	await process_frame
	top.set_initial_power(50.0)
	var p0: float = top.spin_power
	top.apply_wall_hit(10.0)
	check(top.spin_power < p0, "wall hit reduces power")
	top.set_initial_power(3.0)
	top.apply_wall_hit(50.0)
	check(top.is_fallen(), "zero power triggers fall")
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