extends BaseLevel
class_name BossLevel

# ───────────────────────────────────────────────────────────
#  Beat map encoding (positions are zero-indexed 16th notes):
#    0 = beat 1,  1 = "and of 1",  2 = beat 2,  3 = "and of 2", ...
#  BPM = quarter-note BPM; pre_quarter_beat fires every bd*0.25 = 16th note.
#  Standard 7/8 bar (7 eighth notes = 14 sixteenth notes) → 14 positions.
#  4/8 bar → 8 positions.  8/8 bar → 16 positions.
# ───────────────────────────────────────────────────────────

const BOSS_OK_THRESHOLD := 0.18  # tighter than tutorial (0.20) for 16th-note chains
const BOSS_MOVE_SPEED := 4
const BOSS_MOVE_EASE := 3.0
# Presses this many seconds before a ting opens are buffered and auto-confirmed when the ting fires
const PARRY_EARLY_WINDOW_SECS := 0.15

# Phase 1 beat map (26 bars, 120 BPM 7/8 — bars 21 and 26 are 4/8)
const P1_PATTERNS: Array = [
	# bars 0–2 (measures 1–3): 1,3,5,6,7
	[0, 2, 4, 5, 6],
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	# bar 3 (measure 4): 1,3,5
	[0, 4, 8],
	# bars 4–6 (measures 5–7)
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	# bar 7 (measure 8)
	[0, 4, 8],
	# bars 8–10 (measures 9–11)
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	# bar 11 (measure 12)
	[0, 4, 8],
	# bars 12–14 (measures 13–15)
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	# bar 15 (measure 16)
	[0, 4, 8],
	# bar 16 (measure 17): 1,3,5,7
	[0, 4, 8, 12],
	# bar 17 (measure 18): 1,4,6
	[0, 6, 10],
	# bar 18 (measure 19): 1,2,5,7
	[0, 2, 8, 12],
	# bar 19 (measure 20): 2,3,6
	[2, 4, 10],
	# bar 20 (measure 21): beat 1 only — 4/8 bar (length=8)
	[0],
	# bar 21 (measure 22): 1,3,5,7
	[0, 4, 8, 12],
	# bar 22 (measure 23): 1,4,6
	[0, 6, 10],
	# bar 23 (measure 24): 1,2,5,7
	[0, 2, 8, 12],
	# bar 24 (measure 25): 2,3,4,5,6
	[2, 4, 6, 8, 10],
	# bar 25 (measure 26): beat 1 only — 4/8 bar (length=8)
	[0],
]

const P1_BAR_LENGTHS: Array = [
	14, 14, 14, 14,  # bars 0–3
	14, 14, 14, 14,  # bars 4–7
	14, 14, 14, 14,  # bars 8–11
	14, 14, 14, 14,  # bars 12–15
	14, 14, 14, 14,  # bars 16–19
	8,               # bar 20 (4/8)
	14, 14, 14, 14,  # bars 21–24
	14,              # bar 25 (7/8)
]

