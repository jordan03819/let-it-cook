class_name FireSimulation
extends RefCounted
## FireSimulation — Encapsulates heat propagation, wind dynamics, and spread (SPEC Section 19).
## Simulates accumulated ignition pressure between burning nodes, ambient wind shifts,
## active Wind Gust acceleration, wetness damping, and heat transfer to structures and barrels.

signal wind_shifted(new_dir: Vector3)

# Spatial tuning bands (SPEC Section 6.3)
# Connected: <= 5.4m, Conditional: 5.4m–7.6m, Broken: > 7.6m (crossable by Wind
# Gust up to 10.5m). Widened from 4.2/6.0/8.5: a village laid out along lanes
# leaves longer gaps than a grid, and the old bands made most of them untakeable.
const HOUSE_CONNECTED_RADIUS: float = 5.4
const HOUSE_CONDITIONAL_RADIUS: float = 7.6
const HOUSE_RADIUS: float = HOUSE_CONDITIONAL_RADIUS
const TREE_RADIUS: float = 5.6
const HOUSE_HEAT: float = 0.035
const TREE_HEAT: float = 0.13
const HEAT_DECAY: float = 0.025

const WIND_BIAS: float = 0.8
const WIND_SHIFT_MIN: float = 22.0
const WIND_SHIFT_MAX: float = 34.0

const WIND_GUST_DURATION: float = 4.0
const WIND_GUST_RANGE: float = 10.5
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

# Active directional heat connections between flame sources and unburned targets (SPEC Section 6.4)
var active_heat_links: Array[Dictionary] = []


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
	active_heat_links.clear()

	var burning_nodes: Array[VoxelHouse] = []
	for h in houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
			burning_nodes.append(h)

	if burning_nodes.is_empty():
		for h in houses:
			if is_instance_valid(h) and h.state == VoxelHouse.State.UNBURNED and h.heat > 0.0:
				h.heat = maxf(0.0, h.heat - HEAT_DECAY * delta)
		return

	# Apply ambient wind and local gust tilt to settlement houses, flames, and foliage (SPEC Section 7.3)
	for h in houses:
		if is_instance_valid(h):
			h.apply_ambient_wind(wind_dir, wind_strength)
			if active_gust_timer > 0.0:
				var to_h: Vector3 = h.global_position - active_gust_origin
				to_h.y = 0.0
				var d := to_h.length()
				if d <= WIND_GUST_RANGE + 1.0 and d > 0.01:
					var align := (to_h / d).dot(active_gust_dir)
					if align >= cos(WIND_GUST_HALF_ANGLE):
						h.apply_gust_tilt(active_gust_dir)

	for dst in houses:
		if not is_instance_valid(dst) or dst.state != VoxelHouse.State.UNBURNED or dst.kind == "stone":
			continue

		var rate := TREE_HEAT if dst.kind == "tree" else HOUSE_HEAT
		var power := 0.0
		var best_src: VoxelHouse = null
		var max_src_w := 0.0

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

			if w > max_src_w:
				max_src_w = w
				best_src = src

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
			if power >= 0.15 and best_src != null:
				active_heat_links.append({"src": best_src, "dst": dst, "power": power})
			if dst.heat >= 1.0:
				dst.ignite()
		elif dst.heat > 0.0:
			dst.heat = maxf(0.0, dst.heat - HEAT_DECAY * delta)

	# Heat propagation to explosive barrels (SPEC Section 8.5)
	for b in barrels:
		if not is_instance_valid(b) or b.state != VoxelBarrel.State.UNBURNED:
			continue
		var b_power := 0.0
		var best_b_src: VoxelHouse = null
		var max_b_w := 0.0

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

			if w > max_b_w:
				max_b_w = w
				best_b_src = src

			b_power += maxf(0.0, w)
			if b_power >= 3.0:
				break

		if rain_active:
			b_power *= 0.45
		if b_power > 0.0:
			b.add_heat(b_power * delta * 0.35)
			if b_power >= 0.15 and best_b_src != null:
				active_heat_links.append({"src": best_b_src, "dst": b, "power": b_power})


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


