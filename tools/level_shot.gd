extends SceneTree
## Dev-only screenshot harness (not part of the game).
## Boots the real game scene and captures images through the game's own Camera3D,
## so screenshots match exactly what a player sees.
##
## Usage:
##   godot --path . --script res://tools/level_shot.gd -- --level=3 --out=/tmp/shots --tag=fields
##
## Options:
##   --level=N     RunState level index to load (default 0)
##   --out=DIR     Output directory (default /tmp/shots)
##   --tag=NAME    Filename prefix (default "shot")
##   --views=a,b   Comma list of views (see VIEWS below)
##   --hud=1|0     Include the in-game HUD (default 0)
##   --size=WxH    Window size (default 1600x900)
##   --fullscreen=1  Go fullscreen first: tiling compositors (Hyprland, i3, ...)
##                 ignore window_set_size, so this is the reliable way to get a
##                 predictable, wide viewport for screenshots.

const VIEWS := {
	# name: [rig position, covered metres]
	# "covered metres" is the world size the *smaller* screen dimension must show;
	# the camera size is derived from the live viewport aspect so a shot frames the
	# same region whatever geometry the window manager hands us.
	"overview": [Vector3(0, 0, 0), 34.0],
	"core": [Vector3(0, 0, 0), 18.0],
	"north": [Vector3(0, 0, -14), 20.0],
	"south": [Vector3(0, 0, 14), 20.0],
	"west": [Vector3(-14, 0, 0), 20.0],
	"east": [Vector3(14, 0, 0), 20.0],
	"wide": [Vector3(0, 0, 0), 46.0],
	"fit": [Vector3(0, 0, 2), 52.0],
	"close": [Vector3(0, 0, 0), 12.0],
	"plan": [Vector3(0, 0, 0), 52.0],
	"hill": [Vector3(22, 0, -18), 18.0],
	"pond": [Vector3(-15, 0, 9), 20.0],
	"green": [Vector3(-10, 0, 0), 17.0],
	"farm": [Vector3(20, 0, 2), 20.0],
	"hillnw": [Vector3(-18, 0, -17), 18.0],
	"plan_west": [Vector3(-12, 0, 0), 22.0],
	"plan_east": [Vector3(14, 0, 0), 22.0],
}

var _out_dir := "/tmp/shots"
var _tag := "shot"
var _level := 0
var _hud := false
var _views: Array = ["overview", "core", "north", "south"]
var _scene := ""
var _hide: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var parts := a.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"--level": _level = int(parts[1])
			"--out": _out_dir = parts[1]
			"--tag": _tag = parts[1]
			"--hud": _hud = int(parts[1]) != 0
			"--views": _views = parts[1].split(",", false)
			"--scene": _scene = parts[1]
			"--fullscreen":
				if int(parts[1]) != 0:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			"--hide": _hide = parts[1].split(",", false)
			"--size":
				var wh := parts[1].split("x")
				if wh.size() == 2:
					DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
					# Tiling compositors ignore window_set_size; asking for a fixed
					# (non-resizable) window makes them honour it.
					DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, true)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run()


func _run() -> void:
	await process_frame
	RunState.reset_run()
	RunState.start_level(_level)

	var err := change_scene_to_file("res://scenes/game.tscn")
	if err != OK:
		push_error("level_shot: change_scene_to_file failed: %d" % err)
		quit(1)
		return
	await process_frame
	await process_frame

	var game := current_scene
	if game == null:
		push_error("level_shot: game scene failed to load")
		quit(1)
		return

	# Optional: swap the procedurally built level for a handcrafted scene so it can be
	# previewed through the real game camera / lighting / HUD.
	if _scene != "":
		var village := game.get_node_or_null("Village") as Node3D
		if village == null:
			push_error("level_shot: Village node missing")
			quit(1)
			return
		for c in village.get_children():
			village.remove_child(c)
			c.queue_free()
		var ps: PackedScene = load(_scene)
		if ps == null:
			push_error("level_shot: could not load scene %s" % _scene)
			quit(1)
			return
		village.add_child(ps.instantiate())
		await process_frame

	for hidden in _hide:
		for n in game.get_node("Village").find_children(String(hidden).get_file(), "", true, false):
			(n as Node3D).visible = false

	var hud := game.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = _hud

	var rig := game.get_node_or_null("CameraRig") as Node3D
	var cam := game.get_node_or_null("CameraRig/Camera3D") as Camera3D
	if rig == null or cam == null:
		push_error("level_shot: camera nodes missing")
		quit(1)
		return

	var we := game.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var s3 := game.get_node_or_null("Sun") as DirectionalLight3D
	if we != null and we.environment != null:
		print("level_shot: env bg_mode=%d fog=%s ambient_src=%d" % [
			we.environment.background_mode, we.environment.fog_enabled, we.environment.ambient_light_source])
	if s3 != null:
		print("level_shot: sun energy=%.2f color=%s" % [s3.light_energy, s3.light_color])

	# Let the level settle (particles, lighting, deferred setup).
	for i in 30:
		await process_frame

	var base_cam_xform: Transform3D = cam.transform
	var vp_size := Vector2(root.get_visible_rect().size)
	var vp_aspect := vp_size.x / maxf(1.0, vp_size.y)
	# Camera ortho size that guarantees `covered` metres fit in the tight dimension.
	var cover_scale: float = 1.0 / minf(1.0, vp_aspect)
	print("level_shot: viewport %dx%d (aspect %.2f), frame scale %.2f" % [
		int(vp_size.x), int(vp_size.y), vp_aspect, cover_scale])
	for view_name in _views:
		var spec: Array = VIEWS.get(view_name, VIEWS["overview"])
		rig.position = spec[0]
		cam.size = float(spec[1]) * cover_scale
		if String(view_name).begins_with("plan"):
			# straight-down orthographic debug view through the game's own camera
			cam.transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0, 0)), Vector3(0, 40, 0))
		else:
			cam.transform = base_cam_xform
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := "%s/%s_%s.png" % [_out_dir, _tag, view_name]
		img.save_png(path)
		print("level_shot: wrote ", path)

	quit(0)
