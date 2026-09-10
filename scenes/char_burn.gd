extends Node
class_name CharBurn
## Shared "burnable character" component for villagers + firefighters.
## Handles: catch fire, burning visuals (voxel flames + light), damage over
## time, water extinguishing, death (charred corpse + smoke poof).
## Parent character owns AI; this only owns fire state.

signal ignited
signal died
signal extinguished

var parent: CharacterBody3D = null
var visual: Node3D = null
var top_height: float = 1.7
var burn_hp_max: float = 7.0
var burn_hp: float = 7.0
var wetness: float = 0.0 # 0 dry, 1 soaked -> puts fire out
var is_burning: bool = false
var is_dead: bool = false

var _fire_root: Node3D = null
var _flames: Array[MeshInstance3D] = []
var _light: OmniLight3D = null
var _fire_particles: GPUParticles3D = null
var _smoke_particles: GPUParticles3D = null
var _flicker: float = 0.0
var _phase_off: float = -1.0


func configure(p_parent: CharacterBody3D, p_visual: Node3D, p_height: float = 1.7, p_hp: float = 7.0) -> void:
	parent = p_parent
	visual = p_visual
	top_height = p_height
	burn_hp_max = p_hp
	burn_hp = p_hp
	if _fire_root == null:
		_build_fire()
	_set_fire_visible(false)


func ignite() -> bool:
	if is_burning or is_dead or parent == null:
		return false
	if wetness > 0.7:
		return false
	is_burning = true
	burn_hp = burn_hp_max
	wetness = 0.0
	_set_fire_visible(true)
	if is_instance_valid(parent):
		if not parent.is_in_group("burning_chars"):
			parent.add_to_group("burning_chars")
	_pop()
	ignited.emit()
	return true


func apply_water(amount: float, delta: float) -> void:
	if not is_burning or is_dead:
		return
	wetness = clampf(wetness + amount * delta * 0.7, 0.0, 1.0)
	if wetness >= 1.0:
		extinguish()


func extinguish() -> void:
	if not is_burning or is_dead:
		return
	is_burning = false
	wetness = 0.6
	_set_fire_visible(false)
	if is_instance_valid(parent) and parent.is_in_group("burning_chars"):
		parent.remove_from_group("burning_chars")
	extinguished.emit()


func heat() -> float:
	# 0..1 how strongly this character burns (for lights / HUD / AI fear)
	if not is_burning:
		return 0.0
	return clampf(burn_hp / burn_hp_max, 0.15, 1.0)


func _process(delta: float) -> void:
	if is_dead or not is_burning:
		return
	if _phase_off < 0.0:
		_phase_off = fmod(float(abs(get_instance_id())) * 0.618, TAU)
	_flicker = RunState.fire_pulse * 13.0 + _phase_off
	wetness = maxf(0.0, wetness - delta * 0.05)
	burn_hp -= delta
	# Animate voxel flames: crunchy jitter like house fire
	for i in _flames.size():
		var f := _flames[i]
		if not is_instance_valid(f):
			continue
		var grow := 0.8 + 0.5 * RunState.inferno
		var s := (1.0 + sin(_flicker + float(i) * 2.1) * 0.2 + randf_range(-0.07, 0.07)) * grow
		f.scale = Vector3(s, (1.0 + sin(_flicker * 1.3 + float(i)) * 0.24) * grow, s)
		f.rotation.y += delta * (2.0 + float(i))
		f.position.x = sin(_flicker * 0.7 + float(i) * 1.7) * 0.1
	if is_instance_valid(_light):
		_light.light_energy = (0.9 + heat() * 0.9) * (1.0 + sin(_flicker * 1.9) * 0.25)
	if burn_hp <= 0.0:
		_die()


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	is_burning = false
	_set_fire_visible(false)
	if is_instance_valid(parent):
		if parent.is_in_group("burning_chars"):
			parent.remove_from_group("burning_chars")
		_spawn_remains()
	died.emit()


