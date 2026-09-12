extends CharacterBody3D
class_name VoxelVillager
## Autonomous Villager: wanders, spots smoke/fire, forms bucket brigades.
## Flammable: catches fire when exposed, panics and screams ("AAA!!"),
## spreads fire while fleeing, can be extinguished by water, and leaves
## a charred voxel corpse on death (SPEC Section 9.1).

const CharBurnScript := preload("res://scenes/char_burn.gd")

var speed_wander: float = 1.8
var speed_panic: float = 4.2
var speed_bucket: float = 3.6
var sight_radius: float = 11.0
var panic_radius: float = 7.0
var role: String = "lookout" # lookout | bucket
var bucket_target: Node3D = null
var has_water: bool = false

var burn: CharBurn = null
var catch_cd: float = 0.0
var _dead: bool = false
var _spread_t: float = 0.0
var _shout_t: float = 0.0

var _visual: Node3D = null
var _bubble: Label3D = null
var _bucket_node: Node3D = null
var _bucket_water: MeshInstance3D = null

var _dir: Vector3 = Vector3.FORWARD
var _think_t: float = 0.0
var _bubble_t: float = 0.0
var _panicking: bool = false
var _spotted: bool = false


func _ready() -> void:
	add_to_group("villagers")
	add_to_group("flammable")
	_build()
	_build_bubble()

	burn = CharBurnScript.new()
	add_child(burn)
	burn.configure(self, _visual, 1.6, randf_range(8.5, 11.5))
	burn.died.connect(_on_burn_death)
	burn.ignited.connect(_on_burn_ignited)
	burn.extinguished.connect(_on_burn_extinguished)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	_visual.add_child(mi)
	return mi


func _build() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 1.4, 0.6)
	col.shape = shape
	col.position = Vector3(0, 0.7, 0)
	add_child(col)

	var skin := _mat(Color(0.95, 0.78, 0.62))
	var shirt := _mat(Color(0.3 + randf() * 0.6, 0.35 + randf() * 0.4, 0.5 + randf() * 0.4))
	var pants := _mat(Color(0.25, 0.25, 0.35))
	_box(Vector3(0.5, 0.55, 0.35), Vector3(0, 0.85, 0), shirt)
	_box(Vector3(0.2, 0.55, 0.2), Vector3(-0.13, 0.27, 0), pants)
	_box(Vector3(0.2, 0.55, 0.2), Vector3(0.13, 0.27, 0), pants)
	_box(Vector3(0.42, 0.38, 0.42), Vector3(0, 1.32, 0), skin)
	_box(Vector3(0.46, 0.14, 0.46), Vector3(0, 1.55, 0), _mat(Color(0.2 + randf() * 0.6, 0.15, 0.1)))


func _build_bubble() -> void:
	_bubble = Label3D.new()
	_bubble.text = "!"
	_bubble.font_size = 128
	_bubble.pixel_size = 0.012
	_bubble.modulate = Color(1.0, 0.85, 0.2)
	_bubble.outline_size = 16
	_bubble.outline_modulate = Color(0.1, 0.05, 0.05)
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.position = Vector3(0, 2.4, 0)
	_bubble.visible = false
	add_child(_bubble)


# --- Flammability & Water API (SPEC Section 9.1 & 8.4) ---
func ignite() -> bool:
	if burn == null or _dead:
		return false
	return burn.ignite()


func apply_water(amount: float, delta: float) -> void:
	if burn != null:
		burn.apply_water(amount, delta)


func is_burning() -> bool:
	return burn != null and burn.is_burning


func _on_burn_ignited() -> void:
	clear_bucket()
	_panicking = true
	_show_bubble("AAA!!", Color(1.0, 0.3, 0.1))


func _on_burn_extinguished() -> void:
	_show_bubble("PHEW!", Color(0.3, 0.8, 1.0))


func _on_burn_death() -> void:
	if _dead:
		return
	_dead = true
	clear_bucket()
	if is_in_group("villagers"):
		remove_from_group("villagers")
	if is_in_group("flammable"):
		remove_from_group("flammable")
	queue_free()


# --- Bucket Brigade API (SPEC Section 9.2) ---
func set_bucket(t: Node3D) -> void:
	if is_burning() or _dead:
		return
	role = "bucket"
	bucket_target = t
	has_water = false
	_build_bucket()
	_update_bucket_visual()
	_show_bubble("💧", Color(0.4, 0.7, 1.0))


func clear_bucket() -> void:
	role = "lookout"
	bucket_target = null
	has_water = false
	if _bucket_node != null and is_instance_valid(_bucket_node):
		_bucket_node.queue_free()
		_bucket_node = null
	_bucket_water = null


func is_bucket() -> bool:
	return role == "bucket" and not is_burning()


