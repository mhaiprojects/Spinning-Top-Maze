extends Node
## Device tilt, keyboard, and drag steering with calibration.

enum Status { UNAVAILABLE, DENIED, KEYBOARD, SENSOR, DRAG }

const DEADZONE := 0.08
const SMOOTH := 0.18
const DRAG_SCALE := 0.004
const DRAG_MAX := 1.0

var status: Status = Status.KEYBOARD
var _raw := Vector2.ZERO
var _smooth := Vector2.ZERO
var _cal_offset := Vector2.ZERO
var _drag_active := false
var _drag_origin := Vector2.ZERO
var _drag_vec := Vector2.ZERO
var _keyboard := Vector2.ZERO
var _web_installed := false
var _web_poll_ready := false


func _ready() -> void:
	_load_calibration()
	if OS.has_feature("web"):
		_install_web_tilt()
	else:
		_poll_native_accel()


func _process(_delta: float) -> void:
	_poll_keyboard()
	if OS.has_feature("web") and _web_poll_ready:
		_poll_web_tilt()
	elif not OS.has_feature("web"):
		_poll_native_accel()
	_update_status()


func _poll_keyboard() -> void:
	var k := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		k.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		k.x += 1.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		k.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		k.y += 1.0
	if k.length_squared() > 0.0:
		_keyboard = k.normalized()
	else:
		_keyboard = Vector2.ZERO


func _poll_native_accel() -> void:
	var a: Vector3 = Input.get_accelerometer()
	if a == Vector3.ZERO:
		return
	var v := Vector2(a.x, a.y)
	if v.length() > 0.001:
		_raw = _apply_screen_rotation(v.normalized())
		status = Status.SENSOR


func _install_web_tilt() -> void:
	if _web_installed:
		return
	var js := """
	(function(){
	  if (window.stmTilt) return;
	  window.stmTilt = { beta: 0, gamma: 0, ax: 0, ay: 0, ok: false, denied: false };
	  function upd(b,g){ window.stmTilt.beta = b||0; window.stmTilt.gamma = g||0; window.stmTilt.ok = true; }
	  window.addEventListener('deviceorientation', function(e){
	    upd(e.beta, e.gamma);
	  }, true);
	  window.addEventListener('devicemotion', function(e){
	    var a = e.accelerationIncludingGravity;
	    if (a) { window.stmTilt.ax = a.x||0; window.stmTilt.ay = a.y||0; }
	  }, true);
	  window.stmRequestTilt = function(){
	    try {
	      if (typeof DeviceOrientationEvent !== 'undefined' && DeviceOrientationEvent.requestPermission) {
	        return DeviceOrientationEvent.requestPermission().then(function(r){
	          if (r === 'granted') {
	            if (DeviceMotionEvent.requestPermission) {
	              return DeviceMotionEvent.requestPermission().then(function(m){
	                window.stmTilt.ok = (m === 'granted');
	                return m;
	              });
	            }
	            window.stmTilt.ok = true;
	            return r;
	          }
	          window.stmTilt.denied = true;
	          return r;
	        });
	      }
	      window.stmTilt.ok = true;
	      return Promise.resolve('granted');
	    } catch(err) {
	      window.stmTilt.denied = true;
	      return Promise.resolve('denied');
	    }
	  };
	})();
	"""
	JavaScriptBridge.eval(js, true)
	_web_installed = true
	_web_poll_ready = true


func request_web_permission() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("window.stmRequestTilt && window.stmRequestTilt();", true)


