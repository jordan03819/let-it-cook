extends StaticBody3D
class_name VoxelHouse
## Voxel house: flammable, burns, goes burnt. Builds its own boxy meshes.
## Pixel/voxel aesthetic: all BoxMesh, flat colors, no smooth stuff.

signal burned_out(house: VoxelHouse)
signal ignited(house: VoxelHouse)

enum State { UNBURNED, BURNING, BURNT }

var state: int = State.UNBURNED
var fuel_max: float = 22.0
var fuel: float = 22.0
var wetness: float = 0.0 # 0 dry, 1 soaked. Firefighters add this.
var burn_power: float = 1.0 # heat output multiplier
var fireproof: bool = false # L3 stone: normal sparks can't light it
var burn_rate_mult: float = 1.0 # upgrade: Extra Crispy burns faster
var kind: String = "house" # house | tree | barrel | stone
var house_size: Vector3 = Vector3(2.0, 1.6, 2.0)
var base_color: Color = Color(0.9, 0.8, 0.65)
var roof_color: Color = Color(0.75, 0.25, 0.15)
var heat_prime: float = 0.0 # gust-primed stone: 6s window, normal catch odds
var _scorched: bool = false
var _scorch_tween: Tween = null
var _pop_tween: Tween = null
var _lod_low: bool = false
var _albedo_dirty: bool = true

var _visual_root: Node3D
var _base_box: MeshInstance3D
var _roof_box: MeshInstance3D
var _fire_root: Node3D
var _flames: Array[MeshInstance3D] = []
var _fire_particles: GPUParticles3D
var _smoke_particles: GPUParticles3D
var _light: OmniLight3D
var _flicker_t: float = 0.0
var _phase_off: float = -1.0 # lazy per-house offset into the shared breath
var _flash: float = 0.0 # hit-flash / ember glow energy
var _wind_tilt: Vector3 = Vector3.ZERO # set by game wind each frame
var _mat_base: StandardMaterial3D
var _mat_roof: StandardMaterial3D


func setup(p_base_color: Color, p_roof_color: Color, p_fuel: float, p_size: Vector3, p_kind: String = "house") -> void:
	base_color = p_base_color
	roof_color = p_roof_color
	fuel_max = p_fuel
	fuel = p_fuel
	house_size = p_size
	_albedo_dirty = true
	var kind_changed := p_kind != kind
	kind = p_kind
	if is_node_ready():
		if kind_changed:
			_rebuild_visuals()
		else:
			_apply_colors()


func _ready() -> void:
	add_to_group("houses")
	add_to_group("flammable")
	collision_layer = 2 # houses on layer 2 so raycast can hit only houses+ground
	collision_mask = 0
	_build_collision()
	_build_visuals()
	_build_fire_visuals()
	_set_fire_visible(false)


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(house_size.x + 0.4, house_size.y + 1.2, house_size.z + 0.4)
	shape.shape = box
	shape.position = Vector3(0, (house_size.y + 1.2) * 0.5, 0)
	add_child(shape)