func _build_bucket() -> void:
	if _bucket_node != null and is_instance_valid(_bucket_node):
		return
	if _visual == null:
		return
	_bucket_node = Node3D.new()
	_bucket_node.name = "Bucket"
	_bucket_node.position = Vector3(0.38, 0.85, 0.2)
	_visual.add_child(_bucket_node)

	# Wood bucket casing
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.32, 0.34, 0.32)
	bm.material = _mat(Color(0.48, 0.32, 0.18))
	mi.mesh = bm
	_bucket_node.add_child(mi)

	# Water inside bucket
	var wm := MeshInstance3D.new()
	var wbm := BoxMesh.new()
	wbm.size = Vector3(0.26, 0.08, 0.26)
	wbm.material = _mat(Color(0.25, 0.62, 0.95))
	wm.mesh = wbm
	wm.position = Vector3(0, 0.12, 0)
	_bucket_node.add_child(wm)
	_bucket_water = wm


func _update_bucket_visual() -> void:
	if _bucket_water != null and is_instance_valid(_bucket_water):
		_bucket_water.visible = has_water


func has_spotted() -> bool:
	return _spotted


func is_panicking() -> bool:
	return _panicking or is_burning()


# --- Physics & Behavior ---
func _physics_process(delta: float) -> void:
	if _dead:
		return

	catch_cd = maxf(0.0, catch_cd - delta)
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0 and _bubble != null:
			_bubble.visible = false

	# If burning: panic, flee, shout, spread fire (SPEC 9.1)
	if is_burning():
		_physics_flee_burning(delta)
		return

	# Catch fire proximity check
	_check_catch_fire()
	if is_burning():
		return

	if role == "bucket":
		_physics_bucket(delta)
		return

	_physics_wander(delta)


func _physics_flee_burning(delta: float) -> void:
	# Running while on fire!
	_spread_t -= delta
	if _spread_t <= 0.0:
		_spread_t = 0.75
		_spread_fire()

	_shout_t -= delta
	if _shout_t <= 0.0:
		_shout_t = randf_range(1.2, 2.0)
		var shouts := ["AAA!!", "FIRE!!", "HOT!!", "HELP!"]
		_show_bubble(shouts[randi() % shouts.size()], Color(1.0, 0.3, 0.08))

	_think_t -= delta
	if _think_t <= 0.0:
		_think_t = randf_range(0.25, 0.5)
		# Away from nearest burning house or random erratic direction
		var away := Vector3.ZERO
		for h in get_tree().get_nodes_in_group("houses"):
			if h is VoxelHouse and h.state == VoxelHouse.State.BURNING:
				var to: Vector3 = global_position - (h as Node3D).global_position
				to.y = 0.0
				var d := to.length()
				if d < 10.0 and d > 0.01:
					away += to.normalized() * (1.0 - d / 10.0)
		away.y = 0.0
		if away.length() < 0.05:
			away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		_dir = (away + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))).normalized()

	if absf(global_position.x) > 17.0 or absf(global_position.z) > 17.0:
		_dir = (-global_position.normalized())

	velocity = _dir * (speed_panic * 1.25)
	if _dir.length_squared() > 0.01:
		_visual.rotation.y = atan2(_dir.x, _dir.z)
	_visual.position.y = absf(sin(Time.get_ticks_msec() * 0.032)) * 0.16
	move_and_slide()


func _spread_fire() -> void:
	# Spreads fire to nearby combustible structures and other characters
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.UNBURNED:
			if global_position.distance_to(h.global_position) < 2.5:
				if randf() < 0.25:
					h.heat = minf(1.0, h.heat + 0.5)
					if h.heat >= 1.0:
						h.ignite()
					break

	for c in get_tree().get_nodes_in_group("villagers"):
		if c != self and c is VoxelVillager and not (c as VoxelVillager).is_burning():
			if global_position.distance_to((c as Node3D).global_position) < 1.5:
				if randf() < 0.25:
					(c as VoxelVillager).ignite()

	for f in get_tree().get_nodes_in_group("firefighters"):
		if f is Node3D and f.has_method("ignite") and not f.is_burning():
			if global_position.distance_to(f.global_position) < 1.5:
				if randf() < 0.25:
					f.ignite()


func _check_catch_fire() -> void:
	if catch_cd > 0.0:
		return
	# Catch fire from burning structures
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.BURNING:
			if global_position.distance_to(h.global_position) < 2.3:
				if randf() < 0.16:
					catch_cd = 0.8
					ignite()
					return

	# Catch fire from burning people
	for c in get_tree().get_nodes_in_group("burning_chars"):
		if c is Node3D and c != self:
			if global_position.distance_to((c as Node3D).global_position) < 1.5:
				if randf() < 0.22:
					catch_cd = 0.8
					ignite()
					return


