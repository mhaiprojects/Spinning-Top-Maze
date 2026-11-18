extends SceneTree
## GUI smoke capture: launch, steer briefly, save PNG.
## DISPLAY=:2 godot --path . --script res://tests/screenshot.gd -- out.png

const Launch := preload("res://scripts/launch_math.gd")


func _initialize() -> void:
	await _run()
	quit(0)


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		push_error("main scene failed to load")
		quit(1)
		return
	var inst := scene.instantiate()
	root.add_child(inst)
	for i in 10:
		await process_frame
	var launch: LaunchMinigame = null
	var top: SpinningTop = null
	for c in inst.get_children():
		if c is LaunchMinigame:
			launch = c
		if c is SpinningTop:
			top = c
	var power: float = Launch.power_for_offset(0.05)
	if launch:
		launch._pos = 0.05
		launch.try_release()
	for i in 150:
		await process_frame
		if top != null and top.visible:
			break
	var tin: Node = root.get_node_or_null("TiltInput")
	if tin and tin.has_method("set_test_steer_vector"):
		tin.call("set_test_steer_vector", Vector2(0, -1))
	for i in 120:
		await process_frame
	var out := "/tmp/spinning-top-maze-shot.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = str(args[0])
	var img: Image = root.get_texture().get_image()
	if img:
		img.save_png(out)
		print("saved ", out)
	else:
		push_error("no viewport image")
		quit(1)