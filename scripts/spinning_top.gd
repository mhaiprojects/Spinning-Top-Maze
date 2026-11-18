class_name SpinningTop
extends RigidBody2D
## Top-down spinning top: tilt force, spin power, wall bounce loss.

signal fell_over
signal power_changed(value: float)
signal hit_wall

const MIN_HIT_LOSS := 4.0
const HIT_LOSS_SCALE := 1.2
const STEER_FORCE := 280.0
const RADIUS := 22.0
const TRAIL_LEN := 14

var spin_power: float = 100.0
var _falling := false
var _fall_t := 0.0
var _wobble_phase := 0.0
var _last_hit_ms := 0
var _run_active := false
var _decay_rate := 2.2
var _hit_mult := 1.0
var _trail: Array[Vector2] = []
var _trail_line: Line2D
var _spark: CPUParticles2D


func _ready() -> void:
	gravity_scale = 0.0
	linear_damp = 2.8
	angular_damp = 1.5
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
	_trail_line.width = 4.0
	_trail_line.default_color = Color(1, 0.75, 0.2, 0.35)
	_trail_line.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(_trail_line)
	_spark = CPUParticles2D.new()
	_spark.emitting = false
	_spark.one_shot = true
	_spark.amount = 12
	_spark.lifetime = 0.35
	_spark.explosiveness = 0.9
	_spark.direction = Vector2.ZERO
	_spark.spread = 180.0
	_spark.initial_velocity_min = 40.0
	_spark.initial_velocity_max = 120.0
	_spark.scale_amount_min = 2.0
	_spark.scale_amount_max = 4.0
	add_child(_spark)
	set_run_active(false)


func configure_for_wave(wave: int) -> void:
	var p: Dictionary = Difficulty.params_for_wave(wave)
	_decay_rate = float(p.spin_decay)
	_hit_mult = float(p.wall_hit_mult)


func set_run_active(active: bool) -> void:
	_run_active = active
	if active:
		collision_layer = 1
		collision_mask = 6
		set_deferred("contact_monitor", true)
		freeze = false
	else:
		set_deferred("contact_monitor", false)
		collision_layer = 0
		collision_mask = 0
		freeze = true
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
		_trail.clear()
		_trail_line.clear_points()


func set_initial_power(p: float) -> void:
	spin_power = clampf(p, 0.0, 100.0)
	power_changed.emit(spin_power)


func _physics_process(delta: float) -> void:
	if not _run_active:
		return
	if _falling:
		_fall_t += delta
		queue_redraw()
		return
	spin_power = maxf(0.0, spin_power - _decay_rate * delta)
	power_changed.emit(spin_power)
	if spin_power <= 0.0:
		call_deferred("_begin_fall")
		return
	var tin: Node = get_tree().root.get_node_or_null("TiltInput")
	if tin and tin.has_method("set_top_world_position"):
		tin.call("set_top_world_position", global_position)
	var tilt: Vector2 = _tilt_vector()
	if tilt.length_squared() > 0.0001:
		apply_central_force(tilt * STEER_FORCE * (0.35 + 0.65 * spin_power / 100.0))
	_wobble_phase += delta * (8.0 + spin_power * 0.12)
	var spin_rate: float = (spin_power / 100.0) * 24.0
	angular_velocity = lerp(angular_velocity, spin_rate, 0.15)
	_push_trail()
	queue_redraw()


func _push_trail() -> void:
	_trail.push_back(global_position)
	while _trail.size() > TRAIL_LEN:
		_trail.pop_front()
	_trail_line.clear_points()
	var i := 0
	for p in _trail:
		var alpha: float = float(i) / float(maxi(_trail.size() - 1, 1))
		_trail_line.add_point(to_local(p))
		i += 1
	var c: Color = _trail_line.default_color
	c.a = 0.15 + 0.35 * (spin_power / 100.0)
	_trail_line.default_color = c


func _begin_fall() -> void:
	if _falling or not _run_active:
		return
	_falling = true
	_fall_t = 0.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	set_run_active(false)
	call_deferred("_emit_fell_over")


func _emit_fell_over() -> void:
	fell_over.emit()


func is_fallen() -> bool:
	return _falling


func fall_progress() -> float:
	return clampf(_fall_t / 0.45, 0.0, 1.0)


func apply_wall_hit(impact_speed: float) -> void:
	if not _run_active or _falling:
		return
	var loss: float = maxf(MIN_HIT_LOSS, impact_speed * HIT_LOSS_SCALE * _hit_mult)
	spin_power = maxf(0.0, spin_power - loss)
	power_changed.emit(spin_power)
	_spark.position = Vector2.ZERO
	_spark.emitting = true
	hit_wall.emit()
	if spin_power <= 0.0:
		call_deferred("_begin_fall")


func _on_body_entered(body: Node) -> void:
	if not _run_active or _falling:
		return
	if body.is_in_group("hazard_zone"):
		call_deferred("_apply_wall_hit_deferred", 25.0)
		return
	if body is StaticBody2D and body.is_in_group("maze_wall"):
		var now: int = Time.get_ticks_msec()
		if now - _last_hit_ms < 120:
			return
		_last_hit_ms = now
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
	_fall_t = 0.0
	global_position = pos
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	spin_power = clampf(power, 0.0, 100.0)
	_trail.clear()
	_trail_line.clear_points()
	power_changed.emit(spin_power)
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2(6, 8), RADIUS * 0.95, Color(0, 0, 0, 0.22))
	var wobble: float = 0.0
	if not _falling:
		wobble = (1.0 - spin_power / 100.0) * 6.0 * sin(_wobble_phase)
	var tilt_draw: float = wobble * 0.03
	draw_set_transform(Vector2.ZERO, tilt_draw, Vector2.ONE)
	var body_col := Color(1.0, 0.88, 0.28)
	var rim_col := Color(0.62, 0.25, 0.1)
	var stripe_col := Color(1.0, 0.45, 0.12)
	if _falling:
		var t: float = fall_progress()
		draw_set_transform(Vector2.ZERO, rotation + t * PI * 0.5, Vector2.ONE.lerp(Vector2(1.3, 0.35), t))
		body_col = body_col.lerp(Color(0.45, 0.42, 0.4), t)
	for ring_i in 4:
		var rr: float = RADIUS * (1.0 - float(ring_i) * 0.18)
		var col: Color = body_col.lerp(Color(1, 1, 1), float(ring_i) * 0.08)
		draw_circle(Vector2.ZERO, rr, col)
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 40, Color(1, 0.95, 0.75, 0.35), 2.0)
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 40, rim_col, 3.5)
	draw_circle(Vector2.ZERO, RADIUS * 0.28, Color(0.12, 0.08, 0.06))
	var spoke_n := int(5 + spin_power / 18.0)
	for i in spoke_n:
		var a: float = rotation + TAU * float(i) / float(spoke_n) + _wobble_phase * 0.4
		draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * (RADIUS * 0.9), stripe_col, 3.5)
	var tip := Vector2(0, -RADIUS * 0.48).rotated(rotation + wobble * 0.06)
	draw_circle(tip, 6.0, rim_col)
	draw_circle(tip, 3.0, Color(1, 0.9, 0.7))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)