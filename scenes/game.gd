extends Node3D
## Let It Cook — REFORMED foundation (strategic heat-spread).
## - Houses: manual light (1 match) + deterministic heat-chain, 60-75s burn, refund 1.
## - Forest: same heat, faster (fuse). No dice anywhere.
## - Matches: start 6-7, +1/30s up to 12. Win on burn %.

const HOUSE_SCENE := preload("res://scenes/house.tscn")
const VILLAGER_SCENE := preload("res://scenes/villager.tscn")

const LEVELS := [
	{"name": "VILLAGE", "sub": "Lookouts + crews + demolitions", "grid_half": 4, "spacing": 4.2, "matches": 6, "win": 55.0, "villagers": 7, "demos": 3},
	{"name": "TOWN", "sub": "Denser streets", "grid_half": 5, "spacing": 4.0, "matches": 6, "win": 70.0, "villagers": 0, "demos": 0},
	{"name": "CITY", "sub": "Big cook", "grid_half": 6, "spacing": 3.8, "matches": 7, "win": 75.0, "villagers": 0, "demos": 0},
]

# Strategic heat-spread (deterministic, no dice):
# - UNBURNED buildings warm from each burning neighbor in radius.
# - house: 0.045/s per burner (~22s solo, ~11s with 2) | tree: 0.16/s (~6s)
# - decay 0.02/s with no burner nearby. Gaps > radius = natural firebreak.
const HOUSE_RADIUS := 4.7
const TREE_RADIUS := 4.5
const HOUSE_HEAT := 0.028
const TREE_HEAT := 0.13
# Grass fire heats walls poorly: tree->house counts half. Fuse carries,
# but town still needs your matches — the intended decision.
const HEAT_DECAY := 0.03
const MATCH_REGEN := 30.0
const MATCH_MAX := 12
# Wind (self-shifting, not controllable): biases heat by direction.
# weight = 1 + align * strength * WIND_BIAS, min 0.2. Downwind ~1.8x, upwind ~0.2x.
const BUCKET_MAX := 3
const BUCKET_RANGE := 4.5
const BUCKET_COOL := 0.5
const BUCKET_DRAIN := 2.0
const BUCKET_TICK := 1.0
const DEMO_COOLDOWN := 20.0
const WIND_BIAS := 0.8
const WIND_SHIFT_MIN := 22.0
const WIND_SHIFT_MAX := 34.0

var cfg: Dictionary = LEVELS[0]
var level_idx: int = 0

var houses: Array[VoxelHouse] = []
var matches: int = 5
var burn_percent: float = 0.0
var game_over: bool = false
var won: bool = false
var elapsed: float = 0.0
var cam_bound: float = 16.0
var edge_pan: bool = false
var match_tick: float = 0.0
var spotted: bool = false
var alarm: float = 0.0
var _alarm70_warned: bool = false
var demo_used: int = 0
var demo_max: int = 1
var demo_target: VoxelHouse = null
var demo_timer: float = 0.0
var demo_cooldown: float = 0.0
var splash_tick: float = 0.0
var _buckets_warned: bool = false
const DEMO_WARN := 15.0
var demo_marker: Label3D = null
var wind_dir: Vector3 = Vector3(1, 0, 0.3).normalized()
var wind_strength: float = 1.0
var _wind_target: Vector3 = Vector3(1, 0, 0.3).normalized()
var _wind_target_strength: float = 1.0
var _wind_timer: float = 25.0

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
	# Old sim widgets: FIRE bar + combo hidden. Wind label REUSED for self-shifting wind.
	if fire_bar != null:
		fire_bar.hide()
		var fl := get_node_or_null("HUD/TopBar/HBox/FireLabel") as Label
		if fl != null:
			fl.hide()
	if wind_label != null:
		wind_label.show()
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
	match_tick = 0.0
	burn_percent = 0.0
	spotted = false
	alarm = 0.0
	demo_cooldown = 0.0
	splash_tick = 0.0
	_buckets_warned = false
	_alarm70_warned = false
	demo_used = 0
	demo_max = int(cfg.get("demos", 0 if level_idx > 0 else 1))
	demo_target = null
	demo_timer = 0.0
	_clear_demo_marker()
	# Wind starts random, shifts on its own timer.
	var a0 := randf() * TAU
	wind_dir = Vector3(cos(a0), 0, sin(a0)).normalized()
	_wind_target = wind_dir
	wind_strength = randf_range(0.7, 1.1)
	_wind_target_strength = wind_strength
	_wind_timer = randf_range(WIND_SHIFT_MIN, WIND_SHIFT_MAX)
	cam_bound = float(cfg["grid_half"]) * float(cfg["spacing"]) + 4.0
	var cam_sizes := [19.0, 22.0, 25.0]
	camera.size = cam_sizes[clampi(level_idx, 0, 2)]
	rig.position = Vector3.ZERO
	_build_ground()
	_build_village()
	_spawn_villagers(int(cfg.get("villagers", 7 if level_idx == 0 else 0)))
	msg_panel.hide()
	pause_panel.hide()
	get_tree().paused = false
	_flash_hint("Click a house to light it — 1 match. Burnt houses refund 1.")
	_update_hud()


