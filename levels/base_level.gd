extends Node3D
class_name BaseLevel

const SAMPLE_COUNT := 10
const PERFECT_THRESHOLD := 0.066
const OK_THRESHOLD := 0.20
const MISS_DECAY_TIME := 0.5
const PENALTY_PER_MISS := 0.033
const DPAD_INITIAL_DELAY := 0.4
const DPAD_REPEAT_INTERVAL := 0.08
const DEFAULT_PLAYER_HP := 3

const PLAYER_CONTACT_KB := 3.5
const PLAYER_ATTACK_KB := 9.0
const ENEMY_KB_SPEED := 3.0
const ENEMY_KB_VERTICAL := 5.0
const ENEMY_PARRY_HOP := 3.0

const ATTACK_PRECISION_PERFECT: float = 1.5
const ATTACK_PRECISION_OK: float = 1.0
const ATTACK_PRECISION_MISS: float = 0.1
const ATTACK_MAX_CHARGE_BEATS := 3.0
const CRIT_DAMAGE_MULT: float = 3.0

# A parry connects when the player's parry circle (drawn under them during a parry window)
# overlaps the enemy's red attack indicator.
const PARRY_RANGE := 2.5
const PARRY_ACTIVE_SECS := 0.18
# Reach of the player's melee attack, drawn as the charge/quick attack indicator border.
const PLAYER_ATTACK_RANGE := 4.5
const PLAYER_ATTACK_HALF_ARC := PI / 6.0

@onready var hud: HUD = $HUD
@onready var player: Player = $Player

var _in_range: bool = false
var _samples: Array[float] = []
var _current_avg: float = 0.0

var _ting_stream: AudioStream
var _parry_stream: AudioStream
var _oof_stream: AudioStream
var _miss_stream: AudioStream
var _crit_hit_stream: AudioStream

# The parry window is the brief span around an enemy attack during which a press parries it.
var _parry_window_open: bool = false
var _parry_window_id: int = -1
var _parry_landed: bool = false
# Toggled globally by "toggle_ting" / "toggle_move"; the move flag only affects enemies.
var _ting_enabled: bool = true
var _enemy_move_enabled: bool = true

var _recent_misses: Array[float] = []
var _dpad_timer: float = -1.0

var _attack_active: bool = false
var _attack_start_bt: float = -1.0
var _quick_attack_pending: bool = false
var _quick_attack_start_bt: float = -1.0
var _quick_attack_fire_bt: float = -1.0
# A riposte (faster quick attack) is queued for a short window after a successful parry.
var _riposte_ready: bool = false
var _riposte_until_bt: float = -1.0

var _combo: int = 0
var _locked_on: bool = false
var _player_ragdoll: RigidBody3D = null
var _parry_visual_until_ms: float = -1.0

var _player_range_ring_inst: MeshInstance3D = null
var _player_attack_ring_inst: MeshInstance3D = null
var _player_attack_ring_mat: StandardMaterial3D = null
var _player_arc_outline_mat: StandardMaterial3D = null
var _player_iframe_ring_inst: MeshInstance3D = null
var _player_iframe_ring_mat: StandardMaterial3D = null
var _player_parry_ring_inst: MeshInstance3D = null
var _player_parry_fill_mat: StandardMaterial3D = null
var _player_parry_outline_mat: StandardMaterial3D = null


func _ready() -> void:
	_ting_stream = load("res://assets/audio/sfx/ting.mp3")
	_parry_stream = load("res://assets/audio/sfx/parry.mp3")
	_oof_stream = load("res://assets/audio/sfx/oof.mp3")
	_miss_stream = _load_optional_sfx("res://assets/audio/sfx/miss.mp3")
	_crit_hit_stream = _load_optional_sfx("res://assets/audio/sfx/crit_hit.mp3")

	BeatClock.beat.connect(_on_beat)
	BeatClock.pre_beat.connect(_on_pre_beat)

	player.hp_changed.connect(_on_player_hp_changed)
	player.died.connect(_on_player_died)
	player.configure_max_hp(_max_player_hp())

	_setup_player_rings()

	hud.update_calibration(0.0, GameSettings.audio_offset * 1000.0, false)
	hud.update_combo(0)
	hud.set_ting_enabled(_ting_enabled)


