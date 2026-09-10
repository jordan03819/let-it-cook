extends CharacterBody3D
class_name VoxelFirefighter
## Voxel firefighter: seeks nearest burning house, sprays voxel water cubes.
## FLAMMABLE: catches fire near flames; while burning, PANICS and flees
## instead of spraying, and can spread fire. Water spray also rescues
## burning characters.

signal retired(f: VoxelFirefighter)
signal torched(f: VoxelFirefighter)

const CharBurnScript := preload("res://scenes/char_burn.gd")

var speed: float = 4.2
var speed_flee: float = 5.0
var spray_range: float = 4.5
var spray_rate: float = 0.85
var courage: float = 1.0
var elite: bool = false # L3 elites: faster, more spray, braver
var target_house: VoxelHouse = null
var home_pos: Vector3 = Vector3.ZERO
var burn: CharBurn = null
var _retarget_t: float = 0.0
var _spread_t: float = 0.0
var catch_cd: float = 0.0
var _dead: bool = false
var _visual: Node3D = null
var _water_particles: GPUParticles3D = null
var _spraying: bool = false
var retreating: bool = false # wave over: walk home, clock out
var _retreat_t: float = 0.0


func _ready() -> void:
	add_to_group("firefighters")
	add_to_group("flammable")
	_build_visuals()
	_build_water()
	if elite:
		speed = 5.2
		spray_rate = 1.3
		courage = 1.6
	burn = CharBurnScript.new()
	add_child(burn)
	burn.configure(self, _visual, 1.9, randf_range(5.0, 6.0))
	burn.died.connect(_on_burn_death)


