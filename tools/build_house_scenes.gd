extends SceneTree
## Generates the modular house scenes under `scenes/houses/`.
##
##   godot --path . --script res://tools/build_house_scenes.gd
##
## Each scene is a complete `VoxelHouse` (so a level can just instance it):
## the burnable root with its fuel/size/kind set, plus the kit cottage baked in
## as a child named "Model" that VoxelHouse adopts on _ready(). Re-run this
## after changing KitHouse, then place instances in a level.
##
## The variants differ in footprint, wall material, roof family and trim, so a
## row of houses reads as a village rather than a copy-paste.

const OUT_DIR := "res://scenes/houses/"

## name, width (tiles), depth, wall piece, roof family, windows, chimney
const VARIANTS := [
	{"file": "house_cottage_small", "w": 2, "d": 2, "wall": "wall-wood", "roof": "teal", "windows": 1, "chimney": true},
	{"file": "house_cottage", "w": 3, "d": 2, "wall": "wall-wood", "roof": "clay", "windows": 2, "chimney": true},
	{"file": "house_cottage_teal", "w": 3, "d": 2, "wall": "wall", "roof": "teal", "windows": 2, "chimney": false},
	{"file": "house_cottage_wide", "w": 4, "d": 2, "wall": "wall-wood", "roof": "clay", "windows": 3, "chimney": true},
	{"file": "house_cottage_wide_teal", "w": 4, "d": 2, "wall": "wall", "roof": "teal", "windows": 3, "chimney": false},
	{"file": "house_hall", "w": 5, "d": 2, "wall": "wall-wood", "roof": "clay", "windows": 4, "chimney": true},
]

## Fuel is deliberately the same for every cottage: the village's difficulty
## should come from its layout, not from one house being a magic fuel sponge.
## (SPEC 11.1: village houses burn like any other.)
const FUEL := 52.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var house_scene: PackedScene = load("res://scenes/house.tscn")
	if house_scene == null:
		push_error("build_house_scenes: house.tscn not found")
		quit(1)
		return

	var written := 0
	for spec in VARIANTS:
		var path := OUT_DIR + str(spec["file"]) + ".tscn"
		if _build_one(house_scene, spec, path):
			written += 1
	print("build_house_scenes: wrote %d/%d scenes to %s" % [written, VARIANTS.size(), OUT_DIR])
	quit(0 if written == VARIANTS.size() else 1)


func _build_one(house_scene: PackedScene, spec: Dictionary, path: String) -> bool:
	var house: VoxelHouse = house_scene.instantiate()
	if house == null:
		return false
	house.name = String(spec["file"]).replace("house_", "")

	var build := {
		"w": int(spec["w"]),
		"d": int(spec["d"]),
		"wall": str(spec["wall"]),
		"roof_style": str(spec["roof"]),
		"windows": int(spec["windows"]),
		"chimney": bool(spec["chimney"]),
		"seed": int(spec["w"]) * 131 + int(spec["windows"]) * 7,
	}
	var model := KitHouse.build_cottage(build)
	model.name = VoxelHouse.MODEL_NODE_NAME
	house.add_child(model)
	# Everything that should be saved has to be owned by the scene root,
	# including the kit pieces nested under the model.
	model.owner = house
	# Only the piece roots are owned by the scene. Walking into the kit models
	# would save their internals as editable children *and* keep the instance,
	# which draws every wall and roof tile twice.
	for piece in model.get_children():
		piece.owner = house

	var size := KitHouse.cottage_size(build)
	house.house_size = size
	house.fuel_max = FUEL
	house.fuel = FUEL
	house.kind = "house"
	house.base_color = Color(0.82, 0.76, 0.66)
	house.roof_color = Color(0.62, 0.26, 0.20) if str(spec["roof"]) == "clay" else Color(0.32, 0.44, 0.38)
	house.add_to_group("mandatory_houses")

	var packed := PackedScene.new()
	var err := packed.pack(house)
	if err != OK:
		push_error("build_house_scenes: packing %s failed (%d)" % [path, err])
		house.free()
		return false
	err = ResourceSaver.save(packed, path)
	house.free()
	if err != OK:
		push_error("build_house_scenes: saving %s failed (%d)" % [path, err])
		return false
	print("  %-28s w=%d roof=%-5s size=%s" % [path, int(spec["w"]), str(spec["roof"]), str(size)])
	return true
