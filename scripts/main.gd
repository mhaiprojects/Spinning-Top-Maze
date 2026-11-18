extends Node2D
## Wave flow: maze, launch, run, goal / fall over.

enum Phase { LAUNCH, RUN, CLEARED, FELL, PAUSED }

const HUD_H := 120.0
const BOTTOM_H := 100.0

var phase: Phase = Phase.LAUNCH
var wave: int = 1
var maze_seed: int = 0
var _maze: MazeWorld
var _top: SpinningTop
var _launch: LaunchMinigame
var _goal: Area2D
var _play_rect := Rect2()

@onready var _ui: CanvasLayer = $UI


func _ready() -> void:
	_maze = MazeWorld.new()
	add_child(_maze)
	_top = SpinningTop.new()
	add_child(_top)
	_top.fell_over.connect(_on_fell_over)
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
	_start_launch()
	get_viewport().size_changed.connect(_on_viewport_changed)
	call_deferred("_layout_all")


func _on_viewport_changed() -> void:
	_layout_all()


func _layout_all() -> void:
	var vp: Rect2 = get_viewport().get_visible_rect()
	var top_h: float = HUD_H
	var bot_h: float = BOTTOM_H
	_play_rect = Rect2(8, top_h, vp.size.x - 16, vp.size.y - top_h - bot_h)
	_maze.build(_maze.maze_data if not _maze.maze_data.is_empty() else MazeGen.generate(wave, maze_seed), _play_rect)
	if _ui.has_method("set_layout_rects"):
		_ui.set_layout_rects(vp.size, _play_rect)


func _new_wave_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	maze_seed = int(rng.randi())


func _generate_maze() -> void:
	var data: Dictionary = MazeGen.generate(wave, maze_seed)
	_maze.build(data, _play_rect)
	_goal.global_position = _maze.goal_area_rect().get_center()
	var gs: RectangleShape2D = _goal.get_child(0).shape as RectangleShape2D
	gs.size = _maze.goal_area_rect().size * 0.9


func _start_launch() -> void:
	phase = Phase.LAUNCH
	_generate_maze()
	_top.visible = false
	_top.freeze = true
	var bar := Rect2(_play_rect.position.x + 24, _play_rect.end.y + 18, _play_rect.size.x - 48, 56)
	_launch.setup(bar, wave)
	if _ui.has_method("on_phase_launch"):
		_ui.on_phase_launch(wave)


func _on_launch_released(power: float) -> void:
	_begin_run(power)


func _begin_run(power: float) -> void:
	phase = Phase.RUN
	_top.visible = true
	_top.freeze = false
	_top.reset_top(_maze.start_position(), power)
	if _ui.has_method("on_phase_run"):
		_ui.on_phase_run()


func _on_fell_over() -> void:
	if phase != Phase.RUN:
		return
	phase = Phase.FELL
	_top.freeze = true
	if _ui.has_method("on_fell_over"):
		_ui.on_fell_over()


func _on_goal_body(body: Node) -> void:
	if phase != Phase.RUN or body != _top:
		return
	phase = Phase.CLEARED
	_top.freeze = true
	if _ui.has_method("on_wave_cleared"):
		_ui.on_wave_cleared(wave)


func request_retry_same_wave() -> void:
	maze_seed = maze_seed
	_start_launch()


func advance_wave() -> void:
	wave += 1
	_new_wave_seed()
	_start_launch()


func toggle_pause() -> void:
	if phase == Phase.RUN:
		phase = Phase.PAUSED
		get_tree().paused = true
	elif phase == Phase.PAUSED:
		phase = Phase.RUN
		get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	var tilt: Node = get_node_or_null("/root/TiltInput")
	if tilt and tilt.has_method("handle_input"):
		tilt.call("handle_input", event)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if phase == Phase.LAUNCH:
			_launch.try_release()
	if event is InputEventScreenTouch and event.pressed and phase == Phase.LAUNCH:
		_launch.try_release()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if phase == Phase.LAUNCH:
			_launch.try_release()
	if _ui.has_method("forward_input"):
		_ui.forward_input(event)