func _clear_level() -> void:
	_clear_demo_marker()
	demo_target = null
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
	# Dynamic slabs sized to cam_bound so bigger maps stay covered.
	var w := extent * 2.0 - 2.0
	match level_idx:
		0:
			_ground_slab(ground, Vector3(w, 1, w * 0.62), Color(0.42, 0.55, 0.28))
			_add_voxel_box(ground, Vector3(w * 0.94, 0.06, 3.4), Vector3(0, 0.03, -4.4), Color(0.55, 0.42, 0.28))
			_add_voxel_box(ground, Vector3(w * 0.94, 0.06, 3.4), Vector3(0, 0.03, 4.4), Color(0.55, 0.42, 0.28))
			_add_voxel_box(ground, Vector3(w, 0.08, 3.0), Vector3(0, 0.04, 0), Color(0.32, 0.3, 0.3))
		1:
			_ground_slab(ground, Vector3(w, 1, w), Color(0.30, 0.50, 0.28))
			_add_voxel_box(ground, Vector3(w, 0.08, 3.0), Vector3(0, 0.04, 0), Color(0.32, 0.3, 0.3))
			_add_voxel_box(ground, Vector3(3.0, 0.08, w), Vector3(0, 0.04, 0), Color(0.32, 0.3, 0.3))
		_:
			_ground_slab(ground, Vector3(w, 1, w), Color(0.36, 0.44, 0.32))
			_add_voxel_box(ground, Vector3(w, 0.08, 4.5), Vector3(0, 0.04, 0), Color(0.38, 0.36, 0.35))
			_add_voxel_box(ground, Vector3(4.5, 0.08, w), Vector3(0, 0.04, 0), Color(0.38, 0.36, 0.35))


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
	# Two settlements separated by a forest fuse belt (N-S strip at x~0).
	# Houses: manual-only. Forest: auto-spreads. This is the strategy map.
	var half: int = int(cfg["grid_half"])
	var spacing: float = float(cfg["spacing"])
	var wall_cols := [Color(0.92, 0.82, 0.66), Color(0.9, 0.72, 0.55), Color(0.95, 0.88, 0.72)]
	var roof_cols := [Color(0.78, 0.28, 0.16), Color(0.55, 0.2, 0.14), Color(0.35, 0.45, 0.7)]
	var idx := 0
	for gx in range(-half, half + 1):
		for gz in range(-half, half + 1):
			var px := float(gx) * spacing + randf_range(-0.2, 0.2)
			var pz := float(gz) * spacing + randf_range(-0.2, 0.2)
			# Middle strip = forest belt, no houses.
			if absf(float(gx) * spacing) < spacing * 0.9:
				continue
			if gx == 0 and gz == 0:
				continue
			if randf() < 0.2:
				continue
			_place_house(Vector3(px, 0, pz), "house", randf_range(55.0, 70.0), Vector3(randf_range(1.8, 2.2), randf_range(1.4, 1.8), randf_range(1.8, 2.2)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()])
			idx += 1
	# Forest fuse: dense N-S line + a couple of offshoots toward each hamlet.
	# 25s burn, chains on its own. Refund 0 — it's transport, not economy.
	var belt_half := float(half) * spacing
	var z := -belt_half
	while z <= belt_half:
		var jx := randf_range(-0.8, 0.8)
		_place_house(Vector3(jx, 0, z + randf_range(-0.5, 0.5)), "tree", 25.0, Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25))
		z += 2.8
	# Offshoots reaching toward settlements so fire can hop off the belt.
	for side in [-1.0, 1.0]:
		for k in 3:
			var ox: float = float(side) * (spacing * 0.9 + float(k) * 1.6)
			var oz: float = randf_range(-belt_half * 0.7, belt_half * 0.7)
			_place_house(Vector3(ox + randf_range(-0.4, 0.4), 0, oz), "tree", 25.0, Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25))
	# A few rim trees for silhouette.
	for i in 6:
		var ang := TAU * float(i) / 6.0
		var r := cam_bound * 0.85
		_place_house(Vector3(cos(ang) * r, 0, sin(ang) * r), "tree", 25.0, Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25))


