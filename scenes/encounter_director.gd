class_name EncounterDirector
extends Node
## EncounterDirector — Encapsulates responder pacing, alarm escalation,
## bucket brigade coordination, firefighter waves, and ritual timing (SPEC Section 6.2, 9 & 19).

signal firefighter_warning_triggered()
signal firefighter_wave_deployed()
signal shaman_ritual_alert_triggered()
signal helicopter_drop_warning(target_pos: Vector3, duration: float)
signal helicopter_drop_executed(target_pos: Vector3, radius: float)
signal hint_requested(text: String)

const FIREFIGHTER_SCENE := preload("res://scenes/firefighter.tscn")
const HELICOPTER_SCENE := preload("res://scenes/helicopter.tscn")
const BUCKET_MAX: int = 3
const HOUSE_RADIUS: float = 4.8

var level_idx: int = 0
var units_root: Node3D = null
var houses: Array[VoxelHouse] = []
var cam_bound: float = 16.0
var shaman: VoxelShaman = null

var spotted: bool = false
var alarm: float = 0.0
var _buckets_warned: bool = false
var firefighter_warned: bool = false
var firefighter_spawned: bool = false
var elite_warned: bool = false
var elite_spawned: bool = false
var shaman_ritual_triggered: bool = false

var helicopter_active: bool = false
var helicopter_timer: float = 0.0
var helicopter_cooldown: float = 48.0
var helicopter_target_pos: Vector3 = Vector3.ZERO
var _no_fire_timer: float = 0.0


func setup(p_level_idx: int, p_units_root: Node3D, p_houses: Array[VoxelHouse], p_cam_bound: float, p_shaman: VoxelShaman) -> void:
	level_idx = p_level_idx
	units_root = p_units_root
	houses = p_houses
	cam_bound = p_cam_bound
	shaman = p_shaman

	spotted = false
	alarm = 0.0
	_buckets_warned = false
	firefighter_warned = false
	firefighter_spawned = false
	elite_warned = false
	elite_spawned = false
	shaman_ritual_triggered = false
	helicopter_active = false
	helicopter_timer = 0.0
	helicopter_cooldown = 48.0
	helicopter_target_pos = Vector3.ZERO
	_no_fire_timer = 0.0


func tick(delta: float, elapsed: float, starter_ignited: bool, burning_count: int, game_over: bool) -> void:
	if game_over:
		return

	_tick_alarm(delta, burning_count)
	_tick_buckets(delta, burning_count, game_over)

	if starter_ignited and not game_over:
		if firefighter_spawned and burning_count == 0:
			_no_fire_timer += delta
			if _no_fire_timer >= 6.0:
				for f in get_tree().get_nodes_in_group("firefighters"):
					if is_instance_valid(f) and f is VoxelFirefighter and not (f as VoxelFirefighter).retreating:
						(f as VoxelFirefighter).begin_retreat()
		else:
			_no_fire_timer = 0.0

		_tick_firefighter_escalation(elapsed)
		_tick_shaman_ritual(elapsed, burning_count)
		_tick_helicopter(delta, elapsed, burning_count)


func _tick_alarm(delta: float, burning_count: int) -> void:
	for v in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(v) and v is VoxelVillager and (v as VoxelVillager).has_spotted():
			if not spotted:
				spotted = true
				hint_requested.emit("Spotted! Villagers noticed smoke. Response incoming.")
			break

	var target := 0.0
	if spotted:
		target = clampf(25.0 + float(burning_count) * 15.0, 0.0, 100.0)
	else:
		target = clampf(float(burning_count) * 6.0, 0.0, 15.0)

	if target > alarm:
		alarm = minf(target, alarm + 8.0 * delta)
	else:
		alarm = maxf(target, alarm - 2.5 * delta)


func _bucket_count() -> int:
	var n := 0
	for v in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(v) and v is VoxelVillager and (v as VoxelVillager).is_bucket():
			n += 1
	return n


func _pick_bucket_target() -> VoxelHouse:
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