func _voxel_mat(c: Color, emit: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	if emit:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.2
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_visuals() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var col := CollisionShape3D.new()
	var cap := BoxShape3D.new()
	cap.size = Vector3(0.7, 1.6, 0.7)
	col.shape = cap
	col.position = Vector3(0, 0.8, 0)
	add_child(col)
	var coat := Color(0.85, 0.7, 0.35) if not elite else Color(0.2, 0.25, 0.85)
	_box(_visual, Vector3(0.22, 0.5, 0.22), Vector3(-0.15, 0.25, 0), _voxel_mat(Color(0.1, 0.15, 0.4)))
	_box(_visual, Vector3(0.22, 0.5, 0.22), Vector3(0.15, 0.25, 0), _voxel_mat(Color(0.1, 0.15, 0.4)))
	_box(_visual, Vector3(0.7, 0.7, 0.45), Vector3(0, 0.85, 0), _voxel_mat(coat))
	_box(_visual, Vector3(0.72, 0.15, 0.47), Vector3(0, 0.85, 0), _voxel_mat(Color(1.0, 0.9, 0.2), true))
	_box(_visual, Vector3(0.45, 0.4, 0.45), Vector3(0, 1.4, 0), _voxel_mat(Color(0.95, 0.75, 0.6)))
	_box(_visual, Vector3(0.6, 0.25, 0.6), Vector3(0, 1.68, 0), _voxel_mat(Color(0.85, 0.15, 0.1) if not elite else Color(0.9, 0.75, 0.1)))
	_box(_visual, Vector3(0.62, 0.08, 0.62), Vector3(0, 1.56, 0), _voxel_mat(Color(0.7, 0.1, 0.08)))
	_box(_visual, Vector3(0.15, 0.15, 0.7), Vector3(0.3, 1.0, 0.4), _voxel_mat(Color(0.3, 0.3, 0.32)))


func _build_water() -> void:
	_water_particles = GPUParticles3D.new()
	_water_particles.amount = 32
	_water_particles.lifetime = 0.7
	_water_particles.local_coords = false
	_water_particles.emitting = false
	_water_particles.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 6, 16))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.3, 1)
	pm.spread = 12.0
	pm.initial_velocity_min = 9.0
	pm.initial_velocity_max = 13.0
	pm.gravity = Vector3(0, -9.0, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.4
	pm.color = Color(0.3, 0.6, 1.0)
	_water_particles.process_material = pm
	var cube := BoxMesh.new()
	cube.size = Vector3(0.14, 0.14, 0.14)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.65, 1.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cube.material = m
	_water_particles.draw_pass_1 = cube
	_water_particles.position = Vector3(0.3, 1.0, 0.6)
	add_child(_water_particles)


func ignite() -> bool:
	if burn == null or _dead:
		return false
	return burn.ignite()


func apply_water(amount: float, delta: float) -> void:
	if burn != null:
		burn.apply_water(amount, delta)


func is_burning() -> bool:
	return burn != null and burn.is_burning


func is_spraying() -> bool:
	return _spraying and not is_burning() and not _dead


func begin_retreat() -> void:
	if _dead or is_burning():
		return
	retreating = true
	_retreat_t = 14.0
	target_house = null
	_set_spray(false)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	catch_cd = maxf(0.0, catch_cd - delta)
	if retreating and not is_burning():
		_retreat_t -= delta
		_set_spray(false)
		var to_home := home_pos - global_position
		to_home.y = 0.0
		if to_home.length() < 1.5 or _retreat_t <= 0.0:
			retired.emit(self)
			queue_free()
			return
		_move(to_home.normalized(), delta)
		return
	if is_burning():
		_physics_flee(delta)
		return
	_retarget_t -= delta
	if _retarget_t <= 0.0 or not is_instance_valid(target_house) or target_house.state != VoxelHouse.State.BURNING:
		target_house = _find_best_fire()
		_retarget_t = 0.7
		_check_catch_fire()

	if target_house == null or not is_instance_valid(target_house):
		_set_spray(false)
		var to_home := home_pos - global_position
		to_home.y = 0.0
		if to_home.length() > 1.0:
			_move(to_home.normalized(), delta)
		return

	var to_target: Vector3 = target_house.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist < 2.2 / courage:
		_move(-to_target.normalized(), delta)
		_spray_at(target_house, delta)
		return

	if dist <= spray_range:
		_face(to_target)
		velocity = Vector3.ZERO
		move_and_slide()
		_spray_at(target_house, delta)
	else:
		_set_spray(false)
		_move(to_target.normalized(), delta)


func _physics_flee(delta: float) -> void:
	# ON FIRE: panic! No spraying, just run from flames + spread fire.
	_set_spray(false)
	_spread_t -= delta
	if _spread_t <= 0.0:
		_spread_t = 0.9
		_spread_fire()
	var away := Vector3.ZERO
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.BURNING:
			var to: Vector3 = global_position - h.global_position
			to.y = 0.0
			var d := to.length()
			if d < 9.0 and d > 0.01:
				away += to.normalized() * (1.0 - d / 9.0)
	away.y = 0.0
	if away.length() < 0.05:
		away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	_face(away.normalized())
	velocity = away.normalized() * speed_flee
	_visual.position.y = absf(sin(Time.get_ticks_msec() * 0.03)) * 0.16
	move_and_slide()


func _check_catch_fire() -> void:
	if catch_cd > 0.0:
		return
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.BURNING:
			if global_position.distance_to(h.global_position) < 2.6 / courage:
				if randf() < randf_range(0.12, 0.18):
					catch_cd = 0.7
					ignite()
					return
	for c in get_tree().get_nodes_in_group("burning_chars"):
		if c is Node3D and c != self:
			if global_position.distance_to((c as Node3D).global_position) < 1.5:
				if randf() < 0.20:
					catch_cd = 0.7
					ignite()
					return


func _spread_fire() -> void:
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.UNBURNED:
			if global_position.distance_to(h.global_position) < 2.6:
				if randf() < 0.20:
					if h.ignite():
						break
	for c in get_tree().get_nodes_in_group("villagers"):
		if c is VoxelVillager and not (c as VoxelVillager).is_burning():
			if global_position.distance_to((c as Node3D).global_position) < 1.5:
				if randf() < 0.20:
					(c as VoxelVillager).ignite()
	for c in get_tree().get_nodes_in_group("firefighters"):
		if c != self and c is VoxelFirefighter and not (c as VoxelFirefighter).is_burning():
			if global_position.distance_to((c as Node3D).global_position) < 1.5:
				if randf() < 0.20:
					(c as VoxelFirefighter).ignite()


func _move(dir: Vector3, _delta: float) -> void:
	_face(dir)
	velocity = dir * speed
	_visual.position.y = absf(sin(Time.get_ticks_msec() * 0.012)) * 0.08
	move_and_slide()


func _face(dir: Vector3) -> void:
	if dir.length_squared() > 0.001:
		var yaw := atan2(dir.x, dir.z)
		_visual.rotation.y = yaw
		_water_particles.rotation.y = yaw


func _find_best_fire() -> VoxelHouse:
	var best: VoxelHouse = null
	var best_d := 1e9
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.BURNING:
			var d: float = global_position.distance_squared_to(h.global_position)
			if d < best_d:
				best_d = d
				best = h
	return best


func _spray_at(house: VoxelHouse, delta: float) -> void:
	_set_spray(true)
	house.apply_water(spray_rate, delta)
	# Hose water also rescues burning characters near the spray or self.
	for c in get_tree().get_nodes_in_group("burning_chars"):
		if c is Node3D and c != self:
			var cp := (c as Node3D).global_position
			if cp.distance_to(house.global_position) < 4.0 or cp.distance_to(global_position) < 3.0:
				if c is VoxelVillager:
					(c as VoxelVillager).apply_water(1.4, delta)
				elif c is VoxelFirefighter:
					(c as VoxelFirefighter).apply_water(1.4, delta)


func _set_spray(v: bool) -> void:
	_spraying = v
	if is_instance_valid(_water_particles):
		_water_particles.emitting = v


func _on_burn_death() -> void:
	if _dead:
		return
	_dead = true
	_set_spray(false)
	if is_in_group("firefighters"):
		remove_from_group("firefighters")
	if is_in_group("flammable"):
		remove_from_group("flammable")
	torched.emit(self)
	retired.emit(self)
	queue_free()
