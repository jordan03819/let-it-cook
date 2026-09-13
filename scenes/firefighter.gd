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
var commit_timer: float = 0.0
const COMMITMENT_MIN: float = 6.0
var _spread_t: float = 0.0
var catch_cd: float = 0.0
var _dead: bool = false
var _visual: Node3D = null
var _bubble: Label3D = null
var _bubble_t: float = 0.0
var _shout_t: float = 0.0
var _water_particles: GPUParticles3D = null
var _spraying: bool = false
var retreating: bool = false # wave over: walk home, clock out
var _retreat_t: float = 0.0

var _telegraph_root: Node3D = null
var _aim_line_instance: MeshInstance3D = null
var _aim_line_mesh: ImmediateMesh = null
var _reticle_instance: MeshInstance3D = null
var _reticle_mesh: ImmediateMesh = null
var _telegraph_mat: StandardMaterial3D = null


func _ready() -> void:
	add_to_group("firefighters")
	add_to_group("flammable")
	_build_visuals()
	_build_water()
	_build_bubble()
	_build_telegraph()
	if elite:
		speed = 5.2
		spray_rate = 1.3
		courage = 1.6
	burn = CharBurnScript.new()
	add_child(burn)
	burn.configure(self, _visual, KitCharacter.RESPONDER_HEIGHT, randf_range(5.0, 6.0))
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
	# A rigged Mini Character in a responder's colours (assets/chars): the kit's
	# own walk/idle/die clips carry the movement that the old box stack mimed by
	# bobbing up and down.
	_visual = KitCharacter.build(
		KitCharacter.model_for(3 if not elite else 8),
		KitCharacter.RESPONDER_HEIGHT,
		_responser_tint())
	add_child(_visual)

	var col := CollisionShape3D.new()
	var cap := BoxShape3D.new()
	cap.size = Vector3(0.6, KitCharacter.RESPONDER_HEIGHT, 0.6)
	col.shape = cap
	col.position = Vector3(0, KitCharacter.RESPONDER_HEIGHT * 0.5, 0)
	add_child(col)


## Responders wear the campaign's colours so they read at a glance: yellow kit
## for the volunteers, cold blue for the elite crews.
func _responser_tint() -> Color:
	return Color(0.72, 0.86, 1.05) if elite else Color(1.12, 1.0, 0.78)


## Keeps the crew animated: they run when working, idle on the spot.
func _animate(moving: bool) -> void:
	if _visual == null:
		return
	if moving:
		KitCharacter.play(_visual, KitCharacter.CLIP_WALK, 1.1)
	else:
		KitCharacter.play(_visual, KitCharacter.CLIP_IDLE)

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


func _build_telegraph() -> void:
	_telegraph_root = Node3D.new()
	_telegraph_root.name = "FirefighterTelegraph"
	_telegraph_root.top_level = true
	add_child(_telegraph_root)

	_telegraph_mat = StandardMaterial3D.new()
	_telegraph_mat.albedo_color = Color(0.25, 0.75, 1.0, 0.6)
	_telegraph_mat.emission_enabled = true
	_telegraph_mat.emission = Color(0.2, 0.68, 0.95)
	_telegraph_mat.emission_energy_multiplier = 1.5
	_telegraph_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_telegraph_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Aim line connecting firefighter to committed target house (SPEC 6.7)
	_aim_line_mesh = ImmediateMesh.new()
	_aim_line_instance = MeshInstance3D.new()
	_aim_line_instance.mesh = _aim_line_mesh
	_telegraph_root.add_child(_aim_line_instance)

	# Target ring on the ground at the committed house (SPEC 6.7)
	_reticle_mesh = ImmediateMesh.new()
	_reticle_instance = MeshInstance3D.new()
	_reticle_instance.mesh = _reticle_mesh
	_telegraph_root.add_child(_reticle_instance)

	_draw_reticle_ring()
	_telegraph_root.hide()


