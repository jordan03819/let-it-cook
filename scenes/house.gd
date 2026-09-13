extends StaticBody3D
class_name VoxelHouse
## REFORMED VoxelHouse — burn + demolish.
## States: UNBURNED -> BURNING -> BURNT. DEMOLISHED is a villager firebreak:
## flattened rubble, never burns, never spreads, never counts as burnt.

signal burned_out(house: VoxelHouse)
signal ignited(house: VoxelHouse)
signal extinguished(house: VoxelHouse)
signal demolished(house: VoxelHouse)
signal burn_ending(house: VoxelHouse)

enum State { UNBURNED, BURNING, BURNT, DEMOLISHED, SMOLDERING }

var state: int = State.UNBURNED
var fuel_max: float = 22.0
var fuel: float = 22.0
var heat: float = 0.0 # 0..1 warming from nearby burning buildings. 1 = catches.
var wetness: float = 0.0 # 0..1 water saturation; cools heat, resists fire, dries over time
## Water delivered since this building caught. Putting a fire *out* takes a
## quantity of water rather than a splash: see WATER_TO_EXTINGUISH. It bleeds
## away while nobody is spraying, so a brigade has to keep at it (SPEC 6.7).
var water_soaked: float = 0.0
var kind: String = "house" # house | tree | stone
var house_size: Vector3 = Vector3(2.0, 1.6, 2.0)
var base_color: Color = Color(0.9, 0.8, 0.65)
var roof_color: Color = Color(0.75, 0.25, 0.15)
var smolder_timer: float = 0.0

var _smolder_label: Label3D = null
var _gust_tilt: Vector3 = Vector3.ZERO
var _tree_foliage_mats: Array[StandardMaterial3D] = []

## Water needed to smother a burning structure, and the smaller amount that
## snuffs a last spark. A bucket delivers 0.55, so a brigade needs ~6 trips for
## a house, a firefighter's hose ~1.7 seconds, and a helicopter drop still needs
## a second pass to finish the job.
const WATER_TO_EXTINGUISH: float = 3.2
const WATER_TO_DOUSE_SMOLDER: float = 0.9
## How fast delivered water evaporates off a burning building (per second).
const WATER_SOAK_DECAY: float = 0.10

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

# --- Model visuals ---------------------------------------------------------
# A house can be authored as a scene with its kit geometry baked in as a child
# named "Model" (see scenes/houses/ and scenes/kit_house.gd). In that mode the
# placeholder boxes are never built and every runtime cue — heat glow, wet
# sheen, scorch, smoulder, the burnt look — is applied to the model's own
# materials instead, so a kit house feeds back exactly like a voxel one.
const MODEL_NODE_NAME := "Model"
## Metadata the house reads off its model: the per-role tint table on the model
## root, and the role tag on each piece (see scenes/kit_house.gd).
const META_TINTS_META := "kit_tints"
const META_ROLE_META := "kit_role"
var visual_style: String = "voxel" # voxel | model
var _model_root: Node3D = null
var _model_mats: Array[StandardMaterial3D] = []
var _model_base: Array[Color] = []

# Progressive pre-ignition in-world feedback (SPEC Section 6.4)
var _warmth_root: Node3D = null
var _smoke_warmth: GPUParticles3D = null
var _sparks_warmth: GPUParticles3D = null

# Environmental wind & foliage sway (SPEC Section 7.3)
var _ambient_wind_dir: Vector3 = Vector3.ZERO
var _ambient_wind_strength: float = 1.0
var _tree_mesh_mid: MeshInstance3D = null
var _tree_mesh_top: MeshInstance3D = null


func setup(p_base_color: Color, p_roof_color: Color, p_fuel: float, p_size: Vector3, p_kind: String = "house") -> void:
	base_color = p_base_color
	roof_color = p_roof_color
	fuel_max = p_fuel
	fuel = p_fuel
	heat = 0.0
	wetness = 0.0
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
	var baked := get_node_or_null(MODEL_NODE_NAME) as Node3D
	if baked != null:
		attach_model(baked)
	else:
		_build_visuals()
	_build_fire_visuals()
	_build_warmth_visuals()
	_set_fire_visible(false)


