extends StaticBody3D
class_name VoxelBarrel
## Voxel Explosive Barrel — Strategic route-planning prop.
## Cannot be ignited manually by the player (SPEC Section 7.2 & 8.5).
## Catches fire from spread or heat, telegraphs danger for 2s,
## then detonates in a radial fiery explosion that ignites nearby structures,
## knocks/ignites units, triggers sympathetic barrel explosions,
## and grants +1 Ember (SPEC Section 6.5).

signal primed(barrel: VoxelBarrel)
signal exploded(barrel: VoxelBarrel)

enum State { UNBURNED, PRIMED, EXPLODED }

var state: int = State.UNBURNED
var heat: float = 0.0
var wetness: float = 0.0
var prime_timer: float = 2.0
var explosion_radius: float = 6.2

var _visual_root: Node3D = null
var _barrel_mat: StandardMaterial3D = null
var _hoop_mat: StandardMaterial3D = null
var _hazard_mat: StandardMaterial3D = null

var _prime_particles: GPUParticles3D = null
var _danger_label: Label3D = null
var _pop_tween: Tween = null
var _shake_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	add_to_group("barrels")
	add_to_group("flammable")
	collision_layer = 2
	collision_mask = 0
	_build_collision()
	_build_visuals()


func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.65
	cyl.height = 1.4
	col.shape = cyl
	col.position = Vector3(0, 0.7, 0)
	add_child(col)


func _voxel_mat(c: Color, emission: bool = false, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	m.metallic = 0.1
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if emission:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
	return m


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build_visuals() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "BarrelVisual"
	add_child(_visual_root)

	_barrel_mat = _voxel_mat(Color(0.82, 0.22, 0.14)) # Dangerous red
	_hoop_mat = _voxel_mat(Color(0.22, 0.22, 0.24), false) # Dark iron rings
	_hazard_mat = _voxel_mat(Color(0.95, 0.85, 0.12), true, 1.2) # Glowing hazard stripe

	# Octagonal/stepped barrel body using layered voxel boxes
	_add_box(_visual_root, Vector3(0.95, 1.3, 0.95), Vector3(0, 0.65, 0), _barrel_mat)
	_add_box(_visual_root, Vector3(1.15, 1.1, 0.75), Vector3(0, 0.65, 0), _barrel_mat)
	_add_box(_visual_root, Vector3(0.75, 1.1, 1.15), Vector3(0, 0.65, 0), _barrel_mat)

	# Iron hoops (top, middle, bottom)
	_add_box(_visual_root, Vector3(1.02, 0.14, 1.02), Vector3(0, 0.22, 0), _hoop_mat)
	_add_box(_visual_root, Vector3(1.02, 0.14, 1.02), Vector3(0, 1.08, 0), _hoop_mat)
	_add_box(_visual_root, Vector3(1.18, 0.16, 0.78), Vector3(0, 0.65, 0), _hoop_mat)
	_add_box(_visual_root, Vector3(0.78, 0.16, 1.18), Vector3(0, 0.65, 0), _hoop_mat)

	# Hazard flame emblem in center
	_add_box(_visual_root, Vector3(0.35, 0.35, 1.18), Vector3(0, 0.65, 0), _hazard_mat)
	_add_box(_visual_root, Vector3(1.18, 0.35, 0.35), Vector3(0, 0.65, 0), _hazard_mat)

	# Barrel top cap / bung
	_add_box(_visual_root, Vector3(0.25, 0.12, 0.25), Vector3(0.18, 1.35, 0.18), _hoop_mat)


func add_heat(amount: float) -> void:
	if state != State.UNBURNED:
		return
	if wetness > 0.1:
		amount *= maxf(0.1, 1.0 - wetness * 0.8)
	heat = minf(1.0, heat + amount)
	if heat >= 1.0:
		prime()


func apply_water(amount: float, delta: float) -> void:
	if state == State.EXPLODED:
		return
	wetness = clampf(wetness + amount * delta, 0.0, 1.0)
	heat = maxf(0.0, heat - amount * delta * 2.0)


func prime(custom_timer: float = 2.0) -> void:
	if state != State.UNBURNED:
		return
	state = State.PRIMED
	prime_timer = custom_timer

	# Visual telegraph: pulsing hazard emission
	if _barrel_mat != null:
		_barrel_mat.emission_enabled = true
		_barrel_mat.emission = Color(1.0, 0.3, 0.05)
		_barrel_mat.emission_energy_multiplier = 2.0

	# 3D Danger Billboard
	if _danger_label == null or not is_instance_valid(_danger_label):
		_danger_label = Label3D.new()
		_danger_label.text = "DANGER!\n[ 2.0s ]"
		_danger_label.font_size = 64
		_danger_label.pixel_size = 0.009
		_danger_label.modulate = Color(1.0, 0.3, 0.1)
		_danger_label.outline_size = 14
		_danger_label.outline_modulate = Color(0.15, 0, 0)
		_danger_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_danger_label.position = Vector3(0, 2.0, 0)
		add_child(_danger_label)

	# Spurt of sparks and smoke from top
	_spawn_fuse_particles()
	SoundManager.play_sfx("last_spark", 1.4)
	primed.emit(self)


func _spawn_fuse_particles() -> void:
	_prime_particles = GPUParticles3D.new()
	_prime_particles.amount = 20
	_prime_particles.lifetime = 0.6
	_prime_particles.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 2.5
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0, 1.0, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color = Color(1.0, 0.8, 0.2)
	_prime_particles.process_material = pm

	var quad := BoxMesh.new()
	quad.size = Vector3(0.1, 0.1, 0.1)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.7, 0.1)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.05)
	m.emission_energy_multiplier = 3.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = m
	_prime_particles.draw_pass_1 = quad

	add_child(_prime_particles)
	_prime_particles.position = Vector3(0.18, 1.4, 0.18)