# Per-level hooks

func _max_player_hp() -> int:
	return DEFAULT_PLAYER_HP


func _get_current_target() -> BaseEnemy:
	return null


func _get_lock_on_candidates() -> Array[Node3D]:
	return []


# Wire an enemy's shared signals into the generic combat handlers. Levels call this for each
# enemy they spawn; enemy-specific signals (like boss phases) connect separately.
func _register_enemy(enemy: BaseEnemy) -> void:
	enemy.player_entered_range.connect(func(): _in_range = true)
	enemy.player_exited_range.connect(func(): _in_range = false; _close_parry_window())
	enemy.player_body_contact.connect(_on_enemy_body_contact.bind(enemy))
	enemy.posture_broke.connect(_on_enemy_posture_broke.bind(enemy))
	enemy.died.connect(_on_enemy_died.bind(enemy))


# Frame update

func _process(delta: float) -> void:
	_handle_calibration_input(delta)
	# The parry ring runs on wall-clock time so it stays correct even while music is detached.
	_update_parry_ring()

	var bt := BeatClock.get_beat_time()
	if bt < 0.0:
		return

	if _quick_attack_pending and bt >= _quick_attack_fire_bt:
		_fire_quick_attack()

	_update_lock_on()
	_update_iframe_visuals()
	_update_player_attack_ring(bt)


func _update_lock_on() -> void:
	var target := _get_current_target()
	if _locked_on and (target == null or target.dead or not is_instance_valid(player.lock_on_target)):
		_locked_on = false
		player.lock_on_target = null
		if target != null:
			target.set_lock_on_highlighted(false)
			target.force_show_hp_bar = false
	if target != null:
		target.set_lock_on_highlighted(_locked_on)
		target.force_show_hp_bar = _locked_on
		target.tracked_position = player.global_position


func _update_iframe_visuals() -> void:
	if not player.is_iframe():
		hud.update_iframe_bar(0.0)
		_player_iframe_ring_inst.visible = false
		return
	var progress := player.iframe_progress()
	# The HUD i-frame bar is the dash readout; hit i-frames only show the ground ring.
	hud.update_iframe_bar(progress if player.is_dash_iframe() else 0.0)
	var mesh := ImmediateMesh.new()
	RingMesh.add_annulus_sweep(mesh, _player_iframe_ring_mat, 0.37, 0.53, 0.0, progress * TAU, 0.0, 48)
	_player_iframe_ring_inst.mesh = mesh
	_player_iframe_ring_inst.global_position = Vector3(player.global_position.x, 0.01, player.global_position.z)
	_player_iframe_ring_inst.visible = progress > 0.01


