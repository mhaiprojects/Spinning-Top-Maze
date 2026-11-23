class_name InputModes
extends RefCounted
## Pure input-mode helpers (unit-testable).

enum Mode { MOUSE, KEYBOARD, DRAG, TILT }

const ORDER: Array[int] = [Mode.MOUSE, Mode.KEYBOARD, Mode.DRAG, Mode.TILT]

const MOUSE_DEADZONE := 18.0
const MOUSE_MAX_DIST := 220.0
const TILT_DEADZONE := 0.08
const DRAG_RADIUS := 120.0
## Tilt signs (single place). Device d=(gamma,beta): +x = right edge down, +y = top raised toward user.
## Accel after web JS iOS normalisation (Android convention): device = (-ax, ay)/9.8, then screen rotation.
## screen.x = dx*cos(a)+dy*sin(a); screen.y = -dx*sin(a)+dy*cos(a) for screen.orientation.angle a.
const SMOOTH := 0.18


static func smooth_alpha(delta: float, response_rate: float, base_smooth: float = SMOOTH) -> float:
	var b: float = clampf(base_smooth, 0.001, 0.99)
	var r: float = maxf(response_rate, 0.01)
	return 1.0 - pow(1.0 - b, clampf(delta, 0.0, 0.1) * 60.0 * r)


static func map_device_tilt(angles_deg: Vector2, full_scale_deg: float, sensitivity: float) -> Vector2:
	var scale: float = maxf(full_scale_deg, 1.0)
	var v: Vector2 = angles_deg / scale * sensitivity
	var L: float = v.length()
	if L > 1.0:
		v /= L
	return v


static func map_accel_tilt(accel: Vector2, sensitivity: float) -> Vector2:
	var device: Vector2 = device_steer_from_accel(accel)
	var L: float = device.length()
	if L < 0.0001:
		return Vector2.ZERO
	var v: Vector2 = device * sensitivity
	if v.length() > 1.0:
		v = v.normalized()
	return v


static func device_steer_from_accel(accel: Vector2) -> Vector2:
	return Vector2(-accel.x, accel.y) / 9.8


static func device_angles_to_screen_steer(gamma: float, beta: float, screen_angle_deg: float) -> Vector2:
	return device_vector_to_screen_steer(Vector2(gamma, beta), screen_angle_deg)


static func device_accel_to_screen_steer(accel: Vector2, screen_angle_deg: float) -> Vector2:
	var dev: Vector2 = device_steer_from_accel(accel)
	return device_vector_to_screen_steer(dev, screen_angle_deg)


static func device_vector_to_screen_steer(v: Vector2, screen_angle_deg: float) -> Vector2:
	var dx: float = v.x
	var dy: float = v.y
	var a: float = fmod(screen_angle_deg, 360.0)
	if a < 0.0:
		a += 360.0
	var rad: float = deg_to_rad(a)
	var c: float = cos(rad)
	var s: float = sin(rad)
	return Vector2(dx * c + dy * s, -dx * s + dy * c)


static func device_vector_from_screen_tip(screen_x: float, screen_y: float, screen_angle_deg: float) -> Vector2:
	## Inverse of device_vector_to_screen_steer (for tests: screen edge-down => device gamma/beta).
	var a: float = fmod(screen_angle_deg, 360.0)
	if a < 0.0:
		a += 360.0
	var rad: float = deg_to_rad(a)
	var c: float = cos(rad)
	var s: float = sin(rad)
	return Vector2(c * screen_x - s * screen_y, s * screen_x + c * screen_y)


static func native_screen_rotation_deg() -> float:
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		return 0.0
	var o: int = DisplayServer.screen_get_orientation()
	match o:
		DisplayServer.SCREEN_LANDSCAPE:
			return 90.0
		DisplayServer.SCREEN_REVERSE_PORTRAIT:
			return 180.0
		DisplayServer.SCREEN_REVERSE_LANDSCAPE:
			return 270.0
		DisplayServer.SCREEN_PORTRAIT, DisplayServer.SCREEN_SENSOR_LANDSCAPE, DisplayServer.SCREEN_SENSOR_PORTRAIT, DisplayServer.SCREEN_SENSOR:
			return 0.0
		_:
			return 0.0


