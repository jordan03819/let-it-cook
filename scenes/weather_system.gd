class_name WeatherSystem
extends Node3D
## WeatherSystem — Encapsulates weather states, rain particle simulation,
## and environment wetness application (SPEC Section 10.1 & 19).

signal rain_started(duration: float)
signal rain_stopped()

var rain_active: bool = false
var rain_timer: float = 0.0
var rain_particles: GPUParticles3D = null

var houses: Array[VoxelHouse] = []
var barrels: Array[VoxelBarrel] = []
var cam_bound: float = 16.0


func setup(p_houses: Array[VoxelHouse], p_barrels: Array[VoxelBarrel], p_cam_bound: float) -> void:
	houses = p_houses
	barrels = p_barrels
	cam_bound = p_cam_bound
	if rain_active:
		stop_rain()


func start_rain(duration: float = 25.0) -> void:
	rain_active = true
	rain_timer = duration

	if rain_particles == null or not is_instance_valid(rain_particles):
		rain_particles = GPUParticles3D.new()
		rain_particles.name = "RainStormParticles"
		rain_particles.amount = 260
		rain_particles.lifetime = 1.0
		rain_particles.preprocess = 0.5
		rain_particles.local_coords = false
		rain_particles.visibility_aabb = AABB(Vector3(-25, -15, -25), Vector3(50, 30, 50))

		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0.08, -1.0, 0.04).normalized()
		pm.spread = 4.0
		pm.initial_velocity_min = 22.0
		pm.initial_velocity_max = 28.0
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(cam_bound * 1.4, 0.5, cam_bound * 1.4)
		pm.scale_min = 0.8
		pm.scale_max = 1.4
		pm.color = Color(0.65, 0.82, 0.98, 0.75)
		rain_particles.process_material = pm

		var streak := BoxMesh.new()
		streak.size = Vector3(0.04, 0.55, 0.04)
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.65, 0.82, 0.98, 0.7)
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		streak.material = sm
		rain_particles.draw_pass_1 = streak

		add_child(rain_particles)

	rain_particles.emitting = true
	SoundManager.set_rain_ambience(true)
	rain_started.emit(duration)


func stop_rain() -> void:
	if not rain_active:
		return
	rain_active = false
	rain_timer = 0.0
	if rain_particles != null and is_instance_valid(rain_particles):
		rain_particles.emitting = false
	SoundManager.set_rain_ambience(false)
	rain_stopped.emit()


func tick(delta: float, camera_pos: Vector3) -> void:
	if not rain_active:
		return

	rain_timer = maxf(0.0, rain_timer - delta)
	if rain_particles != null and is_instance_valid(rain_particles):
		rain_particles.global_position = camera_pos + Vector3(0, 16.0, 0)

	for h in houses:
		if is_instance_valid(h):
			h.apply_water(0.24, delta)
	for b in barrels:
		if is_instance_valid(b):
			b.apply_water(0.18, delta)

	if rain_timer <= 0.0:
		stop_rain()


func cleanup() -> void:
	stop_rain()
	if rain_particles != null and is_instance_valid(rain_particles):
		rain_particles.queue_free()
		rain_particles = null
