extends Node3D
## Let It Cook — Strategy Fire Deity Master Orchestrator (SPEC Section 19).
## Coordinates level loading, player input, abilities, economy, and UI,
## delegating simulation, encounters, weather, and builders to dedicated modules.

# Ember economy (SPEC Section 6.5)
const EMBER_START: int = 2
const EMBER_MAX: int = 5
const EMBER_REWARD_COOLDOWN: float = 8.0
const ANTI_STALL_DELAY: float = 12.0
const MANUAL_IGNITE_COST: int = 3
const WIND_GUST_COST: int = 1
const LAST_SPARK_COST: int = 1

# Local Wind Gust ability (SPEC Section 6.6, 7.3 & 7.4)
const WIND_COOLDOWN_MAX: float = 6.0
const WIND_GUST_DURATION: float = 4.0
const WIND_GUST_RANGE: float = 8.5
const WIND_GUST_HALF_ANGLE: float = deg_to_rad(30.0) # 60-degree cone total

var level_idx: int = 0
var level_name: String = ""
var level_sub: String = ""

# Level references
var houses: Array[VoxelHouse] = []
var mandatory_houses: Array[VoxelHouse] = []
var barrels: Array[VoxelBarrel] = []
var starter_house: VoxelHouse = null
var shaman: VoxelShaman = null

var burnt_mandatory: int = 0
var burn_percent: float = 0.0

# Subsystems
var fire_sim: FireSimulation = null
var weather: WeatherSystem = null
var director: EncounterDirector = null

# Economy & ability state
var embers: int = EMBER_START
var ember_reward_timer: float = 0.0
var anti_stall_timer: float = 0.0
var starter_ignited: bool = false

# Wind Gust state
var wind_cooldown: float = 0.0
var aiming_wind: bool = false
var wind_aim_origin: Vector3 = Vector3.ZERO
var wind_aim_dir: Vector3 = Vector3.FORWARD
var wind_aim_dist: float = 0.0
var wind_aim_valid: bool = false

var active_gust_timer: float = 0.0
var active_gust_origin: Vector3 = Vector3.ZERO
var active_gust_dir: Vector3 = Vector3.FORWARD
var active_gust_visual: Node3D = null

var wind_cone_preview: MeshInstance3D = null
var wind_cone_mesh: ImmediateMesh = null
var wind_cone_mat: StandardMaterial3D = null

# Fire strength & Last Spark (SPEC Section 6.9 & 8.3)
var fire_strength: float = 60.0
var last_spark_available: bool = true
var last_spark_active: bool = false
var last_spark_house: VoxelHouse = null
var last_spark_timer: float = 0.0

# Camera & loop state
var camera_shake_trauma: float = 0.0
var game_over: bool = false
var won: bool = false
var elapsed: float = 0.0
var cam_bound: float = 16.0
var edge_pan: bool = false

# Scene nodes
@onready var rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var village_root: Node3D = $Village
@onready var units_root: Node3D = $Units

# HUD nodes
@onready var fire_bar: ProgressBar = %FireBar
@onready var ember_label: Label = %EmberLabel
@onready var burn_label: Label = %BurnLabel
@onready var wind_label: Label = %WindLabel
@onready var hint_label: Label = %HintLabel
@onready var objective_label: Label = %ObjectiveLabel
@onready var controls_label: Label = %ControlsLabel
@onready var combo_label: Label = %ComboLabel
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
	_setup_input_actions()
	level_idx = clampi(RunState.level, 0, 2)
	edge_pan = RunState.edge_pan

	_setup_subsystems()
	_setup_hud()
	_setup_wind_cone_preview()

	if not restart_button.pressed.is_connected(_on_restart):
		restart_button.pressed.connect(_on_restart)
	if not menu_button.pressed.is_connected(_on_menu):
		menu_button.pressed.connect(_on_menu)
	if not resume_button.pressed.is_connected(_toggle_pause):
		resume_button.pressed.connect(_toggle_pause)
	if not pause_menu_button.pressed.is_connected(_on_menu):
		pause_menu_button.pressed.connect(_on_menu)

	var up := get_node_or_null("HUD/UpgradePanel") as PanelContainer
	if up != null:
		up.hide()

	_load_level()


