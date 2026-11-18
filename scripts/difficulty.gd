class_name Difficulty
extends RefCounted
## Central wave difficulty curve (testable).

const LABELS: PackedStringArray = ["Easy", "Easy+", "Medium", "Medium+", "Hard", "Hard+", "Expert", "Expert+", "Master", "Master+"]


static func params_for_wave(wave: int) -> Dictionary:
	var w: int = maxi(1, wave)
	var cols: int = clampi(3 + ((w - 1) * 7) / 9, 3, 10)
	var rows: int = clampi(4 + ((w - 1) * 10) / 9, 4, 14)
	var extra_remove: float = clampf(0.52 - float(w - 1) * 0.035, 0.04, 0.52)
	var wall_hit_mult: float = 1.0 + float(w - 1) * 0.06
	var spin_decay: float = 2.2 + float(w - 1) * 0.12
	var marker_speed: float = 1.45 + float(w - 1) * 0.08
	var sweet_spot: float = clampf(0.2 - float(w - 1) * 0.008, 0.08, 0.2)
	var hazards: int = clampi((w - 3) / 2, 0, 8)
	var label_idx: int = clampi(w - 1, 0, LABELS.size() - 1)
	return {
		"wave": w,
		"cols": cols,
		"rows": rows,
		"cells": cols * rows,
		"extra_wall_remove": extra_remove,
		"wall_hit_mult": wall_hit_mult,
		"spin_decay": spin_decay,
		"marker_speed": marker_speed,
		"sweet_spot_frac": sweet_spot,
		"hazards": hazards,
		"difficulty_label": LABELS[label_idx],
		"stars": clampi(1 + (w - 1) / 2, 1, 5),
	}


static func metric_keys_monotonic() -> Array[String]:
	return ["cells", "wall_hit_mult", "spin_decay", "marker_speed", "hazards"]


static func is_easy_wave_1() -> bool:
	var p: Dictionary = params_for_wave(1)
	return p.cols == 3 and p.rows == 4 and p.extra_wall_remove >= 0.45


static func format_table_row(wave: int) -> String:
	var p: Dictionary = params_for_wave(wave)
	return (
		"| %d | %dx%d | %d | %.2f | %.2f | %.2f | %.0f%% | %d | %s |"
		% [
			wave,
			p.cols,
			p.rows,
			p.cells,
			p.wall_hit_mult,
			p.spin_decay,
			p.marker_speed,
			p.sweet_spot_frac * 100.0,
			p.hazards,
			p.difficulty_label,
		]
	)