func _update_player_attack_ring(bt: float) -> void:
	if not (_attack_active or _quick_attack_pending):
		_player_range_ring_inst.visible = false
		_player_attack_ring_inst.visible = false
		return
	var ring_pos := Vector3(player.global_position.x, 0.01, player.global_position.z)
	var pfwd := player.global_transform.basis * Vector3(0.0, 0.0, -1.0)
	pfwd.y = 0.0
	pfwd = pfwd.normalized() if pfwd.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)
	var arc_center := atan2(pfwd.x, pfwd.z)
	var bd := BeatClock.beat_duration()
	var fill_radius: float
	if _attack_active:
		var charge_ratio := clampf((bt - _attack_start_bt) / (ATTACK_MAX_CHARGE_BEATS * bd), 0.0, 1.0)
		fill_radius = charge_ratio * PLAYER_ATTACK_RANGE
	else:
		# Quick attack: the ring fills across its windup so the landing pulse is readable.
		var span := maxf(_quick_attack_fire_bt - _quick_attack_start_bt, 0.001)
		fill_radius = clampf((bt - _quick_attack_start_bt) / span, 0.0, 1.0) * PLAYER_ATTACK_RANGE

	var fill := ImmediateMesh.new()
	RingMesh.add_sector_fill(fill, _player_attack_ring_mat, fill_radius, arc_center, PLAYER_ATTACK_HALF_ARC, 0.0, 24)
	_player_attack_ring_inst.mesh = fill
	_player_attack_ring_inst.global_position = ring_pos
	_player_attack_ring_inst.visible = fill_radius > 0.01

	var outline := ImmediateMesh.new()
	RingMesh.add_sector_outline(outline, _player_arc_outline_mat, PLAYER_ATTACK_RANGE, arc_center, PLAYER_ATTACK_HALF_ARC, 0.0, 16)
	_player_range_ring_inst.mesh = outline
	_player_range_ring_inst.global_position = ring_pos
	_player_range_ring_inst.visible = true


func _handle_calibration_input(delta: float) -> void:
	var dir := 0
	if Input.is_action_pressed("offset_decrease"): dir = -1
	elif Input.is_action_pressed("offset_increase"): dir = 1
	if dir == 0:
		_dpad_timer = -1.0
		return
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


# Enemy attack windows (default: attack on every measure downbeat)

func _on_beat(_beat_number: int) -> void:
	pass


func _on_pre_beat(beat_number: int) -> void:
	var target := _get_current_target()
	if not _in_range or beat_number % 4 != 0 or player.is_dead() or (target != null and target.dead):
		return
	if _ting_enabled:
		_make_sfx(_ting_stream).play()
	_open_parry_window(beat_number, OK_THRESHOLD - GameSettings.audio_offset)


func _open_parry_window(window_id: int, close_delay: float) -> void:
	_parry_window_open = true
	_parry_window_id = window_id
	# A large audio offset can push close_delay to zero or negative, which would close the
	# window instantly. Keep it open at least as long as the timing tolerance.
	get_tree().create_timer(maxf(close_delay, OK_THRESHOLD)).timeout.connect(func(): _resolve_parry_window(window_id))


func _resolve_parry_window(window_id: int) -> void:
	if _parry_window_id != window_id or not _parry_window_open:
		return
	var target := _get_current_target()
	if player.is_dead() or (target != null and (target.dead or target.posture_broken)):
		_close_parry_window()
		return
	if not _parry_landed and _player_in_attack_sector():
		var target_pos := target.base_pos if target != null else Vector3.ZERO
		var to_player := player.global_position - target_pos
		to_player.y = 0.0
		var kb_dir := to_player.normalized() if to_player.length_squared() > 0.001 else Vector3.ZERO
		hud.show_timing("Miss", Color(1.0, 0.3, 0.3))
		_damage_player(kb_dir, PLAYER_ATTACK_KB)
	_close_parry_window()
	if target != null:
		target.hide_attack_ring()


func _close_parry_window() -> void:
	_parry_window_open = false
	_parry_landed = false


# Generic enemy event handlers

func _on_enemy_body_contact(enemy: BaseEnemy) -> void:
	if player.is_dead() or enemy.dead:
		return
	var dir := player.global_position - enemy.base_pos
	dir.y = 0.0
	if dir.length_squared() > 0.001:
		dir = dir.normalized()
	_damage_player(dir, PLAYER_CONTACT_KB)


func _on_enemy_posture_broke(enemy: BaseEnemy) -> void:
	enemy.hide_attack_ring()
	_close_parry_window()


func _on_enemy_died(_with_ragdoll: bool, enemy: BaseEnemy) -> void:
	BeatClock.detach_music()
	_close_parry_window()
	_quick_attack_pending = false
	player.set_attack_charging(false)
	_locked_on = false
	player.lock_on_target = null
	enemy.hide_attack_ring()


# Input

