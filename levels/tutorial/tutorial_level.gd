extends Node3D
class_name TutorialLevel

const SAMPLE_COUNT := 10 # for calculated rolling average
const PERFECT_THRESHOLD := 0.033 # 33ms, 2 frames in 60fps
const OK_THRESHOLD := 0.10 # 100ms, 6 frammes in 60fps
const MISS_DECAY_TIME := 0.5 # seconds before a miss penalty expires
const PENALTY_PER_MISS := 0.033 # each recent miss shrinks the OK window
const DPAD_INITIAL_DELAY := 0.4  # seconds held before auto-repeat starts
const DPAD_REPEAT_INTERVAL := 0.08  # seconds between repeat fires

@onready var metronome: MetronomeDummy = $MetronomeDummy
@onready var hud: HUD = $HUD
@onready var player: Player = $Player

var _in_range: bool = false
var _parry_mode_active: bool = false
var _samples: Array[float] = []
var _current_avg: float = 0.0

var _ting_perfect_stream: AudioStream
var _ting_ok_stream: AudioStream

# Predictive ting: a new AudioStreamPlayer is created each beat so confirmed tings
# can ring out in full while the next beat's ting starts — they overlap freely.
var _current_ting: AudioStreamPlayer = null
var _ting_active: bool = false
var _ting_beat_number: int = -1
var _ting_confirmed: bool = false

# Spam penalty: timestamps of recent failed presses. Each one in the last
# MISS_DECAY_TIME seconds reduces the OK window by PENALTY_PER_MISS.
var _recent_misses: Array[float] = []
var _dpad_timer: float = -1.0


func _ready() -> void:
	metronome.player_entered_range.connect(func(): _in_range = true)
	metronome.player_exited_range.connect(func(): _in_range = false; _stop_ting())

	_ting_perfect_stream = load("res://assets/audio/sfx/ting.mp3")
	_ting_ok_stream = load("res://assets/audio/sfx/ting_alt.mp3")

	BeatClock.pre_beat.connect(_on_pre_beat)

	hud.update_calibration(0.0, GameSettings.audio_offset * 1000.0, false)


func _make_ting(stream: AudioStream) -> AudioStreamPlayer:
	var ting := AudioStreamPlayer.new()
	ting.stream = stream
	ting.volume_db = -20.0
	add_child(ting)
	ting.finished.connect(ting.queue_free)
	return ting


func _get_effective_ok_threshold() -> float:
	var now := Time.get_ticks_usec() / 1_000_000.0
	var cutoff := now - MISS_DECAY_TIME
	while not _recent_misses.is_empty() and _recent_misses[0] < cutoff:
		_recent_misses.pop_front()
	return maxf(0.0, OK_THRESHOLD - float(_recent_misses.size()) * PENALTY_PER_MISS)


func _record_miss() -> void:
	_recent_misses.append(Time.get_ticks_usec() / 1_000_000.0)


func _clear_misses() -> void:
	_recent_misses.clear()


func _on_pre_beat(beat_number: int) -> void:
	if not _in_range:
		return

	# Unconfirmed ting from last beat: cut it now.
	# Confirmed ting: leave it ringing — it owns itself and frees on finish.
	if _ting_active and not _ting_confirmed and _current_ting != null:
		_current_ting.stop()
		_current_ting.queue_free()
	_current_ting = null

	var stream := _ting_perfect_stream if beat_number % 4 == 0 else _ting_ok_stream
	_current_ting = _make_ting(stream)
	_current_ting.play()

	_ting_active = true
	_ting_beat_number = beat_number
	# _ting_confirmed is NOT reset here. Godot processes input before _process, so a press in the 
	# same frame as pre_beat fires would set it true and this reset would immediately wipe it. State
	# is reset in _on_ting_window_expired/_stop_ting.

	var window_close_delay := GameSettings.audio_offset + OK_THRESHOLD
	var captured := beat_number
	get_tree().create_timer(window_close_delay).timeout.connect(
		func(): _on_ting_window_expired(captured)
	)


func _on_ting_window_expired(beat_number: int) -> void:
	if _ting_beat_number != beat_number or not _ting_active:
		return
	if not _ting_confirmed:
		_stop_ting()
	else:
		# Confirmed: release the ting to ring freely, close the window.
		_current_ting = null
		_ting_active = false
		_ting_confirmed = false


func _reset() -> void:
	player.reset()
	metronome.restart_audio()
	_samples.clear()
	_current_avg = 0.0
	_recent_misses.clear()
	_stop_ting()
	hud.update_calibration(0.0, GameSettings.audio_offset * 1000.0, false)


func _stop_ting() -> void:
	_ting_active = false
	_ting_confirmed = false
	if _current_ting != null:
		_current_ting.stop()
		_current_ting.queue_free()
		_current_ting = null


