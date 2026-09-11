extends Node3D
## Let It Cook — REFORMED foundation (fire-sim removed).
## Kept: click a house to light it (voxel burn visuals).
## Removed: combos, spread, explosions, wind/gusts, civilians on fire,
## firefighters, rain, heli, barrels, stone/fireproof, embers-mana,
## fire HP, waves, upgrades.
##
## New minimal loop (first-principles placeholder — easy to reskin):
## - You hold MATCHES. Lighting a house costs 1.
## - A burnt-out house refunds 1 match (arson economy, no auto-spread).
## - WIN: burn WIN% of buildings. LOSE: 0 matches + 0 burning.
## No timers forcing you, no RNG spread, no opposition — pure routing choice.

const HOUSE_SCENE := preload("res://scenes/house.tscn")

const LEVELS := [
	{"name": "VILLAGE", "sub": "Learn to burn", "grid_half": 3, "spacing": 4.6, "matches": 3, "win": 70.0},
	{"name": "TOWN", "sub": "Denser streets", "grid_half": 4, "spacing": 3.8, "matches": 3, "win": 75.0},
	{"name": "CITY", "sub": "Big cook", "grid_half": 5, "spacing": 3.5, "matches": 4, "win": 80.0},
]

var cfg: Dictionary = LEVELS[0]
var level_idx: int = 0

var houses: Array[VoxelHouse] = []
var matches: int = 3
var burn_percent: float = 0.0
var game_over: bool = false
var won: bool = false
var elapsed: float = 0.0
var cam_bound: float = 16.0
var edge_pan: bool = false

@onready var rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var village_root: Node3D = $Village
@onready var units_root: Node3D = $Units
# HUD: reuse existing nodes, hide the old-sim ones.
@onready var fire_bar: ProgressBar = %FireBar
@onready var ember_label: Label = %EmberLabel
@onready var burn_label: Label = %BurnLabel
@onready var wind_label: Label = %WindLabel
@onready var hint_label: Label = %HintLabel
@onready var objective_label: Label = %ObjectiveLabel
@onready var controls_label: Label = %ControlsLabel
@onready var combo_label: Label = %ComboLabel
@onready var toast_label: Label = %ToastLabel
@onready var msg_panel: PanelContainer = %MessagePanel
@onready var msg_label: Label = %MessageLabel
@onready var stats_label: Label = %StatsLabel
@onready var restart_button: Button = %RestartButton
@onready var menu_button: Button = %MenuButton
@onready var pause_panel: PanelContainer = %PausePanel
@onready var resume_button: Button = %ResumeButton
@onready var pause_menu_button: Button = %PauseMenuButton


func _ready() -> void:
	randomize()
	level_idx = clampi(RunState.level, 0, 2)
	cfg = LEVELS[level_idx]
	edge_pan = RunState.edge_pan
	msg_panel.hide()
	pause_panel.hide()
	_hide_legacy_hud()
	if not restart_button.pressed.is_connected(_on_restart):
		restart_button.pressed.connect(_on_restart)
	if not menu_button.pressed.is_connected(_on_menu):
		menu_button.pressed.connect(_on_menu)
	if not resume_button.pressed.is_connected(_toggle_pause):
		resume_button.pressed.connect(_toggle_pause)
	if not pause_menu_button.pressed.is_connected(_on_menu):
		pause_menu_button.pressed.connect(_on_menu)
	# Old upgrade panel: hide forever (no upgrades in reformed loop).
	var up := get_node_or_null("HUD/UpgradePanel") as PanelContainer
	if up != null:
		up.hide()
	_load_level()


func _hide_legacy_hud() -> void:
	# Old sim widgets: FIRE bar, wind, combo. Keep nodes (tscn stable), hide them.
	if fire_bar != null:
		fire_bar.hide()
		var fl := get_node_or_null("HUD/TopBar/HBox/FireLabel") as Label
		if fl != null:
			fl.hide()
	if wind_label != null:
		wind_label.hide()
	if combo_label != null:
		combo_label.hide()
	# Clean any ember-pip row the old build may have left in a hot-reload.
	var pips := get_node_or_null("HUD/TopBar/HBox/EmberPips")
	if pips != null:
		pips.queue_free()