func _unhandled_input(event: InputEvent) -> void:
	if player.is_dead():
		if event.is_action_pressed("reset_level"):
			_reset()
		return

	if event.is_action_pressed("parry"):
		_cancel_player_attack()
		_handle_parry_press()
	elif event.is_action_pressed("quick_attack"):
		# While holding parry, a quick-attack tap parries instead of attacking, once on
		# press and once on release, for two extra parries. The charge attack never parries.
		if Input.is_action_pressed("parry"):
			_handle_parry_press()
		else:
			_handle_quick_attack_press()
	elif event.is_action_released("quick_attack"):
		if Input.is_action_pressed("parry"):
			_handle_parry_press()
	elif event.is_action_pressed("charge_attack"):
		_handle_attack_press()
	elif event.is_action_released("charge_attack"):
		_release_player_attack()
	elif event.is_action_pressed("dash"):
		_handle_dash_press()
	elif event.is_action_pressed("reset_level"):
		_reset()
	elif event.is_action_pressed("lock_on"):
		_toggle_lock_on()
	elif event.is_action_pressed("toggle_ting"):
		_toggle_ting()
	elif event.is_action_pressed("toggle_move"):
		_toggle_enemy_move()
	else:
		_handle_extra_input(event)


func _toggle_ting() -> void:
	_ting_enabled = not _ting_enabled
	hud.set_ting_enabled(_ting_enabled)


func _toggle_enemy_move() -> void:
	_enemy_move_enabled = not _enemy_move_enabled
	if not _enemy_move_enabled:
		var target := _get_current_target()
		if target != null:
			target.cancel_move()
	hud.show_timing("Move: %s" % ("ON" if _enemy_move_enabled else "OFF"), Color(0.8, 0.8, 0.8))


func _handle_extra_input(_event: InputEvent) -> void:
	pass


func _toggle_lock_on() -> void:
	if _locked_on:
		var old_target := _get_current_target()
		if old_target != null:
			old_target.set_lock_on_highlighted(false)
			old_target.force_show_hp_bar = false
		_locked_on = false
		player.lock_on_target = null
	else:
		var target := _pick_lock_on_target(_get_lock_on_candidates())
		if target:
			_locked_on = true
			player.lock_on_target = target


func _handle_dash_press() -> void:
	if player.is_dead() or player.is_iframe():
		return
	var h_vel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var dash_dir: Vector3
	if h_vel.length_squared() > 0.25:
		dash_dir = h_vel.normalized()
	else:
		var fwd := player.global_transform.basis * Vector3(0.0, 0.0, -1.0)
		fwd.y = 0.0
		dash_dir = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)
	player.start_dash(dash_dir)


# Parry

func _handle_parry_press() -> void:
	# The parry always activates (and shows its ring) on press, even with no enemy near.
	_trigger_parry_visual()
	# Out of range, or a telegraphed attack the parry can't reach, is a false parry.
	if not _in_range or (_parry_window_open and not _parry_circle_overlaps_attack()):
		_register_false_parry()
		return
	_record_parry_timing()


func _trigger_parry_visual() -> void:
	_parry_visual_until_ms = float(Time.get_ticks_msec()) + PARRY_ACTIVE_SECS * 1000.0


# A mistimed or out-of-reach parry. Costs the combo, except while the player is mashing
# through an attack chain on a posture-broken enemy.
func _register_false_parry() -> void:
	if _combo_protected():
		return
	hud.show_timing("False Parry", Color(1.0, 0.3, 0.3))
	_break_combo()


# A press inside an open parry window: measure timing, rate it, and feed calibration samples.
func _record_parry_timing() -> void:
	var window := _parry_window_seconds()
	var raw_t := BeatClock.get_beat_time() + GameSettings.audio_offset
	_add_sample(fmod(raw_t + window * 0.5, window) - window * 0.5)
	var comp_dist := fmod(BeatClock.get_beat_time() + window * 0.5, window) - window * 0.5
	_rate_parry(comp_dist)


