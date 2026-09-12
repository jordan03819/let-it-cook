class_name VoxelHelicopter
extends Node3D
## VoxelHelicopter — Aerial Water Drop Countermeasure (SPEC Section 6.7, 10.3 & 11.3).
## In Level 3 (City), flies over an active burning cluster, displays a 5-second
## telegraphed drop zone on the ground, and executes a targeted water drop
## that heavily wets structures and characters in that cluster.

signal drop_executed(pos: Vector3, radius: float)
signal flight_completed()

var start_pos: Vector3 = Vector3.ZERO
var target_pos: Vector3 = Vector3.ZERO
var exit_pos: Vector3 = Vector3.ZERO
var warning_duration: float = 5.0
var drop_radius: float = 6.5

var timer: float = 0.0
var altitude: float = 6.8
var dropped: bool = false
var completed: bool = false

var _heli_root: Node3D = null
var _main_rotor: MeshInstance3D = null
var _tail_rotor: MeshInstance3D = null
var _shadow: MeshInstance3D = null
var _reticle_root: Node3D = null
var _reticle_ring: MeshInstance3D = null
var _reticle_label: Label3D = null
var _deluge_particles: GPUParticles3D = null


func setup(p_start_pos: Vector3, p_target_pos: Vector3, p_exit_pos: Vector3, p_warning: float = 5.0, p_radius: float = 6.5) -> void:
	start_pos = p_start_pos
	target_pos = p_target_pos
	exit_pos = p_exit_pos
	warning_duration = p_warning
	drop_radius = p_radius
	timer = 0.0
	dropped = false
	completed = false
	if is_node_ready():
		if _reticle_root != null:
			_reticle_root.position = Vector3(target_pos.x, 0.08, target_pos.z)
		global_position = start_pos


func _ready() -> void:
	if _heli_root == null:
		_build_reticle()
		_build_helicopter_visual()
		_build_shadow()
	global_position = start_pos


func _voxel_mat(c: Color, emit: bool = false, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if emit:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
	return m


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---------- Ground Telegraph Reticle ----------
func _build_reticle() -> void:
	_reticle_root = Node3D.new()
	_reticle_root.name = "DropZoneReticle"
	_reticle_root.position = Vector3(target_pos.x, 0.08, target_pos.z)
	add_child(_reticle_root)

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.2, 0.75, 1.0, 0.75)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.15, 0.65, 0.95)
	ring_mat.emission_energy_multiplier = 1.8
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var ring_mesh := ImmediateMesh.new()
	_reticle_ring = MeshInstance3D.new()
	_reticle_ring.mesh = ring_mesh
	_reticle_root.add_child(_reticle_ring)

	ring_mesh.surface_begin(Mesh.PRIMITIVE_LINES, ring_mat)
	var segs := 32
	for i in segs:
		var a1 := float(i) * TAU / float(segs)
		var a2 := float(i + 1) * TAU / float(segs)
		var p1 := Vector3(cos(a1) * drop_radius, 0.02, sin(a1) * drop_radius)
		var p2 := Vector3(cos(a2) * drop_radius, 0.02, sin(a2) * drop_radius)
		ring_mesh.surface_add_vertex(p1)
		ring_mesh.surface_add_vertex(p2)

		# Inner warning ring
		var ip1 := p1 * 0.6
		var ip2 := p2 * 0.6
		ring_mesh.surface_add_vertex(ip1)
		ring_mesh.surface_add_vertex(ip2)

	# Crosshairs
	var arm := drop_radius * 1.15
	ring_mesh.surface_add_vertex(Vector3(-arm, 0.02, 0))
	ring_mesh.surface_add_vertex(Vector3(arm, 0.02, 0))
	ring_mesh.surface_add_vertex(Vector3(0, 0.02, -arm))
	ring_mesh.surface_add_vertex(Vector3(0, 0.02, arm))
	ring_mesh.surface_end()

	# 3D Telegraph Label
	_reticle_label = Label3D.new()
	_reticle_label.name = "DropLabel"
	_reticle_label.text = "WATER DROP ZONE\n[ 5.0s ]"
	_reticle_label.font_size = 96
	_reticle_label.pixel_size = 0.014
	_reticle_label.modulate = Color(0.2, 0.85, 1.0)
	_reticle_label.outline_size = 14
	_reticle_label.outline_modulate = Color(0.05, 0.1, 0.25)
	_reticle_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_reticle_label.position = Vector3(0, 2.2, 0)
	_reticle_root.add_child(_reticle_label)


