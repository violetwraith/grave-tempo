extends Node

# Time is counted in quarter-note "beats": bpm is the quarter-note tempo and beat_duration()
# is one beat. The "sixteenth" signal fires four times per beat, and an eighth note is half a
# beat. So even in 7/8, a "beat" here is a quarter note, never the eighth-note pulse.

signal beat(beat_number: int)
signal sixteenth(sixteenth_number: int)

# The pre_ signals fire audio_offset seconds before the audible beat, so SFX triggered here
# reach the output in sync with the beat.
signal pre_beat(beat_number: int)
signal pre_sixteenth(sixteenth_number: int)

var bpm: float = 60.0
var music_player: Node = null

var _last_beat: int = -1
var _last_sixteenth: int = -1
var _last_pre_beat: int = -1
var _last_pre_sixteenth: int = -1
var _clock_start: float = -1.0
var _last_time: float = 0.0


func detach_music() -> void:
	if music_player == null:
		return
	# Capture the current beat time, then hand off to the wall clock at the same position.
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
	# Suppress small backward jitter from the audio thread, but let a large backward
	# jump (over 100ms) through as a genuine restart or seek.
	if t < _last_time and _last_time - t < 0.1:
		t = _last_time
	_last_time = t
	return t


func beat_duration() -> float:
	return 60.0 / bpm


func _process(_delta: float) -> void:
	var t := get_beat_time()
	if t < 0.0:
		return
	var bd := beat_duration()
	var current_beat := int(t / bd)
	var current_sixteenth := int(t / (bd * 0.25))
	if current_beat != _last_beat:
		_last_beat = current_beat
		beat.emit(current_beat)
	if current_sixteenth != _last_sixteenth:
		_last_sixteenth = current_sixteenth
		sixteenth.emit(current_sixteenth)

	var raw_t := t + GameSettings.audio_offset
	var current_pre_beat := int(raw_t / bd)
	if current_pre_beat != _last_pre_beat:
		_last_pre_beat = current_pre_beat
		pre_beat.emit(current_pre_beat)
	var current_pre_sixteenth := int(raw_t / (bd * 0.25))
	if current_pre_sixteenth != _last_pre_sixteenth:
		_last_pre_sixteenth = current_pre_sixteenth
		pre_sixteenth.emit(current_pre_sixteenth)