func _setup_subsystems() -> void:
	fire_sim = FireSimulation.new()

	weather = WeatherSystem.new()
	weather.name = "WeatherSystem"
	add_child(weather)

	director = EncounterDirector.new()
	director.name = "EncounterDirector"
	add_child(director)
	director.hint_requested.connect(_flash_hint)


func _setup_input_actions() -> void:
	_register_action("camera_up", [KEY_W, KEY_UP])
	_register_action("camera_down", [KEY_S, KEY_DOWN])
	_register_action("camera_left", [KEY_A, KEY_LEFT])
	_register_action("camera_right", [KEY_D, KEY_RIGHT])
	_register_action("camera_zoom_in", [KEY_E, KEY_EQUAL])
	_register_action("camera_zoom_out", [KEY_Q, KEY_MINUS])
	_register_action("pause", [KEY_ESCAPE, KEY_P])


func _register_action(action_name: String, keys: Array) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
		for k in keys:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action_name, ev)


func _setup_hud() -> void:
	if fire_bar != null:
		fire_bar.show()
		fire_bar.min_value = 0.0
		fire_bar.max_value = 100.0
		fire_bar.value = 60.0
	var fl := get_node_or_null("HUD/TopBar/Margin/HBox/FireLabel") as Label
	if fl == null:
		fl = get_node_or_null("HUD/TopBar/HBox/FireLabel") as Label
	if fl != null:
		fl.show()
		fl.text = "FIRE"
	if wind_label != null:
		wind_label.show()
	if combo_label != null:
		combo_label.hide()
	msg_panel.hide()
	pause_panel.hide()


func _setup_wind_cone_preview() -> void:
	if wind_cone_preview != null and is_instance_valid(wind_cone_preview):
		return
	wind_cone_preview = MeshInstance3D.new()
	wind_cone_preview.name = "WindConePreview"
	wind_cone_mesh = ImmediateMesh.new()
	wind_cone_preview.mesh = wind_cone_mesh

	wind_cone_mat = StandardMaterial3D.new()
	wind_cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wind_cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wind_cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wind_cone_mat.albedo_color = Color(1.0, 0.55, 0.1, 0.4)

	add_child(wind_cone_preview)
	wind_cone_preview.hide()


# ---------- Level Loading & Lifecycle ----------
func _load_level() -> void:
	_clear_level()
	game_over = false
	won = false
	elapsed = 0.0
	RunState.level_time = 0.0

	# Embers and abilities
	embers = EMBER_START
	ember_reward_timer = 0.0
	anti_stall_timer = 0.0
	wind_cooldown = 0.0
	active_gust_timer = 0.0
	aiming_wind = false
	_hide_wind_cone_preview()

	# Fire strength & Last Spark
	fire_strength = 60.0
	last_spark_available = true
	last_spark_active = false
	last_spark_house = null
	last_spark_timer = 0.0

	# Build Level geometry & actors via LevelBuilder
	var ctx := LevelBuilder.build_level(level_idx, village_root, units_root)
	level_name = ctx.name
	level_sub = ctx.sub
	cam_bound = ctx.cam_bound
	camera.size = ctx.camera_size
	rig.position = Vector3.ZERO

	houses = ctx.houses
	mandatory_houses = ctx.mandatory_houses
	barrels = ctx.barrels
	starter_house = ctx.starter_house
	shaman = ctx.shaman
	starter_ignited = false

	# Wire house signals
	for h in houses:
		h.burned_out.connect(_on_house_burned_out)
		h.burn_ending.connect(_on_house_burn_ending)

	# Wire barrel signals
	for b in barrels:
		b.exploded.connect(_on_barrel_exploded)

	# Wire shaman signals
	if shaman != null and is_instance_valid(shaman):
		shaman.ritual_completed.connect(_on_shaman_ritual_completed)
		shaman.ritual_interrupted.connect(_on_shaman_ritual_interrupted)
		shaman.defeated.connect(_on_shaman_defeated)

	# Initialize subsystems
	fire_sim.setup(houses, barrels)
	fire_sim.wind_shifted.connect(func(_d: Vector3) -> void: _flash_hint("Prevailing wind shifting — watch the compass arrow."))
	weather.setup(houses, barrels, cam_bound)
	director.setup(level_idx, units_root, houses, cam_bound, shaman)

	msg_panel.hide()
	pause_panel.hide()
	get_tree().paused = false

	_flash_hint("Tip: First fire is free on the starter house. Observe the wind direction before sparking.")
	_update_hud()