# ---------- Voxel Helicopter Model ----------
func _build_helicopter_visual() -> void:
	_heli_root = Node3D.new()
	_heli_root.name = "HelicopterMesh"
	add_child(_heli_root)

	var red_fuselage := _voxel_mat(Color(0.85, 0.18, 0.14))
	var white_trim := _voxel_mat(Color(0.95, 0.95, 0.96))
	var dark_metal := _voxel_mat(Color(0.22, 0.22, 0.25))
	var glass_cyan := _voxel_mat(Color(0.25, 0.72, 0.92, 0.85), true, 0.8)
	var yellow_stripe := _voxel_mat(Color(0.95, 0.85, 0.15), true, 1.2)
	var water_tank_blue := _voxel_mat(Color(0.18, 0.42, 0.75))

	# Main cabin
	_add_box(_heli_root, Vector3(2.4, 1.4, 1.5), Vector3(0, 0, 0), red_fuselage)
	_add_box(_heli_root, Vector3(2.42, 0.2, 1.52), Vector3(0, 0.1, 0), white_trim)

	# Sloped nose & cockpit glass
	_add_box(_heli_root, Vector3(1.0, 1.0, 1.3), Vector3(1.4, -0.15, 0), white_trim)
	_add_box(_heli_root, Vector3(0.8, 0.65, 1.15), Vector3(1.35, 0.25, 0), glass_cyan)

	# Belly water tank dispenser
	_add_box(_heli_root, Vector3(1.8, 0.55, 1.1), Vector3(0, -0.85, 0), water_tank_blue)
	_add_box(_heli_root, Vector3(1.82, 0.12, 1.12), Vector3(0, -0.85, 0), yellow_stripe)

	# Landing skids
	for sz in [-0.75, 0.75]:
		_add_box(_heli_root, Vector3(2.6, 0.1, 0.12), Vector3(0.2, -1.2, sz), dark_metal)
		_add_box(_heli_root, Vector3(0.1, 0.35, 0.1), Vector3(0.8, -1.0, sz), dark_metal)
		_add_box(_heli_root, Vector3(0.1, 0.35, 0.1), Vector3(-0.6, -1.0, sz), dark_metal)

	# Tail boom
	_add_box(_heli_root, Vector3(3.2, 0.45, 0.45), Vector3(-2.6, 0.1, 0), red_fuselage)
	_add_box(_heli_root, Vector3(0.5, 1.2, 0.14), Vector3(-4.1, 0.6, 0), white_trim)
	_add_box(_heli_root, Vector3(0.12, 0.15, 1.2), Vector3(-3.2, 0.1, 0), dark_metal)

	# Main rotor mast & spinning blades
	_add_box(_heli_root, Vector3(0.25, 0.5, 0.25), Vector3(0, 0.85, 0), dark_metal)
	_main_rotor = MeshInstance3D.new()
	var b_mesh := BoxMesh.new()
	b_mesh.size = Vector3(6.4, 0.06, 0.38)
	b_mesh.material = dark_metal
	_main_rotor.mesh = b_mesh
	_main_rotor.position = Vector3(0, 1.1, 0)
	_heli_root.add_child(_main_rotor)

	# Tail rotor
	_tail_rotor = MeshInstance3D.new()
	var tr_mesh := BoxMesh.new()
	tr_mesh.size = Vector3(0.06, 1.0, 0.14)
	tr_mesh.material = dark_metal
	_tail_rotor.mesh = tr_mesh
	_tail_rotor.position = Vector3(-4.2, 0.9, 0.16)
	_heli_root.add_child(_tail_rotor)


# ---------- Ground Shadow ----------
func _build_shadow() -> void:
	_shadow = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.2, 0.02, 1.8)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.05, 0.05, 0.08, 0.45)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = sm
	_shadow.mesh = bm
	add_child(_shadow)


# ---------- Frame Loop ----------
func _process(delta: float) -> void:
	if completed or _heli_root == null:
		return

	# Spin rotors
	if _main_rotor != null:
		_main_rotor.rotation.y += delta * 45.0
	if _tail_rotor != null:
		_tail_rotor.rotation.z += delta * 50.0

	timer += delta

	# Position interpolation
	var cur_pos := Vector3.ZERO
	var target_air_pos := Vector3(target_pos.x, altitude, target_pos.z)

	if not dropped and timer >= warning_duration:
		_execute_drop()

	if timer <= warning_duration:
		# Approach phase: fly from start_pos to target_air_pos
		var t_ratio := clampf(timer / warning_duration, 0.0, 1.0)
		cur_pos = start_pos.lerp(target_air_pos, t_ratio)

		# Face flight direction with slight aerodynamic forward tilt
		var fwd := (target_air_pos - start_pos).normalized()
		if fwd.length_squared() > 0.01:
			_heli_root.rotation.y = atan2(-fwd.z, fwd.x)
			_heli_root.rotation.z = -0.12 # slight nose-down flight attitude

		# Reticle countdown pulse
		var rem := maxf(0.0, warning_duration - timer)
		if _reticle_label != null:
			_reticle_label.text = "WATER DROP ZONE\n[ %.1fs ]" % rem
			var pulse := 0.7 + 0.3 * sin(float(Time.get_ticks_msec()) * 0.015)
			_reticle_label.modulate = Color(1.0, pulse * 0.6, 0.2) if rem < 2.0 else Color(0.2, 0.85, 1.0)
	else:
		# Exit phase: fly from target_air_pos to exit_pos
		var exit_time := 3.2
		var t_ratio := clampf((timer - warning_duration) / exit_time, 0.0, 1.0)
		cur_pos = target_air_pos.lerp(exit_pos, t_ratio)

		var fwd := (exit_pos - target_air_pos).normalized()
		if fwd.length_squared() > 0.01:
			_heli_root.rotation.y = atan2(-fwd.z, fwd.x)
			_heli_root.rotation.z = -0.08
			_heli_root.rotation.y = atan2(-fwd.z, fwd.x)

		if t_ratio >= 1.0:
			completed = true
			flight_completed.emit()
			queue_free()

	_heli_root.global_position = cur_pos

	# Follow ground shadow
	if _shadow != null:
		_shadow.global_position = Vector3(cur_pos.x, 0.06, cur_pos.z)
		_shadow.rotation.y = _heli_root.rotation.y


