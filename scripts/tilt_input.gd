extends Node
## Four-mode steering: mouse, keyboard, drag, tilt (+ keyboard override always).

const PlayBg := preload("res://scripts/play_background.gd")

const TILT_TIMEOUT_SEC := 1.5
const AUTO_PROBE_SEC := 0.65

var _settings_path := "user://settings.cfg"
var _mode_explicit := false
var _auto_probing := false
var _auto_probe_left := 0.0
var _web_tilt_data_seen := false
var _web_has_orientation := false
var _web_has_motion := false
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
var _drag_origin_vp := Vector2.ZERO
var _drag_pointer_vp := Vector2.ZERO
var _last_touch_ms := -10000
var _touch_drag_armed := false

signal mode_changed(selected: int, effective: int)
signal fallback_message(text: String)
signal background_changed(id: int)

var _background: int = PlayBg.Id.TABLETOP
var _smooth_target := Vector2.ZERO


func _ready() -> void:
	_load_calibration()
	if OS.has_feature("web"):
		_install_web_tilt()
	_load_mode()
	_load_background()
	PhysicsSettings.load_from_path(_settings_path)
	if _selected_mode == InputModes.Mode.TILT:
		_begin_tilt_watch()


func set_settings_path(path: String) -> void:
	_settings_path = path
	_load_mode()
	_load_background()
	PhysicsSettings.load_from_path(_settings_path)


func settings_path() -> String:
	return _settings_path


func _load_mode() -> void:
	_mode_explicit = UserSettings.load_mode_explicit(_settings_path)
	if _mode_explicit:
		var saved: int = InputModes.load_mode(_settings_path)
		if saved >= 0:
			_apply_mode(saved, false)
			return
	_start_auto_detect()


func _save_mode() -> void:
	UserSettings.save_input_mode_full(_settings_path, _selected_mode, _mode_explicit)


func mode_explicit() -> bool:
	return _mode_explicit


func _start_auto_detect() -> void:
	_mode_explicit = false
	_web_tilt_data_seen = false
	if OS.has_feature("web"):
		_query_web_sensor_caps()
	if _should_auto_probe():
		_auto_probing = true
		_auto_probe_left = AUTO_PROBE_SEC
		_apply_mode(InputModes.auto_pick_mode(_auto_context(false)), false)
	else:
		_apply_mode(InputModes.auto_pick_mode(_auto_context(_native_tilt_data_now())), false)


func _should_auto_probe() -> bool:
	return InputModes.is_touch_device() and OS.has_feature("web")


func _native_tilt_data_now() -> bool:
	return InputModes.native_accel_live()


func _auto_context(web_data: bool) -> Dictionary:
	return {
		"touch": InputModes.is_touch_device(),
		"is_web": OS.has_feature("web"),
		"native_mobile_accel": _native_tilt_data_now(),
		"web_has_orientation": _web_has_orientation,
		"web_has_motion": _web_has_motion,
		"web_tilt_data": web_data or _web_tilt_data_seen,
		"web_tilt_denied": _tilt_denied,
	}


func _query_web_sensor_caps() -> void:
	if not OS.has_feature("web") or not _web_installed:
		return
	var s: String = JavaScriptBridge.eval(
		"(function(){var o=typeof DeviceOrientationEvent!=='undefined';"
		+ "var m=typeof DeviceMotionEvent!=='undefined';"
		+ "return JSON.stringify({o:o,m:m});})();",
		true
	)
	if s.is_empty():
		return
	var d: Variant = JSON.parse_string(s)
	if typeof(d) != TYPE_DICTIONARY:
		return
	_web_has_orientation = bool(d.get("o", false))
	_web_has_motion = bool(d.get("m", false))


func _finish_auto_probe() -> void:
	_auto_probing = false
	_apply_mode(InputModes.auto_pick_mode(_auto_context(true)), false)


func _load_background() -> void:
	_background = UserSettings.load_background(_settings_path)


func _save_background() -> void:
	UserSettings.save_background(_settings_path, _background)


func selected_background() -> int:
	return _background


func background_name() -> String:
	return PlayBg.name_for(_background)


func cycle_background() -> int:
	_background = PlayBg.next_id(_background)
	_save_background()
	background_changed.emit(_background)
	return _background


func set_background(id: int) -> void:
	if not PlayBg.ORDER.has(id):
		return
	_background = id
	_save_background()
	background_changed.emit(_background)


func selected_mode() -> int:
	return _selected_mode


func effective_mode() -> int:
	return _effective_mode


func cycle_mode() -> void:
	_commit_explicit_mode(InputModes.next_mode(_selected_mode))


func set_mode(mode: int) -> void:
	if not InputModes.ORDER.has(mode):
		return
	_commit_explicit_mode(mode)


func apply_auto_detect() -> void:
	_mode_explicit = false
	_start_auto_detect()
	UserSettings.save_input_mode_full(_settings_path, _selected_mode, false)