func _voxel_mat(c: Color, emission: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.metallic = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if emission:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.5
	return m


func _apply_colors() -> void:
	if _mat_base != null:
		_mat_base.albedo_color = base_color
		_mat_base.emission = base_color
	if _mat_roof != null:
		_mat_roof.albedo_color = roof_color


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


func _rebuild_visuals() -> void:
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.queue_free()
	_visual_root = null
	# Rebuild collision for new silhouette.
	for c in get_children():
		if c is CollisionShape3D:
			c.queue_free()
	_build_collision()
	_build_visuals()
	_apply_colors()


func _build_visuals() -> void:
	_visual_root = Node3D.new()
	_visual_root.name = "VoxelVisual"
	add_child(_visual_root)
	match kind:
		"tree":
			_build_tree_visuals()
			return
		"barrel":
			_build_barrel_visuals()
			return
		"stone":
			_build_stone_visuals()
			return

	_mat_base = _voxel_mat(base_color)
	_mat_roof = _voxel_mat(roof_color)
	# Emission channel reserved for ignite hit-flash / burnt ember glow.
	_mat_base.emission_enabled = true
	_mat_base.emission = base_color
	_mat_base.emission_energy_multiplier = 0.0
	_apply_colors()

	# Main body
	_base_box = _add_box(_visual_root, house_size, Vector3(0, house_size.y * 0.5, 0), _mat_base)
	# Roof slab (voxel overhang)
	var roof_size := Vector3(house_size.x + 0.4, 0.6, house_size.z + 0.4)
	_roof_box = _add_box(_visual_root, roof_size, Vector3(0, house_size.y + 0.3, 0), _mat_roof)
	# Roof top voxel step
	_add_box(_visual_root, Vector3(house_size.x * 0.55, 0.4, house_size.z * 0.55), Vector3(0, house_size.y + 0.8, 0), _mat_roof)
	# Door (dark voxel)
	_add_box(_visual_root, Vector3(0.5, 0.9, 0.1), Vector3(0.3, 0.45, house_size.z * 0.5 + 0.02), _voxel_mat(Color(0.25, 0.15, 0.1)))
	# Windows (glowy yellow voxels)
	var win_mat := _voxel_mat(Color(1.0, 0.9, 0.4), true)
	_add_box(_visual_root, Vector3(0.4, 0.4, 0.1), Vector3(-0.5, 0.9, house_size.z * 0.5 + 0.02), win_mat)
	_add_box(_visual_root, Vector3(0.1, 0.4, 0.4), Vector3(house_size.x * 0.5 + 0.02, 0.9, -0.3), win_mat)
	# Chimney
	_add_box(_visual_root, Vector3(0.4, 1.0, 0.4), Vector3(house_size.x * 0.25, house_size.y + 0.7, -house_size.z * 0.2), _voxel_mat(Color(0.5, 0.45, 0.45)))


func _build_tree_visuals() -> void:
	# NO house parts: trunk + stacked foliage cubes. Reads as tree at a glance.
	_mat_base = _voxel_mat(Color(0.42, 0.27, 0.13))
	_mat_roof = _voxel_mat(Color(0.14, 0.56, 0.2))
	_add_box(_visual_root, Vector3(0.35, 1.1, 0.35), Vector3(0, 0.55, 0), _mat_base)
	_add_box(_visual_root, Vector3(1.6, 0.9, 1.6), Vector3(0, 1.4, 0), _mat_roof)
	_add_box(_visual_root, Vector3(1.15, 0.8, 1.15), Vector3(0, 2.1, 0), _voxel_mat(Color(0.18, 0.63, 0.24)))
	_add_box(_visual_root, Vector3(0.65, 0.5, 0.65), Vector3(0, 2.7, 0), _voxel_mat(Color(0.25, 0.7, 0.28)))


func _build_barrel_visuals() -> void:
	# Pallet + 2 upright barrels with hazard band. Small, round-ish silhouette.
	_mat_base = _voxel_mat(Color(0.85, 0.2, 0.12))
	_mat_roof = _voxel_mat(Color(0.95, 0.75, 0.15))
	_add_box(_visual_root, Vector3(1.6, 0.18, 1.2), Vector3(0, 0.09, 0), _voxel_mat(Color(0.5, 0.36, 0.2)))
	# Left barrel.
	_add_box(_visual_root, Vector3(0.62, 0.95, 0.62), Vector3(-0.4, 0.65, 0), _mat_base)
	_add_box(_visual_root, Vector3(0.66, 0.2, 0.66), Vector3(-0.4, 0.65, 0), _mat_roof)
	_add_box(_visual_root, Vector3(0.66, 0.1, 0.66), Vector3(-0.4, 1.05, 0), _voxel_mat(Color(0.6, 0.12, 0.1)))
	# Right barrel.
	_add_box(_visual_root, Vector3(0.62, 0.95, 0.62), Vector3(0.4, 0.65, 0), _mat_base)
	_add_box(_visual_root, Vector3(0.66, 0.2, 0.66), Vector3(0.4, 0.65, 0), _mat_roof)
	# Skull dot (white voxel) so players learn "boom".
	_add_box(_visual_root, Vector3(0.2, 0.2, 0.06), Vector3(-0.4, 0.85, 0.34), _voxel_mat(Color(1, 1, 1), true))
	_add_box(_visual_root, Vector3(0.2, 0.2, 0.06), Vector3(0.4, 0.85, 0.34), _voxel_mat(Color(1, 1, 1), true))


func _build_stone_visuals() -> void:
	# Thick grey cottage, flat slab roof, barred slit window (NO glow).
	_mat_base = _voxel_mat(Color(0.58, 0.58, 0.6))
	_mat_roof = _voxel_mat(Color(0.36, 0.37, 0.42))
	_add_box(_visual_root, house_size, Vector3(0, house_size.y * 0.5, 0), _mat_base)
	# Corner quoins (darker stone blocks) for texture.
	var quoin := _voxel_mat(Color(0.45, 0.45, 0.48))
	_add_box(_visual_root, Vector3(0.3, house_size.y, 0.3), Vector3(-house_size.x * 0.5, house_size.y * 0.5, house_size.z * 0.5), quoin)
	_add_box(_visual_root, Vector3(0.3, house_size.y, 0.3), Vector3(house_size.x * 0.5, house_size.y * 0.5, house_size.z * 0.5), quoin)
	_add_box(_visual_root, Vector3(house_size.x + 0.3, 0.35, house_size.z + 0.3), Vector3(0, house_size.y + 0.17, 0), _mat_roof)
	# Iron door + slit window, both dark and unlit.
	_add_box(_visual_root, Vector3(0.55, 1.0, 0.12), Vector3(0, 0.5, house_size.z * 0.5 + 0.02), _voxel_mat(Color(0.16, 0.16, 0.18)))
	_add_box(_visual_root, Vector3(0.7, 0.18, 0.12), Vector3(0, 1.25, house_size.z * 0.5 + 0.02), _voxel_mat(Color(0.08, 0.08, 0.1)))


func _build_fire_visuals() -> void:
	_fire_root = Node3D.new()
	_fire_root.name = "FireVisual"
	_fire_root.position = Vector3(0, house_size.y + 0.6, 0)
	add_child(_fire_root)

	# 3 voxel flame cubes, animated in _process for crunchy pixel fire
	var flame_cols := [Color(1, 0.25, 0.05), Color(1, 0.55, 0.08), Color(1, 0.9, 0.3)]
	var flame_sizes := [Vector3(0.9, 0.9, 0.9), Vector3(0.65, 0.85, 0.65), Vector3(0.4, 0.7, 0.4)]
	for i in 3:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = flame_sizes[i]
		bm.material = _voxel_mat(flame_cols[i], true)
		mi.mesh = bm
		mi.position = Vector3(0, 0.3 + float(i) * 0.45, 0)
		_fire_root.add_child(mi)
		_flames.append(mi)

	# Ember/spark cubes shooting up (voxel particles = tiny BoxMesh)
	_fire_particles = _make_voxel_particles(
		Color(1.0, 0.5, 0.1),
		Vector3(0.12, 0.12, 0.12),
		24, 1.6, Vector3(0, 4.5, 0), Vector3(1.2, 0.5, 1.2), 0.9
	)
	_fire_root.add_child(_fire_particles)

	# Smoke cubes drifting up (grey voxels, pixel aesthetic)
	_smoke_particles = _make_voxel_particles(
		Color(0.38, 0.36, 0.38, 1.0),
		Vector3(0.22, 0.22, 0.22),
		16, 2.4, Vector3(0, 3.0, 0), Vector3(0.8, 0.5, 0.8), 1.4
	)
	_smoke_particles.position = Vector3(0, 1.2, 0)
	_fire_root.add_child(_smoke_particles)

	# Flickering light (only 1 per house, cheap, no shadow)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.45, 0.1)
	_light.light_energy = 1.6
	_light.omni_range = 6.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.0, 0)
	_fire_root.add_child(_light)


