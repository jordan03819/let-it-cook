extends StaticBody3D
class_name VoxelHouse
## REFORMED VoxelHouse — minimal burn state, no sim.
## States: UNBURNED -> BURNING -> BURNT. Once lit it always burns out.
## No wetness, no fireproof, no wind, no water, no spread hooks.
## Visuals only: voxel body + flame cubes + particles + light.

signal burned_out(house: VoxelHouse)
signal ignited(house: VoxelHouse)

enum State { UNBURNED, BURNING, BURNT }

var state: int = State.UNBURNED
var fuel_max: float = 22.0
var fuel: float = 22.0
var kind: String = "house" # house | tree (visual variety only, same rules)
var house_size: Vector3 = Vector3(2.0, 1.6, 2.0)
var base_color: Color = Color(0.9, 0.8, 0.65)
var roof_color: Color = Color(0.75, 0.25, 0.15)

var _scorched: bool = false
var _scorch_tween: Tween = null
var _pop_tween: Tween = null

var _visual_root: Node3D
var _base_box: MeshInstance3D
var _roof_box: MeshInstance3D
var _fire_root: Node3D
var _flames: Array[MeshInstance3D] = []
var _fire_particles: GPUParticles3D
var _smoke_particles: GPUParticles3D
var _light: OmniLight3D
var _flicker_t: float = 0.0
var _phase_off: float = -1.0
var _flash: float = 0.0
var _mat_base: StandardMaterial3D
var _mat_roof: StandardMaterial3D


func setup(p_base_color: Color, p_roof_color: Color, p_fuel: float, p_size: Vector3, p_kind: String = "house") -> void:
	base_color = p_base_color
	roof_color = p_roof_color
	fuel_max = p_fuel
	fuel = p_fuel
	house_size = p_size
	kind = p_kind
	if is_node_ready():
		_rebuild_visuals()
		_apply_colors()


func _ready() -> void:
	add_to_group("houses")
	collision_layer = 2
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
	if kind == "tree":
		_build_tree_visuals()
		return
	_build_house_visuals()


func _build_house_visuals() -> void:
	_mat_base = _voxel_mat(base_color)
	_mat_roof = _voxel_mat(roof_color)
	_mat_base.emission_enabled = true
	_mat_base.emission = base_color
	_mat_base.emission_energy_multiplier = 0.0
	_apply_colors()
	_base_box = _add_box(_visual_root, house_size, Vector3(0, house_size.y * 0.5, 0), _mat_base)
	var roof_size := Vector3(house_size.x + 0.4, 0.6, house_size.z + 0.4)
	_roof_box = _add_box(_visual_root, roof_size, Vector3(0, house_size.y + 0.3, 0), _mat_roof)
	_add_box(_visual_root, Vector3(house_size.x * 0.55, 0.4, house_size.z * 0.55), Vector3(0, house_size.y + 0.8, 0), _mat_roof)
	_add_box(_visual_root, Vector3(0.5, 0.9, 0.1), Vector3(0.3, 0.45, house_size.z * 0.5 + 0.02), _voxel_mat(Color(0.25, 0.15, 0.1)))
	var win_mat := _voxel_mat(Color(1.0, 0.9, 0.4), true)
	_add_box(_visual_root, Vector3(0.4, 0.4, 0.1), Vector3(-0.5, 0.9, house_size.z * 0.5 + 0.02), win_mat)
	_add_box(_visual_root, Vector3(0.1, 0.4, 0.4), Vector3(house_size.x * 0.5 + 0.02, 0.9, -0.3), win_mat)
	_add_box(_visual_root, Vector3(0.4, 1.0, 0.4), Vector3(house_size.x * 0.25, house_size.y + 0.7, -house_size.z * 0.2), _voxel_mat(Color(0.5, 0.45, 0.45)))


func _build_tree_visuals() -> void:
	_mat_base = _voxel_mat(Color(0.42, 0.27, 0.13))
	_mat_roof = _voxel_mat(Color(0.14, 0.56, 0.2))
	_add_box(_visual_root, Vector3(0.35, 1.1, 0.35), Vector3(0, 0.55, 0), _mat_base)
	_add_box(_visual_root, Vector3(1.6, 0.9, 1.6), Vector3(0, 1.4, 0), _mat_roof)
	_add_box(_visual_root, Vector3(1.15, 0.8, 1.15), Vector3(0, 2.1, 0), _voxel_mat(Color(0.18, 0.63, 0.24)))
	_add_box(_visual_root, Vector3(0.65, 0.5, 0.65), Vector3(0, 2.7, 0), _voxel_mat(Color(0.25, 0.7, 0.28)))


