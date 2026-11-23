class_name SpinningTop
extends RigidBody2D
## Top-down spinning top: tilt force, spin power, wall bounce loss.
## The art is a side-profile top (handle up, pointy tip down at tip_local()).
## Seen from above, the body's 2D angular_velocity is the spin about the top's
## own vertical axis (kept for wall contacts). The node therefore rotates, so
## _draw counter-rotates the profile art to keep it upright on its tip (it used
## to turn end over end like a pinwheel) and shows that same spin as stripes
## sliding round the cone. Lean/precession/fall tilts pivot around the tip.

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
const BASE_RADIUS := 46.0
const TRAIL_JUMP := 100.0
const TRAIL_LEN := 18
const FALL_ANIM := 1.0

var spin_power: float = 100.0
var _falling := false
var _fall_t := 0.0
var _fall_kind: FallKind = FallKind.NONE
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
var _lean := Vector2.ZERO
var _precess_phase := 0.0
var _settings_rev := -1
var _circle_shape: CircleShape2D


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
	_circle_shape = CircleShape2D.new()
	_circle_shape.radius = radius()
	shape.shape = _circle_shape
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
	_sync_physics_tunables()
	_apply_top_size()
	set_run_active(false)


func stored_size_scale() -> float:
	return PhysicsSettings.get_value("top_size_scale")


func radius() -> float:
	var s: float = stored_size_scale()
	if not is_finite(s) or s <= 0.0:
		return BASE_RADIUS * 0.000001
	return BASE_RADIUS * s


func _apply_top_size() -> void:
	var r: float = radius()
	if _circle_shape:
		_circle_shape.radius = r
	if _trail_line:
		var ref_r: float = BASE_RADIUS * 0.5
		_trail_line.width = 7.0 * maxf(r / ref_r, 0.05)
	queue_redraw()


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
	_lean = Vector2.ZERO
	_precess_phase = 0.0
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


## Victory spin-down in place on the goal tile (no pull toward the tile centre).
func start_goal_victory() -> void:
	_clear_trail()
	_fall_kind = FallKind.GOAL
	_falling = false
	_fall_t = 0.0
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


func refresh_size_from_settings() -> void:
	_settings_rev = -1
	_sync_physics_tunables()


func _physics_process(delta: float) -> void:
	_sync_physics_tunables()
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
	var decay_mult: float = PhysicsSettings.get_value("spin_decay_mult")
	spin_power = maxf(0.0, spin_power - _decay_rate * decay_mult * delta)
	power_changed.emit(spin_power)
	var fall_thr: float = PhysicsSettings.get_value("fall_threshold")
	if fall_thr > 0.01 and spin_power <= fall_thr:
		_begin_power_fall()
		return
	if spin_power <= 0.0:
		_begin_power_fall()
		return
	var tin: Node = get_tree().root.get_node_or_null("TiltInput")
	if tin and tin.has_method("set_top_world_position"):
		tin.call("set_top_world_position", global_position)
	var tilt: Vector2 = _tilt_vector()
	var shaped: Vector2 = TopPhysics.shape_input(tilt)
	var lean_max_rad: float = deg_to_rad(PhysicsSettings.get_value("lean_max_deg"))
	if not is_finite(lean_max_rad):
		lean_max_rad = 0.0
	var hi_scale: float = PhysicsSettings.get_value("high_scale")
	var target_lean: Vector2
	if is_finite(hi_scale) and absf(hi_scale) > 1e-9:
		target_lean = shaped * (lean_max_rad / hi_scale)
	else:
		target_lean = Vector2.ZERO
	if not target_lean.is_finite():
		target_lean = Vector2.ZERO
	var stiffness: float = PhysicsSettings.get_value("lean_stiffness")
	_lean = TopPhysics.spring_lean(_lean, target_lean, stiffness, delta)
	var spin_norm: float = maxf(spin_power / 100.0, 0.15)
	var spin_sign: float = signf(angular_velocity)
	if absf(spin_sign) < 0.01:
		spin_sign = 1.0
	var prec_rate: float = PhysicsSettings.get_value("precession_rate")
	_lean = TopPhysics.apply_precession(_lean, spin_norm, prec_rate, delta, spin_sign)
	if prec_rate > 0.0001 and is_finite(prec_rate):
		var phase_delta: float = prec_rate * _lean.length() / spin_norm * delta * spin_sign
		if is_finite(phase_delta):
			_precess_phase = wrapf(_precess_phase + phase_delta, 0.0, TAU)
	var lean_len: float = _lean.length()
	if lean_len > 0.0001:
		if sleeping:
			sleeping = false
		var lean_cap: float = maxf(lean_max_rad, 0.001)
		var steer_f: float = PhysicsSettings.get_value("steer_force")
		var hi_eff: float = hi_scale if is_finite(hi_scale) else 0.0
		# Lean is capped at lean_max for the art; the high tier's extra punch
		# comes back via hi_scale so a hard tilt drives up to high_scale x steer_force.
		var force_mag: float = (
			(lean_len / lean_cap) * hi_eff * steer_f * (0.35 + 0.65 * spin_power / 100.0)
		)
		if is_finite(force_mag) and force_mag != 0.0:
			var dir: Vector2 = _lean.normalized()
			if dir.is_finite():
				apply_central_force(dir * force_mag)
	var max_sp: float = PhysicsSettings.get_value("max_speed")
	if is_finite(max_sp) and max_sp > 0.0 and linear_velocity.is_finite():
		var spd: float = linear_velocity.length()
		if is_finite(spd) and spd > max_sp:
			linear_velocity = linear_velocity.normalized() * max_sp
	if not linear_velocity.is_finite():
		linear_velocity = Vector2.ZERO
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


