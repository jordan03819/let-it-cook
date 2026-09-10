extends Node3D
## Let It Cook - voxel reverse-firefighting manager.
## Data-driven 3-level campaign: Village (tutorial) -> Town (barrels + rain)
## -> City (firebreaks + heli + elites), with upgrade picks between levels.
## You are the Ember Spirit: click to ignite, drag to gust, keep fire alive.

static var _streak_mesh: BoxMesh = null
static var _streak_mat: StandardMaterial3D = null

const HOUSE_SCENE := preload("res://scenes/house.tscn")
const FIREFIGHTER_SCENE := preload("res://scenes/firefighter.tscn")
const VILLAGER_SCENE := preload("res://scenes/villager.tscn")

const LEVELS := [
	{
		"name": "VILLAGE", "sub": "Tutorial grounds",
		"grid_half": 3, "spacing": 4.2, "empty": 0.15, "trees": 8,
		"villagers": 5, "embers": 3, "win": 70.0,
		"drain": 3.6, "gain": 1.8, "ff_interval": 20.0, "ff_speed": 0.9,
		"wind_min": 0.7, "wind_max": 1.3, "rain": false, "barrels": 0,
		"stone": false, "heli": false, "elite_chance": 0.0,
	},
	{
		"name": "TOWN", "sub": "Gas barrels + rain showers",
		"grid_half": 4, "spacing": 3.6, "empty": 0.08, "trees": 12,
		"villagers": 8, "embers": 3, "win": 75.0,
		"drain": 4.2, "gain": 1.7, "ff_interval": 16.0, "ff_speed": 1.0,
		"wind_min": 0.7, "wind_max": 1.3, "rain": true, "barrels": 4,
		"stone": false, "heli": false, "elite_chance": 0.0,
	},
	{
		"name": "CITY", "sub": "Firebreaks + water heli + elites",
		"grid_half": 5, "spacing": 3.4, "empty": 0.08, "trees": 14,
		"villagers": 10, "embers": 4, "win": 80.0,
		"drain": 4.8, "gain": 1.6, "ff_interval": 13.0, "ff_speed": 1.05,
		"wind_min": 0.7, "wind_max": 1.4, "rain": false, "barrels": 3,
		"stone": true, "heli": true, "elite_chance": 0.25,
	},
]

var cfg: Dictionary = LEVELS[0]
var level_idx: int = 0

# Fire state / balance
var fire_hp_max: float = 100.0
var fire_hp: float = 65.0
var fire_drain: float = 3.6
var fire_gain_per_house: float = 1.8
var win_percent: float = 70.0
var embers: int = 3
var ember_max: int = 5
var ember_tick: float = 0.0
var ember_floor_cd: float = 0.0
var toast_cd: float = 0.0
var pity_t: float = 0.0
var burn_percent: float = 0.0
var spread_mult: float = 1.0
var last_stand_cd: float = 0.0
var barrel_bonus: int = 0
var barrel_queue: Array = []

# Wind
var wind_dir: Vector3 = Vector3(1, 0, 0.3).normalized()
var wind_strength: float = 1.0
var wind_timer: float = 0.0
var wind_flash: float = 0.0
var wind_baseline: float = 1.0

# Flow
var houses: Array[VoxelHouse] = []
var game_over: bool = false
var won: bool = false
var elapsed: float = 0.0
var dead_fire_timer: float = 0.0
var no_flame_warned: bool = false
var spread_timer: float = 1.2
var ff_timer: float = 6.0
var ff_interval: float = 20.0
# Fire-crew waves: CALM (breathe) -> WARNING -> ASSAULT -> STAND DOWN.
var wave_phase: int = 0
var wave_timer: float = 60.0
var assault_tick: float = 0.0
var mana_tick: float = 0.0
var cam_bound: float = 16.0
var tutorial_t: float = 0.0
var tutorial_stage: int = 0
# Slow start: nothing burns until the player lights the first house.
var has_started: bool = false
var starter_houses: Array[VoxelHouse] = []
var starter_markers: Array[Node3D] = []

# Juice / announcements
var combo_count: int = 0
var combo_timer: float = 0.0
var peak_combo: int = 0
var max_burning: int = 0
var shake: float = 0.0
var combo_left: float = 0.0
var toast_queue: Array = []
var toast_left: float = 0.0
var hint_t: float = 0.0
var controls_t: float = 0.0
var warn_cd: float = 0.0
var gust_pulse: float = 0.0
var phase_flags := {"p30": false, "p50": false, "pStorm": false}

# Stats
var toasted: int = 0
var torched: int = 0
var scared: int = 0
var scared_tick: float = 0.0

# Rain (L2) with latch
var rain_phase: int = 0 # 0 idle, 1 warning, 2 active
var rain_armed: bool = false
var rain_warned: bool = false
var rain_timer: float = 18.0
var rain_particles: GPUParticles3D = null

# Heli (L3) with latch
var heli_timer: float = 14.0
var heli_armed: bool = false
var heli_warned: bool = false
var heli_phase: int = 0
var helis: Array = []

# Camera
var edge_pan: bool = false

@onready var rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var village_root: Node3D = $Village
@onready var units_root: Node3D = $Units
@onready var crackle: AudioStreamPlayer = $CracklePlayer
@onready var sfx: AudioStreamPlayer = $SfxPlayer
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
@onready var upgrade_panel: PanelContainer = %UpgradePanel
@onready var up_crispy: Button = %UpCrispy
@onready var up_grease: Button = %UpGrease
@onready var up_aura: Button = %UpAura

var wind_arrow: Node3D = null
var wind_arrow_body: Node3D = null
var drift_particles: GPUParticles3D = null
var _fill_style: StyleBoxFlat = null
var _win_marker: ColorRect = null
var _ember_pips: Array = []
var _ember_extra: Label = null

var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO
var _gust_cd: float = 0.0

# Audio rescope (Task 12)
var audio_muted: bool = false
var music_low: AudioStreamPlayer = null
var music_hat: AudioStreamPlayer = null
var sfx_voices: Array[AudioStreamPlayer] = []
var sfx_idx: int = 0
var sfx_cd := {}
var sfx_ignite: AudioStreamWAV = null
var sfx_boom: AudioStreamWAV = null
var sfx_hiss: AudioStreamWAV = null
var barrel_tick_t: float = 0.0


func _ready() -> void:
	randomize()
	add_to_group("game")
	edge_pan = RunState.edge_pan
	level_idx = clampi(RunState.level, 0, 2)
	cfg = LEVELS[level_idx]
	_build_audio()
	_build_wind_fx()
	_build_rain_fx()
	msg_panel.hide()
	pause_panel.hide()
	upgrade_panel.hide()
	if not restart_button.pressed.is_connected(_on_restart):
		restart_button.pressed.connect(_on_restart)
	if not menu_button.pressed.is_connected(_on_menu):
		menu_button.pressed.connect(_on_menu)
	if not resume_button.pressed.is_connected(_toggle_pause):
		resume_button.pressed.connect(_toggle_pause)
	if not pause_menu_button.pressed.is_connected(_on_menu):
		pause_menu_button.pressed.connect(_on_menu)
	if not up_crispy.pressed.is_connected(_on_upgrade.bind("crispy")):
		up_crispy.pressed.connect(_on_upgrade.bind("crispy"))
	if not up_grease.pressed.is_connected(_on_upgrade.bind("grease")):
		up_grease.pressed.connect(_on_upgrade.bind("grease"))
	if not up_aura.pressed.is_connected(_on_upgrade.bind("aura")):
		up_aura.pressed.connect(_on_upgrade.bind("aura"))
	_setup_hud_extras()
	_load_level()


func _setup_hud_extras() -> void:
	# Duplicate fill style once (never mutate the shared FireFill).
	if fire_bar != null:
		var sb := fire_bar.get_theme_stylebox("fill")
		if sb is StyleBoxFlat:
			_fill_style = (sb as StyleBoxFlat).duplicate()
			fire_bar.add_theme_stylebox_override("fill", _fill_style)
		# Threshold marker: child of FireBar, thin 2px line at win%.
		if _win_marker == null:
			_win_marker = ColorRect.new()
			_win_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_win_marker.color = Color(1.0, 0.84, 0.2, 1.0)
			fire_bar.add_child(_win_marker)
			_win_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
		_update_win_marker()
		# Ember pips: 6 max-visible TextureRects + numeric +N label.
		var hbox := get_node_or_null("HUD/TopBar/HBox")
		if hbox != null and _ember_pips.is_empty():
			var pip_row := HBoxContainer.new()
			pip_row.name = "EmberPips"
			pip_row.add_theme_constant_override("separation", 2)
			hbox.add_child(pip_row)
			hbox.move_child(pip_row, 2)
			for i in 6:
				var pip := TextureRect.new()
				pip.custom_minimum_size = Vector2(18, 18)
				pip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				pip.texture = load("res://assets/pixel_fire.png")
				pip_row.add_child(pip)
				_ember_pips.append(pip)
			_ember_extra = Label.new()
			_ember_extra.add_theme_font_size_override("font_size", 16)
			_ember_extra.text = ""
			pip_row.add_child(_ember_extra)
	if burn_label != null:
		burn_label.add_theme_font_size_override("font_size", 18)
	if wind_label != null:
		wind_label.add_theme_font_size_override("font_size", 16)
	if combo_label != null:
		combo_label.add_theme_font_size_override("font_size", 28)
	if pause_panel != null:
		var vbox := pause_panel.get_node_or_null("VBox")
		if vbox != null and vbox.get_node_or_null("EdgePanCheck") == null:
			var cb := CheckBox.new()
			cb.name = "EdgePanCheck"
			cb.text = "Edge pan"
			cb.button_pressed = edge_pan
			cb.toggled.connect(_on_edge_pan_toggled)
			vbox.add_child(cb)


func _on_edge_pan_toggled(v: bool) -> void:
	edge_pan = v
	RunState.edge_pan = v


