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
	{"name": "CITY", "sub": "Firebreaks & Metropolitan Districts", "grid_half": 6, "spacing": 3.8, "villagers": 14},
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
	## Handcrafted levels report reserved building sites here (SPEC 19 data-driven levels).
	var plots: Array[Dictionary] = []
	## True when the level has no burnable structures yet, so win/lose must not be evaluated.
	var staging: bool = false


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
			_build_city(ctx, village_root, units_root)

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
			# East lane connecting SE Farmstead to North Hillside
			_add_voxel_box(ground, Vector3(3.0, 0.06, 12.0), Vector3(6.8, 0.03, -1.0), road_col)
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
			_add_voxel_box(ground, Vector3(3.2, 0.06, w * 0.75), Vector3(0, 0.03, 0), road_col) # Central avenue
			_add_voxel_box(ground, Vector3(w * 0.9, 0.06, 2.8), Vector3(0, 0.03, 6.9), road_col) # South cross street
			_add_voxel_box(ground, Vector3(w * 0.9, 0.06, 2.8), Vector3(0, 0.03, -6.9), road_col) # North cross street
		_:
			# City: Paved urban cobblestone with central boulevard, plazas, and stone sidewalks
			_ground_slab(ground, Vector3(w, 1, w), Color(0.38, 0.38, 0.40))
			var road_asphalt := Color(0.25, 0.25, 0.27)
			var curb_col := Color(0.52, 0.50, 0.48)
			var plaza_col := Color(0.45, 0.44, 0.43)

			# Central Grand Boulevard (South to North through South Gate)
			_add_voxel_box(ground, Vector3(5.2, 0.06, w), Vector3(0, 0.03, 0), road_asphalt)
			_add_voxel_box(ground, Vector3(0.4, 0.12, w), Vector3(-2.8, 0.06, 0), curb_col)
			_add_voxel_box(ground, Vector3(0.4, 0.12, w), Vector3(2.8, 0.06, 0), curb_col)

			# East Merchant Lane (through East Gate)
			_add_voxel_box(ground, Vector3(3.6, 0.06, w * 0.75), Vector3(13.0, 0.03, 1.0), road_asphalt)

			# South Cross Boulevard (connecting SW District and SE District)
			_add_voxel_box(ground, Vector3(w * 0.85, 0.06, 3.6), Vector3(0, 0.03, 7.5), road_asphalt)

			# North Manor Promenade (connecting North Manors)
			_add_voxel_box(ground, Vector3(w * 0.85, 0.06, 3.6), Vector3(0, 0.03, -7.5), road_asphalt)

			# Central Citadel Plaza (in front of Stone Fortifications)
			_add_voxel_box(ground, Vector3(22.0, 0.08, 8.0), Vector3(0, 0.04, -1.5), plaza_col)
			_add_voxel_box(ground, Vector3(12.0, 0.08, 6.0), Vector3(13.0, 0.04, -1.5), plaza_col)


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

	# East Lane Connector (Guaranteed safe house route linking SE Farmsteads to North Hillside, SPEC 6.3 & 6.10)
	var east_houses := [
		Vector3(7.2, 0, 0.8),
		Vector3(6.5, 0, -2.8),
	]
	for pos in east_houses:
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

	# 1. South-West Residential District (8 houses + 1 bridgehead)
	var sw_houses := [
		Vector3(-14.0, 0, 5.0), Vector3(-10.0, 0, 5.0), Vector3(-6.0, 0, 5.0), Vector3(-2.4, 0, 5.0),
		Vector3(-14.0, 0, 8.8), Vector3(-10.0, 0, 8.8), Vector3(-6.0, 0, 8.8), Vector3(-2.4, 0, 8.8),
		Vector3(-7.5, 0, 2.5), # West Bridgehead South
	]
	for pos in sw_houses:
		_place_house(pos, "house", randf_range(48.0, 58.0), Vector3(randf_range(1.9, 2.2), randf_range(1.4, 1.8), randf_range(1.9, 2.2)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()], village_root, ctx)
		idx += 1

	# 2. South-East Residential District (8 houses + 1 bridgehead)
	var se_houses := [
		Vector3(2.4, 0, 5.0), Vector3(6.0, 0, 5.0), Vector3(10.0, 0, 5.0), Vector3(14.0, 0, 5.0),
		Vector3(2.4, 0, 8.8), Vector3(6.0, 0, 8.8), Vector3(10.0, 0, 8.8), Vector3(14.0, 0, 8.8),
		Vector3(7.5, 0, 2.5), # East Bridgehead South
	]
	for pos in se_houses:
		_place_house(pos, "house", randf_range(48.0, 58.0), Vector3(randf_range(1.9, 2.2), randf_range(1.4, 1.8), randf_range(1.9, 2.2)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()], village_root, ctx)
		idx += 1

	# Barrel 1: Strategic bridge across central residential street (SPEC 6.10 & 8.5)
	_place_barrel(Vector3(0.0, 0, 5.0), village_root, ctx)

	# 3. North-West Commercial District (8 houses + 1 bridgehead)
	var nw_houses := [
		Vector3(-14.0, 0, -5.0), Vector3(-10.0, 0, -5.0), Vector3(-6.0, 0, -5.0), Vector3(-2.4, 0, -5.0),
		Vector3(-14.0, 0, -8.8), Vector3(-10.0, 0, -8.8), Vector3(-6.0, 0, -8.8), Vector3(-2.4, 0, -8.8),
		Vector3(-7.5, 0, -2.5), # West Bridgehead North (5.0m across canal bridge from South Bridgehead)
	]
	for pos in nw_houses:
		_place_house(pos, "house", randf_range(48.0, 58.0), Vector3(randf_range(1.9, 2.2), randf_range(1.4, 1.8), randf_range(1.9, 2.2)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()], village_root, ctx)
		idx += 1

	# Barrel 2: Near West Bridge approach
	_place_barrel(Vector3(-7.5, 0, -3.8), village_root, ctx)

	# 4. North-East Commercial & Shaman Approach District (7 houses + 1 bridgehead)
	var ne_houses := [
		Vector3(2.4, 0, -5.0), Vector3(6.0, 0, -5.0), Vector3(10.0, 0, -5.0),
		Vector3(2.4, 0, -8.8), Vector3(6.0, 0, -8.8), Vector3(10.0, 0, -8.8),
		Vector3(13.2, 0, -6.8), # Shaman alley house (guarantees mandatory route without trees)
		Vector3(7.5, 0, -2.5),  # East Bridgehead North (5.0m across canal bridge from South Bridgehead)
	]
	for pos in ne_houses:
		_place_house(pos, "house", randf_range(48.0, 58.0), Vector3(randf_range(1.9, 2.2), randf_range(1.4, 1.8), randf_range(1.9, 2.2)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()], village_root, ctx)
		idx += 1

	# Barrel 3: In the alley leading toward the Shaman
	_place_barrel(Vector3(11.5, 0, -8.5), village_root, ctx)

	# 5. Shaman Ritual Court (Northeast corner)
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
			if h.position.z > 4.0:
				var d := h.position.distance_to(Vector3(-2.4, 0, 5.0))
				if d < best_dist:
					best_dist = d
					best_starter = h
		ctx.starter_house = best_starter
		ctx.starter_house.set_starter(true)