## Evaluates tactical spread certainty, gap category, and projected heat for a target (SPEC Section 6.4).
## Returns a structured dictionary for hover inspection and Wind Gust preview lines.
func evaluate_spread_state(target: Node3D, sim_gust_origin: Vector3 = Vector3.ZERO, sim_gust_dir: Vector3 = Vector3.FORWARD, sim_gust_active: bool = false, rain_active: bool = false) -> Dictionary:
	var result := {
		"status": "Blocked",
		"detail": "",
		"color": Color(0.7, 0.7, 0.7),
		"power": 0.0,
		"best_source": null,
		"will_ignite_in_gust": false,
		"distance": 999.0,
		"inside_cone": false
	}

	if target == null or not is_instance_valid(target):
		return result

	# 1. Shaman Objective (SPEC Section 9.4)
	if target is VoxelShaman:
		var s := target as VoxelShaman
		if s.state == VoxelShaman.State.DEAD:
			result.status = "Defeated"
			result.detail = "Ritualist defeated"
			result.color = Color(0.5, 0.5, 0.5)
		elif s.state == VoxelShaman.State.FLEEING:
			result.status = "Burning"
			result.detail = "Shaman torched & fleeing!"
			result.color = Color(1.0, 0.4, 0.1)
		elif s.state == VoxelShaman.State.CASTING:
			result.status = "Ritual"
			result.detail = "Summoning Rain (%.1fs) — Route fire to altar!" % s.cast_time_remaining
			result.color = Color(0.9, 0.35, 1.0)
		else:
			result.status = "Immune"
			result.detail = "Immune to direct clicks — Route fire to altar"
			result.color = Color(0.8, 0.5, 0.9)
		return result

	# 2. Explosive Barrels (SPEC Section 8.5)
	if target is VoxelBarrel:
		var b := target as VoxelBarrel
		if b.state == VoxelBarrel.State.EXPLODED:
			result.status = "Exploded"
			result.detail = "Barrel already detonated"
			result.color = Color(0.4, 0.4, 0.4)
			return result
		elif b.state == VoxelBarrel.State.PRIMED:
			result.status = "Primed"
			result.detail = "DETONATING in %.1fs!" % b.prime_timer
			result.color = Color(1.0, 0.2, 0.1)
			return result

	# 3. Structures (SPEC Section 6.4 & 8.1)
	if target is VoxelHouse:
		var h := target as VoxelHouse
		if h.kind == "stone":
			result.status = "Blocked"
			result.detail = "Stone structure is fireproof"
			result.color = Color(0.65, 0.65, 0.7)
			return result
		elif h.state == VoxelHouse.State.BURNT:
			result.status = "Burnt"
			result.detail = "Consumed by fire"
			result.color = Color(0.4, 0.4, 0.4)
			return result
		elif h.state == VoxelHouse.State.SMOLDERING:
			result.status = "Smoldering"
			result.detail = "Last Spark: %.1fs (Click to reignite: 1 Ember)" % h.smolder_timer
			result.color = Color(1.0, 0.45, 0.0)
			return result
		elif h.state == VoxelHouse.State.BURNING:
			result.status = "Burning"
			result.detail = "Active flame (Fuel: %ds)" % int(ceil(h.fuel))
			result.color = Color(1.0, 0.5, 0.1)
			return result

	# 4. Unburned combustible target (House, Tree, or Barrel)
	var is_barrel := target is VoxelBarrel
	var house_target := target as VoxelHouse if not is_barrel else null
	var cur_heat: float = house_target.heat if house_target != null else (target as VoxelBarrel).heat
	var cur_wetness: float = house_target.wetness if house_target != null else (target as VoxelBarrel).wetness
	var rate := TREE_HEAT if (house_target != null and house_target.kind == "tree") else (0.35 if is_barrel else HOUSE_HEAT)

	var burning_nodes: Array[VoxelHouse] = []
	for h in houses:
		if is_instance_valid(h) and h.state == VoxelHouse.State.BURNING:
			burning_nodes.append(h)

	if burning_nodes.is_empty():
		result.status = "Blocked"
		result.detail = "No active burning flame source"
		result.color = Color(0.7, 0.7, 0.7)
		return result

	var tgt_pos: Vector3 = target.global_position if target.is_inside_tree() else target.position

	var min_dist: float = 999.0
	var best_src: VoxelHouse = null
	var power: float = 0.0
	var inside_sim_gust := false

	if sim_gust_active:
		var to_tgt: Vector3 = tgt_pos - sim_gust_origin
		to_tgt.y = 0.0
		var tgt_d := to_tgt.length()
		if tgt_d <= WIND_GUST_RANGE and tgt_d > 0.05:
			var align := (to_tgt / tgt_d).dot(sim_gust_dir)
			if align >= cos(WIND_GUST_HALF_ANGLE):
				inside_sim_gust = true
	result.inside_cone = inside_sim_gust

	for src in burning_nodes:
		var src_pos: Vector3 = src.global_position if src.is_inside_tree() else src.position
		var to: Vector3 = tgt_pos - src_pos
		to.y = 0.0
		var dist := to.length()
		if dist < min_dist:
			min_dist = dist
			best_src = src

		var max_dist := WIND_GUST_RANGE if inside_sim_gust else (TREE_RADIUS if (house_target != null and house_target.kind == "tree") else HOUSE_CONDITIONAL_RADIUS)
		if dist > max_dist:
			continue

		var align: float = (to / maxf(0.01, dist)).dot(wind_dir)
		var w: float = maxf(0.2, 1.0 + align * wind_strength * WIND_BIAS)

		if not inside_sim_gust and dist > HOUSE_CONNECTED_RADIUS:
			var falloff: float = 1.0 - (dist - HOUSE_CONNECTED_RADIUS) / (HOUSE_CONDITIONAL_RADIUS - HOUSE_CONNECTED_RADIUS)
			w *= maxf(0.0, falloff * (0.3 + align * 0.7))

		if house_target != null and house_target.kind == "house" and src.kind == "tree":
			w *= 0.5

		if inside_sim_gust:
			w *= 3.5

		power += maxf(0.0, w)
		if power >= 3.5:
			break

	if cur_wetness > 0.05:
		power *= maxf(0.08, 1.0 - cur_wetness * 0.9)
	if rain_active:
		power *= 0.42

	result.power = power
	result.best_source = best_src
	result.distance = min_dist

	# Evaluate forecast under active/simulated Wind Gust
	if sim_gust_active:
		if inside_sim_gust:
			var gained_heat := rate * power * WIND_GUST_DURATION
			var projected_heat := cur_heat + gained_heat
			if cur_wetness >= 0.35 and projected_heat < 1.0:
				result.status = "Wet"
				result.detail = "Wet (%d%%) — Resists gust heat" % int(cur_wetness * 100)
				result.color = Color(0.25, 0.65, 1.0)
			elif projected_heat >= 1.0:
				result.status = "Likely"
				result.detail = "WILL IGNITE during Wind Gust!"
				result.color = Color(0.2, 1.0, 0.35)
				result.will_ignite_in_gust = true
			else:
				result.status = "Needs Heat"
				result.detail = "Gains +%d%% heat in gust (reaches %d%%)" % [int(gained_heat * 100), int(minf(99, projected_heat * 100))]
				result.color = Color(1.0, 0.75, 0.2)
		else:
			result.status = "Blocked"
			result.detail = "Outside wind gust cone"
			result.color = Color(0.65, 0.65, 0.65)
		return result

	# Ambient hover evaluation
	if cur_wetness >= 0.35:
		result.status = "Wet"
		if power >= 1.5:
			result.detail = "Wet (%d%%) — Slowly heating through water" % int(cur_wetness * 100)
		else:
			result.detail = "Wet (%d%%) — Resists ignition until dry" % int(cur_wetness * 100)
		result.color = Color(0.25, 0.65, 1.0)
		return result

	if cur_heat >= 0.8:
		result.status = "Likely"
		result.detail = "Scorching near ignition! (Heat: %d%%)" % int(cur_heat * 100)
		result.color = Color(0.2, 1.0, 0.35)
		return result

	if min_dist > WIND_GUST_RANGE:
		result.status = "Blocked"
		result.detail = "Too far from fire (%.1fm > 8.5m)" % min_dist
		result.color = Color(0.65, 0.65, 0.65)
	elif min_dist > HOUSE_CONDITIONAL_RADIUS:
		result.status = "Needs Wind"
		result.detail = "Broken gap (%.1fm) — Requires Wind Gust" % min_dist
		result.color = Color(0.3, 0.85, 1.0)
	elif min_dist > HOUSE_CONNECTED_RADIUS:
		if power >= 0.35:
			result.status = "Likely"
			result.detail = "Wind carrying fire across %.1fm gap (Heat: %d%%)" % [min_dist, int(cur_heat * 100)]
			result.color = Color(1.0, 0.85, 0.2)
		else:
			result.status = "Needs Wind"
			result.detail = "Conditional gap (%.1fm) — Needs favorable wind" % min_dist
			result.color = Color(0.3, 0.85, 1.0)
	else:
		if power > 0.05:
			result.status = "Likely"
			result.detail = "Connected gap (%.1fm) — Heating (%d%%)" % [min_dist, int(cur_heat * 100)]
			result.color = Color(0.2, 1.0, 0.35) if cur_heat > 0.4 else Color(1.0, 0.85, 0.2)
		else:
			result.status = "Needs Wind"
			result.detail = "Connected (%.1fm) — Opposed by ambient wind" % min_dist
			result.color = Color(0.3, 0.85, 1.0)

	return result