func _update_win_marker() -> void:
	if _win_marker == null or fire_bar == null:
		return
	var f := clampf(win_percent / 100.0, 0.0, 1.0)
	_win_marker.anchor_left = f
	_win_marker.anchor_right = f
	_win_marker.offset_left = -1.0
	_win_marker.offset_right = 1.0
	_win_marker.offset_top = 2.0
	_win_marker.offset_bottom = -2.0


func _load_level() -> void:
	_clear_level()
	game_over = false
	won = false
	elapsed = 0.0
	RunState.level_time = 0.0
	dead_fire_timer = 0.0
	no_flame_warned = false
	spread_timer = 1.2
	spread_mult = 1.0
	last_stand_cd = 0.0
	barrel_bonus = 0
	barrel_queue.clear()
	ember_tick = 0.0
	ember_floor_cd = 0.0
	toast_cd = 0.0
	pity_t = 0.0
	tutorial_t = 0.0
	tutorial_stage = 0
	combo_count = 0
	combo_timer = 0.0
	peak_combo = 0
	max_burning = 0
	toasted = 0
	torched = 0
	scared = 0
	rain_phase = 0
	rain_armed = false
	rain_warned = false
	rain_timer = randf_range(30.0, 40.0)
	heli_timer = randf_range(22.0, 30.0)
	heli_armed = false
	heli_warned = false
	heli_phase = 0
	phase_flags = {"p30": false, "p50": false, "pStorm": false}
	# Balance from data + upgrades (Task 1 exact start block).
	fire_hp_max = 100.0
	fire_hp = 65.0
	fire_drain = float(cfg["drain"])
	fire_gain_per_house = float(cfg["gain"])
	win_percent = float(cfg["win"])
	ember_max = 5 + (2 if RunState.up_grease else 0)
	embers = int(cfg["embers"])
	ff_interval = float(cfg["ff_interval"])
	spread_timer = 1.2
	# Slow start: cold village, long grace so player can read the scene.
	has_started = false
	starter_houses.clear()
	_clear_starter_markers()
	ff_timer = ff_interval + (15.0 if level_idx == 0 else 8.0)
	# Open in a long CALM so the level breathes before the first assault.
	wave_phase = 0
	wave_timer = ff_timer + (30.0 if level_idx == 0 else 15.0)
	assault_tick = 0.0
	mana_tick = 0.0
	wind_baseline = lerpf(float(cfg["wind_min"]), float(cfg["wind_max"]), 0.5)
	wind_strength = wind_baseline
	cam_bound = float(cfg["grid_half"]) * float(cfg["spacing"]) + 4.0
	var cam_sizes := [19.0, 22.0, 25.0]
	camera.size = cam_sizes[clampi(level_idx, 0, 2)]
	rig.position = Vector3.ZERO
	_update_win_marker()
	# L3 CITY: fog off via code.
	var wenv := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if wenv != null and wenv.environment != null:
		if str(cfg["name"]) == "CITY":
			wenv.environment.fog_enabled = false
		else:
			wenv.environment.fog_enabled = true
			wenv.environment.fog_density = 0.005
	_build_ground()
	_build_village()
	_build_decor()
	_build_barrels()
	_spawn_villagers(int(cfg["villagers"]))
	msg_panel.hide()
	pause_panel.hide()
	upgrade_panel.hide()
	get_tree().paused = false
	_queue_intro_toasts()
	_setup_starter()
	_update_hud()


func _clear_level() -> void:
	_clear_starter_markers()
	for c in village_root.get_children():
		if c.name == "WindArrow":
			continue
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			c.queue_free()
	for c in units_root.get_children():
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			c.queue_free()
	for h in helis.duplicate():
		if h is Dictionary:
			var hn: Variant = (h as Dictionary).get("node")
			if hn is Node and is_instance_valid(hn):
				(hn as Node).queue_free()
	helis.clear()
	houses.clear()
	target_cleanup()


func target_cleanup() -> void:
	pass


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


func _water_box(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.5, 0.88)
	m.roughness = 0.35
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)


func _ground_slab(parent: Node3D, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(col)
	mi.mesh = bm
	mi.position = Vector3(0, -0.5, 0)
	parent.add_child(mi)


func _build_ground() -> void:
	# Deliberately different footprints so levels don't read as one square:
	# L0 wide hamlet bar, L1 square town with west canal + park pond,
	# L2 big urban slab with wide roads, grand plaza + corner courts.
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
			# Dirt strips under the two house rows.
			_add_voxel_box(ground, Vector3(34, 0.06, 3.4), Vector3(0, 0.03, -4.4), Color(0.55, 0.42, 0.28))
			_add_voxel_box(ground, Vector3(34, 0.06, 3.4), Vector3(0, 0.03, 4.4), Color(0.55, 0.42, 0.28))
			_add_voxel_box(ground, Vector3(36, 0.08, 3.0), Vector3(0, 0.04, 0), Color(0.32, 0.3, 0.3))
			_add_voxel_box(ground, Vector3(4, 0.1, 4), Vector3(0, 0.05, 0), Color(0.72, 0.68, 0.60))
		1:
			_ground_slab(ground, Vector3(32, 1, 32), Color(0.30, 0.50, 0.28))
			_add_voxel_box(ground, Vector3(32, 0.08, 3.0), Vector3(0, 0.04, 0), Color(0.32, 0.3, 0.3))
			_add_voxel_box(ground, Vector3(3.0, 0.08, 32), Vector3(0, 0.04, 0), Color(0.32, 0.3, 0.3))
			_add_voxel_box(ground, Vector3(5, 0.1, 5), Vector3(0, 0.05, 0), Color(0.72, 0.68, 0.60))
			# South canal + park pond: ankle-deep blue strips (safe color,
			# breaks the square; walk-through reads as wading).
			_water_box(ground, Vector3(30, 0.08, 2.2), Vector3(0, 0.05, 14.5))
			_water_box(ground, Vector3(3.2, 0.08, 3.2), Vector3(-7.0, 0.05, 7.0))
		_:
			_ground_slab(ground, Vector3(40, 1, 40), Color(0.36, 0.44, 0.32))
			_add_voxel_box(ground, Vector3(40, 0.08, 4.5), Vector3(0, 0.04, 0), Color(0.38, 0.36, 0.35))
			_add_voxel_box(ground, Vector3(4.5, 0.08, 40), Vector3(0, 0.04, 0), Color(0.38, 0.36, 0.35))
			_add_voxel_box(ground, Vector3(7, 0.1, 7), Vector3(0, 0.05, 0), Color(0.62, 0.60, 0.57))
			# Corner stone courts.
			for cx in [-1.0, 1.0]:
				for cz in [-1.0, 1.0]:
					_add_voxel_box(ground, Vector3(5, 0.09, 5), Vector3(cx * 15.5, 0.045, cz * 15.5), Color(0.55, 0.53, 0.50))


func _place_prop(pos: Vector3, kind: String, fuel: float, size: Vector3, c1: Color, c2: Color, fireproof: bool = false) -> VoxelHouse:
	var h: VoxelHouse = HOUSE_SCENE.instantiate()
	village_root.add_child(h)
	h.position = pos
	if kind == "house" or kind == "stone":
		h.rotation.y = [0.0, PI * 0.5, PI, -PI * 0.5][randi() % 4]
	h.setup(c1, c2, fuel, size, kind)
	h.fireproof = fireproof
	if RunState.up_crispy and kind != "barrel":
		h.burn_rate_mult = 1.25
	h.burned_out.connect(_on_house_burned_out)
	h.ignited.connect(_on_house_ignited)
	houses.append(h)
	return h


func _build_village() -> void:
	match level_idx:
		0:
			_build_village_hamlet()
		1:
			_build_village_town()
		_:
			_build_village_city()
	_build_fire_station(Vector3(-cam_bound + 2.0, 0, -cam_bound + 2.0))


func _build_village_hamlet() -> void:
	# L0 Hamlet: one street, scattered farmhouses, grove to the east.
	var wall_cols := [Color(0.92, 0.82, 0.66), Color(0.9, 0.72, 0.55), Color(0.95, 0.88, 0.72)]
	var roof_cols := [Color(0.78, 0.28, 0.16), Color(0.55, 0.2, 0.14), Color(0.6, 0.35, 0.15)]
	var idx := 0
	for gx in range(-3, 4):
		var px := float(gx) * 4.6
		if absf(px) < 2.4:
			continue # plaza gap
		for side in [-1.0, 1.0]:
			if randf() < 0.25:
				continue
			_place_prop(Vector3(px, 0, side * 4.4 + randf_range(-0.3, 0.3)), "house", randf_range(30.0, 40.0), Vector3(randf_range(1.8, 2.3), randf_range(1.4, 1.9), randf_range(1.8, 2.3)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()])
			idx += 1
	# Farmhouse north + grove east (distinct cluster, not grid).
	_place_prop(Vector3(-6.5, 0, -8.5), "house", 36.0, Vector3(2.2, 1.8, 2.2), wall_cols[0], roof_cols[0])
	for i in 5:
		var a := -0.5 + float(i) * 0.25
		_place_prop(Vector3(10.5 + randf_range(-1, 1), 0, -6.0 + a * 8.0), "tree", randf_range(10.0, 14.0), Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25))


func _build_village_town() -> void:
	# L1 Town: 4 dense blocks around a cross, park quadrant SW, alley gaps.
	var wall_cols := [Color(0.92, 0.82, 0.66), Color(0.9, 0.72, 0.55), Color(0.82, 0.78, 0.7), Color(0.95, 0.88, 0.72)]
	var roof_cols := [Color(0.78, 0.28, 0.16), Color(0.55, 0.2, 0.14), Color(0.35, 0.45, 0.7), Color(0.6, 0.35, 0.15)]
	var idx := 0
	for bx in [-1.0, 1.0]:
		for bz in [-1.0, 1.0]:
			if bx < 0.0 and bz > 0.0:
				continue # SW = park, not blocks
			var cx: float = bx * 7.0
			var cz: float = bz * 7.0
			for ox in [-1.6, 1.6]:
				for oz in [-1.6, 1.6]:
					if randf() < float(cfg["empty"]):
						continue
					_place_prop(Vector3(cx + ox, 0, cz + oz), "house", randf_range(30.0, 40.0), Vector3(1.9, 1.6, 1.9), wall_cols[idx % wall_cols.size()], roof_cols[(idx * 2 + 1) % roof_cols.size()])
					idx += 1
	# Park: ring of trees SW.
	for i in 7:
		var ang := TAU * float(i) / 7.0
		_place_prop(Vector3(-7.0 + cos(ang) * 2.6, 0, 7.0 + sin(ang) * 2.6), "tree", randf_range(10.0, 14.0), Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25))


