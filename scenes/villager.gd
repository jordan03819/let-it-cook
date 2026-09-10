extends CharacterBody3D
class_name VoxelVillager
## Voxel villager: wanders, panics near fire, may drop lantern.
## FLAMMABLE: catches fire near flames, runs screaming while burning,
## spreads fire to houses + other characters, dies into charred voxels.

signal toasted(v: VoxelVillager)

const CharBurnScript := preload("res://scenes/char_burn.gd")

var speed_wander: float = 1.6
var speed_panic: float = 4.0
var speed_burning: float = 3.4
var panic_radius: float = 7.0
var catch_house_radius: float = 3.4
var catch_char_radius: float = 2.2

var burn: CharBurn = null
var _visual: Node3D = null
var _panic: bool = false
var _dead: bool = false
var _dir: Vector3 = Vector3.FORWARD
var _think_t: float = 0.0
var _spread_t: float = 0.0
var catch_cd: float = 0.0
var _dropped: bool = false


func _ready() -> void:
	add_to_group("villagers")
	add_to_group("flammable")
	_build()
	burn = CharBurnScript.new()
	add_child(burn)
	burn.configure(self, _visual, 1.7, randf_range(10.0, 13.0))
	_build_scream_bubble()
	burn.ignited.connect(_on_ignite)
	burn.died.connect(_on_burn_death)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	_visual.add_child(mi)


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


func ignite() -> bool:
	if burn == null or _dead:
		return false
	return burn.ignite()


func apply_water(amount: float, delta: float) -> void:
	if burn != null:
		burn.apply_water(amount, delta)


func is_burning() -> bool:
	return burn != null and burn.is_burning


func _physics_process(delta: float) -> void:
	if _dead:
		return
	catch_cd = maxf(0.0, catch_cd - delta)
	if is_burning():
		_physics_burning(delta)
		return
	_think_t -= delta
	# Nearest burning house for panic
	var nearest_d := 1e9
	var nearest_pos := Vector3.ZERO
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.BURNING:
			var d := global_position.distance_to(h.global_position)
			if d < nearest_d:
				nearest_d = d
				nearest_pos = h.global_position
	# Burning characters are scary too
	for c in get_tree().get_nodes_in_group("burning_chars"):
		if c is Node3D and c != self:
			var d := global_position.distance_to((c as Node3D).global_position)
			if d < nearest_d:
				nearest_d = d
				nearest_pos = (c as Node3D).global_position
	_panic = nearest_d < panic_radius
	var spd := speed_panic if _panic else speed_wander
	if _think_t <= 0.0:
		_think_t = randf_range(0.8, 2.0) if not _panic else 0.4
		if _panic:
			var away: Vector3 = global_position - nearest_pos
			away.y = 0.0
			_dir = away.normalized() if away.length() > 0.01 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			if not _dropped and randf() < 0.12:
				_dropped = true
				_try_ignite_neighbor()
		else:
			_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		_check_catch_fire()
	if absf(global_position.x) > 14.0 or absf(global_position.z) > 14.0:
		_dir = (-global_position.normalized())
	velocity = _dir * spd
	if _dir.length_squared() > 0.01:
		_visual.rotation.y = atan2(_dir.x, _dir.z)
	_visual.position.y = absf(sin(Time.get_ticks_msec() * (0.02 if _panic else 0.008))) * (0.12 if _panic else 0.05)
	move_and_slide()