func _clear_level() -> void:
	_hide_wind_cone_preview()
	if active_gust_visual != null and is_instance_valid(active_gust_visual):
		active_gust_visual.queue_free()
		active_gust_visual = null

	starter_house = null
	starter_ignited = false
	last_spark_house = null
	shaman = null

	if weather != null:
		weather.cleanup()

	for c in village_root.get_children():
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			c.queue_free()
	for c in units_root.get_children():
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			c.queue_free()

	houses.clear()
	mandatory_houses.clear()
	barrels.clear()
	burnt_mandatory = 0
	burn_percent = 0.0
	camera_shake_trauma = 0.0
	camera.h_offset = 0.0
	camera.v_offset = 0.0


# ---------- Per-frame Game Loop ----------
func _process(delta: float) -> void:
	_update_camera(delta)
	if game_over:
		return

	elapsed += delta
	RunState.run_time += delta
	RunState.level_time += delta

	# Ability & reward timers
	if wind_cooldown > 0.0:
		wind_cooldown = maxf(0.0, wind_cooldown - delta)
	if ember_reward_timer > 0.0:
		ember_reward_timer = maxf(0.0, ember_reward_timer - delta)

	# Active gust visual lifetime
	if active_gust_timer > 0.0:
		active_gust_timer = maxf(0.0, active_gust_timer - delta)
		if active_gust_timer <= 0.0 and active_gust_visual != null and is_instance_valid(active_gust_visual):
			active_gust_visual.queue_free()
			active_gust_visual = null

	# Camera trauma shake decay
	if camera_shake_trauma > 0.0:
		camera_shake_trauma = maxf(0.0, camera_shake_trauma - delta * 2.2)
		camera.h_offset = randf_range(-1.0, 1.0) * camera_shake_trauma * 0.45
		camera.v_offset = randf_range(-1.0, 1.0) * camera_shake_trauma * 0.45
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0

	# Subsystems tick
	fire_sim.tick(delta, weather.rain_active)
	weather.tick(delta, rig.position)

	var burning_count := fire_sim.count_burning()
	var smoldering_count := fire_sim.count_smoldering()

	director.tick(delta, elapsed, starter_ignited, burning_count, game_over)
	SoundManager.update_fire_crackle(burning_count)

	# Weather dampens fire strength
	if weather.rain_active:
		fire_strength = move_toward(fire_strength, 18.0, 7.0 * delta)

	# Anti-stall Ember rule (SPEC Section 6.5)
	if embers == 0 and burning_count > 0:
		anti_stall_timer += delta
		if anti_stall_timer >= ANTI_STALL_DELAY:
			anti_stall_timer = 0.0
			embers = mini(embers + 1, EMBER_MAX)
			_flash_hint("Anti-stall Spark: +1 Ember (%d/%d)" % [embers, EMBER_MAX])
	else:
		anti_stall_timer = 0.0

	# Fire Strength update (SPEC Section 8.3)
	if burning_count > 0:
		var target := clampf(20.0 + float(burning_count) * 16.0, 10.0, 100.0)
		fire_strength = move_toward(fire_strength, target, 20.0 * delta)
	elif smoldering_count > 0:
		fire_strength = move_toward(fire_strength, 15.0, 15.0 * delta)
	else:
		fire_strength = move_toward(fire_strength, 0.0, 30.0 * delta)

	# 100% Mandatory structure progress (SPEC Section 11.4)
	burnt_mandatory = 0
	for h in mandatory_houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.BURNT:
			burnt_mandatory += 1

	burn_percent = 100.0 * float(burnt_mandatory) / float(maxi(1, mandatory_houses.size()))

	# Win check: 100% of ordinary combustible settlement structures destroyed
	if burnt_mandatory >= mandatory_houses.size():
		_end_game(true)
		return

	# Failure check: no flames and Last Spark either consumed or expired
	if starter_ignited and not game_over:
		if last_spark_active:
			last_spark_timer -= delta
			if last_spark_timer <= 0.0 or last_spark_house == null or last_spark_house.state == VoxelHouse.State.BURNT:
				last_spark_active = false
				if fire_sim.count_burning() == 0:
					_end_game(false)
					return
		elif burning_count == 0 and smoldering_count == 0:
			if not last_spark_available:
				_end_game(false)
				return

	_update_hud()


