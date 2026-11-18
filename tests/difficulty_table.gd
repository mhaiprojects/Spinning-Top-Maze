extends SceneTree
## Print difficulty table. godot --headless --path . --script res://tests/difficulty_table.gd

func _initialize() -> void:
	print("| Wave | Grid | Cells | Hit mult | Decay | Marker spd | Sweet spot | Hazards | Label |")
	print("|------|------|-------|----------|-------|------------|------------|-----------|-------|")
	for w in range(1, 11):
		print(Difficulty.format_table_row(w))
	quit(0)