func _process(delta: float) -> void:
	var active := Input.is_action_pressed("parry_mode") and _in_range
	if active != _parry_mode_active:
		_parry_mode_active = active
		hud.set_parry_mode(active)

	var dir := 0
	if not _parry_mode_active:
		if Input.is_action_pressed("offset_decrease"): dir = -1
		elif Input.is_action_pressed("offset_increase"): dir = 1
	if dir != 0:
		if _dpad_timer < 0.0:
			_adjust_offset_snapped(dir)
			_dpad_timer = 0.0
		else:
			_dpad_timer += delta
			if _dpad_timer >= DPAD_INITIAL_DELAY:
				var elapsed := _dpad_timer - DPAD_INITIAL_DELAY
				var prev_elapsed := elapsed - delta
				if int(elapsed / DPAD_REPEAT_INTERVAL) > int(maxf(prev_elapsed, 0.0) / DPAD_REPEAT_INTERVAL):
					_adjust_offset_snapped(dir)
	else:
		_dpad_timer = -1.0


func _unhandled_input(event: InputEvent) -> void:
	if _parry_mode_active:
		if event.is_action_pressed("parry_top"):
			_handle_parry_press(true)
		elif event.is_action_pressed("parry_bottom"):
			_handle_parry_press(false)
		return

	if event.is_action_pressed("reset_level"):
		_reset()


func _handle_parry_press(is_top: bool) -> void:
	if _ting_active:
		var expecting_top := _ting_beat_number % 4 == 0
		if is_top != expecting_top:
			_stop_ting()
			_record_miss()
			hud.show_timing("Wrong", Color(1.0, 0.2, 0.2))
			return

	if is_top:
		_record_top_press()
	else:
		_record_bottom_press()


func _record_top_press() -> void:
	var beat_dur := BeatClock.beat_duration()
	var bar_dur := beat_dur * 4.0
	var raw_t := BeatClock.get_beat_time() + GameSettings.audio_offset

	var x_meas := fmod(raw_t + bar_dur * 0.5, bar_dur) - bar_dur * 0.5
	_add_sample(x_meas)

	var comp_bar_dist := fmod(BeatClock.get_beat_time() + bar_dur * 0.5, bar_dur) - bar_dur * 0.5
	_show_timing(comp_bar_dist)


func _record_bottom_press() -> void:
	var beat_dur := BeatClock.beat_duration()
	var bar_dur := beat_dur * 4.0

	var comp_beat_dist := fmod(BeatClock.get_beat_time() + beat_dur * 0.5, beat_dur) - beat_dur * 0.5
	_show_timing(comp_beat_dist)

	if _samples.is_empty():
		return

	var raw_t := BeatClock.get_beat_time() + GameSettings.audio_offset

	var bar_pos := fmod(raw_t - _current_avg + bar_dur * 4.0, bar_dur)
	var m := roundi(bar_pos / beat_dur) % 4
	if m == 0:
		m = 1

	var x_meas := fmod(raw_t + bar_dur * 4.0, bar_dur) - m * beat_dur
	x_meas = fmod(x_meas + bar_dur * 1.5, bar_dur) - bar_dur * 0.5
	_add_sample(x_meas)


func _add_sample(x: float) -> void:
	_samples.append(x)
	if _samples.size() > SAMPLE_COUNT:
		_samples.pop_front()
	var total := 0.0
	for s in _samples:
		total += s
	_current_avg = total / _samples.size()
	hud.update_calibration(_current_avg * 1000.0, GameSettings.audio_offset * 1000.0, true)


func _adjust_offset_snapped(direction: int) -> void:
	var offset_ms := GameSettings.audio_offset * 1000.0
	var new_ms: float
	if direction < 0:
		new_ms = floorf((offset_ms - 0.001) / 10.0) * 10.0
	else:
		new_ms = ceilf((offset_ms + 0.001) / 10.0) * 10.0
	GameSettings.audio_offset = new_ms / 1000.0
	GameSettings.save()
	hud.update_calibration(_current_avg * 1000.0, GameSettings.audio_offset * 1000.0, _samples.size() > 0)


func _show_timing(dist: float) -> void:
	var effective_ok := _get_effective_ok_threshold()
	var abs_dist: float = absf(dist)
	if abs_dist <= PERFECT_THRESHOLD:
		hud.show_timing("Perfect!", Color(1.0, 0.9, 0.1))
		_ting_confirmed = true
		_clear_misses()
	elif abs_dist <= effective_ok:
		hud.show_timing("OK", Color(0.3, 1.0, 0.3))
		_ting_confirmed = true
		_clear_misses()
	elif dist < 0.0:
		hud.show_timing("Early", Color(1.0, 0.6, 0.2))
		_record_miss()
		_stop_ting()
	else:
		hud.show_timing("Late", Color(1.0, 0.6, 0.2))
		_record_miss()
		_stop_ting()