# ---------- per-frame ----------
func _process(delta: float) -> void:
	_update_camera(delta)
	if game_over:
		return
	elapsed += delta
	RunState.run_time += delta
	RunState.level_time += delta
	# Match regen: slow income so stalls resolve, spam doesn't.
	if matches < MATCH_MAX:
		match_tick += delta
		if match_tick >= MATCH_REGEN:
			match_tick = 0.0
		matches = mini(matches + 1, MATCH_MAX)
	_update_wind(delta)
	_tick_heat(delta)
	_tick_alarm(delta)
	_tick_demo(delta)
	_tick_buckets(delta)
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
	# No hard lose: with regen a stall (0 matches + 0 burning) recovers.
	# Rain/shamans later can add real lose pressure.


func _spawn_villagers(n: int) -> void:
	for i in n:
		var v: VoxelVillager = VILLAGER_SCENE.instantiate()
		units_root.add_child(v)
		v.position = Vector3(randf_range(-cam_bound * 0.55, cam_bound * 0.55), 0, randf_range(-cam_bound * 0.55, cam_bound * 0.55))


func _tick_alarm(delta: float) -> void:
	# #5 Alarm escalation: unseen small fires barely register.
	# Once any lookout spots fire, alarm tracks burning size. Big fire = fast answer.
	for v in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(v) and v is VoxelVillager and (v as VoxelVillager).has_spotted():
			if not spotted:
				spotted = true
				_flash_hint("Spotted! Villagers see the smoke (eye). Stay small or go fast.")
			break
	var burning := 0
	for h in houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
			burning += 1
	var target := 0.0
	if spotted:
		target = clampf(20.0 + float(burning) * 15.0, 0.0, 100.0)
	else:
		target = clampf(float(burning) * 4.0, 0.0, 12.0)
	if target > alarm:
		alarm = minf(target, alarm + 8.0 * delta)
	else:
		alarm = maxf(target, alarm - 2.5 * delta)
	if alarm >= 70.0 and not _alarm70_warned:
		_alarm70_warned = true
		_flash_hint("Fully alert! The village will fight back (demolition).")


func _alarm_text() -> String:
	if not spotted:
		return "hidden"
	return "ALARM %d" % int(alarm)


func _pick_demo_target() -> VoxelHouse:
	var best: VoxelHouse = null
	for h in houses:
		if not is_instance_valid(h):
			continue
		if h.state != VoxelHouse.State.UNBURNED or h.kind != "house":
			continue
		if h.heat < 0.15:
			continue
		if best == null or h.heat > best.heat:
			best = h
	return best