func _make_voxel_particles(col: Color, cube_size: Vector3, amount: int, lifetime: float, grav: Vector3, spread: Vector3, init_vel: float) -> GPUParticles3D:
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
	# Crunchy pixel fade: shrink, no soft blend
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

	# Voxel cube as particle mesh = matches voxel aesthetic
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
	if _fire_root:
		_fire_root.visible = v


func set_wind_tilt(tilt: Vector3) -> void:
	_wind_tilt = tilt


func set_light_allowed(v: bool) -> void:
	if _light:
		_light.visible = v


func set_smoke_lod(low: bool) -> void:
	if low == _lod_low:
		return
	_lod_low = low
	if _smoke_particles != null:
		_smoke_particles.amount = 8 if low else 16
	if _fire_particles != null:
		_fire_particles.amount = 14 if low else 24


func force_ignite() -> bool:
	# Barrels / gust flanks / burning martyrs: ignores fireproof + wetness.
	if state != State.UNBURNED:
		return false
	fireproof = false
	wetness = 0.0
	heat_prime = 0.0
	state = State.BURNING
	_set_fire_visible(true)
	_flash = 1.0
	_albedo_dirty = true
	_pop(1.2)
	ignited.emit(self)
	return true


func _pop(s: float) -> void:
	if _visual_root == null or not is_inside_tree():
		return
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
		_visual_root.scale = Vector3.ONE
	_pop_tween = _visual_root.create_tween()
	_pop_tween.tween_property(_visual_root, "scale", Vector3.ONE * s, 0.1)
	_pop_tween.tween_property(_visual_root, "scale", Vector3.ONE, 0.18)