static func _build_city(ctx: LevelContext, village_root: Node3D, _units_root: Node3D) -> void:
	var wall_cols := [Color(0.86, 0.83, 0.78), Color(0.74, 0.65, 0.54), Color(0.88, 0.78, 0.65), Color(0.65, 0.58, 0.52)]
	var roof_cols := [Color(0.72, 0.24, 0.16), Color(0.28, 0.35, 0.48), Color(0.52, 0.20, 0.18), Color(0.32, 0.28, 0.32)]
	var idx := 0

	# 1. Great Stone Firebreak Wall & Fortifications
	_build_city_firebreak(ctx, village_root)

	# 2. Public Water Fountains / Cisterns for Bucket Carriers
	_build_city_fountain(Vector3(-10.5, 0, 9.5), village_root)
	_build_city_fountain(Vector3(10.5, 0, 9.5), village_root)
	_build_city_fountain(Vector3(2.5, 0, -12.5), village_root)

	# 3. District 1: Outer South-West District (11 combustible houses)
	var sw_houses := [
		Vector3(-14.5, 0, 13.5), # Starter house
		Vector3(-10.5, 0, 13.5),
		Vector3(-6.5, 0, 13.5),
		Vector3(-14.5, 0, 9.5),
		Vector3(-10.5, 0, 9.5),
		Vector3(-6.5, 0, 9.5),
		Vector3(-14.5, 0, 5.5),
		Vector3(-10.5, 0, 5.5),
		Vector3(-6.5, 0, 5.5),
		Vector3(-2.2, 0, 5.5),   # Boulevard approach
		Vector3(-2.2, 0, 1.4),   # South Grand Gate South approach (5.4m through gate)
	]
	for pos in sw_houses:
		_place_house(pos, "house", randf_range(52.0, 62.0), Vector3(randf_range(2.0, 2.3), randf_range(1.6, 2.0), randf_range(2.0, 2.3)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()], village_root, ctx)
		idx += 1

	# 4. District 2: Outer South-East District (8 combustible workshops & guildhalls)
	var se_houses := [
		Vector3(2.2, 0, 5.5),    # East side of South Gate boulevard (4.4m from SW approach)
		Vector3(6.0, 0, 5.5),
		Vector3(10.0, 0, 5.5),
		Vector3(14.0, 0, 5.5),
		Vector3(6.0, 0, 9.5),
		Vector3(10.0, 0, 9.5),
		Vector3(14.0, 0, 9.5),
		Vector3(13.0, 0, 1.4),   # East Merchant Gate South approach (5.4m through gate)
	]
	for pos in se_houses:
		_place_house(pos, "house", randf_range(52.0, 62.0), Vector3(randf_range(2.0, 2.3), randf_range(1.6, 2.0), randf_range(2.0, 2.3)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()], village_root, ctx)
		idx += 1

	# 5. District 3: Inner Northern Metropolitan District (15 combustible manors & merchant halls)
	var n_houses := [
		# South Gate North Approach (5.4m across South Gate arch from -2.2, 0, 1.4)
		Vector3(-2.2, 0, -4.0),
		# East Gate North Approach (5.4m across East Gate arch from 13.0, 0, 1.4)
		Vector3(13.0, 0, -4.0),

		# North-West Manor Block (accessible directly via South Gate)
		Vector3(-6.0, 0, -4.0),
		Vector3(-10.0, 0, -4.0),
		Vector3(-14.0, 0, -4.0),
		Vector3(-2.2, 0, -8.0),
		Vector3(-6.0, 0, -8.0),
		Vector3(-10.0, 0, -8.0),
		Vector3(-14.0, 0, -8.0),

		# North-East Guild Block (accessible directly via East Gate)
		Vector3(9.5, 0, -4.0),
		Vector3(6.0, 0, -4.0),
		Vector3(2.2, 0, -4.0),
		Vector3(13.0, 0, -8.0),
		Vector3(9.5, 0, -8.0),
		Vector3(6.0, 0, -8.0),
	]
	for pos in n_houses:
		_place_house(pos, "house", randf_range(54.0, 66.0), Vector3(randf_range(2.1, 2.4), randf_range(1.8, 2.2), randf_range(2.1, 2.4)), wall_cols[idx % wall_cols.size()], roof_cols[idx % roof_cols.size()], village_root, ctx)
		idx += 1

	# 6. Strategic Explosive Barrels (SPEC 8.5 & 11.3)
	# Barrel 1: Junction between SW residential and SE artisan district across the avenue
	_place_barrel(Vector3(0.0, 0, 5.5), village_root, ctx)
	# Barrel 2: Near approach to East Merchant Gate
	_place_barrel(Vector3(11.5, 0, 3.5), village_root, ctx)
	# Barrel 3: In North Manor alley
	_place_barrel(Vector3(-6.0, 0, -10.5), village_root, ctx)

	# 7. Courtyard Trees: Optional bridge between NW manors and NE guild block
	_place_house(Vector3(2.0, 0, -7.5), "tree", 24.0, Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25), village_root, ctx)
	_place_house(Vector3(4.5, 0, -7.5), "tree", 24.0, Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25), village_root, ctx)
	_place_house(Vector3(7.0, 0, -7.5), "tree", 24.0, Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25), village_root, ctx)

	# 8. Perimeter framing trees
	for x_pos in [-22.0, 22.0]:
		for z_pos in [-18.0, -12.0, -6.0, 6.0, 12.0, 18.0]:
			_place_house(Vector3(x_pos + randf_range(-0.5, 0.5), 0, z_pos + randf_range(-0.5, 0.5)), "tree", 24.0, Vector3(0.9, 1.0, 0.9), Color(0.4, 0.25, 0.12), Color(0.2, 0.55, 0.25), village_root, ctx)

	# Set Starter House to SW District outer corner
	if not ctx.mandatory_houses.is_empty():
		ctx.starter_house = ctx.mandatory_houses[0]
		ctx.starter_house.set_starter(true)


