extends BaseLevel
class_name BossLevel

const BOSS_OK_THRESHOLD := 0.18
const BOSS_MOVE_SPEED := 4
const BOSS_MOVE_EASE := 3.0
const PARRY_EARLY_WINDOW_SECS := 0.15

# beat maps: each entry is a measure, each subentry is a sixteenth note within that measure

# Phase 1 is 26 measures long, 120bpm 7/8, measures 21 and 26 are 4/8
const P1_MEASURE_LENGTHS: Array = [
	14, 14, 14, 14,
	14, 14, 14, 14,
	14, 14, 14, 14,
	14, 14, 14, 14,
	14, 14, 14, 14,
	8,
	14, 14, 14, 14,
	14,
]

const P1_PATTERNS: Array = [
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 4, 8],
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 4, 8],
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 4, 8],
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 4, 8],
	[0, 4, 8, 12],
	[0, 6, 10],
	[0, 2, 8, 12],
	[2, 4, 10],
	[0],
	[0, 4, 8, 12],
	[0, 6, 10],
	[0, 2, 8, 12],
	[2, 4, 6, 8, 10],
	[0],
]

const P1_ACCENT_PATTERNS: Array = [
	[], [], [], [4, 8],
	[], [], [], [4, 8],
	[], [], [], [4, 8],
	[], [], [], [4, 8],
	[], [], [], [],
	[0],
	[], [], [], [],
	[0],
]

const P1_MOVE_PATTERNS: Array = [
	[0, 8],
	[2, 10],
	[4, 12],
	[4, 8],
	[0, 8],
	[2, 10],
	[4, 12],
	[4, 8],
	[0, 8],
	[2, 10],
	[4, 12],
	[4, 8],
	[0, 8],
	[2, 10],
	[4, 12],
	[4, 8],
	[0, 8],
	[2, 10],
	[4, 12],
	[6],
	[0],
	[0, 18],
	[2, 10],
	[4],
	[0],
	[0],
]

# Phase 2 is 32 measures long, 140 BPM 7/8, measure 23 is 8/8
const P2_MEASURE_LENGTHS: Array = [
	14, 14, 14, 14, 14, 14, 14, 14,
	14, 14, 14, 14, 14, 14, 14, 14,
	14, 14, 14, 14, 14, 14, 14, 16,
	14, 14, 14, 14, 14, 14, 14, 14,
]

const P2_PATTERNS: Array = [
	[0, 2, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 2, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 2, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 2, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 2, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 2, 4, 8, 10, 12],
	[0, 4, 8, 10, 12],
	[0, 2, 4, 6, 8, 10, 12],
	[0, 2, 4, 6, 8, 10, 12],
	[0, 1, 2, 3, 4, 8],
	[0, 8, 12],
	[0, 2, 3, 4, 8],
	[0],
	[0, 2, 3, 4, 8, 10],
	[0, 4, 6, 8, 12],
	[0, 2, 3, 4, 8, 10],
	[0, 8, 12],
	[0, 8, 10],
	[0, 8, 12],
	[0, 8],
	[0, 8],
	[0, 4, 8, 12],
	[0, 4, 8, 12],
	[0, 4, 8, 12],
	[0],
]

const P2_MOVE_ACCENT_PATTERNS: Array = [
	[], [], [], [0],
	[], [], [], [],
	[0], [], [], [],
	[0], [], [], [0, 4, 8],
	[], [], [], [],
	[], [], [], [],
	[], [], [], [],
	[], [], [], [],
]

const P2_MOVE_PATTERNS: Array = [
	[4, 12],
	[4, 12],
	[4],
	[0, 4, 10],
	[4, 12],
	[4, 8],
	[0, 4, 8],
	[0, 2, 4, 6, 8, 10, 12],
	[0, 4, 12],
	[4, 12],
	[4],
	[0, 2, 4, 6, 8, 10, 12],
	[0, 4, 12],
	[4],
	[0, 2, 4, 6, 8, 10, 12],
	[0, 4, 8],
	[0],
	[],
	[0],
	[],
	[0],
	[],
	[0],
	[],
	[8],
	[8],
	[8],
	[8],
	[8],
	[8],
	[8],
	[0],
]

