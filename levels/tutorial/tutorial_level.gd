extends Node3D
class_name TutorialLevel

const SAMPLE_COUNT := 10 # for calculating rolling average
const PERFECT_THRESHOLD := 0.066 # 4 frames in 60fps
const OK_THRESHOLD := 0.20 # 12 frames in 60fps
const MISS_DECAY_TIME := 0.5 # seconds before a miss penalty expires
const PENALTY_PER_MISS := 0.033 # each recent miss shrinks the OK window
const DPAD_INITIAL_DELAY := 0.4  # seconds held before auto-repeat starts
const DPAD_REPEAT_INTERVAL := 0.08  # seconds between repeat fires

@onready var metronome: MetronomeDummy = $MetronomeDummy
@onready var hud: HUD = $HUD
@onready var player: Player = $Player

var _in_range: bool = false
var _samples: Array[float] = []
var _current_avg: float = 0.0

var _ting_perfect_stream: AudioStream
var _parry_response_stream: AudioStream

var _ting_active: bool = false
var _ting_beat_number: int = -1
var _ting_confirmed: bool = false

# Spam penalty: timestamps of recent failed presses. Each one in the last
# MISS_DECAY_TIME seconds reduces the OK window by PENALTY_PER_MISS.
var _recent_misses: Array[float] = []
var _dpad_timer: float = -1.0
var _ting_enabled: bool = false


func _ready() -> void:
	metronome.player_entered_range.connect(func(): _in_range = true)
	metronome.player_exited_range.connect(func(): _in_range = false; _stop_ting())

	_ting_perfect_stream = load("res://assets/audio/sfx/ting.mp3")
	_parry_response_stream = load("res://assets/audio/sfx/ting.mp3")

	BeatClock.beat.connect(_on_beat)
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
	if not _in_range or beat_number % 4 != 0:
		return

	# Attack sound rings out freely — no reference kept, no cutting on miss.
	# The parry response (played on confirmed input) blends with this ring-out.
	if _ting_enabled:
		_make_ting(_ting_perfect_stream).play()

	_ting_active = true
	_ting_beat_number = beat_number
	# _ting_confirmed is NOT reset here — race condition: Godot processes input before _process,
	# so a same-frame press sets it true and a reset here would immediately wipe it.
	# Reset only in _on_ting_window_expired / _stop_ting.

	var window_close_delay := OK_THRESHOLD - GameSettings.audio_offset
	var captured := beat_number
	get_tree().create_timer(window_close_delay).timeout.connect(
		func(): _on_ting_window_expired(captured)
	)


func _on_ting_window_expired(beat_number: int) -> void:
	if _ting_beat_number != beat_number or not _ting_active:
		return
	if not _ting_confirmed:
		hud.show_timing("Miss", Color(1.0, 0.3, 0.3))
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


func _on_beat(beat_number: int) -> void:
	if _in_range and beat_number % 4 == 3:
		hud.show_windup()


func _play_parry_response(dist: float) -> void:
	var p := _make_ting(_parry_response_stream)
	if dist > PERFECT_THRESHOLD:
		# Late hit: pitch up and duck volume proportional to how late.
		# The sharper, quieter sound resolves faster and blends into the attack ring-out.
		var t := clampf((dist - PERFECT_THRESHOLD) / (OK_THRESHOLD - PERFECT_THRESHOLD), 0.0, 1.0)
		p.pitch_scale = lerpf(1.0, 1.25, t)
		p.volume_db = lerpf(-20.0, -25.0, t)
	p.play()


func _process(delta: float) -> void:
	var dir := 0
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
	if event.is_action_pressed("parry"):
		_handle_parry_press()
	elif event.is_action_pressed("reset_level"):
		_reset()
	elif event.is_action_pressed("toggle_ting"):
		_ting_enabled = not _ting_enabled
		hud.set_ting_enabled(_ting_enabled)


func _handle_parry_press() -> void:
	if not _in_range:
		return
	_record_top_press()


func _record_top_press() -> void:
	var beat_dur := BeatClock.beat_duration()
	var bar_dur := beat_dur * 4.0
	var raw_t := BeatClock.get_beat_time() + GameSettings.audio_offset

	var x_meas := fmod(raw_t + bar_dur * 0.5, bar_dur) - bar_dur * 0.5
	_add_sample(x_meas)

	var comp_bar_dist := fmod(BeatClock.get_beat_time() + bar_dur * 0.5, bar_dur) - bar_dur * 0.5
	_show_timing(comp_bar_dist)


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
		_play_parry_response(dist)
	elif abs_dist <= effective_ok:
		hud.show_timing("OK", Color(0.3, 1.0, 0.3))
		_ting_confirmed = true
		_clear_misses()
		_play_parry_response(dist)
	elif dist < 0.0:
		hud.show_timing("Early", Color(1.0, 0.6, 0.2))
		_record_miss()
		_stop_ting()
	else:
		hud.show_timing("Late", Color(1.0, 0.6, 0.2))
		_record_miss()
		_stop_ting()
