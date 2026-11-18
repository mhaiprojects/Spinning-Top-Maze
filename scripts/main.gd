extends Node2D
## Wave flow: maze, launch, run, goal / fall over.

enum Phase { LAUNCH, RUN, CLEARED, FELL, PAUSED }

const BASE_TOP_H := 228.0
const BASE_BOTTOM_H := 140.0
const MARGIN := 10.0

var phase: Phase = Phase.LAUNCH
var wave: int = 1
var maze_seed: int = 0
var _maze: MazeWorld
var _top: SpinningTop
var _launch: LaunchMinigame
var _goal: Area2D
var _play_rect := Rect2()
var _overlay_busy := false
var _shake := 0.0
var _base_position := Vector2.ZERO

@onready var _ui: CanvasLayer = $UI


func _ready() -> void:
	_base_position = position
	var layer := CanvasLayer.new()
	layer.name = "DragStick"
	layer.layer = 5
	var stick := DragStickOverlay.new()
	stick.name = "Draw"
	layer.add_child(stick)
	add_child(layer)
	_maze = MazeWorld.new()
	add_child(_maze)
	_top = SpinningTop.new()
	add_child(_top)
	_top.fell_over.connect(_on_fell_over)
	_top.hit_wall.connect(_on_top_hit_wall)
	_launch = LaunchMinigame.new()
	add_child(_launch)
	_launch.released.connect(_on_launch_released)
	_goal = Area2D.new()
	var goal_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 40)
	goal_shape.shape = rect
	_goal.add_child(goal_shape)
	_goal.body_entered.connect(_on_goal_body)
	_goal.collision_layer = 0
	_goal.collision_mask = 1
	_goal.monitoring = true
	_goal.monitorable = false
	add_child(_goal)
	_new_wave_seed()
	get_viewport().size_changed.connect(_on_viewport_changed)
	call_deferred("_bootstrap")


func _bootstrap() -> void:
	_layout_all()
	_start_launch()
	print("WAVE %d STARTED" % wave)


func _process(delta: float) -> void:
	_update_steer_block()
	if _shake > 0.01:
		_shake = maxf(0.0, _shake - delta * 8.0)
		position = _base_position + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 6.0
	else:
		position = _base_position


func apply_screen_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _update_steer_block() -> void:
	var tin: Node = get_node_or_null("/root/TiltInput")
	if tin == null or not tin.has_method("set_steer_blocked"):
		return
	var blocked: bool = phase != Phase.RUN or _overlay_busy
	if _ui.has_method("overlay_visible") and _ui.overlay_visible():
		blocked = true
	tin.call("set_steer_blocked", blocked)


func _on_viewport_changed() -> void:
	_layout_all()
	if phase == Phase.LAUNCH:
		_position_launch_bar()


func _layout_all() -> void:
	var vp: Rect2 = get_viewport().get_visible_rect()
	var sy: float = vp.size.y / 1280.0
	var top_h: float = BASE_TOP_H * sy
	var bot_h: float = BASE_BOTTOM_H * sy
	_play_rect = Rect2(
		MARGIN,
		top_h,
		vp.size.x - MARGIN * 2.0,
		maxf(80.0, vp.size.y - top_h - bot_h)
	)
	if _ui.has_method("set_layout_rects"):
		_ui.set_layout_rects(vp.size, _play_rect, top_h, bot_h)
	_generate_maze_data_only()
	if not _maze.maze_data.is_empty():
		_maze.build(_maze.maze_data, _play_rect)
		_position_goal()
	_position_launch_bar()


func _generate_maze_data_only() -> void:
	var data: Dictionary = MazeGen.generate(wave, maze_seed)
	_maze.maze_data = data


func _new_wave_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	maze_seed = int(rng.randi())


func _generate_maze() -> void:
	var data: Dictionary = MazeGen.generate(wave, maze_seed)
	_maze.build(data, _play_rect)
	_position_goal()
	_position_launch_bar()


func _set_goal_active(on: bool) -> void:
	_goal.set_deferred("monitoring", on)


func _position_goal() -> void:
	if _maze.maze_data.is_empty():
		return
	_goal.global_position = _maze.goal_area_rect().get_center()
	var gs: RectangleShape2D = _goal.get_child(0).shape as RectangleShape2D
	gs.size = _maze.goal_area_rect().size * 0.85


func _position_launch_bar() -> void:
	if _play_rect.size.x < 1.0:
		return
	var vp: Rect2 = get_viewport().get_visible_rect()
	var bot_h: float = BASE_BOTTOM_H * (vp.size.y / 1280.0)
	var bar := Rect2(
		_play_rect.position.x + 16,
		vp.size.y - bot_h + 12,
		_play_rect.size.x - 32,
		maxf(48.0, bot_h - 24)
	)
	if phase == Phase.LAUNCH and _launch.active:
		_launch.setup(bar, wave)