## Switches this house to a kit model. Called automatically for a scene that
## carries a child named "Model"; also usable at runtime for a house assembled
## in code.
##
## Every mesh gets its own material copy, tinted by the role its piece was
## tagged with in the scene (KitHouse.META_ROLE) and recorded in KitHouse's
## per-role tint table (KitHouse.META_TINTS). Owning the materials is the whole
## point: kit models otherwise share one material per piece type across the
## level, so one burning cottage and one cold cottage would fight over the same
## glow, and neither could scorch without scorching the other.
func attach_model(model: Node3D) -> void:
	visual_style = "model"
	_model_root = model
	_model_mats.clear()
	_model_base.clear()
	var tints: Dictionary = model.get_meta(META_TINTS_META, {})
	for piece in _model_pieces(model):
		var role := str(piece.get_meta(META_ROLE_META, "wall"))
		var tint: Color = tints.get(role, Color.WHITE)
		for mi in KitHouse.mesh_instances(piece):
			var src := mi.get_active_material(0) as StandardMaterial3D
			var mat := StandardMaterial3D.new()
			if src != null:
				mat = src.duplicate()
			mat.metallic = 0.0
			mat.roughness = 0.9
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.albedo_color = mat.albedo_color * tint
			mat.emission_enabled = true
			mat.emission = Color(0, 0, 0)
			mat.emission_energy_multiplier = 0.0
			mi.material_override = mat
			_model_mats.append(mat)
			_model_base.append(mat.albedo_color)
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.visible = false
	_sync_model_look()