func _physics_bucket(delta: float) -> void:
	# Multi-stage Bucket Loop (SPEC Section 6.7 & 9.2):
	# 1. If empty bucket: path to nearest WaterSource -> fill bucket.
	# 2. If full bucket: path to burning target -> douse fire -> return to water source.
	_think_t -= delta

	# Check target validity
	if bucket_target == null or not is_instance_valid(bucket_target) or (bucket_target as VoxelHouse).state != VoxelHouse.State.BURNING:
		bucket_target = _find_nearest_burning_house()
		if bucket_target == null:
			# No burning houses left, idle
			velocity = Vector3.ZERO
			move_and_slide()
			return

	if not has_water:
		# Step 1: Head to water source to fetch water
		var source := _find_nearest_water_source()
		var target_pos := source.global_position if source != null else global_position
		var to_source := target_pos - global_position
		to_source.y = 0.0
		var dist := to_source.length()

		if dist > 2.0 and source != null:
			_dir = to_source.normalized()
			velocity = _dir * speed_bucket
		else:
			# At water source! Fill bucket.
			velocity = Vector3.ZERO
			has_water = true
			_update_bucket_visual()
			_show_bubble("💧", Color(0.3, 0.7, 1.0))
	else:
		# Step 2: Carry water to burning house and splash
		var to_target := (bucket_target as Node3D).global_position - global_position
		to_target.y = 0.0
		var dist := to_target.length()

		if dist > 3.4:
			_dir = to_target.normalized()
			velocity = _dir * speed_bucket
		else:
			# At target! Splash water.
			velocity = Vector3.ZERO
			var h := bucket_target as VoxelHouse
			h.apply_water(2.2, 1.0)
			SoundManager.play_sfx("splash")

			# Also rescue nearby burning characters
			for c in get_tree().get_nodes_in_group("burning_chars"):
				if is_instance_valid(c) and c is Node3D and c != self:
					if (c as Node3D).global_position.distance_to(global_position) <= 4.2:
						if c.has_method("apply_water"):
							c.apply_water(2.5, 1.0)

			has_water = false
			_update_bucket_visual()
			_show_bubble("~", Color(0.4, 0.7, 1.0))

	if _dir.length_squared() > 0.01:
		_visual.rotation.y = atan2(_dir.x, _dir.z)
	_visual.position.y = absf(sin(Time.get_ticks_msec() * 0.016)) * 0.09
	move_and_slide()


func _find_nearest_water_source() -> Node3D:
	var sources := get_tree().get_nodes_in_group("water_sources")
	var best: Node3D = null
	var best_d := 1e9
	for s in sources:
		if is_instance_valid(s) and s is Node3D:
			var d := global_position.distance_to((s as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = s as Node3D
	return best


func _find_nearest_burning_house() -> VoxelHouse:
	var best: VoxelHouse = null
	var best_d := 1e9
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.BURNING:
			var d := global_position.distance_to((h as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = h
	return best


func _physics_wander(delta: float) -> void:
	_think_t -= delta

	# Nearest burning building sight/panic check
	var nearest_d := 1e9
	var nearest_pos := Vector3.ZERO
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.BURNING:
			var d := global_position.distance_to((h as Node3D).global_position)
			if d < nearest_d:
				nearest_d = d
				nearest_pos = (h as Node3D).global_position

	if nearest_d < sight_radius:
		if not _spotted:
			_spotted = true
			_show_bubble("!")
		elif nearest_d < sight_radius * 0.6:
			_show_bubble("!")

	_panicking = nearest_d < panic_radius
	var spd := speed_panic if _panicking else speed_wander

	if _think_t <= 0.0:
		_think_t = 0.35 if _panicking else randf_range(1.0, 2.2)
		if _panicking:
			var away: Vector3 = global_position - nearest_pos
			away.y = 0.0
			_dir = away.normalized() if away.length() > 0.01 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		else:
			if randf() < 0.35:
				var home: Vector3 = -global_position
				home.y = 0.0
				_dir = home.normalized() if home.length() > 1.0 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			else:
				_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()

	if absf(global_position.x) > 16.0 or absf(global_position.z) > 16.0:
		_dir = (-global_position.normalized())
		_think_t = 1.0

	velocity = _dir * spd
	if _dir.length_squared() > 0.01:
		_visual.rotation.y = atan2(_dir.x, _dir.z)
	_visual.position.y = absf(sin(Time.get_ticks_msec() * (0.02 if _panicking else 0.008))) * (0.12 if _panicking else 0.05)
	move_and_slide()


func _show_bubble(txt: String, col: Color = Color(1.0, 0.85, 0.2)) -> void:
	if _bubble == null:
		return
	_bubble.text = txt
	_bubble.modulate = col
	_bubble.visible = true
	_bubble_t = 1.6