func _build_village_city() -> void:
	# L2 City: stone inner ring (firebreak wall with 4 gates) + wooden outer ring.
	var wall_cols := [Color(0.92, 0.82, 0.66), Color(0.9, 0.72, 0.55), Color(0.82, 0.78, 0.7)]
	var roof_cols := [Color(0.78, 0.28, 0.16), Color(0.55, 0.2, 0.14), Color(0.35, 0.45, 0.7)]
	var idx := 0
	# Outer wooden ring.
	for i in 14:
		var ang := TAU * float(i) / 14.0
		var r := 12.5
		var pos := Vector3(cos(ang) * r, 0, sin(ang) * r)
		if absf(pos.x) < 2.6 or absf(pos.z) < 2.6:
			continue # cardinal roads
		_place_prop(pos, "house", randf_range(30.0, 40.0), Vector3(1.9, 1.6, 1.9), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()])
		idx += 1
	# Inner stone ring with 4 gate gaps.
	for i in 12:
		var ang2 := TAU * float(i) / 12.0 + PI / 12.0
		var deg: float = rad_to_deg(ang2) - floor(rad_to_deg(ang2) / 90.0) * 90.0
		if deg < 12.0:
			continue # gate
		var pos2 := Vector3(cos(ang2) * 6.4, 0, sin(ang2) * 6.4)
		_place_prop(pos2, "stone", randf_range(30.0, 40.0), Vector3(2.0, 1.7, 2.0), Color(0.6, 0.6, 0.62), Color(0.36, 0.37, 0.42), true)
	# Mid wooden infill between rings.
	for i in 8:
		var ang3 := TAU * float(i) / 8.0
		_place_prop(Vector3(cos(ang3) * 9.4, 0, sin(ang3) * 9.4), "house", randf_range(30.0, 40.0), Vector3(1.8, 1.5, 1.8), wall_cols[(idx + i) % wall_cols.size()], roof_cols[i % roof_cols.size()])


func _build_fire_station(pos: Vector3) -> void:
	var st := StaticBody3D.new()
	st.name = "FireStation"
	st.collision_layer = 2
	st.collision_mask = 0
	st.position = pos
	village_root.add_child(st)
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(3.5, 3, 3.5)
	col.shape = sh
	col.position = Vector3(0, 1.5, 0)
	st.add_child(col)
	_add_voxel_box(st, Vector3(3.2, 2.0, 3.0), Vector3(0, 1.0, 0), Color(0.85, 0.2, 0.15))
	_add_voxel_box(st, Vector3(3.6, 0.5, 3.4), Vector3(0, 2.25, 0), Color(0.6, 0.12, 0.1))
	_add_voxel_box(st, Vector3(1.4, 1.4, 0.15), Vector3(0, 0.7, 1.55), Color(0.15, 0.15, 0.18))
	# Tower + white roof edge for silhouette.
	_add_voxel_box(st, Vector3(1.0, 3.0, 1.0), Vector3(1.8, 1.5, -1.0), Color(0.85, 0.2, 0.15))
	_add_voxel_box(st, Vector3(1.2, 0.2, 1.2), Vector3(1.8, 3.1, -1.0), Color(0.95, 0.95, 0.95))
	st.set_meta("is_station", true)


func _build_decor() -> void:
	# Perimeter trees use the dedicated tree silhouette (no house parts).
	for i in int(cfg["trees"]):
		var ang := randf() * TAU
		var r := randf_range(cam_bound * 0.6, cam_bound * 0.95)
		_place_prop(Vector3(cos(ang) * r, 0, sin(ang) * r), "tree", randf_range(10.0, 14.0), Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25))


func _build_barrels() -> void:
	# L2/L3: explosive gas barrels with dedicated barrel silhouette.
	for i in int(cfg["barrels"]):
		var h := _place_prop(Vector3(randf_range(-cam_bound * 0.7, cam_bound * 0.7), 0, randf_range(-cam_bound * 0.7, cam_bound * 0.7)), "barrel", 5.0, Vector3(0.8, 1.0, 0.8), Color(0.85, 0.15, 0.1), Color(0.9, 0.6, 0.1))
		h.set_meta("barrel", true)


func _build_wind_fx() -> void:
	wind_arrow = Node3D.new()
	wind_arrow.name = "WindArrow"
	wind_arrow.position = Vector3(0, 8.5, 0)
	village_root.add_child(wind_arrow)
	wind_arrow_body = Node3D.new()
	wind_arrow.add_child(wind_arrow_body)
	_add_voxel_box(wind_arrow_body, Vector3(2.2, 0.3, 0.3), Vector3(0, 0, 0), Color(0.4, 0.7, 1.0))
	_add_voxel_box(wind_arrow_body, Vector3(0.7, 0.7, 0.7), Vector3(1.4, 0, 0), Color(0.5, 0.85, 1.0))
	_add_voxel_box(wind_arrow_body, Vector3(0.5, 0.9, 0.3), Vector3(-1.1, 0, 0), Color(0.3, 0.55, 0.85))
	drift_particles = GPUParticles3D.new()
	drift_particles.amount = 30
	drift_particles.lifetime = 4.0
	drift_particles.preprocess = 4.0
	if DisplayServer.get_name() == "headless":
		drift_particles.preprocess = 0.0
	drift_particles.local_coords = false
	drift_particles.visibility_aabb = AABB(Vector3(-25, -2, -25), Vector3(50, 14, 50))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18, 2, 18)
	pm.direction = Vector3(1, 0.1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.color = Color(0.85, 0.8, 0.6)
	drift_particles.process_material = pm
	var cube := BoxMesh.new()
	cube.size = Vector3(0.14, 0.14, 0.14)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.8, 0.6)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cube.material = m
	drift_particles.draw_pass_1 = cube
	drift_particles.position = Vector3(0, 3, 0)
	village_root.add_child(drift_particles)


