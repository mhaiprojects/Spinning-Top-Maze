extends SceneTree
## GUI v3 capture. DISPLAY=:2 godot --path . --resolution 450x800 --script res://tests/screenshot.gd -- /home/systemadmin/agent-tools/stm --flow

const Launch := preload("res://scripts/launch_math.gd")
const MainScript := preload("res://scripts/main.gd")
const InputModes := preload("res://scripts/input_modes.gd")
const PlayBg := preload("res://scripts/play_background.gd")

const SETTINGS_TEST := "user://test_stm_screenshot.cfg"
var _prefix := "/tmp/stm"
var _flow := false
var _bg_flow := false


func _initialize() -> void:
	await _run()
	quit(0)


func _args() -> Dictionary:
	var user := OS.get_cmdline_user_args()
	var out := {"prefix": "/tmp/stm", "flow": false, "bg_flow": false}
	for a in user:
		var s := str(a)
		if s == "--flow":
			out.flow = true
		elif s == "--bg-flow":
			out.bg_flow = true
		elif not s.begins_with("-"):
			out.prefix = s
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


func _skip_intro(main: Node) -> void:
	if main.has_node("LaunchIntroLayer"):
		main.get_node("LaunchIntroLayer").get_child(0).call("skip")
	for i in 12:
		await process_frame


func _stitch_grid(names: PackedStringArray, out_name: String, cols: int) -> void:
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
	var cw := 0
	var ch := 0
	for im in imgs:
		cw = maxi(cw, im.get_width())
		ch = maxi(ch, im.get_height())
	var rows := int(ceil(float(imgs.size()) / float(cols)))
	var out := Image.create(cw * cols, ch * rows, false, Image.FORMAT_RGBA8)
	var i := 0
	for im in imgs:
		var cx: int = i % cols
		var cy: int = i / cols
		out.blit_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i(cx * cw, cy * ch))
		i += 1
	out.save_png("%s/%s" % [_prefix, out_name])
	print("saved ", out_name)


func _run_bg_boards(main: Node, tin: Node) -> void:
	var files := PackedStringArray([
		"bg_tabletop.png",
		"bg_chopping.png",
		"bg_planks.png",
		"bg_stone.png",
	])
	for i in PlayBg.ORDER.size():
		var id: int = PlayBg.ORDER[i]
		if tin and tin.has_method("set_background"):
			tin.call("set_background", id)
		for j in 10:
			await process_frame
		await _skip_intro(main)
		main.call("_begin_run", 94.0)
		for j in 25:
			await physics_frame
		_save(files[i])
	_stitch_grid(files, "bg.png", 2)


func _run() -> void:
	var cfg: Dictionary = _args()
	_prefix = cfg.prefix
	_flow = cfg.flow
	_bg_flow = cfg.bg_flow
	if FileAccess.file_exists(SETTINGS_TEST):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_TEST))
	var tin0: Node = root.get_node_or_null("TiltInput")
	if tin0 and tin0.has_method("set_settings_path"):
		tin0.call("set_settings_path", SETTINGS_TEST)
	if _flow or _bg_flow:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_prefix))
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	var main: Node = inst
	var ui: Node = inst.get_node("UI")
	var top: SpinningTop = _find(inst, SpinningTop) as SpinningTop
	var maze: MazeWorld = _find(inst, MazeWorld) as MazeWorld
	for i in 15:
		await process_frame
	var tin: Node = root.get_node_or_null("TiltInput")
	if _bg_flow and not _flow:
		await _run_bg_boards(main, tin)
		return
	if not _flow:
		_save("shot.png")
		return
	for i in 8:
		await process_frame
	_save("v3_minigame.png")
	var power: float = Launch.power_for_offset(0.0)
	main.call("_on_launch_released", power)
	for i in 40:
		await process_frame
	_save("v3_intro.png")
	await _skip_intro(main)
	for i in 12:
		await process_frame
	for i in 120:
		await physics_frame
	if tin == null:
		tin = root.get_node_or_null("TiltInput")
	if tin:
		tin.call("set_mode", InputModes.Mode.DRAG)
		if tin.has_method("set_steer_blocked"):
			tin.call("set_steer_blocked", false)
	for i in 90:
		await physics_frame
	if tin:
		var down := InputEventMouseButton.new()
		down.pressed = true
		down.button_index = MOUSE_BUTTON_LEFT
		down.position = Vector2(225, 450)
		Input.parse_input_event(down)
		await process_frame
		for step in 10:
			var mot := InputEventMouseMotion.new()
			mot.position = Vector2(225, lerpf(450.0, 300.0, float(step) / 10.0))
			mot.button_mask = MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(mot)
			await physics_frame
	_save("v3_gameplay.png")
	maze = _find(inst, MazeWorld) as MazeWorld
	top = _find(inst, SpinningTop) as SpinningTop
	if maze != null and top != null:
		main.set("phase", MainScript.Phase.RUN)
		top.set_run_active(true)
		top.global_position = maze.start_position() + Vector2(15, 0)
		top.linear_velocity = Vector2(400, 0)
		for i in 8:
			await physics_frame
		top.wake_for_run()
		top.apply_wall_hit(90.0, Vector2(10, 0))
		if main.has_method("apply_screen_shake"):
			main.call("apply_screen_shake", 1.5)
		for i in 10:
			await physics_frame
		_save("v3_hit.png")
		for i in 12:
			await physics_frame
		top.wake_for_run()
		top.global_position = maze.goal_area_rect().get_center()
		top.reset_top(maze.goal_area_rect().get_center(), top.spin_power)
		main.call("_check_goal_reached")
		for i in 35:
			await physics_frame
		_save("v3_goal_fall.png")
		for i in 50:
			await physics_frame
		_save("v3_cleared.png")
		main.call("force_retry_wave")
		await _skip_intro(main)
		main.call("_begin_run", 8.0)
		for i in 200:
			await physics_frame
		_save("v3_power0_fall.png")
	else:
		push_error("screenshot flow lost maze or top after gameplay")
	_stitch_grid(
		PackedStringArray([
			"v3_intro.png",
			"v3_minigame.png",
			"v3_gameplay.png",
			"v3_hit.png",
			"v3_goal_fall.png",
			"v3_cleared.png",
			"v3_power0_fall.png",
		]),
		"v3.png",
		3
	)
	if tin and tin.has_method("clear_test_steer_vector"):
		tin.call("clear_test_steer_vector")