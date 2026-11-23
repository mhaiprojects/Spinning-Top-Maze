class_name PhysicsSettings
extends RefCounted
## Central tunables for top steering / physics (live + persisted).

const TopScript := preload("res://scripts/spinning_top.gd")

const SECTION := "physics"
const LS_KEY := "stm_physics"
const PHYSICS_VERSION := 2
const VERSION_KEY := "physics_version"
const MIGRATE_EPS := 0.001

const LEGACY_DEFAULTS: Dictionary = {
	"tilt_response": 2.0,
	"tilt_sensitivity": 1.0,
	"lean_max_deg": 28.0,
}

static var _values: Dictionary = {}
static var _revision: int = 0

static var DEFS: Array[Dictionary] = [
	{
		"key": "tilt_response",
		"label": "Tilt response",
		"default": 3.0,
		"min": 0.5,
		"max": 4.0,
		"step": 0.05,
	},
	{
		"key": "tilt_sensitivity",
		"label": "Tilt sensitivity",
		"default": 3.0,
		"min": 0.25,
		"max": 3.0,
		"step": 0.05,
	},
	{
		"key": "tilt_full_scale_deg",
		"label": "Tilt full scale (deg)",
		"default": 35.0,
		"min": 10.0,
		"max": 90.0,
		"step": 1.0,
	},
	{
		"key": "lean_max_deg",
		"label": "Max lean (deg)",
		"default": 45.0,
		"min": 5.0,
		"max": 60.0,
		"step": 1.0,
	},
	{
		"key": "lean_stiffness",
		"label": "Lean stiffness",
		"default": 10.0,
		"min": 1.0,
		"max": 30.0,
		"step": 0.5,
	},
	{
		"key": "precession_rate",
		"label": "Precession rate",
		"default": 2.5,
		"min": 0.0,
		"max": 10.0,
		"step": 0.1,
	},
	{
		"key": "low_scale",
		"label": "Gentle tier scale",
		"default": 0.35,
		"min": 0.05,
		"max": 1.5,
		"step": 0.05,
	},
	{
		"key": "high_scale",
		"label": "Hard tier scale",
		"default": 1.6,
		"min": 0.5,
		"max": 4.0,
		"step": 0.05,
	},
	{
		"key": "tier_threshold",
		"label": "Tier threshold",
		"default": 0.5,
		"min": 0.1,
		"max": 0.9,
		"step": 0.02,
	},
	{
		"key": "tier_blend",
		"label": "Tier blend width",
		"default": 0.18,
		"min": 0.02,
		"max": 0.4,
		"step": 0.01,
	},
	{
		"key": "steer_force",
		"label": "Steer force",
		"default": TopScript.STEER_FORCE,
		"min": 100.0,
		"max": 1500.0,
		"step": 10.0,
	},
	{
		"key": "max_speed",
		"label": "Max speed",
		"default": TopScript.MAX_LINEAR_SPEED,
		"min": 150.0,
		"max": 1500.0,
		"step": 10.0,
	},
	{
		"key": "linear_damp",
		"label": "Linear damp",
		"default": 2.2,
		"min": 0.0,
		"max": 8.0,
		"step": 0.1,
	},
	{
		"key": "spin_decay_mult",
		"label": "Spin decay mult",
		"default": 1.0,
		"min": 0.0,
		"max": 3.0,
		"step": 0.05,
	},
	{
		"key": "wall_hit_slowdown",
		"label": "Wall hit slowdown",
		"default": TopScript.HIT_VEL_SCALE,
		"min": 0.1,
		"max": 1.0,
		"step": 0.05,
	},
	{
		"key": "wall_hit_loss_mult",
		"label": "Wall hit loss mult",
		"default": 1.0,
		"min": 0.0,
		"max": 3.0,
		"step": 0.05,
	},
	{
		"key": "fall_threshold",
		"label": "Fall threshold (%)",
		"default": 0.0,
		"min": 0.0,
		"max": 40.0,
		"step": 1.0,
	},
]


static func _def_for(key: String) -> Dictionary:
	for d in DEFS:
		if d.key == key:
			return d
	return {}


