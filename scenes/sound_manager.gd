class_name SoundManager
extends Node
## Global SoundManager for Let It Cook.
## Synthesizes clean, normalized 16-bit PCM procedural audio (SPEC Section 17 & 20).
## Dispatches through dedicated buses (Master, Ambience, SFX, Music) with zero clipping.
## Persists volume settings to user://settings.cfg (SPEC Section 18.3).

const SETTINGS_PATH := "user://settings.cfg"
const POOL_SIZE := 8
const SAMPLE_RATE := 22050

static var _instance: SoundManager = null

var _streams: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_idx: int = 0
var _last_play_time: Dictionary = {}

var _crackle_player: AudioStreamPlayer = null
var _rain_player: AudioStreamPlayer = null
var _target_crackle_db: float = -80.0
var _target_rain_db: float = -80.0


func _init() -> void:
	if _instance == null:
		_instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	if _instance == null:
		_instance = self
	_streams = _load_audio()
	if _streams.size() < AUDIO_FILES.size():
		# Fill any gap — a missing file must never silence a cue.
		var synth := {}
		var previous := _streams
		_streams = {}
		_synth_all_streams()
		synth = _streams
		_streams = previous
		for k in synth:
			if not _streams.has(k):
				_streams[k] = synth[k]
		print("SoundManager: %d/%d shipped sounds loaded, rest synthesised" % [previous.size(), AUDIO_FILES.size()])
	else:
		print("SoundManager: loaded %d CC0 sounds from %s" % [_streams.size(), AUDIO_DIR])
	_setup_audio_players()
	_load_settings_impl()


func _setup_audio_players() -> void:
	# Ambience player for Fire Crackle
	_crackle_player = AudioStreamPlayer.new()
	_crackle_player.name = "CrackleAmbience"
	_crackle_player.bus = &"Ambience"
	_crackle_player.stream = _streams.get("crackle")
	_crackle_player.volume_db = -80.0
	add_child(_crackle_player)
	_crackle_player.play()

	# Ambience player for Rain
	_rain_player = AudioStreamPlayer.new()
	_rain_player.name = "RainAmbience"
	_rain_player.bus = &"Ambience"
	_rain_player.stream = _streams.get("rain")
	_rain_player.volume_db = -80.0
	add_child(_rain_player)
	_rain_player.play()

	# Pool of SFX players
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SFX_%d" % i
		p.bus = &"SFX"
		add_child(p)
		_sfx_players.append(p)


func _process(delta: float) -> void:
	if _crackle_player != null:
		_crackle_player.volume_db = lerpf(_crackle_player.volume_db, _target_crackle_db, minf(1.0, delta * 3.5))
	if _rain_player != null:
		_rain_player.volume_db = lerpf(_rain_player.volume_db, _target_rain_db, minf(1.0, delta * 3.0))


# ---------- Static API ----------
static func _ensure_instance() -> SoundManager:
	if _instance == null:
		_instance = SoundManager.new()
		_instance.name = "SoundManager"
		var loop := Engine.get_main_loop()
		if loop is SceneTree and (loop as SceneTree).root != null:
			(loop as SceneTree).root.call_deferred("add_child", _instance)
	return _instance


static func play_sfx(sound_name: String, pitch_scale: float = 1.0, volume_offset_db: float = 0.0) -> void:
	var inst := _ensure_instance()
	if inst != null:
		inst._play_sfx_impl(sound_name, pitch_scale, volume_offset_db)


static func update_fire_crackle(burning_count: int) -> void:
	var inst := _ensure_instance()
	if inst != null:
		inst._update_fire_crackle_impl(burning_count)


static func set_rain_ambience(active: bool) -> void:
	var inst := _ensure_instance()
	if inst != null:
		inst._set_rain_ambience_impl(active)


static func set_master_volume(linear_val: float) -> void:
	var inst := _ensure_instance()
	if inst != null:
		inst._set_master_volume_impl(linear_val)


static func set_sfx_volume(linear_val: float) -> void:
	var inst := _ensure_instance()
	if inst != null:
		inst._set_sfx_volume_impl(linear_val)


static func set_ambience_volume(linear_val: float) -> void:
	var inst := _ensure_instance()
	if inst != null:
		inst._set_ambience_volume_impl(linear_val)


static func save_settings() -> void:
	var inst := _ensure_instance()
	if inst != null:
		inst._save_settings_impl()


static func load_settings() -> void:
	var inst := _ensure_instance()
	if inst != null:
		inst._load_settings_impl()


# ---------- Implementation Methods ----------
func _play_sfx_impl(sound_name: String, pitch_scale: float = 1.0, volume_offset_db: float = 0.0) -> void:
	if not _streams.has(sound_name) or _sfx_players.is_empty():
		return

	# Rate limit rapid duplicate triggers
	var now := Time.get_ticks_msec()
	var last_t: int = _last_play_time.get(sound_name, 0)
	if now - last_t < 60:
		return
	_last_play_time[sound_name] = now

	# Pick next player from pool
	var player := _sfx_players[_sfx_idx]
	_sfx_idx = (_sfx_idx + 1) % POOL_SIZE

	player.stop()
	player.stream = _streams[sound_name]
	player.pitch_scale = pitch_scale * randf_range(0.96, 1.04)
	player.volume_db = volume_offset_db
	player.play()