## The piece nodes of a kit model, tags and all: a model's direct children are
## its pieces.
func _model_pieces(model: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in model.get_children():
		if c is Node3D:
			out.append(c as Node3D)
	return out


## Writes the current heat / wetness / scorch state onto the model materials.
func _sync_model_look() -> void:
	if _model_mats.is_empty():
		return
	var wet_factor := 1.0 - wetness * 0.35
	var scorch_factor := 1.0
	if state == State.BURNT:
		scorch_factor = 0.22
	elif _scorched:
		scorch_factor = 0.55
	elif state == State.UNBURNED and heat > 0.45:
		scorch_factor = 1.0 - (heat - 0.45) * 0.6
	var emission_colour := Color(0, 0, 0)
	var emission_energy := 0.0
	if state == State.SMOLDERING:
		emission_colour = Color(1.0, 0.25, 0.05)
		emission_energy = 0.8 + 0.4 * sin(float(Time.get_ticks_msec()) * 0.008)
	elif state == State.BURNT:
		emission_colour = Color(1.0, 0.3, 0.05)
		emission_energy = _flash * 1.2
	elif _flash > 0.0:
		emission_colour = Color(1.0, 0.5, 0.1)
		emission_energy = _flash * 1.6
	elif state == State.BURNING:
		emission_colour = Color(0.45, 0.08, 0.05) if _scorched else Color(0.9, 0.25, 0.05)
		emission_energy = 0.5 if _scorched else 0.35 + heat * 0.8
	elif kind != "stone" and heat > 0.02:
		# Warming forecast: hotter reads brighter. This IS the UI.
		emission_colour = Color(1.0, 0.45, 0.1)
		emission_energy = heat * 1.4
	for i in _model_mats.size():
		var mat := _model_mats[i]
		if i < _model_base.size():
			mat.albedo_color = _shaded(_model_base[i], scorch_factor * wet_factor)
		mat.roughness = clampf(0.9 - wetness * 0.6, 0.3, 1.0)
		mat.emission = emission_colour
		mat.emission_energy_multiplier = emission_energy


static func _shaded(c: Color, factor: float) -> Color:
	return Color(minf(c.r * factor, 1.0), minf(c.g * factor, 1.0), minf(c.b * factor, 1.0), c.a)


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
	if visual_style == "model":
		for c in get_children():
			if c is CollisionShape3D:
				c.queue_free()
		_build_collision()
		_sync_model_look()
		return
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
	elif kind == "stone":
		_build_stone_visuals()
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
	_tree_foliage_mats.clear()
	_mat_base = _voxel_mat(Color(0.42, 0.27, 0.13))
	_mat_roof = _voxel_mat(Color(0.14, 0.56, 0.2))
	_tree_foliage_mats.append(_mat_roof)
	var mat_mid := _voxel_mat(Color(0.18, 0.63, 0.24))
	_tree_foliage_mats.append(mat_mid)
	var mat_top := _voxel_mat(Color(0.25, 0.7, 0.28))
	_tree_foliage_mats.append(mat_top)

	_add_box(_visual_root, Vector3(0.35, 1.1, 0.35), Vector3(0, 0.55, 0), _mat_base)
	_roof_box = _add_box(_visual_root, Vector3(1.6, 0.9, 1.6), Vector3(0, 1.4, 0), _mat_roof)
	_tree_mesh_mid = _add_box(_visual_root, Vector3(1.15, 0.8, 1.15), Vector3(0, 2.1, 0), mat_mid)
	_tree_mesh_top = _add_box(_visual_root, Vector3(0.65, 0.5, 0.65), Vector3(0, 2.7, 0), mat_top)


func _build_stone_visuals() -> void:
	_mat_base = _voxel_mat(base_color if base_color != Color(0.9, 0.8, 0.65) else Color(0.48, 0.46, 0.45))
	_mat_roof = _voxel_mat(roof_color if roof_color != Color(0.75, 0.25, 0.15) else Color(0.24, 0.25, 0.28))
	var stone_dark := _voxel_mat(Color(0.34, 0.33, 0.32))
	var iron_mat := _voxel_mat(Color(0.18, 0.18, 0.2))

	# Heavy masonry base
	_base_box = _add_box(_visual_root, house_size, Vector3(0, house_size.y * 0.5, 0), _mat_base)

	# Stone corner buttresses
	var pw: float = 0.4
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var px: float = sx * (house_size.x * 0.5 + pw * 0.15)
			var pz: float = sz * (house_size.z * 0.5 + pw * 0.15)
			_add_box(_visual_root, Vector3(pw, house_size.y + 0.3, pw), Vector3(px, (house_size.y + 0.3) * 0.5, pz), stone_dark)

	# Crenellated roof parapet
	var parapet_size := Vector3(house_size.x + 0.3, 0.5, house_size.z + 0.3)
	_roof_box = _add_box(_visual_root, parapet_size, Vector3(0, house_size.y + 0.25, 0), _mat_roof)

	# Battlements
	for sx: float in [-1.0, 1.0]:
		_add_box(_visual_root, Vector3(house_size.x * 0.35, 0.35, 0.25), Vector3(sx * house_size.x * 0.3, house_size.y + 0.65, house_size.z * 0.5), stone_dark)
		_add_box(_visual_root, Vector3(house_size.x * 0.35, 0.35, 0.25), Vector3(sx * house_size.x * 0.3, house_size.y + 0.65, -house_size.z * 0.5), stone_dark)

	# Arched entrance
	_add_box(_visual_root, Vector3(0.85, 1.3, 0.12), Vector3(0, 0.65, house_size.z * 0.5 + 0.04), stone_dark)
	_add_box(_visual_root, Vector3(0.65, 1.1, 0.14), Vector3(0, 0.55, house_size.z * 0.5 + 0.05), iron_mat)

	# Narrow arrow slits
	var slit_mat := _voxel_mat(Color(0.1, 0.1, 0.12))
	_add_box(_visual_root, Vector3(0.18, 0.55, 0.08), Vector3(-house_size.x * 0.28, house_size.y * 0.65, house_size.z * 0.5 + 0.02), slit_mat)
	_add_box(_visual_root, Vector3(0.18, 0.55, 0.08), Vector3(house_size.x * 0.28, house_size.y * 0.65, house_size.z * 0.5 + 0.02), slit_mat)


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


func _build_warmth_visuals() -> void:
	if _warmth_root != null and is_instance_valid(_warmth_root):
		_warmth_root.queue_free()
	_warmth_root = Node3D.new()
	_warmth_root.name = "WarmthVisual"
	_warmth_root.position = Vector3(0, house_size.y + 0.2, 0)
	add_child(_warmth_root)

	# Faint smoke for heat >= 0.12 (SPEC 6.4: "1. Warm edge or faint smoke: receiving heat")
	_smoke_warmth = _make_voxel_particles(Color(0.42, 0.40, 0.40, 0.65), Vector3(0.14, 0.14, 0.14), 10, 1.6, Vector3(0, 2.2, 0), 0.7)
	_warmth_root.add_child(_smoke_warmth)
	_smoke_warmth.emitting = false

	# Scorching sparks for heat >= 0.55 (SPEC 6.4: "2. Scorching and sparks: likely to ignite soon")
	_sparks_warmth = _make_voxel_particles(Color(1.0, 0.65, 0.1), Vector3(0.08, 0.08, 0.08), 14, 0.9, Vector3(0, 3.2, 0), 1.2)
	_warmth_root.add_child(_sparks_warmth)
	_sparks_warmth.emitting = false


func _set_fire_visible(v: bool) -> void:
	if _fire_root:
		_fire_root.visible = v
	if v:
		if _warmth_root != null:
			_warmth_root.visible = false
		if _smoke_warmth != null:
			_smoke_warmth.emitting = false
		if _sparks_warmth != null:
			_sparks_warmth.emitting = false
	else:
		if _warmth_root != null:
			_warmth_root.visible = true


# --- core verb: lighting. No conditions besides state. ---
func is_burnable() -> bool:
	return state == State.UNBURNED and kind != "stone"


func apply_ambient_wind(dir: Vector3, strength: float) -> void:
	_ambient_wind_dir = dir
	_ambient_wind_strength = strength


func apply_water(amount: float, delta: float) -> void:
	if kind == "stone" or state == State.BURNT or state == State.DEMOLISHED:
		return
	# Wetness (0..1) is the *damping*: it slows heat build-up and darkens the
	# wood. Putting the fire out is the separate water tally below, so a splash
	# can soak a building without magically ending the fire.
	wetness = clampf(wetness + amount * delta * 1.1, 0.0, 1.0)
	if state == State.BURNING:
		water_soaked += amount * delta
		if water_soaked >= WATER_TO_EXTINGUISH:
			extinguish()
	elif state == State.SMOLDERING:
		water_soaked += amount * delta
		if water_soaked >= WATER_TO_DOUSE_SMOLDER:
			extinguish()
	elif state == State.UNBURNED:
		heat = maxf(0.0, heat - amount * delta * 2.5)


func extinguish() -> void:
	if state != State.BURNING and state != State.SMOLDERING:
		return
	state = State.UNBURNED
	heat = 0.0
	wetness = 0.85
	water_soaked = 0.0
	_set_fire_visible(false)
	if _smolder_label != null and is_instance_valid(_smolder_label):
		_smolder_label.queue_free()
		_smolder_label = null
	if _light != null:
		_light.visible = false
	_flash = 0.6
	_spawn_steam()
	SoundManager.play_sfx("splash")
	extinguished.emit(self)


func _spawn_steam() -> void:
	if not is_inside_tree():
		return
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 1.0
	p.one_shot = true
	p.explosiveness = 0.85
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 28.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0, 1.2, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.8
	pm.color = Color(0.85, 0.88, 0.92, 0.7)
	p.process_material = pm
	var cube := BoxMesh.new()
	cube.size = Vector3(0.2, 0.2, 0.2)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.88, 0.92, 0.6)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cube.material = m
	p.draw_pass_1 = cube
	add_child(p)
	p.position = Vector3(0, house_size.y * 0.7, 0)
	p.emitting = true
	var tree := get_tree()
	if tree != null:
		tree.create_timer(1.6).timeout.connect(p.queue_free)


