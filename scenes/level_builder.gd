class_name LevelBuilder
extends RefCounted
## LevelBuilder — Encapsulates level geometry and actor placement (SPEC Section 19).
## Builds ground terrain, roads, water channels, houses, trees, barrels, wells,
## and spawns initial villagers and shamans for Village, Town, and City.

const HOUSE_SCENE := preload("res://scenes/house.tscn")
const VILLAGER_SCENE := preload("res://scenes/villager.tscn")
const BARREL_SCENE := preload("res://scenes/barrel.tscn")
const SHAMAN_SCENE := preload("res://scenes/shaman.tscn")

const LEVELS := [
	{"name": "VILLAGE", "sub": "Clusters & Bucket Brigades", "grid_half": 4, "spacing": 4.2, "villagers": 7},
	{"name": "TOWN", "sub": "Canals, Explosive Barrels & Shaman", "grid_half": 5, "spacing": 4.0, "villagers": 9},
	{"name": "CITY", "sub": "Firebreaks & Metropolitan Districts", "grid_half": 6, "spacing": 3.8, "villagers": 0},
]

const CAM_SIZES := [19.0, 22.0, 25.0]

class LevelContext extends RefCounted:
	var name: String = ""
	var sub: String = ""
	var cam_bound: float = 16.0
	var camera_size: float = 19.0
	var houses: Array[VoxelHouse] = []
	var mandatory_houses: Array[VoxelHouse] = []
	var barrels: Array[VoxelBarrel] = []
	var starter_house: VoxelHouse = null
	var shaman: VoxelShaman = null


static func build_level(level_idx: int, village_root: Node3D, units_root: Node3D) -> LevelContext:
	var idx := clampi(level_idx, 0, LEVELS.size() - 1)
	var cfg: Dictionary = LEVELS[idx]
	var ctx := LevelContext.new()
	ctx.name = str(cfg["name"])
	ctx.sub = str(cfg["sub"])
	ctx.cam_bound = float(cfg["grid_half"]) * float(cfg["spacing"]) + 4.0
	ctx.camera_size = CAM_SIZES[clampi(idx, 0, CAM_SIZES.size() - 1)]

	_build_ground(idx, ctx.cam_bound, village_root)

	match idx:
		0:
			_build_village(ctx, village_root, units_root)
		1:
			_build_town(ctx, village_root, units_root)
		_:
			_build_city_stub(ctx, village_root, units_root)

	_spawn_villagers(int(cfg.get("villagers", 0)), ctx.cam_bound, units_root)
	return ctx


# ---------- Ground & Environment Builders ----------
static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return m


