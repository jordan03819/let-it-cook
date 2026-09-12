class_name EncounterDirector
extends Node
## EncounterDirector — Encapsulates responder pacing, alarm escalation,
## bucket brigade coordination, firefighter waves, and ritual timing (SPEC Section 6.2, 9 & 19).

signal firefighter_warning_triggered()
signal firefighter_wave_deployed()
signal shaman_ritual_alert_triggered()
signal hint_requested(text: String)

const FIREFIGHTER_SCENE := preload("res://scenes/firefighter.tscn")
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
var shaman_ritual_triggered: bool = false


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
	shaman_ritual_triggered = false


func tick(delta: float, elapsed: float, starter_ignited: bool, burning_count: int, game_over: bool) -> void:
	if game_over:
		return

	_tick_alarm(delta, burning_count)
	_tick_buckets(delta, burning_count, game_over)

	if starter_ignited and not game_over:
		_tick_firefighter_escalation(elapsed)
		_tick_shaman_ritual(elapsed, burning_count)


func _tick_alarm(delta: float, burning_count: int) -> void:
	for v in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(v) and v is VoxelVillager and (v as VoxelVillager).has_spotted():
			if not spotted:
				spotted = true
				hint_requested.emit("Spotted! Villagers noticed smoke. Response incoming.")
			break

	var target := 0.0
	if spotted:
		target = clampf(20.0 + float(burning_count) * 15.0, 0.0, 100.0)
	else:
		target = clampf(float(burning_count) * 4.0, 0.0, 12.0)

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
	if alarm >= 40.0 and burning_count >= 1:
		allowed = 1
	if alarm >= 60.0 and burning_count >= 2:
		allowed = 2
	if alarm >= 75.0 and burning_count >= 5:
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
	var warn_time := 45.0 if level_idx == 1 else 80.0
	var spawn_time := 50.0 if level_idx == 1 else 85.0
	var alarm_threshold := 50.0 if level_idx == 1 else 70.0

	if not firefighter_warned and not firefighter_spawned:
		if elapsed >= warn_time or (alarm >= alarm_threshold and elapsed >= warn_time - 15.0):
			firefighter_warned = true
			SoundManager.play_sfx("siren")
			hint_requested.emit("SIRENS! Official firefighters dispatched — arriving on the road in 5s!")
			firefighter_warning_triggered.emit()
	elif firefighter_warned and not firefighter_spawned:
		if elapsed >= spawn_time or (alarm >= alarm_threshold and elapsed >= warn_time - 10.0):
			firefighter_spawned = true
			_spawn_firefighter_wave()
			firefighter_wave_deployed.emit()


func _spawn_firefighter_wave() -> void:
	if units_root == null:
		return
	var road_z: float = -cam_bound + 1.5
	var positions: Array[Vector3] = []
	if level_idx == 1:
		positions = [Vector3(-7.5, 0, road_z), Vector3(7.5, 0, road_z), Vector3(-7.5, 0, -road_z)]
	else:
		positions = [Vector3(-1.2, 0, road_z), Vector3(1.2, 0, road_z)]

	for p in positions:
		var ff: VoxelFirefighter = FIREFIGHTER_SCENE.instantiate()
		units_root.add_child(ff)
		ff.position = p
		ff.home_pos = p

	hint_requested.emit("FIREFIGHTERS DEPLOYED! High-pressure water hoses attacking flames.")


func _tick_shaman_ritual(elapsed: float, burning_count: int) -> void:
	if level_idx == 1 and shaman != null and is_instance_valid(shaman) and not shaman_ritual_triggered:
		if alarm >= 30.0 or elapsed >= 38.0 or burning_count >= 2:
			shaman_ritual_triggered = true
			shaman.start_ritual()
			hint_requested.emit("RITUAL ALARM! Shaman in the Northeast court is summoning rain!")
			shaman_ritual_alert_triggered.emit()