func _tick_demo(delta: float) -> void:
	# #2 Demolition: telegraphed firebreaks on your hottest house-front (max 2, L1).
	# Counterplay: burn the marked house before the timer ends.
	if demo_cooldown > 0.0:
		demo_cooldown = maxf(0.0, demo_cooldown - delta)
	if level_idx != 0 and demo_max <= 0:
		return
	if demo_target != null and is_instance_valid(demo_target):
		if demo_target.state != VoxelHouse.State.UNBURNED:
			_flash_hint("Demolition stopped — already burning!")
			demo_used += 1
			demo_cooldown = DEMO_COOLDOWN
			demo_target = null
			_clear_demo_marker()
			return
		demo_timer -= delta
		_update_demo_marker()
		if demo_timer <= 0.0:
			if demo_target.demolish():
				_flash_hint("Demolished! Chain broken — go around.")
			demo_used += 1
			demo_cooldown = DEMO_COOLDOWN
			demo_target = null
			_clear_demo_marker()
		return
	elif demo_target != null:
		demo_target = null
		_clear_demo_marker()
	if demo_target != null or game_over:
		return
	if demo_used >= demo_max:
		return
	if demo_cooldown > 0.0:
		return
	if alarm < 30.0 or elapsed < 30.0:
		return
	var burning := 0
	for h in houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
			burning += 1
	if burning < 2:
		return
	var pick := _pick_demo_target()
	if pick == null:
		return
	demo_target = pick
	demo_timer = DEMO_WARN if alarm < 70.0 else 12.0
	_make_demo_marker()
	_flash_hint("Villagers will demolish a warming house! Burn it first!")


func _make_demo_marker() -> void:
	_clear_demo_marker()
	if demo_target == null or not is_instance_valid(demo_target):
		return
	var lab := Label3D.new()
	lab.text = "DEMOLISH!"
	lab.font_size = 96
	lab.pixel_size = 0.012
	lab.modulate = Color(1.0, 0.3, 0.2)
	lab.outline_size = 16
	lab.outline_modulate = Color(0, 0, 0)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position = Vector3(0, 3.4, 0)
	demo_target.add_child(lab)
	demo_marker = lab
	_update_demo_marker()


func _update_demo_marker() -> void:
	if demo_marker != null and is_instance_valid(demo_marker) and demo_target != null:
		demo_marker.text = "DEMOLISH %ds!" % int(ceil(demo_timer))


func _clear_demo_marker() -> void:
	if demo_marker != null and is_instance_valid(demo_marker):
		demo_marker.queue_free()
	demo_marker = null


func _bucket_count() -> int:
	var n := 0
	for v in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(v) and v is VoxelVillager and (v as VoxelVillager).is_bucket():
			n += 1
	return n


func _pick_bucket_target() -> VoxelHouse:
	# Front hub: burning house with the most warming (heat>0.05) unburnt neighbors.
	var best: VoxelHouse = null
	var best_score := -1
	for src in houses:
		if not is_instance_valid(src) or src.state != VoxelHouse.State.BURNING:
			continue
		var score := 0
		for dst in houses:
			if not is_instance_valid(dst) or dst.state != VoxelHouse.State.UNBURNED:
				continue
			if dst.heat < 0.05:
				continue
			if src.global_position.distance_to(dst.global_position) <= HOUSE_RADIUS + 1.0:
				score += 1
		if score > best_score:
			best_score = score
			best = src
	if best == null:
		for h in houses:
			if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
				return h
	return best