func _load_level() -> void:
	_clear_level()
	game_over = false
	won = false
	elapsed = 0.0
	RunState.level_time = 0.0
	matches = int(cfg["matches"])
	burn_percent = 0.0
	cam_bound = float(cfg["grid_half"]) * float(cfg["spacing"]) + 4.0
	var cam_sizes := [19.0, 22.0, 25.0]
	camera.size = cam_sizes[clampi(level_idx, 0, 2)]
	rig.position = Vector3.ZERO
	_build_ground()
	_build_village()
	msg_panel.hide()
	pause_panel.hide()
	get_tree().paused = false
	_flash_hint("Click a house to light it — 1 match. Burnt houses refund 1.")
	_update_hud()


func _clear_level() -> void:
	for c in village_root.get_children():
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			c.queue_free()
	for c in units_root.get_children():
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			c.queue_free()
	houses.clear()


# ---------- builders ----------
func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return m


func _add_voxel_box(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = _mat(col)
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)
	return mi


func _ground_slab(parent: Node3D, size: Vector3, col: Color) -> void:
	_add_voxel_box(parent, size, Vector3(0, -0.5, 0), col)


func _build_ground() -> void:
	var extent: float = cam_bound + 2.0
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	village_root.add_child(ground)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(extent * 2.0, 1, extent * 2.0)
	col.shape = shape
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)
	match level_idx:
		0:
			_ground_slab(ground, Vector3(36, 1, 22), Color(0.42, 0.55, 0.28))
			_add_voxel_box(ground, Vector3(34, 0.06, 3.4), Vector3(0, 0.03, -4.4), Color(0.55, 0.42, 0.28))
			_add_voxel_box(ground, Vector3(34, 0.06, 3.4), Vector3(0, 0.03, 4.4), Color(0.55, 0.42, 0.28))
			_add_voxel_box(ground, Vector3(36, 0.08, 3.0), Vector3(0, 0.04, 0), Color(0.32, 0.3, 0.3))
		1:
			_ground_slab(ground, Vector3(32, 1, 32), Color(0.30, 0.50, 0.28))
			_add_voxel_box(ground, Vector3(32, 0.08, 3.0), Vector3(0, 0.04, 0), Color(0.32, 0.3, 0.3))
			_add_voxel_box(ground, Vector3(3.0, 0.08, 32), Vector3(0, 0.04, 0), Color(0.32, 0.3, 0.3))
		_:
			_ground_slab(ground, Vector3(40, 1, 40), Color(0.36, 0.44, 0.32))
			_add_voxel_box(ground, Vector3(40, 0.08, 4.5), Vector3(0, 0.04, 0), Color(0.38, 0.36, 0.35))
			_add_voxel_box(ground, Vector3(4.5, 0.08, 40), Vector3(0, 0.04, 0), Color(0.38, 0.36, 0.35))


func _place_house(pos: Vector3, kind: String, fuel: float, size: Vector3, c1: Color, c2: Color) -> VoxelHouse:
	var h: VoxelHouse = HOUSE_SCENE.instantiate()
	village_root.add_child(h)
	h.position = pos
	if kind == "house":
		h.rotation.y = [0.0, PI * 0.5, PI, -PI * 0.5][randi() % 4]
	h.setup(c1, c2, fuel, size, kind)
	h.burned_out.connect(_on_house_burned_out)
	houses.append(h)
	return h