func _sync_physics_tunables() -> void:
	var rev: int = PhysicsSettings.revision()
	if rev == _settings_rev:
		return
	_settings_rev = rev
	var ld: float = PhysicsSettings.get_value("linear_damp")
	linear_damp = ld if is_finite(ld) else 2.2
	_apply_top_size()


func lean_vector() -> Vector2:
	return _lean


## Spin about the top's own vertical (tip-to-handle) axis, rad/s.
func spin_rate() -> float:
	return angular_velocity


## Spin phase shown by the cone stripes: the body's physics rotation.
func spin_angle() -> float:
	return rotation


## Screen-plane tilt of the drawn top around its tip (radians, 0 = upright).
func visual_tilt() -> float:
	return float(_visual_pose().rot)


func tip_local() -> Vector2:
	return Vector2(0, radius() * 0.8)


## Local draw transform of the top's art (counter-rotated, tilted about the tip).
func visual_transform() -> Transform2D:
	var pose: Dictionary = _visual_pose()
	var body_rot: float = pose.rot
	var body_scale: Vector2 = pose.scale
	var tip_l: Vector2 = tip_local()
	var tip: Vector2 = (pose.off as Vector2) + tip_l
	var pivot_origin: Vector2 = tip - (tip_l * body_scale).rotated(body_rot)
	return Transform2D(-rotation, Vector2.ZERO) * Transform2D(body_rot, body_scale, 0.0, pivot_origin)


## World-space direction from tip to handle of the drawn top (UP = upright).
func visual_up_world() -> Vector2:
	return global_transform.basis_xform(visual_transform().basis_xform(Vector2.UP)).normalized()