func demolish() -> bool:
	if state != State.UNBURNED:
		return false
	state = State.DEMOLISHED
	heat = 0.0
	_set_fire_visible(false)
	if _light != null:
		_light.visible = false
	if _mat_base != null:
		_mat_base.albedo_color = Color(0.45, 0.43, 0.4)
		_mat_base.emission_energy_multiplier = 0.0
	if _mat_roof != null:
		_mat_roof.albedo_color = Color(0.35, 0.34, 0.33)
	if _visual_root != null:
		_visual_root.scale = Vector3(1.15, 0.3, 1.15)
	demolished.emit(self)
	return true


func start_smolder(duration: float = 8.0) -> void:
	state = State.SMOLDERING
	smolder_timer = duration
	_set_fire_visible(true)
	for i in _flames.size():
		_flames[i].scale = Vector3(0.35, 0.35, 0.35)
	if _light:
		_light.light_energy = 0.5
	if _smolder_label != null and is_instance_valid(_smolder_label):
		_smolder_label.queue_free()
	_smolder_label = Label3D.new()
	_smolder_label.name = "SmolderLabel"
	_smolder_label.text = "LAST SPARK: %ds\nCLICK (1 EMBER)" % int(ceil(smolder_timer))
	_smolder_label.font_size = 80
	_smolder_label.pixel_size = 0.011
	_smolder_label.modulate = Color(1.0, 0.4, 0.1)
	_smolder_label.outline_size = 14
	_smolder_label.outline_modulate = Color(0.1, 0, 0)
	_smolder_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_smolder_label.position = Vector3(0, house_size.y + 2.2, 0)
	add_child(_smolder_label)
	SoundManager.play_sfx("last_spark")


