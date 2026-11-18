class_name SpinningTop
extends RigidBody2D
## Top-down spinning top: tilt force, spin power, wall bounce loss.

signal fell_over
signal victory_complete
signal power_changed(value: float)
signal hit_wall

enum FallKind { NONE, POWER, GOAL }

const MIN_HIT_LOSS := 3.0
const MAX_HIT_POWER_LOSS := 12.0
const HIT_LOSS_SCALE := 0.22
const HIT_VEL_SCALE := 0.6
const HIT_COOLDOWN_MS := 150
const STEER_FORCE := 480.0
const MAX_LINEAR_SPEED := 520.0
const RADIUS := 46.0
const TRAIL_JUMP := 100.0
const TRAIL_LEN := 18
const FALL_ANIM := 1.0

var spin_power: float = 100.0
var _falling := false
var _fall_t := 0.0
var _fall_kind: FallKind = FallKind.NONE
var _goal_target := Vector2.ZERO
var _goal_start := Vector2.ZERO
var _fall_power_start := 100.0
var _wobble_phase := 0.0
var _last_hit_ms := 0
var _run_active := false
var _decay_rate := 2.2
var _hit_mult := 1.0
var _trail: Array[Vector2] = []
var _trail_line: Line2D
var _spark: CPUParticles2D
var _spark_flash: CPUParticles2D
var _dbg_tick := 0.0


func _ready() -> void:
	gravity_scale = 0.0
	linear_damp = 2.2
	angular_damp = 1.5
	can_sleep = false
	body_entered.connect(_on_body_entered)
	lock_rotation = false
	collision_layer = 1
	collision_mask = 6
	contact_monitor = true
	max_contacts_reported = 8
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)
	_trail_line = Line2D.new()
	_trail_line.width = 7.0
	_trail_line.default_color = Color(1, 0.65, 0.25, 0.5)
	_trail_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail_line.z_index = 8
	add_child(_trail_line)
	_spark = CPUParticles2D.new()
	_spark.z_index = 120
	_spark.emitting = false
	_spark.one_shot = true
	_spark.amount = 18
	_spark.lifetime = 0.35
	_spark.explosiveness = 1.0
	_spark.direction = Vector2.ZERO
	_spark.spread = 180.0
	_spark.initial_velocity_min = 120.0
	_spark.initial_velocity_max = 280.0
	_spark.scale_amount_min = 4.0
	_spark.scale_amount_max = 9.0
	_spark.color = Color(1.0, 0.95, 0.45)
	add_child(_spark)
	_spark_flash = CPUParticles2D.new()
	_spark_flash.z_index = 121
	_spark_flash.emitting = false
	_spark_flash.one_shot = true
	_spark_flash.amount = 10
	_spark_flash.lifetime = 0.25
	_spark_flash.explosiveness = 1.0
	_spark_flash.direction = Vector2.ZERO
	_spark_flash.spread = 180.0
	_spark_flash.initial_velocity_min = 60.0
	_spark_flash.initial_velocity_max = 140.0
	_spark_flash.color = Color(1, 1, 1)
	add_child(_spark_flash)
	z_index = 10
	set_run_active(false)


func configure_for_wave(wave: int) -> void:
	var p: Dictionary = Difficulty.params_for_wave(wave)
	_decay_rate = float(p.spin_decay)
	_hit_mult = float(p.wall_hit_mult)


func set_run_active(active: bool) -> void:
	if not active and _fall_kind != FallKind.NONE:
		return
	if active:
		wake_for_run()
		return
	_run_active = false
	contact_monitor = false
	collision_layer = 0
	collision_mask = 0
	freeze = false
	sleeping = false
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	_trail.clear()
	_trail_line.clear_points()
	_sync_physics_body()


func wake_for_run() -> void:
	_fall_kind = FallKind.NONE
	_falling = false
	_fall_t = 0.0
	_run_active = true
	collision_layer = 1
	collision_mask = 6
	freeze = false
	sleeping = false
	contact_monitor = true
	_trail.clear()
	_trail_line.clear_points()
	_sync_physics_body()


func _sync_physics_body() -> void:
	freeze = false
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	reset_physics_interpolation()
	var xf := global_transform
	PhysicsServer2D.body_set_state(
		get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		xf
	)
	PhysicsServer2D.body_set_state(
		get_rid(),
		PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY,
		Vector2.ZERO
	)
	PhysicsServer2D.body_set_state(
		get_rid(),
		PhysicsServer2D.BODY_STATE_ANGULAR_VELOCITY,
		0.0
	)


func set_initial_power(p: float) -> void:
	spin_power = clampf(p, 0.0, 100.0)
	power_changed.emit(spin_power)


func start_goal_victory(target: Vector2) -> void:
	_clear_trail()
	_fall_kind = FallKind.GOAL
	_falling = false
	_fall_t = 0.0
	_goal_target = target
	_goal_start = global_position
	_fall_power_start = spin_power
	_run_active = false
	collision_layer = 0
	collision_mask = 0
	freeze = true
	linear_velocity = Vector2.ZERO


