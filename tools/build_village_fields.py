#!/usr/bin/env python3
"""
Generates scenes/levels/village_fields.tscn — the handcrafted "Village Fields"
level foundation for Let It Cook.

Pipeline note (dev tool, not shipped with the game):
  Re-run after editing the layout tables:
      python3 tools/build_village_fields.py

Scale convention
----------------
Kit models are 1 m objects whose bases sit at y = -0.05 (the importer bakes the
offset), so anything authored at y = 0 sits flush with the next model.

How the ground is built
-----------------------
Nothing structural is laid out as tiles any more — a 2 m tile grid is exactly
what made the village read as graph paper:

* Roads are polylines (PATH_LANES) emitted as `metadata/spine`; the level script
  draws each one as a ribbon mesh with a wobbling edge.
* The pond is parameters (centre, radius, seed) emitted as metadata; the script
  draws an organic polygon with a muddy shore ring.
* Hills are parameters; the script draws faceted mounds with a rock skirt.
* Building plots are hung off the roads (PLOT_ROWS: lane, stretch, side, setback)
  and relaxed apart so a 3 x 3 m house always fits; the script marks each one with
  a cleared pad and a few leftover stones.
* Kit models are still used for everything that is an object rather than a
  surface: trees, rocks, crops, fences, tents, statues, lilies.

The level inherits the campaign's own sky/sun/fog (it authors no environment), and
the level script remaps the kit's candy palette onto the campaign's colours.
"""

import math
import os
import zlib

TAU_PY = 6.283185307179586

TILE = 2.0                      # metres per design cell (grid pitch)
MODEL = 1.0                     # metres covered by one Nature Kit tile model
CELL = TILE / MODEL             # scale factor that stretches a 1 m model to a cell
Y = 0.0                         # nominal ground plane (prop bases sit at -0.05)
# The kit's tiles are designed to sit flush, so lane/water surfaces end up coplanar
# with the grass plate and z-fight against it. Offset the lawn down and the tile
# surfaces up by a few millimetres: visually flush, no flicker.
LAWN_Y = -0.03
PROP_Y = LAWN_Y                 # prop bases land exactly on the lawn surface
PATH_LIFT = 0.02                # lane plates ride ~5 cm above the lawn
GRAV = 0.0

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "scenes", "levels", "village_fields.tscn")

# ---------------------------------------------------------------- scene writer


class Scene:
    def __init__(self, root_name, root_type="Node3D", script=None):
        self.root_name = root_name
        self.root_type = root_type
        self.script = script
        self.ext = []            # (path, id)
        self.ext_ids = {}
        self.sub = []            # (id, [property lines], type)
        self.nodes = []          # (name, parent, type_or_instance, props, group)
        self.counts = {}

    def sub_shape(self, size, name="Shape"):
        sid = "Shape_%s_%d" % (name, len(self.sub))
        self.sub.append((sid, ["size = Vector3%s" % (size,)], "BoxShape3D"))
        return sid

    def ext_id(self, model):
        if model not in self.ext_ids:
            eid = "m_%s" % model
            self.ext_ids[model] = eid
            self.ext.append(("res://assets/nature/%s.glb" % model, eid))
        return self.ext_ids[model]

    def sub_box(self, size, colour, name="Box"):
        sid = "Box_%s_%d" % (name, len(self.sub))
        mat_id = "Mat_%s_%d" % (name, len(self.sub))
        self.sub.append((mat_id, ["albedo_color = Color%s" % colour], "StandardMaterial3D"))
        self.sub.append((sid, ["size = Vector3%s" % (size,), "material = SubResource(\"%s\")" % mat_id], "BoxMesh"))
        return sid

    def uniq(self, base):
        n = self.counts.get(base, 0)
        self.counts[base] = n + 1
        return base if n == 0 else "%s%d" % (base, n + 1)

    def node(self, name, parent, type_="Node3D", props=(), group=None, instance=None):
        self.nodes.append((name, parent, instance or type_, list(props), group))

    def tile(self, model, parent, x, z, y=PROP_Y, rot_y=0.0, cells=(1, 1), name=None):
        """Place one kit tile stretched to cover `cells` design cells (default 1x1 = TILE m)."""
        self.prop(model, parent, x, z, y=y, rot_y=rot_y,
                  scale=(cells[0] * CELL, 1.0, cells[1] * CELL), name=name)

    def prop(self, model, parent, x, z, y=PROP_Y, rot_y=0.0, scale=None, name=None, extra=()):
        """Place one Nature Kit model. rot_y in degrees."""
        eid = self.ext_id(model)
        props = ["transform = Transform3D(%s, %s)" % (
            _basis(rot_y, scale), _fmt3((x, y, z)))]
        props.extend(extra)
        self.node(name or self.uniq(model), parent, None, props, instance=eid)

    def write(self, path):
        lines = []
        script_id = None
        if self.script:
            script_id = "1_scene_script"
            load_steps = len(self.ext) + len(self.sub) + 2
        else:
            load_steps = len(self.ext) + len(self.sub) + 1
        lines.append("[gd_scene load_steps=%d format=3]" % load_steps)
        lines.append("")
        if script_id:
            lines.append('[ext_resource type="Script" path="%s" id="%s"]' % (self.script, script_id))
        for p, eid in self.ext:
            lines.append('[ext_resource type="PackedScene" path="%s" id="%s"]' % (p, eid))
        lines.append("")
        for sid, props, stype in self.sub:
            lines.append('[sub_resource type="%s" id="%s"]' % (stype, sid))
            for p in props:
                lines.append(p)
            lines.append("")
        root_props = []
        if script_id:
            root_props.append('script = ExtResource("%s")' % script_id)
        lines.append('[node name="%s" type="%s"]' % (self.root_name, self.root_type))
        for p in root_props:
            lines.append(p)
        for name, parent, type_or_inst, props, group in self.nodes:
            parent_attr = ' parent="%s"' % (parent if parent else ".")
            if type_or_inst in self.ext_ids.values():
                lines.append('[node name="%s"%s instance=ExtResource("%s")]' % (name, parent_attr, type_or_inst))
            else:
                lines.append('[node name="%s"%s type="%s"]' % (name, parent_attr, type_or_inst))
            if group:
                lines.append('groups = ["%s"]' % group)
            for p in props:
                lines.append(p)
            lines.append("")
        with open(path, "w") as f:
            f.write("\n".join(lines) + "\n")
        print("wrote %s (%d nodes, %d models, %d sub-resources)" % (
            path, len(self.nodes), len(self.ext), len(self.sub)))