func reignite(new_fuel: float = 35.0) -> bool:
	if kind == "stone" or (state != State.SMOLDERING and state != State.UNBURNED):
		return false
	state = State.BURNING
	water_soaked = 0.0
	fuel = new_fuel
	fuel_max = maxf(fuel_max, new_fuel)
	heat = 0.0
	if _smolder_label != null and is_instance_valid(_smolder_label):
		_smolder_label.queue_free()
		_smolder_label = null
	_set_fire_visible(true)
	_flash = 1.0
	_pop(1.3)
	SoundManager.play_sfx("ignite")
	ignited.emit(self)
	return true


func apply_gust_tilt(dir: Vector3) -> void:
	_gust_tilt = dir


func ignite() -> bool:
	if kind == "stone" or state != State.UNBURNED:
		return false
	state = State.BURNING
	heat = 0.0
	water_soaked = 0.0
	_set_fire_visible(true)
	_flash = 1.0
	_pop(1.2)
	SoundManager.play_sfx("ignite")
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
	# Only voxel buildings own these two materials; a kit model chars through
	# its own set (see _sync_model_look), so every write here has to be guarded.
	if _mat_base != null:
		_mat_base.albedo_color = Color(0.12, 0.1, 0.1)
		_mat_base.emission = Color(1.0, 0.3, 0.05)
	if _mat_roof != null:
		_mat_roof.albedo_color = Color(0.08, 0.07, 0.07)
	for m in _tree_foliage_mats:
		if m != null:
			m.albedo_color = Color(0.08, 0.07, 0.07)
	_flash = 0.8
	if visual_style == "model":
		_sync_model_look()
	if _light != null:
		_light.visible = false
	if _roof_box != null and is_instance_valid(_roof_box) and kind != "tree":
		_roof_box.scale = Vector3(1.0, 0.35, 1.0)
		_roof_box.position.y = house_size.y + 0.15
	# Collapse the shape that is actually on screen: the placeholder boxes for a
	# voxel building, the kit model for a scene-authored one. A kit model is
	# scaled off its model root, so keep its own scale as the base.
	var shape: Node3D = _model_root if visual_style == "model" else _visual_root
	if shape != null and is_inside_tree():
		if _pop_tween != null and _pop_tween.is_valid():
			_pop_tween.kill()
		var base: Vector3 = shape.scale
		shape.scale = base
		var tw := shape.create_tween()
		tw.tween_property(shape, "scale", Vector3(base.x * 1.18, base.y * 0.55, base.z * 1.18), 0.16)
		tw.tween_property(shape, "scale", Vector3(base.x * 1.1, base.y * 0.7, base.z * 1.1), 0.25)
	SoundManager.play_sfx("collapse")
	burned_out.emit(self)