func fall_kind() -> int:
	return int(_fall_kind)


func is_run_active() -> bool:
	return _run_active


func sync_physics_state() -> void:
	_sync_physics_body()


func _physics_process(delta: float) -> void:
	if _fall_kind == FallKind.GOAL:
		_advance_goal_fall(delta)
		return
	if _fall_kind == FallKind.POWER:
		_advance_power_fall(delta)
		return
	if not _run_active:
		return
	if _fall_kind == FallKind.NONE and freeze:
		freeze = false
		sleeping = false
	spin_power = maxf(0.0, spin_power - _decay_rate * delta)
	power_changed.emit(spin_power)
	if spin_power <= 0.0:
		_begin_power_fall()
		return
	var tin: Node = get_tree().root.get_node_or_null("TiltInput")
	if tin and tin.has_method("set_top_world_position"):
		tin.call("set_top_world_position", global_position)
	var tilt: Vector2 = _tilt_vector()
	if tilt.length_squared() > 0.0001:
		if sleeping:
			sleeping = false
		apply_central_force(tilt * STEER_FORCE * (0.35 + 0.65 * spin_power / 100.0))
	if linear_velocity.length() > MAX_LINEAR_SPEED:
		linear_velocity = linear_velocity.normalized() * MAX_LINEAR_SPEED
	_wobble_phase += delta * (8.0 + spin_power * 0.12)
	var spin_rate: float = (spin_power / 100.0) * 24.0
	angular_velocity = lerp(angular_velocity, spin_rate, 0.15)
	_push_trail()
	_debug_motion(delta)
	queue_redraw()


func _debug_motion(delta: float) -> void:
	if OS.get_environment("STM_DEBUG") != "1":
		return
	_dbg_tick += delta
	if _dbg_tick < 1.0:
		return
	_dbg_tick = 0.0
	print(
		"STM top pos=%s freeze=%s sleep=%s vel=%s run=%s fall=%d"
		% [global_position, freeze, sleeping, linear_velocity, _run_active, _fall_kind]
	)


func _clear_trail() -> void:
	_trail.clear()
	_trail_line.clear_points()


func _advance_goal_fall(delta: float) -> void:
	_fall_t += delta
	var u: float = clampf(_fall_t / FALL_ANIM, 0.0, 1.0)
	var glide: float = clampf(u / 0.55, 0.0, 1.0)
	var ease: float = glide * glide * (3.0 - 2.0 * glide)
	global_position = _goal_start.lerp(_goal_target, ease)
	spin_power = lerpf(_fall_power_start, 8.0, ease)
	power_changed.emit(spin_power)
	if u > 0.55:
		_falling = true
	if _fall_t >= FALL_ANIM:
		_fall_kind = FallKind.NONE
		_falling = false
		victory_complete.emit()
	queue_redraw()


func _advance_power_fall(delta: float) -> void:
	_fall_t += delta
	_falling = true
	spin_power = maxf(0.0, spin_power - 80.0 * delta)
	power_changed.emit(spin_power)
	queue_redraw()
	if _fall_t >= FALL_ANIM:
		_fall_kind = FallKind.NONE
		_emit_fell_over()


func _push_trail() -> void:
	if _trail.size() > 0 and global_position.distance_to(_trail.back()) > TRAIL_JUMP:
		_clear_trail()
	_trail.push_back(global_position)
	while _trail.size() > TRAIL_LEN:
		_trail.pop_front()
	_trail_line.clear_points()
	var i := 0
	for p in _trail:
		_trail_line.add_point(to_local(p))
		i += 1
	var c: Color = _trail_line.default_color
	c.a = 0.28 + 0.45 * (spin_power / 100.0)
	_trail_line.default_color = c


func _begin_power_fall() -> void:
	if _fall_kind != FallKind.NONE:
		return
	_fall_kind = FallKind.POWER
	_fall_t = 0.0
	_falling = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	freeze = true
	collision_layer = 0
	collision_mask = 0
	_run_active = false


func _emit_fell_over() -> void:
	fell_over.emit()


func is_fallen() -> bool:
	return _fall_kind == FallKind.POWER


func fall_progress() -> float:
	return clampf(_fall_t / FALL_ANIM, 0.0, 1.0)


func apply_wall_hit(impact_speed: float, spark_local: Vector2 = Vector2.ZERO) -> void:
	if not _run_active or _fall_kind != FallKind.NONE:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_hit_ms < HIT_COOLDOWN_MS:
		return
	_last_hit_ms = now
	var loss: float = clampf(
		impact_speed * HIT_LOSS_SCALE * _hit_mult,
		MIN_HIT_LOSS,
		MAX_HIT_POWER_LOSS
	)
	spin_power = maxf(0.0, spin_power - loss)
	power_changed.emit(spin_power)
	_spark.position = spark_local
	_spark.emitting = true
	_spark.restart()
	_spark_flash.position = spark_local
	_spark_flash.emitting = true
	_spark_flash.restart()
	linear_velocity *= HIT_VEL_SCALE
	hit_wall.emit()