@onready var boss: BossEnemy = $Boss

var _sixteenth_in_measure: int = 0
var _measure_number: int = 0
var _measure_start_sixteenths: Array[int] = []
var _total_loop_sixteenths: int = 0
var _active_patterns: Array = []
var _active_move_patterns: Array = []
var _active_accent_patterns: Array = []
var _active_move_accent_patterns: Array = []

var _awaiting_transition: bool = false

# Posture break stuns always end on a new measure.
# It lasts STUN_MEASURES full measures, rolling its start past any
# downbeat closer than STUN_ROLLOVER_SIXTEENTHS so the window is never cut short.
const STUN_ROLLOVER_SIXTEENTHS := 8  # 2 beats; a beat is a quarter note = 4 sixteenths
const STUN_MEASURES := 2
var _stun_end_sixteenth: int = -1

var _last_parry_press_ms: float = -1.0

var _ring_visible_duration: float = 0.125

# blip on every new measure to confirm BeatClock stays in phase
var _beat1_blip: AudioStreamWAV = null


func _ready() -> void:
	_register_enemy(boss)
	boss.phase_transition_pending.connect(_on_phase_transition_pending)
	boss.phase_transition_started.connect(_on_phase_transition_started)
	boss.phase_two_ready.connect(_on_phase_two_ready)

	super._ready()

	# boss attacks are separate from BeatClock attack timings, probably consolidate this later
	BeatClock.pre_beat.disconnect(_on_pre_beat)
	BeatClock.pre_sixteenth.connect(_on_boss_pre_sixteenth)
	BeatClock.sixteenth.connect(_on_boss_sixteenth)

	boss.force_show_hp_bar = true

	_setup_floor()
	_beat1_blip = _make_blip_stream()
	_load_phase_one()


func _max_player_hp() -> int:
	return 6


func _get_current_target() -> BaseEnemy:
	return boss


func _get_lock_on_candidates() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	if not boss.dead:
		candidates.append(boss)
	return candidates


func _parry_window_seconds() -> float:
	return BeatClock.beat_duration() * 0.25


func _attack_grid_seconds() -> float:
	return BeatClock.beat_duration() * 0.5


func _default_windup_steps() -> int:
	return 2


# todo consolidate
func _on_pre_beat(_beat_number: int) -> void:
	pass


func _on_boss_pre_sixteenth(sixteenth_number: int) -> void:
	if player.is_dead() or boss.dead or boss.current_phase == BossEnemy.Phase.TRANSITIONING:
		return

	if _stun_end_sixteenth >= 0 and sixteenth_number > _stun_end_sixteenth and boss.stun_beats > 0:
		boss.end_stun()
		_stun_end_sixteenth = -1

	var measure_pos := _sixteenth_pos_in_measure(sixteenth_number)
	var measure: int = measure_pos[0]
	var pos: int = measure_pos[1]

	if pos == 0 and _beat1_blip != null:
		_make_sfx(_beat1_blip, -12.0).play()

	var pattern: Array = _active_patterns[measure] if measure < _active_patterns.size() else []
	if pos not in pattern:
		return
	if boss.stun_beats > 0 or boss.posture_broken:
		return

	if _ting_enabled:
		_make_sfx(_ting_stream).play()
	_parry_window_open = true
	_parry_window_id = sixteenth_number
	var captured := sixteenth_number
	get_tree().create_timer(BOSS_OK_THRESHOLD + GameSettings.audio_offset).timeout.connect(
		func(): _resolve_boss_parry_window(captured)
	)

	# Aim at the player; accents cover the full circle.
	var is_accent: bool = pos in _accent_positions(measure)
	boss.aim_attack(player.global_position - boss.base_pos, PI if is_accent else PI / 2.0)
	boss.update_attack_ring(1.0)

	# Hide the visual ring early so fast note chains read cleanly.
	get_tree().create_timer(_ring_visible_duration).timeout.connect(func():
		if _parry_window_id == captured:
			boss.hide_attack_ring()
	)

	# Retroactively confirm a press buffered just before this window opened.
	if _last_parry_press_ms > 0.0:
		var age_ms := float(Time.get_ticks_msec()) - _last_parry_press_ms
		_last_parry_press_ms = -1.0
		if age_ms <= PARRY_EARLY_WINDOW_SECS * 1000.0:
			if _parry_circle_overlaps_attack():
				_record_parry_timing()
			else:
				_register_false_parry()