def _fmt3(v):
    return "%.4f, %.4f, %.4f" % (v[0], v[1], v[2])


def _basis(rot_y_deg, scale=None):
    """Emit a Transform3D basis (as 9 numbers) for a Y rotation + uniform/non-uniform scale."""
    r = math.radians(rot_y_deg)
    c, s = math.cos(r), math.sin(r)
    sx, sy, sz = scale if scale else (1.0, 1.0, 1.0)
    # Godot: +Y rotation, basis columns = rotated axes
    return "%.6f, 0, %.6f, 0, %.6f, 0, %.6f, 0, %.6f" % (
        c * sx, -s * sx, sy, s * sz, c * sz)


# ---------------------------------------------------------------- layout tables
#
# Coordinates: x = east, z = south (north is -Z, matching the game camera).
# One continuous meadow: the village core sits around the green in the middle,
# the farmstead on the east side. All distances are metres.

# Lawn rectangle; the pond is cut out of it so grass never covers water.
LAWN = (-26.0, -26.0, 26.0, 26.0)

# Pond (west of the village, south-west corner). Centre + radii in metres.
POND = (-19.0, 13.0, 4.2, 3.4)     # cx, cz, rx, rz

# Little hills: (cx, cz, rx, rz, height)
HILLS = [
    (-19.0, -18.0, 6.5, 5.0, 1.0),   # orchard hill (north-west)
    (-21.5, -13.0, 3.5, 2.5, 0.5),   # spur
    (22.0, -18.5, 4.0, 3.0, 1.0),    # north-east rise (pines), clear of lanes
]

# ---------------------------------------------------------------- pond
# An irregular blob, not a rectangle: the shoreline is a wobbling radius so the
# water reads as something the land grew around rather than something drawn on it.
POND_C = (-19.0, 13.0)
POND_R = 5.0


# ---------------------------------------------------------------- deterministic
# Everything organic in this level is placed from a stable hash of its own name,
# never from RNG state: regenerating the scene is byte-for-byte reproducible and a
# single site can be nudged without shifting every other prop.
def _h01(key, salt=0):
    return (zlib.crc32(("%s|%d" % (key, salt)).encode("utf-8")) % 100000) / 100000.0

# ---------------------------------------------------------------- road network
# Roads are polylines in metres, NOT runs of axis-aligned 2 m cells: the generator
# lays kit tiles along each curve at a fixed step, turned to the local tangent, so
# a lane bends where the polyline bends. Move a point here and the lane, its
# verges and the plots that front it all follow.
#
# side below: -1 = left of travel, +1 = right of travel.

PATH_LANES = {
    # the street: enters west, wanders past the green and out to the farm
    "MainRoad": [(-26.0, 5.0), (-16.0, 5.8), (-6.0, 4.6), (4.0, 5.4), (14.0, 4.4),
                 (22.0, 5.0), (26.0, 4.8)],
    # the north loop: leaves the street, wanders round the north, comes back
    "NorthLoop": [(-4.0, 5.4), (-4.8, -3.0), (0.0, -9.5), (6.0, -12.5), (12.0, -11.0),
                  (16.0, -5.0), (15.0, 1.0), (14.0, 4.6)],
    # hill lane: north-west out of the loop, below the orchard hill
    "HillLane": [(-4.8, -3.0), (-9.5, -5.5), (-13.5, -9.5), (-16.5, -13.0)],
    # pond lane: south out of the street, past the pond to the old shrine
    "PondLane": [(-9.5, 4.6), (-10.6, 9.0), (-10.2, 14.0), (-13.0, 18.5), (-18.0, 21.5)],
    # camp track: off the loop into the north-east woods
    "CampTrack": [(6.0, -12.5), (4.0, -16.5), (6.5, -19.5)],
    # farm track: off the street into the fields
    "FarmTrack": [(22.0, 5.0), (24.0, 9.5), (23.0, 14.5), (20.0, 18.0)],
}

PATH_WOOD = {
    "PondDock": [(-12.4, 10.0), (-15.4, 10.6)],
    "CampPlanks": [(1.4, -17.2), (3.2, -18.6)],
    "FarmYard": [(23.6, 8.4), (22.2, 10.2)],
}

LANE_HALF_WIDTH = 1.05        # metres of dirt either side of the centre line


def _poly_length(poly):
    return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(poly, poly[1:]))


def _poly_at(poly, s):
    """Point at distance `s` along a polyline plus the tangent angle in degrees,
    in Godot's Y-rotation convention (the model's +X axis follows the tangent)."""
    for idx, (a, b) in enumerate(zip(poly, poly[1:])):
        seg = math.hypot(b[0] - a[0], b[1] - a[1])
        if s <= seg or idx == len(poly) - 2:
            t = 0.0 if seg <= 0.0 else max(0.0, min(1.0, s / seg))
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t,
                    math.degrees(math.atan2(-(b[1] - a[1]), b[0] - a[0])))
        s -= seg
    return poly[-1][0], poly[-1][1], 0.0


def _poly_dist(x, z, poly):
    """Distance from a point to the nearest point of a polyline."""
    best = 1e9
    for a, b in zip(poly, poly[1:]):
        dx, dz = b[0] - a[0], b[1] - a[1]
        l2 = dx * dx + dz * dz
        t = 0.0 if l2 <= 0.0 else max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[1]) * dz) / l2))
        best = min(best, math.hypot(x - (a[0] + dx * t), z - (a[1] + dz * t)))
    return best


# ---------------------------------------------------------------- house plots
# Plots hang off the roads rather than sitting on a lattice: a row names the lane
# it fronts, how far along that lane it runs, which side, how far back from the
# verge. Rows therefore bend with their road and never line up across the village.
# (prefix, cluster, lane, t0, t1, count, side, setback, role)
PLOT_ROWS = [
    ("A", "green_west", "MainRoad", 0.04, 0.26, 4, -1, 3.4, "starter"),
    ("B", "green_east", "MainRoad", 0.30, 0.52, 4, -1, 3.6, "mandatory"),
    ("G", "farm_lane", "MainRoad", 0.62, 0.94, 5, -1, 3.5, "mandatory"),
    ("C", "north_row", "NorthLoop", 0.10, 0.34, 4, -1, 3.3, "mandatory"),
    ("D", "hill_orchard", "HillLane", 0.12, 0.90, 4, -1, 3.4, "mandatory"),
    ("E", "pond_cottages", "PondLane", 0.16, 0.64, 4, 1, 2.9, "mandatory"),
    ("F", "east_farm", "FarmTrack", 0.06, 0.62, 4, 1, 3.2, "mandatory"),
]