static func _add_voxel_box(parent: Node3D, size: Vector3, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = _mat(col)
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _ground_slab(parent: Node3D, size: Vector3, col: Color) -> void:
	_add_voxel_box(parent, size, Vector3(0, -0.5, 0), col)


static func _build_ground(level_idx: int, cam_bound: float, village_root: Node3D) -> void:
	var extent: float = cam_bound + 2.0
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	village_root.add_child(ground)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(extent * 2.0, 1, extent * 2.0)
	col.shape = shape
	col.position = Vector3(0, -0.5, 0)
	ground.add_child(col)

	var w := extent * 2.0 - 2.0
	match level_idx:
		0:
			# Village: Soft pasture lawn + dirt lane connecting clusters + central well square
			_ground_slab(ground, Vector3(w, 1, w), Color(0.42, 0.56, 0.26))
			var road_col := Color(0.54, 0.42, 0.26)
			_add_voxel_box(ground, Vector3(w * 0.75, 0.06, 3.0), Vector3(0, 0.03, 6.0), road_col)
			_add_voxel_box(ground, Vector3(w * 0.65, 0.06, 3.0), Vector3(0, 0.03, -7.5), road_col)
			_add_voxel_box(ground, Vector3(3.0, 0.06, 16.0), Vector3(0, 0.03, -0.5), road_col)
			_add_voxel_box(ground, Vector3(4.2, 0.08, 4.2), Vector3(0, 0.04, 0.5), Color(0.45, 0.43, 0.42))
		1:
			# Town: Base lawn + central canal with water and stone quays + bridge crossways
			_ground_slab(ground, Vector3(w, 1, w), Color(0.30, 0.48, 0.26))
			var canal_w := w + 4.0
			var canal_z_width := 4.6
			_add_voxel_box(ground, Vector3(canal_w, 0.2, canal_z_width), Vector3(0, -0.05, 0), Color(0.18, 0.45, 0.78))

			var canal_water_body := StaticBody3D.new()
			canal_water_body.name = "CanalWaterSource"
			canal_water_body.position = Vector3(0, 0, 0)
			canal_water_body.add_to_group("water_sources")
			var cw_col := CollisionShape3D.new()
			var cw_shape := BoxShape3D.new()
			cw_shape.size = Vector3(canal_w, 1.0, canal_z_width)
			cw_col.shape = cw_shape
			canal_water_body.add_child(cw_col)
			village_root.add_child(canal_water_body)

			var quay_col := Color(0.44, 0.42, 0.40)
			_add_voxel_box(ground, Vector3(canal_w, 0.28, 0.4), Vector3(0, 0.1, -canal_z_width * 0.5 - 0.2), quay_col)
			_add_voxel_box(ground, Vector3(canal_w, 0.28, 0.4), Vector3(0, 0.1, canal_z_width * 0.5 + 0.2), quay_col)

			var segs := [
				Vector2(-w * 0.5, -9.4),
				Vector2(-5.6, 5.6),
				Vector2(9.4, w * 0.5)
			]
			for seg in segs:
				var seg_len: float = seg.y - seg.x
				var seg_mid: float = (seg.x + seg.y) * 0.5
				for qz in [-canal_z_width * 0.5 - 0.2, canal_z_width * 0.5 + 0.2]:
					var q_col := CollisionShape3D.new()
					var q_shape := BoxShape3D.new()
					q_shape.size = Vector3(seg_len, 1.2, 0.5)
					q_col.shape = q_shape
					q_col.position = Vector3(seg_mid, 0.6, qz)
					ground.add_child(q_col)

			for wx in [-12.0, -4.0, 4.0, 12.0]:
				for wz in [-2.5, 2.5]:
					var wp := Node3D.new()
					wp.name = "QuayWaterPoint"
					wp.position = Vector3(wx, 0.1, wz)
					wp.add_to_group("water_sources")
					village_root.add_child(wp)

			var plank_col := Color(0.48, 0.32, 0.18)
			var rail_col := Color(0.36, 0.22, 0.12)
			for bx in [-7.5, 7.5]:
				_add_voxel_box(ground, Vector3(3.2, 0.22, canal_z_width + 0.8), Vector3(bx, 0.11, 0), plank_col)
				_add_voxel_box(ground, Vector3(0.2, 0.5, canal_z_width + 0.8), Vector3(bx - 1.5, 0.35, 0), rail_col)
				_add_voxel_box(ground, Vector3(0.2, 0.5, canal_z_width + 0.8), Vector3(bx + 1.5, 0.35, 0), rail_col)

			var road_col := Color(0.34, 0.33, 0.32)
			_add_voxel_box(ground, Vector3(3.2, 0.06, w), Vector3(-7.5, 0.03, 0), road_col)
			_add_voxel_box(ground, Vector3(3.2, 0.06, w), Vector3(7.5, 0.03, 0), road_col)
			_add_voxel_box(ground, Vector3(w * 0.9, 0.06, 2.8), Vector3(0, 0.03, 8.5), road_col)
			_add_voxel_box(ground, Vector3(w * 0.9, 0.06, 2.8), Vector3(0, 0.03, -8.5), road_col)
		_:
			_ground_slab(ground, Vector3(w, 1, w), Color(0.36, 0.44, 0.32))
			_add_voxel_box(ground, Vector3(w, 0.08, 4.5), Vector3(0, 0.04, 0), Color(0.38, 0.36, 0.35))
			_add_voxel_box(ground, Vector3(4.5, 0.08, w), Vector3(0, 0.04, 0), Color(0.38, 0.36, 0.35))


# ---------- Level Specific Generators ----------
static func _place_house(pos: Vector3, kind: String, fuel: float, size: Vector3, c1: Color, c2: Color, village_root: Node3D, ctx: LevelContext) -> VoxelHouse:
	var h: VoxelHouse = HOUSE_SCENE.instantiate()
	village_root.add_child(h)
	h.position = pos
	if kind == "house":
		h.rotation.y = [0.0, PI * 0.5, PI, -PI * 0.5][randi() % 4]
	h.setup(c1, c2, fuel, size, kind)
	ctx.houses.append(h)
	if kind == "house":
		ctx.mandatory_houses.append(h)
	return h


static func _place_barrel(pos: Vector3, village_root: Node3D, ctx: LevelContext) -> VoxelBarrel:
	var b: VoxelBarrel = BARREL_SCENE.instantiate()
	village_root.add_child(b)
	b.position = pos
	ctx.barrels.append(b)
	return b


static func _build_water_well(pos: Vector3, village_root: Node3D) -> StaticBody3D:
	var well := StaticBody3D.new()
	well.name = "WaterWell"
	well.position = pos
	well.add_to_group("water_sources")
	village_root.add_child(well)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.6, 1.2, 1.6)
	col.shape = shape
	col.position = Vector3(0, 0.6, 0)
	well.add_child(col)

	var stone_col := Color(0.48, 0.46, 0.45)
	_add_voxel_box(well, Vector3(1.6, 0.6, 0.35), Vector3(0, 0.3, 0.65), stone_col)
	_add_voxel_box(well, Vector3(1.6, 0.6, 0.35), Vector3(0, 0.3, -0.65), stone_col)
	_add_voxel_box(well, Vector3(0.35, 0.6, 1.0), Vector3(-0.65, 0.3, 0), stone_col)
	_add_voxel_box(well, Vector3(0.35, 0.6, 1.0), Vector3(0.65, 0.3, 0), stone_col)

	var water_col := Color(0.2, 0.55, 0.92)
	_add_voxel_box(well, Vector3(1.0, 0.3, 1.0), Vector3(0, 0.25, 0), water_col)

	var wood_col := Color(0.38, 0.25, 0.14)
	_add_voxel_box(well, Vector3(0.18, 1.5, 0.18), Vector3(-0.6, 0.85, 0), wood_col)
	_add_voxel_box(well, Vector3(0.18, 1.5, 0.18), Vector3(0.6, 0.85, 0), wood_col)

	var roof_col := Color(0.55, 0.2, 0.14)
	_add_voxel_box(well, Vector3(1.8, 0.25, 1.8), Vector3(0, 1.6, 0), roof_col)
	_add_voxel_box(well, Vector3(1.1, 0.25, 1.1), Vector3(0, 1.8, 0), roof_col)
	return well


