extends Node
## Four-mode steering: mouse, keyboard, drag, tilt (+ keyboard override always).

const SMOOTH := 0.18
const TILT_TIMEOUT_SEC := 1.5

var _settings_path := "user://settings.cfg"
var _selected_mode: int = InputModes.Mode.MOUSE
var _effective_mode: int = InputModes.Mode.MOUSE
var _smooth := Vector2.ZERO
var _cal_offset := Vector2.ZERO
var _raw_tilt := Vector2.ZERO
var _tilt_live := false
var _tilt_denied := false
var _tilt_watch := 0.0
var _fallback_msg := ""

var _top_world := Vector2.ZERO
var _cursor_world := Vector2.ZERO

var _drag_active := false
var _drag_origin := Vector2.ZERO
var _drag_pointer := Vector2.ZERO

var _steer_blocked := false
var _web_installed := false
var _test_steer: Variant = null

signal mode_changed(selected: int, effective: int)
signal fallback_message(text: String)


func _ready() -> void:
	_load_calibration()
	_load_mode()
	if OS.has_feature("web"):
		_install_web_tilt()
	if _selected_mode == InputModes.Mode.TILT:
		_begin_tilt_watch()


func set_settings_path(path: String) -> void:
	_settings_path = path


func settings_path() -> String:
	return _settings_path


func _load_mode() -> void:
	var saved: int = InputModes.load_mode(_settings_path)
	if saved >= 0:
		_set_selected_mode(saved, false)
	else:
		var touch: bool = InputModes.is_touch_device()
		var sensor: bool = InputModes.native_accel_available()
		_set_selected_mode(InputModes.default_mode(touch, sensor), false)


func _save_mode() -> void:
	InputModes.save_mode(_settings_path, _selected_mode)


func selected_mode() -> int:
	return _selected_mode


func effective_mode() -> int:
	return _effective_mode


func cycle_mode() -> void:
	_set_selected_mode(InputModes.next_mode(_selected_mode), true)


func set_mode(mode: int) -> void:
	if not InputModes.ORDER.has(mode):
		return
	_set_selected_mode(mode, true)


func _set_selected_mode(mode: int, persist: bool) -> void:
	_selected_mode = mode
	_effective_mode = mode
	_fallback_msg = ""
	if mode == InputModes.Mode.TILT:
		_begin_tilt_watch()
		if OS.has_feature("web"):
			request_web_permission()
	else:
		_tilt_watch = 0.0
	if persist:
		_save_mode()
	mode_changed.emit(_selected_mode, _effective_mode)


func _begin_tilt_watch() -> void:
	_tilt_watch = TILT_TIMEOUT_SEC
	_tilt_live = false
	_tilt_denied = false


func _process(delta: float) -> void:
	if _selected_mode == InputModes.Mode.TILT or _effective_mode == InputModes.Mode.TILT:
		_poll_tilt_sources(delta)
		_maybe_tilt_fallback(delta)
	_update_cursor_world()
	_refresh_effective_from_selection()


func _refresh_effective_from_selection() -> void:
	if _selected_mode != InputModes.Mode.TILT:
		_effective_mode = _selected_mode
		return
	if _fallback_msg != "":
		_effective_mode = InputModes.tilt_fallback_mode(InputModes.is_touch_device())
	else:
		_effective_mode = InputModes.Mode.TILT


func _maybe_tilt_fallback(delta: float) -> void:
	if _selected_mode != InputModes.Mode.TILT:
		return
	if _tilt_denied:
		_apply_fallback("Tilt unavailable — using %s" % InputModes.mode_name(InputModes.tilt_fallback_mode(InputModes.is_touch_device())))
		return
	if _tilt_live:
		_tilt_watch = 0.0
		_fallback_msg = ""
		return
	if _tilt_watch <= 0.0:
		return
	_tilt_watch -= delta
	if _tilt_watch <= 0.0:
		_apply_fallback("Tilt unavailable — using %s" % InputModes.mode_name(InputModes.tilt_fallback_mode(InputModes.is_touch_device())))


func _apply_fallback(msg: String) -> void:
	if _fallback_msg == msg:
		return
	_fallback_msg = msg
	fallback_message.emit(msg)
	mode_changed.emit(_selected_mode, _effective_mode)


func set_top_world_position(pos: Vector2) -> void:
	_top_world = pos


func set_steer_blocked(blocked: bool) -> void:
	_steer_blocked = blocked
	if blocked:
		_drag_active = false
		_notify_drag_overlay(false)


func set_test_steer_vector(v: Vector2) -> void:
	_test_steer = v


func clear_test_steer_vector() -> void:
	_test_steer = null