func _process(delta: float) -> void:
	if wetness > 0.0 and state == State.UNBURNED:
		wetness = maxf(0.0, wetness - delta * 0.05)

	if state == State.UNBURNED:
		if heat > 0.04 and _barrel_mat != null:
			_barrel_mat.emission_enabled = true
			_barrel_mat.emission = Color(1.0, 0.35, 0.08)
			_barrel_mat.emission_energy_multiplier = heat * 2.2
		elif _barrel_mat != null:
			_barrel_mat.emission_energy_multiplier = 0.0

	if state == State.PRIMED:
		prime_timer -= delta
		if _danger_label != null and is_instance_valid(_danger_label):
			_danger_label.text = "DANGER!\n[ %.1fs ]" % maxf(0.0, prime_timer)
			var pulse := 0.6 + 0.4 * sin(float(Time.get_ticks_msec()) * 0.02)
			_danger_label.modulate = Color(1.0, pulse * 0.4, 0.05)

		# Visual shake and swell
		if _visual_root != null:
			var shake := Vector3(randf_range(-0.06, 0.06), randf_range(-0.03, 0.03), randf_range(-0.06, 0.06))
			_visual_root.position = shake
			var swell := 1.0 + (1.0 - clampf(prime_timer / 2.0, 0.0, 1.0)) * 0.25
			_visual_root.scale = Vector3(swell, swell, swell)

		if prime_timer <= 0.0:
			explode()


func explode() -> void:
	if state == State.EXPLODED:
		return
	state = State.EXPLODED

	if _danger_label != null and is_instance_valid(_danger_label):
		_danger_label.queue_free()
		_danger_label = null
	if _prime_particles != null and is_instance_valid(_prime_particles):
		_prime_particles.queue_free()
		_prime_particles = null

	# Disable collision
	collision_layer = 0

	# Spawn explosive effects
	_spawn_explosion_vfx()
	SoundManager.play_sfx("explosion")

	# Affect nearby structures and actors
	_detonate_blast()

	# Hide barrel visual and leave a charred crater
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.queue_free()
		_visual_root = null
	_build_crater_visual()

	exploded.emit(self)


