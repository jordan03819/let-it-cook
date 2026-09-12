extends Control
## Basic main menu for Let It Cook.
## Handles Start / Options / Quit.

@onready var start_button: Button = %StartButton
@onready var level2_button: Button = %Level2Button
@onready var level3_button: Button = %Level3Button
@onready var options_button: Button = %OptionsButton
@onready var quit_button: Button = %QuitButton
@onready var options_panel: PanelContainer = %OptionsPanel
@onready var volume_slider: HSlider = %VolumeSlider
@onready var options_back_button: Button = %OptionsBackButton

const GAME_SCENE := "res://scenes/game.tscn"


func _ready() -> void:
	# Keyboard / gamepad navigation starts on Start.
	start_button.grab_focus()
	options_panel.hide()
	# Sequential progression: L2/L3 unlock by winning earlier levels.
	level2_button.disabled = RunState.unlocked < 1
	level3_button.disabled = RunState.unlocked < 2
	if level2_button.disabled:
		level2_button.text = "Level 2 Town (locked)"
	if level3_button.disabled:
		level3_button.text = "Level 3 City (locked)"

	# Connect signals (also connected in .tscn, safe to connect here with flags).
	if not start_button.pressed.is_connected(_on_start_pressed):
		start_button.pressed.connect(_on_start_pressed)
	if not options_button.pressed.is_connected(_on_options_pressed):
		options_button.pressed.connect(_on_options_pressed)
	if not quit_button.pressed.is_connected(_on_quit_pressed):
		quit_button.pressed.connect(_on_quit_pressed)
	if not level2_button.pressed.is_connected(_on_level2_pressed):
		level2_button.pressed.connect(_on_level2_pressed)
	if not level3_button.pressed.is_connected(_on_level3_pressed):
		level3_button.pressed.connect(_on_level3_pressed)
	if not options_back_button.pressed.is_connected(_on_options_back_pressed):
		options_back_button.pressed.connect(_on_options_back_pressed)
	if not volume_slider.value_changed.is_connected(_on_volume_changed):
		volume_slider.value_changed.connect(_on_volume_changed)

	# Init volume slider from current Master bus.
	var master_idx := AudioServer.get_bus_index("Master")
	volume_slider.value = db_to_linear(AudioServer.get_bus_volume_db(master_idx))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if options_panel.visible:
			options_panel.hide()
			options_button.grab_focus()
		else:
			get_tree().quit()


func _on_start_pressed() -> void:
	RunState.reset_run()
	RunState.start_level(0)
	_open_game()


func _on_level2_pressed() -> void:
	if RunState.unlocked < 1:
		return
	RunState.reset_run()
	RunState.start_level(1)
	_open_game()


func _on_level3_pressed() -> void:
	if RunState.unlocked < 2:
		return
	RunState.reset_run()
	RunState.start_level(2)
	_open_game()


func _open_game() -> void:
	if ResourceLoader.exists(GAME_SCENE):
		get_tree().change_scene_to_file(GAME_SCENE)
	else:
		push_warning("Game scene not found: %s" % GAME_SCENE)


func _on_options_pressed() -> void:
	options_panel.show()
	options_back_button.grab_focus()


func _on_options_back_pressed() -> void:
	options_panel.hide()
	options_button.grab_focus()
	SoundManager.save_settings()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_volume_changed(value: float) -> void:
	SoundManager.set_master_volume(value)
