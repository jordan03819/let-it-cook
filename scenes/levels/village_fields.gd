class_name VillageFieldsLevel
extends Node3D
## Handcrafted "Village Fields" village for Let It Cook (SPEC Section 6.10, 11.1).
##
## This scene is authored by hand / by tools/build_village_fields.py and holds the
## level foundation only: terrain, pond, path network, fences, crops,
## vegetation and atmosphere. Burnable buildings are intentionally NOT part of
## this scene yet — every building site is reserved by an invisible marker:
##
##   HousePlots/<name>     Node3D with metadata:
##       cluster (String)  which settlement cluster it belongs to
##       role    (String)  "starter" | "mandatory" | "optional"
##       size    (Vector3) intended building footprint
##       rotation.y        which way the building should face (towards its lane)
##
## Dropping a house scene under these markers (or pointing `houses` at a node that
## contains them) is all that is needed for the level to become a burnable level:
## `build_context()` collects whatever VoxelHouse instances it finds.
##
## While the level has no houses it reports `staging = true`, which makes the game
## skip win/lose evaluation so the foundation can be walked and reviewed.

const LEVEL_NAME := "VILLAGE FIELDS"
const LEVEL_SUB := "Foundations: pond, lanes, farm & plots"
const CAM_BOUND := 25.0
const CAMERA_SIZE := 24.0
## Bucket-carrying villagers. They are the level's main opposition (SPEC 11.1):
## they path to the nearest `water_sources` marker, which here is the pond rim or
## the village well. Zero keeps the level uncontested.
const VILLAGER_COUNT := 9
const START_INDEX := 3

## Kenney's GLB exports ship `metallicFactor = 1`, which reads as unlit metal in
## this game's environment (no reflection probe / sky in the base scene). Force
## the matte look the kit is drawn for.
const NORMALIZE_METALLIC := 0.0
const NORMALIZE_ROUGHNESS := 0.9

## The kit's flat-shaded swatches are a bright candy palette (mint grass, salmon
## dirt, near-white water) that fights the muted colours the campaign levels use.
## Remap the kit's named materials onto that same palette so this level reads as
## part of the same world (SPEC 11.1). Names come from the GLB material list.
const PALETTE := {
	"grass": Color(0.43, 0.56, 0.27),
	"leafsGreen": Color(0.22, 0.42, 0.20),
	"leafsDark": Color(0.17, 0.33, 0.17),
	"leafsFall": Color(0.70, 0.44, 0.20),
	"corn": Color(0.76, 0.68, 0.30),
	"dirt": Color(0.55, 0.43, 0.27),
	"dirtDark": Color(0.44, 0.34, 0.21),
	"wood": Color(0.52, 0.39, 0.24),
	"woodBark": Color(0.40, 0.30, 0.19),
	"woodBarkDark": Color(0.32, 0.24, 0.15),
	"woodDark": Color(0.44, 0.33, 0.20),
	"woodInner": Color(0.72, 0.60, 0.40),
	"woodBirch": Color(0.80, 0.76, 0.66),
	"stone": Color(0.55, 0.56, 0.52),
	"stoneDark": Color(0.43, 0.44, 0.41),
	"water": Color(0.18, 0.45, 0.78),
	"colorTan": Color(0.85, 0.78, 0.62),
	"colorRed": Color(0.72, 0.28, 0.22),
	"colorRedDark": Color(0.55, 0.20, 0.16),
	"colorYellow": Color(0.88, 0.74, 0.28),
	"colorPurple": Color(0.52, 0.38, 0.62),
	"colorWhite": Color(0.90, 0.90, 0.86),
}


## Ground surfaces the level draws itself, as meshes rather than kit tiles: roads
## are ribbons following their spine, the pond is an organic polygon, hills are
## faceted mounds. None of it follows a tile grid.
const PATH_LIFT := 0.02
const ROAD_MID := Color(0.60, 0.48, 0.30)
const ROAD_EDGE := Color(0.50, 0.39, 0.24)
const ROAD_WOOD := Color(0.50, 0.38, 0.23)
const WATER_COL := Color(0.20, 0.45, 0.71)
const SHORE_COL := Color(0.47, 0.38, 0.26)
const MOUND_ROCK := Color(0.52, 0.52, 0.48)
const MOUND_GRASS := Color(0.42, 0.54, 0.27)


