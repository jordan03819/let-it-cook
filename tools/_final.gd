extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	RunState.reset_run()
	RunState.start_level(3)
	change_scene_to_file("res://scenes/game.tscn")
	await process_frame
	await process_frame
	var game := current_scene
	for i in 25:
		await process_frame
	var trees := game.get_node("Village/Terrain/Trees").get_child_count()
	var vs := get_nodes_in_group("villagers")
	var models := {}
	var clips := {}
	for v in vs:
		var vis: Node3D = v.get("_visual")
		var p := KitCharacter.animation_player(vis)
		clips[p.current_animation] = int(clips.get(p.current_animation, 0)) + 1
		for c in vis.get_children():
			if String(c.name).begins_with("character-"):
				models[String(c.name)] = true
	print("houses=%d  villagers=%d  distinct characters=%d  tree props=%d  water sources=%d" % [
		game.houses.size(), vs.size(), models.size(), trees, get_nodes_in_group("water_sources").size()])
	print("villager heights: %.2f m  clips=%s" % [
		KitCharacter.meshes(vs[0].get("_visual"))[0].mesh.get_aabb().size.y * (vs[0].get("_visual") as Node3D).scale.y, str(clips)])
	quit()