func pick_mode_from_ui(mode: int) -> void:
	if not InputModes.ORDER.has(mode):
		return
	_commit_explicit_mode(mode)
	if mode == InputModes.Mode.TILT and OS.has_feature("web"):
		request_web_permission()


func tilt_picker_enabled() -> bool:
	if not InputModes.is_touch_device() and not OS.has_feature("mobile"):
		return false
	if OS.has_feature("web"):
		return (_web_has_orientation or _web_has_motion) and not _tilt_denied
	return InputModes.native_accel_live() or OS.has_feature("mobile")


func _commit_explicit_mode(mode: int) -> void:
	_mode_explicit = true
	_auto_probing = false
	_apply_mode(mode, true)


func _apply_mode(mode: int, persist: bool) -> void:
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
	if _auto_probing:
		_auto_probe_left -= delta
		if _web_tilt_data_seen or _tilt_denied or _auto_probe_left <= 0.0:
			_finish_auto_probe()
	if _selected_mode == InputModes.Mode.TILT or _effective_mode == InputModes.Mode.TILT:
		_poll_tilt_sources(delta)
		_maybe_tilt_fallback(delta)
	_update_cursor_world()
	_refresh_effective_from_selection()
	_smooth_target = _compute_steer_target()
	var alpha: float = InputModes.smooth_alpha(
		delta,
		PhysicsSettings.get_value("tilt_response")
	)
	_smooth = _smooth.lerp(_smooth_target, alpha)
	if _drag_active and _effective_mode == InputModes.Mode.DRAG and not _steer_blocked and not _touch_drag_armed:
		var vp: Viewport = get_viewport()
		if vp:
			_drag_pointer_vp = vp.get_mouse_position()
			_drag_pointer = _drag_pointer_vp
			_notify_drag_overlay(true)


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


func steer_blocked() -> bool:
	return _steer_blocked


func set_steer_blocked(blocked: bool) -> void:
	_steer_blocked = blocked
	if blocked:
		_drag_active = false
		_notify_drag_overlay(false)


func release_menu_drag() -> void:
	_drag_active = false
	_touch_drag_armed = false
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
		return kb
	return _smooth


func _compute_steer_target() -> Vector2:
	var kb: Vector2 = InputModes.steer_keyboard(
		Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A),
		Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D),
		Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W),
		Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S)
	)
	if kb.length_squared() > 0.0001:
		return kb
	var base := Vector2.ZERO
	match _effective_mode:
		InputModes.Mode.MOUSE:
			base = InputModes.steer_mouse(_cursor_world, _top_world)
		InputModes.Mode.KEYBOARD:
			base = Vector2.ZERO
		InputModes.Mode.DRAG:
			base = InputModes.steer_drag(
				_drag_pointer,
				_drag_origin,
				_drag_active and not _steer_blocked
			)
		InputModes.Mode.TILT:
			base = InputModes.steer_tilt(_raw_tilt, _cal_offset)
	return base


func get_tilt_vector() -> Vector2:
	return get_steer_vector()


func drag_active() -> bool:
	return _drag_active


func mode_label_for_settings() -> String:
	var base: String = InputModes.mode_name(_selected_mode)
	if not _mode_explicit:
		return "%s (Auto)" % base
	return base


func status_text() -> String:
	var label: String = "Input: %s" % mode_label_for_settings()
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


func _input(event: InputEvent) -> void:
	handle_input(event)


func _event_viewport_pos(event: InputEvent) -> Vector2:
	if event is InputEventMouse:
		return (event as InputEventMouse).position
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return (event as InputEventFromWindow).position
	return Vector2.ZERO


func _is_emulated_mouse_from_touch() -> bool:
	if not OS.has_feature("web"):
		return false
	return Time.get_ticks_msec() - _last_touch_ms < 80


func _maybe_request_ios_tilt_on_gesture(event: InputEvent) -> void:
	if _mode_explicit or not OS.has_feature("web"):
		return
	var gesture: bool = (
		(event is InputEventScreenTouch and event.pressed)
		or (event is InputEventMouseButton and event.pressed)
	)
	if gesture:
		request_web_permission()


func handle_input(event: InputEvent) -> void:
	_maybe_request_ios_tilt_on_gesture(event)
	if _steer_blocked or _effective_mode != InputModes.Mode.DRAG:
		return

	if event is InputEventScreenTouch:
		_last_touch_ms = Time.get_ticks_msec()
		_touch_drag_armed = true
		var pos := _event_viewport_pos(event)
		if event.pressed:
			_drag_active = true
			_drag_origin_vp = pos
			_drag_pointer_vp = pos
			_drag_origin = pos
			_drag_pointer = pos
			_notify_drag_overlay(true)
		else:
			_drag_active = false
			_touch_drag_armed = false
			_smooth = Vector2.ZERO
			_notify_drag_overlay(false)
	elif event is InputEventScreenDrag:
		if _drag_active:
			var p := _event_viewport_pos(event)
			_drag_pointer_vp = p
			_drag_pointer = p
			_notify_drag_overlay(true)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_emulated_mouse_from_touch():
			return
		var pos := _event_viewport_pos(event)
		if event.pressed:
			_drag_active = true
			_touch_drag_armed = false
			_drag_origin_vp = pos
			_drag_pointer_vp = pos
			_drag_origin = pos
			_drag_pointer = pos
			_notify_drag_overlay(true)
		else:
			_drag_active = false
			_smooth = Vector2.ZERO
			_notify_drag_overlay(false)
	elif event is InputEventMouseMotion:
		if not _drag_active:
			return
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			return
		var p := _event_viewport_pos(event)
		_drag_pointer_vp = p
		_drag_pointer = p
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
	_cursor_world = _viewport_to_world(vp, vp.get_mouse_position())