# ---------- Water Drop Execution (SPEC Section 10.3) ----------
func _execute_drop() -> void:
	dropped = true
	SoundManager.play_sfx("splash", 0.75, 4.0)

	# Spawn aerial water deluge
	_spawn_water_drop_vfx()

	# Heavily wet the targeted cluster (SPEC Section 10.3)
	# 1. Structures (Houses & Trees)
	for h in get_tree().get_nodes_in_group("houses"):
		if is_instance_valid(h) and h is VoxelHouse:
			var d := target_pos.distance_to(h.global_position)
			if d <= drop_radius:
				# Heavy saturation: douses burning, saturates unburned to resist ignition
				h.apply_water(1.6, 1.0)

	# 2. Explosive Barrels
	for b in get_tree().get_nodes_in_group("barrels"):
		if is_instance_valid(b) and b is VoxelBarrel:
			var d := target_pos.distance_to(b.global_position)
			if d <= drop_radius:
				b.apply_water(1.2, 1.0)

	# 3. Flammable Units (extinguish burning people caught in the drop)
	for u in get_tree().get_nodes_in_group("flammable"):
		if is_instance_valid(u) and u is CharacterBody3D:
			var d := target_pos.distance_to(u.global_position)
			if d <= drop_radius:
				for c in u.get_children():
					if c is CharBurn:
						c.extinguish()

	# Fade out reticle
	if _reticle_root != null:
		var tw := create_tween()
		tw.tween_property(_reticle_root, "scale", Vector3.ZERO, 0.8)
		tw.tween_callback(_reticle_root.queue_free)

	drop_executed.emit(target_pos, drop_radius)


func _spawn_water_drop_vfx() -> void:
	# Downward water torrent particles
	var deluge := GPUParticles3D.new()
	deluge.amount = 90
	deluge.lifetime = 0.65
	deluge.one_shot = true
	deluge.explosiveness = 0.85
	deluge.visibility_aabb = AABB(Vector3(-8, -14, -8), Vector3(16, 18, 16))

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 18.0
	pm.initial_velocity_max = 24.0
	pm.gravity = Vector3(0, -18.0, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.8
	pm.color = Color(0.65, 0.85, 1.0, 0.85)
	deluge.process_material = pm

	var drop_mesh := BoxMesh.new()
	drop_mesh.size = Vector3(0.25, 0.55, 0.25)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.65, 0.85, 1.0, 0.8)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_mesh.material = sm
	deluge.draw_pass_1 = drop_mesh

	add_child(deluge)
	deluge.global_position = Vector3(target_pos.x, altitude - 0.8, target_pos.z)
	deluge.emitting = true

	# Ground splash / mist cloud
	var splash := GPUParticles3D.new()
	splash.amount = 40
	splash.lifetime = 1.2
	splash.one_shot = true
	splash.explosiveness = 0.9
	splash.visibility_aabb = AABB(Vector3(-8, 0, -8), Vector3(16, 6, 16))

	var sp_pm := ParticleProcessMaterial.new()
	sp_pm.direction = Vector3(0, 1, 0)
	sp_pm.spread = 80.0
	sp_pm.initial_velocity_min = 3.5
	sp_pm.initial_velocity_max = 6.5
	sp_pm.gravity = Vector3(0, 0.5, 0)
	sp_pm.scale_min = 1.2
	sp_pm.scale_max = 2.4
	sp_pm.color = Color(0.8, 0.9, 0.98, 0.6)
	splash.process_material = sp_pm

	var splash_mesh := BoxMesh.new()
	splash_mesh.size = Vector3(0.35, 0.35, 0.35)
	splash_mesh.material = sm
	splash.draw_pass_1 = splash_mesh

	add_child(splash)
	splash.global_position = Vector3(target_pos.x, 0.3, target_pos.z)
	splash.emitting = true