# The note grid the parry is timed against. Default is the measure; the boss overrides to 16ths.
func _parry_window_seconds() -> float:
	return BeatClock.beat_duration() * 4.0


func _rate_parry(dist: float) -> void:
	var effective_ok := _get_effective_ok_threshold()
	var abs_dist := absf(dist)
	var target := _get_current_target()
	if abs_dist <= PERFECT_THRESHOLD:
		hud.show_timing("Perfect!", Color(1.0, 0.9, 0.1))
		_confirm_parry(target, 1.5, dist)
	elif abs_dist <= effective_ok:
		hud.show_timing("OK", Color(0.3, 1.0, 0.3))
		_confirm_parry(target, 1.0, dist)
	else:
		hud.show_timing("Early" if dist < 0.0 else "Late", Color(1.0, 0.6, 0.2))
		_record_miss()
		if not _combo_protected():
			_break_combo()
		_close_parry_window()


func _confirm_parry(target: BaseEnemy, posture_gain: float, dist: float) -> void:
	_parry_landed = true
	_riposte_ready = true
	_riposte_until_bt = BeatClock.get_beat_time() + _attack_grid_seconds()
	_clear_misses()
	_increment_combo()
	_play_parry_response(dist)
	if target != null:
		target.fall_vel = maxf(target.fall_vel, ENEMY_PARRY_HOP)
		target.accumulate_posture(posture_gain)


# True while the player is mid-punish on a posture-broken enemy, so mistimed or false
# parries don't cost the combo before the player lands the critical hit.
func _combo_protected() -> bool:
	var target := _get_current_target()
	return target != null and target.posture_broken


# Attack-sector geometry (read from the enemy's telegraph)

# True if the player's parry circle overlaps the active attack sector.
func _parry_circle_overlaps_attack() -> bool:
	var target := _get_current_target()
	if target == null:
		return false
	var to_player := player.global_position - target.base_pos
	to_player.y = 0.0
	var d := to_player.length()
	if d > target.attack_radius + PARRY_RANGE:
		return false
	if target.attack_half_arc >= PI or d < 0.001:
		return true
	var ang := acos(clampf(target.attack_dir.dot(to_player / d), -1.0, 1.0))
	# The parry circle widens the angular reach by the angle it subtends at distance d.
	var ang_margin := asin(clampf(PARRY_RANGE / maxf(d, PARRY_RANGE), 0.0, 1.0))
	return ang <= target.attack_half_arc + ang_margin


# True if the player's body sits inside the active attack sector (used for taking damage).
func _player_in_attack_sector() -> bool:
	var target := _get_current_target()
	if target == null:
		return false
	var to_player := player.global_position - target.base_pos
	to_player.y = 0.0
	var d := to_player.length()
	if d > target.attack_radius:
		return false
	if target.attack_half_arc >= PI or d < 0.001:
		return true
	return target.attack_dir.dot(to_player / d) >= cos(target.attack_half_arc)


# True if an enemy sits inside the player's melee attack arc.
func _target_in_attack_reach(target: BaseEnemy) -> bool:
	if target == null:
		return false
	var to_target := target.base_pos - player.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return true
	if to_target.length() > PLAYER_ATTACK_RANGE:
		return false
	var fwd := player.global_transform.basis * Vector3(0.0, 0.0, -1.0)
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)
	return fwd.dot(to_target.normalized()) >= cos(PLAYER_ATTACK_HALF_ARC)


# Player attacks

func _cancel_player_attack() -> void:
	_attack_active = false
	_attack_start_bt = -1.0
	_quick_attack_pending = false
	player.set_attack_charging(false)


func _handle_attack_press() -> void:
	if _attack_active or _quick_attack_pending:
		return
	_attack_active = true
	_attack_start_bt = BeatClock.get_beat_time()
	player.set_attack_charging(true)