# ---------- Event & Signal Handlers ----------
func _on_house_burn_ending(h: VoxelHouse) -> void:
	if game_over or not starter_ignited:
		return

	var other_burning := 0
	for other in houses:
		if is_instance_valid(other) and other != h and other.state == VoxelHouse.State.BURNING:
			other_burning += 1

	if other_burning == 0 and last_spark_available and burnt_mandatory < mandatory_houses.size():
		last_spark_available = false
		last_spark_active = true
		last_spark_house = h
		last_spark_timer = 8.0
		h.start_smolder(8.0)
		_flash_hint("LAST SPARK! Final fire smoldering (8s) — Click house to reignite for 1 Ember!")
		_update_hud()


func _on_house_burned_out(h: VoxelHouse) -> void:
	if game_over:
		return
	if is_instance_valid(h) and h.kind == "house":
		if ember_reward_timer <= 0.0:
			if embers < EMBER_MAX:
				embers = mini(embers + 1, EMBER_MAX)
				ember_reward_timer = EMBER_REWARD_COOLDOWN
				_flash_hint("House consumed! +1 Ember (%d/%d)" % [embers, EMBER_MAX])
		else:
			_flash_hint("House consumed!")
	else:
		_flash_hint("Forest fuse burnt through.")
	_update_hud()


func _on_barrel_exploded(_b: VoxelBarrel) -> void:
	camera_shake_trauma = minf(1.0, camera_shake_trauma + 0.65)
	if embers < EMBER_MAX:
		embers = mini(embers + 1, EMBER_MAX)
		_flash_hint("BOOM! Explosive barrel detonated (+1 Ember, %d/%d)!" % [embers, EMBER_MAX])
	else:
		_flash_hint("BOOM! Explosive barrel detonated!")
	_update_hud()


func _on_shaman_ritual_completed(_s: VoxelShaman) -> void:
	weather.start_rain(25.0)
	_flash_hint("TORRENTIAL RAIN SUMMONED! (25s) Spreading fire is severely dampened.")


func _on_shaman_ritual_interrupted(_s: VoxelShaman) -> void:
	_flash_hint("RITUAL INTERRUPTED! Shaman caught fire and fled!")
	_update_hud()


func _on_shaman_defeated(_s: VoxelShaman) -> void:
	if embers < EMBER_MAX:
		embers = mini(embers + 1, EMBER_MAX)
		_flash_hint("Shaman defeated with fire! +1 Ember (%d/%d)" % [embers, EMBER_MAX])
	else:
		_flash_hint("Shaman defeated with fire!")
	_update_hud()