func _advance_goal_fall(delta: float) -> void:
	_fall_t += delta
	var u: float = clampf(_fall_t / FALL_ANIM, 0.0, 1.0)
	var settle: float = clampf(u / 0.55, 0.0, 1.0)
	var ease: float = settle * settle * (3.0 - 2.0 * settle)
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
	var loss_mult: float = PhysicsSettings.get_value("wall_hit_loss_mult")
	var loss: float = clampf(
		impact_speed * HIT_LOSS_SCALE * _hit_mult * loss_mult,
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
	var slow: float = PhysicsSettings.get_value("wall_hit_slowdown")
	if is_finite(slow):
		linear_velocity *= slow
	if not linear_velocity.is_finite():
		linear_velocity = Vector2.ZERO
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
	_lean = Vector2.ZERO
	_precess_phase = 0.0
	_sync_physics_body()
	power_changed.emit(spin_power)
	queue_redraw()


func _visual_pose() -> Dictionary:
	var lean_max_rad: float = deg_to_rad(PhysicsSettings.get_value("lean_max_deg"))
	var lean_ratio: float = 0.0
	if lean_max_rad > 0.001:
		lean_ratio = clampf(_lean.length() / lean_max_rad, 0.0, 1.0)
	var lean_dir: Vector2 = _lean.normalized() if _lean.length_squared() > 0.0001 else Vector2.ZERO
	var lean_offset: Vector2 = lean_dir * lean_ratio * radius() * 0.35
	var wobble: float = (1.0 - spin_power / 100.0) * 14.0 * sin(_wobble_phase)
	# Bounded tilts around the tip: sideways lean, precession sway, low-spin wobble.
	var body_rot: float = wobble * 0.025 + sin(_precess_phase) * lean_ratio * 0.12
	var body_off := lean_offset
	var body_scale := Vector2.ONE
	if lean_dir.length_squared() > 0.0001:
		body_rot += lean_dir.x * lean_ratio * 0.3
		var along: float = absf(lean_dir.dot(Vector2.RIGHT))
		body_scale = Vector2(
			1.0 - lean_ratio * 0.14 * along,
			1.0 - lean_ratio * 0.1 * (1.0 - along)
		)
	if _falling or _fall_kind == FallKind.GOAL:
		var t: float = fall_progress()
		body_rot += t * 0.9
		body_off = Vector2.ZERO
		body_scale = Vector2(1.0 + t * 0.25, 0.55 + t * 0.35)
	return {"rot": body_rot, "off": body_off, "scale": body_scale}


func _draw() -> void:
	var pose: Dictionary = _visual_pose()
	var body_rot: float = pose.rot
	var body_off: Vector2 = pose.off
	var body_scale: Vector2 = pose.scale
	var tip: Vector2 = body_off + tip_local()
	var r: float = radius()
	# Undo the body's physics spin so the profile stays upright on screen.
	var counter := Transform2D(-rotation, Vector2.ZERO)
	# Contact shadow under the tip, stretched toward the handle's lean.
	var spread: float = 0.35 + 0.4 * absf(sin(body_rot))
	draw_set_transform_matrix(
		counter * Transform2D(0.0, Vector2(1.0 + spread, 0.32), 0.0, tip + Vector2(6.0 * signf(body_rot), 4))
	)
	draw_circle(Vector2.ZERO, r * 0.5, Color(0, 0, 0, 0.28))
	# Rotate/scale about the tip so it stays planted on the floor.
	draw_set_transform_matrix(visual_transform())
	_draw_classic_body(rotation)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_classic_body(spin_ang: float) -> void:
	var r: float = radius()
	var wood_a := Color(0.68, 0.34, 0.12)
	var wood_b := Color(0.92, 0.58, 0.2)
	var wood_c := Color(0.48, 0.24, 0.08)
	var pts := PackedVector2Array([
		Vector2(-r * 0.82, -r * 0.22),
		Vector2(r * 0.82, -r * 0.22),
		Vector2(r * 0.26, r * 0.48),
		Vector2(0, r * 0.78),
		Vector2(-r * 0.26, r * 0.48),
	])
	draw_colored_polygon(pts, wood_a)
	for band_i in 5:
		var by: float = lerpf(-r * 0.15, r * 0.55, float(band_i) / 5.0)
		var col: Color = wood_b if band_i % 2 == 0 else wood_c
		var hw: float = lerpf(r * 0.78, r * 0.22, float(band_i) / 5.0)
		draw_line(Vector2(-hw, by), Vector2(hw, by), col, 5.0)
	# Spin about the vertical tip-to-handle axis: stripes on the cone slide
	# sideways and wrap round the back (only the front half is drawn).
	var stripe_n := 8
	for i in stripe_n:
		var a: float = spin_ang + TAU * float(i) / float(stripe_n)
		var facing: float = cos(a)
		if facing <= 0.0:
			continue
		var sx: float = sin(a)
		draw_line(
			Vector2(sx * r * 0.76, -r * 0.2),
			Vector2(sx * r * 0.24, r * 0.47),
			Color(1, 0.92, 0.55, 0.15 + 0.35 * facing),
			3.5
		)
	draw_rect(Rect2(-r * 0.1, -r * 0.78, r * 0.2, r * 0.45), Color(0.78, 0.5, 0.22))
	draw_circle(Vector2(0, -r * 0.78), r * 0.14, Color(0.92, 0.9, 0.88))
	draw_circle(Vector2(0, -r * 0.55), r * 0.22, Color(0.92, 0.88, 0.82))
	draw_circle(Vector2(0, r * 0.72), r * 0.11, Color(0.5, 0.52, 0.58))
	draw_circle(Vector2(0, r * 0.76), r * 0.045, Color(0.95, 0.96, 1.0))
	var hi := PackedVector2Array([
		Vector2(-r * 0.4, -r * 0.12),
		Vector2(-r * 0.05, -r * 0.28),
		Vector2(-r * 0.25, r * 0.2),
	])
	draw_colored_polygon(hi, Color(1, 1, 1, 0.22))