func _build_village() -> void:
	# Simple grid hamlet/town/city. Houses + a few trees. All burn the same way.
	var half: int = int(cfg["grid_half"])
	var spacing: float = float(cfg["spacing"])
	var wall_cols := [Color(0.92, 0.82, 0.66), Color(0.9, 0.72, 0.55), Color(0.95, 0.88, 0.72)]
	var roof_cols := [Color(0.78, 0.28, 0.16), Color(0.55, 0.2, 0.14), Color(0.35, 0.45, 0.7)]
	var idx := 0
	for gx in range(-half, half + 1):
		for gz in range(-half, half + 1):
			if gx == 0 and gz == 0:
				continue # plaza gap
			if randf() < 0.12:
				continue
			var px := float(gx) * spacing + randf_range(-0.2, 0.2)
			var pz := float(gz) * spacing + randf_range(-0.2, 0.2)
			_place_house(Vector3(px, 0, pz), "house", randf_range(20.0, 26.0), Vector3(randf_range(1.8, 2.2), randf_range(1.4, 1.8), randf_range(1.8, 2.2)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()])
			idx += 1
	# A few trees on the rim for variety (same rules, shorter burn).
	for i in 6:
		var ang := TAU * float(i) / 6.0
		var r := cam_bound * 0.8
		_place_house(Vector3(cos(ang) * r, 0, sin(ang) * r), "tree", randf_range(12.0, 16.0), Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25))


# ---------- per-frame ----------
func _process(delta: float) -> void:
	_update_camera(delta)
	if game_over:
		return
	elapsed += delta
	RunState.run_time += delta
	RunState.level_time += delta
	# Burn % from actual states.
	var burnt := 0
	var burning := 0
	for h in houses:
		if is_instance_valid(h):
			if h.state == VoxelHouse.State.BURNT:
				burnt += 1
			elif h.state == VoxelHouse.State.BURNING:
				burning += 1
	burn_percent = 100.0 * float(burnt) / float(maxi(1, houses.size()))
	_update_hud()
	var win := float(cfg["win"])
	if burn_percent >= win:
		_end_game(true)
	elif matches <= 0 and burning == 0:
		# No way to light anything and nothing left cooking: stuck.
		# Only lose once at least one house has burnt (else it's just the opening).
		if burnt > 0:
			_end_game(false)


func _on_house_burned_out(_h: VoxelHouse) -> void:
	if game_over:
		return
	# The one economy rule: a finished burn refunds the match you spent.
	matches += 1
	_flash_hint("Burnt! +1 match refunded.")
	_update_hud()


# ---------- camera ----------
func _update_camera(delta: float) -> void:
	var pan := Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		pan.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		pan.x += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		pan.y -= 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		pan.y += 1.0
	if pan != Vector2.ZERO:
		var fwd := -camera.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := camera.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		rig.position += (right * pan.x + -fwd * pan.y) * delta * 14.0
		rig.position.x = clampf(rig.position.x, -cam_bound, cam_bound)
		rig.position.z = clampf(rig.position.z, -cam_bound, cam_bound)
	if Input.is_key_pressed(KEY_Q):
		_zoom_step(-8.0 * delta)
	if Input.is_key_pressed(KEY_E):
		_zoom_step(8.0 * delta)
	if edge_pan:
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport().get_visible_rect().size
		var edge := 12.0
		var ep := Vector2.ZERO
		if mp.x < edge:
			ep.x -= 1.0
		elif mp.x > vs.x - edge:
			ep.x += 1.0
		if mp.y < edge:
			ep.y -= 1.0
		elif mp.y > vs.y - edge:
			ep.y += 1.0
		if ep != Vector2.ZERO:
			rig.position += Vector3(ep.x, 0, ep.y) * delta * 12.0
			rig.position.x = clampf(rig.position.x, -cam_bound, cam_bound)
			rig.position.z = clampf(rig.position.z, -cam_bound, cam_bound)


func _zoom_step(amount: float) -> void:
	camera.size = clampf(camera.size + amount, 8.0, 40.0)