# The grid the player's attacks resolve on. Default is the quarter note; the boss overrides
# to the eighth-note pulse so attacks can be woven into its attack gaps.
func _attack_grid_seconds() -> float:
	return BeatClock.beat_duration()


# Grid steps a plain quick attack takes to land. The boss overrides to 2 (an eighth pair).
func _default_windup_steps() -> int:
	return 1


# A fresh parry shortens the next quick attack to a single grid step (the riposte).
func _quick_attack_windup_steps() -> int:
	if _riposte_ready and BeatClock.get_beat_time() < _riposte_until_bt:
		return 1
	return _default_windup_steps()


func _handle_quick_attack_press() -> void:
	var target := _get_current_target()
	if _attack_active or _quick_attack_pending or (target != null and target.dead):
		return
	var g := _attack_grid_seconds()
	var bt := BeatClock.get_beat_time()
	var windup := _quick_attack_windup_steps()
	_riposte_ready = false
	_quick_attack_start_bt = bt
	_quick_attack_fire_bt = (floor(bt / g) + windup) * g
	_quick_attack_pending = true
	player.set_attack_charging(true)


func _fire_quick_attack() -> void:
	_quick_attack_pending = false
	player.set_attack_charging(false)
	var target := _get_current_target()
	if target == null or target.dead or not _in_range or not _target_in_attack_reach(target):
		_break_combo()
		return
	var damage := 1.0
	target.hp = maxf(target.hp - damage, 0.0)
	target.spawn_damage_number(damage, false)
	_increment_combo()
	target.accumulate_posture(0.5)
	target.apply_stun(1)
	_make_sfx(_ting_stream).play()
	_knock_back_enemy(target, ENEMY_KB_SPEED, ENEMY_KB_VERTICAL * 0.3)
	if target.hp <= 0.0:
		target.kill(true)


func _release_player_attack() -> void:
	if not _attack_active or player.is_dead():
		return
	_attack_active = false
	player.set_attack_charging(false)

	var bt := BeatClock.get_beat_time()
	var bd := BeatClock.beat_duration()
	var charge_secs := clampf(bt - _attack_start_bt, 0.0, ATTACK_MAX_CHARGE_BEATS * bd)

	# Release timing is rated against the attack grid (eighths for the boss).
	var grid := _attack_grid_seconds()
	var dist := fmod(bt + grid * 0.5, grid) - grid * 0.5
	var abs_dist := absf(dist)
	var effective_ok := _get_effective_ok_threshold()
	var timing_mult: float
	var timing_label: String
	var timing_color: Color
	if abs_dist <= PERFECT_THRESHOLD:
		timing_mult = ATTACK_PRECISION_PERFECT
		timing_label = "Perfect!"
		timing_color = Color(1.0, 0.9, 0.1)
	elif abs_dist <= effective_ok:
		timing_mult = ATTACK_PRECISION_OK
		timing_label = "OK"
		timing_color = Color(0.3, 1.0, 0.3)
	else:
		timing_mult = ATTACK_PRECISION_MISS
		timing_label = "Early" if dist < 0.0 else "Late"
		timing_color = Color(1.0, 0.6, 0.2)

	hud.show_timing(timing_label, timing_color)

	var damage := maxf(float(_combo) * timing_mult * charge_secs, 1.0)
	if timing_mult < ATTACK_PRECISION_OK:
		_record_miss()
	else:
		_clear_misses()
	_combo = 0
	hud.update_combo(0)

	var target := _get_current_target()
	var in_reach := target != null and _target_in_attack_reach(target)
	var target_dead := target.dead if target != null else true
	var is_clash := _parry_window_open and not _parry_landed and _in_range and in_reach and not target_dead

	if target != null and _in_range and in_reach and not target_dead:
		var is_crit := target.posture_broken
		if is_crit:
			target.posture_broken = false
			if _crit_hit_stream:
				_make_sfx(_crit_hit_stream, -10.0).play()
		else:
			_make_sfx(_ting_stream).play()
		var actual_damage := damage * (CRIT_DAMAGE_MULT if is_crit else 1.0)
		target.hp = maxf(target.hp - actual_damage, 0.0)
		target.spawn_damage_number(actual_damage, is_crit)
		target.apply_stun(1)
		if not is_crit:
			target.accumulate_posture(timing_mult * 0.5)
		var kb_cap := 50.0 if is_crit else 30.0
		var kb_speed := minf(pow(maxf(actual_damage, 0.01), maxf(charge_secs, 0.1)), kb_cap)
		var charge_ratio := clampf(charge_secs / (ATTACK_MAX_CHARGE_BEATS * bd), 0.3, 1.0)
		_knock_back_enemy(target, kb_speed, ENEMY_KB_VERTICAL * (3.0 if is_crit else 1.0) * charge_ratio)
		if target.hp <= 0.0:
			target.kill(true)
	elif _miss_stream and not target_dead:
		_make_sfx(_miss_stream).play()

	if is_clash:
		var player_kb_dir := player.global_position - target.base_pos
		player_kb_dir.y = 0.0
		if player_kb_dir.length_squared() > 0.001:
			player_kb_dir = player_kb_dir.normalized()
		_damage_player(player_kb_dir, PLAYER_ATTACK_KB)
		_parry_window_open = false


