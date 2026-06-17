extends Node

signal beat(beat_number: int)
signal half_beat(beat_number: int)
signal quarter_beat(quarter_beat_number: int)

# Fires audio_offset seconds before the audible beat so SFX arrive in sync.
signal pre_beat(beat_number: int)

# Same early-fire as pre_beat but at half-beat (8th note) resolution.
signal pre_half_beat(half_beat_number: int)

# Same early-fire but at quarter-beat (16th note) resolution.
signal pre_quarter_beat(quarter_beat_number: int)

var bpm: float = 60.0
var music_player: Node = null

# init at -1 so logic starts on frame 0
var _last_beat: int = -1
var _last_half_beat: int = -1
var _last_quarter_beat: int = -1
var _last_pre_beat: int = -1
var _last_pre_half_beat: int = -1
var _last_pre_quarter_beat: int = -1
var _clock_start: float = -1.0
var _last_time: float = 0.0


func start_clock() -> void:
	_clock_start = Time.get_ticks_usec() / 1_000_000.0


func detach_music() -> void:
	if music_player == null:
		return
	# Capture current beat time, then hand off to wall clock at same position
	var t := get_beat_time()
	music_player = null
	_clock_start = Time.get_ticks_usec() / 1_000_000.0 - t - GameSettings.audio_offset


func get_beat_time() -> float:
	var t: float
	if music_player != null and music_player.playing:
		t = (
			music_player.get_playback_position()
			+ AudioServer.get_time_since_last_mix()
			- AudioServer.get_output_latency()
			- GameSettings.audio_offset
		)
	elif _clock_start >= 0.0:
		t = Time.get_ticks_usec() / 1_000_000.0 - _clock_start - GameSettings.audio_offset
	else:
		return -1.0
	# Suppress backward jitter from audio thread timing. A large backward jump
	# (>100ms) is a genuine restart/seek, not jitter — let it through.
	if t < _last_time and _last_time - t < 0.1:
		t = _last_time
	_last_time = t
	return t


func get_beat_phase() -> float:
	return fmod(get_beat_time(), beat_duration()) / beat_duration()


func get_beat_number() -> int:
	return int(get_beat_time() / beat_duration())


func beat_duration() -> float:
	return 60.0 / bpm


func _process(_delta: float) -> void:
	var t := get_beat_time()
	if t < 0.0:
		return
	var bd := beat_duration()
	var current_beat := int(t / bd)
	var current_half_beat := int(t / (bd * 0.5))
	var current_quarter_beat := int(t / (bd * 0.25))
	if current_beat != _last_beat:
		_last_beat = current_beat
		beat.emit(current_beat)
	if current_half_beat != _last_half_beat:
		_last_half_beat = current_half_beat
		half_beat.emit(current_half_beat)
	if current_quarter_beat != _last_quarter_beat:
		_last_quarter_beat = current_quarter_beat
		quarter_beat.emit(current_quarter_beat)

	# pre_beat uses the raw (hardware-buffer) clock: get_beat_time + audio_offset.
	# This fires audio_offset seconds ahead of the audible beat so that SFX connected here enter the
	# output pipeline in sync with the beat click.
	var raw_t := t + GameSettings.audio_offset
	var current_pre_beat := int(raw_t / bd)
	if current_pre_beat != _last_pre_beat:
		_last_pre_beat = current_pre_beat
		pre_beat.emit(current_pre_beat)
	var current_pre_half_beat := int(raw_t / (bd * 0.5))
	if current_pre_half_beat != _last_pre_half_beat:
		_last_pre_half_beat = current_pre_half_beat
		pre_half_beat.emit(current_pre_half_beat)
	var current_pre_quarter_beat := int(raw_t / (bd * 0.25))
	if current_pre_quarter_beat != _last_pre_quarter_beat:
		_last_pre_quarter_beat = current_pre_quarter_beat
		pre_quarter_beat.emit(current_pre_quarter_beat)