# ---------- Camera Control (SPEC Section 14.1) ----------
func _update_camera(delta: float) -> void:
	var pan := Vector2.ZERO
	if Input.is_action_pressed("camera_left"):
		pan.x -= 1.0
	if Input.is_action_pressed("camera_right"):
		pan.x += 1.0
	if Input.is_action_pressed("camera_up"):
		pan.y -= 1.0
	if Input.is_action_pressed("camera_down"):
		pan.y += 1.0

	var fwd := -camera.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	if pan != Vector2.ZERO:
		rig.position += (right * pan.x - fwd * pan.y) * delta * 14.0
		rig.position.x = clampf(rig.position.x, -cam_bound, cam_bound)
		rig.position.z = clampf(rig.position.z, -cam_bound, cam_bound)

	if Input.is_action_pressed("camera_zoom_in"):
		_zoom_step(-8.0 * delta)
	if Input.is_action_pressed("camera_zoom_out"):
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
			rig.position += (right * ep.x - fwd * ep.y) * delta * 12.0
			rig.position.x = clampf(rig.position.x, -cam_bound, cam_bound)
			rig.position.z = clampf(rig.position.z, -cam_bound, cam_bound)


func _zoom_step(amount: float) -> void:
	camera.size = clampf(camera.size + amount, 8.0, 40.0)


# ---------- Desktop Input & Abilities (SPEC Section 14.1 & 7.4) ----------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if aiming_wind:
			aiming_wind = false
			_hide_wind_cone_preview()
			_flash_hint("Wind aim cancelled.")
			get_viewport().set_input_as_handled()
			return
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
			_handle_left_click(mb.position)
			return

		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_start_wind_aim(mb.position)
			else:
				_release_wind_aim()
			return

	elif event is InputEventMouseMotion:
		if aiming_wind:
			_update_wind_aim(event.position)


func _handle_left_click(screen_pos: Vector2) -> void:
	var obj := _pick_object(screen_pos)
	if obj == null:
		return

	if obj is VoxelBarrel:
		_flash_hint("Barrels cannot be ignited manually! Route fire to them to detonate.")
		return

	if obj is VoxelShaman:
		_flash_hint("Shaman is immune to direct clicks! Route fire to the ritual court to interrupt.")
		return

	if not (obj is VoxelHouse):
		return

	var house: VoxelHouse = obj as VoxelHouse

	if not starter_ignited:
		if house == starter_house:
			starter_house.set_starter(false)
			starter_house.ignite()
			starter_ignited = true
			_flash_hint("Fire sparked! Direct spread with Wind Gust (Hold RMB on flames).")
			_update_hud()
		else:
			_flash_hint("First fire must be on the highlighted STARTER house!")
		return

	if house.state == VoxelHouse.State.SMOLDERING:
		if embers >= LAST_SPARK_COST:
			embers -= LAST_SPARK_COST
			house.reignite(35.0)
			last_spark_active = false
			last_spark_house = null
			_flash_hint("Last Spark caught! Fire restored! (-1 Ember)")
			_update_hud()
		else:
			_flash_hint("Need 1 Ember to reignite Last Spark! (Have 0)")
		return

	if house.state == VoxelHouse.State.UNBURNED:
		if embers >= MANUAL_IGNITE_COST:
			embers -= MANUAL_IGNITE_COST
			house.ignite()
			_flash_hint("Manual Ignition sparked! (-3 Embers, %d remaining)" % embers)
			_update_hud()
		else:
			_flash_hint("Manual Ignition costs 3 Embers! (Have %d) Guide fire with Wind instead." % embers)


