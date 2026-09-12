class_name FireSimulation
extends RefCounted
## FireSimulation — Encapsulates heat propagation, wind dynamics, and spread (SPEC Section 19).
## Simulates accumulated ignition pressure between burning nodes, ambient wind shifts,
## active Wind Gust acceleration, wetness damping, and heat transfer to structures and barrels.

signal wind_shifted(new_dir: Vector3)

# Spatial tuning bands (SPEC Section 6.3)
# Connected: <= 4.2m, Conditional: 4.2m–6.0m, Broken: > 6.0m (crossable by Wind Gust up to 8.5m)
const HOUSE_CONNECTED_RADIUS: float = 4.2
const HOUSE_CONDITIONAL_RADIUS: float = 6.0
const HOUSE_RADIUS: float = HOUSE_CONDITIONAL_RADIUS
const TREE_RADIUS: float = 4.5
const HOUSE_HEAT: float = 0.035
const TREE_HEAT: float = 0.13
const HEAT_DECAY: float = 0.025

const WIND_BIAS: float = 0.8
const WIND_SHIFT_MIN: float = 22.0
const WIND_SHIFT_MAX: float = 34.0

const WIND_GUST_DURATION: float = 4.0
const WIND_GUST_RANGE: float = 8.5
const WIND_GUST_HALF_ANGLE: float = deg_to_rad(30.0) # 60-degree cone total

var houses: Array[VoxelHouse] = []
var barrels: Array[VoxelBarrel] = []

var wind_dir: Vector3 = Vector3(1, 0, 0.3).normalized()
var wind_strength: float = 1.0
var _wind_target: Vector3 = Vector3(1, 0, 0.3).normalized()
var _wind_target_strength: float = 1.0
var _wind_timer: float = 25.0

var active_gust_timer: float = 0.0
var active_gust_origin: Vector3 = Vector3.ZERO
var active_gust_dir: Vector3 = Vector3.FORWARD


func setup(p_houses: Array[VoxelHouse], p_barrels: Array[VoxelBarrel]) -> void:
	houses = p_houses
	barrels = p_barrels
	active_gust_timer = 0.0
	active_gust_origin = Vector3.ZERO
	active_gust_dir = Vector3.FORWARD

	var a0 := randf() * TAU
	wind_dir = Vector3(cos(a0), 0, sin(a0)).normalized()
	_wind_target = wind_dir
	wind_strength = randf_range(0.7, 1.1)
	_wind_target_strength = wind_strength
	_wind_timer = randf_range(WIND_SHIFT_MIN, WIND_SHIFT_MAX)


func cast_gust(origin: Vector3, dir: Vector3) -> void:
	active_gust_origin = origin
	active_gust_dir = dir
	active_gust_timer = WIND_GUST_DURATION


func is_gust_active() -> bool:
	return active_gust_timer > 0.0


func tick(delta: float, rain_active: bool) -> void:
	if active_gust_timer > 0.0:
		active_gust_timer = maxf(0.0, active_gust_timer - delta)

	_update_wind(delta)
	_tick_heat(delta, rain_active)


func _update_wind(delta: float) -> void:
	_wind_timer -= delta
	if _wind_timer <= 0.0:
		_wind_timer = randf_range(WIND_SHIFT_MIN, WIND_SHIFT_MAX)
		var cur_ang := atan2(wind_dir.x, wind_dir.z)
		cur_ang += randf_range(-2.2, 2.2)
		_wind_target = Vector3(cos(cur_ang), 0, sin(cur_ang)).normalized()
		_wind_target_strength = randf_range(0.6, 1.3)
		wind_shifted.emit(_wind_target)
	wind_dir = (wind_dir.lerp(_wind_target, minf(1.0, delta * 0.4))).normalized()
	wind_strength = lerpf(wind_strength, _wind_target_strength, minf(1.0, delta * 0.3))