func _build_rain_fx() -> void:
	rain_particles = GPUParticles3D.new()
	rain_particles.amount = 120
	rain_particles.lifetime = 1.2
	rain_particles.preprocess = 1.2
	if DisplayServer.get_name() == "headless":
		rain_particles.preprocess = 0.0
	rain_particles.local_coords = false
	rain_particles.emitting = false
	rain_particles.visibility_aabb = AABB(Vector3(-30, -14, -30), Vector3(60, 28, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 1, 22)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 6.0
	pm.initial_velocity_min = 11.0
	pm.initial_velocity_max = 15.0
	pm.gravity = Vector3(0, -4, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.2
	pm.color = Color(0.35, 0.6, 1.0)
	rain_particles.process_material = pm
	var cube := BoxMesh.new()
	cube.size = Vector3(0.12, 0.12, 0.12)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.4, 0.65, 1.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cube.material = m
	rain_particles.draw_pass_1 = cube
	rain_particles.position = Vector3(0, 13, 0)
	village_root.add_child(rain_particles)


# ---------- audio (Task 12: rescoped, headless-guarded, <=6 players) ----------
func _audio_dead() -> bool:
	return AudioServer.get_mix_rate() <= 0 or DisplayServer.get_name() == "headless"


func _build_audio() -> void:
	if _audio_dead():
		audio_muted = true
		if crackle != null:
			crackle.stream = null
		if sfx != null:
			sfx.stream = null
		return
	crackle.stream = _make_crackle_loop()
	crackle.volume_db = -24.0
	crackle.play()
	sfx_ignite = _make_ignite()
	sfx_boom = _make_boom()
	sfx_hiss = _make_hiss()
	sfx.stream = _make_pop()
	# Music: one shared 4s loop, two players (bass + hat) with volume by intensity.
	var music_wav := _make_music_loop()
	music_low = AudioStreamPlayer.new()
	music_low.name = "MusicLow"
	music_low.stream = music_wav
	music_low.volume_db = -20.0
	add_child(music_low)
	music_low.play()
	music_hat = AudioStreamPlayer.new()
	music_hat.name = "MusicHat"
	music_hat.stream = music_wav
	music_hat.volume_db = -28.0
	music_hat.pitch_scale = 2.0
	add_child(music_hat)
	music_hat.play()
	# 3-voice round-robin SFX.
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%s" % ["A", "B", "C"][i]
		add_child(p)
		sfx_voices.append(p)


func _make_crackle_loop() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var last := 0.0
	var pop := 0.0
	for i in n:
		var samp := rng.randf_range(-1.0, 1.0)
		last = last * 0.92 + samp * 0.08
		if rng.randf() < 0.0025:
			pop = rng.randf_range(0.4, 1.0)
		pop *= 0.985
		var s := clampf(last * 2.2 + pop, -1.0, 1.0)
		data[i] = int((s * 0.5 + 0.5) * 255.0)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = rate
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


func _make_music_loop() -> AudioStreamWAV:
	# ONE loop: 11025Hz, 4s, 8-bit (~44k samples). 55Hz square bass @100BPM
	# + hat every other beat, final 50ms equal-power fade (no click).
	var rate := 11025
	var n := rate * 4
	var data := PackedByteArray()
	data.resize(n)
	var beat := float(rate) * 60.0 / 100.0
	for i in n:
		var t := float(i) / float(rate)
		var step := int(float(i) / beat) % 4
		var freqs := [55.0, 55.0, 65.4, 49.0]
		var freq: float = float(freqs[step])
		var ph := fmod(t * freq, 1.0)
		var bass := 0.5 if ph < 0.5 else -0.5
		bass *= 0.5 * (1.0 - fmod(float(i), beat) / beat * 0.5)
		var hat := 0.0
		var in_beat := fmod(float(i), beat * 2.0)
		if in_beat < float(rate) * 0.03:
			hat = 0.25 * (1.0 - in_beat / (float(rate) * 0.03))
			if i % 2 == 0:
				hat = -hat
		var s := clampf((bass + hat) * 0.6, -1.0, 1.0)
		var fade_n := int(float(rate) * 0.05)
		if i >= n - fade_n:
			var u := float(n - i) / float(fade_n)
			s *= sqrt(u * u) # equal-power-ish fade to loop point
			var j := i - (n - fade_n)
			# blend toward loop-start value to avoid click
			var start_ph := fmod(float(j) / float(rate) * 55.0, 1.0)
			var start_v := 0.3 if start_ph < 0.5 else -0.3
			s = lerpf(s, start_v * (1.0 - u), 1.0 - u)
		data[i] = int((s * 0.5 + 0.5) * 255.0)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = rate
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = n
	return wav


func _render_tone(f0: float, f1: float, dur: float, noise: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(float(rate) * dur)
	var data := PackedByteArray()
	data.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f0) + n
	for i in n:
		var u := float(i) / float(n)
		var f := lerpf(f0, f1, u)
		var t := float(i) / float(rate)
		var tone := sin(TAU * f * t) * (1.0 - u)
		var nz := rng.randf_range(-1.0, 1.0) * noise * (1.0 - u)
		var s := clampf((tone * 0.7 + nz) * 0.6, -1.0, 1.0)
		data[i] = int((s * 0.5 + 0.5) * 255.0)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav


func _make_ignite() -> AudioStreamWAV:
	return _render_tone(200.0, 900.0, 0.25, 0.15)


func _make_boom() -> AudioStreamWAV:
	return _render_tone(120.0, 30.0, 0.4, 0.6)


func _make_hiss() -> AudioStreamWAV:
	return _render_tone(900.0, 300.0, 0.3, 0.8)


func _make_pop() -> AudioStreamWAV:
	var rate := 22050
	var n := int(float(rate) * 0.22)
	var data := PackedByteArray()
	data.resize(n)
	for i in n:
		var t := float(i) / float(rate)
		var f := lerpf(700.0, 180.0, float(i) / float(n))
		var s := sin(TAU * f * t) * (1.0 - float(i) / float(n))
		data[i] = int((s * 0.4 + 0.5) * 255.0)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav


func _play_sfx(sname: String) -> void:
	if audio_muted or sfx_voices.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if sfx_cd.has(sname) and now - float(sfx_cd[sname]) < (0.15 if sname != "hiss" else 0.3):
		return
	sfx_cd[sname] = now
	var v := sfx_voices[sfx_idx % sfx_voices.size()]
	sfx_idx += 1
	match sname:
		"ignite":
			v.stream = sfx_ignite
		"boom":
			v.stream = sfx_boom
		"hiss":
			v.stream = sfx_hiss
		_:
			return
	if v.stream == null:
		return
	v.pitch_scale = randf_range(0.95, 1.08)
	v.play()


func _play_pop(pitch: float = 1.0) -> void:
	if audio_muted or sfx == null or sfx.stream == null:
		return
	sfx.pitch_scale = pitch
	sfx.play()


# ---------- spawning ----------
func _spawn_villagers(n: int) -> void:
	for i in n:
		var v: VoxelVillager = VILLAGER_SCENE.instantiate()
		units_root.add_child(v)
		v.position = Vector3(randf_range(-cam_bound * 0.7, cam_bound * 0.7), 0, randf_range(-cam_bound * 0.7, cam_bound * 0.7))
		_buff_char(v)
		v.toasted.connect(_on_villager_toasted)
		v.burn.ignited.connect(_on_char_ignited)


func _update_waves(delta: float, house_burning: int) -> void:
	# CALM 0: nothing spawns, breathe. WARNING 1: banner. ASSAULT 2:
	# crews land every 6s up to cap. STAND DOWN 3: crews retreat home.
	wave_timer -= delta
	match wave_phase:
		0:
			if wave_timer <= 0.0:
				wave_phase = 1
				wave_timer = 5.0
				_show_combo("FIRE CREW INBOUND!")
				_play_pop(0.4)
		1:
			if wave_timer <= 0.0:
				wave_phase = 2
				wave_timer = 45.0
				assault_tick = 0.0
		2:
			assault_tick -= delta
			if assault_tick <= 0.0:
				assault_tick = 6.0
				var cap := 2 + int(burn_percent * 0.05) + (1 if house_burning >= 4 else 0)
				cap = mini(cap, 5)
				var alive := 0
				for f in get_tree().get_nodes_in_group("firefighters"):
					if is_instance_valid(f):
						alive += 1
				if alive < cap:
					_spawn_firefighter()
			if wave_timer <= 0.0:
				wave_phase = 3
				wave_timer = 8.0
				for f in get_tree().get_nodes_in_group("firefighters"):
					if is_instance_valid(f) and f is VoxelFirefighter:
						(f as VoxelFirefighter).begin_retreat()
				_show_combo("CREW FALLS BACK...")
		3:
			if wave_timer <= 0.0:
				wave_phase = 0
				wave_timer = 80.0 if level_idx == 0 else 65.0
				_flash_hint("Quiet... feed THE fire while you can.")


func _spawn_firefighter() -> void:
	var f: VoxelFirefighter = FIREFIGHTER_SCENE.instantiate()
	units_root.add_child(f)
	var station := Vector3(-cam_bound + 2.0, 0, -cam_bound + 2.0)
	f.global_position = station + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	f.home_pos = f.global_position
	f.speed *= float(cfg["ff_speed"])
	if randf() < float(cfg["elite_chance"]):
		f.elite = true
		f.speed = 5.2
		f.spray_rate = 1.3
		f.courage = 1.6
	_buff_char(f)
	f.torched.connect(_on_firefighter_torched)
	f.burn.ignited.connect(_on_char_ignited)


func _buff_char(c: Node) -> void:
	# Marshmallow Aura: burning characters survive +40% longer.
	if RunState.up_aura:
		var b: CharBurn = c.get("burn")
		if b != null:
			b.burn_hp_max *= 1.4
			b.burn_hp = b.burn_hp_max


func _setup_starter() -> void:
	var sorted := houses.duplicate()
	sorted.sort_custom(func(a, b): return a.position.length() < b.position.length())
	starter_houses.clear()
	for h in sorted:
		if h is VoxelHouse and h.house_size.x > 1.2 and not h.fireproof:
			starter_houses.append(h)
			if starter_houses.size() >= 2:
				break
	for h in starter_houses:
		starter_markers.append(_make_starter_marker(h))
	_flash_hint("Take your time - click a glowing house to light it (FREE)!")


func _make_starter_marker(h: VoxelHouse) -> Node3D:
	var root := Node3D.new()
	root.set_meta("bob_t", randf() * TAU)
	village_root.add_child(root)
	root.global_position = h.global_position + Vector3(0, 4.2, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.75, 0.15)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.15)
	mat.emission_energy_multiplier = 1.5
	var tip := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.7, 0.5)
	bm.material = mat
	tip.mesh = bm
	tip.rotation.y = PI / 4.0
	root.add_child(tip)
	var stem := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.22, 0.6, 0.22)
	sm.material = mat
	stem.mesh = sm
	stem.position = Vector3(0, 0.6, 0)
	root.add_child(stem)
	return root


func _clear_starter_markers() -> void:
	for m in starter_markers:
		if is_instance_valid(m):
			m.queue_free()
	starter_markers.clear()
	starter_houses.clear()


func _ignite_starter() -> void:
	_setup_starter()


