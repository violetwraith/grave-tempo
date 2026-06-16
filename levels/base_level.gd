extends Node3D
class_name BaseLevel

const SAMPLE_COUNT := 10
const PERFECT_THRESHOLD := 0.066
const OK_THRESHOLD := 0.20
const MISS_DECAY_TIME := 0.5
const PENALTY_PER_MISS := 0.033
const DPAD_INITIAL_DELAY := 0.4
const DPAD_REPEAT_INTERVAL := 0.08
const MAX_HP := 3
const ENEMY_WINDUP_BEATS := 1

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

var _ting_active: bool = false
var _ting_beat_number: int = -1
var _ting_confirmed: bool = false
var _ting_enabled: bool = false

var _recent_misses: Array[float] = []
var _dpad_timer: float = -1.0

var _attack_active: bool = false
var _attack_start_bt: float = -1.0
var _quick_attack_pending: bool = false

var _enemy_hit_time_bt: float = -1.0

var _combo: int = 0
var _player_hp: int = MAX_HP
var _player_dead: bool = false
var _player_iframe: bool = false
var _player_iframe_until_bt: float = -1.0
var _player_iframe_start_bt: float = -1.0
var _player_ragdoll: RigidBody3D = null

var _locked_on: bool = false

var _player_range_ring_inst: MeshInstance3D = null
var _player_attack_ring_inst: MeshInstance3D = null
var _player_attack_ring_mat: StandardMaterial3D = null
var _player_arc_outline_mat: StandardMaterial3D = null
var _player_iframe_ring_inst: MeshInstance3D = null
var _player_iframe_ring_mat: StandardMaterial3D = null


func _ready() -> void:
	_ting_stream = load("res://assets/audio/sfx/ting.mp3")
	_parry_stream = load("res://assets/audio/sfx/parry.mp3")
	_oof_stream = load("res://assets/audio/sfx/oof.mp3")
	_miss_stream = load("res://assets/audio/sfx/miss.mp3") \
		if ResourceLoader.exists("res://assets/audio/sfx/miss.mp3") else null
	_crit_hit_stream = load("res://assets/audio/sfx/crit_hit.mp3") \
		if ResourceLoader.exists("res://assets/audio/sfx/crit_hit.mp3") else null

	BeatClock.beat.connect(_on_beat)
	BeatClock.pre_beat.connect(_on_pre_beat)

	_setup_player_rings()
	_setup_iframe_ring()

	hud.update_calibration(0.0, GameSettings.audio_offset * 1000.0, false)
	hud.update_hp(MAX_HP)
	hud.update_combo(0)


func _get_current_target() -> BaseEnemy:
	return null