# --- visuals ---
func _vmat(c: Color, emit: bool = false, energy: float = 1.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if emit:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
	return m


func _build_fire() -> void:
	# Big readable torch: oversized flame cubes engulfing the head + one
	# cheap short-range light so burning people glow at dusk.
	_fire_root = Node3D.new()
	_fire_root.name = "CharFireVisual"
	_fire_root.position = Vector3(0, top_height * 0.7, 0)
	add_child(_fire_root)
	var cols := [Color(1, 0.25, 0.05), Color(1, 0.55, 0.08), Color(1, 0.9, 0.3)]
	var sizes := [Vector3(0.95, 0.95, 0.95), Vector3(0.65, 0.85, 0.65), Vector3(0.42, 0.7, 0.42)]
	for i in 3:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sizes[i]
		bm.material = _vmat(cols[i], true, 2.6)
		mi.mesh = bm
		mi.position = Vector3(0, 0.25 + float(i) * 0.45, 0)
		_fire_root.add_child(mi)
		_flames.append(mi)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.5, 0.12)
	_light.light_energy = 1.4
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.6, 0)
	_fire_root.add_child(_light)
	# Same particle kit as houses (smaller counts): ember cubes + smoke.
	_fire_particles = _make_voxel_particles(Color(1.0, 0.5, 0.1), Vector3(0.12, 0.12, 0.12), 12, 1.2, Vector3(0, 4.5, 0), 0.9)
	_fire_root.add_child(_fire_particles)
	_smoke_particles = _make_voxel_particles(Color(0.35, 0.34, 0.36, 1.0), Vector3(0.2, 0.2, 0.2), 8, 1.8, Vector3(0, 3.0, 0), 1.2)
	_smoke_particles.position = Vector3(0, 0.9, 0)
	_fire_root.add_child(_smoke_particles)


func _make_voxel_particles(col: Color, cube_size: Vector3, amount: int, lifetime: float, grav: Vector3, init_vel: float) -> GPUParticles3D:
	# Same crunchy cube-particle recipe as VoxelHouse.
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	if DisplayServer.get_name() == "headless":
		p.preprocess = 0.0
	p.explosiveness = 0.0
	p.randomness = 0.6
	p.local_coords = true
	p.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	p.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 12, 12))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 22.0
	pm.initial_velocity_min = init_vel * 0.6
	pm.initial_velocity_max = init_vel * 1.4
	pm.gravity = grav
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.color = col
	var ramp := Gradient.new()
	ramp.set_color(0, col)
	var end_col := col
	end_col.a = 0.0
	ramp.set_color(1, end_col)
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = ramp
	pm.color_ramp = grad_tex
	p.process_material = pm
	var quad := BoxMesh.new()
	quad.size = cube_size
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if col.r > 0.8 and col.g < 0.7:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 2.0
	quad.material = m
	p.draw_pass_1 = quad
	return p


func _set_fire_visible(v: bool) -> void:
	if is_instance_valid(_fire_root):
		_fire_root.visible = v


func _pop() -> void:
	if visual == null or not is_instance_valid(visual):
		return
	if not visual.is_inside_tree():
		return
	var tw := visual.create_tween()
	tw.tween_property(visual, "scale", Vector3.ONE * 1.25, 0.1)
	tw.tween_property(visual, "scale", Vector3.ONE, 0.18)


func _spawn_remains() -> void:
	# Charred voxel corpse + grey smoke poof, left behind in the world.
	if parent == null or not is_instance_valid(parent):
		return
	var root := parent.get_parent()
	if root == null:
		return
	var pos: Vector3 = parent.global_position
	var corpse := Node3D.new()
	corpse.position = pos
	corpse.rotation.y = randf() * TAU
	root.add_child(corpse)
	var char_mat := _vmat(Color(0.1, 0.09, 0.09))
	for i in 3:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.3, 0.55), randf_range(0.2, 0.35), randf_range(0.3, 0.55))
		bm.material = char_mat
		mi.mesh = bm
		mi.position = Vector3(randf_range(-0.25, 0.25), 0.12 + float(i) * 0.18, randf_range(-0.25, 0.25))
		mi.rotation.y = randf() * TAU
		corpse.add_child(mi)
	_spawn_puff(root, pos + Vector3(0, 0.8, 0))


func _spawn_puff(root: Node, pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 10, 12))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, 1.5, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.6
	pm.color = Color(0.3, 0.3, 0.32)
	p.process_material = pm
	var cube := BoxMesh.new()
	cube.size = Vector3(0.2, 0.2, 0.2)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.3, 0.32)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cube.material = m
	p.draw_pass_1 = cube
	root.add_child(p)
	p.global_position = pos
	p.emitting = true
	var tree := p.get_tree()
	if tree != null:
		tree.create_timer(3.0).timeout.connect(p.queue_free)