def _lane_facing(poly, x, z):
    """Rotation that turns a building front from (x, z) towards the nearest point
    of its lane: every house faces the road it belongs to, whatever the row did."""
    best = (1e9, 0.0, 0.0)
    for a, b in zip(poly, poly[1:]):
        dx, dz = b[0] - a[0], b[1] - a[1]
        l2 = dx * dx + dz * dz
        t = 0.0 if l2 <= 0.0 else max(0.0, min(1.0, ((x - a[0]) * dx + (z - a[1]) * dz) / l2))
        px, pz = a[0] + dx * t, a[1] + dz * t
        d = math.hypot(x - px, z - pz)
        if d < best[0]:
            best = (d, px - x, pz - z)
    return math.degrees(math.atan2(-best[2], best[1])) % 360.0


def _relax(points, min_gap, iterations=80):
    """Push sites apart until every pair is at least `min_gap` apart, so a 3.2 m
    house always fits on its plot. The row table says roughly where plots belong;
    this only nudges them off each other."""
    pts = [list(p) for p in points]
    for _ in range(iterations):
        moved = False
        for i in range(len(pts)):
            for j in range(i + 1, len(pts)):
                dx, dz = pts[j][0] - pts[i][0], pts[j][1] - pts[i][1]
                d = math.hypot(dx, dz)
                if d >= min_gap or d <= 1e-6:
                    continue
                push = (min_gap - d) * 0.5
                ux, uz = dx / d, dz / d
                pts[i][0] -= ux * push
                pts[i][1] -= uz * push
                pts[j][0] += ux * push
                pts[j][1] += uz * push
                moved = True
        if not moved:
            break
    return pts


def build_plots():
    """Turn the row table into concrete sites: (name, x, z, y, facing, cluster, role)."""
    out = []
    for prefix, cluster, lane, t0, t1, count, side, setback, role in PLOT_ROWS:
        poly = PATH_LANES[lane]
        length = _poly_length(poly)
        for k in range(count):
            t = t0 + (t1 - t0) * (k / (count - 1) if count > 1 else 0.0)
            s = length * t + (_h01(cluster, k) - 0.5) * 0.8
            x, z, _ang = _poly_at(poly, max(0.0, min(length, s)))
            # offset square to the lane's *average* direction over the row, not the
            # local tangent: on the inside of a bend the local tangent piles plots up
            a = _poly_at(poly, max(0.0, s - 4.0))
            b = _poly_at(poly, min(length, s + 4.0))
            ang = math.degrees(math.atan2(-(b[1] - a[1]), b[0] - a[0]))
            back = setback + (_h01(cluster + "b", k) - 0.5) * 0.8
            rad = math.radians(ang)
            out.append([x + math.sin(rad) * back * side, z + math.cos(rad) * back * side,
                        cluster, lane, role, prefix, k])
    pts = _relax([(p[0], p[1]) for p in out], 3.6)
    sites = []
    for (px, pz), entry in zip(pts, out):
        cluster, lane, role, prefix, k = entry[2], entry[3], entry[4], entry[5], entry[6]
        facing = _lane_facing(PATH_LANES[lane], px, pz)
        sites.append(("%s%d" % (prefix, k + 1), px, pz, 0.0, facing, cluster,
                      role if k == 0 else ("mandatory" if role == "starter" else role)))
    return sites


PLOTS = build_plots()

# Water source marker points (bucket brigade targets) — pond rim + village well
WATER_POINTS = [
    ("Well", -4.2, 1.2),
]


# ---------------------------------------------------------------- helpers


# Tile rotations (deg) for each opening set, measured from the GLB vertex data.
# straight: opens N+S at 0            corner: opens S+E at 0, advances with +90
STRAIGHT_ROT = {"NS": 0.0, "EW": 90.0}
CORNER_ROT = {frozenset("SE"): 0.0, frozenset("EN"): 90.0,
              frozenset("NW"): 180.0, frozenset("WS"): 270.0}


def _on_path(x, z, margin=0.0):
    """True when a world position is close enough to a road to be kept clear."""
    for poly in PATH_LANES.values():
        if _poly_dist(x, z, poly) <= LANE_HALF_WIDTH + 0.6 + margin:
            return True
    for poly in PATH_WOOD.values():
        if _poly_dist(x, z, poly) <= 1.1 + margin:
            return True
    return False


def emit_paths(scene):
    """Roads are handed to the level script as spines, not laid out as tiles: it
    draws each one as a wobbly-edged ribbon mesh, so a lane follows its curve and
    never shows the tile grid. Edit the polylines above; nothing here to tune."""
    scene.node("Roads", "", "Node3D")
    for name, poly in PATH_LANES.items():
        flat = []
        for x, z in poly:
            flat.extend([x, z])
        scene.node(name, "Roads", "Node3D",
                   ["metadata/spine = PackedVector3Array(%s)" % _fmt_flat(poly),
                    "metadata/half_width = %.2f" % LANE_HALF_WIDTH,
                    'metadata/kind = "dirt"',
                    "metadata/seed = %.3f" % (_h01("seed" + name) * 10.0)])
    for name, poly in PATH_WOOD.items():
        scene.node(name, "Roads", "Node3D",
                   ["metadata/spine = PackedVector3Array(%s)" % _fmt_flat(poly),
                    "metadata/half_width = 0.9",
                    'metadata/kind = "wood"',
                    "metadata/seed = %.3f" % (_h01("seed" + name) * 10.0)])


def _fmt_flat(poly):
    """A polyline as the flat, comma-separated x, z pairs PackedVector3Array wants
    (the y component is always 0: every lane sits on the meadow)."""
    vals = []
    for x, z in poly:
        vals.append("%.3f, 0, %.3f" % (x, z))
    return ", ".join(vals)


def emit_water(scene):
    """The pond is an organic polygon the level script draws from these parameters,
    with its own wobbly shoreline — there are no water tiles anywhere."""
    scene.node("Water", "", "Node3D")
    scene.node("Pond", "Water", "Node3D",
               ["metadata/centre = Vector2(%.2f, %.2f)" % (POND_C[0], POND_C[1]),
                "metadata/radius = %.2f" % POND_R,
                "metadata/seed = %.3f" % (_h01("pondseed") * 10.0)])
    scene.node("WaterPoints", "Water", "Node3D")