func _ready() -> void:
	_build_ground()
	normalize_imported_materials()
	_build_scatter()


func _build_ground() -> void:
	_build_roads()
	_build_pond()
	_build_mounds()


## Flat, matte, double-sided material: these are ground decals seen from above, so
## there is nothing to shade and nothing to cull.
func _flat_material(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func _sample_spine(spine: PackedVector3Array, step: float) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for i in range(spine.size() - 1):
		var a := spine[i]
		var b := spine[i + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / step)))
		for k in n:
			pts.append(a.lerp(b, float(k) / float(n)))
	pts.append(spine[spine.size() - 1])
	return pts


## One triangle surface with up-facing normals. Flat-shaded ground, so normals are
## constant and no vertex colours are needed.
func _add_surface(parent: Node3D, surface_name: String, verts: PackedVector3Array,
		idx: PackedInt32Array, colour: Color) -> void:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _flat_material(colour))
	var mi := MeshInstance3D.new()
	mi.name = surface_name
	mi.mesh = mesh
	parent.add_child(mi)


## Roads: a ribbon laid along the spine the generator wrote into the scene, with a
## wobbling, uneven edge. `metadata/spine` is the only input.
func _build_roads() -> void:
	var root := get_node_or_null("Roads")
	if root == null:
		return
	for lane in root.get_children():
		var spine: PackedVector3Array = lane.get_meta("spine", PackedVector3Array())
		if spine.size() < 2:
			continue
		var half := float(lane.get_meta("half_width", 1.0))
		var seed := float(lane.get_meta("seed", 0.0))
		var wood := String(lane.get_meta("kind", "dirt")) == "wood"
		var pts := _sample_spine(spine, 0.8)
		var body := PackedVector3Array()
		var verge := PackedVector3Array()
		var body_i := PackedInt32Array()
		var verge_i := PackedInt32Array()
		for i in pts.size():
			var prev := pts[maxi(0, i - 1)]
			var next := pts[mini(pts.size() - 1, i + 1)]
			var dir := next - prev
			dir.y = 0.0
			dir = Vector3.RIGHT if dir.length_squared() < 1e-6 else dir.normalized()
			var side := Vector3(-dir.z, 0.0, dir.x)
			var f := float(i)
			var w := half * (1.0 + 0.16 * sin(f * 0.31 + seed * 3.1)
				+ 0.10 * sin(f * 0.83 + seed * 1.7))
			var wobble := 1.0 + 0.22 * sin(f * 0.57 + seed * 2.3)
			var p := pts[i]
			p.y = PATH_LIFT + 0.0015 * sin(f * 0.9 + seed)
			body.append(p + side * w * 0.72)
			body.append(p - side * w * 0.72)
			verge.append(p + side * w * wobble)
			verge.append(p + side * w * 0.66)
			verge.append(p - side * w * 0.66)
			verge.append(p - side * w * wobble)
		for i in pts.size() - 1:
			var a := i * 2
			var b := (i + 1) * 2
			body_i.append(a)
			body_i.append(b)
			body_i.append(a + 1)
			body_i.append(a + 1)
			body_i.append(b)
			body_i.append(b + 1)
			var va := i * 4
			var vb := (i + 1) * 4
			for k in [0, 2]:
				verge_i.append(va + k)
				verge_i.append(vb + k)
				verge_i.append(va + k + 1)
				verge_i.append(va + k + 1)
				verge_i.append(vb + k)
				verge_i.append(vb + k + 1)
		var mid_colour := ROAD_WOOD if wood else ROAD_MID
		_add_surface(lane, "Body", body, body_i, mid_colour)
		_add_surface(lane, "Verge", verge, verge_i, (mid_colour.darkened(0.14)))


