extends SceneTree
## DISPLAY=:2 godot --path . --resolution 450x800 --script res://tests/drag_repro_capture.gd
## Waits for xdotool (optional) then saves before/after frames and drag-fix.png.

const InputModes := preload("res://scripts/input_modes.gd")
const OUT := "/home/systemadmin/agent-tools/stm"

var _prefix := OUT


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(_prefix)
	await _run()
	quit(0)


func _save(name: String) -> void:
	var img: Image = root.get_texture().get_image()
	if img:
		img.save_png("%s/%s" % [_prefix, name])
		print("saved ", name)


func _stitch() -> void:
	var a := Image.load_from_file("%s/drag_before.png" % _prefix)
	var b := Image.load_from_file("%s/drag_after.png" % _prefix)
	if a == null or b == null:
		return
	var w: int = a.get_width() + b.get_width()
	var h: int = maxi(a.get_height(), b.get_height())
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.blit_rect(a, Rect2i(0, 0, a.get_width(), a.get_height()), Vector2i(0, 0))
	out.blit_rect(b, Rect2i(0, 0, b.get_width(), b.get_height()), Vector2i(a.get_width(), 0))
	out.save_png("%s/drag-fix.png" % _prefix)
	print("saved drag-fix.png")


func _find(scene: Node, type) -> Node:
	for c in scene.get_children():
		if is_instance_of(c, type):
			return c
	return null


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst := scene.instantiate()
	root.add_child(inst)
	var main: Node = inst
	var tin: Node = root.get_node_or_null("TiltInput")
	for i in 20:
		await process_frame
	tin.call("set_mode", InputModes.Mode.DRAG)
	print("READY drag mode — xdotool window to Drag (M×2), Space launch, drag up from (225,450)")
	for i in 90:
		await process_frame
	main.call("_begin_run", 95.0)
	for i in 20:
		await process_frame
	_save("drag_before.png")
	var top: SpinningTop = _find(inst, SpinningTop) as SpinningTop
	var y0: float = top.global_position.y if top else 0.0
	print("idle 2.5s — use xdotool drag now")
	for i in 150:
		await physics_frame
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(225, 450)
	Input.parse_input_event(down)
	await process_frame
	var up_evt := InputEventMouseButton.new()
	up_evt.button_index = MOUSE_BUTTON_LEFT
	up_evt.pressed = false
	up_evt.position = Vector2(225, 320)
	for step in range(12):
		var t: float = float(step + 1) / 12.0
		var mot := InputEventMouseMotion.new()
		mot.position = Vector2(225, lerpf(450.0, 320.0, t))
		mot.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(mot)
		await physics_frame
	Input.parse_input_event(up_evt)
	for i in 60:
		await physics_frame
	_save("drag_after.png")
	if top:
		print("top dy=%.1f vel=%.1f sleeping=%s" % [y0 - top.global_position.y, top.linear_velocity.length(), top.sleeping])
	_stitch()