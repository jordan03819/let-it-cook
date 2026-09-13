extends SceneTree
## Temporary: the heat-link overlay must survive a link it cannot draw.
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	RunState.reset_run()
	RunState.start_level(3)
	change_scene_to_file("res://scenes/game.tscn")
	await process_frame
	await process_frame
	var game := current_scene
	for i in 20:
		await process_frame
	# A live link, a dead one, and a degenerate one.
	var a: VoxelHouse = game.mandatory_houses[0]
	var b: VoxelHouse = game.mandatory_houses[1]
	var corpse := VoxelHouse.new()
	root.add_child(corpse)
	corpse.position = a.position + Vector3(1, 0, 0)
	a.ignite()
	game.fire_sim.active_heat_links = [
		{"src": a, "dst": b, "power": 0.5},
		{"src": a, "dst": corpse, "power": 0.5},     # too short to draw
	]
	game._update_heat_link_preview(0.5)
	print("two links, one undrawable: ok")
	game.fire_sim.active_heat_links = [{"src": a, "dst": corpse, "power": 0.5}]
	game._update_heat_link_preview(0.5)
	print("no drawable links: ok")
	game.fire_sim.active_heat_links = []
	game._update_heat_link_preview(0.5)
	print("no links at all: ok")
	quit()