# ---------- per-frame ----------
func _process(delta: float) -> void:
	tutorial_t += delta
	_update_camera(delta)
	_tick_barrels(delta)
	if game_over:
		_update_fx(delta)
		return
	if not has_started:
		_update_tutorial_pre()
		_update_fx(delta)
		_update_hud()
		return
	elapsed += delta
	RunState.run_time += delta
	RunState.level_time += delta
	_gust_cd = maxf(0.0, _gust_cd - delta)
	last_stand_cd = maxf(0.0, last_stand_cd - delta)
	toast_cd = maxf(0.0, toast_cd - delta)
	ember_floor_cd = maxf(0.0, ember_floor_cd - delta)
	_update_wind(delta)
	_update_rain(delta)
	_update_heli(delta)
	_update_combo(delta)
	_update_toasts(delta)
	_update_tutorial_post()

	var house_burning := _house_burning_count()
	var chars_burning := _chars_burning_count()
	var total_flames := house_burning + chars_burning
	max_burning = maxi(max_burning, total_flames)

	# THE Fire's heartbeat + growth. Every flame reads these.
	RunState.fire_pulse += delta
	RunState.inferno = lerpf(RunState.inferno, clampf(float(total_flames) / 10.0, 0.0, 1.0), delta * 0.8)

	# HP economy (M1): idle-only bleed 0.6/s with no flames; else drain/gain.
	# NOTE: chars give 0 HP.
	if total_flames == 0:
		fire_hp -= 0.6 * delta
	else:
		fire_hp -= fire_drain * delta
		fire_hp += float(house_burning) * fire_gain_per_house * delta
	fire_hp = clampf(fire_hp, 0.0, fire_hp_max)

	# Spray pressure: hoses wound THE fire itself, not just local fuel.
	var spraying := 0
	for f in get_tree().get_nodes_in_group("firefighters"):
		if is_instance_valid(f) and f is VoxelFirefighter and (f as VoxelFirefighter).is_spraying():
			spraying += 1
	if spraying > 0:
		fire_hp -= 0.4 * float(spraying) * delta

	# Mana regen: slow MP drip so strategy never fully stalls.
	mana_tick += delta
	if mana_tick >= 15.0:
		mana_tick = 0.0
		if embers < ember_max:
			embers = mini(embers + 1, ember_max)

	# Ember floor trickle: only while embers<2, hard cap +1 per 4s.
	if house_burning > 0 and embers < 2:
		ember_tick += delta * float(house_burning) * 0.10
		if ember_tick >= 1.0 and ember_floor_cd <= 0.0:
			ember_tick = 0.0
			ember_floor_cd = 4.0
			embers = mini(embers + 1, ember_max)
	elif embers >= 2:
		ember_tick = 0.0

	# Pity: burning<=1 and embers==0 -> free ember every 6s.
	if house_burning <= 1 and embers <= 0:
		pity_t += delta
		if pity_t >= 6.0:
			pity_t = 0.0
			embers = mini(embers + 1, ember_max)
			_flash_hint("The wind feeds you an ember")
	else:
		pity_t = 0.0

	spread_timer -= delta
	if spread_timer <= 0.0:
		spread_timer = 1.6
		_spread_fire()

	_update_waves(delta, house_burning)

	scared_tick -= delta
	if scared_tick <= 0.0:
		scared_tick = 1.0
		_count_scared()

	var burnt := 0
	for h in houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.BURNT:
			burnt += 1
	burn_percent = 100.0 * float(burnt) / float(maxi(1, houses.size()))
	_check_phases()
	_cull_lights()

	if burn_percent >= win_percent:
		_end_game(true)
	elif total_flames == 0:
		dead_fire_timer += delta
		var limit := 12.0 if embers > 0 else 6.0
		if not no_flame_warned:
			no_flame_warned = true
		# No-flames countdown goes on objective_label (big central).
		var left := maxf(0.0, limit - dead_fire_timer)
		objective_label.text = "NO FLAMES! %.0fs — click a house NOW!" % left if embers > 0 else "NO FLAMES! %.0fs" % left
		if dead_fire_timer > limit or fire_hp <= 0.0:
			_end_game(false)
	else:
		dead_fire_timer = 0.0
		no_flame_warned = false
		if fire_hp <= 0.0:
			_last_stand()

	if not game_over and total_flames > 0 and fire_hp < 22.0:
		var pulse := 0.6 + 0.4 * sin(elapsed * 8.0)
		fire_bar.modulate = Color(1.0, pulse, pulse)
		warn_cd -= delta
		if warn_cd <= 0.0:
			warn_cd = 6.0
			_flash_hint("LOW FIRE! Ignite something!")
	else:
		fire_bar.modulate = Color.WHITE

	_update_fx(delta)
	_update_hud()
	_update_audio(total_flames)


func _last_stand() -> void:
	# On fire_hp<=0 with flames>0: extinguish lowest-fuel burning house
	# (no refund), fire_hp=25, 20s CD, banner on combo_label.
	if last_stand_cd > 0.0:
		fire_hp = 0.01
		return
	var worst: VoxelHouse = null
	for h in houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
			if worst == null or h.fuel < worst.fuel:
				worst = h
	if worst == null:
		return
	worst.extinguish()
	fire_hp = 25.0
	last_stand_cd = 20.0
	combo_label.add_theme_font_size_override("font_size", 28)
	_show_combo("A FLAME GUTTERS OUT! (25 HP)")
	_play_sfx("hiss")


func _house_burning_count() -> int:
	var n := 0
	for h in houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
			n += 1
	return n


func _chars_burning_count() -> int:
	var n := 0
	for c in get_tree().get_nodes_in_group("burning_chars"):
		if is_instance_valid(c):
			n += 1
	return n


func _count_scared() -> void:
	for f in get_tree().get_nodes_in_group("firefighters"):
		if not is_instance_valid(f) or (f is VoxelFirefighter and (f as VoxelFirefighter).is_burning()):
			continue
		if (f as Node3D) == null:
			continue
		var fp := (f as Node3D).global_position
		for h in houses:
			if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
				if fp.distance_to(h.global_position) < 3.0:
					if not (f as Node).has_meta("scared_cd") or Time.get_ticks_msec() - int((f as Node).get_meta("scared_cd")) > 8000:
						(f as Node).set_meta("scared_cd", Time.get_ticks_msec())
						scared += 1
					break


func _spread_budget() -> int:
	var budgets := [1, 2, 2]
	var b: int = int(budgets[clampi(level_idx, 0, 2)])
	if spread_mult > 1.0:
		b += 1
	if barrel_bonus > 0:
		b += barrel_bonus
		barrel_bonus = 0
	return b


func _spread_fire() -> void:
	# Pipeline: dedupe candidates (dst -> max c), sort desc, top-3,
	# weighted-random pick N=budget. No immediate pairwise ignite() calls.
	var house_src: Array[VoxelHouse] = []
	for h in houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
			house_src.append(h)
	var candidates := {}
	var R := 4.4
	var base := 0.055
	for src in house_src:
		for dst in houses:
			if not is_instance_valid(dst) or dst.state != VoxelHouse.State.UNBURNED:
				continue
			if dst.fireproof and dst.heat_prime <= 0.0:
				continue
			var to: Vector3 = dst.global_position - src.global_position
			var dist := to.length()
			if dist > R or dist < 0.01:
				continue
			to = to.normalized()
			var align := to.dot(wind_dir) * 0.5 + 0.5
			var wind_term := lerpf(0.6, 1.5, align) * wind_strength
			var c: float = base * (1.0 - dist / R) * wind_term * spread_mult
			c *= (1.0 - dst.wetness * 1.5)
			if rain_phase == 2:
				c *= 0.25
			if dst.house_size.x < 1.2:
				c *= 1.3 # trees (was 1.6)
			else:
				c *= 1.0
			if c <= 0.0:
				continue
			if not candidates.has(dst) or float(candidates[dst]) < c:
				candidates[dst] = c
	if not candidates.is_empty():
		var keys := candidates.keys()
		keys.sort_custom(func(a, b): return float(candidates[a]) > float(candidates[b]))
		var top: Array = keys.slice(0, 3)
		var budget := _spread_budget()
		for i in budget:
			if top.is_empty():
				break
			var total := 0.0
			for k in top:
				total += float(candidates[k])
			if total <= 0.0:
				break
			var roll := randf() * total
			var pick: VoxelHouse = null
			for k in top:
				roll -= float(candidates[k])
				if roll <= 0.0:
					pick = k
					break
			if pick == null:
				pick = top[top.size() - 1]
			top.erase(pick)
			pick.ignite()
	# Char -> house: only if char burn_hp > 30% max, 2.6m / 0.18, 0.9s tick.
	for c in get_tree().get_nodes_in_group("burning_chars"):
		if not is_instance_valid(c) or not (c is Node3D):
			continue
		var burn: CharBurn = (c as Node).get("burn")
		if burn != null and burn.burn_hp < burn.burn_hp_max * 0.3:
			continue
		var tick_ok := true
		if (c as Node).has_meta("spread_t"):
			if float((c as Node).get_meta("spread_t")) > 0.0:
				tick_ok = false
		if not tick_ok:
			continue
		(c as Node).set_meta("spread_t", 0.9)
		var pos := (c as Node3D).global_position
		for dst in houses:
			if not is_instance_valid(dst) or dst.state != VoxelHouse.State.UNBURNED:
				continue
			if dst.fireproof and dst.heat_prime <= 0.0:
				continue
			if pos.distance_to(dst.global_position) < 2.6:
				if randf() < 0.18 * spread_mult:
					if dst.ignite():
						break
	# Char -> char: 0.15 in 1.5m.
	var chars := get_tree().get_nodes_in_group("villagers") + get_tree().get_nodes_in_group("firefighters")
	for pos_node in get_tree().get_nodes_in_group("burning_chars"):
		if not is_instance_valid(pos_node) or not (pos_node is Node3D):
			continue
		var pos := (pos_node as Node3D).global_position
		for cc in chars:
			if not is_instance_valid(cc) or not (cc is Node3D):
				continue
			if (cc as Node).is_in_group("burning_chars"):
				continue
			if pos.distance_to((cc as Node3D).global_position) < 1.5:
				if randf() < 0.15:
					if cc is VoxelVillager:
						(cc as VoxelVillager).ignite()
					elif cc is VoxelFirefighter:
						(cc as VoxelFirefighter).ignite()


func _on_house_ignited(_h: VoxelHouse) -> void:
	_bump_combo()
	shake = minf(shake + 0.08, 0.8)
	_play_sfx("ignite")
	_play_pop(randf_range(0.9, 1.15))


func _on_char_ignited() -> void:
	_bump_combo()
	shake = minf(shake + 0.08, 0.8)
	_play_sfx("ignite")
	_play_pop(randf_range(0.7, 0.9))


func _on_villager_toasted(_v: VoxelVillager) -> void:
	toasted += 1
	RunState.run_toasted += 1
	if toast_cd <= 0.0:
		toast_cd = 2.0
		embers = mini(embers + 1, ember_max)
	shake = minf(shake + 0.25, 0.9)
	_play_pop(0.6)


func _on_firefighter_torched(_f: VoxelFirefighter) -> void:
	torched += 1
	RunState.run_torched += 1
	embers = mini(embers + 2, ember_max)
	_bump_combo()
	_bump_combo()
	_show_combo("FIREFIGHTER TORCHED!")
	shake = minf(shake + 0.4, 1.0)
	_play_pop(0.5)


func _on_house_burned_out(h: VoxelHouse) -> void:
	if not is_instance_valid(h):
		return
	var bonus := 2 if RunState.up_grease else 1
	embers = mini(embers + bonus, ember_max)
	_play_pop(0.55)
	if h.has_meta("barrel"):
		barrel_queue.append({"pos": h.global_position, "t": 1.0})
		shake = minf(shake + 0.2, 0.8)
	else:
		shake = minf(shake + 0.25, 0.8)