func get_steer_vector() -> Vector2:
	if _test_steer is Vector2:
		return _test_steer as Vector2
	var kb: Vector2 = InputModes.steer_keyboard(
		Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A),
		Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D),
		Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W),
		Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)
	)
	if kb.length_squared() > 0.0001:
		_smooth = _smooth.lerp(kb, SMOOTH)
		return _smooth

	var base := Vector2.ZERO
	match _effective_mode:
		InputModes.Mode.MOUSE:
			base = InputModes.steer_mouse(_cursor_world, _top_world)
		InputModes.Mode.KEYBOARD:
			base = Vector2.ZERO
		InputModes.Mode.DRAG:
			base = InputModes.steer_drag(_drag_pointer, _drag_origin, _drag_active and not _steer_blocked)
		InputModes.Mode.TILT:
			var oriented: Vector2 = _raw_tilt
			base = InputModes.steer_tilt(_raw_tilt, _cal_offset, oriented)

	_smooth = _smooth.lerp(base, SMOOTH)
	return _smooth


func get_tilt_vector() -> Vector2:
	return get_steer_vector()


func status_text() -> String:
	var label: String = "Input: %s" % InputModes.mode_name(_selected_mode)
	if _selected_mode == InputModes.Mode.TILT and _fallback_msg != "":
		label += " (steer: %s)" % InputModes.mode_name(_effective_mode)
	elif _selected_mode == InputModes.Mode.TILT and _tilt_denied:
		label += " (denied)"
	elif _selected_mode == InputModes.Mode.TILT and _tilt_live:
		label += " (on)"
	return label


func calibrate_zero() -> void:
	_cal_offset = _raw_tilt
	_save_calibration()


func handle_input(event: InputEvent) -> void:
	if _steer_blocked or _effective_mode != InputModes.Mode.DRAG:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_drag_active = true
			_drag_origin = event.position
			_drag_pointer = event.position
			_notify_drag_overlay(true)
		else:
			_drag_active = false
			_notify_drag_overlay(false)
	elif event is InputEventScreenDrag:
		if _drag_active:
			_drag_pointer = event.position
			_notify_drag_overlay(true)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_active = true
			_drag_origin = event.position
			_drag_pointer = event.position
			_notify_drag_overlay(true)
		else:
			_drag_active = false
			_notify_drag_overlay(false)
	elif event is InputEventMouseMotion and _drag_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_drag_pointer = event.position
		_notify_drag_overlay(true)


func keyboard_override_from_arrows() -> Vector2:
	return InputModes.steer_keyboard(
		Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A),
		Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D),
		Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W),
		Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)
	)


func _update_cursor_world() -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var canvas: Transform2D = vp.get_canvas_transform()
	_cursor_world = canvas.affine_inverse() * vp.get_mouse_position()


func _poll_tilt_sources(_delta: float) -> void:
	if OS.has_feature("web"):
		_poll_web_tilt()
	else:
		_poll_native_accel()


func _poll_native_accel() -> void:
	var a: Vector3 = Input.get_accelerometer()
	if a == Vector3.ZERO:
		return
	var v := Vector2(a.x, a.y)
	if v.length() > 0.001:
		_raw_tilt = InputModes.rotate_for_screen(v.normalized(), float(DisplayServer.screen_get_orientation()))
		_tilt_live = true


func _install_web_tilt() -> void:
	if _web_installed:
		return
	var js := """
	(function(){
	  if (window.stmTilt) return;
	  window.stmTilt = { beta: 0, gamma: 0, ax: 0, ay: 0, ok: false, denied: false };
	  function upd(b,g){ window.stmTilt.beta = b||0; window.stmTilt.gamma = g||0; window.stmTilt.ok = true; }
	  window.addEventListener('deviceorientation', function(e){ upd(e.beta, e.gamma); }, true);
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
		_tilt_denied = true
		return
	var v := Vector2.ZERO
	if absf(float(d.get("gamma", 0.0))) > 0.01 or absf(float(d.get("beta", 0.0))) > 0.01:
		v = Vector2(float(d.get("gamma", 0.0)) / 90.0, float(d.get("beta", 0.0)) / 90.0)
	elif absf(float(d.get("ax", 0.0))) > 0.01:
		v = Vector2(float(d.get("ax", 0.0)) / 9.8, float(d.get("ay", 0.0)) / 9.8)
	if v.length() > 0.01:
		_raw_tilt = InputModes.rotate_for_screen(v.normalized(), float(DisplayServer.screen_get_orientation()))
		_tilt_live = true


func _notify_drag_overlay(on: bool) -> void:
	var stick: Node = get_tree().root.get_node_or_null("Main/DragStick/Draw")
	if stick == null:
		stick = get_tree().root.get_node_or_null("Main/DragStick")
	if stick == null:
		return
	if on and stick.has_method("show_stick"):
		stick.call("show_stick", _drag_origin, _drag_pointer)
	elif not on and stick.has_method("hide_stick"):
		stick.call("hide_stick")


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