func _get_lock_on_candidates() -> Array[Node3D]:
	return []


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

	var bt := BeatClock.get_beat_time()
	if bt < 0.0:
		return

	var target := _get_current_target()

	# Auto-release lock-on if target gone/dead
	if _locked_on and (target == null or target.dead or not is_instance_valid(player.lock_on_target)):
		_locked_on = false
		player.lock_on_target = null
		if target != null:
			target.set_lock_on_highlighted(false)
			target.force_show_hp_bar = false

	# Lock-on indicator and HP bar visibility
	if target != null:
		target.set_lock_on_highlighted(_locked_on)
		target.force_show_hp_bar = _locked_on
		target.tracked_position = player.global_position

	# Expire iframes
	if _player_iframe and bt >= _player_iframe_until_bt:
		_player_iframe = false
		_player_iframe_until_bt = -1.0
		player.end_iframe()

	# Iframe ring
	if _player_iframe and _player_iframe_start_bt >= 0.0:
		var total_if := _player_iframe_until_bt - _player_iframe_start_bt
		var elapsed_if := bt - _player_iframe_start_bt
		var if_progress := clampf(1.0 - elapsed_if / maxf(total_if, 0.001), 0.0, 1.0)
		var arc_span_if := if_progress * TAU
		var if_inner := 0.37
		var if_outer := 0.53
		var if_mesh := ImmediateMesh.new()
		if_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _player_iframe_ring_mat)
		for i in range(48):
			var a1 := -float(i) / 48 * arc_span_if
			var a2 := -float(i + 1) / 48 * arc_span_if
			if_mesh.surface_add_vertex(Vector3(sin(a1) * if_outer, 0.0, cos(a1) * if_outer))
			if_mesh.surface_add_vertex(Vector3(sin(a2) * if_outer, 0.0, cos(a2) * if_outer))
			if_mesh.surface_add_vertex(Vector3(sin(a2) * if_inner, 0.0, cos(a2) * if_inner))
			if_mesh.surface_add_vertex(Vector3(sin(a1) * if_outer, 0.0, cos(a1) * if_outer))
			if_mesh.surface_add_vertex(Vector3(sin(a2) * if_inner, 0.0, cos(a2) * if_inner))
			if_mesh.surface_add_vertex(Vector3(sin(a1) * if_inner, 0.0, cos(a1) * if_inner))
		if_mesh.surface_end()
		_player_iframe_ring_inst.mesh = if_mesh
		_player_iframe_ring_inst.global_position = Vector3(player.global_position.x, 0.01, player.global_position.z)
		_player_iframe_ring_inst.visible = if_progress > 0.01
	else:
		_player_iframe_ring_inst.visible = false

	# Player attack visuals
	if _attack_active or _quick_attack_pending:
		var ring_pos := Vector3(player.global_position.x, 0.01, player.global_position.z)
		var pfwd := player.global_transform.basis * Vector3(0.0, 0.0, -1.0)
		pfwd.y = 0.0
		pfwd = pfwd.normalized() if pfwd.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)
		var arc_center := atan2(pfwd.x, pfwd.z)
		var half_arc := PI / 6.0
		var R := MetronomeDummy.RANGE_RADIUS
		var bd_vis := BeatClock.beat_duration()
		var fill_radius: float
		if _attack_active:
			var charge_ratio_a := clampf((bt - _attack_start_bt) / (ATTACK_MAX_CHARGE_BEATS * bd_vis), 0.0, 1.0)
			fill_radius = charge_ratio_a * R
		else:
			fill_radius = clampf(fmod(bt, bd_vis) / bd_vis, 0.0, 1.0) * R
		var fill_mesh := ImmediateMesh.new()
		fill_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _player_attack_ring_mat)
		for i in range(24):
			var a1 := arc_center - half_arc + float(i) / 24 * (half_arc * 2.0)
			var a2 := arc_center - half_arc + float(i + 1) / 24 * (half_arc * 2.0)
			fill_mesh.surface_add_vertex(Vector3(0.0, 0.0, 0.0))
			fill_mesh.surface_add_vertex(Vector3(sin(a2) * fill_radius, 0.0, cos(a2) * fill_radius))
			fill_mesh.surface_add_vertex(Vector3(sin(a1) * fill_radius, 0.0, cos(a1) * fill_radius))
		fill_mesh.surface_end()
		_player_attack_ring_inst.mesh = fill_mesh
		_player_attack_ring_inst.global_position = ring_pos
		_player_attack_ring_inst.visible = fill_radius > 0.01
		var outline_mesh := ImmediateMesh.new()
		outline_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _player_arc_outline_mat)
		outline_mesh.surface_add_vertex(Vector3(0.0, 0.0, 0.0))
		for i in range(17):
			var a := arc_center - half_arc + float(i) / 16 * (half_arc * 2.0)
			outline_mesh.surface_add_vertex(Vector3(sin(a) * R, 0.0, cos(a) * R))
		outline_mesh.surface_add_vertex(Vector3(0.0, 0.0, 0.0))
		outline_mesh.surface_end()
		_player_range_ring_inst.mesh = outline_mesh
		_player_range_ring_inst.global_position = ring_pos
		_player_range_ring_inst.visible = true
	else:
		_player_range_ring_inst.visible = false
		_player_attack_ring_inst.visible = false


func _on_beat(beat_number: int) -> void:
	if _player_dead:
		return
	if _quick_attack_pending:
		_fire_quick_attack()


func _on_pre_beat(beat_number: int) -> void:
	var target := _get_current_target()
	if not _in_range or beat_number % 4 != 0 or _player_dead or (target != null and target.dead):
		return

	if _ting_enabled:
		_make_sfx(_ting_stream).play()

	_ting_active = true
	_ting_beat_number = beat_number

	var window_close_delay := OK_THRESHOLD - GameSettings.audio_offset
	var captured := beat_number
	get_tree().create_timer(window_close_delay).timeout.connect(
		func(): _on_ting_window_expired(captured)
	)


