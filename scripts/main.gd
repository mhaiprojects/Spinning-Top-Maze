extends Node2D
## Wave flow: maze, launch timing bar, hand release (INTRO), run, goal / fall over.
## The goal is exactly one tile; it is won only when the top's centre is on it
## (no trigger area and no pull toward it).

const LaunchIntroScene := preload("res://scripts/launch_intro.gd")
const ViewportLayout := preload("res://scripts/viewport_layout.gd")

enum Phase { INTRO, LAUNCH, RUN, GOAL_FALL, CLEARED, FELL, PAUSED }

const BASE_TOP_H := 152.0
const BASE_BOTTOM_H := 140.0
const MARGIN := 10.0

var phase: Phase = Phase.LAUNCH
var wave: int = 1
var maze_seed: int = 0
var _maze: MazeWorld
var _top: SpinningTop
var _launch: LaunchMinigame
var _release_power := 0.0
var _play_rect := Rect2()
var _overlay_busy := false
var _shake := 0.0
var _base_position := Vector2.ZERO
var _intro: Control

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
	_top.victory_complete.connect(_on_victory_complete)
	_top.hit_wall.connect(_on_top_hit_wall)
	var intro_layer := CanvasLayer.new()
	intro_layer.name = "LaunchIntroLayer"
	intro_layer.layer = 8
	_intro = LaunchIntroScene.new()
	intro_layer.add_child(_intro)
	add_child(intro_layer)
	_intro.finished.connect(_on_intro_finished)
	_launch = LaunchMinigame.new()
	add_child(_launch)
	_launch.released.connect(_on_launch_released)
	_new_wave_seed()
	get_viewport().size_changed.connect(_on_viewport_changed)
	call_deferred("_wire_play_background")
	call_deferred("_bootstrap")


func _wire_play_background() -> void:
	var tin: Node = get_node_or_null("/root/TiltInput")
	if tin == null:
		return
	if tin.has_signal("background_changed"):
		tin.background_changed.connect(_on_play_background_changed)
	if tin.has_method("selected_background"):
		_maze.set_play_background(tin.call("selected_background"))


func _on_play_background_changed(id: int) -> void:
	_maze.set_play_background(id)


func _bootstrap() -> void:
	_layout_all()
	_start_launch()
	print("WAVE %d STARTED" % wave)


func _process(delta: float) -> void:
	_update_steer_block()
	# Only write position while shaking (or when returning to rest once).
	# Assigning position every frame dirties this Node2D's transform and snaps
	# the child RigidBody2D top back to its spawn pose: velocity still updates,
	# but the top never actually moves.
	if _shake > 0.01:
		_shake = maxf(0.0, _shake - delta * 8.0)
		position = _base_position + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 6.0
	elif position != _base_position:
		position = _base_position


func apply_screen_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _update_steer_block() -> void:
	var tin: Node = get_node_or_null("/root/TiltInput")
	if tin == null or not tin.has_method("set_steer_blocked"):
		return
	var blocked: bool = phase != Phase.RUN or _overlay_busy or phase == Phase.GOAL_FALL
	if _ui.has_method("overlay_visible") and _ui.overlay_visible():
		blocked = true
	if _ui.has_method("physics_settings_menu_open") and _ui.physics_settings_menu_open():
		blocked = true
	if _ui.has_method("input_picker_open") and _ui.input_picker_open():
		blocked = true
	tin.call("set_steer_blocked", blocked)


func _on_viewport_changed() -> void:
	_layout_all()
	if phase == Phase.LAUNCH:
		_position_launch_bar()


func _layout_all() -> void:
	_apply_play_layout(false)


func relayout_for_hud() -> void:
	_apply_play_layout(true)


func play_rect_screen() -> Rect2:
	return _play_rect


func launch_bar_screen_rect() -> Rect2:
	if _launch and _launch.has_method("bar_screen_rect"):
		return _launch.call("bar_screen_rect") as Rect2
	return Rect2()


func _apply_play_layout(_hud_only: bool) -> void:
	var vp: Rect2 = get_viewport().get_visible_rect()
	var layout: Dictionary = ViewportLayout.scaled_heights(vp.size)
	var top_h: float = float(layout.top)
	if _ui and _ui.has_method("hud_band_height"):
		top_h = maxf(top_h, _ui.hud_band_height())
	var bot_h: float = float(layout.bottom)
	var margin: float = float(layout.margin)
	_play_rect = Rect2(
		margin,
		top_h,
		maxf(40.0, vp.size.x - margin * 2.0),
		maxf(80.0, vp.size.y - top_h - bot_h)
	)
	if _ui and _ui.has_method("set_layout_rects"):
		_ui.set_layout_rects(vp.size, _play_rect, top_h, bot_h)
		if _ui.has_method("hud_band_height"):
			var measured: float = _ui.hud_band_height()
			if measured > top_h + 0.5:
				top_h = measured
				_play_rect.position = Vector2(margin, top_h)
				_play_rect.size = Vector2(
					maxf(40.0, vp.size.x - margin * 2.0),
					maxf(80.0, vp.size.y - top_h - bot_h)
				)
				_ui.set_layout_rects(vp.size, _play_rect, top_h, bot_h)
	if not _hud_only:
		_generate_maze_data_only()
	if not _maze.maze_data.is_empty():
		_maze.build(_maze.maze_data, _play_rect)
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
	_position_launch_bar()


