extends SceneTree
## GUI smoke: simple shot or full wave flow.
## DISPLAY=:2 godot --path . --script res://tests/screenshot.gd -- prefix [--flow]

const Launch := preload("res://scripts/launch_math.gd")
const MainScript := preload("res://scripts/main.gd")


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
	var path: String = "%s/%s" % [_args().prefix, name]
	var img: Image = root.get_texture().get_image()
	if img:
		img.save_png(path)
		print("saved ", path)


func _find(scene: Node, type) -> Node:
	for c in scene.get_children():
		if is_instance_of(c, type):
			return c
	return null


func _run() -> void:
	var cfg: Dictionary = _args()
	if cfg.flow:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cfg.prefix))
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	var main: Node = inst
	var ui: Node = inst.get_node("UI")
	var top: SpinningTop = _find(inst, SpinningTop) as SpinningTop
	var launch: LaunchMinigame = _find(inst, LaunchMinigame) as LaunchMinigame
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
		tin.call("set_test_steer_vector", Vector2(0, -0.7))
	for i in 90:
		await process_frame
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
		if cfg.flow and wave_target == 2:
			_save("v2_wavecomplete.png")
		var rect: Rect2 = ui.call("overlay_button_rect") as Rect2
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = rect.get_center()
		Input.parse_input_event(click)
		click.pressed = false
		click.position = rect.get_center()
		Input.parse_input_event(click)
		for i in 8:
			await process_frame
		if int(main.get("wave")) < wave_target:
			ui.call("_activate_overlay_action")
		for i in 30:
			await process_frame
		check_wave_started(main, wave_target)
	if tin and tin.has_method("clear_test_steer_vector"):
		tin.call("clear_test_steer_vector")


func _activate_overlay(ui: Node) -> void:
	if ui.has_method("_activate_overlay_action"):
		ui.call("_activate_overlay_action")


func check_wave_started(main: Node, w: int) -> void:
	var got: int = int(main.get("wave"))
	if got == w:
		print("WAVE %d STARTED" % w)
	else:
		push_error("expected wave %d got %d" % [w, got])