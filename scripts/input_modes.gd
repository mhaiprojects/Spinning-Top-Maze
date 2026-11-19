class_name InputModes
extends RefCounted
## Pure input-mode helpers (unit-testable).

enum Mode { MOUSE, KEYBOARD, DRAG, TILT }

const ORDER: Array[int] = [Mode.MOUSE, Mode.KEYBOARD, Mode.DRAG, Mode.TILT]

const MOUSE_DEADZONE := 18.0
const MOUSE_MAX_DIST := 220.0
const TILT_DEADZONE := 0.08
const TILT_INVERT_X := true
const DRAG_RADIUS := 120.0
const SMOOTH := 0.18


static func smooth_alpha(delta: float, response_rate: float, base_smooth: float = SMOOTH) -> float:
	var b: float = clampf(base_smooth, 0.001, 0.99)
	var r: float = maxf(response_rate, 0.01)
	return 1.0 - pow(1.0 - b, clampf(delta, 0.0, 0.1) * 60.0 * r)


static func map_device_tilt(angles_deg: Vector2, full_scale_deg: float, sensitivity: float) -> Vector2:
	var scale: float = maxf(full_scale_deg, 1.0)
	var v: Vector2 = angles_deg / scale * sensitivity
	v = map_tilt_axes(v)
	var L: float = v.length()
	if L > 1.0:
		v /= L
	return v


static func map_accel_tilt(accel: Vector2, sensitivity: float) -> Vector2:
	var v: Vector2 = accel / 9.8 * sensitivity
	v = map_tilt_axes(v)
	var L: float = v.length()
	if L > 1.0:
		v /= L
	return v


static func map_tilt_axes(v: Vector2) -> Vector2:
	if TILT_INVERT_X:
		return Vector2(-v.x, v.y)
	return v


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


static func steer_tilt(raw: Vector2, cal_offset: Vector2, oriented: Vector2) -> Vector2:
	var o: Vector2 = map_tilt_axes(oriented)
	var cal: Vector2 = map_tilt_axes(cal_offset)
	var base: Vector2 = o - cal
	if base.length() > 1.0:
		base = base.normalized()
	return apply_radial_deadzone(base, TILT_DEADZONE)


static func apply_radial_deadzone(v: Vector2, deadzone: float) -> Vector2:
	if v.length() < deadzone:
		return Vector2.ZERO
	var t: float = (v.length() - deadzone) / (1.0 - deadzone)
	return v.normalized() * clampf(t, 0.0, 1.0)


static func rotate_for_screen(v: Vector2, angle_deg: float) -> Vector2:
	var rad: float = deg_to_rad(angle_deg)
	var c: float = cos(rad)
	var s: float = sin(rad)
	return Vector2(v.x * c - v.y * s, v.x * s + v.y * c)


static func save_mode(path: String, mode: int) -> bool:
	return UserSettings.save_input_mode(path, mode)


static func load_mode(path: String) -> int:
	return mode_from_saved(UserSettings.load_input_mode(path))