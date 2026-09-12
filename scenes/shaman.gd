extends CharacterBody3D
class_name VoxelShaman
## Voxel Shaman / Ritualist — High-priority mini-objective (SPEC Section 6.7 & 9.4).
## Stands at a ritual site and conducts a telegraphed 10-second ritual.
## If completed, summons settlement-wide rain suppressing fire.
## Immune to direct manual clicks; player must route fire to the ritual site!
## Catching fire interrupts the ritual, forces the shaman to flee screaming,
## and grants the player +1 Ember (SPEC Section 6.5).

signal ritual_started(shaman: VoxelShaman)
signal ritual_tick(remaining: float)
signal ritual_interrupted(shaman: VoxelShaman)
signal ritual_completed(shaman: VoxelShaman)
signal defeated(shaman: VoxelShaman)

const CharBurnScript := preload("res://scenes/char_burn.gd")

enum State { IDLE, CASTING, FLEEING, DEAD }

var state: int = State.IDLE
var cast_time_total: float = 10.0
var cast_time_remaining: float = 10.0
var speed_flee: float = 4.6
var burn: CharBurn = null

var _visual: Node3D = null
var _ritual_vfx: Node3D = null
var _ritual_circle: MeshInstance3D = null
var _ritual_particles: GPUParticles3D = null
var _ritual_label: Label3D = null
var _bubble: Label3D = null
var _bubble_t: float = 0.0
var _dead: bool = false
var _shout_t: float = 0.0
var _spread_t: float = 0.0
var catch_cd: float = 0.0


func _ready() -> void:
	add_to_group("shamans")
	add_to_group("flammable")
	_build_collision()
	_build_visuals()
	_build_ritual_vfx()
	_build_bubble()

	burn = CharBurnScript.new()
	add_child(burn)
	burn.configure(self, _visual, 1.8, randf_range(8.0, 10.5))
	burn.died.connect(_on_burn_death)
	burn.ignited.connect(_on_burn_ignited)


func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 1.6, 0.7)
	col.shape = box
	col.position = Vector3(0, 0.8, 0)
	add_child(col)


func _mat(c: Color, emit: bool = false, energy: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if emit:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	bm_setup(b, size, mat)
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)
	return mi


func bm_setup(b: BoxMesh, size: Vector3, mat: Material) -> void:
	b.size = size
	b.material = mat


func _build_visuals() -> void:
	_visual = Node3D.new()
	_visual.name = "ShamanVisual"
	add_child(_visual)

	# Robe: Mystic indigo/purple with ceremonial gold trim
	var robe_col := _mat(Color(0.35, 0.14, 0.52))
	var trim_col := _mat(Color(0.95, 0.82, 0.18), true, 1.2)
	var skin_col := _mat(Color(0.92, 0.74, 0.58))
	var wood_col := _mat(Color(0.38, 0.24, 0.14))
	var orb_col := _mat(Color(0.2, 0.85, 0.95), true, 2.5) # Glowing cyan orb

	# Robe skirt & torso
	_box(_visual, Vector3(0.65, 0.8, 0.55), Vector3(0, 0.4, 0), robe_col)
	_box(_visual, Vector3(0.55, 0.6, 0.45), Vector3(0, 0.9, 0), robe_col)
	_box(_visual, Vector3(0.57, 0.12, 0.47), Vector3(0, 0.8, 0), trim_col)
	_box(_visual, Vector3(0.12, 0.6, 0.48), Vector3(0, 0.9, 0), trim_col)

	# Head
	_box(_visual, Vector3(0.42, 0.38, 0.42), Vector3(0, 1.35, 0), skin_col)

	# Mystic Headdress / Antlers
	var antler_col := _mat(Color(0.85, 0.8, 0.72))
	_box(_visual, Vector3(0.5, 0.14, 0.5), Vector3(0, 1.58, 0), robe_col)
	_box(_visual, Vector3(0.12, 0.45, 0.12), Vector3(-0.25, 1.82, 0), antler_col)
	_box(_visual, Vector3(0.12, 0.45, 0.12), Vector3(0.25, 1.82, 0), antler_col)
	_box(_visual, Vector3(0.25, 0.1, 0.1), Vector3(-0.32, 1.95, 0), antler_col)
	_box(_visual, Vector3(0.25, 0.1, 0.1), Vector3(0.32, 1.95, 0), antler_col)

	# Ritual Staff in hand
	_box(_visual, Vector3(0.1, 1.8, 0.1), Vector3(0.42, 0.9, 0.25), wood_col)
	_box(_visual, Vector3(0.28, 0.28, 0.28), Vector3(0.42, 1.85, 0.25), orb_col)