func ignite() -> bool:
	if state != State.UNBURNED:
		return false
	if fireproof and heat_prime <= 0.0:
		return false # stone shrugs off sparks; needs barrel/gust prime
	if wetness > 0.65:
		return false # too wet to catch
	state = State.BURNING
	_set_fire_visible(true)
	_flash = 1.0
	_albedo_dirty = true
	_pop(1.2)
	ignited.emit(self)
	return true


func set_stage() -> void:
	# One-time scorch transition at fuel < 50%: walls x0.55, flames x0.75,
	# smoke grey + alpha ramp, roof sag via single tween (kill prior first).
	if _scorched:
		return
	_scorched = true
	if _mat_base != null:
		_mat_base.albedo_color = base_color * 0.55
	if _mat_roof != null:
		_mat_roof.albedo_color = roof_color * 0.55
	for f in _flames:
		if is_instance_valid(f):
			f.scale *= 0.75
	if _smoke_particles != null:
		_smoke_particles.amount = 16
		if _smoke_particles.draw_pass_1 is BoxMesh:
			var bm := _smoke_particles.draw_pass_1 as BoxMesh
			bm.size = Vector3(0.18, 0.18, 0.18)
	if _roof_box != null and is_inside_tree():
		if _scorch_tween != null and _scorch_tween.is_valid():
			_scorch_tween.kill()
		_scorch_tween = create_tween()
		_scorch_tween.tween_property(_roof_box, "rotation:z", 0.08, 0.6)
		_scorch_tween.tween_property(_roof_box, "position:y", house_size.y + 0.22, 0.6)


func apply_water(amount: float, delta: float) -> void:
	if state != State.BURNING:
		wetness = maxf(0.0, wetness - delta * 0.2)
		return
	wetness = clampf(wetness + amount * delta, 0.0, 1.0)
	fuel -= amount * delta * 3.0 # water eats fuel (tuned 6.0 -> 3.0)
	if wetness >= 1.0 or fuel <= 0.0:
		extinguish()


func extinguish() -> void:
	if state != State.BURNING:
		return
	# If fuel ran out it is burnt, else it survived (damp unburned)
	if fuel <= 0.5:
		_burn_out()
	else:
		state = State.UNBURNED
		_set_fire_visible(false)
		wetness = 0.6


func _burn_out() -> void:
	state = State.BURNT
	_set_fire_visible(false)
	if _scorch_tween != null and _scorch_tween.is_valid():
		_scorch_tween.kill()
	# Char the house: blacken, collapse roof (albedo only on transition)
	_mat_base.albedo_color = Color(0.12, 0.1, 0.1)
	_mat_roof.albedo_color = Color(0.08, 0.07, 0.07)
	_mat_base.emission = Color(1.0, 0.3, 0.05)
	_flash = 0.8 # dying ember glow that fades out
	if _light != null:
		_light.visible = false
	if kind == "tree":
		# Tree falls to a black stump: shrink foliage via whole-root squash.
		pass
	elif _roof_box != null and is_instance_valid(_roof_box):
		_roof_box.scale = Vector3(1.0, 0.35, 1.0)
		_roof_box.position.y = house_size.y + 0.15
	# Squash-and-settle juice (visual root only, collision untouched)
	if _visual_root != null and is_inside_tree():
		if _pop_tween != null and _pop_tween.is_valid():
			_pop_tween.kill()
		_visual_root.scale = Vector3.ONE
		var tw := _visual_root.create_tween()
		tw.tween_property(_visual_root, "scale", Vector3(1.18, 0.55, 1.18), 0.16)
		tw.tween_property(_visual_root, "scale", Vector3(1.1, 0.7, 1.1), 0.25)
	remove_from_group("flammable")
	burned_out.emit(self)