func _tick_barrels(delta: float) -> void:
	if barrel_queue.is_empty():
		return
	barrel_tick_t -= delta
	for q in barrel_queue.duplicate():
		var d := q as Dictionary
		d["t"] = float(d["t"]) - delta
		if barrel_tick_t <= 0.0:
			barrel_tick_t = 0.25
			_play_pop(lerpf(0.8, 1.6, 1.0 - float(d["t"])))
		if float(d["t"]) <= 0.0:
			barrel_queue.erase(q)
			_explode_barrel(d["pos"])


func _explode_barrel(pos: Vector3) -> void:
	# Banked blast: budgeted p=0.8 / R=4.0m / cap 2 ignites via force_ignite;
	# non-ignited in radius primed; chars in 3.5m single 0.5 roll.
	shake = 1.0
	_play_sfx("boom")
	_show_combo("BARREL BOOM!")
	barrel_bonus += 1
	embers = mini(embers + 1, ember_max)
	var ignited := 0
	var in_radius: Array[VoxelHouse] = []
	for dst in houses:
		if is_instance_valid(dst) and dst.state == VoxelHouse.State.UNBURNED:
			if pos.distance_to(dst.global_position) < 4.0:
				in_radius.append(dst)
	in_radius.sort_custom(func(a, b): return pos.distance_to(a.global_position) < pos.distance_to(b.global_position))
	for dst in in_radius:
		if ignited >= 2:
			break
		if randf() < 0.8:
			if dst.force_ignite():
				ignited += 1
	for dst in in_radius:
		if dst.state == VoxelHouse.State.UNBURNED:
			dst.wetness = 0.0
			dst._flash = 1.0
	for c in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(c) and c is VoxelVillager and not (c as VoxelVillager).is_burning():
			if pos.distance_to((c as Node3D).global_position) < 3.5:
				if randf() < 0.5:
					(c as VoxelVillager).ignite()
	for c in get_tree().get_nodes_in_group("firefighters"):
		if is_instance_valid(c) and c is VoxelFirefighter and not (c as VoxelFirefighter).is_burning():
			if pos.distance_to((c as Node3D).global_position) < 3.5:
				if randf() < 0.5:
					(c as VoxelFirefighter).ignite()


# ---------- wind ----------
func _update_wind(delta: float) -> void:
	wind_timer -= delta
	if wind_timer <= 0.0:
		wind_timer = randf_range(22.0, 32.0) if level_idx == 0 else randf_range(14.0, 22.0)
		var a := randf() * TAU
		wind_dir = Vector3(cos(a), 0, sin(a))
		wind_baseline = randf_range(float(cfg["wind_min"]), float(cfg["wind_max"]))
		wind_strength = wind_baseline
	else:
		wind_strength = lerpf(wind_strength, wind_baseline, delta * 0.5)
	wind_flash = maxf(0.0, wind_flash - delta * 2.0)
	gust_pulse = maxf(0.0, gust_pulse - delta * 2.5)
	var tilt := wind_dir * wind_strength
	for h in houses:
		if is_instance_valid(h):
			h.set_wind_tilt(tilt)
	# Decay per-char spread ticks.
	for c in get_tree().get_nodes_in_group("burning_chars"):
		if is_instance_valid(c) and (c as Node).has_meta("spread_t"):
			(c as Node).set_meta("spread_t", maxf(0.0, float((c as Node).get_meta("spread_t")) - delta))


func _cull_lights() -> void:
	# Perf budget: nearest 4 burning houses keep lights, rest off.
	var burning: Array[VoxelHouse] = []
	for h in houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
			burning.append(h)
	burning.sort_custom(func(a, b): return rig.position.distance_squared_to(a.global_position) < rig.position.distance_squared_to(b.global_position))
	for i in burning.size():
		burning[i].set_light_allowed(i < 4)
		burning[i].set_smoke_lod(_house_burning_count() > 5)


func _update_fx(delta: float) -> void:
	for m in starter_markers:
		if is_instance_valid(m):
			var t: float = float(m.get_meta("bob_t")) + delta * 3.0
			m.set_meta("bob_t", t)
			m.position.y += sin(t) * delta * 0.8
			m.rotation.y += delta * 2.0
	if is_instance_valid(wind_arrow_body):
		wind_arrow_body.rotation.y = atan2(-wind_dir.z, wind_dir.x)
	if is_instance_valid(wind_arrow):
		wind_arrow.position.y = 8.5 + sin(Time.get_ticks_msec() * 0.002) * 0.3
		var s := 1.0 + gust_pulse * 0.6
		wind_arrow.scale = Vector3(s, s, s)
	if is_instance_valid(drift_particles) and drift_particles.process_material is ParticleProcessMaterial:
		var dpm := drift_particles.process_material as ParticleProcessMaterial
		dpm.direction = (wind_dir + Vector3(0, 0.08, 0)).normalized()
		var v := 2.0 + wind_strength * 2.5
		dpm.initial_velocity_min = v * 0.7
		dpm.initial_velocity_max = v * 1.3
	shake = maxf(0.0, shake - delta * 2.5)
	if camera != null:
		if shake > 0.01:
			camera.h_offset = randf_range(-1.0, 1.0) * shake * 0.45
			camera.v_offset = randf_range(-1.0, 1.0) * shake * 0.45
		else:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
	if combo_left > 0.0:
		combo_left -= delta
		var a := clampf(combo_left, 0.0, 1.0)
		combo_label.modulate = Color(1, 1, 1, a)
		if combo_left <= 0.0:
			combo_label.text = ""
	if toast_left > 0.0:
		toast_left -= delta
		toast_label.modulate = Color(1, 1, 1, clampf(toast_left, 0.0, 1.0))
	if hint_t > 0.0:
		hint_t -= delta
		if hint_t <= 0.0:
			hint_label.modulate.a = 0.35
	if controls_t > 0.0:
		controls_t -= delta
		if controls_label != null:
			if controls_t < 12.0:
				controls_label.modulate.a = 0.35


func _spawn_gust_streaks(dir: Vector3) -> void:
	# Shared class-level mesh + material (transient alpha fade, no leak).
	if _streak_mesh == null:
		_streak_mesh = BoxMesh.new()
		_streak_mesh.size = Vector3(1.6, 0.12, 0.12)
	if _streak_mat == null:
		_streak_mat = StandardMaterial3D.new()
		_streak_mat.albedo_color = Color(0.9, 0.95, 1.0, 0.8)
		_streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in 10:
		var mi := MeshInstance3D.new()
		mi.mesh = _streak_mesh
		mi.material_override = _streak_mat
		var start := Vector3(randf_range(-12, 12), randf_range(1.0, 5.0), randf_range(-12, 12))
		mi.position = start
		mi.rotation.y = atan2(-dir.z, dir.x)
		village_root.add_child(mi)
		var tw := mi.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "position", start + dir * 10.0 + Vector3(0, 1.0, 0), 0.55)
		tw.tween_property(mi, "scale", Vector3(0.1, 1.0, 1.0), 0.55)
		tw.chain().tween_callback(mi.queue_free)


# ---------- rain (L2, latched) ----------
func _update_rain(delta: float) -> void:
	if not bool(cfg["rain"]) or game_over:
		if rain_phase == 2 and rain_particles != null:
			rain_particles.emitting = false
		return
	if burn_percent < 45.0 and rain_phase == 0 and rain_timer <= 0.0:
		rain_armed = true
		rain_timer = 30.0
	if burn_percent >= 45.0 and rain_armed and not rain_warned:
		rain_warned = true
		rain_phase = 1
		rain_timer = 4.0
		_show_combo("RAIN COMING... PROTECT THE FLAME!")
		_play_pop(0.4)
		return
	if rain_phase == 0 and not rain_armed:
		rain_timer -= delta
		if rain_timer <= 0.0 and burn_percent >= 45.0:
			rain_phase = 1
			rain_timer = 4.0
			rain_warned = true
			_show_combo("RAIN COMING... PROTECT THE FLAME!")
			_play_pop(0.4)
		elif rain_timer <= 0.0:
			rain_armed = true
			rain_timer = 30.0
	elif rain_phase == 1:
		rain_timer -= delta
		if rain_timer <= 0.0:
			rain_phase = 2
			rain_timer = 6.0
			if rain_particles != null:
				rain_particles.emitting = true
			_flash_hint("RAIN! Keep something burning!")
			_dim_for_rain(true)
	elif rain_phase == 2:
		if rain_particles != null:
			rain_particles.emitting = true
		# Rain wounds THE fire directly, not just local fuel.
		fire_hp -= 1.5 * delta
		for h in houses:
			if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
				h.apply_water(0.30, delta)
		for c in get_tree().get_nodes_in_group("burning_chars"):
			if is_instance_valid(c):
				if c is VoxelVillager:
					(c as VoxelVillager).apply_water(0.4, delta)
				elif c is VoxelFirefighter:
					(c as VoxelFirefighter).apply_water(0.4, delta)
		rain_timer -= delta
		if rain_timer <= 0.0:
			rain_phase = 0
			rain_armed = false
			rain_warned = false
			rain_timer = randf_range(25.0, 35.0)
			if rain_particles != null:
				rain_particles.emitting = false
			_dim_for_rain(false)
			_flash_hint("Rain passed. Cook on!")


func _dim_for_rain(on: bool) -> void:
	var env := ($WorldEnvironment as WorldEnvironment)
	if env == null or env.environment == null:
		return
	if on:
		env.environment.ambient_light_energy = 0.5
	else:
		env.environment.ambient_light_energy = 0.7
	var sun := ($Sun as DirectionalLight3D)
	if sun != null:
		sun.light_energy = 0.65 if on else 0.9