def emit_lawn(scene):
    """One meadow plane; the pond blob is layered on top of it, so grass never
    needs cutting into rectangles. The rects returned here are the *collision*
    footprint: the meadow with the pond's bounding box left open."""
    span = POND_R * 1.45
    wx0, wz0, wx1, wz1 = LAWN
    # the pond reaches the west edge of the meadow, so clamp its collision box
    px0 = max(wx0, POND_C[0] - span)
    px1 = min(wx1, POND_C[0] + span)
    pz0 = max(wz0, POND_C[1] - span)
    pz1 = min(wz1, POND_C[1] + span)
    rects = [
        (wx0, wz0, wx1, pz0),        # north of pond
        (wx0, pz1, wx1, wz1),        # south of pond
        (wx0, pz0, px0, pz1),        # west of pond
        (px1, pz0, wx1, pz1),        # east of pond
    ]
    scene.node("Lawn", "Terrain", "Node3D")
    scene.prop("ground_grass", "Terrain/Lawn", (wx0 + wx1) * 0.5, (wz0 + wz1) * 0.5,
               y=LAWN_Y, scale=((wx1 - wx0) / MODEL, 1.0, (wz1 - wz0) / MODEL),
               name="Meadow")
    return rects


def emit_hills(scene):
    """Little hills are low-poly mounds drawn by the level script: rounded, faceted,
    with a stone skirt and a grass top. Nothing here follows the tile grid."""
    scene.node("Hills", "Terrain", "Node3D")
    for idx, (cx, cz, rx, rz, height) in enumerate(HILLS):
        scene.node("Hill%d" % idx, "Terrain/Hills", "Node3D",
                   ["metadata/centre = Vector2(%.2f, %.2f)" % (cx, cz),
                    "metadata/radii = Vector2(%.2f, %.2f)" % (rx, rz),
                    "metadata/height = %.2f" % height,
                    "metadata/seed = %.3f" % (_h01("hillseed", idx) * 10.0)])


def emit_underlay(scene):
    """Dark soil slab under the whole map: gaps read as earth, never as void."""
    scene.node("Underlay", "Terrain", "Node3D")
    slab = scene.sub_box((58.0, 0.4, 54.0), "(0.26, 0.20, 0.15, 1)", "Soil")
    scene.node("SoilSlab", "Terrain/Underlay", "MeshInstance3D",
               ["mesh = SubResource(\"%s\")" % slab,
                "position = Vector3(%s)" % _fmt3((0.0, -0.55, 0.0))])


def emit_collision(scene, land_rects):
    """Meadow collision in four big slabs around the pond, plus one wading bed
    under the pond itself, so nothing follows the tile grid."""
    scene.node("Collision", "", "StaticBody3D")
    for idx, (x0, z0, x1, z1) in enumerate(land_rects):
        if x1 - x0 < 0.1 or z1 - z0 < 0.1:
            continue
        shape = scene.sub_shape((x1 - x0, 2.0, z1 - z0), "Land")
        scene.node("Land%d" % idx, "Collision", "CollisionShape3D",
                   ["shape = SubResource(\"%s\")" % shape,
                    "position = Vector3(%s)" % _fmt3(((x0 + x1) * 0.5, -1.0, (z0 + z1) * 0.5))])
    # pond floor: one bed under the whole outline so characters wade
    shape = scene.sub_shape((POND_R * 2.9, 2.0, POND_R * 2.9), "Pond")
    scene.node("PondBed", "Collision", "CollisionShape3D",
               ["shape = SubResource(\"%s\")" % shape,
                "position = Vector3(%s)" % _fmt3((POND_C[0], -1.45, POND_C[1]))])


def emit_atmosphere(scene):
    """No authored environment: the level deliberately inherits the campaign's
    base sky/sun/fog so it reads as the same world as the procedural levels.
    `game.gd` restores its own Environment when the level provides none."""
    return


def emit_plots(scene):
    """Reserved building sites: a cleared footprint with a low stone kerb, so a
    plot reads as "a house goes here" without carpeting the meadow in brown.
    Some plots keep only part of their kerb: an old foundation, not a stamp."""
    scene.node("HousePlots", "", "Node3D")
    scene.node("Sites", "HousePlots", "Node3D")
    kerb = scene.sub_box((1.0, 0.05, 1.0), "(0.46, 0.45, 0.41, 1)", "Kerb")
    earth = scene.sub_box((1.0, 0.03, 1.0), "(0.53, 0.48, 0.34, 1)", "Earth")
    for name, x, z, y, facing, cluster, role in PLOTS:
        half = 1.45 + _h01(name, 13) * 0.35
        scene.node(name, "HousePlots", "Node3D",
                   ["position = Vector3(%s)" % _fmt3((x, PROP_Y + y, z)),
                    "rotation = Vector3(0, %.4f, 0)" % math.radians(facing),
                    'metadata/cluster = "%s"' % cluster,
                    'metadata/role = "%s"' % role,
                    'metadata/size = Vector3(3.2, 3.2, 3.2)'])
        if _h01(name, 14) < 0.6:
            scene.node("Pad_%s" % name, "HousePlots/Sites", "MeshInstance3D",
                       ["mesh = SubResource(\"%s\")" % earth,
                        "transform = Transform3D(%s, %s)" % (
                            _basis(facing, (half * 1.85, 1.0, half * 1.85)),
                            _fmt3((x, PROP_Y + y + 0.002, z)))])
        # No kerb frame: a frame of straight bars turns the village into a grid.
        # A plot reads as cleared ground (the pad) with a few stones and stumps
        # left at its edge, which is both quieter and more like a real plot.
        rad = math.radians(facing)
        cos_f, sin_f = math.cos(rad), math.sin(rad)
        for k, model in enumerate(["rock_smallB", "stump_round", "stone_largeC", "rock_smallD"]):
            if _h01(name, 20 + k) < 0.42:
                continue
            var_ang = _h01(name, 30 + k) * TAU_PY
            r = half + 0.5 + _h01(name, 40 + k) * 0.7
            ox, oz = math.cos(var_ang) * r, math.sin(var_ang) * r
            scene.prop(model, "HousePlots/Sites",
                       x + ox * cos_f + oz * sin_f, z - ox * sin_f + oz * cos_f,
                       rot_y=_h01(name, 50 + k) * 360.0,
                       scale=(0.8 + _h01(name, 60 + k) * 0.4,) * 3,
                       name="Site%d_%s" % (k, name))