func _start_wind_aim(screen_pos: Vector2) -> void:
	var obj := _pick_object(screen_pos)
	var house: VoxelHouse = obj as VoxelHouse if obj is VoxelHouse else null
	var origin := Vector3.ZERO
	var found := false

	if house != null and (house.state == VoxelHouse.State.BURNING or house.state == VoxelHouse.State.SMOLDERING):
		origin = house.global_position
		found = true
	else:
		var ground_pos := _raycast_plane_y(screen_pos, 0.0)
		var nearest_d := 4.5
		for h in houses:
			if is_instance_valid(h) and (h.state == VoxelHouse.State.BURNING or h.state == VoxelHouse.State.SMOLDERING):
				var d := ground_pos.distance_to(h.global_position)
				if d < nearest_d:
					nearest_d = d
					origin = h.global_position
					found = true

	if found:
		aiming_wind = true
		wind_aim_origin = origin
		wind_aim_dir = Vector3.FORWARD
		wind_aim_valid = false
		_update_wind_cone_preview(wind_aim_origin, wind_aim_dir, false)
	else:
		if fire_sim.count_burning() > 0:
			_flash_hint("Wind Gust must originate from an active BURNING structure!")
		else:
			_flash_hint("No active fire to cast wind from!")


func _update_wind_aim(screen_pos: Vector2) -> void:
	var mouse_world := _raycast_plane_y(screen_pos, wind_aim_origin.y)
	var vec := mouse_world - wind_aim_origin
	vec.y = 0.0
	wind_aim_dist = vec.length()

	if wind_aim_dist >= 1.0:
		wind_aim_valid = true
		wind_aim_dir = vec.normalized()
	else:
		wind_aim_valid = false

	_update_wind_cone_preview(wind_aim_origin, wind_aim_dir, wind_aim_valid)


func _release_wind_aim() -> void:
	if not aiming_wind:
		return
	aiming_wind = false
	_hide_wind_cone_preview()

	if wind_aim_valid:
		if embers >= WIND_GUST_COST and wind_cooldown <= 0.0:
			embers -= WIND_GUST_COST
			wind_cooldown = WIND_COOLDOWN_MAX
			_cast_wind_gust(wind_aim_origin, wind_aim_dir)
			_flash_hint("Wind Gust released! 4s intense spread downwind.")
			_update_hud()
		elif wind_cooldown > 0.0:
			_flash_hint("Wind Gust on cooldown (%.1fs)!" % wind_cooldown)
		else:
			_flash_hint("Need 1 Ember to cast Wind Gust!")
	else:
		_flash_hint("Drag further from the fire to establish wind direction.")


func _cast_wind_gust(origin: Vector3, dir: Vector3) -> void:
	active_gust_origin = origin
	active_gust_dir = dir
	active_gust_timer = WIND_GUST_DURATION
	fire_sim.cast_gust(origin, dir)
	_spawn_gust_visual(origin, dir)
	SoundManager.play_sfx("wind_gust")


func _spawn_gust_visual(origin: Vector3, dir: Vector3) -> void:
	if active_gust_visual != null and is_instance_valid(active_gust_visual):
		active_gust_visual.queue_free()

	var p := GPUParticles3D.new()
	p.name = "GustParticles"
	p.amount = 40
	p.lifetime = 0.85
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 6, 20))

	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = 24.0
	pm.initial_velocity_min = 10.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3(0, 0.4, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.color = Color(1.0, 0.75, 0.2, 0.85)
	p.process_material = pm

	var b := BoxMesh.new()
	b.size = Vector3(0.12, 0.12, 0.28)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.1)
	mat.emission_energy_multiplier = 2.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b.material = mat
	p.draw_pass_1 = b

	add_child(p)
	p.global_position = origin + Vector3(0, 0.6, 0)
	active_gust_visual = p