func _update_fire_crackle_impl(burning_count: int) -> void:
	if burning_count <= 0:
		_target_crackle_db = -80.0
	elif burning_count == 1:
		_target_crackle_db = -18.0
	elif burning_count <= 3:
		_target_crackle_db = -10.0
	elif burning_count <= 6:
		_target_crackle_db = -4.0
	else:
		_target_crackle_db = 0.0


func _set_rain_ambience_impl(active: bool) -> void:
	_target_rain_db = -6.0 if active else -80.0


func _set_master_volume_impl(linear_val: float) -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx >= 0:
		if linear_val <= 0.001:
			AudioServer.set_bus_mute(idx, true)
		else:
			AudioServer.set_bus_mute(idx, false)
			AudioServer.set_bus_volume_db(idx, linear_to_db(linear_val))


func _set_sfx_volume_impl(linear_val: float) -> void:
	var idx := AudioServer.get_bus_index("SFX")
	if idx >= 0:
		if linear_val <= 0.001:
			AudioServer.set_bus_mute(idx, true)
		else:
			AudioServer.set_bus_mute(idx, false)
			AudioServer.set_bus_volume_db(idx, linear_to_db(linear_val))


func _set_ambience_volume_impl(linear_val: float) -> void:
	var idx := AudioServer.get_bus_index("Ambience")
	if idx >= 0:
		if linear_val <= 0.001:
			AudioServer.set_bus_mute(idx, true)
		else:
			AudioServer.set_bus_mute(idx, false)
			AudioServer.set_bus_volume_db(idx, linear_to_db(linear_val))


func _save_settings_impl() -> void:
	var config := ConfigFile.new()
	var master_idx := AudioServer.get_bus_index("Master")
	var sfx_idx := AudioServer.get_bus_index("SFX")
	var amb_idx := AudioServer.get_bus_index("Ambience")

	config.set_value("audio", "master", db_to_linear(AudioServer.get_bus_volume_db(master_idx)))
	config.set_value("audio", "sfx", db_to_linear(AudioServer.get_bus_volume_db(sfx_idx)))
	config.set_value("audio", "ambience", db_to_linear(AudioServer.get_bus_volume_db(amb_idx)))
	config.save(SETTINGS_PATH)


func _load_settings_impl() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		var m_vol: float = float(config.get_value("audio", "master", 0.8))
		var s_vol: float = float(config.get_value("audio", "sfx", 0.8))
		var a_vol: float = float(config.get_value("audio", "ambience", 0.8))
		_set_master_volume_impl(m_vol)
		_set_sfx_volume_impl(s_vol)
		_set_ambience_volume_impl(a_vol)
	else:
		_set_master_volume_impl(0.8)
		_set_sfx_volume_impl(0.8)
		_set_ambience_volume_impl(0.8)


# ---------- Procedural PCM Audio Synthesis ----------
## The audio shipped with the game: CC0 files under assets/audio (see
## CREDITS.md there), mapped onto the sound names the rest of the code asks for.
## `loop` is for ambiences, which the manager plays on their own players.
const AUDIO_DIR := "res://assets/audio/"
const AUDIO_FILES := {
	"ignite": "ignite.ogg",
	"wind_gust": "wind_gust.ogg",
	"explosion": "explosion.ogg",
	"collapse": "collapse.ogg",
	"splash": "splash.ogg",
	"siren": "siren.ogg",
	"shaman_cue": "shaman_cue.ogg",
	"helicopter": "helicopter.ogg",
	"last_spark": "last_spark.ogg",
	"crackle": "fire_crackle.ogg",
	"rain": "rain.ogg",
}
const LOOPING_SOUNDS: Array[String] = ["crackle", "rain", "helicopter"]


## Loads the shipped CC0 audio. Anything missing falls back to the synthesiser
## below, so a stripped build (or a missing file) still makes sound.
func _load_audio() -> Dictionary:
	var out := {}
	for sound_name in AUDIO_FILES:
		var path: String = AUDIO_DIR + str(AUDIO_FILES[sound_name])
		if not ResourceLoader.exists(path):
			continue
		var stream := load(path)
		if stream == null:
			continue
		if sound_name in LOOPING_SOUNDS and stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		out[sound_name] = stream
	return out


func _synth_all_streams() -> void:
	_streams["ignite"] = _synth_ignite()
	_streams["wind_gust"] = _synth_wind()
	_streams["explosion"] = _synth_explosion()
	_streams["collapse"] = _synth_collapse()
	_streams["splash"] = _synth_splash()
	_streams["siren"] = _synth_siren()
	_streams["shaman_cue"] = _synth_shaman_cue()
	_streams["helicopter"] = _synth_helicopter()
	_streams["last_spark"] = _synth_last_spark()
	_streams["crackle"] = _synth_crackle_loop()
	_streams["rain"] = _synth_rain_loop()