func _poll_web_tilt() -> void:
	var s: String = JavaScriptBridge.eval(
		"(function(){var t=window.stmTilt||{};return JSON.stringify({b:t.beta,g:t.gamma,ax:t.ax,ay:t.ay,ok:!!t.ok,denied:!!t.denied});})();",
		true
	)
	if s.is_empty():
		return
	var parsed: Variant = JSON.parse_string(s)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	if d.get("denied", false):
		status = Status.DENIED
		return
	var v := Vector2.ZERO
	if absf(float(d.get("gamma", 0.0))) > 0.01 or absf(float(d.get("beta", 0.0))) > 0.01:
		v = Vector2(float(d.get("gamma", 0.0)) / 90.0, float(d.get("beta", 0.0)) / 90.0)
	elif absf(float(d.get("ax", 0.0))) > 0.01:
		v = Vector2(float(d.get("ax", 0.0)) / 9.8, float(d.get("ay", 0.0)) / 9.8)
	if v.length() > 0.01:
		_raw = _apply_screen_rotation(v.normalized())
		if d.get("ok", false):
			status = Status.SENSOR


func _apply_screen_rotation(v: Vector2) -> Vector2:
	var angle_deg: int = DisplayServer.screen_get_orientation()
	var rad: float = deg_to_rad(float(angle_deg))
	var c: float = cos(rad)
	var s: float = sin(rad)
	return Vector2(v.x * c - v.y * s, v.x * s + v.y * c)


func _update_status() -> void:
	if _keyboard.length_squared() > 0.0001:
		status = Status.KEYBOARD
	elif _drag_active and _drag_vec.length_squared() > 0.0001:
		status = Status.DRAG
	elif _raw.length_squared() < 0.0001 and status == Status.SENSOR:
		status = Status.KEYBOARD


func get_tilt_vector() -> Vector2:
	var base := Vector2.ZERO
	if _keyboard.length_squared() > 0.0001:
		base = _keyboard.normalized()
	elif _raw.length_squared() > 0.0001:
		base = (_raw - _cal_offset)
		if base.length() > 1.0:
			base = base.normalized()
	elif _drag_active:
		base = _drag_vec
	_apply_deadzone(base)
	_smooth = _smooth.lerp(base, SMOOTH)
	return _smooth


func _apply_deadzone(v: Vector2) -> void:
	if v.length() < DEADZONE:
		v = Vector2.ZERO
	else:
		var t: float = (v.length() - DEADZONE) / (1.0 - DEADZONE)
		v = v.normalized() * clampf(t, 0.0, 1.0)


func status_text() -> String:
	match status:
		Status.SENSOR:
			return "tilt: on"
		Status.DENIED:
			return "tilt: denied"
		Status.UNAVAILABLE:
			return "tilt: unavailable"
		Status.DRAG:
			return "tilt: drag"
		_:
			return "tilt: keyboard"


func calibrate_zero() -> void:
	_cal_offset = _raw
	_save_calibration()


func handle_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_drag_active = true
			_drag_origin = event.position
			_drag_vec = Vector2.ZERO
		else:
			_drag_active = false
			_drag_vec = Vector2.ZERO
	elif event is InputEventScreenDrag and _drag_active:
		var d: Vector2 = (event.position - _drag_origin) * DRAG_SCALE
		_drag_vec = Vector2(
			clampf(d.x, -DRAG_MAX, DRAG_MAX),
			clampf(d.y, -DRAG_MAX, DRAG_MAX)
		)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_active = true
			_drag_origin = event.position
		else:
			_drag_active = false
			_drag_vec = Vector2.ZERO
	elif event is InputEventMouseMotion and _drag_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var md: Vector2 = (event.position - _drag_origin) * DRAG_SCALE
		_drag_vec = Vector2(clampf(md.x, -DRAG_MAX, DRAG_MAX), clampf(md.y, -DRAG_MAX, DRAG_MAX))


func keyboard_override_from_arrows() -> Vector2:
	return _keyboard


func _save_calibration() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("tilt", "ox", _cal_offset.x)
	cfg.set_value("tilt", "oy", _cal_offset.y)
	cfg.save("user://tilt_cal.cfg")


func _load_calibration() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://tilt_cal.cfg") == OK:
		_cal_offset = Vector2(
			float(cfg.get_value("tilt", "ox", 0.0)),
			float(cfg.get_value("tilt", "oy", 0.0))
		)