func _tick_heat(delta: float, rain_active: bool) -> void:
	var burning_nodes: Array[VoxelHouse] = []
	for h in houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
			burning_nodes.append(h)

	if burning_nodes.is_empty():
		for h in houses:
			if is_instance_valid(h) and h.state == VoxelHouse.State.UNBURNED and h.heat > 0.0:
				h.heat = maxf(0.0, h.heat - HEAT_DECAY * delta)
		return

	# Apply gust visual tilt to flames within active gust
	if active_gust_timer > 0.0:
		for src in burning_nodes:
			var to_src := src.global_position - active_gust_origin
			to_src.y = 0.0
			if to_src.length() <= WIND_GUST_RANGE + 1.0:
				src.apply_gust_tilt(active_gust_dir)

	for dst in houses:
		if not is_instance_valid(dst) or dst.state != VoxelHouse.State.UNBURNED or dst.kind == "stone":
			continue

		var rate := TREE_HEAT if dst.kind == "tree" else HOUSE_HEAT
		var power := 0.0

		for src in burning_nodes:
			var to: Vector3 = dst.global_position - src.global_position
			var dist := to.length()
			if dist < 0.01:
				continue

			# Check if target structure lies within active player Wind Gust cone
			var inside_active_gust := false
			if active_gust_timer > 0.0:
				var to_dst: Vector3 = dst.global_position - active_gust_origin
				to_dst.y = 0.0
				var dst_dist := to_dst.length()
				if dst_dist <= WIND_GUST_RANGE:
					var gust_align := (to_dst / maxf(0.01, dst_dist)).dot(active_gust_dir)
					if gust_align >= cos(WIND_GUST_HALF_ANGLE):
						inside_active_gust = true

			# Max effective distance: Wind Gust reaches up to 8.5m; ambient spread reaches conditional 6.0m
			var max_dist := WIND_GUST_RANGE if inside_active_gust else (TREE_RADIUS if dst.kind == "tree" else HOUSE_CONDITIONAL_RADIUS)
			if dist > max_dist:
				continue

			var align: float = (to / dist).dot(wind_dir)
			var w: float = maxf(0.2, 1.0 + align * wind_strength * WIND_BIAS)

			# If in conditional band (> 4.2m) without active gust, spread requires favorable wind
			if not inside_active_gust and dist > HOUSE_CONNECTED_RADIUS:
				var falloff: float = 1.0 - (dist - HOUSE_CONNECTED_RADIUS) / (HOUSE_CONDITIONAL_RADIUS - HOUSE_CONNECTED_RADIUS)
				w *= maxf(0.0, falloff * (0.3 + align * 0.7))

			if dst.kind == "house" and src.kind == "tree":
				w *= 0.5

			# Active Local Wind Gust acceleration (SPEC Section 6.6)
			if inside_active_gust:
				w *= 3.5

			power += maxf(0.0, w)
			if power >= 3.5:
				break

		# Wetness suppresses incoming heat (SPEC Section 6.4 & 8.4)
		if dst.wetness > 0.05:
			power *= maxf(0.08, 1.0 - dst.wetness * 0.9)
		if rain_active:
			power *= 0.42

		if power > 0.0:
			dst.heat = minf(1.0, dst.heat + rate * power * delta)
			if dst.heat >= 1.0:
				dst.ignite()
		elif dst.heat > 0.0:
			dst.heat = maxf(0.0, dst.heat - HEAT_DECAY * delta)

	# Heat propagation to explosive barrels (SPEC Section 8.5)
	for b in barrels:
		if not is_instance_valid(b) or b.state != VoxelBarrel.State.UNBURNED:
			continue
		var b_power := 0.0
		for src in burning_nodes:
			var to_b := b.global_position - src.global_position
			var dist := to_b.length()
			if dist < 0.01:
				continue

			var inside_active_gust := false
			if active_gust_timer > 0.0:
				var to_dst: Vector3 = b.global_position - active_gust_origin
				to_dst.y = 0.0
				var dst_dist := to_dst.length()
				if dst_dist <= WIND_GUST_RANGE:
					var gust_align := (to_dst / maxf(0.01, dst_dist)).dot(active_gust_dir)
					if gust_align >= cos(WIND_GUST_HALF_ANGLE):
						inside_active_gust = true

			var max_dist := WIND_GUST_RANGE if inside_active_gust else HOUSE_CONDITIONAL_RADIUS
			if dist > max_dist:
				continue

			var align: float = (to_b / dist).dot(wind_dir)
			var w: float = maxf(0.2, 1.0 + align * wind_strength * WIND_BIAS)

			if not inside_active_gust and dist > HOUSE_CONNECTED_RADIUS:
				var falloff: float = 1.0 - (dist - HOUSE_CONNECTED_RADIUS) / (HOUSE_CONDITIONAL_RADIUS - HOUSE_CONNECTED_RADIUS)
				w *= maxf(0.0, falloff * (0.3 + align * 0.7))

			# Active Local Wind Gust acceleration
			if inside_active_gust:
				w *= 3.5

			b_power += maxf(0.0, w)
			if b_power >= 3.0:
				break

		if rain_active:
			b_power *= 0.45
		if b_power > 0.0:
			b.add_heat(b_power * delta * 0.35)


func count_burning() -> int:
	var n := 0
	for h in houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
			n += 1
	return n


func count_smoldering() -> int:
	var n := 0
	for h in houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.SMOLDERING:
			n += 1
	return n


func get_burning_nodes() -> Array[VoxelHouse]:
	var burning: Array[VoxelHouse] = []
	for h in houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
			burning.append(h)
	return burning


func get_wind_arrow() -> String:
	var ang := atan2(wind_dir.x, -wind_dir.z)
	var idx := int(round(ang / (TAU / 8.0))) % 8
	if idx < 0:
		idx += 8
	var arrows := ["\u2191 N", "\u2197 NE", "\u2192 E", "\u2198 SE", "\u2193 S", "\u2199 SW", "\u2190 W", "\u2196 NW"]
	return arrows[idx]


func get_wind_word() -> String:
	if wind_strength < 0.7:
		return "gentle"
	if wind_strength < 1.1:
		return "steady"
	return "strong"