func _physics_burning(delta: float) -> void:
	# Screaming + stumbling zigzag; half the time charges TOWARD fresh houses
	# (arson run) so burning villagers visibly spread the fire.
	_think_t -= delta
	_spread_t -= delta
	if _think_t <= 0.0:
		_think_t = randf_range(0.4, 0.8)
		var goal := _away_from_flames()
		if randf() < 0.5:
			var charge := _toward_fresh_house()
			if charge.length_squared() > 0.01:
				goal = charge
		var jitter := Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
		_dir = (goal + jitter).normalized() if (goal + jitter).length() > 0.01 else _dir
		if absf(global_position.x) > 14.0 or absf(global_position.z) > 14.0:
			_dir = (-global_position.normalized())
	if _spread_t <= 0.0:
		_spread_t = 0.9
		_spread_fire()
	velocity = _dir * speed_burning
	if _dir.length_squared() > 0.01:
		_visual.rotation.y = atan2(_dir.x, _dir.z)
	_visual.position.y = absf(sin(Time.get_ticks_msec() * 0.03)) * 0.16
	move_and_slide()


func _toward_fresh_house() -> Vector3:
	var best := Vector3.ZERO
	var best_d := 9.0
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.UNBURNED:
			var to: Vector3 = (h as Node3D).global_position - global_position
			to.y = 0.0
			var d := to.length()
			if d < best_d and d > 0.01:
				best_d = d
			best = to.normalized()
	return best


func _away_from_flames() -> Vector3:
	var away := Vector3.ZERO
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.BURNING:
			var to: Vector3 = global_position - h.global_position
			to.y = 0.0
			var d := to.length()
			if d < 8.0 and d > 0.01:
				away += to.normalized() * (1.0 - d / 8.0)
	return away.normalized() if away.length() > 0.01 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()


func _check_catch_fire() -> void:
	# Clumsy villagers: hang around fire and WILL catch (0.38 + 0.3s CD).
	if catch_cd > 0.0:
		return
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.BURNING:
			if global_position.distance_to(h.global_position) < catch_house_radius:
				if randf() < 0.38:
					catch_cd = 0.3
					ignite()
					return
	for c in get_tree().get_nodes_in_group("burning_chars"):
		if c is Node3D and c != self:
			if global_position.distance_to((c as Node3D).global_position) < catch_char_radius:
				if randf() < 0.35:
					catch_cd = 0.3
					ignite()
					return


func _spread_fire() -> void:
	# Burning villager ignites nearby houses (0.30 / 3.0m / 0.9s) + chars.
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.UNBURNED:
			if global_position.distance_to(h.global_position) < 3.0:
				if randf() < 0.30:
					if h.ignite():
						break
	for c in get_tree().get_nodes_in_group("villagers"):
		if c != self and c is VoxelVillager and not (c as VoxelVillager).is_burning():
			if global_position.distance_to((c as Node3D).global_position) < 1.5:
				if randf() < 0.20:
					(c as VoxelVillager).ignite()
	for c in get_tree().get_nodes_in_group("firefighters"):
		if c is VoxelFirefighter and not (c as VoxelFirefighter).is_burning():
			if global_position.distance_to((c as Node3D).global_position) < 1.5:
				if randf() < 0.20:
					(c as VoxelFirefighter).ignite()


func _try_ignite_neighbor() -> void:
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.UNBURNED:
			if global_position.distance_to(h.global_position) < 4.0:
				h.ignite()
				break


func _build_scream_bubble() -> void:
	var lab := Label3D.new()
	lab.name = "ScreamBubble"
	lab.text = "AAA!!"
	lab.font_size = 96
	lab.pixel_size = 0.011
	lab.modulate = Color(1.0, 0.85, 0.2)
	lab.outline_size = 16
	lab.outline_modulate = Color(0.1, 0.05, 0.05)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.position = Vector3(0, 2.7, 0)
	lab.visible = false
	add_child(lab)


func _on_ignite() -> void:
	_think_t = 0.0
	_spread_t = 0.3
	var bubble := get_node_or_null("ScreamBubble")
	if bubble is Label3D:
		(bubble as Label3D).visible = true


func _on_burn_death() -> void:
	if _dead:
		return
	_dead = true
	if is_in_group("villagers"):
		remove_from_group("villagers")
	if is_in_group("flammable"):
		remove_from_group("flammable")
	toasted.emit(self)
	queue_free()
