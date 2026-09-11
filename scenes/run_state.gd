class_name RunState
## REFORMED run state — minimal. No fire sim, no upgrades.
## Just level progression + timing.

static var level: int = 0
static var unlocked: int = 0
static var run_time: float = 0.0
static var level_time: float = 0.0
static var edge_pan: bool = false

# Deprecated leftovers from the old fire-sim (combos/spread/wind/etc).
# Kept only so the orphaned villager/firefighter/char_burn scripts
# still parse if opened. Not used by the reformed game.
static var fire_pulse: float = 0.0
static var inferno: float = 0.0
static var up_crispy: bool = false
static var up_grease: bool = false
static var up_aura: bool = false
static var run_toasted: int = 0
static var run_torched: int = 0


static func reset_run() -> void:
	level = 0
	run_time = 0.0
	level_time = 0.0


static func start_level(idx: int) -> void:
	level = clampi(idx, 0, 2)


static func apply_upgrade(_id: String) -> void:
	pass # deprecated no-op