func _build_fire_visuals() -> void:
	_fire_root = Node3D.new()
	_fire_root.name = "FireVisual"
	_fire_root.position = Vector3(0, house_size.y + 0.6, 0)
	add_child(_fire_root)
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
	_fire_particles = _make_voxel_particles(Color(1.0, 0.5, 0.1), Vector3(0.12, 0.12, 0.12), 24, 1.6, Vector3(0, 4.5, 0), 0.9)
	_fire_root.add_child(_fire_particles)
	_smoke_particles = _make_voxel_particles(Color(0.38, 0.36, 0.38, 1.0), Vector3(0.22, 0.22, 0.22), 16, 2.4, Vector3(0, 3.0, 0), 1.4)
	_smoke_particles.position = Vector3(0, 1.2, 0)
	_fire_root.add_child(_smoke_particles)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.45, 0.1)
	_light.light_energy = 1.6
	_light.omni_range = 6.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.0, 0)
	_fire_root.add_child(_light)


func _make_voxel_particles(col: Color, cube_size: Vector3, amount: int, lifetime: float, grav: Vector3, init_vel: float) -> GPUParticles3D:
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
	if _fire_root:
		_fire_root.visible = v


# --- core verb: lighting. No conditions besides state. ---
func ignite() -> bool:
	if state != State.UNBURNED:
		return false
	state = State.BURNING
	_set_fire_visible(true)
	_flash = 1.0
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


func _burn_out() -> void:
	state = State.BURNT
	_set_fire_visible(false)
	if _scorch_tween != null and _scorch_tween.is_valid():
		_scorch_tween.kill()
	_mat_base.albedo_color = Color(0.12, 0.1, 0.1)
	_mat_roof.albedo_color = Color(0.08, 0.07, 0.07)
	_mat_base.emission = Color(1.0, 0.3, 0.05)
	_flash = 0.8
	if _light != null:
		_light.visible = false
	if _roof_box != null and is_instance_valid(_roof_box) and kind != "tree":
		_roof_box.scale = Vector3(1.0, 0.35, 1.0)
		_roof_box.position.y = house_size.y + 0.15
	if _visual_root != null and is_inside_tree():
		if _pop_tween != null and _pop_tween.is_valid():
			_pop_tween.kill()
		_visual_root.scale = Vector3.ONE
		var tw := _visual_root.create_tween()
		tw.tween_property(_visual_root, "scale", Vector3(1.18, 0.55, 1.18), 0.16)
		tw.tween_property(_visual_root, "scale", Vector3(1.1, 0.7, 1.1), 0.25)
	burned_out.emit(self)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 1.2)
	if state != State.BURNING:
		if _mat_base != null:
			if state == State.BURNT:
				_mat_base.emission = Color(1.0, 0.3, 0.05)
				_mat_base.emission_energy_multiplier = _flash * 1.2
			elif _flash > 0.0:
				_mat_base.emission = Color(1.0, 0.5, 0.1)
				_mat_base.emission_energy_multiplier = _flash * 1.6
			else:
				_mat_base.emission_energy_multiplier = 0.0
		return
	# Burning: simple fuel countdown, local flicker clock (no global sim).
	if _phase_off < 0.0:
		_phase_off = fmod(float(abs(get_instance_id())) * 0.618, TAU)
	_flicker_t += delta * 12.0
	var t := _flicker_t + _phase_off
	fuel -= delta * 1.0
	if not _scorched and fuel < fuel_max * 0.5:
		_scorched = true
		if _mat_base != null:
			_mat_base.albedo_color = base_color * 0.55
		if _mat_roof != null:
			_mat_roof.albedo_color = roof_color * 0.55
	for i in _flames.size():
		var f := _flames[i]
		var s := 1.0 + sin(t + float(i) * 2.1) * 0.18 + randf_range(-0.06, 0.06)
		f.scale = Vector3(s, 1.0 + sin(t * 1.3 + float(i)) * 0.22, s)
		f.rotation.y += delta * (1.5 + float(i) * 0.7)
	if _light:
		_light.light_energy = 1.4 + sin(t * 1.7) * 0.4 + randf_range(-0.15, 0.15)
	if _mat_base != null:
		if _flash > 0.0:
			_mat_base.emission = Color(1.0, 0.5, 0.1)
			_mat_base.emission_energy_multiplier = _flash * 1.6
		elif _scorched:
			_mat_base.emission = Color(0.45, 0.08, 0.05)
			_mat_base.emission_energy_multiplier = 0.5
		else:
			_mat_base.emission_energy_multiplier = 0.0
	if fuel <= 0.0:
		_burn_out()
