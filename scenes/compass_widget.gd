class_name CompassWidget
extends Control
## CompassWidget — Tactical 2D flight instrument for prevailing ambient wind & Local Wind Gust (SPEC Section 7.3).
## Features:
## - Rotating aerodynamic needle aligned to screen-space ambient wind direction.
## - Ghost target needle telegraphing shifting wind target before arrival.
## - Cardinal tick marks (N, E, S, W) rotated to true screen bearings for the isometric camera.
## - Radial Local Wind Gust indicator (cooldown arc, active glowing arc, or ready status).
## - Wind intensity gauge ring.

var wind_angle: float = 0.0 # radians in 2D screen space
var target_wind_angle: float = 0.0
var wind_strength: float = 1.0

var north_angle: float = 0.0
var east_angle: float = 0.0
var south_angle: float = 0.0
var west_angle: float = 0.0

var gust_state: String = "ready" # "ready" | "cooldown" | "active"
var gust_cooldown_left: float = 0.0
var gust_cooldown_max: float = 6.0
var gust_active_left: float = 0.0
var gust_active_max: float = 4.0


func _init() -> void:
	custom_minimum_size = Vector2(48, 48)
	mouse_filter = MOUSE_FILTER_IGNORE


func update_wind(p_wind_angle: float, p_target_angle: float, p_strength: float, p_cam_basis: Basis) -> void:
	wind_angle = p_wind_angle
	target_wind_angle = p_target_angle
	wind_strength = p_strength

	# Project world cardinal directions (N = -Z, E = +X, S = +Z, W = -X) onto screen
	north_angle = _project_screen_angle(Vector3(0, 0, -1), p_cam_basis)
	east_angle = _project_screen_angle(Vector3(1, 0, 0), p_cam_basis)
	south_angle = _project_screen_angle(Vector3(0, 0, 1), p_cam_basis)
	west_angle = _project_screen_angle(Vector3(-1, 0, 0), p_cam_basis)

	queue_redraw()


func update_gust(state_name: String, cd_left: float, cd_max: float, active_left: float, active_max: float) -> void:
	gust_state = state_name
	gust_cooldown_left = cd_left
	gust_cooldown_max = cd_max
	gust_active_left = active_left
	gust_active_max = active_max
	queue_redraw()


func _project_screen_angle(world_vec: Vector3, cam_basis: Basis) -> float:
	var sx := world_vec.dot(cam_basis.x)
	var sy := -world_vec.dot(cam_basis.y)
	return atan2(sy, sx)


func _draw() -> void:
	var center := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 3.0

	# 1. Dark circular backing
	draw_circle(center, r, Color(0.08, 0.10, 0.14, 0.92))

	# 2. Outer compass bezel ring
	draw_arc(center, r, 0, TAU, 36, Color(0.35, 0.44, 0.56, 0.85), 2.0)
	draw_arc(center, r * 0.82, 0, TAU, 32, Color(0.2, 0.26, 0.36, 0.4), 1.0)

	# 3. Cardinal indicators (N, E, S, W)
	var font := get_theme_default_font()
	var font_sz := 9
	var cardinals := [
		{"text": "N", "ang": north_angle, "col": Color(1.0, 0.85, 0.3)},
		{"text": "E", "ang": east_angle, "col": Color(0.75, 0.85, 0.95)},
		{"text": "S", "ang": south_angle, "col": Color(0.75, 0.85, 0.95)},
		{"text": "W", "ang": west_angle, "col": Color(0.75, 0.85, 0.95)}
	]
	for c in cardinals:
		var ca: float = c["ang"]
		var c_pos := center + Vector2(cos(ca), sin(ca)) * (r - 7.5)
		var t_out := center + Vector2(cos(ca), sin(ca)) * r
		var t_in := center + Vector2(cos(ca), sin(ca)) * (r - 3.5)
		draw_line(t_in, t_out, c["col"], 1.5)
		draw_string(font, c_pos + Vector2(-3, 3.5), c["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, font_sz, c["col"])

	# 4. Local Gust Status Arc on the outer bezel
	if gust_state == "active":
		var pulse := 0.7 + 0.3 * sin(float(Time.get_ticks_msec()) * 0.014)
		var gust_col := Color(1.0, 0.55, 0.1, pulse)
		draw_arc(center, r + 1.0, 0, TAU, 36, gust_col, 3.5)
	elif gust_state == "cooldown":
		var frac := clampf(gust_cooldown_left / maxf(0.01, gust_cooldown_max), 0.0, 1.0)
		var start_a := -PI * 0.5
		var sweep := (1.0 - frac) * TAU
		draw_arc(center, r + 1.0, start_a, start_a + sweep, 32, Color(0.3, 0.75, 1.0, 0.85), 2.5)
		draw_arc(center, r + 1.0, start_a + sweep, start_a + TAU, 32, Color(0.75, 0.2, 0.15, 0.5), 2.5)
	else:
		draw_arc(center, r + 1.0, 0, TAU, 36, Color(1.0, 0.85, 0.25, 0.6), 2.0)

	# 5. Shifting Target Ghost Needle
	var ang_diff := absf(fposmod(target_wind_angle - wind_angle + PI, TAU) - PI)
	if ang_diff > 0.08:
		var ghost_len := r * 0.72
		var ghost_tip := center + Vector2(cos(target_wind_angle), sin(target_wind_angle)) * ghost_len
		var ghost_col := Color(0.3, 0.85, 1.0, 0.38)
		draw_line(center, ghost_tip, ghost_col, 2.0)
		var g_side := Vector2(-sin(target_wind_angle), cos(target_wind_angle)) * 3.5
		var g_left := ghost_tip - Vector2(cos(target_wind_angle), sin(target_wind_angle)) * 6.0 + g_side
		var g_right := ghost_tip - Vector2(cos(target_wind_angle), sin(target_wind_angle)) * 6.0 - g_side
		draw_line(ghost_tip, g_left, ghost_col, 1.5)
		draw_line(ghost_tip, g_right, ghost_col, 1.5)

	# 6. Main Wind Arrow Needle
	var needle_len := r * clampf(0.65 + (wind_strength - 0.7) * 0.35, 0.55, 0.88)
	var needle_dir := Vector2(cos(wind_angle), sin(wind_angle))
	var needle_tip := center + needle_dir * needle_len
	var needle_norm := Vector2(-needle_dir.y, needle_dir.x)
	var w := 4.2

	# Forward arrow head (cyan/gold)
	var head_pts := PackedVector2Array([
		needle_tip,
		center + needle_norm * w,
		center - needle_norm * w
	])
	var head_col := Color(0.25, 0.9, 1.0) if gust_state != "active" else Color(1.0, 0.7, 0.2)
	draw_colored_polygon(head_pts, head_col)
	draw_polyline(head_pts, Color(1.0, 1.0, 1.0, 0.9), 1.0)

	# Backward tail feathers
	var tail_tip := center - needle_dir * (needle_len * 0.42)
	var tail_pts := PackedVector2Array([
		tail_tip,
		center + needle_norm * (w * 0.75),
		center - needle_norm * (w * 0.75)
	])
	draw_colored_polygon(tail_pts, Color(0.85, 0.3, 0.2, 0.85))

	# Center pivot pin
	draw_circle(center, 3.5, Color(0.95, 0.95, 1.0))
	draw_circle(center, 1.5, Color(0.1, 0.15, 0.2))