func _update_wind_cone_preview(origin: Vector3, dir: Vector3, valid: bool) -> void:
	if wind_cone_mesh == null:
		return
	wind_cone_mesh.clear_surfaces()

	var col: Color
	if not valid:
		col = Color(1.0, 0.8, 0.2, 0.2)
	elif embers < WIND_GUST_COST:
		col = Color(0.9, 0.2, 0.2, 0.3)
	elif wind_cooldown > 0.0:
		col = Color(0.5, 0.5, 0.5, 0.3)
	else:
		col = Color(1.0, 0.6, 0.15, 0.45)

	wind_cone_mat.albedo_color = col
	wind_cone_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, wind_cone_mat)

	var half_angle := WIND_GUST_HALF_ANGLE
	var base_angle := atan2(dir.x, dir.z)
	var segments := 20
	var radius := WIND_GUST_RANGE
	var y_off := 0.25
	var center := origin + Vector3(0, y_off, 0)

	for i in segments:
		var f1 := float(i) / float(segments)
		var f2 := float(i + 1) / float(segments)
		var a1 := base_angle - half_angle + f1 * (half_angle * 2.0)
		var a2 := base_angle - half_angle + f2 * (half_angle * 2.0)
		var p1 := origin + Vector3(sin(a1) * radius, y_off, cos(a1) * radius)
		var p2 := origin + Vector3(sin(a2) * radius, y_off, cos(a2) * radius)

		wind_cone_mesh.surface_add_vertex(center)
		wind_cone_mesh.surface_add_vertex(p1)
		wind_cone_mesh.surface_add_vertex(p2)

	# Center aiming arrow
	var p_mid := origin + Vector3(sin(base_angle) * (radius + 0.6), y_off, cos(base_angle) * (radius + 0.6))
	var p_left := origin + Vector3(sin(base_angle - 0.09) * radius * 0.8, y_off, cos(base_angle - 0.09) * radius * 0.8)
	var p_right := origin + Vector3(sin(base_angle + 0.09) * radius * 0.8, y_off, cos(base_angle + 0.09) * radius * 0.8)
	wind_cone_mesh.surface_add_vertex(p_mid)
	wind_cone_mesh.surface_add_vertex(p_left)
	wind_cone_mesh.surface_add_vertex(p_right)

	wind_cone_mesh.surface_end()
	wind_cone_preview.show()

	# Highlight structures inside cone that receive boosted heat
	if valid and embers >= WIND_GUST_COST and wind_cooldown <= 0.0:
		for h in houses:
			if is_instance_valid(h) and h.state == VoxelHouse.State.UNBURNED:
				var to_h := h.global_position - origin
				to_h.y = 0.0
				if to_h.length() <= radius and to_h.normalized().dot(dir) >= cos(half_angle):
					h._flash = maxf(h._flash, 0.4)
		for b in barrels:
			if is_instance_valid(b) and b.state == VoxelBarrel.State.UNBURNED:
				var to_b := b.global_position - origin
				to_b.y = 0.0
				if to_b.length() <= radius and to_b.normalized().dot(dir) >= cos(half_angle):
					b.add_heat(0.04)


func _hide_wind_cone_preview() -> void:
	if wind_cone_preview != null and is_instance_valid(wind_cone_preview):
		wind_cone_preview.hide()


# ---------- Raycast Helpers ----------
func _pick_object(screen_pos: Vector2) -> Object:
	if camera == null:
		return null
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 200.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 2
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	return hit.get("collider")


func _raycast_plane_y(screen_pos: Vector2, plane_y: float) -> Vector3:
	if camera == null:
		return Vector3.ZERO
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return from
	var t := (plane_y - from.y) / dir.y
	return from + dir * t


# ---------- HUD Presentation ----------
var _hint_t: float = 0.0

func _flash_hint(text: String) -> void:
	if hint_label == null:
		return
	hint_label.text = text
	hint_label.modulate.a = 1.0
	_hint_t = 3.0