## The pond: an organic water polygon with a muddy shore ring, plus lilies, a canoe
## and the bucket-brigade water markers around the rim.
func _build_pond() -> void:
	var pond := get_node_or_null("Water/Pond")
	if pond == null:
		return
	var centre: Vector2 = pond.get_meta("centre", Vector2(-19.0, 13.0))
	var radius := float(pond.get_meta("radius", 5.0))
	var seed := float(pond.get_meta("seed", 0.0))
	var segments := 56
	var ring: Array[Vector3] = []
	for i in range(segments + 1):
		var th := TAU * float(i) / float(segments)
		var r := radius * (1.0 + 0.20 * sin(3.0 * th + 0.6 + seed)
			+ 0.11 * sin(5.0 * th + 2.1 + seed * 0.5))
		ring.append(Vector3(centre.x + cos(th) * r, PATH_LIFT, centre.y + sin(th) * r))
	var water := PackedVector3Array([Vector3(centre.x, PATH_LIFT, centre.y)])
	for i in range(segments + 1):
		water.append(ring[i])
	var water_i := PackedInt32Array()
	for i in range(segments):
		water_i.append(0)
		water_i.append(i + 1)
		water_i.append(i + 2)
	var shore := PackedVector3Array()
	var shore_i := PackedInt32Array()
	for i in range(segments + 1):
		var edge: Vector3 = ring[i]
		var away := Vector3(edge.x - centre.x, 0.0, edge.z - centre.y).normalized()
		var wide := 0.6 + 0.6 * (0.5 + 0.5 * sin(float(i) * 0.9 + seed))
		shore.append(Vector3(edge.x, PATH_LIFT - 0.014, edge.z))
		shore.append(Vector3(edge.x, PATH_LIFT - 0.014, edge.z) + away * wide)
	for i in range(segments):
		var a := i * 2
		var b := (i + 1) * 2
		shore_i.append(a)
		shore_i.append(b)
		shore_i.append(a + 1)
		shore_i.append(a + 1)
		shore_i.append(b)
		shore_i.append(b + 1)
	_add_surface(pond, "Water", water, water_i, WATER_COL)
	_add_surface(pond, "Shore", shore, shore_i, SHORE_COL)
	var life := Node3D.new()
	life.name = "PondLife"
	pond.add_child(life)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed * 1000.0) + 7
	for i in 22:
		var th := rng.randf_range(0.0, TAU)
		var r := sqrt(rng.randf()) * radius * 0.75
		_place_kit_prop("lily_small" if i % 2 else "lily_large", life,
			Vector3(centre.x + cos(th) * r, PATH_LIFT + 0.004, centre.y + sin(th) * r),
			rng.randf_range(0.0, 360.0))
	_place_kit_prop("canoe", life,
		Vector3(centre.x + radius * 0.35, PATH_LIFT + 0.004, centre.y - radius * 0.25),
		rng.randf_range(-40.0, -10.0))
	_place_kit_prop("canoe_paddle", life,
		Vector3(centre.x + radius * 0.5, PATH_LIFT + 0.004, centre.y - radius * 0.05), 40.0)
	var points := get_node_or_null("Water/WaterPoints")
	if points != null:
		for i in range(0, segments, 4):
			var p := Node3D.new()
			p.name = "PondWater%d" % i
			p.position = Vector3(ring[i].x, 0.0, ring[i].z)
			p.add_to_group("water_sources")
			points.add_child(p)


func _place_kit_prop(model: String, parent: Node3D, pos: Vector3, rot_y: float) -> void:
	var path := "res://assets/nature/%s.glb" % model
	if not ResourceLoader.exists(path):
		return
	var packed: PackedScene = load(path)
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return
	inst.position = pos
	inst.rotation.y = deg_to_rad(rot_y)
	parent.add_child(inst)


