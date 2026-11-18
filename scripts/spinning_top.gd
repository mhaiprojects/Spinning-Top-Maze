class_name SpinningTop
extends RigidBody2D
## Top-down spinning top: tilt force, spin power, wall bounce loss.

signal fell_over
signal power_changed(value: float)

const DECAY_PER_SEC := 2.5
const MIN_HIT_LOSS := 4.0
const HIT_LOSS_SCALE := 1.2
const STEER_FORCE := 280.0
const RADIUS := 14.0

var spin_power: float = 100.0
var _falling := false
var _fall_t := 0.0
var _wobble_phase := 0.0
var _last_hit_ms := 0


func _ready() -> void:
	gravity_scale = 0.0
	linear_damp = 2.8
	angular_damp = 1.5
	contact_monitor = true
	max_contacts_reported = 8
	body_entered.connect(_on_body_entered)
	lock_rotation = false
	collision_layer = 1
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	add_child(shape)


func set_initial_power(p: float) -> void:
	spin_power = clampf(p, 0.0, 100.0)
	power_changed.emit(spin_power)


func _physics_process(delta: float) -> void:
	if _falling:
		_fall_t += delta
		return
	spin_power = maxf(0.0, spin_power - DECAY_PER_SEC * delta)
	power_changed.emit(spin_power)
	if spin_power <= 0.0:
		_begin_fall()
		return
	var tilt: Vector2 = _tilt_vector()
	if tilt.length_squared() > 0.0001:
		apply_central_force(tilt * STEER_FORCE * (0.35 + 0.65 * spin_power / 100.0))
	_wobble_phase += delta * (8.0 + spin_power * 0.12)
	var spin_rate: float = (spin_power / 100.0) * 18.0
	angular_velocity = lerp(angular_velocity, spin_rate, 0.15)
	queue_redraw()


func _begin_fall() -> void:
	if _falling:
		return
	_falling = true
	_fall_t = 0.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	fell_over.emit()


func is_fallen() -> bool:
	return _falling


func fall_progress() -> float:
	return clampf(_fall_t / 0.45, 0.0, 1.0)


func apply_wall_hit(impact_speed: float) -> void:
	var loss: float = maxf(MIN_HIT_LOSS, impact_speed * HIT_LOSS_SCALE)
	spin_power = maxf(0.0, spin_power - loss)
	power_changed.emit(spin_power)
	if spin_power <= 0.0:
		_begin_fall()


func _on_body_entered(body: Node) -> void:
	if _falling:
		return
	if body is StaticBody2D and body.is_in_group("maze_wall"):
		var now: int = Time.get_ticks_msec()
		if now - _last_hit_ms < 80:
			return
		_last_hit_ms = now
		var impact: float = linear_velocity.length()
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
	power_changed.emit(spin_power)
	queue_redraw()


func _draw() -> void:
	var wobble: float = 0.0
	if not _falling:
		wobble = (1.0 - spin_power / 100.0) * 5.0 * sin(_wobble_phase)
	var tip := Vector2(0, -RADIUS * 0.35).rotated(rotation + wobble * 0.05)
	var body_col := Color(0.92, 0.78, 0.32)
	var rim_col := Color(0.35, 0.26, 0.18)
	if _falling:
		var t: float = fall_progress()
		draw_set_transform(Vector2.ZERO, rotation + t * PI * 0.5, Vector2.ONE.lerp(Vector2(1.3, 0.35), t))
		body_col = body_col.lerp(Color(0.45, 0.42, 0.4), t)
	draw_circle(Vector2.ZERO, RADIUS, body_col)
	draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 24, rim_col, 2.0)
	draw_circle(tip, 3.5, rim_col)
	var spoke_n := int(3 + spin_power / 25.0)
	for i in spoke_n:
		var a: float = rotation + TAU * float(i) / float(spoke_n) + _wobble_phase * 0.2
		draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * (RADIUS * 0.65), rim_col, 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)