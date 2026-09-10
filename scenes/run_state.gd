class_name RunState
## Static run progress shared across scene reloads (no autoload needed).
## Main menu Start -> reset_run() -> Level 1. Wins unlock later levels.

static var level: int = 0
static var unlocked: int = 0 # highest level index reachable via menu
static var up_crispy: bool = false # houses burn 25% faster
static var up_grease: bool = false # +2 max embers, +1 ember per burn-out
static var up_aura: bool = false # burning characters live +40% longer
static var run_toasted: int = 0
static var run_torched: int = 0
static var run_time: float = 0.0
static var edge_pan: bool = false
static var level_time: float = 0.0
# THE Fire: one creature. Global breath clock (all flames pulse together)
# and 0..1 growth (all flames grow as it feeds).
static var fire_pulse: float = 0.0
static var inferno: float = 0.0


static func reset_run() -> void:
	level = 0
	up_crispy = false
	up_grease = false
	up_aura = false
	run_toasted = 0
	run_torched = 0
	run_time = 0.0
	level_time = 0.0


static func start_level(idx: int) -> void:
	level = clampi(idx, 0, 2)
	# Fresh-level picks reset only on full restart; upgrades persist per run.


static func apply_upgrade(id: String) -> void:
	match id:
		"crispy":
			up_crispy = true
		"grease":
			up_grease = true
		"aura":
			up_aura = true