func _knock_back_enemy(target: BaseEnemy, speed: float, vertical: float) -> void:
	var kb_dir := target.base_pos - player.global_position
	kb_dir.y = 0.0
	if kb_dir.length_squared() > 0.001:
		target.apply_knockback(kb_dir.normalized() * speed, vertical)


# Player damage and death

func _damage_player(knockback_dir: Vector3 = Vector3.ZERO, knockback_speed: float = 0.0) -> void:
	if not player.take_damage(knockback_dir, knockback_speed):
		return
	_make_sfx(_oof_stream).play()
	_break_combo()


func _on_player_hp_changed(hp: int, max_hp: int) -> void:
	hud.set_max_hp(max_hp)
	hud.update_hp(hp)


func _on_player_died() -> void:
	_attack_active = false
	_quick_attack_pending = false
	player.set_attack_charging(false)
	_player_ragdoll = _spawn_ragdoll(
		player.global_position, player.velocity,
		Vector3(0.8, 1.8, 0.4), Color(0.1, 0.8, 0.2)
	)
	hud.show_dead()


# Reset

func _reset() -> void:
	player.reset()
	_samples.clear()
	_current_avg = 0.0
	_recent_misses.clear()
	_close_parry_window()
	_attack_active = false
	_quick_attack_pending = false
	_attack_start_bt = -1.0
	_quick_attack_start_bt = -1.0
	_quick_attack_fire_bt = -1.0
	_riposte_ready = false
	_riposte_until_bt = -1.0
	_combo = 0
	_parry_visual_until_ms = -1.0
	hud.update_iframe_bar(0.0)
	_in_range = false
	_locked_on = false
	player.lock_on_target = null
	if _player_ragdoll:
		_player_ragdoll.queue_free()
		_player_ragdoll = null
	_player_range_ring_inst.visible = false
	_player_attack_ring_inst.visible = false
	_player_iframe_ring_inst.visible = false
	_player_parry_ring_inst.visible = false
	hud.update_calibration(0.0, GameSettings.audio_offset * 1000.0, false)
	hud.update_combo(0)
	hud.clear_dead()


# Combo and calibration helpers

func _increment_combo() -> void:
	_combo += 1
	hud.update_combo(_combo)


func _break_combo() -> void:
	if _combo > 0:
		_combo = 0
		hud.update_combo(0)


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


func _play_parry_response(dist: float) -> void:
	if not _ting_enabled:
		return
	var p := _make_sfx(_parry_stream)
	# Late parries within the OK window read as a slightly higher, quieter ring.
	if dist > PERFECT_THRESHOLD:
		var t := clampf((dist - PERFECT_THRESHOLD) / (OK_THRESHOLD - PERFECT_THRESHOLD), 0.0, 1.0)
		p.pitch_scale = lerpf(1.0, 1.25, t)
		p.volume_db = lerpf(-20.0, -25.0, t)
	p.play()