## Hills: low-poly mounds — a rock skirt rising to a grass top.
func _build_mounds() -> void:
	var root := get_node_or_null("Hills")
	if root == null:
		return
	for hill in root.get_children():
		var centre: Vector2 = hill.get_meta("centre", Vector2.ZERO)
		var radii: Vector2 = hill.get_meta("radii", Vector2(3.0, 2.5))
		var height := float(hill.get_meta("height", 1.0))
		var seed := float(hill.get_meta("seed", 0.0))
		var segments := 28
		var skirt := PackedVector3Array()
		var skirt_i := PackedInt32Array()
		var rings := [
			{"scale": 1.0, "y": 0.0},
			{"scale": 0.72, "y": height * 0.55},
			{"scale": 0.38, "y": height * 0.92},
		]
		for ring in rings:
			for i in range(segments + 1):
				var th := TAU * float(i) / float(segments)
				var wob := 1.0 + 0.07 * sin(3.0 * th + seed) + 0.04 * sin(5.0 * th + seed * 2.0)
				var scale := float(ring["scale"])
				skirt.append(Vector3(centre.x + cos(th) * radii.x * scale * wob,
					float(ring["y"]),
					centre.y + sin(th) * radii.y * scale * wob))
		for band in 2:
			var a := band * (segments + 1)
			var b := (band + 1) * (segments + 1)
			for i in range(segments):
				skirt_i.append(a + i)
				skirt_i.append(b + i)
				skirt_i.append(a + i + 1)
				skirt_i.append(a + i + 1)
				skirt_i.append(b + i)
				skirt_i.append(b + i + 1)
		_add_surface(hill, "Skirt", skirt, skirt_i, MOUND_ROCK)
		# grass cap: a fan over the top ring
		var cap := PackedVector3Array()
		var cap_i := PackedInt32Array()
		for i in range(segments + 1):
			var th := TAU * float(i) / float(segments)
			var wob := 1.0 + 0.07 * sin(3.0 * th + seed) + 0.04 * sin(5.0 * th + seed * 2.0)
			cap.append(Vector3(centre.x + cos(th) * radii.x * 0.38 * wob, height * 0.92,
				centre.y + sin(th) * radii.y * 0.38 * wob))
		cap.append(Vector3(centre.x, height * 1.02, centre.y))
		var top := cap.size() - 1
		for i in range(segments):
			cap_i.append(i)
			cap_i.append(top)
			cap_i.append(i + 1)
		_add_surface(hill, "Cap", cap, cap_i, MOUND_GRASS)