static func _build_village(ctx: LevelContext, village_root: Node3D, _units_root: Node3D) -> void:
	var wall_cols := [Color(0.92, 0.82, 0.66), Color(0.90, 0.74, 0.56), Color(0.95, 0.88, 0.72)]
	var roof_cols := [Color(0.78, 0.28, 0.16), Color(0.60, 0.22, 0.15), Color(0.35, 0.48, 0.70)]
	var idx := 0

	# Cluster 1: Southwest Starter Cluster (6 houses)
	var sw_houses := [
		Vector3(-6.4, 0, 8.0), # House 0: Starter House
		Vector3(-2.8, 0, 4.5),
		Vector3(-6.2, 0, 4.2),
		Vector3(-2.8, 0, 8.2),
		Vector3(-9.6, 0, 5.8),
		Vector3(-9.6, 0, 9.6),
	]
	for pos in sw_houses:
		_place_house(pos, "house", randf_range(48.0, 58.0), Vector3(randf_range(1.9, 2.2), randf_range(1.4, 1.8), randf_range(1.9, 2.2)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()], village_root, ctx)
		idx += 1

	# South Lane Connector House
	_place_house(Vector3(0.6, 0, 6.2), "house", randf_range(48.0, 58.0), Vector3(randf_range(1.9, 2.2), randf_range(1.4, 1.8), randf_range(1.9, 2.2)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()], village_root, ctx)
	idx += 1

	# Cluster 2: Southeast Farmstead Cluster (5 houses)
	var se_houses := [
		Vector3(4.2, 0, 4.5),
		Vector3(7.8, 0, 4.2),
		Vector3(11.2, 0, 5.0),
		Vector3(4.5, 0, 8.2),
		Vector3(8.5, 0, 8.4),
	]
	for pos in se_houses:
		_place_house(pos, "house", randf_range(48.0, 58.0), Vector3(randf_range(1.9, 2.2), randf_range(1.4, 1.8), randf_range(1.9, 2.2)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()], village_root, ctx)
		idx += 1

	# Cluster 3: North Hillside Cluster (6 houses)
	var n_houses := [
		Vector3(-4.5, 0, -6.0),
		Vector3(-0.8, 0, -6.0),
		Vector3(3.8, 0, -6.0),
		Vector3(-4.5, 0, -9.8),
		Vector3(-0.8, 0, -9.8),
		Vector3(3.8, 0, -9.8),
	]
	for pos in n_houses:
		_place_house(pos, "house", randf_range(48.0, 58.0), Vector3(randf_range(1.9, 2.2), randf_range(1.4, 1.8), randf_range(1.9, 2.2)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()], village_root, ctx)
		idx += 1

	# Exposed Tree Bridge (3 trees connecting Cluster 1 and Cluster 3)
	_place_house(Vector3(-3.2, 0, 1.8), "tree", 22.0, Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25), village_root, ctx)
	_place_house(Vector3(-3.5, 0, -0.8), "tree", 22.0, Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25), village_root, ctx)
	_place_house(Vector3(-3.8, 0, -3.4), "tree", 22.0, Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25), village_root, ctx)

	# Central water well for bucket carriers
	_build_water_well(Vector3(0.0, 0, 0.5), village_root)

	# Framing perimeter trees
	for side in [-1.0, 1.0]:
		for k in 4:
			var ox: float = float(side) * (14.0 + float(k) * 1.5)
			var oz: float = randf_range(-12.0, 12.0)
			_place_house(Vector3(ox, 0, oz), "tree", 24.0, Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25), village_root, ctx)

	for i in 8:
		var ang := TAU * float(i) / 8.0
		var r := ctx.cam_bound * 0.88
		_place_house(Vector3(cos(ang) * r, 0, sin(ang) * r), "tree", 24.0, Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25), village_root, ctx)

	# Set starter house
	ctx.starter_house = ctx.mandatory_houses[0]
	ctx.starter_house.set_starter(true)