static func defaults() -> Dictionary:
	var out := {}
	for d in DEFS:
		out[d.key] = d.default
	return out


static func reset_all() -> void:
	_values = defaults()
	_bump_revision()


static func reset(key: String) -> void:
	var d: Dictionary = _def_for(key)
	if d.is_empty():
		return
	_values[key] = d.default
	_bump_revision()


static func revision() -> int:
	return _revision


static func _bump_revision() -> void:
	_revision += 1


static func _clamp_key(key: String, v: float) -> float:
	var d: Dictionary = _def_for(key)
	if d.is_empty():
		return v
	return clampf(v, float(d.min), float(d.max))


static func get_value(key: String) -> float:
	if _values.is_empty():
		reset_all()
	if _values.has(key):
		return float(_values[key])
	var d: Dictionary = _def_for(key)
	return float(d.get("default", 0.0))


static func set_value(key: String, v: float) -> void:
	if _values.is_empty():
		reset_all()
	if _def_for(key).is_empty():
		return
	var cv: float = _clamp_key(key, v)
	if _values.get(key, null) == cv:
		return
	_values[key] = cv
	_bump_revision()


static func load_from_path(path: String = UserSettings.DEFAULT_PATH) -> void:
	if _values.is_empty():
		reset_all()
	var cfg := UserSettings.load_config(path)
	var has_section := cfg.has_section(SECTION)
	var saved_ver := 0
	if has_section:
		for d in DEFS:
			var k: String = d.key
			if cfg.has_section_key(SECTION, k):
				_values[k] = _clamp_key(k, float(cfg.get_value(SECTION, k, d.default)))
		if cfg.has_section_key(SECTION, VERSION_KEY):
			saved_ver = int(cfg.get_value(SECTION, VERSION_KEY, 0))
	elif OS.has_feature("web"):
		saved_ver = _load_local_storage()
	if _apply_version_migration(saved_ver):
		save_to_path(path)
	_bump_revision()


static func save_to_path(path: String = UserSettings.DEFAULT_PATH) -> bool:
	if OS.get_environment("STM_HEADLESS_TEST") == "1" and path == UserSettings.DEFAULT_PATH:
		return false
	var cfg := UserSettings.load_config(path)
	for d in DEFS:
		cfg.set_value(SECTION, d.key, get_value(d.key))
	cfg.set_value(SECTION, VERSION_KEY, PHYSICS_VERSION)
	if OS.has_feature("web"):
		_mirror_local_storage()
	return UserSettings.save_config(path, cfg)


static func _legacy_value_matches(key: String, v: float) -> bool:
	if not LEGACY_DEFAULTS.has(key):
		return false
	return absf(v - float(LEGACY_DEFAULTS[key])) <= MIGRATE_EPS


static func _apply_version_migration(saved_ver: int) -> bool:
	if saved_ver >= PHYSICS_VERSION:
		return false
	var changed := false
	for key in LEGACY_DEFAULTS.keys():
		var cur: float = get_value(key)
		if _legacy_value_matches(key, cur):
			var nv: float = float(_def_for(key).default)
			if not is_equal_approx(cur, nv):
				_values[key] = nv
				changed = true
	return changed


static func _mirror_local_storage() -> void:
	var payload := {VERSION_KEY: PHYSICS_VERSION}
	for d in DEFS:
		payload[d.key] = get_value(d.key)
	var json := JSON.stringify(payload)
	JavaScriptBridge.eval(
		"(function(){try{localStorage.setItem('%s',%s);}catch(e){}})();" % [LS_KEY, json],
		true
	)


static func _load_local_storage() -> int:
	var s: String = JavaScriptBridge.eval(
		"(function(){try{return localStorage.getItem('%s')||'';}catch(e){return '';}})();" % LS_KEY,
		true
	)
	if s.is_empty():
		return 0
	var parsed: Variant = JSON.parse_string(s)
	if typeof(parsed) != TYPE_DICTIONARY:
		return 0
	var dct: Dictionary = parsed
	for d in DEFS:
		if dct.has(d.key):
			_values[d.key] = _clamp_key(d.key, float(dct[d.key]))
	if dct.has(VERSION_KEY):
		return int(dct[VERSION_KEY])
	return 0