func _start_launch() -> void:
	_overlay_busy = false
	phase = Phase.LAUNCH
	_set_goal_active(false)
	_generate_maze()
	_top.visible = false
	_top.set_run_active(false)
	_top.global_position = Vector2(-4000, -4000)
	var vp: Rect2 = get_viewport().get_visible_rect()
	var bot_h: float = BASE_BOTTOM_H * (vp.size.y / 1280.0)
	var bar := Rect2(
		_play_rect.position.x + 16,
		vp.size.y - bot_h + 12,
		_play_rect.size.x - 32,
		maxf(48.0, bot_h - 24)
	)
	_launch.setup(bar, wave)
	_launch.visible = true
	if _ui.has_method("on_phase_launch"):
		_ui.on_phase_launch(wave)


func _on_launch_released(power: float) -> void:
	call_deferred("_begin_run", power)


func _begin_run(power: float) -> void:
	_overlay_busy = false
	phase = Phase.RUN
	_set_goal_active(true)
	_top.visible = true
	_launch.visible = false
	_launch.cancel()
	_top.configure_for_wave(wave)
	_top.reset_top(_maze.start_position(), power)
	_top.set_run_active(true)
	if _ui.has_method("on_phase_run"):
		_ui.on_phase_run(wave)


func _on_fell_over() -> void:
	if phase != Phase.RUN:
		return
	phase = Phase.FELL
	call_deferred("_finish_fell_over")


func _finish_fell_over() -> void:
	_set_goal_active(false)
	_top.set_run_active(false)
	_overlay_busy = true
	if _ui.has_method("on_fell_over"):
		_ui.on_fell_over()


func _on_goal_body(body: Node) -> void:
	if phase != Phase.RUN or body != _top or _overlay_busy:
		return
	call_deferred("_finish_goal", body)


func _finish_goal(_body: Node) -> void:
	if phase != Phase.RUN:
		return
	_set_goal_active(false)
	phase = Phase.CLEARED
	_top.set_run_active(false)
	_overlay_busy = true
	if _ui.has_method("on_wave_cleared"):
		_ui.on_wave_cleared(wave)


func request_retry_same_wave() -> void:
	if phase != Phase.FELL:
		return
	force_retry_wave()


func force_retry_wave() -> void:
	get_tree().paused = false
	_overlay_busy = false
	_new_wave_seed()
	call_deferred("_start_launch")


func advance_wave() -> void:
	if phase != Phase.CLEARED:
		return
	_overlay_busy = false
	wave += 1
	_new_wave_seed()
	call_deferred("_advance_wave_deferred")


func _advance_wave_deferred() -> void:
	_start_launch()
	print("WAVE %d STARTED" % wave)


func _on_top_hit_wall() -> void:
	apply_screen_shake(1.35)


func toggle_pause() -> void:
	if phase == Phase.RUN:
		phase = Phase.PAUSED
		get_tree().paused = true
	elif phase == Phase.PAUSED:
		phase = Phase.RUN
		get_tree().paused = false


func _try_launch_release() -> void:
	if phase == Phase.LAUNCH:
		_launch.try_release()


func overlay_primary_action() -> void:
	if not _overlay_busy:
		return
	if phase == Phase.CLEARED:
		advance_wave()
	elif phase == Phase.FELL:
		request_retry_same_wave()


func _unhandled_input(event: InputEvent) -> void:
	if _ui.has_method("handle_overlay_input") and _ui.handle_overlay_input(event):
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if phase == Phase.LAUNCH:
			_try_launch_release()
		return

	var screen_pos := Vector2.ZERO
	if event is InputEventScreenTouch:
		screen_pos = event.position
		if event.pressed:
			if _ui.has_method("consumes_steering_at") and _ui.consumes_steering_at(screen_pos):
				return
			if phase == Phase.LAUNCH:
				_try_launch_release()
				var tin: Node = get_node_or_null("/root/TiltInput")
				if tin and tin.has_method("request_web_permission"):
					tin.call("request_web_permission")
				return
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		screen_pos = event.position
		if event.pressed:
			if _ui.has_method("consumes_steering_at") and _ui.consumes_steering_at(screen_pos):
				return
			if phase == Phase.LAUNCH:
				_try_launch_release()
				return

	var tin: Node = get_node_or_null("/root/TiltInput")
	if tin and tin.has_method("handle_input"):
		tin.call("handle_input", event)