static func _build_town(ctx: LevelContext, village_root: Node3D, units_root: Node3D) -> void:
	var wall_cols := [Color(0.90, 0.80, 0.65), Color(0.88, 0.72, 0.54), Color(0.92, 0.85, 0.70)]
	var roof_cols := [Color(0.75, 0.26, 0.16), Color(0.58, 0.20, 0.15), Color(0.30, 0.42, 0.65)]
	var idx := 0

	# 1. South Residential District (Z > 0)
	var sw_houses := [
		Vector3(-14.0, 0, 4.8), Vector3(-10.2, 0, 4.8), Vector3(-4.8, 0, 4.8),
		Vector3(-14.0, 0, 12.2), Vector3(-10.2, 0, 12.2), Vector3(-4.8, 0, 12.2),
	]
	for pos in sw_houses:
		_place_house(pos, "house", randf_range(48.0, 58.0), Vector3(randf_range(1.9, 2.2), randf_range(1.4, 1.8), randf_range(1.9, 2.2)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()], village_root, ctx)
		idx += 1

	var se_houses := [
		Vector3(4.8, 0, 4.8), Vector3(10.2, 0, 4.8), Vector3(14.0, 0, 4.8),
		Vector3(4.8, 0, 12.2), Vector3(10.2, 0, 12.2), Vector3(14.0, 0, 12.2),
	]
	for pos in se_houses:
		_place_house(pos, "house", randf_range(48.0, 58.0), Vector3(randf_range(1.9, 2.2), randf_range(1.4, 1.8), randf_range(1.9, 2.2)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()], village_root, ctx)
		idx += 1

	# Barrel 1: Strategic bridge across central residential street
	_place_barrel(Vector3(0.0, 0, 4.8), village_root, ctx)

	# 2. North Commercial & Guild District (Z < 0)
	var nw_houses := [
		Vector3(-14.0, 0, -4.8), Vector3(-10.2, 0, -4.8), Vector3(-4.8, 0, -4.8),
		Vector3(-14.0, 0, -12.2), Vector3(-10.2, 0, -12.2), Vector3(-4.8, 0, -12.2),
	]
	for pos in nw_houses:
		_place_house(pos, "house", randf_range(48.0, 58.0), Vector3(randf_range(1.9, 2.2), randf_range(1.4, 1.8), randf_range(1.9, 2.2)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()], village_root, ctx)
		idx += 1

	# Barrel 2: Near West Bridge approach
	_place_barrel(Vector3(-7.5, 0, -3.2), village_root, ctx)

	var ne_houses := [
		Vector3(4.8, 0, -4.8), Vector3(8.8, 0, -4.8),
		Vector3(4.8, 0, -12.2), Vector3(8.8, 0, -12.2),
		Vector3(2.6, 0, -8.5),
	]
	for pos in ne_houses:
		_place_house(pos, "house", randf_range(48.0, 58.0), Vector3(randf_range(1.9, 2.2), randf_range(1.4, 1.8), randf_range(1.9, 2.2)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()], village_root, ctx)
		idx += 1

	# Barrel 3: In the alley leading toward the Shaman
	_place_barrel(Vector3(10.8, 0, -8.5), village_root, ctx)

	# 3. Shaman Ritual Court (Northeast corner)
	ctx.shaman = _build_shaman_court(Vector3(14.5, 0, -8.5), village_root, units_root)

	# Flammable tree bridge connecting Northeast houses to Ritual Court
	_place_house(Vector3(11.2, 0, -6.5), "tree", 24.0, Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25), village_root, ctx)
	_place_house(Vector3(12.8, 0, -7.2), "tree", 24.0, Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25), village_root, ctx)

	# Perimeter trees
	for x_pos in [-16.0, 16.0]:
		for z_pos in [-14.0, -9.0, -4.0, 4.0, 9.0, 14.0]:
			_place_house(Vector3(x_pos + randf_range(-0.4, 0.4), 0, z_pos + randf_range(-0.4, 0.4)), "tree", 24.0, Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25), village_root, ctx)

	# Pick Starter House: south district close to center
	if not ctx.mandatory_houses.is_empty():
		var best_starter := ctx.mandatory_houses[0]
		var best_dist := 1e9
		for h in ctx.mandatory_houses:
			if h.position.z > 2.0:
				var d := h.position.length()
				if d < best_dist:
					best_dist = d
					best_starter = h
		ctx.starter_house = best_starter
		ctx.starter_house.set_starter(true)