func _launch_bar_rect(vp: Rect2) -> Rect2:
	var bot_h: float = float(ViewportLayout.scaled_heights(vp.size).bottom)
	var s: float = float(ViewportLayout.scaled_heights(vp.size).scale)
	var inset: float = maxf(12.0, 16.0 * s)
	var bar_left: float = maxf(
		_play_rect.position.x + inset,
		ViewportLayout.launch_bar_left_clearance(vp.size)
	)
	var bar_right: float = _play_rect.position.x + _play_rect.size.x - inset
	var bar := Rect2(
		bar_left,
		maxf(_play_rect.end.y + 4.0, vp.size.y - bot_h + 8.0 * s),
		maxf(40.0, bar_right - bar_left),
		maxf(36.0, minf(bot_h - 16.0 * s, vp.size.y - (_play_rect.end.y + 8.0)))
	)
	if bar.end.y > vp.size.y:
		bar.size.y = maxf(32.0, vp.size.y - bar.position.y - 2.0)
	return bar


func _position_launch_bar(setup := false) -> void:
	if _play_rect.size.x < 1.0:
		return
	var vp: Rect2 = get_viewport().get_visible_rect()
	var bar: Rect2 = _launch_bar_rect(vp)
	if phase == Phase.LAUNCH and (setup or _launch.active):
		_launch.setup(bar, wave)


func _start_launch() -> void:
	_overlay_busy = false
	_generate_maze()
	_top.visible = false
	_top.set_run_active(false)
	_park_top_off_maze()
	_show_launch_bar()


## Timing bar first; the hand release animation follows once it resolves.
func _show_launch_bar() -> void:
	phase = Phase.LAUNCH
	_position_launch_bar(true)
	_launch.visible = true
	if _ui.has_method("on_phase_launch"):
		_ui.on_phase_launch(wave)


func _on_launch_released(power: float) -> void:
	if phase != Phase.LAUNCH:
		return
	_release_power = power
	_launch.visible = false
	phase = Phase.INTRO
	if _ui.has_method("on_phase_intro"):
		_ui.on_phase_intro(wave)
	_intro.start_at(_maze.run_spawn_position())


func _park_top_off_maze() -> void:
	var dock: Vector2 = _play_rect.position + Vector2(_play_rect.size.x * 0.5, _play_rect.end.y + 72)
	_top.global_position = dock
	_top.sync_physics_state()


func _begin_run(power: float) -> void:
	_overlay_busy = false
	phase = Phase.RUN
	_top.visible = true
	_launch.visible = false
	_launch.cancel()
	_top.configure_for_wave(wave)
	_top.reset_top(_maze.run_spawn_position(), power)
	_top.wake_for_run()
	_top.call_deferred("sync_physics_state")
	if _ui.has_method("on_phase_run"):
		_ui.on_phase_run(wave)


func _on_intro_finished() -> void:
	if phase != Phase.INTRO:
		return
	call_deferred("_begin_run", _release_power)


func _on_fell_over() -> void:
	if phase != Phase.RUN:
		return
	phase = Phase.FELL
	call_deferred("_finish_fell_over")


func _on_victory_complete() -> void:
	if phase != Phase.GOAL_FALL:
		return
	phase = Phase.CLEARED
	_top.set_run_active(false)
	_overlay_busy = true
	if _ui.has_method("on_wave_cleared"):
		_ui.on_wave_cleared(wave)


func _finish_fell_over() -> void:
	_top.set_run_active(false)
	_overlay_busy = true
	if _ui.has_method("on_fell_over"):
		_ui.on_fell_over()


func _physics_process(_delta: float) -> void:
	_check_goal_reached()


## Win only when the top's centre is actually on the single goal tile.
func _check_goal_reached() -> bool:
	if phase != Phase.RUN or _overlay_busy or not _top.is_run_active():
		return false
	if not _maze.is_on_goal_tile(_top.global_position):
		return false
	_finish_goal()
	return true


func _finish_goal() -> void:
	if phase != Phase.RUN:
		return
	phase = Phase.GOAL_FALL
	_top.start_goal_victory()


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


func _gui_editing_text() -> bool:
	var fo: Control = get_viewport().gui_get_focus_owner()
	return fo is LineEdit


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
	if _ui.has_method("physics_settings_menu_open") and _ui.physics_settings_menu_open():
		return
	if _ui.has_method("input_picker_open") and _ui.input_picker_open():
		return
	if _gui_editing_text():
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if phase == Phase.INTRO:
			_intro.skip()
			get_viewport().set_input_as_handled()
			return
		if phase == Phase.LAUNCH:
			_try_launch_release()
		return
	if phase == Phase.INTRO:
		if (
			(event is InputEventScreenTouch and event.pressed)
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
		):
			_intro.skip()
			get_viewport().set_input_as_handled()
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