func _update_material_state() -> void:
	# Single authority for emission, called once at end of _process.
	# Priority: wet>0.3 blue -> BURNT ember decay -> _flash orange ->
	# _scorched faint red rim -> else energy 0.
	if _mat_base == null:
		return
	if wetness > 0.3 and state == State.BURNING:
		_mat_base.emission = Color(0.2, 0.45, 1.0)
		_mat_base.emission_energy_multiplier = 0.7
	elif state == State.BURNT:
		_mat_base.emission = Color(1.0, 0.3, 0.05)
		_mat_base.emission_energy_multiplier = _flash * 1.2
	elif _flash > 0.0:
		_mat_base.emission = Color(1.0, 0.5, 0.1)
		_mat_base.emission_energy_multiplier = _flash * 1.6
	elif _scorched and state == State.BURNING:
		_mat_base.emission = Color(0.45, 0.08, 0.05)
		_mat_base.emission_energy_multiplier = 0.5
	else:
		_mat_base.emission_energy_multiplier = 0.0


func _process(delta: float) -> void:
	# Hit-flash / ember-glow decay (also runs on burnt corpses briefly)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 1.2)
	if heat_prime > 0.0:
		heat_prime = maxf(0.0, heat_prime - delta)
	if state == State.BURNING:
		# Shared heartbeat: every flame breathes on RunState.fire_pulse,
		# each house only offsets phase. THE fire, not separate fires.
		if _phase_off < 0.0:
			_phase_off = fmod(float(abs(get_instance_id())) * 0.618, TAU)
		_flicker_t = RunState.fire_pulse * 12.0 + _phase_off
		# Burn fuel, dry out slowly
		wetness = maxf(0.0, wetness - delta * 0.15)
		fuel -= delta * 0.9 * burn_rate_mult + wetness * -0.3 * delta
		if not _scorched and fuel < fuel_max * 0.5:
			set_stage()
		# Wind feedback: whole fire root leans downwind, flames offset.
		if _fire_root != null:
			_fire_root.rotation.x = lerpf(_fire_root.rotation.x, _wind_tilt.z * 0.45, delta * 3.0)
			_fire_root.rotation.z = lerpf(_fire_root.rotation.z, -_wind_tilt.x * 0.45, delta * 3.0)
		# Smoke drifts downwind: steer its process material gradually.
		if _smoke_particles != null and _smoke_particles.process_material is ParticleProcessMaterial:
			var spm := _smoke_particles.process_material as ParticleProcessMaterial
			var want := Vector3(_wind_tilt.x * 3.0, 3.6, _wind_tilt.z * 3.0)
			spm.gravity = spm.gravity.lerp(want, delta * 1.5)
		# Animate voxel flames: jitter scale/rot for crunchy pixel fire
		for i in _flames.size():
			var f := _flames[i]
			var grow := 0.8 + 0.5 * RunState.inferno
			var s := (1.0 + sin(_flicker_t + float(i) * 2.1) * 0.18 + randf_range(-0.06, 0.06)) * grow
			f.scale = Vector3(s, (1.0 + sin(_flicker_t * 1.3 + float(i)) * 0.22) * grow, s)
			f.rotation.y += delta * (1.5 + float(i) * 0.7)
			f.position.x = sin(_flicker_t * 0.7 + float(i) * 1.7) * 0.12 + _wind_tilt.x * 0.35 * float(i + 1) * 0.33
			f.position.z = _wind_tilt.z * 0.35 * float(i + 1) * 0.33
		if _light:
			_light.light_energy = 1.4 + sin(_flicker_t * 1.7) * 0.4 + randf_range(-0.15, 0.15)
		if fuel <= 0.0:
			_burn_out()
	# Trees / small props lean in the wind (all states, cheap voxel life).
	if _visual_root != null and house_size.x < 1.2:
		_visual_root.rotation.x = lerpf(_visual_root.rotation.x, _wind_tilt.z * 0.18, delta * 2.0)
		_visual_root.rotation.z = lerpf(_visual_root.rotation.z, -_wind_tilt.x * 0.18, delta * 2.0)
	_update_material_state()