# ---------------------------------------------------------------- dressing

def emit_fences(scene):
    """Fences read as property lines: pasture, garden, pond edge, field boundary.
    Runs follow whatever angle they need to; posts are skipped where a road or a
    reserved plot crosses."""
    scene.node("Fences", "", "Node3D")
    lines = [
        ("PastureW", [(-2.2, -1.4), (-3.0, -6.0)]),
        ("PastureN", [(-3.0, -6.0), (2.8, -9.4)]),
        ("GardenW", [(-16.6, 6.0), (-16.6, 10.4)]),
        ("GardenN", [(-16.6, 6.0), (-13.4, 6.0)]),
        ("PondN", [(-22.6, 8.6), (-19.8, 9.0)]),
        ("FieldW", [(20.6, 9.2), (20.6, 18.4)]),
        ("FieldN", [(20.6, 9.2), (23.2, 8.6)]),
        ("FieldS", [(20.6, 18.4), (23.4, 18.0)]),
        ("FieldE", [(23.2, 8.6), (23.4, 18.0)]),
    ]
    for name, pts in lines:
        _fence_line(scene, "Fences", name, pts)


def _fence_line(scene, parent, name, pts):
    """Fence run: a post every metre along the segment, turned to its tangent."""
    scene.node(name, parent, "Node3D")
    poly = list(pts)
    length = _poly_length(poly)
    steps = max(1, int(round(length)))
    for step in range(steps + 1):
        t = step / steps
        x, z, ang = _poly_at(poly, t * length)
        if _on_path(x, z) or _near_plot_pt(x, z, 2.0):
            continue
        at_corner = step == steps and len(poly) > 2
        scene.prop("fence_corner" if at_corner else "fence_simple", "%s/%s" % (parent, name),
                   x, z, rot_y=ang + (_h01(name, step) - 0.5) * 6.0,
                   name="%s_%d" % (name, step))


def emit_trees(scene):
    """Woodland grows in clumps, not rows: a thinning ring of woodland around the
    meadow (with a gap where each lane leaves the map) and loose stands inside it.
    Species, height, turn and spacing all come from the site's own hash."""
    scene.node("Trees", "Terrain", "Node3D")
    species = ["tree_default", "tree_oak", "tree_pineTallA", "tree_pineTallB",
               "tree_small", "tree_thin", "tree_blocks"]

    def _stand(parent, key, x, z, count, spread, base_y=PROP_Y):
        for k in range(count):
            ang = _h01(key + "a", k) * math.tau
            rad = _h01(key + "r", k) * spread
            sx, sz = x + math.cos(ang) * rad, z + math.sin(ang) * rad
            if _on_path(sx, sz) or _near_plot_pt(sx, sz):
                continue
            s = 0.95 + _h01(key + "s", k) * 0.75
            scene.prop(species[int(_h01(key + "sp", k) * len(species)) % len(species)],
                       parent, sx, sz, y=base_y, rot_y=_h01(key + "t", k) * 360.0,
                       scale=(s, s, s), name="%s_%d" % (key, k))

    # woodland ring: the offset from the boundary wobbles, and the ring thins out
    # in places, so the edge of the map never reads as a straight line of trees
    steps = [(-26.0 + i * 1.8) for i in range(30)]
    for idx, t in enumerate(steps):
        wob_n = 1.2 + 1.8 * _h01("belt", idx)
        wob_s = 1.2 + 1.8 * _h01("belt", idx + 100)
        wob_w = 1.2 + 1.8 * _h01("belt", idx + 200)
        wob_e = 1.2 + 1.8 * _h01("belt", idx + 300)
        ring = [(t, -26.0 + wob_n), (t, 26.0 - wob_s),
                (-26.0 + wob_w, t), (26.0 - wob_e, t)]
        for side, (x, z) in enumerate(ring):
            # leave the lane ends and the camp track open
            if abs(z - 2.0) < 3.4 and (x < -20.0 or x > 17.0):
                continue
            if abs(x - 20.0) < 3.0 and z < -10.0:
                continue
            if _h01("beltd", idx * 4 + side) < 0.12:
                continue
            _stand("Terrain/Trees", "Belt%d_%d" % (idx, side), x, z,
                   2 + int(_h01("beltn", idx * 4 + side) * 3), 2.2)

    # loose stands inside the meadow: copse, spinney, a few singles by the lanes
    for ci, (cx, cz, count, spread) in enumerate([
            (-15.5, -8.0, 5, 2.6), (-10.5, -14.5, 4, 2.2), (5.5, -9.5, 4, 2.4),
            (9.0, -3.5, 2, 1.6), (-4.0, 9.5, 4, 2.4), (3.0, 7.5, 5, 2.8),
            (13.5, -8.0, 4, 2.4), (-22.5, 4.5, 3, 2.2), (17.0, 12.0, 3, 2.4),
            (-13.0, 20.0, 4, 2.6), (7.0, 18.0, 4, 2.6), (-2.5, -6.0, 2, 1.5),
            (24.0, 12.0, 3, 2.2), (-24.0, -6.0, 3, 2.0)]):
        _stand("Terrain/Trees", "Stand%d" % ci, cx, cz, count, spread)

    # pines standing on the north-east rise: planted at hill-top height so the
    # rise reads as a wooded knoll instead of a bare stone wall
    rise = [(20.5, -19.6), (22.4, -18.2), (24.0, -19.2),
            (23.2, -16.4), (20.2, -17.0), (25.0, -17.6)]
    for i, (x, z) in enumerate(rise):
        scene.prop(["tree_pineTallA", "tree_pineTallB", "tree_default"][i % 3],
                   "Terrain/Trees", x, z, y=PROP_Y + 1.0, rot_y=_h01("rise", i) * 360.0,
                   scale=(0.9 + _h01("rises", i) * 0.4,) * 3, name="RisePine%d" % i)
    # orchard on the north-west hill: a planted grid, the one place a grid belongs
    for row in range(3):
        for col in range(3):
            scene.prop("tree_oak", "Terrain/Trees",
                       -21.5 + col * 2.6 + (_h01("orx", row * 3 + col) - 0.5) * 0.5,
                       -20.0 + row * 2.6 + (_h01("orz", row * 3 + col) - 0.5) * 0.5,
                       y=PROP_Y + 1.0,
                       rot_y=_h01("ort", row * 3 + col) * 360.0,
                       scale=(0.9 + _h01("ors", row * 3 + col) * 0.25,) * 3,
                       name="Orchard%d_%d" % (row, col))