# Lock-on

func _pick_lock_on_target(candidates: Array[Node3D]) -> Node3D:
	const MAX_DIST := 20.0
	const MAX_ANGLE := PI * 0.7
	var cam_fwd := -player.camera.global_transform.basis.z
	var cam_fwd_flat := Vector3(cam_fwd.x, 0.0, cam_fwd.z)
	cam_fwd_flat = cam_fwd_flat.normalized() if cam_fwd_flat.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)
	var best: Node3D = null
	var best_score := INF
	for c in candidates:
		if not is_instance_valid(c):
			continue
		var to_c := c.global_position - player.global_position
		to_c.y = 0.0
		var dist := to_c.length()
		if dist < 0.1 or dist > MAX_DIST:
			continue
		var angle := acos(clampf(cam_fwd_flat.dot(to_c / dist), -1.0, 1.0))
		if angle > MAX_ANGLE:
			continue
		var score := angle + 0.5 * (dist / MAX_DIST)
		if score < best_score:
			best_score = score
			best = c
	return best


# Resource, ragdoll, and sfx helpers

func _load_optional_sfx(path: String) -> AudioStream:
	return load(path) if ResourceLoader.exists(path) else null


func _make_sfx(stream: AudioStream, vol_db: float = -20.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	add_child(p)
	p.finished.connect(p.queue_free)
	return p


func _spawn_ragdoll(pos: Vector3, vel: Vector3, box_size: Vector3, color: Color) -> RigidBody3D:
	var rb := RigidBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	col.position = Vector3(0.0, box_size.y * 0.5, 0.0)
	rb.add_child(col)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.mesh = mesh
	mi.position = Vector3(0.0, box_size.y * 0.5, 0.0)
	rb.add_child(mi)
	rb.collision_layer = 0
	rb.collision_mask = 1
	add_child(rb)
	rb.global_position = pos
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-8.0, 8.0), randf_range(-3.0, 3.0), randf_range(-8.0, 8.0))
	return rb


# Player ground-ring visuals

func _setup_player_rings() -> void:
	_player_arc_outline_mat = _make_unshaded(Color(1.0, 0.85, 0.1, 0.9))
	_player_range_ring_inst = _make_hidden_mesh_instance()
	_player_attack_ring_mat = _make_unshaded(Color(1.0, 0.85, 0.1, 0.35), true)
	_player_attack_ring_inst = _make_hidden_mesh_instance()

	_player_iframe_ring_mat = _make_unshaded(Color(0.4, 0.8, 1.0, 0.85), true)
	_player_iframe_ring_inst = _make_hidden_mesh_instance()

	_player_parry_fill_mat = _make_unshaded(Color(0.25, 0.55, 1.0, 0.16), true)
	_player_parry_outline_mat = _make_unshaded(Color(0.45, 0.78, 1.0, 0.95), true)
	_player_parry_ring_inst = _make_hidden_mesh_instance()


func _update_parry_ring() -> void:
	if float(Time.get_ticks_msec()) >= _parry_visual_until_ms:
		_player_parry_ring_inst.visible = false
		return
	var mesh := ImmediateMesh.new()
	RingMesh.add_disc(mesh, _player_parry_fill_mat, PARRY_RANGE, 0.0)
	RingMesh.add_circle_outline(mesh, _player_parry_outline_mat, PARRY_RANGE, 0.004)
	_player_parry_ring_inst.mesh = mesh
	_player_parry_ring_inst.global_position = Vector3(player.global_position.x, 0.008, player.global_position.z)
	_player_parry_ring_inst.visible = true


func _make_unshaded(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat


func _make_hidden_mesh_instance() -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.visible = false
	add_child(inst)
	return inst