func _build_ritual_vfx() -> void:
	_ritual_vfx = Node3D.new()
	_ritual_vfx.name = "RitualTelegraph"
	add_child(_ritual_vfx)

	# Ritual Circle Mesh
	_ritual_circle = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.4
	cyl.bottom_radius = 2.4
	cyl.height = 0.05
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.75, 0.95, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.65, 0.9)
	mat.emission_energy_multiplier = 1.8
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.material = mat
	_ritual_circle.mesh = cyl
	_ritual_circle.position = Vector3(0, 0.03, 0)
	_ritual_vfx.add_child(_ritual_circle)

	# Swirling ascending mystic particles
	_ritual_particles = GPUParticles3D.new()
	_ritual_particles.amount = 28
	_ritual_particles.lifetime = 1.4
	_ritual_particles.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 20.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, 1.5, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.color = Color(0.3, 0.85, 1.0, 0.8)
	_ritual_particles.process_material = pm

	var quad := BoxMesh.new()
	quad.size = Vector3(0.12, 0.12, 0.12)
	var qm := StandardMaterial3D.new()
	qm.albedo_color = Color(0.2, 0.8, 1.0)
	qm.emission_enabled = true
	qm.emission = Color(0.2, 0.8, 1.0)
	qm.emission_energy_multiplier = 2.5
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = qm
	_ritual_particles.draw_pass_1 = quad

	_ritual_vfx.add_child(_ritual_particles)
	_ritual_particles.position = Vector3(0, 0.2, 0)

	# 3D Billboard Label
	_ritual_label = Label3D.new()
	_ritual_label.text = "SUMMONING RAIN\n[ 10.0s ]"
	_ritual_label.font_size = 60
	_ritual_label.pixel_size = 0.009
	_ritual_label.modulate = Color(0.3, 0.9, 1.0)
	_ritual_label.outline_size = 14
	_ritual_label.outline_modulate = Color(0.05, 0.15, 0.3)
	_ritual_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_ritual_label.position = Vector3(0, 2.6, 0)
	_ritual_vfx.add_child(_ritual_label)

	_ritual_vfx.hide()


func _build_bubble() -> void:
	_bubble = Label3D.new()
	_bubble.text = "!"
	_bubble.font_size = 120
	_bubble.pixel_size = 0.012
	_bubble.modulate = Color(1.0, 0.85, 0.2)
	_bubble.outline_size = 16
	_bubble.outline_modulate = Color(0.1, 0.05, 0.05)
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.position = Vector3(0, 2.4, 0)
	_bubble.visible = false
	add_child(_bubble)


func start_ritual() -> void:
	if state != State.IDLE:
		return
	state = State.CASTING
	cast_time_remaining = cast_time_total
	if _ritual_vfx != null:
		_ritual_vfx.show()
	_show_bubble("RITUAL!", Color(0.3, 0.85, 1.0))
	ritual_started.emit(self)


func interrupt_ritual() -> void:
	if state != State.CASTING:
		return
	state = State.FLEEING
	if _ritual_vfx != null:
		_ritual_vfx.hide()
	_show_bubble("CURSE IT!!", Color(1.0, 0.2, 0.1))
	ritual_interrupted.emit(self)
	defeated.emit(self)


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
	if state == State.CASTING:
		interrupt_ritual()
	else:
		state = State.FLEEING
		defeated.emit(self)
	_show_bubble("AAA!!", Color(1.0, 0.3, 0.1))


func _on_burn_death() -> void:
	_dead = true
	state = State.DEAD
	if _ritual_vfx != null:
		_ritual_vfx.hide()
	if _bubble != null:
		_bubble.visible = false


func _process(delta: float) -> void:
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0 and _bubble != null:
			_bubble.visible = false

	if state == State.CASTING:
		cast_time_remaining = maxf(0.0, cast_time_remaining - delta)
		if _ritual_label != null:
			_ritual_label.text = "SUMMONING RAIN\n[ %.1fs ]" % cast_time_remaining
		if _ritual_circle != null:
			_ritual_circle.rotation.y += delta * 1.5
		ritual_tick.emit(cast_time_remaining)

		# Idle chanting bob
		_visual.position.y = absf(sin(float(Time.get_ticks_msec()) * 0.008)) * 0.12

		if cast_time_remaining <= 0.0:
			_complete_ritual()


func _physics_process(delta: float) -> void:
	if _dead:
		return

	if catch_cd > 0.0:
		catch_cd -= delta

	if is_burning():
		_physics_flee(delta)
	elif state == State.IDLE:
		_check_catch_fire()


func _complete_ritual() -> void:
	state = State.IDLE
	if _ritual_vfx != null:
		_ritual_vfx.hide()
	_show_bubble("RAIN FALLS!", Color(0.2, 0.6, 1.0))
	ritual_completed.emit(self)


func _physics_flee(delta: float) -> void:
	_spread_t -= delta
	if _spread_t <= 0.0:
		_spread_t = 0.7
		_spread_fire()

	_shout_t -= delta
	if _shout_t <= 0.0:
		_shout_t = randf_range(1.0, 1.8)
		_show_bubble("AAA!!", Color(1.0, 0.3, 0.1))

	# Run away from nearest fire
	var away := Vector3.ZERO
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.BURNING:
			var to: Vector3 = global_position - h.global_position
			to.y = 0.0
			var d := to.length()
			if d < 10.0 and d > 0.01:
				away += to.normalized() * (1.0 - d / 10.0)
	away.y = 0.0
	if away.length() < 0.05:
		away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	var dir := away.normalized()
	velocity = dir * speed_flee
	_visual.rotation.y = atan2(dir.x, dir.z)
	_visual.position.y = absf(sin(float(Time.get_ticks_msec()) * 0.025)) * 0.15
	move_and_slide()


func _check_catch_fire() -> void:
	if catch_cd > 0.0:
		return
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.BURNING:
			if global_position.distance_to(h.global_position) < 2.5:
				catch_cd = 0.6
				ignite()
				return
	for c in get_tree().get_nodes_in_group("burning_chars"):
		if c is Node3D and c != self:
			if global_position.distance_to((c as Node3D).global_position) < 1.6:
				catch_cd = 0.6
				ignite()
				return


func _spread_fire() -> void:
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.UNBURNED:
			if global_position.distance_to(h.global_position) < 2.5:
				if randf() < 0.25:
					h.ignite()
					break


func _show_bubble(text: String, col: Color) -> void:
	if _bubble == null:
		return
	_bubble.text = text
	_bubble.modulate = col
	_bubble.visible = true
	_bubble_t = 1.4