static func _build_city_stub(ctx: LevelContext, village_root: Node3D, _units_root: Node3D) -> void:
	var wall_cols := [Color(0.85, 0.85, 0.85), Color(0.8, 0.78, 0.75)]
	var roof_cols := [Color(0.3, 0.35, 0.45), Color(0.25, 0.25, 0.3)]
	var spacing := 3.8
	var half := 6
	var idx := 0

	for gx in range(-half, half + 1):
		for gz in range(-half, half + 1):
			if absi(gx) < 2 and absi(gz) < 2:
				continue
			if randf() < 0.25:
				continue
			var px := float(gx) * spacing
			var pz := float(gz) * spacing
			_place_house(Vector3(px, 0, pz), "house", randf_range(50.0, 65.0), Vector3(2.0, 1.8, 2.0), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()], village_root, ctx)
			idx += 1

	if not ctx.mandatory_houses.is_empty():
		ctx.starter_house = ctx.mandatory_houses[0]
		ctx.starter_house.set_starter(true)


static func _build_shaman_court(pos: Vector3, village_root: Node3D, units_root: Node3D) -> VoxelShaman:
	var court := Node3D.new()
	court.name = "ShamanRitualCourt"
	court.position = pos
	village_root.add_child(court)

	var stone_col := Color(0.48, 0.46, 0.44)
	var rune_col := Color(0.2, 0.8, 0.95)

	_add_voxel_box(court, Vector3(5.6, 0.3, 5.6), Vector3(0, 0.15, 0), stone_col)
	for px in [-2.4, 2.4]:
		for pz in [-2.4, 2.4]:
			_add_voxel_box(court, Vector3(0.5, 2.4, 0.5), Vector3(px, 1.2, pz), stone_col)
			_add_voxel_box(court, Vector3(0.3, 0.3, 0.3), Vector3(px, 2.5, pz), rune_col)

	_add_voxel_box(court, Vector3(1.2, 0.6, 0.8), Vector3(0, 0.45, 1.2), stone_col)
	_add_voxel_box(court, Vector3(0.8, 0.15, 0.5), Vector3(0, 0.75, 1.2), rune_col)

	var shaman: VoxelShaman = SHAMAN_SCENE.instantiate()
	units_root.add_child(shaman)
	shaman.position = pos + Vector3(0, 0.3, 0)
	return shaman


static func _spawn_villagers(n: int, cam_bound: float, units_root: Node3D) -> void:
	for i in n:
		var v: VoxelVillager = VILLAGER_SCENE.instantiate()
		units_root.add_child(v)
		v.position = Vector3(randf_range(-cam_bound * 0.55, cam_bound * 0.55), 0, randf_range(-cam_bound * 0.55, cam_bound * 0.55))