static func _build_city_firebreak(ctx: LevelContext, village_root: Node3D) -> void:
	var firebreak_root := Node3D.new()
	firebreak_root.name = "StoneFirebreak"
	village_root.add_child(firebreak_root)

	var stone_wall_col := Color(0.46, 0.44, 0.42)
	var stone_cap_col := Color(0.36, 0.35, 0.34)
	var arch_beam_col := Color(0.50, 0.48, 0.46)
	var banner_gold := Color(0.85, 0.72, 0.2)

	# Static collision body for solid stone walls
	var wall_body := StaticBody3D.new()
	wall_body.name = "StoneWallCollision"
	wall_body.collision_layer = 1
	wall_body.collision_mask = 0
	firebreak_root.add_child(wall_body)

	# Helper to add wall section with collision and crenellations
	var add_wall_segment := func(x1: float, x2: float, z_pos: float) -> void:
		var seg_len := absf(x2 - x1)
		var mid_x := (x1 + x2) * 0.5
		# Base wall
		_add_voxel_box(firebreak_root, Vector3(seg_len, 3.2, 1.6), Vector3(mid_x, 1.6, z_pos), stone_wall_col)
		# Parapet cap
		_add_voxel_box(firebreak_root, Vector3(seg_len + 0.3, 0.3, 1.9), Vector3(mid_x, 3.35, z_pos), stone_cap_col)
		# Crenellations along top
		var step := 1.6
		var n_cren := int(seg_len / step)
		for i in n_cren:
			var cx := x1 + 0.8 + float(i) * step
			_add_voxel_box(firebreak_root, Vector3(0.7, 0.45, 0.4), Vector3(cx, 3.7, z_pos + 0.7), stone_wall_col)
			_add_voxel_box(firebreak_root, Vector3(0.7, 0.45, 0.4), Vector3(cx, 3.7, z_pos - 0.7), stone_wall_col)
		# Physics collision shape
		var c_shape := CollisionShape3D.new()
		var b_shape := BoxShape3D.new()
		b_shape.size = Vector3(seg_len, 3.6, 1.6)
		c_shape.shape = b_shape
		c_shape.position = Vector3(mid_x, 1.8, z_pos)
		wall_body.add_child(c_shape)

	# --- Wall Section 1: West Wall (from outer boundary to South Gate) ---
	add_wall_segment.call(-22.0, -3.4, -1.5)

	# --- Wall Section 2: Middle Wall (between South Gate and East Gate) ---
	add_wall_segment.call(3.4, 10.6, -1.5)

	# --- Wall Section 3: Far East Wall (from East Gate to outer boundary) ---
	add_wall_segment.call(15.4, 22.0, -1.5)

	# --- GATE 1: South Grand Gate (X = 0, Z = -1.5, open lane width 6.8m) ---
	# Left Gate Tower
	_add_voxel_box(firebreak_root, Vector3(2.4, 5.4, 2.6), Vector3(-3.8, 2.7, -1.5), stone_wall_col)
	_add_voxel_box(firebreak_root, Vector3(2.6, 0.4, 2.8), Vector3(-3.8, 5.6, -1.5), stone_cap_col)
	_add_voxel_box(firebreak_root, Vector3(0.4, 1.2, 0.4), Vector3(-3.8, 6.4, -1.5), stone_wall_col)
	_add_voxel_box(firebreak_root, Vector3(0.8, 0.5, 0.1), Vector3(-3.8, 6.7, -1.5), banner_gold)
	# Right Gate Tower
	_add_voxel_box(firebreak_root, Vector3(2.4, 5.4, 2.6), Vector3(3.8, 2.7, -1.5), stone_wall_col)
	_add_voxel_box(firebreak_root, Vector3(2.6, 0.4, 2.8), Vector3(3.8, 5.6, -1.5), stone_cap_col)
	_add_voxel_box(firebreak_root, Vector3(0.4, 1.2, 0.4), Vector3(3.8, 6.4, -1.5), stone_wall_col)
	_add_voxel_box(firebreak_root, Vector3(0.8, 0.5, 0.1), Vector3(3.8, 6.7, -1.5), banner_gold)
	# Overhead Archway Beam
	_add_voxel_box(firebreak_root, Vector3(5.6, 1.2, 2.0), Vector3(0, 4.6, -1.5), arch_beam_col)
	_add_voxel_box(firebreak_root, Vector3(1.8, 0.8, 0.25), Vector3(0, 4.6, -0.4), banner_gold) # Gate crest

	# --- GATE 2: East Merchant Gate (X = 13.0, Z = -1.5, open lane width 4.8m) ---
	# Left Merchant Archpost
	_add_voxel_box(firebreak_root, Vector3(1.8, 4.4, 2.0), Vector3(10.6, 2.2, -1.5), stone_wall_col)
	_add_voxel_box(firebreak_root, Vector3(2.0, 0.35, 2.2), Vector3(10.6, 4.55, -1.5), stone_cap_col)
	# Right Merchant Archpost
	_add_voxel_box(firebreak_root, Vector3(1.8, 4.4, 2.0), Vector3(15.4, 2.2, -1.5), stone_wall_col)
	_add_voxel_box(firebreak_root, Vector3(2.0, 0.35, 2.2), Vector3(15.4, 4.55, -1.5), stone_cap_col)
	# Overhead Merchant Arch Beam
	_add_voxel_box(firebreak_root, Vector3(3.8, 0.9, 1.6), Vector3(13.0, 3.8, -1.5), arch_beam_col)

	# --- Stone Bastions & Wall Towers ---
	_add_voxel_box(firebreak_root, Vector3(2.4, 4.8, 2.4), Vector3(-20.5, 2.4, -1.5), stone_wall_col)
	_add_voxel_box(firebreak_root, Vector3(2.6, 0.4, 2.6), Vector3(-20.5, 5.0, -1.5), stone_cap_col)
	_add_voxel_box(firebreak_root, Vector3(2.4, 4.8, 2.4), Vector3(20.5, 2.4, -1.5), stone_wall_col)
	_add_voxel_box(firebreak_root, Vector3(2.6, 0.4, 2.6), Vector3(20.5, 5.0, -1.5), stone_cap_col)

	# --- Non-combustible Stone Buildings (kind == "stone", excluded from mandatory completion) ---
	# 1. Grand Stone Cathedral / Basilica
	_place_house(Vector3(-7.5, 0, -1.5), "stone", 999.0, Vector3(4.8, 3.4, 4.2), Color(0.48, 0.46, 0.45), Color(0.24, 0.25, 0.28), village_root, ctx)
	# 2. Royal Stone Treasury & Archives
	_place_house(Vector3(-16.0, 0, -1.5), "stone", 999.0, Vector3(3.8, 2.6, 3.6), Color(0.48, 0.46, 0.45), Color(0.24, 0.25, 0.28), village_root, ctx)
	# 3. City Guard Garrison & Armory
	_place_house(Vector3(7.0, 0, -1.5), "stone", 999.0, Vector3(3.8, 2.6, 3.4), Color(0.48, 0.46, 0.45), Color(0.24, 0.25, 0.28), village_root, ctx)