func _update_hud() -> void:
	if fire_bar != null:
		fire_bar.value = fire_strength

	if ember_label != null:
		var extra := ""
		if embers == 0 and fire_sim.count_burning() > 0:
			extra = " (+1 anti-stall in %ds)" % int(ceil(ANTI_STALL_DELAY - anti_stall_timer))
		ember_label.text = "Embers: %d / %d%s" % [embers, EMBER_MAX, extra]

	if burn_label != null:
		burn_label.text = "Settlement: %d / %d (100%% Goal)" % [burnt_mandatory, mandatory_houses.size()]

	if wind_label != null:
		var gust_str := ""
		if active_gust_timer > 0.0:
			gust_str = "ACTIVE (%.1fs)" % active_gust_timer
		elif wind_cooldown > 0.0:
			gust_str = "CD %.1fs" % wind_cooldown
		else:
			gust_str = "Ready (1 Ember, RMB)"
		var rain_str := " | RAIN: %ds" % int(ceil(weather.rain_timer)) if weather.rain_active else ""
		wind_label.text = "Wind: %s %s | Gust: %s%s" % [fire_sim.get_wind_arrow(), fire_sim.get_wind_word(), gust_str, rain_str]

	if objective_label != null and not game_over:
		var spark_status := "READY"
		if last_spark_active:
			spark_status = "ACTIVE (%.1fs)!" % maxf(0.0, last_spark_timer)
		elif not last_spark_available:
			spark_status = "USED"

		if not starter_ignited:
			objective_label.text = "SPARK PHASE: Click the highlighted STARTER house to begin"
		elif last_spark_active:
			objective_label.text = "CRITICAL: LAST SPARK SMOLDERING (%.1fs)! Click house to save (1 Ember)!" % maxf(0.0, last_spark_timer)
		elif shaman != null and is_instance_valid(shaman) and shaman.state == VoxelShaman.State.CASTING:
			objective_label.text = "THREAT: SHAMAN RITUAL! Rain in %.1fs — Route fire to ritual court to interrupt!" % shaman.cast_time_remaining
		elif weather.rain_active:
			objective_label.text = "WEATHER: Torrential Rain (%.1fs) — Spread dampened! Burn %d/%d houses." % [weather.rain_timer, burnt_mandatory, mandatory_houses.size()]
		else:
			objective_label.text = "Lv%d %s: Burn 100%% of settlement houses (%d/%d) · Last Spark: %s" % [level_idx + 1, level_name, burnt_mandatory, mandatory_houses.size(), spark_status]

	if controls_label != null:
		controls_label.text = "LMB: Ignite (Starter free / Manual 3) | RMB Drag: Wind Gust (1 Ember) | WASD: Pan | Q/E: Zoom | P: Pause"

	if _hint_t > 0.0:
		_hint_t -= get_process_delta_time()
		if _hint_t <= 0.0 and hint_label != null:
			hint_label.modulate.a = 0.45


# ---------- Pause / Game End ----------
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
	get_tree().paused = true
	msg_panel.show()

	if did_win:
		RunState.unlocked = mini(2, maxi(RunState.unlocked, level_idx + 1))
		if level_idx < 2:
			msg_label.text = "%s FULLY COOKED!\nAll %d settlement structures consumed." % [level_name, mandatory_houses.size()]
			stats_label.text = "Time: %ds | Embers remaining: %d\nProceed to Level %d." % [int(RunState.level_time), embers, level_idx + 2]
			restart_button.text = "Advance to Lv%d" % [level_idx + 2]
		else:
			msg_label.text = "ALL DISTRICTS COOKED!\nYOU WIN THE DISASTER CAMPAIGN!"
			stats_label.text = "Total Run Time: %ds | Fire deity victorious." % int(RunState.run_time)
			restart_button.text = "Play Again (L1)"
	else:
		msg_label.text = "FIRE EXTINGUISHED!\nThe settlement survived the disaster."
		stats_label.text = "%s: Burnt %d of %d houses (%d%%)\nTime: %ds | Replan your route and fronts." % [level_name, burnt_mandatory, mandatory_houses.size(), int(burn_percent), int(RunState.level_time)]
		restart_button.text = "Retry Level %d" % [level_idx + 1]

	restart_button.grab_focus()


func _on_restart() -> void:
	get_tree().paused = false
	if won and level_idx < 2:
		RunState.level = level_idx + 1
		level_idx = RunState.level
		_load_level()
		return
	RunState.level = level_idx
	_load_level()


func _on_menu() -> void:
	get_tree().paused = false
	RunState.level = level_idx
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