def _near_plot_pt(x, z, radius=2.4):
    """True when a position is close enough to a reserved plot to stay clear of it."""
    for name, px, pz, _y, _f, _cluster, _role in PLOTS:
        if abs(px - x) < radius and abs(pz - z) < radius:
            return True
    return False


def emit_crops(scene):
    """Fields and kitchen gardens: parallel ploughed strips with meadow between
    them, planted unevenly, so a field reads as a field and not as a brown mat."""
    scene.node("Crops", "", "Node3D")
    # (name, x0, z0, strip length, strip count, crop)
    jobs = [
        ("FieldA", 21.5, 6.5, 3.0, 5, "crops_cornStageD"),
        ("FieldB", 21.5, 16.0, 3.0, 2, "crops_wheatStageB"),
        ("Garden", -17.6, 5.6, 2.0, 3, "crop_carrot"),
    ]
    for name, x0, z0, length, strips, crop in jobs:
        scene.node(name, "Crops", "Node3D")
        for r in range(strips):
            z = z0 + r * 2.0
            scene.tile("crops_dirtRow", "Crops/" + name, x0 + length * 0.5, z,
                       y=PATH_LIFT + 0.002,
                       rot_y=(_h01("strip" + name, r) - 0.5) * 4.0,
                       cells=(length * 0.5, 0.5), name="Strip_%s_%d" % (name, r))
            for c in range(int(length * 2) + 1):
                key = "%s_%d_%d" % (name, r, c)
                if _h01("crop" + key) < 0.34:
                    continue
                scene.prop(crop, "Crops/" + name,
                           x0 + c * 0.5 + (_h01("cx" + key) - 0.5) * 0.35,
                           z + (_h01("cz" + key) - 0.5) * 0.35,
                           y=PATH_LIFT + 0.002,
                           rot_y=_h01("cr" + key) * 360.0,
                           scale=(0.85 + _h01("cs" + key) * 0.3,) * 3,
                           name="Crop_%s" % key)

    # melon / pumpkin patch beside the garden
    for i, (x, z, m) in enumerate([(-16.4, 10.2, "crop_melon"), (-15.6, 10.4, "crop_pumpkin"),
                                    (-16.0, 11.0, "crop_turnip")]):
        scene.prop(m, "Crops", x, z, rot_y=i * 40, name="Patch%d" % i)


def emit_details(scene):
    """Wooden overlays, the camp, the shrine, pond life."""
    scene.node("Details", "", "Node3D")
    # village green furniture
    scene.prop("sign", "Details", -8.4, 1.4, rot_y=20, name="VillageSign")
    scene.prop("pot_large", "Details", -6.6, 3.4, name="GreenPot")
    scene.prop("campfire_bricks", "Details", -7.4, -0.4, name="GreenFire")
    scene.prop("log", "Details", -6.0, -0.8, rot_y=35, name="GreenLog")
    scene.prop("statue_ring", "Details", -8.0, 2.0, name="Well")
    scene.prop("log", "Details", -8.0, 2.0, y=PROP_Y + 0.42, rot_y=90, name="WellBeam")
    # logging / camp in the north-east woods
    scene.node("Camp", "Details", "Node3D")
    scene.prop("tent_detailedClosed", "Details/Camp", 5.0, -16.2, rot_y=200, name="TentA")
    scene.prop("tent_smallOpen", "Details/Camp", 7.6, -17.0, rot_y=150, name="TentB")
    scene.prop("campfire_logs", "Details/Camp", 6.4, -15.4, name="CampFire")
    scene.prop("log_stack", "Details/Camp", 4.2, -17.4, rot_y=25, name="StackA")
    scene.prop("log_stackLarge", "Details/Camp", 8.6, -15.2, rot_y=75, name="StackB")
    scene.prop("stump_round", "Details/Camp", 3.2, -15.6, name="StumpA")
    scene.prop("stump_square", "Details/Camp", 9.4, -16.6, rot_y=40, name="StumpB")
    scene.prop("axe" if False else "log_large", "Details/Camp", 5.6, -18.2, rot_y=15, name="LogBig")
    # old shrine south of the pond (stone: reads as non-flammable)
    scene.node("Shrine", "Details", "Node3D")
    scene.prop("statue_ring", "Details/Shrine", -16.0, 18.4, name="Ring")
    scene.prop("statue_columnDamaged", "Details/Shrine", -16.6, 19.2, rot_y=25, name="Column")
    scene.prop("statue_obelisk", "Details/Shrine", -15.2, 19.4, rot_y=-15, name="Obelisk")
    scene.prop("statue_head", "Details/Shrine", -17.2, 18.0, rot_y=60, name="Head")
    for i, (x, z) in enumerate([(-14.6, 18.2), (-17.4, 19.6), (-16.0, 20.4), (-14.2, 19.6)]):
        scene.prop("stone_largeB", "Details/Shrine", x, z, rot_y=i * 45, name="Stone%d" % i)
    scene.prop("hanging_moss", "Details/Shrine", -16.0, 18.4, y=PROP_Y + 0.8, name="Moss")
    # pond life
    scene.node("PondLife", "Details", "Node3D")
    for i, (x, z) in enumerate([(-20.5, 12.2), (-18.4, 11.0), (-16.6, 13.6), (-21.0, 14.8),
                                 (-19.2, 15.4)]):
        scene.prop("lily_large" if i % 2 else "lily_small", "Details/PondLife", x, z,
                   y=PATH_LIFT, rot_y=i * 37, name="Lily%d" % i)
    scene.prop("canoe", "Details/PondLife", -22.0, 13.2, y=PATH_LIFT, rot_y=8, name="Canoe")
    scene.prop("canoe_paddle", "Details/PondLife", -21.4, 13.4, y=PATH_LIFT, rot_y=30, name="Paddle")
    for i, (x, z) in enumerate([(-23.0, 10.4), (-22.2, 16.0), (-15.2, 10.4), (-15.6, 15.6)]):
        scene.prop("rock_largeC", "Details/PondLife", x, z, rot_y=i * 55, name="PondRock%d" % i)
    # rocks + stones through the meadow and on the hills
    scene.node("Rocks", "Terrain", "Node3D")
    rocks = [
        (-2.0, -18.0), (0.6, -18.6), (2.4, -17.2), (-5.0, -19.0), (4.0, -19.4),
        (8.6, -11.6), (9.2, -4.0), (8.8, 6.0), (9.6, 10.0),
        (-6.0, 14.0), (-8.4, 16.0), (-2.0, 16.0), (3.0, 14.0), (6.0, 12.0),
        (-24.0, -12.0), (-23.0, -19.0), (-13.0, -16.0), (-14.6, -11.0),
        (20.0, 12.0), (23.0, 6.0), (25.0, 10.0), (19.0, 18.0),
        (-11.0, -4.0), (-12.4, 2.0), (-12.0, -6.0),
    ]
    kinds = ["rock_largeA", "rock_smallB", "rock_tallA", "stone_largeC", "rock_smallD"]
    for i, (x, z) in enumerate(rocks):
        s = 0.8 + _h01("rocks", i) * 0.6
        scene.prop(kinds[i % len(kinds)], "Terrain/Rocks",
                   x + (_h01("rockx", i) - 0.5) * 1.8,
                   z + (_h01("rockz", i) - 0.5) * 1.8,
                   rot_y=_h01("rockr", i) * 360.0, scale=(s, s, s), name="Rock%d" % i)
    # shrubs, flowers, mushrooms: discrete accents along lanes and fences
    scene.node("Plants", "Terrain", "Node3D")
    plants = [
        ("plant_bushLarge", -21.0, 2.4), ("plant_bush", -18.4, 6.0),
        ("plant_bushDetailed", -12.6, -2.0), ("plant_bushSmall", -1.0, 2.6),
        ("plant_bushLargeTriangle", (3.6), 6.0), ("plant_bushTriangle", (8.4), -6.0),
        ("plant_flatTall", -10.0, 6.4), ("plant_flatShort", -2.6, -6.0),
        ("flower_redA", -14.0, 0.0), ("flower_yellowB", -6.0, -2.6),
        ("flower_purpleC", 1.0, 0.0), ("flower_redC", 9.4, 3.0),
        ("mushroom_red", -19.0, -14.0), ("mushroom_tan", -20.4, -16.0),
        ("mushroom_redGroup", 3.4, -18.0), ("mushroom_tanGroup", 8.0, -19.4),
        ("stump_round", -12.0, -8.0), ("stump_squareDetailed", 6.0, -10.0),
        ("log", 8.0, -6.0), ("log_large", -22.0, -20.0),
    ]
    for i, (m, x, z) in enumerate(plants):
        scene.prop(m, "Terrain/Plants", x, z, rot_y=(i * 53) % 360, name="Plant%d" % i)