static func tilt_steer_pipeline(
	gamma: float,
	beta: float,
	screen_angle_deg: float,
	cal_offset: Vector2,
	full_scale_deg: float,
	sensitivity: float
) -> Vector2:
	var screen_deg: Vector2 = device_angles_to_screen_steer(gamma, beta, screen_angle_deg)
	var oriented: Vector2 = map_device_tilt(screen_deg, full_scale_deg, sensitivity)
	return steer_tilt(oriented, cal_offset)


static func tilt_steer_from_accel_pipeline(
	accel: Vector2,
	screen_angle_deg: float,
	cal_offset: Vector2,
	sensitivity: float
) -> Vector2:
	var screen: Vector2 = device_accel_to_screen_steer(accel, screen_angle_deg)
	var oriented: Vector2 = screen * sensitivity
	if oriented.length() > 1.0:
		oriented = oriented.normalized()
	return steer_tilt(oriented, cal_offset)


static func mode_name(mode: int) -> String:
	match mode:
		Mode.MOUSE:
			return "Mouse"
		Mode.KEYBOARD:
			return "Keyboard"
		Mode.DRAG:
			return "Drag"
		Mode.TILT:
			return "Tilt"
	return "Mouse"


static func next_mode(mode: int) -> int:
	var idx: int = ORDER.find(mode)
	if idx < 0:
		return Mode.MOUSE
	return ORDER[(idx + 1) % ORDER.size()]


static func mode_from_saved(value: Variant) -> int:
	var m: int = int(value)
	if ORDER.has(m):
		return m
	return -1


static func is_touch_device() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	return DisplayServer.is_touchscreen_available()


static func native_accel_available() -> bool:
	if OS.has_feature("web"):
		return true
	return Input.get_accelerometer() != Vector3.ZERO or OS.has_feature("mobile")


static func default_mode(touch: bool, sensor_likely: bool) -> int:
	if touch and sensor_likely:
		return Mode.TILT
	if touch:
		return Mode.DRAG
	return Mode.MOUSE


static func tilt_fallback_mode(touch: bool) -> int:
	return Mode.DRAG if touch else Mode.MOUSE


static func steer_mouse(cursor_world: Vector2, top_world: Vector2) -> Vector2:
	var delta: Vector2 = cursor_world - top_world
	var dist: float = delta.length()
	if dist <= MOUSE_DEADZONE:
		return Vector2.ZERO
	var dir: Vector2 = delta / dist
	var t: float = clampf((dist - MOUSE_DEADZONE) / (MOUSE_MAX_DIST - MOUSE_DEADZONE), 0.0, 1.0)
	return dir * t


static func steer_keyboard(left: bool, right: bool, up: bool, down: bool) -> Vector2:
	var k := Vector2.ZERO
	if left:
		k.x -= 1.0
	if right:
		k.x += 1.0
	if up:
		k.y -= 1.0
	if down:
		k.y += 1.0
	if k.length_squared() < 0.0001:
		return Vector2.ZERO
	return k.normalized()


static func steer_drag(pointer: Vector2, origin: Vector2, active: bool) -> Vector2:
	if not active:
		return Vector2.ZERO
	var delta: Vector2 = pointer - origin
	var v: Vector2 = delta / DRAG_RADIUS
	if v.length() > 1.0:
		v = v.normalized()
	return v


static func steer_tilt(oriented: Vector2, cal_offset: Vector2) -> Vector2:
	var base: Vector2 = oriented - cal_offset
	if base.length() > 1.0:
		base = base.normalized()
	return apply_radial_deadzone(base, TILT_DEADZONE)


static func apply_radial_deadzone(v: Vector2, deadzone: float) -> Vector2:
	if v.length() < deadzone:
		return Vector2.ZERO
	var t: float = (v.length() - deadzone) / (1.0 - deadzone)
	return v.normalized() * clampf(t, 0.0, 1.0)


static func rotate_for_screen(v: Vector2, angle_deg: float) -> Vector2:
	return device_vector_to_screen_steer(v, angle_deg)


static func save_mode(path: String, mode: int) -> bool:
	return UserSettings.save_input_mode(path, mode)


static func load_mode(path: String) -> int:
	return mode_from_saved(UserSettings.load_input_mode(path))