func _on_ting_window_expired(beat_number: int) -> void:
	if _ting_beat_number != beat_number or not _ting_active:
		return
	var target := _get_current_target()
	if _player_dead or (target != null and (target.dead or target.posture_broken)):
		_ting_active = false
		_ting_confirmed = false
		return
	if not _ting_confirmed:
		var target_pos := target.base_pos if target != null else Vector3.ZERO
		var to_player := player.global_position - target_pos
		to_player.y = 0.0
		var in_arc := true
		if to_player.length_squared() > 0.001:
			in_arc = _get_attack_dir().dot(to_player.normalized()) >= 0.0
		if in_arc:
			hud.show_timing("Miss", Color(1.0, 0.3, 0.3))
			var kb_dir := to_player.normalized() if to_player.length_squared() > 0.001 else Vector3.ZERO
			_take_damage(kb_dir, PLAYER_ATTACK_KB)
			_break_combo()
	_ting_active = false
	_ting_confirmed = false
	_enemy_hit_time_bt = -1.0
	_on_ting_expired_cleanup()


func _get_attack_dir() -> Vector3:
	return Vector3(0.0, 0.0, 1.0)


func _on_ting_expired_cleanup() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if _player_dead:
		if event.is_action_pressed("reset_level"):
			_reset()
		return

	if event.is_action_pressed("parry"):
		if Input.is_action_pressed("charge_attack"):
			_cancel_player_attack()
		if _quick_attack_pending:
			_quick_attack_pending = false
			player.set_attack_charging(false)
		_handle_parry_press()
	elif event.is_action_pressed("quick_attack"):
		if Input.is_action_pressed("parry"):
			_handle_parry_press()
		else:
			_handle_quick_attack_press()
	elif event.is_action_pressed("charge_attack"):
		_handle_attack_press()
	elif event.is_action_released("charge_attack"):
		if Input.is_action_pressed("parry"):
			_handle_parry_press()
		else:
			_release_player_attack()
	elif event.is_action_pressed("reset_level"):
		_reset()
	elif event.is_action_pressed("lock_on"):
		if _locked_on:
			var old_target := _get_current_target()
			if old_target != null:
				old_target.set_lock_on_highlighted(false)
				old_target.force_show_hp_bar = false
			_locked_on = false
			player.lock_on_target = null
		else:
			var candidates := _get_lock_on_candidates()
			var target := _pick_lock_on_target(candidates)
			if target:
				_locked_on = true
				player.lock_on_target = target
	else:
		_handle_extra_input(event)


func _handle_extra_input(_event: InputEvent) -> void:
	pass


func _handle_parry_press() -> void:
	if not _in_range:
		return
	_record_top_press()


func _cancel_player_attack() -> void:
	_attack_active = false
	_attack_start_bt = -1.0
	player.set_attack_charging(false)


func _handle_attack_press() -> void:
	if _attack_active or _quick_attack_pending:
		return
	_attack_active = true
	_attack_start_bt = BeatClock.get_beat_time()
	player.set_attack_charging(true)


func _handle_quick_attack_press() -> void:
	var target := _get_current_target()
	if _attack_active or _quick_attack_pending or (target != null and target.dead):
		return
	var bt := BeatClock.get_beat_time()
	var bd := BeatClock.beat_duration()
	var beat_phase := fmod(bt, bd)
	var snap_dist := bd - beat_phase
	if snap_dist <= OK_THRESHOLD:
		_fire_quick_attack()
	else:
		_quick_attack_pending = true
		player.set_attack_charging(true)


func _fire_quick_attack() -> void:
	_quick_attack_pending = false
	player.set_attack_charging(false)
	var target := _get_current_target()
	if target == null or target.dead or not _in_range:
		_break_combo()
		return
	var player_fwd := player.global_transform.basis * Vector3(0.0, 0.0, -1.0)
	player_fwd.y = 0.0
	player_fwd = player_fwd.normalized() if player_fwd.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)
	var to_target := target.base_pos - player.global_position
	to_target.y = 0.0
	var facing := to_target.length_squared() < 0.01 or \
		player_fwd.dot(to_target.normalized()) >= cos(PI / 6.0)
	if not facing:
		_break_combo()
		return
	var damage := 1.0
	target.hp = maxf(target.hp - damage, 0.0)
	target.spawn_damage_number(damage, false)
	_combo += 1
	hud.update_combo(_combo)
	target.accumulate_posture(0.5)
	target.apply_stun(1)
	_make_sfx(_ting_stream).play()
	var kb_dir := target.base_pos - player.global_position
	kb_dir.y = 0.0
	if kb_dir.length_squared() > 0.001:
		target.apply_knockback(kb_dir.normalized() * ENEMY_KB_SPEED, ENEMY_KB_VERTICAL * 0.3)
	if target.hp <= 0.0:
		target.kill(true)