func _create_stream(samples: int, loop: bool = false) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SAMPLE_RATE
	s.stereo = false
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = samples
	return s


func _synth_ignite() -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * 0.38)
	var s := _create_stream(count)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var env := sin(t / 0.38 * PI)
		var noise := randf_range(-1.0, 1.0)
		var tone := sin(t * (130.0 - t * 80.0) * TAU)
		var val := (noise * 0.4 + tone * 0.6) * env * 0.65
		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))
	s.data = data
	return s


func _synth_wind() -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * 1.1)
	var s := _create_stream(count)
	var data := PackedByteArray()
	data.resize(count * 2)
	var f_val := 0.0
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var env := sin(t / 1.1 * PI)
		var noise := randf_range(-1.0, 1.0)
		f_val = lerpf(f_val, noise, 0.15 + env * 0.22)
		var val := f_val * env * 0.7
		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))
	s.data = data
	return s


func _synth_helicopter() -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * 2.0)
	var s := _create_stream(count)
	var data := PackedByteArray()
	data.resize(count * 2)
	var lfo_freq := 11.5 # 11.5 Hz rotor blade chop
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var chop := maxf(0.0, sin(t * lfo_freq * TAU))
		chop = pow(chop, 2.6) # sharp aerodynamic pulse
		var low_hum := sin(t * 64.0 * TAU) * 0.45
		var mid_hum := sin(t * 128.0 * TAU) * 0.25
		var noise := randf_range(-0.5, 0.5) * 0.4
		var env := sin(t / 2.0 * PI)
		var val := (low_hum + mid_hum + noise) * chop * env * 0.85
		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))
	s.data = data
	return s


func _synth_explosion() -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * 1.2)
	var s := _create_stream(count)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var env := exp(-t * 3.2)
		var freq := maxf(32.0, 130.0 - t * 90.0)
		var sine := sin(t * freq * TAU)
		var noise := randf_range(-1.0, 1.0) * exp(-t * 5.5)
		var val := (sine * 0.72 + noise * 0.38) * env * 0.75
		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))
	s.data = data
	return s


func _synth_collapse() -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * 0.65)
	var s := _create_stream(count)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var env := exp(-t * 4.5)
		var click := randf_range(-1.0, 1.0) if randf() < 0.04 else 0.0
		var tone := sin(t * 85.0 * TAU) * 0.5
		var val := (click * 0.8 + tone) * env * 0.6
		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))
	s.data = data
	return s


func _synth_splash() -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * 0.45)
	var s := _create_stream(count)
	var data := PackedByteArray()
	data.resize(count * 2)
	var prev := 0.0
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var env := exp(-t * 6.0)
		var noise := randf_range(-1.0, 1.0)
		var hp := noise - prev
		prev = noise
		var val := hp * env * 0.6
		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))
	s.data = data
	return s


func _synth_siren() -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * 0.85)
	var s := _create_stream(count)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var env := sin(t / 0.85 * PI)
		var freq := 740.0 if t < 0.42 else 920.0
		var val := sin(t * freq * TAU) * env * 0.5
		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))
	s.data = data
	return s


func _synth_shaman_cue() -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * 1.8)
	var s := _create_stream(count)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var env := exp(-t * 2.2)
		var h1 := sin(t * 330.0 * TAU)
		var h2 := sin(t * 660.0 * TAU) * 0.5
		var h3 := sin(t * 990.0 * TAU) * 0.25
		var val := (h1 + h2 + h3) * env * 0.45
		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))
	s.data = data
	return s


func _synth_last_spark() -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * 0.5)
	var s := _create_stream(count)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / float(SAMPLE_RATE)
		var p1 := sin(t * 240.0 * TAU) * sin(clamped_norm(t, 0.0, 0.22) * PI)
		var p2 := sin(t * 240.0 * TAU) * sin(clamped_norm(t, 0.25, 0.47) * PI)
		var val := (p1 + p2) * 0.6
		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))
	s.data = data
	return s


func clamped_norm(t: float, start_t: float, end_t: float) -> float:
	if t < start_t or t > end_t:
		return 0.0
	return (t - start_t) / (end_t - start_t)


func _synth_crackle_loop() -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * 2.5)
	var s := _create_stream(count, true)
	var data := PackedByteArray()
	data.resize(count * 2)
	var lp := 0.0
	for i in count:
		var noise := randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.08)
		var pop := 0.0
		if randf() < 0.003:
			pop = randf_range(0.3, 0.8) * (1.0 if randf() > 0.5 else -1.0)
		var val := (lp * 0.35 + pop) * 0.5
		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))
	s.data = data
	return s


func _synth_rain_loop() -> AudioStreamWAV:
	var count := int(SAMPLE_RATE * 2.0)
	var s := _create_stream(count, true)
	var data := PackedByteArray()
	data.resize(count * 2)
	var lp := 0.0
	for i in count:
		var noise := randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.22)
		var val := lp * 0.4
		data.encode_s16(i * 2, clampi(int(val * 32767.0), -32768, 32767))
	s.data = data
	return s
