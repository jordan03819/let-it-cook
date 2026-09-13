extends SceneTree
## Prints the reserved building plots of the authored level, nearest-first from the
## starter plot, with the centre-to-centre distance to the closest other plot.
## Keep this table in step with scenes/levels/VILLAGE_FIELDS.md after layout edits:
##   godot --path . --script res://tools/dump_plots.gd
func _initialize() -> void:
	var ps: PackedScene = load(RunState.HANDCRAFTED_SCENE)
	if ps == null:
		push_error("cannot load level scene")
		quit(1)
		return
	var lvl: VillageFieldsLevel = ps.instantiate()
	root.add_child(lvl)
	var plots: Array[Dictionary] = lvl.house_plots()
	plots.sort_custom(func(a, b): return a["name"] < b["name"])
	print("%-5s %-14s %-9s %8s %8s %7s %7s %8s" % ["plot", "cluster", "role", "x", "z", "y", "facing", "nearest"])
	for p in plots:
		var best := 999.0
		var best_name := ""
		for q in plots:
			if q["name"] == p["name"]:
				continue
			var d: float = (p["position"] as Vector3).distance_to(q["position"] as Vector3)
			if d < best:
				best = d
				best_name = q["name"]
		print("%-5s %-14s %-9s %8.1f %8.1f %7.1f %7.0f %5.2f m -> %s" % [
			p["name"], p["cluster"], p["role"], p["position"].x, p["position"].z,
			p["position"].y, p["facing"], best, best_name])
	print("total plots: %d" % plots.size())
	quit(0)