def emit_scatter(scene):
    """Dense low ground cover is generated at load time as MultiMeshes (see the
    level script) so a few hundred tufts cost one draw call each, not one node."""
    scene.node("Scatter", "", "Node3D")
    fields = [
        ("GrassTufts", "grass", 900, -25, -23, 25, 23, 0.75, 1.5),
        ("GrassLarge", "grass_large", 420, -25, -23, 25, 23, 0.8, 1.6),
        ("LeafLitter", "grass_leafs", 380, -25, -23, 25, 23, 0.8, 1.5),
        ("LeafLitterLarge", "grass_leafsLarge", 200, -25, -23, 25, 23, 0.9, 1.7),
        ("Bushes", "plant_bushSmall", 150, -25, -23, 25, 23, 0.8, 1.4),
        ("Flowers", "flower_yellowA", 120, -25, -14, 25, 23, 0.9, 1.5),
        ("FlowersRed", "flower_redB", 90, -25, -14, 25, 23, 0.9, 1.5),
        ("Mushrooms", "mushroom_tan", 70, -24, -22, 12, -14, 0.9, 1.4),
    ]
    for name, model, count, x0, z0, x1, z1, smin, smax in fields:
        scene.node(name, "Scatter", "Node3D",
                   ['metadata/model = "%s"' % model,
                    "metadata/count = %d" % count,
                    'metadata/area = Vector4(%s, %s, %s, %s)' % (x0, z0, x1, z1),
                    "metadata/scale_min = %.2f" % smin,
                    "metadata/scale_max = %.2f" % smax,
                    "metadata/y = %.3f" % PROP_Y,
                    "metadata/seed = %d" % (abs(hash(name)) % 100000)])


# ---------------------------------------------------------------- validation
# Spec 6.3: every mandatory building must be reachable by ordinary spread, the
# network must offer more than one clearing order, and optional props (trees,
# barrels) must never be the only way in. This check runs on every build.

CONNECTED_MAX = 4.0        # centre-to-centre that spreads without help
CONDITIONAL_MAX = 6.0      # needs a gust to jump between buildings


def _distance(a, b):
    """Distance between two sites: (name, x, z, y, facing, cluster, role)."""
    return math.hypot(a[1] - b[1], a[2] - b[2])


def validate(plots):
    mandatory = [p for p in plots if p[6] != "optional"]
    problems = []
    for p in mandatory:
        nearest = min((_distance(p, q) for q in plots if q is not p), default=99.0)
        if nearest > CONDITIONAL_MAX:
            problems.append("%s has no neighbour within %.0f m (nearest %.2f m)" % (p[0], CONDITIONAL_MAX, nearest))
    # reachability from the starter plot over connected + conditional links
    starter = next(p for p in plots if p[6] == "starter")
    seen = {starter[0]}
    frontier = [starter]
    while frontier:
        cur = frontier.pop()
        for q in plots:
            if q[0] in seen or q[6] == "optional":
                continue
            if _distance(cur, q) <= CONDITIONAL_MAX:
                seen.add(q[0])
                frontier.append(q)
    for p in mandatory:
        if p[0] not in seen:
            problems.append("%s unreachable from the starter plot" % p[0])
    links = {}
    for p in plots:
        for q in plots:
            if p[0] >= q[0]:
                continue
            d = _distance(p, q)
            if d <= CONDITIONAL_MAX:
                links[(p[0], q[0])] = d
    conditional = {k: v for k, v in links.items() if v > CONNECTED_MAX}
    clusters = sorted({(p[5], p[6]) for p in plots})
    print("\nSpread graph: %d plots, %d links (%d connected, %d conditional)" % (
        len(plots), len(links), len(links) - len(conditional), len(conditional)))
    print("  clusters: " + ", ".join("%s(%s)" % (c[0], c[1]) for c in clusters))
    if conditional:
        print("  wind-assisted links: " + ", ".join(
            "%s-%s %.1fm" % (a, b, d) for (a, b), d in sorted(conditional.items(), key=lambda kv: kv[1])))
    if problems:
        print("  WARNINGS:")
        for w in problems:
            print("    - " + w)
    else:
        print("  OK: every mandatory plot is reachable by spread alone")