func _process(delta: float) -> void:
	if kind == "stone":
		return

	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 1.2)

	# Kit-model houses drive every visual cue through their own materials.
	if visual_style == "model":
		_sync_model_look()

	# Tree foliage wind sway and downwind lean (SPEC Section 7.3)
	if kind == "tree" and _tree_mesh_top != null and state != State.BURNT:
		var sway_phase := float(get_instance_id() % 100) * 0.12
		var sway := sin(float(Time.get_ticks_msec()) * 0.003 + sway_phase) * 0.08 * _ambient_wind_strength
		var tree_lean := _ambient_wind_dir * (_ambient_wind_strength * 0.14) + _gust_tilt * 0.4
		if _roof_box != null:
			_roof_box.position = Vector3(tree_lean.x * 0.25, 1.4, tree_lean.z * 0.25)
		if _tree_mesh_mid != null:
			_tree_mesh_mid.position = Vector3(tree_lean.x * 0.55 + sway * 0.5, 2.1, tree_lean.z * 0.55 + sway * 0.25)
		_tree_mesh_top.position = Vector3(tree_lean.x * 0.9 + sway, 2.7, tree_lean.z * 0.9 + sway * 0.5)

	# Water thrown at a fire evaporates off again: a brigade that gives up loses
	# the ground it had made.
	if water_soaked > 0.0 and state == State.BURNING:
		water_soaked = maxf(0.0, water_soaked - delta * WATER_SOAK_DECAY)

	# Evaporation: drying over time (SPEC 6.7 & 8.4)
	if wetness > 0.0:
		var dry_rate := 0.065 if state == State.BURNING else 0.035
		wetness = maxf(0.0, wetness - delta * dry_rate)

	if state == State.SMOLDERING:
		smolder_timer -= delta
		if _smolder_label != null and is_instance_valid(_smolder_label):
			_smolder_label.text = "LAST SPARK: %ds\nCLICK (1 EMBER)" % int(ceil(maxf(0.0, smolder_timer)))
			var pulse := 0.7 + 0.3 * sin(float(Time.get_ticks_msec()) * 0.01)
			_smolder_label.modulate = Color(1.0, pulse * 0.5, 0.1)
		if _mat_base != null:
			_mat_base.emission = Color(1.0, 0.25, 0.05)
			_mat_base.emission_energy_multiplier = 0.8 + 0.4 * sin(float(Time.get_ticks_msec()) * 0.008)
		if smolder_timer <= 0.0:
			if _smolder_label != null and is_instance_valid(_smolder_label):
				_smolder_label.queue_free()
				_smolder_label = null
			_burn_out()
		return

	if state != State.BURNING:
		if _smoke_warmth != null:
			if state == State.UNBURNED and kind != "stone":
				if wetness > 0.2 and heat > 0.04:
					# Steaming droplets cooling the structure (SPEC 6.4: "4. Wet sheen or droplets")
					_smoke_warmth.emitting = true
					var pm := _smoke_warmth.process_material as ParticleProcessMaterial
					if pm != null:
						pm.color = Color(0.85, 0.92, 1.0, 0.75)
					if _sparks_warmth != null:
						_sparks_warmth.emitting = false
				elif heat > 0.12:
					_smoke_warmth.emitting = true
					var pm := _smoke_warmth.process_material as ParticleProcessMaterial
					if pm != null:
						pm.color = Color(0.35, 0.33, 0.33, 0.5 + heat * 0.4)
					if _sparks_warmth != null:
						_sparks_warmth.emitting = (heat >= 0.55)
				else:
					_smoke_warmth.emitting = false
					if _sparks_warmth != null:
						_sparks_warmth.emitting = false
			else:
				_smoke_warmth.emitting = false
				if _sparks_warmth != null:
					_sparks_warmth.emitting = false

		if _mat_base != null:
			if state == State.BURNT:
				_mat_base.emission = Color(1.0, 0.3, 0.05)
				_mat_base.emission_energy_multiplier = _flash * 1.2
			elif _flash > 0.0:
				_mat_base.emission = Color(1.0, 0.5, 0.1)
				_mat_base.emission_energy_multiplier = _flash * 1.6
			elif state == State.UNBURNED and heat > 0.02 and kind != "stone":
				# Warming forecast: hotter = brighter orange rim. This IS the UI.
				_mat_base.emission = Color(1.0, 0.45, 0.1)
				_mat_base.emission_energy_multiplier = heat * 1.5
				if _mat_roof != null:
					_mat_roof.emission_enabled = true
					_mat_roof.emission = Color(1.0, 0.35, 0.08)
					_mat_roof.emission_energy_multiplier = heat * 1.2
			else:
				_mat_base.emission_energy_multiplier = 0.0
				if _mat_roof != null and not _scorched:
					_mat_roof.emission_energy_multiplier = 0.0

			# Wet sheen visual feedback: darker wood and glossy roughness when wet
			if state == State.UNBURNED:
				var wet_factor := 1.0 - wetness * 0.38
				var scorch_factor := (1.0 - (heat - 0.45) * 0.5) if (heat > 0.45 and not _scorched) else 1.0
				var target_col := (base_color * 0.55 if _scorched else base_color * scorch_factor) * wet_factor
				_mat_base.albedo_color = target_col
				_mat_base.roughness = clampf(1.0 - wetness * 0.7, 0.25, 1.0)
				if _mat_roof != null and not _scorched:
					_mat_roof.albedo_color = roof_color * scorch_factor * wet_factor
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
		for m in _tree_foliage_mats:
			m.albedo_color = m.albedo_color * 0.55

	var total_lean := _ambient_wind_dir * (_ambient_wind_strength * 0.22) + _gust_tilt * 0.45
	_gust_tilt = _gust_tilt.lerp(Vector3.ZERO, delta * 3.0)

	for i in _flames.size():
		var f := _flames[i]
		var s := 1.0 + sin(t + float(i) * 2.1) * 0.18 + randf_range(-0.06, 0.06)
		f.scale = Vector3(s, 1.0 + sin(t * 1.3 + float(i)) * 0.22, s)
		f.rotation.y += delta * (1.5 + float(i) * 0.7)
		f.position = Vector3(total_lean.x * float(i + 1), 0.3 + float(i) * 0.45, total_lean.z * float(i + 1))
	if _light:
		_light.light_energy = 1.4 + sin(t * 1.7) * 0.4 + randf_range(-0.15, 0.15)
		_light.position = Vector3(total_lean.x, 1.0, total_lean.z)
	if _smoke_particles != null:
		var pm := _smoke_particles.process_material as ParticleProcessMaterial
		if pm != null:
			pm.direction = (Vector3(0, 1.4, 0) + total_lean * 1.8).normalized()
	if _fire_particles != null:
		var pm_f := _fire_particles.process_material as ParticleProcessMaterial
		if pm_f != null:
			pm_f.direction = (Vector3(0, 1.2, 0) + total_lean * 1.2).normalized()
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
		burn_ending.emit(self)
		if state == State.BURNING:
			_burn_out()