func _tick_buckets(_delta: float, burning_count: int, game_over: bool) -> void:
	var allowed := 0
	if (spotted or alarm >= 25.0) and burning_count >= 1:
		allowed = 1
	if alarm >= 45.0 and burning_count >= 2:
		allowed = 2
	if alarm >= 65.0 and burning_count >= 3:
		allowed = 3
	allowed = mini(allowed, BUCKET_MAX)

	if allowed > 0 and burning_count >= 1 and not game_over:
		var have := _bucket_count()
		if have < allowed:
			for v in get_tree().get_nodes_in_group("villagers"):
				if have >= allowed:
					break
				if is_instance_valid(v) and v is VoxelVillager and not (v as VoxelVillager).is_bucket() and not (v as VoxelVillager).is_burning():
					var tgt := _pick_bucket_target()
					if tgt == null:
						break
					(v as VoxelVillager).set_bucket(tgt)
					have += 1
					if not _buckets_warned:
						_buckets_warned = true
						hint_requested.emit("Bucket carriers formed a brigade! Fetching water to cool homes.")

	# Keep bucket targets updated
	for v in get_tree().get_nodes_in_group("villagers"):
		if not (is_instance_valid(v) and v is VoxelVillager and (v as VoxelVillager).is_bucket()):
			continue
		var vv := v as VoxelVillager
		if vv.bucket_target == null or not is_instance_valid(vv.bucket_target) or (vv.bucket_target as VoxelHouse).state != VoxelHouse.State.BURNING:
			vv.bucket_target = _pick_bucket_target() if burning_count > 0 else null


func _tick_firefighter_escalation(elapsed: float) -> void:
	var warn_time := 80.0
	var spawn_time := 85.0
	var alarm_threshold := 70.0

	if level_idx == 1:
		warn_time = 45.0
		spawn_time = 50.0
		alarm_threshold = 50.0
	elif level_idx == 2:
		warn_time = 32.0
		spawn_time = 37.0
		alarm_threshold = 38.0

	if not firefighter_warned and not firefighter_spawned:
		if elapsed >= warn_time or (alarm >= alarm_threshold and elapsed >= warn_time - 15.0):
			firefighter_warned = true
			SoundManager.play_sfx("siren")
			hint_requested.emit("SIRENS! Official firefighters dispatched — arriving on the road in 5s!")
			firefighter_warning_triggered.emit()
	elif firefighter_warned and not firefighter_spawned:
		if elapsed >= spawn_time or (alarm >= alarm_threshold and elapsed >= warn_time - 10.0):
			firefighter_spawned = true
			_spawn_firefighter_wave(false)
			firefighter_wave_deployed.emit()

	# City Wave 2: Elite Firefighters (SPEC Section 6.10 & 11.3)
	if level_idx == 2 and firefighter_spawned and not elite_spawned:
		var elite_warn_t := 75.0
		var elite_spawn_t := 80.0
		if not elite_warned:
			if elapsed >= elite_warn_t or (alarm >= 65.0 and elapsed >= elite_warn_t - 15.0):
				elite_warned = true
				SoundManager.play_sfx("siren")
				hint_requested.emit("HIGH ALERT! Elite Metropolitan Firefighters responding in 5s!")
		else:
			if elapsed >= elite_spawn_t or (alarm >= 65.0 and elapsed >= elite_warn_t - 10.0):
				elite_spawned = true
				_spawn_firefighter_wave(true)
				firefighter_wave_deployed.emit()