# Phase 2 beat map (32 bars, 140 BPM 7/8 — bar 23 is 8/8)
const P2_PATTERNS: Array = [
	# bar 0 (measure 1): 1,2,3,5,6,7
	[0, 2, 4, 8, 10, 12],
	# bar 1 (measure 2): 1,3,5,6,7
	[0, 4, 8, 10, 12],
	# bars 2–3: same as 0–1
	[0, 2, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	# bars 4–5: same as 0–1
	[0, 2, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	# bar 6 (measure 7): 2 only
	[2],
	# bar 7 (measure 8): 1,3,5,6,7
	[0, 4, 8, 10, 12],
	# bars 8–13: repeat bars 0–5
	[0, 2, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 2, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 2, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	# bars 14–15 (measures 15–16): all downbeats 1–7
	[0, 2, 4, 6, 8, 10, 12],
	[0, 2, 4, 6, 8, 10, 12],
	# bar 16 (measure 17): 1, and-of-1, 2, and-of-2, 3, 5
	[0, 1, 2, 3, 4, 8],
	# bar 17 (measure 18): 1,5,7
	[0, 8, 12],
	# bar 18 (measure 19): 1, 2, and-of-2, 3, 5
	[0, 2, 3, 4, 8],
	# bar 19 (measure 20): 1 only
	[0],
	# bar 20 (measure 21): 1, 2, and-of-2, 3, 5, 6
	[0, 2, 3, 4, 8, 10],
	# bar 21 (measure 22): 1, 3, 4, 5, 7
	[0, 4, 6, 8, 12],
	# bar 22 (measure 23): 1, 2, and-of-2, 3, 5, 6
	[0, 2, 3, 4, 8, 10],
	# bar 23 (measure 24): 1, 5, 7 — 8/8 bar (length=16)
	[0, 8, 12],
	# bar 24 (measure 25): 1, 5, 6
	[0, 8, 10],
	# bar 25 (measure 26): 1, 5, 7
	[0, 8, 12],
	# bar 26 (measure 27): 1, 5
	[0, 8],
	# bar 27 (measure 28): 1, 5
	[0, 8],
	# bars 28–30 (measures 29–31): 1, 3, 5, 7
	[0, 4, 8, 12],
	[0, 4, 8, 12],
	[0, 4, 8, 12],
	# bar 31 (measure 32): 1 only
	[0],
]

# Phase 1 movement map (16th-note positions within each bar where the boss steps toward player).
# 8th note N → 16th-note position (N-1)*2.  Empty array = no movement that bar.
const P1_MOVE_PATTERNS: Array = [
	# Measures 1–4 (bars 0–3): rotating pair pattern
	[0, 8],   # M1:  8th 1, 5
	[2, 10],  # M2:  8th 2, 6
	[4, 12],  # M3:  8th 3, 7
	[4, 8],   # M4:  8th 3, 5
	# Measures 5–8 (bars 4–7)
	[0, 8],
	[2, 10],
	[4, 12],
	[4, 8],
	# Measures 9–12 (bars 8–11)
	[0, 8],
	[2, 10],
	[4, 12],
	[4, 8],
	# Measures 13–16 (bars 12–15)
	[0, 8],
	[2, 10],
	[4, 12],
	[4, 8],
	# Measures 17–21 (bars 16–20)
	[0, 8],   # M17: 8th 1, 5
	[2, 10],  # M18: 8th 2, 6
	[4, 12],  # M19: 8th 3, 7
	[6],      # M20: 8th 4
	[0],      # M21: 8th 1  (4/8 bar)
	# Measures 22–26 (bars 21–25) = same pattern as M18–M21 + 4/8 close
	[2, 10],  # M22 = M18
	[4, 12],  # M23 = M19
	[6],      # M24 = M20
	[0],      # M25 = M21 cadence (7/8, moves on beat 1 only)
	[0],      # M26: 7/8 bar, beat 1
]

# 16th-note positions within each bar that are "accent" notes:
#   boss moves further (2× step) and the attack ring covers 360°.
const P1_ACCENT_PATTERNS: Array = [
	[], [], [], [4, 8],  # bars 0–3 (bar 3: 3rd and 5th 8th notes)
	[], [], [], [4, 8],  # bars 4–7
	[], [], [], [4, 8],  # bars 8–11
	[], [], [], [4, 8],  # bars 12–15
	[], [], [], [],      # bars 16–19
	[0],                 # bar 20 (4/8, first beat)
	[], [], [], [],      # bars 21–24
	[0],                 # bar 25 (7/8, first beat)
]

const P2_BAR_LENGTHS: Array = [
	14, 14, 14, 14, 14, 14, 14, 14,  # bars 0–7
	14, 14, 14, 14, 14, 14, 14, 14,  # bars 8–15
	14, 14, 14, 14, 14, 14, 14, 16,  # bars 16–23 (bar 23 is 8/8)
	14, 14, 14, 14, 14, 14, 14, 14,  # bars 24–31
]

@onready var boss: BossEnemy = $Boss

var _boss_attack_dir: Vector3 = Vector3(0.0, 0.0, 1.0)

# Bar/quarter-beat (16th note) tracking
var _quarter_beat_in_bar: int = 0
var _bar_number: int = 0
var _bar_start_quarter_beats: Array[int] = []
var _total_loop_quarter_beats: int = 0
var _active_patterns: Array = []
var _active_bar_lengths: Array = []
var _active_move_patterns: Array = []

# Transition
var _awaiting_transition: bool = false

# Parry early-press buffer: stores Time.get_ticks_msec() when player presses outside a ting window
var _last_parry_press_ms: float = -1.0

# After posture break clears, block attacks until next bar downbeat so the boss can't
# immediately attack on the same beat that stun expired.
var _awaiting_stun_recovery: bool = false

# How long the attack ring visual stays visible (shorter than the full ting window).
# P1: one 16th note (bd*0.25); P2: one 32nd note (bd*0.125).
var _ring_visible_duration: float = 0.125

var _active_accent_patterns: Array = []
var _ting_is_accent: bool = false

# Diagnostic blip stream — 880 Hz sine, 40 ms, plays on every bar downbeat (pos 0)
var _beat1_blip: AudioStreamWAV = null



func _ready() -> void:
	boss.player_entered_range.connect(func(): _in_range = true)
	boss.player_exited_range.connect(func(): _in_range = false; _stop_ting())
	boss.player_body_contact.connect(_on_player_body_contact)
	boss.posture_broke.connect(_on_enemy_posture_broke)
	boss.died.connect(_on_enemy_died)
	boss.phase_transition_pending.connect(_on_phase_transition_pending)
	boss.phase_transition_started.connect(_on_phase_transition_started)
	boss.phase_two_ready.connect(_on_phase_two_ready)

	super._ready()

	# Disconnect base_level's pre_beat handler; we manage attack windows at 16th-note resolution
	BeatClock.pre_beat.disconnect(_on_pre_beat)
	BeatClock.pre_quarter_beat.connect(_on_boss_pre_quarter_beat)
	BeatClock.quarter_beat.connect(_on_boss_quarter_beat)

	_in_range = true  # boss arena — player is always in combat range
	force_show_hp_bar_on_boss(true)

	_setup_floor()
	_beat1_blip = _make_blip_stream()
	_precompute_bar_quarter_starts(P1_BAR_LENGTHS)
	_active_patterns = P1_PATTERNS
	_active_bar_lengths = P1_BAR_LENGTHS
	_active_move_patterns = P1_MOVE_PATTERNS
	_active_accent_patterns = P1_ACCENT_PATTERNS
	boss.start_phase_one()
	_ring_visible_duration = BeatClock.beat_duration() * 0.25


func _max_player_hp() -> int:
	return 6


func _get_current_target() -> BaseEnemy:
	return boss


func _get_lock_on_candidates() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	if not boss.dead:
		candidates.append(boss)
	return candidates


func _get_attack_dir() -> Vector3:
	return _boss_attack_dir


func _on_ting_expired_cleanup() -> void:
	boss.hide_attack_ring()


# Override: boss level manages ting windows through _on_boss_pre_half_beat
func _on_pre_beat(_beat_number: int) -> void:
	pass


func _on_beat(beat_number: int) -> void:
	super._on_beat(beat_number)
	if _player_dead or boss.dead or boss.current_phase == BossEnemy.Phase.TRANSITIONING:
		return
	if boss.stun_beats > 0:
		boss.tick_stun()
		if boss.stun_beats == 0:
			_awaiting_stun_recovery = true


# Fires at 16th-note resolution, audio_offset early — opens ting windows for boss attacks
func _on_boss_pre_quarter_beat(quarter_beat_number: int) -> void:
	if _player_dead or boss.dead or boss.current_phase == BossEnemy.Phase.TRANSITIONING:
		return

	var bar_pos := _quarter_beat_pos_in_bar(quarter_beat_number)
	var bar: int = bar_pos[0]
	var pos: int = bar_pos[1]

	# Debug blip on every bar downbeat so you can hear if BeatClock is in phase with the music
	if pos == 0 and _beat1_blip != null:
		_make_sfx(_beat1_blip, -12.0).play()

	var pattern: Array = _active_patterns[bar] if bar < _active_patterns.size() else []
	if pos not in pattern:
		return

	if boss.stun_beats > 0 or boss.posture_broken or _awaiting_stun_recovery:
		return

	# Open ting window
	if _ting_enabled:
		_make_sfx(_ting_stream).play()

	_ting_active = true
	_ting_beat_number = quarter_beat_number

	var window_close_delay := BOSS_OK_THRESHOLD + GameSettings.audio_offset
	var captured := quarter_beat_number
	get_tree().create_timer(window_close_delay).timeout.connect(
		func(): _on_boss_ting_expired(captured)
	)

	# Update attack direction toward player, then flash ring at full extent
	var dir := player.global_position - boss.base_pos
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		_boss_attack_dir = dir.normalized()

	var accent_pattern: Array = _active_accent_patterns[bar] \
		if bar < _active_accent_patterns.size() else []
	_ting_is_accent = pos in accent_pattern
	boss.update_attack_ring(1.0, _boss_attack_dir, BossEnemy.RANGE_RADIUS, _ting_is_accent)

	# Hide the visual ring early (shorter than the ting window) so fast note chains look clean
	var ring_captured := quarter_beat_number
	get_tree().create_timer(_ring_visible_duration).timeout.connect(func():
		if _ting_beat_number == ring_captured:
			boss.hide_attack_ring()
	)

	# Retroactively confirm if the player pressed early (within PARRY_EARLY_WINDOW_SECS)
	if _last_parry_press_ms > 0.0:
		var age_ms := float(Time.get_ticks_msec()) - _last_parry_press_ms
		_last_parry_press_ms = -1.0
		if age_ms <= PARRY_EARLY_WINDOW_SECS * 1000.0:
			if _parry_circle_overlaps_attack():
				_record_top_press()
			else:
				_register_false_parry()


# Fires at actual 16th-note time — bar/position tracking and boss AI movement
func _on_boss_quarter_beat(quarter_beat_number: int) -> void:
	var bar_pos := _quarter_beat_pos_in_bar(quarter_beat_number)
	_bar_number = bar_pos[0]
	_quarter_beat_in_bar = bar_pos[1]

	if _quarter_beat_in_bar == 0:
		_awaiting_stun_recovery = false

	if _player_dead or boss.dead or boss.current_phase == BossEnemy.Phase.TRANSITIONING:
		return

	# Move on music-specified 8th-note positions (16th-note positions, always even)
	var move_pattern: Array = _active_move_patterns[_bar_number] \
		if _bar_number < _active_move_patterns.size() else []
	if _quarter_beat_in_bar in move_pattern and boss.stun_beats == 0 and not boss.knocked_back:
		var accent_pattern: Array = _active_accent_patterns[_bar_number] \
			if _bar_number < _active_accent_patterns.size() else []
		var is_accent := _quarter_beat_in_bar in accent_pattern
		var step_speed := BOSS_MOVE_SPEED * 2.0 if is_accent else float(BOSS_MOVE_SPEED)
		var dir := player.global_position - boss.base_pos
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			var bd := BeatClock.beat_duration()
			var to := boss.base_pos + dir.normalized() * step_speed * bd
			boss.start_move(boss.base_pos, to, BeatClock.get_beat_time(), BOSS_MOVE_EASE, 0.5)
		else:
			boss.cancel_move()

	# Transition check: if HP hit 0 and we're waiting for bar start
	if _awaiting_transition and _quarter_beat_in_bar == 0:
		_awaiting_transition = false
		boss.begin_transition()


func _on_boss_ting_expired(quarter_beat_number: int) -> void:
	if _ting_beat_number != quarter_beat_number or not _ting_active:
		return
	var target := boss
	if _player_dead or target.dead or target.posture_broken:
		_ting_active = false
		_ting_confirmed = false
		return
	if not _ting_confirmed and _player_in_attack_sector():
		var to_player := player.global_position - target.base_pos
		to_player.y = 0.0
		hud.show_timing("Miss", Color(1.0, 0.3, 0.3))
		var kb_dir := to_player.normalized() if to_player.length_squared() > 0.001 else Vector3.ZERO
		_take_damage(kb_dir, PLAYER_ATTACK_KB)
		_break_combo()
	_ting_active = false
	_ting_confirmed = false
	_ting_is_accent = false
	_enemy_hit_time_bt = -1.0
	boss.hide_attack_ring()


func _process(delta: float) -> void:
	super._process(delta)
	if boss.dead:
		hud.hide_boss_hp()
	else:
		hud.show_boss_hp(boss.hp, boss.max_hp, "")


func _on_player_body_contact() -> void:
	if not _player_dead and not boss.dead:
		var dir := player.global_position - boss.base_pos
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			dir = dir.normalized()
		_take_damage(dir, PLAYER_CONTACT_KB)


func _on_enemy_posture_broke() -> void:
	_enemy_hit_time_bt = -1.0
	boss.hide_attack_ring()
	_stop_ting()


func _on_enemy_died(_with_ragdoll: bool) -> void:
	BeatClock.detach_music()
	_stop_ting()
	_enemy_hit_time_bt = -1.0
	_quick_attack_pending = false
	player.set_attack_charging(false)
	_locked_on = false
	player.lock_on_target = null
	boss.hide_attack_ring()


func _on_phase_transition_pending() -> void:
	_awaiting_transition = true
	_stop_ting()
	boss.hide_attack_ring()
	hud.show_timing("Phase I clear!", Color(0.4, 1.0, 0.4))


func _on_phase_transition_started() -> void:
	_stop_ting()
	_enemy_hit_time_bt = -1.0
	boss.hide_attack_ring()
	hud.show_timing("Phase II incoming...", Color(1.0, 0.6, 0.1))


func _on_phase_two_ready() -> void:
	# Switch to phase 2 patterns and reset bar tracking
	_precompute_bar_quarter_starts(P2_BAR_LENGTHS)
	_active_patterns = P2_PATTERNS
	_active_bar_lengths = P2_BAR_LENGTHS
	_active_move_patterns = []  # phase 2 movement TBD
	_active_accent_patterns = []
	_ring_visible_duration = BeatClock.beat_duration() * 0.125
	_bar_number = 0
	_quarter_beat_in_bar = 0
	force_show_hp_bar_on_boss(true)
	hud.show_timing("Phase II", Color(1.0, 0.85, 0.1))


func _reset() -> void:
	super._reset()
	boss.reset_state()
	_boss_attack_dir = Vector3(0.0, 0.0, 1.0)
	_awaiting_transition = false
	_awaiting_stun_recovery = false
	_ting_is_accent = false
	_last_parry_press_ms = -1.0
	_bar_number = 0
	_quarter_beat_in_bar = 0
	_precompute_bar_quarter_starts(P1_BAR_LENGTHS)
	_active_patterns = P1_PATTERNS
	_active_bar_lengths = P1_BAR_LENGTHS
	_active_move_patterns = P1_MOVE_PATTERNS
	_active_accent_patterns = P1_ACCENT_PATTERNS
	boss.start_phase_one()
	_ring_visible_duration = BeatClock.beat_duration() * 0.25
	force_show_hp_bar_on_boss(true)


func force_show_hp_bar_on_boss(enable: bool) -> void:
	boss.force_show_hp_bar = enable


func _precompute_bar_quarter_starts(bar_lengths: Array) -> void:
	_bar_start_quarter_beats.clear()
	var cumulative := 0
	for length in bar_lengths:
		_bar_start_quarter_beats.append(cumulative)
		cumulative += length
	_total_loop_quarter_beats = cumulative


# Returns [bar_index, quarter_beat_within_bar]
func _quarter_beat_pos_in_bar(quarter_beat_number: int) -> Array:
	if _total_loop_quarter_beats <= 0:
		return [0, 0]
	var pos := quarter_beat_number % _total_loop_quarter_beats
	# Binary search for bar
	var lo := 0
	var hi := _bar_start_quarter_beats.size() - 1
	while lo < hi:
		var mid: int = (lo + hi + 1) >> 1
		if _bar_start_quarter_beats[mid] <= pos:
			lo = mid
		else:
			hi = mid - 1
	return [lo, pos - _bar_start_quarter_beats[lo]]


func _handle_parry_press() -> void:
	# The parry always activates (and shows its ring) on press, even with no enemy near.
	_trigger_parry_visual()
	if not _in_range:
		_register_false_parry()
		return
	if _ting_active:
		_last_parry_press_ms = -1.0
		# Valid only if the player's parry circle overlaps the boss's attack ring.
		if _parry_circle_overlaps_attack():
			_record_top_press()
		else:
			_register_false_parry()
		return
	# No active ting: buffer the press so a ting opening within PARRY_EARLY_WINDOW_SECS
	# can retroactively confirm it. If no ting fires in time, register a false parry.
	_last_parry_press_ms = float(Time.get_ticks_msec())
	var captured_ms := _last_parry_press_ms
	get_tree().create_timer(PARRY_EARLY_WINDOW_SECS).timeout.connect(func():
		if _last_parry_press_ms == captured_ms and _in_range:
			_last_parry_press_ms = -1.0
			_register_false_parry()
	)


# Boss accent attacks cover the full 360°; normal attacks are a forward half-circle.
func _get_attack_half_arc() -> float:
	return PI if _ting_is_accent else PI / 2.0


func _record_top_press() -> void:
	var qbd := BeatClock.beat_duration() * 0.25  # 16th note duration
	var raw_t := BeatClock.get_beat_time() + GameSettings.audio_offset
	var x_meas := fmod(raw_t + qbd * 0.5, qbd) - qbd * 0.5
	_add_sample(x_meas)
	var comp_dist := fmod(BeatClock.get_beat_time() + qbd * 0.5, qbd) - qbd * 0.5
	_show_parry_timing(comp_dist)


func _make_blip_stream() -> AudioStreamWAV:
	var sample_hz := 44100
	var num_samples := int(sample_hz * 0.04)  # 40 ms
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_hz
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(sample_hz)
		var env := 1.0 - float(i) / float(num_samples)
		var s := clampi(int(env * sin(TAU * 880.0 * t) * 22000), -32768, 32767)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	stream.data = data
	return stream


func _setup_floor() -> void:
	var floor_node: StaticBody3D = $Floor
	if floor_node == null:
		return
	var floor_mesh: MeshInstance3D = floor_node.get_node_or_null("MeshInstance3D")
	if floor_mesh == null:
		return
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in range(64):
		for x in range(64):
			var dark: bool = ((x >> 5) + (y >> 5)) % 2 == 0
			img.set_pixel(x, y, Color(0.14, 0.10, 0.14) if dark else Color(0.20, 0.16, 0.20))
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(20.0, 20.0, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mesh.set_surface_override_material(0, mat)