func _detonate_blast() -> void:
	var pos := global_position

	# 1. Structures (Houses and Trees)
	for h in get_tree().get_nodes_in_group("houses"):
		if is_instance_valid(h) and h is VoxelHouse and h.kind != "stone":
			var d := pos.distance_to(h.global_position)
			if d <= explosion_radius:
				if h.state == VoxelHouse.State.UNBURNED:
					h.heat = 1.0
					h.ignite()
				elif h.state == VoxelHouse.State.SMOLDERING:
					h.reignite(30.0)

	# 2. Sympathetic Barrel Detonation
	for b in get_tree().get_nodes_in_group("barrels"):
		if is_instance_valid(b) and b is VoxelBarrel and b != self:
			var d := pos.distance_to(b.global_position)
			if d <= explosion_radius and b.state == State.UNBURNED:
				b.prime(randf_range(0.2, 0.45)) # Chain reaction!

	# 3. Flammable Units (Villagers & Firefighters & Shamans)
	for v in get_tree().get_nodes_in_group("villagers"):
		if is_instance_valid(v) and v is CharacterBody3D:
			var d := pos.distance_to(v.global_position)
			if d <= explosion_radius:
				if v.has_method("ignite"):
					v.ignite()
				var push: Vector3 = (v.global_position - pos).normalized()
				push.y = 0.5
				v.velocity += push * 10.0

	for f in get_tree().get_nodes_in_group("firefighters"):
		if is_instance_valid(f) and f is CharacterBody3D:
			var d := pos.distance_to(f.global_position)
			if d <= explosion_radius:
				if f.has_method("ignite"):
					f.ignite()
				var push: Vector3 = (f.global_position - pos).normalized()
				push.y = 0.5
				f.velocity += push * 10.0

	for s in get_tree().get_nodes_in_group("shamans"):
		if is_instance_valid(s) and s is CharacterBody3D:
			var d := pos.distance_to(s.global_position)
			if d <= explosion_radius:
				if s.has_method("ignite"):
					s.ignite()


func _spawn_explosion_vfx() -> void:
	if not is_inside_tree():
		return

	# Explosion light flash
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.2)
	light.light_energy = 8.0
	light.omni_range = explosion_radius * 1.8
	add_child(light)

	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.45)
	tw.tween_callback(light.queue_free)

	# Fiery blast particles
	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 1.1
	p.one_shot = true
	p.explosiveness = 0.95
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 10, 20))

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = 7.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3(0, -6.0, 0)
	pm.scale_min = 1.0
	pm.scale_max = 2.4
	pm.color = Color(1.0, 0.6, 0.1, 1.0)

	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.3, 1.0))
	ramp.set_color(1, Color(0.2, 0.1, 0.08, 0.0))
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = ramp
	pm.color_ramp = grad_tex
	p.process_material = pm

	var cube := BoxMesh.new()
	cube.size = Vector3(0.28, 0.28, 0.28)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.6, 0.1)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.05)
	m.emission_energy_multiplier = 3.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cube.material = m
	p.draw_pass_1 = cube

	add_child(p)
	p.position = Vector3(0, 0.6, 0)
	p.emitting = true

	get_tree().create_timer(1.8).timeout.connect(p.queue_free)


func _build_crater_visual() -> void:
	var crater := Node3D.new()
	crater.name = "Crater"
	add_child(crater)
	var scorch_mat := _voxel_mat(Color(0.12, 0.1, 0.1))
	_add_box(crater, Vector3(1.8, 0.04, 1.8), Vector3(0, 0.02, 0), scorch_mat)
	_add_box(crater, Vector3(1.2, 0.06, 1.2), Vector3(0, 0.03, 0), scorch_mat)
	_add_box(crater, Vector3(0.4, 0.15, 0.4), Vector3(0.3, 0.07, -0.2), _hoop_mat)