# Fires at the real 16th-note, for measure tracking and boss movement.
func _on_boss_sixteenth(sixteenth_number: int) -> void:
	var measure_pos := _sixteenth_pos_in_measure(sixteenth_number)
	_measure_number = measure_pos[0]
	_sixteenth_in_measure = measure_pos[1]

	if player.is_dead() or boss.dead or boss.current_phase == BossEnemy.Phase.TRANSITIONING:
		return

	var move_pattern: Array = _active_move_patterns[_measure_number] \
		if _measure_number < _active_move_patterns.size() else []
	if _enemy_move_enabled and _sixteenth_in_measure in move_pattern and boss.stun_beats == 0 and not boss.knocked_back:
		var is_accent: bool = _sixteenth_in_measure in _move_accent_positions(_measure_number)
		var step_speed := BOSS_MOVE_SPEED * 2.0 if is_accent else float(BOSS_MOVE_SPEED)
		var dir := player.global_position - boss.base_pos
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			var to := boss.base_pos + dir.normalized() * step_speed * BeatClock.beat_duration()
			boss.start_move(boss.base_pos, to, BeatClock.get_beat_time(), BOSS_MOVE_EASE, 0.5)
		else:
			boss.cancel_move()

	if _awaiting_transition and _sixteenth_in_measure == 0:
		_awaiting_transition = false
		boss.begin_transition()


func _resolve_boss_parry_window(window_id: int) -> void:
	if _parry_window_id != window_id or not _parry_window_open:
		return
	if player.is_dead() or boss.dead or boss.posture_broken:
		_close_parry_window()
		return
	if not _parry_landed and _player_in_attack_sector():
		var to_player := player.global_position - boss.base_pos
		to_player.y = 0.0
		var kb_dir := to_player.normalized() if to_player.length_squared() > 0.001 else Vector3.ZERO
		hud.show_timing("Miss", Color(1.0, 0.3, 0.3))
		_damage_player(kb_dir, PLAYER_ATTACK_KB)
	_close_parry_window()
	boss.hide_attack_ring()


func _process(delta: float) -> void:
	super._process(delta)
	if boss.dead:
		hud.hide_boss_hp()
	else:
		hud.show_boss_hp(boss.hp, boss.max_hp, boss.pending_hp)


# Replace the default beat-count stun with one held until a measure downbeat, so the boss
# always recovers (and attacks resume) on a '1'.
func _on_enemy_posture_broke(enemy: BaseEnemy) -> void:
	super._on_enemy_posture_broke(enemy)
	var sixteenth_secs := BeatClock.beat_duration() * 0.25
	var now_sixteenth := int(BeatClock.get_beat_time() / sixteenth_secs)
	_stun_end_sixteenth = _stun_end_target_sixteenth(now_sixteenth)
	boss.stun_until(_stun_end_sixteenth * sixteenth_secs)


# The downbeat the stun ends on: the first '1' past the rollover buffer, then extended to a
# full STUN_MEASURES so the player has time to charge and land the crit.
func _stun_end_target_sixteenth(now_sixteenth: int) -> int:
	var target := _next_measure_start_sixteenth(now_sixteenth + STUN_ROLLOVER_SIXTEENTHS)
	for _i in range(STUN_MEASURES - 1):
		target = _next_measure_start_sixteenth(target + 1)
	return target