func _spawn_firefighter_wave(is_elite: bool = false) -> void:
	if units_root == null:
		return
	var road_z: float = -cam_bound + 1.5
	var positions: Array[Vector3] = []
	if level_idx == 1:
		positions = [Vector3(-7.5, 0, road_z), Vector3(7.5, 0, road_z), Vector3(-7.5, 0, -road_z)]
	elif level_idx == 2:
		if is_elite:
			positions = [Vector3(-1.8, 0, cam_bound - 3.0), Vector3(1.8, 0, cam_bound - 3.0), Vector3(13.0, 0, cam_bound - 3.0)]
		else:
			positions = [Vector3(-1.2, 0, cam_bound - 3.0), Vector3(1.2, 0, cam_bound - 3.0), Vector3(0.0, 0, cam_bound - 3.0)]
	else:
		positions = [Vector3(-1.2, 0, road_z), Vector3(1.2, 0, road_z)]

	for p in positions:
		var ff: VoxelFirefighter = FIREFIGHTER_SCENE.instantiate()
		if is_elite:
			ff.elite = true
		units_root.add_child(ff)
		ff.position = p
		ff.home_pos = p

	if is_elite:
		hint_requested.emit("ELITE FIREFIGHTERS DEPLOYED! High-pressure blue squad reinforcing the defense!")
	else:
		hint_requested.emit("FIREFIGHTERS DEPLOYED! High-pressure water hoses attacking flames.")


func _tick_shaman_ritual(elapsed: float, burning_count: int) -> void:
	if level_idx == 1 and shaman != null and is_instance_valid(shaman) and not shaman_ritual_triggered:
		if alarm >= 30.0 or elapsed >= 38.0 or burning_count >= 2:
			shaman_ritual_triggered = true
			shaman.start_ritual()
			hint_requested.emit("RITUAL ALARM! Shaman in the Northeast court is summoning rain!")
			shaman_ritual_alert_triggered.emit()


# ---------- City Helicopter Water Drop (SPEC Section 6.7, 10.3 & 11.3) ----------
func _tick_helicopter(delta: float, elapsed: float, burning_count: int) -> void:
	if level_idx != 2:
		return

	if helicopter_active:
		helicopter_timer = maxf(0.0, helicopter_timer - delta)
		return

	if helicopter_cooldown > 0.0:
		helicopter_cooldown = maxf(0.0, helicopter_cooldown - delta)
		return

	# Trigger condition: City level, elapsed >= 48s, at least 2 burning houses
	if elapsed >= 48.0 and burning_count >= 2:
		var target := _pick_helicopter_target()
		if target != null:
			_launch_helicopter_drop(target.global_position)


func _pick_helicopter_target() -> VoxelHouse:
	var best: VoxelHouse = null
	var best_score := -1
	for src in houses:
		if not is_instance_valid(src) or src.state != VoxelHouse.State.BURNING or src.kind == "stone":
			continue
		var score := 0
		for other in houses:
			if not is_instance_valid(other) or other.kind == "stone":
				continue
			if src.global_position.distance_to(other.global_position) <= 6.5:
				if other.state == VoxelHouse.State.BURNING:
					score += 3
				elif other.state == VoxelHouse.State.UNBURNED and other.heat > 0.1:
					score += 1
		if score > best_score:
			best_score = score
			best = src
	return best


func _launch_helicopter_drop(drop_pos: Vector3) -> void:
	if units_root == null:
		return

	helicopter_active = true
	helicopter_timer = 5.0
	helicopter_cooldown = 55.0
	helicopter_target_pos = drop_pos

	var flight_dir := Vector3(1.0, 0.0, -1.0).normalized() # Screen-space horizontal pass
	var start_pos := drop_pos - flight_dir * 32.0 + Vector3(0, 6.8, 0)
	var exit_pos := drop_pos + flight_dir * 34.0 + Vector3(0, 6.8, 0)

	var heli: VoxelHelicopter = HELICOPTER_SCENE.instantiate()
	units_root.add_child(heli)
	heli.setup(start_pos, drop_pos, exit_pos, 5.0, 6.5)

	heli.drop_executed.connect(func(pos: Vector3, rad: float) -> void:
		helicopter_active = false
		helicopter_drop_executed.emit(pos, rad)
		hint_requested.emit("AERIAL WATER IMPACT! Local fire cluster doused!")
	)

	SoundManager.play_sfx("helicopter")
	hint_requested.emit("AERIAL THREAT! City helicopter incoming — 5s warning on highlighted cluster!")
	helicopter_drop_warning.emit(drop_pos, 5.0)