# ---------- input: click = ignite. No drag, no gust. ----------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_P:
			_toggle_pause()
			return
	if game_over or get_tree().paused:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_step(-2.0)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_step(2.0)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_try_ignite_at(mb.position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if not st.pressed:
			_try_ignite_at(st.position)


func _try_ignite_at(screen_pos: Vector2) -> void:
	var house := _pick_house(screen_pos)
	if house == null:
		return
	if house.state != VoxelHouse.State.UNBURNED:
		return
	if matches <= 0:
		_flash_hint("No matches! Wait for a burn to finish (+1).")
		return
	if house.ignite():
		matches -= 1
		_update_hud()


func _pick_house(screen_pos: Vector2) -> VoxelHouse:
	if camera == null:
		return null
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 200.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 2
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var collider: Object = hit.get("collider")
	if collider is VoxelHouse:
		return collider
	return null


# ---------- HUD ----------
var _hint_t: float = 0.0
var _toast_t: float = 0.0


func _flash_hint(text: String) -> void:
	if hint_label == null:
		return
	hint_label.text = text
	hint_label.modulate.a = 1.0
	_hint_t = 2.5


func _update_hud() -> void:
	if ember_label != null:
		ember_label.text = "Matches: %d" % matches
	if burn_label != null:
		burn_label.text = "Burnt %d%% / %d%%" % [int(burn_percent), int(float(cfg["win"]))]
	if objective_label != null and not game_over:
		objective_label.text = "Lv%d %s: burn %d%% — click a house (1 match, refunded when burnt)" % [level_idx + 1, str(cfg["name"]), int(float(cfg["win"]))]
	if controls_label != null:
		controls_label.text = "WASD/arrows pan | Q/E/wheel zoom | Click burn | P pause"
	# Fade hint/toast.
	if _hint_t > 0.0:
		_hint_t -= get_process_delta_time()
		if _hint_t <= 0.0 and hint_label != null:
			hint_label.modulate.a = 0.35
	if _toast_t > 0.0:
		_toast_t -= get_process_delta_time()
		if _toast_t <= 0.0 and toast_label != null:
			toast_label.modulate.a = 0.0


# ---------- pause / end ----------
func _toggle_pause() -> void:
	if game_over:
		return
	get_tree().paused = not get_tree().paused
	pause_panel.visible = get_tree().paused
	if get_tree().paused:
		resume_button.grab_focus()


func _end_game(did_win: bool) -> void:
	game_over = true
	won = did_win
	msg_panel.show()
	if did_win:
		RunState.unlocked = mini(2, maxi(RunState.unlocked, level_idx + 1))
		if level_idx < 2:
			msg_label.text = "%s COOKED! Burnt %d%%.\nNext district unlocked." % [str(cfg["name"]), int(burn_percent)]
			stats_label.text = "Time: %ds | Matches left: %d\nPress Cook Again for Lv%d." % [int(RunState.level_time), matches, level_idx + 2]
			restart_button.text = "Cook Lv%d" % [level_idx + 2]
		else:
			msg_label.text = "CITY COOKED! YOU WIN THE RUN!\nAll three districts burnt."
			stats_label.text = "Run time: %ds" % int(RunState.run_time)
			restart_button.text = "Cook Again (L1)"
	else:
		msg_label.text = "Out of matches... the fire went cold.\n%s: burnt only %d%% of %d%%." % [str(cfg["name"]), int(burn_percent), int(float(cfg["win"]))]
		stats_label.text = "Time: %ds | Try a different order." % int(RunState.level_time)
		restart_button.text = "Retry Level %d" % [level_idx + 1]
	restart_button.grab_focus()


func _on_restart() -> void:
	get_tree().paused = false
	if won and level_idx < 2:
		RunState.level = level_idx + 1
		level_idx = RunState.level
		cfg = LEVELS[level_idx]
		_load_level()
		return
	RunState.level = level_idx
	_load_level()


func _on_menu() -> void:
	get_tree().paused = false
	RunState.level = level_idx
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