static func _build_city_fountain(pos: Vector3, village_root: Node3D) -> StaticBody3D:
	var f := StaticBody3D.new()
	f.name = "CityFountain"
	f.position = pos
	f.add_to_group("water_sources")
	village_root.add_child(f)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.2
	shape.height = 1.0
	col.shape = shape
	col.position = Vector3(0, 0.5, 0)
	f.add_child(col)

	var stone_col := Color(0.48, 0.46, 0.45)
	var water_col := Color(0.2, 0.55, 0.85)

	# Octagonal/layered stone basin
	_add_voxel_box(f, Vector3(2.4, 0.45, 2.4), Vector3(0, 0.225, 0), stone_col)
	_add_voxel_box(f, Vector3(2.6, 0.12, 2.6), Vector3(0, 0.42, 0), stone_col)
	# Water surface inside basin
	_add_voxel_box(f, Vector3(2.0, 0.08, 2.0), Vector3(0, 0.38, 0), water_col)
	# Central fountain spout pillar
	_add_voxel_box(f, Vector3(0.6, 1.2, 0.6), Vector3(0, 0.8, 0), stone_col)
	_add_voxel_box(f, Vector3(0.8, 0.15, 0.8), Vector3(0, 1.3, 0), stone_col)
	_add_voxel_box(f, Vector3(0.2, 0.2, 0.2), Vector3(0, 1.45, 0), water_col)
	return f


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
