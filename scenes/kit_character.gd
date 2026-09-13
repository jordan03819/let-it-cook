class_name KitCharacter
extends RefCounted
## Mini-character visuals for the level's NPCs, built from the Kenney Mini
## Characters kit (CC0, assets/chars/).
##
## The kit ships twelve rigged characters (six male, six female) plus aids and
## wheelchairs, each with a cartoon skeleton — root, torso, head, two legs, two
## arms — and a 30-clip animation library (idle, walk, sprint, holding-*, die,
## emote-*, …). This module is the single place that knows how to turn one of
## those models into a game NPC visual: scaled to the height the game expects,
## with its own material copies so a burning villager does not recolour the
## whole crowd, and with helpers for driving the kit's own animations.

const DIR := "res://assets/chars/"

## Clip names the game drives. The kit ships these (see variants() docs).
const CLIP_IDLE := "idle"
const CLIP_WALK := "walk"
const CLIP_RUN := "sprint"
const CLIP_HOLD_RIGHT := "holding-right"
const CLIP_HOLD_LEFT := "holding-left"
const CLIP_DIE := "die"
const CLIP_CHEER := "emote-yes"
const CLIP_DENY := "emote-no"

## The character models only — the kit also ships wheelchairs, canes, crutches
## and glasses, which are props rather than people.
const MODELS: Array[String] = [
	"character-male-a", "character-male-b", "character-male-c",
	"character-male-d", "character-male-e", "character-male-f",
	"character-female-a", "character-female-b", "character-female-c",
	"character-female-d", "character-female-e", "character-female-f",
]

## Character heights the game uses. The Mini Characters kit is drawn to the same
## unit convention as the Fantasy Town kit — its people are about as tall as one
## of the town kit's doors (0.7-0.8 units) — so a character is at its correct
## size against a cottage when it is *not* scaled up. The game's actors are
## built to these heights, and the props they carry hang off the same number.
const VILLAGER_HEIGHT := 0.80
const RESPONDER_HEIGHT := 0.86
const SHAMAN_HEIGHT := 0.92

## Height the characters are authored at, measured off the models (metres).
static var _natural: Dictionary = {}
static var _scene_cache: Dictionary = {}


static func scene(model: String) -> PackedScene:
	if not _scene_cache.has(model):
		var path := DIR + model + ".glb"
		_scene_cache[model] = load(path) if ResourceLoader.exists(path) else null
	return _scene_cache[model]


## Pick a character model by index; `salt` lets callers derive a stable choice.
static func model_for(index: int) -> String:
	return MODELS[posmod(index, MODELS.size())]


## Builds one character visual, `height` metres tall, facing +Z like the rest of
## the game's actors. The returned node is the one to move and turn: its
## AnimationPlayer is inside it, and its materials are private to this instance.
static func build(model: String, height: float = 1.55, tint: Color = Color.WHITE) -> Node3D:
	var sc := scene(model)
	if sc == null:
		push_warning("KitCharacter: missing model '%s'" % model)
		return Node3D.new()
	var root: Node3D = sc.instantiate()
	root.name = "NpcVisual"
	root.scale = Vector3.ONE * (height / _height_of(model, root))
	_own_materials(root, tint)
	play(root, CLIP_IDLE)
	return root


static func _height_of(model: String, root: Node3D) -> float:
	if not _natural.has(model):
		var aabb := AABB()
		var first := true
		for mi in meshes(root):
			if mi.mesh == null or mi.mesh.get_surface_count() == 0:
				continue
			var a: AABB = mi.transform * mi.mesh.get_aabb()
			aabb = a if first else aabb.merge(a)
			first = false
		_natural[model] = maxf(0.05, aabb.size.y)
	return _natural[model]


## Copies every material so this character can be tinted, scorched and set
## alight without touching anyone else wearing the same shirt.
static func _own_materials(root: Node3D, tint: Color) -> void:
	for mi in meshes(root):
		var src := mi.get_active_material(0) as StandardMaterial3D
		var mat := StandardMaterial3D.new()
		if src != null:
			mat = src.duplicate()
		mat.metallic = 0.0
		mat.roughness = 0.9
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.resource_local_to_scene = true
		if tint != Color.WHITE:
			mat.albedo_color = mat.albedo_color * tint
		# Characters are flammable: CharBurn drives this emission when they burn.
		mat.emission_enabled = true
		mat.emission = Color(0, 0, 0)
		mat.emission_energy_multiplier = 0.0
		mi.material_override = mat


static func meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		out.append_array(meshes(c))
	return out


static func animation_player(visual: Node3D) -> AnimationPlayer:
	if visual == null:
		return null
	for c in visual.find_children("*", "AnimationPlayer", true, false):
		return c as AnimationPlayer
	return null


## Plays a clip if it is not already the one running, so callers can ask for a
## state every frame without restarting the animation each time.
static func play(visual: Node3D, clip: String, speed: float = 1.0) -> void:
	var player := animation_player(visual)
	if player == null:
		return
	if not player.has_animation(clip):
		clip = CLIP_IDLE
	if player.current_animation == clip:
		player.speed_scale = speed
		return
	player.speed_scale = speed
	player.play(clip)


## True while `clip` is the running animation, for callers that want to know
## whether a one-shot (a death, a cheer) has been replaced yet.
static func is_playing(visual: Node3D, clip: String) -> bool:
	var player := animation_player(visual)
	return player != null and player.current_animation == clip
