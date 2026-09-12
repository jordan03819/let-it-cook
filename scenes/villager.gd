extends CharacterBody3D
class_name VoxelVillager
## Lookout villager (L1): NOT flammable, never burns, never spreads.
## Wanders between houses. If a burning house is in sight -> spots it (! bubble).
## If fire is close -> panics and flees away. Game polls has_spotted() for Alarm/demo.

var speed_wander: float = 1.8
var speed_panic: float = 4.2
var speed_bucket: float = 3.6
var sight_radius: float = 11.0
var panic_radius: float = 7.0
var role: String = "lookout" # lookout | bucket (brave, approaches fire)
var bucket_target: Node3D = null

var _visual: Node3D = null
var _bubble: Label3D = null
var _dir: Vector3 = Vector3.FORWARD
var _think_t: float = 0.0
var _bubble_t: float = 0.0
var _panicking: bool = false
var _spotted: bool = false


func _ready() -> void:
	add_to_group("villagers")
	_build()
	_build_bubble()


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	return m


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	_visual.add_child(mi)


func _build() -> void:
	_visual = Node3D.new()
	add_child(_visual)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 1.4, 0.6)
	col.shape = shape
	col.position = Vector3(0, 0.7, 0)
	add_child(col)
	var skin := _mat(Color(0.95, 0.78, 0.62))
	var shirt := _mat(Color(0.3 + randf() * 0.6, 0.35 + randf() * 0.4, 0.5 + randf() * 0.4))
	var pants := _mat(Color(0.25, 0.25, 0.35))
	_box(Vector3(0.5, 0.55, 0.35), Vector3(0, 0.85, 0), shirt)
	_box(Vector3(0.2, 0.55, 0.2), Vector3(-0.13, 0.27, 0), pants)
	_box(Vector3(0.2, 0.55, 0.2), Vector3(0.13, 0.27, 0), pants)
	_box(Vector3(0.42, 0.38, 0.42), Vector3(0, 1.32, 0), skin)
	_box(Vector3(0.46, 0.14, 0.46), Vector3(0, 1.55, 0), _mat(Color(0.2 + randf() * 0.6, 0.15, 0.1)))


func _build_bubble() -> void:
	_bubble = Label3D.new()
	_bubble.text = "!"
	_bubble.font_size = 128
	_bubble.pixel_size = 0.012
	_bubble.modulate = Color(1.0, 0.85, 0.2)
	_bubble.outline_size = 16
	_bubble.outline_modulate = Color(0.1, 0.05, 0.05)
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.position = Vector3(0, 2.4, 0)
	_bubble.visible = false
	add_child(_bubble)


func has_spotted() -> bool:
	return _spotted


func set_bucket(t: Node3D) -> void:
	role = "bucket"
	bucket_target = t
	_build_bucket()
	_show_bubble("~", Color(0.4, 0.7, 1.0))


func clear_bucket() -> void:
	role = "lookout"
	bucket_target = null
	var b := get_node_or_null("Bucket")
	if b != null:
		b.queue_free()


func is_bucket() -> bool:
	return role == "bucket"


func _build_bucket() -> void:
	if get_node_or_null("Bucket") != null or _visual == null:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.35, 0.3)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.55, 0.95)
	m.roughness = 1.0
	bm.material = m
	mi.mesh = bm
	mi.name = "Bucket"
	mi.position = Vector3(0.4, 0.9, 0.2)
	_visual.add_child(mi)


func is_panicking() -> bool:
	return _panicking


func _physics_process(delta: float) -> void:
	if role == "bucket":
		_physics_bucket(delta)
		return
	_think_t -= delta
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0 and _bubble != null:
			_bubble.visible = false
	# Nearest burning building.
	var nearest_d := 1e9
	var nearest_pos := Vector3.ZERO
	for h in get_tree().get_nodes_in_group("houses"):
		if h is VoxelHouse and h.state == VoxelHouse.State.BURNING:
			var d := global_position.distance_to((h as Node3D).global_position)
			if d < nearest_d:
				nearest_d = d
				nearest_pos = (h as Node3D).global_position
	if nearest_d < sight_radius:
		if not _spotted:
			_spotted = true
			_show_bubble("!")
		elif nearest_d < sight_radius * 0.6:
			_show_bubble("!")
	_panicking = nearest_d < panic_radius
	var spd := speed_panic if _panicking else speed_wander
	if _think_t <= 0.0:
		_think_t = 0.35 if _panicking else randf_range(1.0, 2.2)
		if _panicking:
			var away: Vector3 = global_position - nearest_pos
			away.y = 0.0
			_dir = away.normalized() if away.length() > 0.01 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		else:
			# Drift toward village center-ish so they stay around houses.
			if randf() < 0.3:
				var home: Vector3 = -global_position
				home.y = 0.0
				_dir = home.normalized() if home.length() > 1.0 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			else:
				_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	# Keep inside bounds.
	if absf(global_position.x) > 16.0 or absf(global_position.z) > 16.0:
		_dir = (-global_position.normalized())
		_think_t = 1.0
	velocity = _dir * spd
	if _dir.length_squared() > 0.01:
		_visual.rotation.y = atan2(_dir.x, _dir.z)
	_visual.position.y = absf(sin(Time.get_ticks_msec() * (0.02 if _panicking else 0.008))) * (0.12 if _panicking else 0.05)
	move_and_slide()


func _physics_bucket(delta: float) -> void:
	# Brave: walk to the assigned burning house, stand ~3m off and hold.
	# Splash effect itself is applied by game.gd (single authority).
	_think_t -= delta
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0 and _bubble != null:
			_bubble.visible = false
	if bucket_target == null or not is_instance_valid(bucket_target):
		velocity = Vector3.ZERO
		move_and_slide()
		return
	var to: Vector3 = (bucket_target as Node3D).global_position - global_position
	to.y = 0.0
	var d := to.length()
	if d > 3.2:
		_dir = to.normalized() if d > 0.01 else _dir
		velocity = _dir * speed_bucket
	else:
		velocity = Vector3.ZERO
	if _dir.length_squared() > 0.01:
		_visual.rotation.y = atan2(_dir.x, _dir.z)
	_visual.position.y = absf(sin(Time.get_ticks_msec() * 0.014)) * 0.08
	move_and_slide()


func _show_bubble(txt: String, col: Color = Color(1.0, 0.85, 0.2)) -> void:
	if _bubble == null:
		return
	_bubble.text = txt
	_bubble.modulate = col
	_bubble.visible = true
	_bubble_t = 1.6