func _tick_buckets(delta: float) -> void:
	# Bucket crews: tiered unlocks so the opening always establishes.
	# 1 crew at alarm>=55 (75s grace), 2nd at 70, 3rd at 85 + 8 burning.
	# Splash every 1s: cool warming neighbors, drain the burner.
	# Counterplay: open more fronts than crews.
	var burning := 0
	for h in houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
			burning += 1
	var allowed := 0
	if alarm >= 55.0 and elapsed > 75.0 and burning >= 1:
		allowed = 1
	if alarm >= 70.0:
		allowed = 2
	if alarm >= 85.0 and burning >= 8:
		allowed = 3
	allowed = mini(allowed, BUCKET_MAX)
	if allowed > 0 and burning >= 1 and not game_over:
		var have := _bucket_count()
		if have < allowed:
			for v in get_tree().get_nodes_in_group("villagers"):
				if have >= allowed:
					break
				if is_instance_valid(v) and v is VoxelVillager and not (v as VoxelVillager).is_bucket():
					var tgt := _pick_bucket_target()
					if tgt == null:
						break
					(v as VoxelVillager).set_bucket(tgt)
					have += 1
					if not _buckets_warned:
						_buckets_warned = true
						_flash_hint("Bucket crews incoming! They cool chains — split fronts!")
	# Retarget dead assignments.
	for v in get_tree().get_nodes_in_group("villagers"):
		if not (is_instance_valid(v) and v is VoxelVillager and (v as VoxelVillager).is_bucket()):
			continue
		var vv := v as VoxelVillager
		if vv.bucket_target == null or not is_instance_valid(vv.bucket_target) or (vv.bucket_target as VoxelHouse).state != VoxelHouse.State.BURNING:
			var nt := _pick_bucket_target() if burning > 0 else null
			vv.bucket_target = nt
	# Splash tick.
	splash_tick += delta
	if splash_tick < BUCKET_TICK:
		return
	splash_tick = 0.0
	for v in get_tree().get_nodes_in_group("villagers"):
		if not (is_instance_valid(v) and v is VoxelVillager and (v as VoxelVillager).is_bucket()):
			continue
		var vv := v as VoxelVillager
		if vv.bucket_target == null or not is_instance_valid(vv.bucket_target):
			continue
		var tgt := vv.bucket_target as VoxelHouse
		if tgt.state != VoxelHouse.State.BURNING:
			continue
		if (vv as Node3D).global_position.distance_to(tgt.global_position) > BUCKET_RANGE + 1.0:
			continue
		# Cool every warming neighbor in range, drain the burner itself.
		for dst in houses:
			if not is_instance_valid(dst) or dst.state != VoxelHouse.State.UNBURNED:
				continue
			if (vv as Node3D).global_position.distance_to(dst.global_position) <= BUCKET_RANGE:
				dst.heat = maxf(0.0, dst.heat - BUCKET_COOL)
		tgt.fuel = maxf(0.0, tgt.fuel - BUCKET_DRAIN)
		vv._show_bubble("~", Color(0.4, 0.7, 1.0))


func _update_wind(delta: float) -> void:
	# Self-shifting: drift toward target, pick new target every 22-34s.
	_wind_timer -= delta
	if _wind_timer <= 0.0:
		_wind_timer = randf_range(WIND_SHIFT_MIN, WIND_SHIFT_MAX)
		var cur_ang := atan2(wind_dir.x, wind_dir.z)
		cur_ang += randf_range(-2.2, 2.2)
		_wind_target = Vector3(cos(cur_ang), 0, sin(cur_ang)).normalized()
		_wind_target_strength = randf_range(0.5, 1.4)
		_flash_hint("Wind shifting - check the arrow.")
	wind_dir = (wind_dir.lerp(_wind_target, minf(1.0, delta * 0.4))).normalized()
	wind_strength = lerpf(wind_strength, _wind_target_strength, minf(1.0, delta * 0.3))


