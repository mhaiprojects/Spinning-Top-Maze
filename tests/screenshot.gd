extends SceneTree
## GUI smoke: simple shot or full wave flow.
## DISPLAY=:2 godot --path . --resolution 450x800 --script res://tests/screenshot.gd -- prefix --flow

const Launch := preload("res://scripts/launch_math.gd")
const MainScript := preload("res://scripts/main.gd")

var _prefix := "/tmp/stm"


func _initialize() -> void:
	await _run()
	quit(0)


func _args() -> Dictionary:
	var user := OS.get_cmdline_user_args()
	var out := {"prefix": "/tmp/stm", "flow": false}
	if user.is_empty():
		return out
	if user.has("--flow"):
		out.flow = true
	for a in user:
		var s := str(a)
		if s != "--flow" and not s.begins_with("-"):
			out.prefix = s
			break
	return out


func _save(name: String) -> void:
	var path: String = "%s/%s" % [_prefix, name]
	var img: Image = root.get_texture().get_image()
	if img:
		img.save_png(path)
		print("saved ", path)


func _find(scene: Node, type) -> Node:
	for c in scene.get_children():
		if is_instance_of(c, type):
			return c
	return null


func _click_at(pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	Input.parse_input_event(up)


func _advance_from_overlay(ui: Node, main: Node, wave_target: int) -> void:
	var rect: Rect2 = ui.call("overlay_button_rect") as Rect2
	await _click_at(rect.get_center())
	for i in 8:
		await process_frame
	if int(main.get("wave")) < wave_target:
		ui.call("_activate_overlay_action")
	for i in 30:
		await process_frame
	check_wave_started(main, wave_target)


func _stitch_strip(names: PackedStringArray, out_name: String) -> void:
	var imgs: Array[Image] = []
	for n in names:
		var p: String = "%s/%s" % [_prefix, n]
		if not FileAccess.file_exists(p):
			continue
		var im := Image.load_from_file(p)
		if im:
			imgs.append(im)
	if imgs.is_empty():
		return
	var w := 0
	var h := 0
	for im in imgs:
		w += im.get_width()
		h = maxi(h, im.get_height())
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var ox := 0
	for im in imgs:
		out.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(ox, 0))
		ox += im.get_width()
	var path: String = "%s/%s" % [_prefix, out_name]
	out.save_png(path)
	print("saved ", path)


func _run() -> void:
	var cfg: Dictionary = _args()
	_prefix = cfg.prefix
	if cfg.flow:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cfg.prefix))
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	var main: Node = inst
	var ui: Node = inst.get_node("UI")
	var top: SpinningTop = _find(inst, SpinningTop) as SpinningTop
	var maze: MazeWorld = _find(inst, MazeWorld) as MazeWorld
	for i in 25:
		await process_frame
	if cfg.flow:
		_save("v2_minigame.png")
	var power: float = Launch.power_for_offset(0.0)
	main.call("_begin_run", power)
	for i in 20:
		await process_frame
	var tin: Node = root.get_node_or_null("TiltInput")
	if tin and tin.has_method("set_test_steer_vector"):
		tin.call("set_test_steer_vector", Vector2(0, -0.85))
	for i in 100:
		await physics_frame
	if cfg.flow:
		_save("v2_gameplay.png")
	if not cfg.flow:
		_save("shot.png")
		return
	if maze == null:
		maze = _find(inst, MazeWorld) as MazeWorld
	if top == null:
		top = _find(inst, SpinningTop) as SpinningTop
	if maze == null or top == null:
		push_error("screenshot flow missing maze or top")
		return

	# Wall hit + sparks
	if tin and tin.has_method("set_test_steer_vector"):
		tin.call("set_test_steer_vector", Vector2(0.95, 0.0))
	top.global_position = maze.start_position() + Vector2(12, 0)
	top.linear_velocity = Vector2(420, 0)
	for i in 25:
		await physics_frame
	if top.has_method("apply_wall_hit"):
		top.call("apply_wall_hit", 55.0)
	if main.has_method("apply_screen_shake"):
		main.call("apply_screen_shake", 2.0)
	for i in 15:
		await process_frame
	_save("v2_hit.png")

	# Fell over overlay
	top.set_initial_power(2.0)
	top.set_run_active(true)
	for _j in 4:
		top.apply_wall_hit(20.0)
		await process_frame
	if not top.is_fallen():
		top.set_initial_power(0.0)
		await physics_frame
	if int(main.get("phase")) != MainScript.Phase.FELL:
		main.set("phase", MainScript.Phase.RUN)
		if top.has_signal("fell_over"):
			top.emit_signal("fell_over")
	for i in 20:
		await process_frame
	_save("v2_fell.png")

	# Restart wave 1 run for wave flow shots
	main.call("force_retry_wave")
	for i in 30:
		await process_frame
	main.call("_begin_run", Launch.power_for_offset(0.0))
	for i in 20:
		await process_frame

	for wave_target in [2, 3]:
		if int(main.get("phase")) != MainScript.Phase.RUN:
			main.call("_begin_run", Launch.power_for_offset(0.0))
			for i in 15:
				await process_frame
		top.global_position = maze.goal_area_rect().get_center()
		for i in 10:
			await process_frame
		main.call("_on_goal_body", top)
		for i in 20:
			await process_frame
		if wave_target == 2:
			_save("v2_wavecomplete.png")
		await _advance_from_overlay(ui, main, wave_target)
		main.call("_begin_run", Launch.power_for_offset(0.0))
		for i in 25:
			await physics_frame
		if tin and tin.has_method("set_test_steer_vector"):
			tin.call("set_test_steer_vector", Vector2(0, -0.5))
		for i in 40:
			await physics_frame
		if wave_target == 2:
			_save("v2_wave2.png")
		else:
			_save("v2_wave3.png")
		if tin and tin.has_method("set_test_steer_vector"):
			tin.call("set_test_steer_vector", Vector2.ZERO)

	_stitch_strip(
		PackedStringArray(["v2_minigame.png", "v2_gameplay.png", "v2_wavecomplete.png"]),
		"v2.png"
	)

	if tin and tin.has_method("clear_test_steer_vector"):
		tin.call("clear_test_steer_vector")


func check_wave_started(main: Node, w: int) -> void:
	var got: int = int(main.get("wave"))
	if got == w:
		print("WAVE %d STARTED" % w)
	else:
		push_error("expected wave %d got %d" % [w, got])