func _release_player_attack() -> void:
	if not _attack_active or _player_dead:
		return
	_attack_active = false
	player.set_attack_charging(false)

	var bt := BeatClock.get_beat_time()
	var bd := BeatClock.beat_duration()
	var charge_secs := clampf(bt - _attack_start_bt, 0.0, ATTACK_MAX_CHARGE_BEATS * bd)

	var dist := fmod(bt + bd * 0.5, bd) - bd * 0.5
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
	var player_fwd := player.global_transform.basis * Vector3(0.0, 0.0, -1.0)
	player_fwd.y = 0.0
	player_fwd = player_fwd.normalized() if player_fwd.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)
	var facing_target := false
	var target_dead := true
	if target != null:
		var to_target := target.base_pos - player.global_position
		to_target.y = 0.0
		facing_target = to_target.length_squared() < 0.01 or \
			player_fwd.dot(to_target.normalized()) >= cos(PI / 6.0)
		target_dead = target.dead

	var is_clash := _ting_active and not _ting_confirmed and _in_range and facing_target and not target_dead

	if target != null and _in_range and facing_target and not target_dead:
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
		var kb_dir := target.base_pos - player.global_position
		kb_dir.y = 0.0
		if kb_dir.length_squared() > 0.001:
			var kb_cap := 50.0 if is_crit else 30.0
			var kb_speed := minf(pow(maxf(actual_damage, 0.01), maxf(charge_secs, 0.1)), kb_cap)
			var charge_ratio := clampf(charge_secs / (ATTACK_MAX_CHARGE_BEATS * bd), 0.3, 1.0)
			target.apply_knockback(
				kb_dir.normalized() * kb_speed,
				ENEMY_KB_VERTICAL * (3.0 if is_crit else 1.0) * charge_ratio
			)
		if target.hp <= 0.0:
			target.kill(true)
	else:
		if _miss_stream and not target_dead:
			_make_sfx(_miss_stream).play()

	if is_clash:
		var player_kb_dir := player.global_position - target.base_pos
		player_kb_dir.y = 0.0
		if player_kb_dir.length_squared() > 0.001:
			player_kb_dir = player_kb_dir.normalized()
		_take_damage(player_kb_dir, PLAYER_ATTACK_KB)
		_ting_active = false


func _take_damage(knockback_dir: Vector3 = Vector3.ZERO, knockback_speed: float = 0.0) -> void:
	if _player_dead or _player_iframe:
		return
	_make_sfx(_oof_stream).play()
	_player_hp -= 1
	hud.update_hp(_player_hp)
	_combo = 0
	hud.update_combo(0)
	if knockback_dir.length_squared() > 0.001 and knockback_speed > 0.0:
		player.apply_knockback(knockback_dir, knockback_speed)
	if _player_hp <= 0:
		_player_dead = true
		_attack_active = false
		_quick_attack_pending = false
		player.set_attack_charging(false)
		player.set_dead(true)
		_player_ragdoll = _spawn_ragdoll(
			player.global_position,
			player.velocity,
			Vector3(0.8, 1.8, 0.4), Color(0.1, 0.8, 0.2)
		)
		player.hide_mesh()
		hud.show_dead()
	else:
		_player_iframe = true
		var bt := BeatClock.get_beat_time()
		_player_iframe_until_bt = bt + BeatClock.beat_duration() + OK_THRESHOLD + 0.05
		_player_iframe_start_bt = bt
		player.start_iframe()