def write_docs(plots):
    """Keep the human-readable plot table in step with the layout automatically."""
    path = os.path.join(ROOT, "scenes", "levels", "VILLAGE_FIELDS.md")
    rows = []
    for p in sorted(plots, key=lambda r: r[0]):
        rows.append("| `%s` | %.1f | %.1f | %.1f | %d\u00b0 | `%s` | %s |" % (
            p[0], p[1], p[2], p[3], p[4], p[5], p[6]))
    table = "\n".join(rows)
    doc = DOC_TEMPLATE.replace("{{PLOTS}}", table).replace("{{COUNT}}", str(len(plots)))
    with open(path, "w") as f:
        f.write(doc)
    print("wrote %s" % path)


DOC_TEMPLATE = """# Village Fields — authored village level

`village_fields.tscn` is the hand-built foundation for a *Village* level: meadow,
pond, curving lanes, fences, crops and woodland. It is generated by
`tools/build_village_fields.py` and meant to be edited from there (or by hand in
the editor — the generator is only a convenience for tiling).

* Scene: `res://scenes/levels/village_fields.tscn`
* Script: `res://scenes/levels/village_fields.gd` (adds MultiMesh ground cover,
  normalises the kit's materials, exposes `house_plots()`)
* Selectable in the main menu as **Village Fields (authored preview)** (level index
  3, `RunState.HANDCRAFTED_LEVEL`). It never affects campaign unlocks.
* While it contains no houses the game runs it in *staging* mode: win/lose
  evaluation is suspended and the HUD reports the reserved plot count.

## How the ground is made

Nothing that shapes the village is laid out on a tile grid — that is what used to
make it read as graph paper. The scene carries *parameters*, and
`village_fields.gd` draws the surfaces:

* `Roads/<name>` — `metadata/spine` is a polyline in metres. The script lays a
  ribbon mesh along it with a wobbling edge, a lighter centre and a darker verge.
* `Water/Pond` — `metadata/centre`, `radius`, `seed`. Drawn as an organic polygon
  with a muddy shore ring, plus lilies, a canoe and `water_sources` markers around
  the rim.
* `Terrain/Hills/Hill*` — `metadata/centre`, `radii`, `height`. Drawn as faceted
  mounds: rock skirt, grass cap.
* `HousePlots/<name>` — the reserved sites. Each row in the generator's
  `PLOT_ROWS` names a lane, the stretch of it, which side and how far back, so
  plots bend with their road and never line up across the village. Sites are then
  relaxed apart so a 3 x 3 m house always fits, and each is marked with a cleared
  pad plus a few stones or stumps left at its edge.

Kit models are still used for everything that is an object rather than a surface:
trees, rocks, crops, fences, tents, statues, lilies, logs.

The level authors no environment of its own: it inherits the campaign's sky, sun
and fog so it sits in the same light as the procedural levels. The kit's candy
palette (mint grass, salmon dirt, near-white water) is remapped onto the campaign
palette in `village_fields.gd` (`PALETTE`).

* Fire-spread bands used by the layout (SPEC 6.3): <= 4 m connected,
  4-6 m conditional (needs a gust), > 6 m broken.

## Reserved building plots ({{COUNT}})

Each `HousePlots/<name>` node is an empty marker carrying `metadata/cluster`,
`metadata/role`, `metadata/size` and a facing rotation. `HousePlots/Pads` holds
matching ground pads purely so the reserved ground reads clearly; delete that node
once houses are in.

| plot | x | z | y | facing | cluster | role |
|---|---:|---:|---:|---:|---|---|
{{PLOTS}}

## Dropping houses in

1. Add a `Houses` node under `VillageFields`.
2. Place house scenes under it (anything typed `VoxelHouse` is collected) or
   re-parent them onto the plot markers so each house inherits position/facing.
3. `VillageFieldsLevel.build_context()` then reports them as burnable structures and
   automatically drops out of staging mode.

Suggested layout (see the plot table): lane-facing fronts at 3.4-4.3 m pitch for
easy spread, continuing along the main lane past the green into the `farm_lane`
row and on into the `east_farm` cluster. Each marker's `rotation.y` already faces
its road, so re-parenting a house onto a marker gives it the right front.

## Water

The pond and the village well carry `water_sources` markers, so bucket carriers
path to whichever is nearest. The pond is drawn as a mesh (no water tiles), so its
outline is smooth rather than stepped; it is a hard firebreak on the south-west
side of the village.

## Regenerating / validating

```bash
python3 tools/build_village_fields.py     # rebuild the .tscn + this file
godot --path . --script res://tools/dump_plots.gd   # print the plot table
```

The generator validates the spread graph on every build and prints a warning if a
mandatory plot becomes unreachable or has no neighbour inside 6 m.

## Screenshots through the real game view

```bash
godot --path . --script res://tools/level_shot.gd -- --level=3 --out=/tmp/shots \
      --views=fit,overview,core --size=1500x1000 [--hud=1] [--fullscreen=1]
```

Pass `--fullscreen=1` under a tiling compositor (Hyprland, i3, ...): those ignore
`--size` and hand the window any geometry the layout dictates, while fullscreen
gives a predictable, wide viewport. The harness derives the camera size from the
real viewport either way, so a shot always frames the same region.

Views: `fit`, `wide`, `overview`, `core`, `close`, `north/south/east/west`,
`plan`, `plan_west`, `plan_east`, `hill`, `hillnw`, `pond`, `green`, `farm`.
`plan*` are straight-down debug views through the game's own camera.
"""


def main():
    scene = Scene("VillageFields", script="res://scenes/levels/village_fields.gd")
    scene.node("Atmosphere", "", "Node3D")
    emit_atmosphere(scene)
    scene.node("Terrain", "", "Node3D")
    land = emit_lawn(scene)
    emit_underlay(scene)
    emit_hills(scene)
    emit_paths(scene)
    emit_water(scene)
    emit_trees(scene)
    emit_details(scene)
    emit_crops(scene)
    emit_fences(scene)
    emit_scatter(scene)
    emit_plots(scene)
    emit_collision(scene, land)
    scene.write(OUT)
    validate(PLOTS)
    write_docs(PLOTS)


if __name__ == "__main__":
    main()