## Dense ground cover (grass tufts, leaf litter, flowers) is declared as Scatter
## field nodes with metadata and realised here as MultiMeshes: a few hundred
## tufts then cost one draw call per field instead of one node each.
func _build_scatter() -> void:
	var scatter := get_node_or_null("Scatter")
	if scatter == null:
		return
	var flags := _path_flags()
	var rng := RandomNumberGenerator.new()
	for field in scatter.get_children():
		var model := String(field.get_meta("model", ""))
		if model == "":
			continue
		var mesh := _mesh_of(model)
		if mesh == null:
			continue
		var area: Vector4 = field.get_meta("area", Vector4(-25, -22, 25, 22))
		var want := int(field.get_meta("count", 0))
		var smin := float(field.get_meta("scale_min", 0.9))
		var smax := float(field.get_meta("scale_max", 1.4))
		var base_y := float(field.get_meta("y", 0.0))
		rng.seed = int(field.get_meta("seed", 1))

		var placed: Array[Transform3D] = []
		var guard := 0
		while placed.size() < want and guard < want * 25:
			guard += 1
			var x := rng.randf_range(area.x, area.z)
			var z := rng.randf_range(area.y, area.w)
			var cell := Vector2i(int(floor(x / 2.0)), int(floor(z / 2.0)))
			if flags.get(cell, 0) == 2:
				continue
			if _near_plot(x, z):
				continue
			# Ground cover grows in drifts, and thicker along the verges: a uniform
			# speckle just reads as noise from the game camera.
			var density := _clump_density(x, z)
			if flags.get(cell, 0) == 1:
				density *= 2.1
			if rng.randf() > density:
				continue
			var s := rng.randf_range(smin, smax)
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(s, s, s))
			placed.append(Transform3D(basis, Vector3(x, base_y, z)))

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = placed.size()
		for i in placed.size():
			mm.set_instance_transform(i, placed[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = String(field.name)
		mmi.multimesh = mm
		field.add_child(mmi)


## MultiMeshInstances cannot carry per-instance material overrides, so the GLB's
## material (often an override on the MeshInstance rather than baked into the mesh
## surfaces) is copied onto the mesh before it is shared by the MultiMesh.
func _mesh_of(model: String) -> Mesh:
	var path := "res://assets/nature/%s.glb" % model
	if not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path)
	var inst := packed.instantiate()
	var mesh: Mesh = null
	var source: MeshInstance3D = null
	for child in _all_descendants(inst):
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh != null:
			mesh = mi.mesh
			source = mi
			break
	if mesh != null and source != null:
		for surface in mesh.get_surface_count():
			var mat := source.get_surface_override_material(surface)
			if mat == null:
				mat = mesh.surface_get_material(surface)
			if mat != null:
				mesh.surface_set_material(surface, mat)
	inst.free()
	return mesh


## Cell flags for ground cover, read from the same metadata the ground meshes are
## built from: 0 = open meadow, 1 = verge (open, next to a lane), 2 = covered
## (lane, water or a reserved plot). Verges get a thickness of tufts so a lane
## reads as a track worn through grass rather than a painted ribbon.
func _path_flags() -> Dictionary:
	var flags := {}
	for lane in _children_of(get_node_or_null("Roads")):
		var spine: PackedVector3Array = lane.get_meta("spine", PackedVector3Array())
		var half := float(lane.get_meta("half_width", 1.2))
		for i in range(spine.size() - 1):
			var a := spine[i]
			var b := spine[i + 1]
			var steps := maxi(1, int(a.distance_to(b) / 2.0))
			for k in steps + 1:
				var pt := a.lerp(b, float(k) / float(steps))
				_mark_cells(flags, pt.x, pt.z, half + 0.3, 2)
				_mark_cells(flags, pt.x, pt.z, half + 2.2, 1)
	var pond := get_node_or_null("Water/Pond")
	if pond != null:
		var centre: Vector2 = pond.get_meta("centre", Vector2.ZERO)
		var radius := float(pond.get_meta("radius", 0.0))
		_mark_cells(flags, centre.x, centre.y, radius * 1.5, 2)
		_mark_cells(flags, centre.x, centre.y, radius * 1.5 + 1.6, 1)
	for plot in _children_of(get_node_or_null("HousePlots")):
		if plot.has_meta("cluster"):
			_mark_cells(flags, plot.position.x, plot.position.z, 2.5, 2)
	return flags


func _children_of(root: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if root == null:
		return out
	for child in root.get_children():
		if child is Node3D:
			out.append(child)
	return out


func _mark_cells(flags: Dictionary, x: float, z: float, radius: float, flag: int) -> void:
	var cx := int(floor(x / 2.0))
	var cz := int(floor(z / 2.0))
	var reach := int(ceil(radius / 2.0)) + 1
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var key := Vector2i(cx + dx, cz + dz)
			var centre := Vector2((float(key.x) + 0.5) * 2.0, (float(key.y) + 0.5) * 2.0)
			if Vector2(x, z).distance_to(centre) <= radius:
				flags[key] = maxi(int(flags.get(key, 0)), flag)


## Low-frequency noise so tufts gather into drifts and clearings rather than
## spreading evenly across the meadow.
func _clump_density(x: float, z: float) -> float:
	var n := sin(x * 0.29 + z * 0.15) * 0.5 + sin(x * 0.11 - z * 0.27) * 0.35 \
		+ sin((x + z) * 0.06) * 0.2
	return clampf(0.40 + n * 0.75, 0.10, 1.30)


func _near_plot(x: float, z: float) -> bool:
	var root := get_node_or_null("HousePlots")
	if root == null:
		return false
	for child in root.get_children():
		if child is not Node3D or not child.has_meta("cluster"):
			continue
		var p := (child as Node3D).position
		if absf(p.x - x) < 2.6 and absf(p.z - z) < 2.6:
			return true
	return false


## Kenney GLB materials are shared per model, so patching them once fixes every
## instance of that model in this level.
func normalize_imported_materials() -> void:
	var patched := 0
	for node in _all_descendants(self):
		var mesh: Mesh = null
		var mi := node as MeshInstance3D
		var mmi := node as MultiMeshInstance3D
		if mi != null:
			mesh = mi.mesh
		elif mmi != null and mmi.multimesh != null:
			mesh = mmi.multimesh.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var mat := mesh.surface_get_material(surface) as StandardMaterial3D
			if mat == null:
				continue
			var changed := false
			if mat.metallic != NORMALIZE_METALLIC:
				mat.metallic = NORMALIZE_METALLIC
				changed = true
			if not is_equal_approx(mat.roughness, NORMALIZE_ROUGHNESS):
				mat.roughness = NORMALIZE_ROUGHNESS
				changed = true
			if PALETTE.has(mat.resource_name):
				mat.albedo_color = PALETTE[mat.resource_name]
				changed = true
			if changed:
				patched += 1
	if patched > 0:
		print("VillageFields: normalised %d imported material surfaces" % patched)


func _all_descendants(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_all_descendants(c))
	return out


## The level authors its own sky and sun so it also looks right when opened
## standalone. When the game hosts this scene it copies these values onto its
## single Environment/Sun and hides these nodes, so nothing is lit twice.
func release_atmosphere_visuals() -> void:
	# The host game duplicates the Environment and copies the sun transform, so the
	# authoring nodes are removed here to avoid lighting the scene twice.
	var env_node := get_node_or_null("Atmosphere/WorldEnvironment") as WorldEnvironment
	if env_node != null:
		env_node.environment = null
		env_node.queue_free()
	var sun_node := get_node_or_null("Atmosphere/Sun") as DirectionalLight3D
	if sun_node != null:
		sun_node.visible = false


func get_environment() -> Environment:
	var env_node := get_node_or_null("Atmosphere/WorldEnvironment") as WorldEnvironment
	return env_node.environment if env_node != null else null


func get_sun() -> DirectionalLight3D:
	return get_node_or_null("Atmosphere/Sun") as DirectionalLight3D


## Collected data for the game: see LevelBuilder.LevelContext.
func build_context(units_root: Node3D) -> LevelBuilder.LevelContext:
	var ctx := LevelBuilder.LevelContext.new()
	ctx.name = LEVEL_NAME
	ctx.sub = LEVEL_SUB
	ctx.cam_bound = CAM_BOUND
	ctx.camera_size = CAMERA_SIZE
	ctx.staging = true
	ctx.plots = house_plots()

	var houses_root := get_node_or_null("Houses")
	for node in _all_descendants(houses_root if houses_root != null else self):
		var h := node as VoxelHouse
		if h == null:
			continue
		ctx.houses.append(h)
		if h.is_in_group("mandatory_houses") or h.kind == "house":
			ctx.mandatory_houses.append(h)

	# The opening spark is free on any house (SPEC 7.2); the starter plot is
	# simply the site the level's layout suggests opening on.
	if not ctx.mandatory_houses.is_empty():
		ctx.starter_house = ctx.mandatory_houses[0]

	ctx.staging = ctx.houses.is_empty()

	# The village only fields a bucket brigade once there is something to burn;
	# while the scene is still a foundation there is nothing to defend.
	if not ctx.staging and VILLAGER_COUNT > 0:
		LevelBuilder.spawn_villagers(VILLAGER_COUNT, ctx.cam_bound, units_root)

	return ctx


## Reserved building sites, nearest-first from the starter plot, with the gaps the
## fire rules will see. Used by tooling and by the (future) house placer.
func house_plots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var root := get_node_or_null("HousePlots")
	if root == null:
		return out
	for child in root.get_children():
		if child is not Node3D or not child.has_meta("cluster"):
			continue
		out.append({
			"name": String(child.name),
			"position": (child as Node3D).position,
			"facing": rad_to_deg((child as Node3D).rotation.y),
			"cluster": child.get_meta("cluster", "unassigned"),
			"role": child.get_meta("role", "mandatory"),
			"size": child.get_meta("size", Vector3(3, 3, 3)),
		})
	return out