func _viewport_to_world(vp: Viewport, viewport_pos: Vector2) -> Vector2:
	var canvas: Transform2D = vp.get_canvas_transform()
	return canvas.affine_inverse() * viewport_pos


func _poll_tilt_sources(_delta: float) -> void:
	if OS.has_feature("web"):
		_poll_web_tilt()
	else:
		_poll_native_accel()


func _poll_native_accel() -> void:
	var a: Vector3 = Input.get_accelerometer()
	if a == Vector3.ZERO:
		return
	var sens: float = PhysicsSettings.get_value("tilt_sensitivity")
	var ang: float = InputModes.native_screen_rotation_deg()
	var screen: Vector2 = InputModes.device_accel_to_screen_steer(Vector2(a.x, a.y), ang)
	var mapped: Vector2 = screen * sens
	if mapped.length() > 1.0:
		mapped = mapped.normalized()
	if mapped.length() > 0.001:
		_raw_tilt = mapped
		_tilt_live = true


func _install_web_tilt() -> void:
	if _web_installed:
		return
	var js := """
	(function(){
	  if (window.stmTilt) return;
	  window.stmTilt = { beta: 0, gamma: 0, ax: 0, ay: 0, ang: 0, ok: false, denied: false };
	  function screenAngle(){
	    var a = 0;
	    try {
	      if (window.screen && window.screen.orientation && typeof screen.orientation.angle === 'number')
	        a = screen.orientation.angle;
	      else if (typeof window.orientation === 'number')
	        a = window.orientation;
	    } catch(e) {}
	    return ((a % 360) + 360) % 360;
	  }
	  function isAppleTilt(){
	    var ua = navigator.userAgent || '';
	    if (/iPad|iPhone|iPod/.test(ua)) return true;
	    if (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1) return true;
	    return false;
	  }
	  function normalizeAccelToAndroid(ax, ay){
	    if (isAppleTilt()) return { ax: -ax, ay: -ay };
	    return { ax: ax, ay: ay };
	  }
	  function upd(b,g){
	    window.stmTilt.beta = b || 0;
	    window.stmTilt.gamma = g || 0;
	    window.stmTilt.ang = screenAngle();
	    window.stmTilt.ok = true;
	  }
	  window.addEventListener('deviceorientation', function(e){ upd(e.beta, e.gamma); }, true);
	  window.addEventListener('devicemotion', function(e){
	    var a = e.accelerationIncludingGravity;
	    if (a) {
	      var n = normalizeAccelToAndroid(a.x||0, a.y||0);
	      window.stmTilt.ax = n.ax; window.stmTilt.ay = n.ay;
	      window.stmTilt.ang = screenAngle();
	    }
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
		"(function(){var t=window.stmTilt||{};return JSON.stringify({b:t.beta,g:t.gamma,ax:t.ax,ay:t.ay,ang:t.ang||0,ok:!!t.ok,denied:!!t.denied});})();",
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
	var sens: float = PhysicsSettings.get_value("tilt_sensitivity")
	var full: float = PhysicsSettings.get_value("tilt_full_scale_deg")
	var ang: float = float(d.get("ang", 0.0))
	var mapped := Vector2.ZERO
	if absf(float(d.get("gamma", 0.0))) > 0.01 or absf(float(d.get("beta", 0.0))) > 0.01:
		var scr: Vector2 = InputModes.device_angles_to_screen_steer(
			float(d.get("gamma", 0.0)),
			float(d.get("beta", 0.0)),
			ang
		)
		mapped = InputModes.map_device_tilt(scr, full, sens)
	elif absf(float(d.get("ax", 0.0))) > 0.01:
		var screen: Vector2 = InputModes.device_accel_to_screen_steer(
			Vector2(float(d.get("ax", 0.0)), float(d.get("ay", 0.0))),
			ang
		)
		mapped = screen * sens
		if mapped.length() > 1.0:
			mapped = mapped.normalized()
	if mapped.length() > 0.01:
		_raw_tilt = mapped
		_tilt_live = true
		_web_tilt_data_seen = true


func _notify_drag_overlay(on: bool) -> void:
	var stick: Node = get_tree().root.get_node_or_null("Main/DragStick/Draw")
	if stick == null:
		stick = get_tree().root.get_node_or_null("Main/DragStick")
	if stick == null:
		return
	if on and stick.has_method("show_stick"):
		stick.call("show_stick", _drag_origin_vp, _drag_pointer_vp)
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