func _tick_heat(delta: float) -> void:
	# Deterministic strategic spread, wind-biased. No randomness.
	# weight per burner = 1 + align(burner->dst, wind) * strength * BIAS (min 0.2).
	# Downwind ~1.8x, upwind ~0.2x. Gaps > radius = firebreak.
	var burning_nodes: Array[VoxelHouse] = []
	for h in houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
			burning_nodes.append(h)
	if burning_nodes.is_empty():
		for h in houses:
			if is_instance_valid(h) and h.state == VoxelHouse.State.UNBURNED and h.heat > 0.0:
				h.heat = maxf(0.0, h.heat - HEAT_DECAY * delta)
		return
	for dst in houses:
		if not is_instance_valid(dst) or dst.state != VoxelHouse.State.UNBURNED:
			continue
		var radius := TREE_RADIUS if dst.kind == "tree" else HOUSE_RADIUS
		var rate := TREE_HEAT if dst.kind == "tree" else HOUSE_HEAT
		var power := 0.0
		for src in burning_nodes:
			var to: Vector3 = dst.global_position - src.global_position
			var dist := to.length()
			if dist > radius or dist < 0.01:
				continue
			var align: float = (to / dist).dot(wind_dir)
			var w: float = maxf(0.2, 1.0 + align * wind_strength * WIND_BIAS)
			if dst.kind == "house" and src.kind == "tree":
				w *= 0.5
			power += w
			if power >= 2.5:
				break
		if power > 0.0:
			dst.heat = minf(1.0, dst.heat + rate * power * delta)
			if dst.heat >= 1.0:
				dst.ignite()
		elif dst.heat > 0.0:
			dst.heat = maxf(0.0, dst.heat - HEAT_DECAY * delta)


func _on_house_burned_out(h: VoxelHouse) -> void:
	if game_over:
		return
	# Houses refund the match (economy). Forest is transport: refund 0.
	if is_instance_valid(h) and h.kind == "house":
		matches = mini(matches + 1, MATCH_MAX)
		_flash_hint("House burnt! +1 match.")
	else:
		_flash_hint("Forest burnt through.")
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
		_flash_hint("No matches! Next free in %ds — or wait for a house to finish." % int(ceil(MATCH_REGEN - match_tick)))
		return
	if house.ignite():
		matches -= 1
		if house.kind == "tree":
			_flash_hint("Forest lit — heat will run down the belt.")
		else:
			_flash_hint("Lit — neighbors warm orange. Cluster for chains.")
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
		var regen_in := int(ceil(MATCH_REGEN - match_tick)) if matches < MATCH_MAX else 0
		if matches < MATCH_MAX:
			ember_label.text = "Matches: %d (+1 in %ds)" % [matches, regen_in]
		else:
			ember_label.text = "Matches: %d (full)" % matches
	if burn_label != null:
		burn_label.text = "Burnt %d%% / %d%%" % [int(burn_percent), int(float(cfg["win"]))]
	if wind_label != null:
		wind_label.text = "Wind %s %s" % [_wind_arrow(), _wind_word()]
	if objective_label != null and not game_over:
		var extra := ""
		var nb := _bucket_count()
		if nb > 0:
			extra += " · buckets:%d" % nb
		if demo_target != null and is_instance_valid(demo_target):
			objective_label.text = "Lv%d %s: BURN the marked house before demolition! (%s%s)" % [level_idx + 1, str(cfg["name"]), _alarm_text(), extra]
		else:
			objective_label.text = "Lv%d %s: burn %d%% — downwind chains fast (%s%s)" % [level_idx + 1, str(cfg["name"]), int(float(cfg["win"])), _alarm_text(), extra]
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


func _wind_arrow() -> String:
	var ang := atan2(wind_dir.x, -wind_dir.z)
	var idx := int(round(ang / (TAU / 8.0))) % 8
	if idx < 0:
		idx += 8
	var arrows := ["\u2191 N", "\u2197 NE", "\u2192 E", "\u2198 SE", "\u2193 S", "\u2199 SW", "\u2190 W", "\u2196 NW"]
	return arrows[idx]


func _wind_word() -> String:
	if wind_strength < 0.7:
		return "weak"
	if wind_strength < 1.1:
		return ""
	return "strong"


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