# ---------- heli (L3, latched) ----------
func _update_heli(delta: float) -> void:
	if not bool(cfg["heli"]) or game_over:
		return
	if burn_percent < 45.0 and heli_phase == 0 and heli_timer <= 0.0:
		heli_armed = true
		heli_timer = 25.0
	if burn_percent >= 45.0 and heli_armed and not heli_warned:
		heli_warned = true
		heli_phase = 1
		heli_timer = 4.0
		_show_combo("HELI INBOUND! GUARD YOUR FIRE!")
		_play_pop(0.4)
		return
	if heli_phase == 1:
		heli_timer -= delta
		if heli_timer <= 0.0:
			heli_phase = 0
			heli_armed = false
			heli_timer = randf_range(20.0, 30.0)
			_spawn_heli()
		_update_heli_flight(delta)
		return
	heli_timer -= delta
	if heli_timer <= 0.0 and burn_percent < 45.0:
		heli_armed = true
		heli_timer = 25.0
	elif heli_timer <= 0.0:
		heli_timer = randf_range(20.0, 30.0)
		_spawn_heli()
	_update_heli_flight(delta)


func _spawn_heli() -> void:
	var heli := Node3D.new()
	var side: float = [-1.0, 1.0][randi() % 2]
	var from := Vector3(side * (cam_bound + 6.0), 11.0, randf_range(-8, 8))
	var to := Vector3(-side * (cam_bound + 6.0), 11.0, randf_range(-8, 8))
	heli.position = from
	village_root.add_child(heli)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.2, 0.3, 0.6)
	body_mat.roughness = 1.0
	var body := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(1.6, 0.6, 0.9)
	bb.material = body_mat
	body.mesh = bb
	heli.add_child(body)
	var tail := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(1.6, 0.25, 0.25)
	tb.material = body_mat
	tail.mesh = tb
	tail.position = Vector3(-1.4, 0.15, 0)
	heli.add_child(tail)
	var rotor := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(2.6, 0.08, 0.3)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.15, 0.15, 0.15)
	rb.material = rm
	rotor.mesh = rb
	rotor.position = Vector3(0, 0.45, 0)
	heli.add_child(rotor)
	helis.append({"node": heli, "rotor": rotor, "t": 0.0, "dur": 12.0, "from": from, "to": to, "dropped": false})
	_show_combo("HELI INBOUND! GUARD YOUR FIRE!")
	_play_pop(0.4)


func _update_heli_flight(delta: float) -> void:
	for h in helis.duplicate():
		if h is not Dictionary:
			continue
		var d := h as Dictionary
		if not is_instance_valid(d.get("node")):
			helis.erase(h)
			continue
		d["t"] = float(d["t"]) + delta
		var t: float = clampf(float(d["t"]) / float(d["dur"]), 0.0, 1.0)
		var node := (d["node"]) as Node3D
		node.position = (d["from"] as Vector3).lerp(d["to"] as Vector3, t)
		if is_instance_valid(d.get("rotor")):
			((d["rotor"]) as Node3D).rotation.y += delta * 20.0
		if not bool(d["dropped"]) and t >= 0.5:
			d["dropped"] = true
			_heli_drop(node.position)
		if t >= 1.0:
			node.queue_free()
			helis.erase(h)


func _heli_drop(pos: Vector3) -> void:
	_flash_hint("SPLASH! Water drop!")
	_play_sfx("hiss")
	_play_pop(0.35)
	fire_hp = maxf(0.0, fire_hp - 8.0)
	for h in houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
			var flat := Vector2(h.global_position.x - pos.x, h.global_position.z - pos.z)
			if flat.length() < 5.0:
				h.apply_water(2.0, 1.0)
	for c in get_tree().get_nodes_in_group("burning_chars"):
		if is_instance_valid(c) and c is Node3D:
			var cp := (c as Node3D).global_position
			var flat := Vector2(cp.x - pos.x, cp.z - pos.z)
			if flat.length() < 5.0:
				if c is VoxelVillager:
					(c as VoxelVillager).apply_water(2.0, 1.0)
				elif c is VoxelFirefighter:
					(c as VoxelFirefighter).apply_water(2.0, 1.0)


# ---------- camera ----------
func _update_camera(delta: float) -> void:
	if rig == null or camera == null:
		return
	var k := 1.0 - exp(-8.0 * delta)
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or Input.is_action_pressed("ui_up"):
		pan.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) or Input.is_action_pressed("ui_down"):
		pan.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT) or Input.is_action_pressed("ui_left"):
		pan.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT) or Input.is_action_pressed("ui_right"):
		pan.x += 1.0
	if edge_pan and not game_over:
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport().get_visible_rect().size
		var m := 12.0
		if mp.x >= 0.0 and mp.x <= vs.x and mp.y >= 0.0 and mp.y <= vs.y:
			if mp.x < m:
				pan.x -= 0.7
			elif mp.x > vs.x - m:
				pan.x += 0.7
			if mp.y < m:
				pan.y -= 0.7
			elif mp.y > vs.y - m:
				pan.y += 0.7
	if pan != Vector2.ZERO:
		var yaw_basis := camera.global_transform.basis
		var fwd := -yaw_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := yaw_basis.x
		right.y = 0.0
		right = right.normalized()
		var speed := camera.size * 0.9
		var want: Vector3 = rig.position + (right * pan.x - fwd * -pan.y) * speed * delta * 4.0
		# Narrow-aspect guard: widen clamp so portrait shows level corners.
		var vs2 := get_viewport().get_visible_rect().size
		var aspect := vs2.x / maxf(1.0, vs2.y)
		var widen := maxf(1.0, (16.0 / 9.0) / maxf(0.2, aspect))
		var bound := cam_bound * widen
		want.x = clampf(want.x, -bound, bound)
		want.z = clampf(want.z, -bound, bound)
		want.y = 0.0
		rig.position = rig.position.lerp(want, k)
	var zoom := 0.0
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		zoom += 1.0
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_PLUS) or Input.is_key_pressed(KEY_KP_ADD):
		zoom -= 1.0
	if zoom != 0.0:
		var want_size := clampf(camera.size + zoom * 12.0 * delta * 4.0, 12.0, 28.0)
		camera.size = lerpf(camera.size, want_size, k)


func _zoom_step(amount: float) -> void:
	if camera == null:
		return
	camera.size = clampf(camera.size + amount, 12.0, 28.0)


# ---------- input: click ignite, drag gust, wheel zoom, pause ----------
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
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_start = mb.position
			else:
				if _dragging:
					var drag_vec: Vector2 = mb.position - _drag_start
					if drag_vec.length() > 40.0 and _gust_cd <= 0.0:
						_do_gust(drag_vec)
					else:
						_try_ignite_at(mb.position)
					_dragging = false
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_dragging = true
			_drag_start = st.position
		else:
			if _dragging:
				_dragging = false
				_try_ignite_at(st.position)


func _try_ignite_at(screen_pos: Vector2) -> void:
	var house := _pick_house(screen_pos)
	if house == null:
		return
	if house.state != VoxelHouse.State.UNBURNED:
		return
	if house.fireproof and house.heat_prime <= 0.0:
		_flash_hint("Stone won't catch! Prime it with a gust first.")
		return
	var free := not has_started
	if not free and embers <= 0:
		_flash_hint("No embers! Wait for fire to cook.")
		return
	if house.ignite():
		if free:
			has_started = true
			_clear_starter_markers()
			_flash_hint("Nice! Burning houses feed FIRE HP - keep it alive!")
		else:
			embers -= 1
		_update_hud()
	else:
		_flash_hint("Too wet to ignite!")


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


func _do_gust(drag_vec: Vector2) -> void:
	# Gust: 2 embers (MP) + 8s CD. Steers wind 6s, primes stone.
	if embers < 2:
		_flash_hint("Need 2 embers for a gust!")
		return
	embers -= 2
	_gust_cd = 8.0
	var cam_basis := camera.global_transform.basis
	var world_push := (cam_basis.x * drag_vec.x + cam_basis.y * -drag_vec.y)
	world_push.y = 0.0
	if world_push.length() < 0.01:
		return
	wind_dir = world_push.normalized()
	wind_strength = 1.4
	wind_baseline = 1.4
	wind_timer = 6.0
	gust_pulse = 1.0
	wind_flash = 1.0
	_spawn_gust_streaks(wind_dir)
	# Stone prime only: wetness=0 + heat_prime 6s near any burning house.
	for dst in houses:
		if not is_instance_valid(dst) or dst.state != VoxelHouse.State.UNBURNED:
			continue
		if not dst.fireproof:
			continue
		for src in houses:
			if not is_instance_valid(src) or src.state != VoxelHouse.State.BURNING:
				continue
			if src.global_position.distance_to(dst.global_position) < 3.5:
				dst.wetness = 0.0
				dst.heat_prime = 6.0
				break
	_flash_hint("Wind shifted! Stone near flames is primed.")
	_play_pop(1.3)


# ---------- announcements / HUD ----------
func _bump_combo() -> void:
	if game_over:
		return
	combo_count += 1
	combo_timer = 4.0
	peak_combo = maxi(peak_combo, combo_count)
	if combo_count == 3:
		_show_combo("LET HIM COOK! x3")
	elif combo_count == 5:
		_show_combo("HE CAN'T MISS! x5")
	elif combo_count == 8:
		_show_combo("ABSOLUTE INFERNO! x8")
	elif combo_count > 8 and combo_count % 4 == 0:
		_show_combo("UNSTOPPABLE! x%d" % combo_count)


func _show_combo(text: String) -> void:
	if combo_label == null:
		return
	combo_label.text = text
	combo_label.modulate = Color(1, 1, 1, 1)
	combo_left = 2.2
	shake = minf(shake + 0.15, 0.8)


func _update_combo(delta: float) -> void:
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo_count = 0


func _queue_intro_toasts() -> void:
	toast_queue.clear()
	toast_left = 0.0
	controls_t = 12.0
	if controls_label != null:
		controls_label.modulate.a = 1.0
	if level_idx == 0:
		toast_queue = [
			[0.5, "You are the EMBER SPIRIT - Keep it alive!"],
			[3.5, "Click a house to IGNITE (1 ember) - Drag to GUST"],
			[7.5, "Burning houses feed FIRE HP - Cook %d%% to win!" % int(win_percent)],
			[11.5, "WASD / arrows pan - Q / E or wheel zoom - P pauses"],
		]
	elif level_idx == 1:
		toast_queue = [
			[0.5, "TOWN: denser streets, faster crews..."],
			[3.5, "Red BARRELS explode! Rain will try to stop you."],
		]
	else:
		toast_queue = [
			[0.5, "CITY: stone firebreaks won't catch sparks."],
			[3.5, "Flank stone with gusts/barrels. Beware the HELI + elites!"],
		]