func _draw_reticle_ring() -> void:
	if _reticle_mesh == null or _telegraph_mat == null:
		return
	_reticle_mesh.clear_surfaces()
	_reticle_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _telegraph_mat)
	var segs := 20
	var r := 1.7
	for i in segs:
		var a1 := float(i) * TAU / float(segs)
		var a2 := float(i + 1) * TAU / float(segs)
		var p1 := Vector3(cos(a1) * r, 0.04, sin(a1) * r)
		var p2 := Vector3(cos(a2) * r, 0.04, sin(a2) * r)
		_reticle_mesh.surface_add_vertex(p1)
		_reticle_mesh.surface_add_vertex(p2)
	# Cross tick marks
	_reticle_mesh.surface_add_vertex(Vector3(-r * 1.3, 0.04, 0))
	_reticle_mesh.surface_add_vertex(Vector3(-r * 0.75, 0.04, 0))
	_reticle_mesh.surface_add_vertex(Vector3(r * 0.75, 0.04, 0))
	_reticle_mesh.surface_add_vertex(Vector3(r * 1.3, 0.04, 0))
	_reticle_mesh.surface_add_vertex(Vector3(0, 0.04, -r * 1.3))
	_reticle_mesh.surface_add_vertex(Vector3(0, 0.04, -r * 0.75))
	_reticle_mesh.surface_add_vertex(Vector3(0, 0.04, r * 0.75))
	_reticle_mesh.surface_add_vertex(Vector3(0, 0.04, r * 1.3))
	_reticle_mesh.surface_end()


func _update_target_telegraph() -> void:
	if _telegraph_root == null:
		return
	if is_burning() or retreating or _dead or target_house == null or not is_instance_valid(target_house) or target_house.state != VoxelHouse.State.BURNING:
		_telegraph_root.hide()
		return

	_telegraph_root.show()
	_reticle_instance.global_position = target_house.global_position

	# Draw dashed aim line from firefighter to target house
	_aim_line_mesh.clear_surfaces()
	_aim_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _telegraph_mat)
	var p_start := global_position + Vector3(0, 0.5, 0)
	var p_end := target_house.global_position + Vector3(0, 0.5, 0)
	var to_end := p_end - p_start
	var total_len := to_end.length()
	var step := 0.75
	var segs := int(total_len / step)
	var dir_norm := to_end.normalized()
	for i in segs:
		if i % 2 == 0:
			var s1 := p_start + dir_norm * (float(i) * step)
			var s2 := p_start + dir_norm * minf(total_len, float(i + 1) * step)
			_aim_line_mesh.surface_add_vertex(s1)
			_aim_line_mesh.surface_add_vertex(s2)
	_aim_line_mesh.surface_end()


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


func _show_bubble(txt: String, col: Color = Color(1.0, 0.85, 0.2)) -> void:
	if _bubble == null:
		return
	_bubble.text = txt
	_bubble.modulate = col
	_bubble.visible = true
	_bubble_t = 1.6


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
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0 and _bubble != null:
			_bubble.visible = false
	if retreating and not is_burning():
		_retreat_t -= delta
		_set_spray(false)
		_update_target_telegraph()
		var to_home := home_pos - global_position
		to_home.y = 0.0
		if to_home.length() < 1.5 or _retreat_t <= 0.0:
			retired.emit(self)
			queue_free()
			return
		_move(to_home.normalized(), delta)
		return
	if is_burning():
		_update_target_telegraph()
		_physics_flee(delta)
		return

	# Target commitment (SPEC Section 6.7: commits for >= 6 seconds unless fire goes out)
	if commit_timer > 0.0:
		commit_timer -= delta

	var need_retarget := false
	if target_house == null or not is_instance_valid(target_house):
		need_retarget = true
	elif target_house.state != VoxelHouse.State.BURNING:
		need_retarget = true
	elif commit_timer <= 0.0:
		need_retarget = true

	if need_retarget:
		target_house = _find_best_fire()
		commit_timer = randf_range(COMMITMENT_MIN, COMMITMENT_MIN + 1.5)
		_check_catch_fire()

	_update_target_telegraph()

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
		_spread_t = 0.8
		_spread_fire()
	_shout_t -= delta
	if _shout_t <= 0.0:
		_shout_t = randf_range(1.2, 2.0)
		_show_bubble("AAA!!", Color(1.0, 0.3, 0.1))
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
	_animate(true)
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
	_animate(velocity.length_squared() > 0.01)
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
	house.apply_water(spray_rate * 2.2, delta)
	# Hose water also rescues burning characters near the spray or self.
	for c in get_tree().get_nodes_in_group("burning_chars"):
		if c is Node3D and c != self:
			var cp := (c as Node3D).global_position
			if cp.distance_to(house.global_position) < 4.5 or cp.distance_to(global_position) < 3.5:
				if c.has_method("apply_water"):
					c.apply_water(2.0, delta)


func _set_spray(v: bool) -> void:
	_spraying = v
	if is_instance_valid(_water_particles):
		_water_particles.emitting = v


func _on_burn_death() -> void:
	if _dead:
		return
	_dead = true
	_set_spray(false)
	_update_target_telegraph()
	if is_in_group("firefighters"):
		remove_from_group("firefighters")
	if is_in_group("flammable"):
		remove_from_group("flammable")
	torched.emit(self)
	retired.emit(self)
	queue_free()