# Earliest absolute 16th-note index that is a measure downbeat at or after from_sixteenth.
func _next_measure_start_sixteenth(from_sixteenth: int) -> int:
	if _total_loop_sixteenths <= 0:
		return from_sixteenth
	var loop_index := int(floor(float(from_sixteenth) / _total_loop_sixteenths))
	for k in range(loop_index, loop_index + 2):
		var base := k * _total_loop_sixteenths
		for start in _measure_start_sixteenths:
			if base + start >= from_sixteenth:
				return base + start
	return from_sixteenth


# Boss-specific parry input (with early-press buffer)

func _handle_parry_press() -> void:
	_trigger_parry_visual()
	if _parry_window_open:
		_last_parry_press_ms = -1.0
		if _parry_circle_overlaps_attack():
			_record_parry_timing()
		else:
			_register_false_parry()
		return
	# No open window: buffer the press for retroactive confirmation, else a false parry.
	_last_parry_press_ms = float(Time.get_ticks_msec())
	var captured_ms := _last_parry_press_ms
	get_tree().create_timer(PARRY_EARLY_WINDOW_SECS).timeout.connect(func():
		if _last_parry_press_ms == captured_ms:
			_last_parry_press_ms = -1.0
			_register_false_parry()
	)


# Phase flow

func _on_phase_transition_pending() -> void:
	_awaiting_transition = true
	boss.end_stun()
	_stun_end_sixteenth = -1
	_close_parry_window()
	boss.hide_attack_ring()


func _on_phase_transition_started() -> void:
	_close_parry_window()
	boss.hide_attack_ring()


func _on_phase_two_ready() -> void:
	_precompute_measure_starts(P2_MEASURE_LENGTHS)
	_active_patterns = P2_PATTERNS
	_active_move_patterns = P2_MOVE_PATTERNS
	_active_move_accent_patterns = P2_MOVE_ACCENT_PATTERNS
	_active_accent_patterns = P2_MOVE_ACCENT_PATTERNS
	_ring_visible_duration = BeatClock.beat_duration() * 0.125
	_measure_number = 0
	_sixteenth_in_measure = 0
	boss.force_show_hp_bar = true


func _reset() -> void:
	super._reset()
	boss.reset_state()
	_awaiting_transition = false
	_stun_end_sixteenth = -1
	_last_parry_press_ms = -1.0
	_measure_number = 0
	_sixteenth_in_measure = 0
	_load_phase_one()
	boss.force_show_hp_bar = true


func _load_phase_one() -> void:
	_precompute_measure_starts(P1_MEASURE_LENGTHS)
	_active_patterns = P1_PATTERNS
	_active_move_patterns = P1_MOVE_PATTERNS
	_active_accent_patterns = P1_ACCENT_PATTERNS
	_active_move_accent_patterns = P1_ACCENT_PATTERNS
	_ring_visible_duration = BeatClock.beat_duration() * 0.25
	boss.start_phase_one()


func _accent_positions(measure: int) -> Array:
	return _active_accent_patterns[measure] if measure < _active_accent_patterns.size() else []


func _move_accent_positions(measure: int) -> Array:
	return _active_move_accent_patterns[measure] if measure < _active_move_accent_patterns.size() else []


func _precompute_measure_starts(measure_lengths: Array) -> void:
	_measure_start_sixteenths.clear()
	var cumulative := 0
	for length in measure_lengths:
		_measure_start_sixteenths.append(cumulative)
		cumulative += length
	_total_loop_sixteenths = cumulative


# Returns [measure_index, sixteenth_within_measure].
func _sixteenth_pos_in_measure(sixteenth_number: int) -> Array:
	if _total_loop_sixteenths <= 0:
		return [0, 0]
	var pos := sixteenth_number % _total_loop_sixteenths
	var lo := 0
	var hi := _measure_start_sixteenths.size() - 1
	while lo < hi:
		var mid: int = (lo + hi + 1) >> 1
		if _measure_start_sixteenths[mid] <= pos:
			lo = mid
		else:
			hi = mid - 1
	return [lo, pos - _measure_start_sixteenths[lo]]


func _make_blip_stream() -> AudioStreamWAV:
	var sample_hz := 44100
	var num_samples := int(sample_hz * 0.04) # 40 ms
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