func _reset() -> void:
	player.reset()
	_samples.clear()
	_current_avg = 0.0
	_recent_misses.clear()
	_stop_ting()
	_attack_active = false
	_quick_attack_pending = false
	_attack_start_bt = -1.0
	_enemy_hit_time_bt = -1.0
	_combo = 0
	_player_hp = MAX_HP
	_player_dead = false
	_player_iframe = false
	_player_iframe_until_bt = -1.0
	_player_iframe_start_bt = -1.0
	_in_range = false
	_locked_on = false
	player.lock_on_target = null
	if _player_ragdoll:
		_player_ragdoll.queue_free()
		_player_ragdoll = null
	_player_range_ring_inst.visible = false
	_player_attack_ring_inst.visible = false
	_player_iframe_ring_inst.visible = false
	hud.update_calibration(0.0, GameSettings.audio_offset * 1000.0, false)
	hud.update_hp(MAX_HP)
	hud.update_combo(0)
	hud.clear_dead()


func _stop_ting() -> void:
	_ting_active = false
	_ting_confirmed = false


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


func _increment_combo() -> void:
	_combo += 1
	hud.update_combo(_combo)


func _break_combo() -> void:
	if _combo > 0:
		_combo = 0
		hud.update_combo(0)


func _record_top_press() -> void:
	var beat_dur := BeatClock.beat_duration()
	var bar_dur := beat_dur * 4.0
	var raw_t := BeatClock.get_beat_time() + GameSettings.audio_offset

	var x_meas := fmod(raw_t + bar_dur * 0.5, bar_dur) - bar_dur * 0.5
	_add_sample(x_meas)

	var comp_bar_dist := fmod(BeatClock.get_beat_time() + bar_dur * 0.5, bar_dur) - bar_dur * 0.5
	_show_parry_timing(comp_bar_dist)


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
	var p := _make_sfx(_parry_stream)
	if dist > PERFECT_THRESHOLD:
		var t := clampf((dist - PERFECT_THRESHOLD) / (OK_THRESHOLD - PERFECT_THRESHOLD), 0.0, 1.0)
		p.pitch_scale = lerpf(1.0, 1.25, t)
		p.volume_db = lerpf(-20.0, -25.0, t)
	p.play()


func _show_parry_timing(dist: float) -> void:
	var effective_ok := _get_effective_ok_threshold()
	var abs_dist: float = absf(dist)
	var target := _get_current_target()
	if abs_dist <= PERFECT_THRESHOLD:
		hud.show_timing("Perfect!", Color(1.0, 0.9, 0.1))
		_ting_confirmed = true
		_clear_misses()
		_increment_combo()
		_play_parry_response(dist)
		if target != null:
			target.fall_vel = maxf(target.fall_vel, ENEMY_PARRY_HOP)
			target.accumulate_posture(1.5)
	elif abs_dist <= effective_ok:
		hud.show_timing("OK", Color(0.3, 1.0, 0.3))
		_ting_confirmed = true
		_clear_misses()
		_increment_combo()
		_play_parry_response(dist)
		if target != null:
			target.fall_vel = maxf(target.fall_vel, ENEMY_PARRY_HOP)
			target.accumulate_posture(1.0)
	elif dist < 0.0:
		hud.show_timing("Early", Color(1.0, 0.6, 0.2))
		_record_miss()
		_break_combo()
		_stop_ting()
	else:
		hud.show_timing("Late", Color(1.0, 0.6, 0.2))
		_record_miss()
		_break_combo()
		_stop_ting()


func _setup_player_rings() -> void:
	_player_arc_outline_mat = StandardMaterial3D.new()
	_player_arc_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_player_arc_outline_mat.albedo_color = Color(1.0, 0.85, 0.1, 0.9)
	_player_range_ring_inst = MeshInstance3D.new()
	_player_range_ring_inst.visible = false
	add_child(_player_range_ring_inst)
	_player_attack_ring_mat = StandardMaterial3D.new()
	_player_attack_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_player_attack_ring_mat.albedo_color = Color(1.0, 0.85, 0.1, 0.35)
	_player_attack_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_player_attack_ring_inst = MeshInstance3D.new()
	_player_attack_ring_inst.visible = false
	add_child(_player_attack_ring_inst)


func _setup_iframe_ring() -> void:
	_player_iframe_ring_mat = StandardMaterial3D.new()
	_player_iframe_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_player_iframe_ring_mat.albedo_color = Color(0.4, 0.8, 1.0, 0.85)
	_player_iframe_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_player_iframe_ring_inst = MeshInstance3D.new()
	_player_iframe_ring_inst.visible = false
	add_child(_player_iframe_ring_inst)