func _update_tutorial_pre() -> void:
	# Tutorial clock advances pre-start too. L1 beats.
	if level_idx == 0:
		if tutorial_stage == 0 and tutorial_t >= 0.5:
			tutorial_stage = 1
			toast_label.text = "Click an AMBER-marked house (FREE)"
			toast_label.modulate = Color(1, 1, 1, 1)
			toast_left = 3.0
	else:
		if tutorial_stage == 0 and tutorial_t >= 0.5:
			tutorial_stage = 1
			toast_label.text = str(toast_queue[0][1]) if not toast_queue.is_empty() else ""
			toast_label.modulate = Color(1, 1, 1, 1)
			toast_left = 3.0


func _update_tutorial_post() -> void:
	if level_idx == 0:
		if tutorial_stage == 1 and has_started:
			tutorial_stage = 2
			toast_label.text = "Burning feeds FIRE — light a 2nd downwind"
			toast_label.modulate = Color(1, 1, 1, 1)
			toast_left = 3.0
		elif tutorial_stage == 2 and _house_burning_count() >= 3:
			tutorial_stage = 3
			toast_label.text = "Drag = gust (−4 HP) · crews coming"
			toast_label.modulate = Color(1, 1, 1, 1)
			toast_left = 3.0
	else:
		if tutorial_stage == 1 and tutorial_t >= 3.5 and toast_queue.size() > 1:
			tutorial_stage = 2
			toast_label.text = str(toast_queue[1][1])
			toast_label.modulate = Color(1, 1, 1, 1)
			toast_left = 3.0


func _update_toasts(_delta: float) -> void:
	if toast_queue.is_empty():
		return
	var next: Array = toast_queue[0]
	if elapsed >= float(next[0]):
		toast_queue.pop_front()
		toast_label.text = str(next[1])
		toast_label.modulate = Color(1, 1, 1, 1)
		toast_left = 3.0


func _flash_hint(text: String) -> void:
	if hint_label == null:
		return
	hint_label.text = text
	hint_label.modulate.a = 1.0
	hint_t = 2.5


func _check_phases() -> void:
	if not bool(phase_flags["p30"]) and burn_percent >= 30.0:
		phase_flags["p30"] = true
		_show_combo("THE VILLAGE PANICS!")
		_spawn_villagers(3)
	if not bool(phase_flags["p50"]) and burn_percent >= 50.0:
		phase_flags["p50"] = true
		_show_combo("LET HIM COOK!!")
		wind_strength = minf(wind_strength + 0.5, 2.4)
		gust_pulse = 1.0
	var storm_at := win_percent - 12.0
	if not bool(phase_flags["pStorm"]) and burn_percent >= storm_at:
		phase_flags["pStorm"] = true
		spread_mult = 1.6
		_show_combo("FIRESTORM! Everything catches!")
		shake = minf(shake + 0.5, 1.0)


func _update_audio(total_flames: int) -> void:
	if audio_muted or crackle == null or crackle.stream == null:
		return
	if total_flames <= 0:
		crackle.volume_db = -60.0
	else:
		crackle.volume_db = lerpf(-30.0, -10.0, clampf(float(total_flames) / 6.0, 0.0, 1.0))
	var intensity := clampf(float(total_flames) / 6.0, 0.0, 1.0)
	if music_low != null:
		music_low.volume_db = lerpf(-26.0, -14.0, intensity)
	if music_hat != null:
		music_hat.volume_db = lerpf(-34.0, -20.0, intensity)


func _update_hud() -> void:
	if fire_bar == null:
		return
	fire_bar.value = 100.0 * fire_hp / fire_hp_max
	var frac := fire_hp / fire_hp_max
	if _fill_style != null:
		_fill_style.bg_color = Color(1.0, lerpf(0.2, 0.6, frac), 0.1)
	_update_win_marker()
	ember_label.text = "Embers (MP): %d/%d — ignite 1 / gust 2" % [embers, ember_max]
	var shown := mini(embers, 6)
	for i in _ember_pips.size():
		(_ember_pips[i] as TextureRect).modulate = Color(1, 1, 1, 1) if i < shown else Color(1, 1, 1, 0.18)
	if _ember_extra != null:
		_ember_extra.text = "+%d" % (embers - 6) if embers > 6 else ""
	burn_label.text = "Cooked %d/%d · THE FIRE: %s (%d)" % [int(burn_percent), int(win_percent), _fire_name(_house_burning_count() + _chars_burning_count()), _house_burning_count() + _chars_burning_count()]
	var dirs := ["->", "SE", "v", "SW", "<-", "NW", "^", "NE"]
	var ang := atan2(wind_dir.z, wind_dir.x)
	var di := int(round(ang / (TAU / 8.0))) % 8
	var gust_txt := "  GUST READY" if _gust_cd <= 0.0 else "  gust %.1fs" % _gust_cd
	wind_label.text = "Wind %s x%.1f%s" % [dirs[di], wind_strength, gust_txt]
	if wind_flash > 0.0:
		wind_label.modulate = Color(1.0, 1.0, 0.4)
	else:
		wind_label.modulate = Color.WHITE
	if dead_fire_timer <= 0.0:
		if not has_started:
			objective_label.text = "Lv%d %s: click a GLOWING house to light your first flame (FREE - take your time!)" % [level_idx + 1, str(cfg["name"])]
		else:
			var wave_txt := "";
			match wave_phase:
				0:
					wave_txt = " · crew quiet %.0fs" % wave_timer
				1:
					wave_txt = " · CREW INBOUND!"
				2:
					wave_txt = " · CREW ASSAULT"
				_:
					wave_txt = " · crew retreating"
			objective_label.text = "Lv%d %s: cook %d%% — burning feeds THE FIRE!%s" % [level_idx + 1, str(cfg["name"]), int(win_percent), wave_txt]
	controls_label.text = "WASD/arrows pan | Q/E/wheel zoom | Click ignite | Drag gust | P pause"


func _fire_name(flames: int) -> String:
	if flames <= 0:
		return "dying"
	if flames <= 2:
		return "Spark"
	if flames <= 5:
		return "Blaze"
	if flames <= 9:
		return "Inferno"
	return "FIRESTORM"


# ---------- pause / end / progression ----------
func _toggle_pause() -> void:
	if game_over:
		return
	get_tree().paused = not get_tree().paused
	pause_panel.visible = get_tree().paused
	if get_tree().paused:
		resume_button.grab_focus()


func _rank() -> String:
	if RunState.level_time < 100.0:
		return "GORDON-APPROVED! (3 stars)"
	elif RunState.level_time < 180.0:
		return "Tasty! (2 stars)"
	return "Edible. (1 star)"


func _stats_text() -> String:
	var s := "Time: %ds | Cooked: %.0f%%\n" % [int(RunState.level_time), burn_percent]
	s += "Villagers toasted: %d | Firefighters torched: %d | Scared: %d\n" % [toasted, torched, scared]
	s += "Best combo: x%d | Peak flames: %d | Rank: %s" % [peak_combo, max_burning, _rank()]
	return s


func _end_game(did_win: bool) -> void:
	game_over = true
	won = did_win
	if rain_particles != null:
		rain_particles.emitting = false
	if did_win:
		RunState.unlocked = mini(2, maxi(RunState.unlocked, level_idx + 1))
		if level_idx < 2:
			_show_upgrade_panel()
			return
		msg_panel.show()
		msg_label.text = "CITY COOKED! YOU WIN THE RUN!\nYou consumed all three districts!\n\nLET IT COOK FOREVER!"
		stats_label.text = _run_stats_text()
		restart_button.text = "Cook Again (L1)"
		restart_button.grab_focus()
	else:
		msg_panel.show()
		msg_label.text = "Fire died... it got cold :(\n%s: cooked only %.0f%% of %d%%.\nGordon Ramsay is disappointed." % [str(cfg["name"]), burn_percent, int(win_percent)]
		stats_label.text = _stats_text()
		restart_button.text = "Retry Level %d" % [level_idx + 1]
		restart_button.grab_focus()


func _run_stats_text() -> String:
	var s := "Run time: %ds | Toasted: %d | Torched: %d\n" % [int(RunState.run_time), RunState.run_toasted, RunState.run_torched]
	s += "Upgrades:"
	if RunState.up_crispy:
		s += " Crispy"
	if RunState.up_grease:
		s += " Grease"
	if RunState.up_aura:
		s += " Aura"
	if not RunState.up_crispy and not RunState.up_grease and not RunState.up_aura:
		s += " none (speedrun!)"
	return s


func _show_upgrade_panel() -> void:
	upgrade_panel.show()
	up_crispy.text = "Extra Crispy\nHouses burn 25% faster" + (" (TAKEN)" if RunState.up_crispy else "")
	up_grease.text = "Grease Fire\n+2 max embers, +1/cook" + (" (TAKEN)" if RunState.up_grease else "")
	up_aura.text = "Marshmallow Aura\nBurning folk live longer" + (" (TAKEN)" if RunState.up_aura else "")
	up_crispy.grab_focus()


func _on_upgrade(id: String) -> void:
	if not game_over:
		return
	RunState.apply_upgrade(id)
	RunState.level = mini(2, level_idx + 1)
	level_idx = RunState.level
	cfg = LEVELS[level_idx]
	_play_pop(1.2)
	_load_level()


func _on_restart() -> void:
	get_tree().paused = false
	if won and level_idx >= 2:
		RunState.reset_run()
		level_idx = 0
		cfg = LEVELS[0]
		_load_level()
		return
	RunState.level = level_idx
	_load_level()


func _on_menu() -> void:
	get_tree().paused = false
	RunState.level = level_idx
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