func _on_body_entered(body: Node) -> void:
	if not _run_active or _fall_kind != FallKind.NONE:
		return
	if body.is_in_group("hazard_zone"):
		call_deferred("_apply_wall_hit_deferred", 25.0)
		return
	if body is StaticBody2D and body.is_in_group("maze_wall"):
		var impact: float = maxf(linear_velocity.length(), 40.0)
		call_deferred("_apply_wall_hit_deferred", impact)


func _apply_wall_hit_deferred(impact: float) -> void:
	apply_wall_hit(impact)


func _tilt_vector() -> Vector2:
	var n: Node = get_tree().root.get_node_or_null("TiltInput")
	if n and n.has_method("get_tilt_vector"):
		return n.call("get_tilt_vector") as Vector2
	return Vector2.ZERO


func reset_top(pos: Vector2, power: float) -> void:
	_falling = false
	_fall_kind = FallKind.NONE
	_fall_t = 0.0
	_clear_trail()
	spin_power = clampf(power, 0.0, 100.0)
	freeze = false
	sleeping = false
	global_position = pos
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	_sync_physics_body()
	power_changed.emit(spin_power)
	queue_redraw()


func _draw() -> void:
	var shadow_scale := Vector2(1.15, 0.42)
	draw_set_transform(Vector2(8, 12), 0.0, shadow_scale)
	draw_circle(Vector2.ZERO, RADIUS * 0.82, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var wobble: float = (1.0 - spin_power / 100.0) * 14.0 * sin(_wobble_phase)
	var precess: float = wobble * 0.04
	if _falling or _fall_kind == FallKind.GOAL:
		var t: float = fall_progress()
		precess += t * 0.9
		draw_set_transform(Vector2.ZERO, precess, Vector2(1.0 + t * 0.25, 0.55 + t * 0.35))
	else:
		draw_set_transform(Vector2.ZERO, precess, Vector2.ONE)
	var spin_ang: float = _wobble_phase * (1.2 + spin_power * 0.02)
	_draw_classic_body(spin_ang)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_classic_body(spin_ang: float) -> void:
	var wood_a := Color(0.68, 0.34, 0.12)
	var wood_b := Color(0.92, 0.58, 0.2)
	var wood_c := Color(0.48, 0.24, 0.08)
	var pts := PackedVector2Array([
		Vector2(-RADIUS * 0.82, -RADIUS * 0.22),
		Vector2(RADIUS * 0.82, -RADIUS * 0.22),
		Vector2(RADIUS * 0.26, RADIUS * 0.48),
		Vector2(0, RADIUS * 0.78),
		Vector2(-RADIUS * 0.26, RADIUS * 0.48),
	])
	draw_colored_polygon(pts, wood_a)
	for band_i in 5:
		var by: float = lerpf(-RADIUS * 0.15, RADIUS * 0.55, float(band_i) / 5.0)
		var col: Color = wood_b if band_i % 2 == 0 else wood_c
		var hw: float = lerpf(RADIUS * 0.78, RADIUS * 0.22, float(band_i) / 5.0)
		draw_line(Vector2(-hw, by), Vector2(hw, by), col, 5.0)
	var stripe_n := 12
	for i in stripe_n:
		var a: float = spin_ang + TAU * float(i) / float(stripe_n)
		draw_line(
			Vector2.ZERO,
			Vector2(cos(a), sin(a)) * RADIUS * 0.55,
			Color(1, 0.92, 0.55, 0.35),
			3.5
		)
	draw_rect(Rect2(-RADIUS * 0.1, -RADIUS * 0.78, RADIUS * 0.2, RADIUS * 0.45), Color(0.78, 0.5, 0.22))
	draw_circle(Vector2(0, -RADIUS * 0.78), RADIUS * 0.14, Color(0.92, 0.9, 0.88))
	draw_circle(Vector2(0, -RADIUS * 0.55), RADIUS * 0.22, Color(0.92, 0.88, 0.82))
	draw_circle(Vector2(0, RADIUS * 0.72), RADIUS * 0.11, Color(0.5, 0.52, 0.58))
	draw_circle(Vector2(0, RADIUS * 0.76), RADIUS * 0.045, Color(0.95, 0.96, 1.0))
	var hi := PackedVector2Array([
		Vector2(-RADIUS * 0.4, -RADIUS * 0.12),
		Vector2(-RADIUS * 0.05, -RADIUS * 0.28),
		Vector2(-RADIUS * 0.25, RADIUS * 0.2),
	])
	draw_colored_polygon(hi, Color(1, 1, 1, 0.22))