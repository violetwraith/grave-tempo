extends Node3D
class_name TutorialLevel

const SAMPLE_COUNT := 10
const PERFECT_THRESHOLD := 0.066
const OK_THRESHOLD := 0.20
const MISS_DECAY_TIME := 0.5
const PENALTY_PER_MISS := 0.033
const DPAD_INITIAL_DELAY := 0.4
const DPAD_REPEAT_INTERVAL := 0.08
const MAX_HP := 3
const ENEMY_WINDUP_BEATS := 1  # windup on beat 4, attack resolves on beat 1

const DUMMY_MAX_HP: float = 20.0
const DUMMY_POSTURE_THRESHOLD: float = 3.0
const DUMMY_POSTURE_STUN_BEATS: int = 4
const DUMMY_MOVE_SPEED := 3.0  # units per second — same numeric value as MetronomeDummy.RANGE_RADIUS
const DUMMY_MOVE_EASE := 3.0   # ease-out exponent: higher = sharper burst at beat start

const PLAYER_CONTACT_KB := 3.5   # small bump from body contact
const PLAYER_ATTACK_KB := 9.0    # big launch from a failed parry
const ENEMY_KB_SPEED := 3.0      # horizontal impulse when dummy is hit
const ENEMY_KB_VERTICAL := 5.0   # initial vertical velocity of dummy hop
const ENEMY_PARRY_HOP := 3.0     # smaller hop when dummy is staggered by a parry
const STUN_RING_RADIUS := 0.45   # radius of the gray stun arc drawn around the dummy
const ENEMY_KB_GRAVITY := -20.0  # downward acceleration during hop
const ENEMY_KB_FRICTION := 4.0   # exponential horizontal decay rate
const FLOOR_HALF_EXTENT := 19.5  # floor is 40×40; dummy dies when it falls beyond this

const ATTACK_PRECISION_PERFECT: float = 1.5
const ATTACK_PRECISION_OK: float = 1.0
const ATTACK_PRECISION_MISS: float = 0.1
const ATTACK_MAX_CHARGE_BEATS := 3.0
const CRIT_DAMAGE_MULT: float = 3.0
const POSTURE_MIN_FACTOR: float = 0.25   # min missing-HP fraction for posture gain (enables full-health buildup)
const POSTURE_DECAY_RATE: float = 0.4    # posture lost per idle beat, scaled by current HP fraction

const DAMAGE_NUM_LIFETIME: float = 1.6  # seconds before a floating damage number fully fades
const DAMAGE_NUM_RISE: float = 0.9      # world units per second that damage numbers drift upward
const HP_BAR_W: float = 1.2             # full-width of the enemy HP bar in world units
const HP_BAR_H: float = 0.07            # height of the enemy HP bar in world units

@onready var metronome: MetronomeDummy = $MetronomeDummy
@onready var hud: HUD = $HUD
@onready var player: Player = $Player

var _in_range: bool = false
var _samples: Array[float] = []
var _current_avg: float = 0.0

var _ting_stream: AudioStream
var _parry_stream: AudioStream
var _oof_stream: AudioStream
var _miss_stream: AudioStream  # null until miss.mp3 is added to assets

var _ting_active: bool = false
var _ting_beat_number: int = -1
var _ting_confirmed: bool = false

# Spam penalty: timestamps of recent failed presses. Each one in the last
# MISS_DECAY_TIME seconds reduces the OK window by PENALTY_PER_MISS.
var _recent_misses: Array[float] = []
var _dpad_timer: float = -1.0
var _ting_enabled: bool = false

var _attack_active: bool = false
var _attack_start_bt: float = -1.0

var _enemy_hit_time_bt: float = -1.0

var _combo: int = 0
var _player_hp: int = MAX_HP
var _player_dead: bool = false
var _player_iframe: bool = false
var _player_iframe_until_bt: float = -1.0

var _dummy_hp: float = DUMMY_MAX_HP
var _dummy_posture: float = 0.0
var _dummy_posture_broken: bool = false
var _last_posture_interaction_bt: float = -999.0
var _dummy_dead: bool = false
var _dummy_spawn_pos: Vector3 = Vector3.ZERO

var _dummy_stun_beats: int = 0   # beats of stun remaining; 0 = not stunned
var _dummy_knocked_back: bool = false
var _dummy_kb_vel: Vector3 = Vector3.ZERO
var _dummy_base_pos: Vector3 = Vector3.ZERO
var _dummy_move_enabled: bool = false
var _dummy_moving: bool = false
var _dummy_move_start: Vector3 = Vector3.ZERO
var _dummy_move_target: Vector3 = Vector3.ZERO
var _dummy_move_start_bt: float = -1.0

var _quick_attack_pending: bool = false
var _dummy_stun_indicator: Label3D = null
var _damage_numbers: Array = []
var _hp_bar_real_inst: MeshInstance3D = null
var _hp_bar_real_mat: StandardMaterial3D = null
var _hp_bar_pending_inst: MeshInstance3D = null
var _hp_bar_pending_mat: StandardMaterial3D = null

var _dummy_fall_vel: float = 0.0
var _dummy_stun_ring_inst: MeshInstance3D = null
var _dummy_stun_ring_mat: StandardMaterial3D = null
var _dummy_move_arrow_inst: MeshInstance3D = null
var _dummy_attack_dir: Vector3 = Vector3(0.0, 0.0, 1.0)
var _kill_stream: AudioStream = null
var _posture_break_stream: AudioStream = null
var _crit_hit_stream: AudioStream = null
var _dummy_ragdoll: RigidBody3D = null
var _player_ragdoll: RigidBody3D = null
var _locked_on: bool = false
var _lock_on_indicator: Label3D = null
var _player_range_ring_inst: MeshInstance3D = null
var _player_attack_ring_inst: MeshInstance3D = null
var _player_attack_ring_mat: StandardMaterial3D = null
var _player_arc_outline_mat: StandardMaterial3D = null
var _player_iframe_ring_inst: MeshInstance3D = null
var _player_iframe_ring_mat: StandardMaterial3D = null
var _player_iframe_start_bt: float = -1.0


func _ready() -> void:
	metronome.player_entered_range.connect(func(): _in_range = true)
	metronome.player_exited_range.connect(func(): _in_range = false; _stop_ting())
	metronome.player_body_contact.connect(_on_player_body_contact)

	_ting_stream = load("res://assets/audio/sfx/ting.mp3")
	_parry_stream = load("res://assets/audio/sfx/parry.mp3")
	_oof_stream = load("res://assets/audio/sfx/oof.mp3")
	_miss_stream = load("res://assets/audio/sfx/miss.mp3") if ResourceLoader.exists("res://assets/audio/sfx/miss.mp3") else null
	_kill_stream = load("res://assets/audio/sfx/kill.mp3") if ResourceLoader.exists("res://assets/audio/sfx/kill.mp3") else null
	_posture_break_stream = load("res://assets/audio/sfx/posture_break.mp3") if ResourceLoader.exists("res://assets/audio/sfx/posture_break.mp3") else null
	_crit_hit_stream = load("res://assets/audio/sfx/crit_hit.mp3") if ResourceLoader.exists("res://assets/audio/sfx/crit_hit.mp3") else null

	BeatClock.beat.connect(_on_beat)
	BeatClock.pre_beat.connect(_on_pre_beat)

	_dummy_spawn_pos = metronome.global_position
	_dummy_base_pos = metronome.global_position

	_setup_player_rings()
	_setup_stun_indicator()
	_setup_stun_ring()
	_setup_iframe_ring()
	_setup_move_arrow()
	_setup_hp_bar()
	_setup_floor()

	_lock_on_indicator = Label3D.new()
	_lock_on_indicator.text = "◈"
	_lock_on_indicator.font_size = 36
	_lock_on_indicator.pixel_size = 0.007
	_lock_on_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_lock_on_indicator.modulate = Color(1.0, 0.85, 0.1, 1.0)
	_lock_on_indicator.outline_size = 6
	_lock_on_indicator.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_lock_on_indicator.hide()
	add_child(_lock_on_indicator)

	hud.update_calibration(0.0, GameSettings.audio_offset * 1000.0, false)
	hud.update_hp(MAX_HP)
	hud.update_combo(0)


func _setup_player_rings() -> void:
	# Outline: yellow wedge boundary, rebuilt each frame as player rotates
	_player_arc_outline_mat = StandardMaterial3D.new()
	_player_arc_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_player_arc_outline_mat.albedo_color = Color(1.0, 0.85, 0.1, 0.9)
	_player_range_ring_inst = MeshInstance3D.new()
	_player_range_ring_inst.visible = false
	add_child(_player_range_ring_inst)
	# Fill: semi-transparent yellow wedge that grows with charge
	_player_attack_ring_mat = StandardMaterial3D.new()
	_player_attack_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_player_attack_ring_mat.albedo_color = Color(1.0, 0.85, 0.1, 0.35)
	_player_attack_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_player_attack_ring_inst = MeshInstance3D.new()
	_player_attack_ring_inst.visible = false
	add_child(_player_attack_ring_inst)


func _setup_stun_indicator() -> void:
	_dummy_stun_indicator = Label3D.new()
	_dummy_stun_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_dummy_stun_indicator.font_size = 20
	_dummy_stun_indicator.pixel_size = 0.008
	_dummy_stun_indicator.outline_size = 5
	_dummy_stun_indicator.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_dummy_stun_indicator.modulate = Color(1.0, 0.85, 0.1, 1.0)
	_dummy_stun_indicator.position = Vector3(0.0, 1.8, 0.0)
	_dummy_stun_indicator.hide()
	metronome.add_child(_dummy_stun_indicator)


func _update_stun_indicator() -> void:
	if _dummy_stun_beats > 0 and not _dummy_dead:
		_dummy_stun_indicator.text = "STUN x%d" % _dummy_stun_beats
		_dummy_stun_indicator.show()
	else:
		_dummy_stun_indicator.hide()


func _apply_stun(beats: int) -> void:
	if beats > _dummy_stun_beats:
		_dummy_stun_beats = beats
		_update_stun_indicator()


func _pick_lock_on_target(candidates: Array[Node3D]) -> Node3D:
	const MAX_DIST := 20.0
	const MAX_ANGLE := PI * 0.7  # 126° — exclude targets mostly behind camera
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


func _accumulate_posture(mult: float) -> void:
	_last_posture_interaction_bt = BeatClock.get_beat_time()
	var hp_factor := maxf(1.0 - _dummy_hp / DUMMY_MAX_HP, POSTURE_MIN_FACTOR)
	_dummy_posture += mult * hp_factor
	if _dummy_posture >= DUMMY_POSTURE_THRESHOLD:
		_dummy_posture = 0.0
		_dummy_posture_broken = true
		_apply_stun(DUMMY_POSTURE_STUN_BEATS)
		_enemy_hit_time_bt = -1.0
		metronome.hide_attack_ring()
		_stop_ting()
		if _posture_break_stream:
			_make_sfx(_posture_break_stream, -10.0).play()


func _setup_stun_ring() -> void:
	_dummy_stun_ring_mat = StandardMaterial3D.new()
	_dummy_stun_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dummy_stun_ring_mat.albedo_color = Color(1.0, 0.55, 0.1, 0.9)
	_dummy_stun_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dummy_stun_ring_inst = MeshInstance3D.new()
	_dummy_stun_ring_inst.visible = false
	add_child(_dummy_stun_ring_inst)


func _setup_iframe_ring() -> void:
	_player_iframe_ring_mat = StandardMaterial3D.new()
	_player_iframe_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_player_iframe_ring_mat.albedo_color = Color(0.4, 0.8, 1.0, 0.85)
	_player_iframe_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_player_iframe_ring_inst = MeshInstance3D.new()
	_player_iframe_ring_inst.visible = false
	add_child(_player_iframe_ring_inst)


func _setup_move_arrow() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.1, 0.9)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	# Arrow pointing in local +Z direction; shaft then head
	mesh.surface_add_vertex(Vector3(-0.08, 0.0,  0.25))
	mesh.surface_add_vertex(Vector3( 0.08, 0.0,  0.25))
	mesh.surface_add_vertex(Vector3( 0.08, 0.0,  0.72))
	mesh.surface_add_vertex(Vector3(-0.08, 0.0,  0.25))
	mesh.surface_add_vertex(Vector3( 0.08, 0.0,  0.72))
	mesh.surface_add_vertex(Vector3(-0.08, 0.0,  0.72))
	mesh.surface_add_vertex(Vector3(-0.28, 0.0,  0.72))
	mesh.surface_add_vertex(Vector3( 0.28, 0.0,  0.72))
	mesh.surface_add_vertex(Vector3( 0.0,  0.0,  1.15))
	mesh.surface_end()
	_dummy_move_arrow_inst = MeshInstance3D.new()
	_dummy_move_arrow_inst.mesh = mesh
	_dummy_move_arrow_inst.visible = false
	add_child(_dummy_move_arrow_inst)


func _setup_floor() -> void:
	var floor_mesh: MeshInstance3D = $Floor/MeshInstance3D
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in range(64):
		for x in range(64):
			var dark: bool = (x / 32 + y / 32) % 2 == 0
			img.set_pixel(x, y, Color(0.22, 0.22, 0.26) if dark else Color(0.34, 0.34, 0.40))
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(20.0, 20.0, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mesh.set_surface_override_material(0, mat)


func _setup_hp_bar() -> void:
	_hp_bar_real_mat = StandardMaterial3D.new()
	_hp_bar_real_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_bar_real_mat.albedo_color = Color(0.9, 0.75, 0.2, 1.0)
	_hp_bar_real_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hp_bar_real_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar_real_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hp_bar_real_inst = MeshInstance3D.new()
	_hp_bar_real_inst.visible = false
	add_child(_hp_bar_real_inst)
	_hp_bar_pending_mat = StandardMaterial3D.new()
	_hp_bar_pending_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_bar_pending_mat.albedo_color = Color(1.0, 0.3, 0.05, 1.0)
	_hp_bar_pending_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hp_bar_pending_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar_pending_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hp_bar_pending_inst = MeshInstance3D.new()
	_hp_bar_pending_inst.visible = false
	add_child(_hp_bar_pending_inst)


func _draw_hp_quad(inst: MeshInstance3D, mat: StandardMaterial3D, x0: float, x1: float) -> void:
	if x1 <= x0 + 0.001:
		inst.visible = false
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	mesh.surface_add_vertex(Vector3(x0, 0.0, 0.0))
	mesh.surface_add_vertex(Vector3(x1, HP_BAR_H, 0.0))
	mesh.surface_add_vertex(Vector3(x1, 0.0, 0.0))
	mesh.surface_add_vertex(Vector3(x0, 0.0, 0.0))
	mesh.surface_add_vertex(Vector3(x0, HP_BAR_H, 0.0))
	mesh.surface_add_vertex(Vector3(x1, HP_BAR_H, 0.0))
	mesh.surface_end()
	inst.mesh = mesh
	inst.visible = true


func _spawn_damage_number(damage: float, is_crit: bool) -> void:
	var label := Label3D.new()
	label.text = "%d" % roundi(damage)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = clamp(int(24.0 + sqrt(damage) * 5.0), 24, 60)
	label.pixel_size = 0.007
	label.outline_size = 6
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.modulate = Color(1.0, 0.5, 0.1, 1.0) if is_crit else Color(1.0, 0.95, 0.6, 1.0)
	add_child(label)
	label.global_position = _dummy_base_pos + Vector3(
		randf_range(-0.25, 0.25), 1.4 + randf_range(0.0, 0.2), randf_range(-0.1, 0.1)
	)
	_damage_numbers.append({ "label": label, "age": 0.0, "damage": damage })


func _kill_dummy(with_ragdoll: bool) -> void:
	_dummy_dead = true
	_dummy_stun_beats = 0
	_dummy_moving = false
	_ting_active = false
	_quick_attack_pending = false
	player.set_attack_charging(false)
	_enemy_hit_time_bt = -1.0
	metronome.hide_attack_ring()
	BeatClock.detach_music()
	metronome.stop_audio()
	metronome.disable_collision()
	_dummy_stun_indicator.hide()
	_dummy_stun_ring_inst.visible = false
	_dummy_move_arrow_inst.visible = false
	_hp_bar_real_inst.visible = false
	_hp_bar_pending_inst.visible = false
	if with_ragdoll:
		_dummy_ragdoll = _spawn_ragdoll(
			_dummy_base_pos,
			_dummy_kb_vel + Vector3(0.0, _dummy_fall_vel, 0.0),
			Vector3(0.5, 1.2, 0.5), Color(0.55, 0.35, 0.15)
		)
	metronome.visible = false
	if _kill_stream:
		_make_sfx(_kill_stream).play()


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
	# Collide only with layer 1 (floor), invisible to other physics bodies
	rb.collision_layer = 0
	rb.collision_mask = 1
	add_child(rb)
	rb.global_position = pos
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-8.0, 8.0), randf_range(-3.0, 3.0), randf_range(-8.0, 8.0))
	return rb


func _make_sfx(stream: AudioStream, vol_db: float = -20.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	add_child(p)
	p.finished.connect(p.queue_free)
	return p


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


func _on_pre_beat(beat_number: int) -> void:
	if not _in_range or beat_number % 4 != 0 or _player_dead or _dummy_dead:
		return

	# Attack cue rings out freely — the parry response blends with this tail.
	if _ting_enabled:
		_make_sfx(_ting_stream).play()

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
	if _player_dead or _dummy_dead or _dummy_stun_beats > 0:
		_ting_active = false
		_ting_confirmed = false
		return
	if not _ting_confirmed:
		# Only deal damage if player is within the 180° locked attack arc
		var to_player := player.global_position - _dummy_base_pos
		to_player.y = 0.0
		var in_arc := true
		if to_player.length_squared() > 0.001:
			in_arc = _dummy_attack_dir.dot(to_player.normalized()) >= 0.0
		if in_arc:
			hud.show_timing("Miss", Color(1.0, 0.3, 0.3))
			var kb_dir := to_player.normalized() if to_player.length_squared() > 0.001 else Vector3.ZERO
			_take_damage(kb_dir, PLAYER_ATTACK_KB)
			_break_combo()
	_ting_active = false
	_ting_confirmed = false
	_enemy_hit_time_bt = -1.0
	metronome.hide_attack_ring()


func _on_player_body_contact() -> void:
	if not _player_dead and not _dummy_dead:
		var dir := player.global_position - _dummy_base_pos
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			dir = dir.normalized()
		_take_damage(dir, PLAYER_CONTACT_KB)


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
		# Expire after one full beat + the ting window, so attack damage can't follow immediately
		var bt := BeatClock.get_beat_time()
		_player_iframe_until_bt = bt + BeatClock.beat_duration() + OK_THRESHOLD + 0.05
		_player_iframe_start_bt = bt
		player.start_iframe()


func _reset() -> void:
	player.reset()
	metronome.restart_audio()
	_samples.clear()
	_current_avg = 0.0
	_recent_misses.clear()
	_stop_ting()
	_attack_active = false
	_quick_attack_pending = false
	_attack_start_bt = -1.0
	_enemy_hit_time_bt = -1.0
	metronome.hide_attack_ring()
	_combo = 0
	_player_hp = MAX_HP
	_player_dead = false
	_player_iframe = false
	_player_iframe_until_bt = -1.0
	_dummy_hp = DUMMY_MAX_HP
	_dummy_posture = 0.0
	_dummy_posture_broken = false
	_last_posture_interaction_bt = -999.0
	_dummy_dead = false
	_dummy_stun_beats = 0
	_dummy_knocked_back = false
	_dummy_kb_vel = Vector3.ZERO
	_dummy_fall_vel = 0.0
	_dummy_stun_indicator.hide()
	_dummy_stun_ring_inst.visible = false
	_dummy_move_arrow_inst.visible = false
	_dummy_base_pos = _dummy_spawn_pos
	_dummy_moving = false
	_player_range_ring_inst.visible = false
	_player_attack_ring_inst.visible = false
	_player_iframe_ring_inst.visible = false
	_player_iframe_start_bt = -1.0
	if _dummy_ragdoll:
		_dummy_ragdoll.queue_free()
		_dummy_ragdoll = null
	if _player_ragdoll:
		_player_ragdoll.queue_free()
		_player_ragdoll = null
	_locked_on = false
	player.lock_on_target = null
	BeatClock.music_player = metronome.audio
	metronome.enable_collision()
	metronome.visible = true
	metronome.global_position = _dummy_spawn_pos
	for num in _damage_numbers:
		(num.label as Label3D).queue_free()
	_damage_numbers.clear()
	_hp_bar_real_inst.visible = false
	_hp_bar_pending_inst.visible = false
	hud.update_calibration(0.0, GameSettings.audio_offset * 1000.0, false)
	hud.update_hp(MAX_HP)
	hud.update_combo(0)
	hud.clear_dead()


func _stop_ting() -> void:
	_ting_active = false
	_ting_confirmed = false


func _on_beat(beat_number: int) -> void:
	if _player_dead or _dummy_dead:
		return

	var is_attack_beat := beat_number % 4 == 0  # beat 1: attack resolves, movement stops
	var is_move_beat := not is_attack_beat       # beats 2, 3, 4: move or wait

	if is_attack_beat:
		_dummy_moving = false

	if is_move_beat:
		if _dummy_stun_beats > 0:
			_dummy_stun_beats -= 1
			_dummy_moving = false
			_update_stun_indicator()
			if _dummy_stun_beats == 0:
				_dummy_posture_broken = false
		elif _dummy_move_enabled and not _dummy_knocked_back:
			var bd := BeatClock.beat_duration()
			var dir := player.global_position - _dummy_base_pos
			dir.y = 0.0
			if dir.length_squared() > 0.001:
				dir = dir.normalized()
				_dummy_move_start = _dummy_base_pos
				_dummy_move_target = _dummy_move_start + dir * DUMMY_MOVE_SPEED * bd
				_dummy_move_start_bt = BeatClock.get_beat_time()
				_dummy_moving = true
			else:
				_dummy_moving = false
		else:
			_dummy_moving = false

	if beat_number % 4 == 3 and _dummy_stun_beats == 0:
		var atk_dir := player.global_position - _dummy_base_pos
		atk_dir.y = 0.0
		_dummy_attack_dir = atk_dir.normalized() if atk_dir.length_squared() > 0.001 else Vector3(0.0, 0.0, 1.0)
		_enemy_hit_time_bt = BeatClock.get_beat_time() + float(ENEMY_WINDUP_BEATS) * BeatClock.beat_duration()

	if _quick_attack_pending:
		_fire_quick_attack()


func _play_parry_response(dist: float) -> void:
	var p := _make_sfx(_parry_stream)
	if dist > PERFECT_THRESHOLD:
		# Late hit: pitch up and duck volume proportional to how late.
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

	var bt := BeatClock.get_beat_time()
	if bt < 0.0:
		return

	# Auto-release lock-on if target is gone or dead
	if _locked_on and (_dummy_dead or not is_instance_valid(player.lock_on_target)):
		_locked_on = false
		player.lock_on_target = null

	# Update lock-on indicator position
	if _locked_on and player.lock_on_target != null:
		_lock_on_indicator.global_position = player.lock_on_target.global_position + Vector3(0.0, 1.8, 0.0)
		_lock_on_indicator.show()
	else:
		_lock_on_indicator.hide()

	# Expire iframes once enough time has passed to cover the ting window of the next beat
	if _player_iframe and bt >= _player_iframe_until_bt:
		_player_iframe = false
		_player_iframe_until_bt = -1.0
		player.end_iframe()

	# Floating damage numbers: age each one, drift upward, fade alpha; accumulate pending HP
	var pending_hp := 0.0
	var i_dn := _damage_numbers.size() - 1
	while i_dn >= 0:
		var num: Dictionary = _damage_numbers[i_dn]
		num.age += delta
		if num.age >= DAMAGE_NUM_LIFETIME:
			(num.label as Label3D).queue_free()
			_damage_numbers.remove_at(i_dn)
		else:
			var frac: float = 1.0 - float(num.age) / DAMAGE_NUM_LIFETIME
			(num.label as Label3D).modulate.a = frac
			(num.label as Label3D).global_position.y += DAMAGE_NUM_RISE * delta
			pending_hp += (num.damage as float) * frac
		i_dn -= 1

	# Enemy HP bar: visible when locked on or damage numbers are active
	var bar_pos := _dummy_base_pos + Vector3(0.0, 1.9, 0.0)
	_hp_bar_real_inst.global_position = bar_pos
	_hp_bar_pending_inst.global_position = bar_pos
	if not _dummy_dead and (_locked_on or _damage_numbers.size() > 0):
		var real_frac := clampf(_dummy_hp / DUMMY_MAX_HP, 0.0, 1.0)
		var pending_frac := clampf(pending_hp / DUMMY_MAX_HP, 0.0, 1.0 - real_frac)
		var x0 := -HP_BAR_W * 0.5
		_draw_hp_quad(_hp_bar_real_inst, _hp_bar_real_mat, x0, x0 + real_frac * HP_BAR_W)
		_draw_hp_quad(_hp_bar_pending_inst, _hp_bar_pending_mat,
			x0 + real_frac * HP_BAR_W, x0 + (real_frac + pending_frac) * HP_BAR_W)
	else:
		_hp_bar_real_inst.visible = false
		_hp_bar_pending_inst.visible = false

	# Smooth posture decay: starts after one beat of no interaction, drains proportional to HP
	if not _dummy_posture_broken and not _dummy_dead and _dummy_posture > 0.0:
		var bd_pd := BeatClock.beat_duration()
		if bt - _last_posture_interaction_bt > bd_pd:
			var decay_per_sec := POSTURE_DECAY_RATE * (_dummy_hp / DUMMY_MAX_HP) / bd_pd
			_dummy_posture = maxf(_dummy_posture - decay_per_sec * delta, 0.0)

	# Posture ring: fills as posture builds; full bright gold when posture is broken; always visible
	if not _dummy_dead and (_dummy_posture > 0.0 or _dummy_posture_broken):
		var posture_progress := 1.0 if _dummy_posture_broken else clampf(_dummy_posture / DUMMY_POSTURE_THRESHOLD, 0.0, 1.0)
		_dummy_stun_ring_mat.albedo_color = Color(1.0, 0.95, 0.3, 1.0) if _dummy_posture_broken else Color(1.0, 0.55, 0.1, 0.9)
		var dir_sp := player.global_position - _dummy_base_pos
		dir_sp.y = 0.0
		dir_sp = dir_sp.normalized() if dir_sp.length_squared() > 0.001 else Vector3(0.0, 0.0, 1.0)
		var angle_sp := atan2(dir_sp.x, dir_sp.z)
		var arc_span := posture_progress * TAU
		var stun_inner := STUN_RING_RADIUS - 0.08
		var stun_outer := STUN_RING_RADIUS + 0.08
		var stun_seg := 64
		var stun_mesh := ImmediateMesh.new()
		stun_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _dummy_stun_ring_mat)
		for i in range(stun_seg):
			var a1 := angle_sp - float(i) / stun_seg * arc_span
			var a2 := angle_sp - float(i + 1) / stun_seg * arc_span
			stun_mesh.surface_add_vertex(Vector3(sin(a1) * stun_outer, 0.0, cos(a1) * stun_outer))
			stun_mesh.surface_add_vertex(Vector3(sin(a2) * stun_outer, 0.0, cos(a2) * stun_outer))
			stun_mesh.surface_add_vertex(Vector3(sin(a2) * stun_inner, 0.0, cos(a2) * stun_inner))
			stun_mesh.surface_add_vertex(Vector3(sin(a1) * stun_outer, 0.0, cos(a1) * stun_outer))
			stun_mesh.surface_add_vertex(Vector3(sin(a2) * stun_inner, 0.0, cos(a2) * stun_inner))
			stun_mesh.surface_add_vertex(Vector3(sin(a1) * stun_inner, 0.0, cos(a1) * stun_inner))
		stun_mesh.surface_end()
		_dummy_stun_ring_inst.mesh = stun_mesh
		_dummy_stun_ring_inst.global_position = Vector3(_dummy_base_pos.x, 0.02, _dummy_base_pos.z)
		_dummy_stun_ring_inst.visible = arc_span > 0.01
	else:
		_dummy_stun_ring_inst.visible = false

	# Iframe ring: blue filled arc band around player, draining over iframe duration
	if _player_iframe and _player_iframe_start_bt >= 0.0:
		var total_if := _player_iframe_until_bt - _player_iframe_start_bt
		var elapsed_if := bt - _player_iframe_start_bt
		var if_progress := clampf(1.0 - elapsed_if / maxf(total_if, 0.001), 0.0, 1.0)
		var arc_span_if := if_progress * TAU
		var if_inner := 0.37
		var if_outer := 0.53
		var if_seg := 48
		var if_mesh := ImmediateMesh.new()
		if_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _player_iframe_ring_mat)
		for i in range(if_seg):
			var a1 := -float(i) / if_seg * arc_span_if
			var a2 := -float(i + 1) / if_seg * arc_span_if
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

	# Movement arrow: visible when dummy will move on the next beat (all phases except windup)
	var current_beat_num := int(bt / BeatClock.beat_duration())
	var show_arrow := _dummy_move_enabled and not _dummy_dead \
		and not _dummy_knocked_back and _dummy_stun_beats == 0 \
		and current_beat_num % 4 != 3
	if show_arrow:
		var dir_arr := player.global_position - _dummy_base_pos
		dir_arr.y = 0.0
		if dir_arr.length_squared() > 0.01:
			_dummy_move_arrow_inst.global_position = Vector3(_dummy_base_pos.x, 0.02, _dummy_base_pos.z)
			_dummy_move_arrow_inst.rotation.y = atan2(dir_arr.x, dir_arr.z)
			_dummy_move_arrow_inst.visible = true
		else:
			_dummy_move_arrow_inst.visible = false
	else:
		_dummy_move_arrow_inst.visible = false

	# Enemy attack ring countdown
	if _enemy_hit_time_bt > 0.0:
		var remaining := _enemy_hit_time_bt - bt
		var total := float(ENEMY_WINDUP_BEATS) * BeatClock.beat_duration()
		var progress := 1.0 - remaining / total
		metronome.update_attack_ring(progress, _dummy_attack_dir)
		if remaining <= 0.0:
			_enemy_hit_time_bt = -1.0
			metronome.hide_attack_ring()

	# Dummy y-axis: gravity always; floor clamps y only within floor bounds
	if not _dummy_dead:
		_dummy_fall_vel += ENEMY_KB_GRAVITY * delta
		_dummy_base_pos.y += _dummy_fall_vel * delta
		if absf(_dummy_base_pos.x) <= FLOOR_HALF_EXTENT and absf(_dummy_base_pos.z) <= FLOOR_HALF_EXTENT:
			if _dummy_base_pos.y < 0.0:
				_dummy_base_pos.y = 0.0
				_dummy_fall_vel = 0.0

	# Dummy x/z knockback (interrupts beat movement while active)
	if _dummy_knocked_back and not _dummy_dead:
		_dummy_kb_vel.x = lerpf(_dummy_kb_vel.x, 0.0, ENEMY_KB_FRICTION * delta)
		_dummy_kb_vel.z = lerpf(_dummy_kb_vel.z, 0.0, ENEMY_KB_FRICTION * delta)
		_dummy_base_pos.x += _dummy_kb_vel.x * delta
		_dummy_base_pos.z += _dummy_kb_vel.z * delta
		if _dummy_kb_vel.length_squared() < 0.01 and _dummy_base_pos.y <= 0.001:
			_dummy_kb_vel = Vector3.ZERO
			_dummy_knocked_back = false
	elif _dummy_move_enabled and _dummy_moving and not _dummy_dead:
		# Ease-out interpolation: fast burst at beat start, decelerates to stop
		var elapsed := bt - _dummy_move_start_bt
		var t := clampf(elapsed / BeatClock.beat_duration(), 0.0, 1.0)
		var t_ease := 1.0 - pow(1.0 - t, DUMMY_MOVE_EASE)
		var new_pos := _dummy_move_start.lerp(_dummy_move_target, t_ease)
		_dummy_base_pos.x = new_pos.x
		_dummy_base_pos.z = new_pos.z

	# Sync dummy position and check for fall death
	if not _dummy_dead:
		metronome.global_position = _dummy_base_pos
		if _dummy_base_pos.y < -8.0:
			_kill_dummy(false)

	# Player attack visuals: 60° directional wedge outline + growing fill (runs after death checks)
	if _attack_active or _quick_attack_pending:
		var ring_pos := Vector3(player.global_position.x, 0.01, player.global_position.z)
		var pfwd := player.global_transform.basis * Vector3(0.0, 0.0, -1.0)
		pfwd.y = 0.0
		pfwd = pfwd.normalized() if pfwd.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)
		var arc_center := atan2(pfwd.x, pfwd.z)
		var half_arc := PI / 6.0  # ±30° = 60° total
		var R := MetronomeDummy.RANGE_RADIUS
		var bd_vis := BeatClock.beat_duration()
		var fill_radius: float
		if _attack_active:
			var charge_ratio_a := clampf((bt - _attack_start_bt) / (ATTACK_MAX_CHARGE_BEATS * bd_vis), 0.0, 1.0)
			fill_radius = charge_ratio_a * R
		else:
			# Quick attack: fill grows from 0 → R as the next beat approaches
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


func _release_player_attack() -> void:
	if not _attack_active or _player_dead:
		return
	_attack_active = false
	player.set_attack_charging(false)

	var bt := BeatClock.get_beat_time()
	var bd := BeatClock.beat_duration()
	var charge_secs := clampf(bt - _attack_start_bt, 0.0, ATTACK_MAX_CHARGE_BEATS * bd)

	# Timing precision relative to nearest beat
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

	# Damage = combo × timing_mult × charge_secs, minimum 1; combo always resets after attack
	var damage := maxf(float(_combo) * timing_mult * charge_secs, 1.0)
	if timing_mult < ATTACK_PRECISION_OK:
		_record_miss()
	else:
		_clear_misses()
	_combo = 0
	hud.update_combo(0)

	# Directional check: dummy must be within 60° of player's facing direction
	var player_fwd := player.global_transform.basis * Vector3(0.0, 0.0, -1.0)
	player_fwd.y = 0.0
	player_fwd = player_fwd.normalized() if player_fwd.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)
	var to_dummy := _dummy_base_pos - player.global_position
	to_dummy.y = 0.0
	var facing_dummy := to_dummy.length_squared() < 0.01 or \
		player_fwd.dot(to_dummy.normalized()) >= cos(PI / 6.0)

	# Clash detection: releasing during the enemy ting window — both take damage
	# _ting_confirmed means the player already parried, so the attack is deflected — no clash damage
	var is_clash := _ting_active and not _ting_confirmed and _in_range and facing_dummy and not _dummy_dead

	if _in_range and facing_dummy and not _dummy_dead:
		var is_crit := _dummy_posture_broken
		if is_crit:
			_dummy_posture_broken = false
			if _crit_hit_stream:
				_make_sfx(_crit_hit_stream, -10.0).play()
		else:
			_make_sfx(_ting_stream).play()
		var actual_damage := damage * (CRIT_DAMAGE_MULT if is_crit else 1.0)
		_dummy_hp = maxf(_dummy_hp - actual_damage, 0.0)
		_spawn_damage_number(actual_damage, is_crit)
		_apply_stun(1)
		if not is_crit:
			_accumulate_posture(timing_mult * 0.5)
		var kb_dir := _dummy_base_pos - player.global_position
		kb_dir.y = 0.0
		if kb_dir.length_squared() > 0.001:
			var kb_cap := 50.0 if is_crit else 30.0
			var kb_speed := minf(pow(maxf(actual_damage, 0.01), maxf(charge_secs, 0.1)), kb_cap)
			_dummy_kb_vel = kb_dir.normalized() * kb_speed
			var charge_ratio := clampf(charge_secs / (ATTACK_MAX_CHARGE_BEATS * bd), 0.3, 1.0)
			_dummy_fall_vel = ENEMY_KB_VERTICAL * (3.0 if is_crit else 1.0) * charge_ratio
			_dummy_knocked_back = true
			_dummy_moving = false
		if _dummy_hp <= 0.0:
			_kill_dummy(true)
	else:
		if _miss_stream and not _dummy_dead:
			_make_sfx(_miss_stream).play()

	# Clash: player also takes damage (enemy attack landed simultaneously)
	if is_clash:
		var player_kb_dir := player.global_position - _dummy_base_pos
		player_kb_dir.y = 0.0
		if player_kb_dir.length_squared() > 0.001:
			player_kb_dir = player_kb_dir.normalized()
		_take_damage(player_kb_dir, PLAYER_ATTACK_KB)
		_ting_active = false  # prevent timer from double-firing


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
			_handle_parry_press()  # R1 press while L1 held → parry (not attack)
		else:
			_handle_quick_attack_press()
	elif event.is_action_pressed("charge_attack"):
		_handle_attack_press()
	elif event.is_action_released("charge_attack"):
		if Input.is_action_pressed("parry"):
			_handle_parry_press()  # R2 release while L1 still held → second parry
		else:
			_release_player_attack()
	elif event.is_action_pressed("reset_level"):
		_reset()
	elif event.is_action_pressed("toggle_ting"):
		_ting_enabled = not _ting_enabled
		hud.set_ting_enabled(_ting_enabled)
	elif event.is_action_pressed("toggle_move"):
		_dummy_move_enabled = not _dummy_move_enabled
		if not _dummy_move_enabled:
			_dummy_moving = false
		hud.show_timing("Move: %s" % ("ON" if _dummy_move_enabled else "OFF"), Color(0.8, 0.8, 0.8))
	elif event.is_action_pressed("lock_on"):
		if _locked_on:
			_locked_on = false
			player.lock_on_target = null
		else:
			var candidates: Array[Node3D] = []
			if not _dummy_dead:
				candidates.append(metronome)
			var target := _pick_lock_on_target(candidates)
			if target:
				_locked_on = true
				player.lock_on_target = target


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
	_start_player_attack()


func _handle_quick_attack_press() -> void:
	if _attack_active or _quick_attack_pending or _dummy_dead:
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
	if _dummy_dead or not _in_range:
		_combo = 0
		hud.update_combo(0)
		return
	var player_fwd := player.global_transform.basis * Vector3(0.0, 0.0, -1.0)
	player_fwd.y = 0.0
	player_fwd = player_fwd.normalized() if player_fwd.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)
	var to_dummy := _dummy_base_pos - player.global_position
	to_dummy.y = 0.0
	var facing_dummy := to_dummy.length_squared() < 0.01 or \
		player_fwd.dot(to_dummy.normalized()) >= cos(PI / 6.0)
	if not facing_dummy:
		_combo = 0
		hud.update_combo(0)
		return
	var damage := 1.0
	_dummy_hp = maxf(_dummy_hp - damage, 0.0)
	_spawn_damage_number(damage, false)
	_combo += 1
	hud.update_combo(_combo)
	_accumulate_posture(0.5)
	_apply_stun(1)
	_make_sfx(_ting_stream).play()
	var kb_dir := _dummy_base_pos - player.global_position
	kb_dir.y = 0.0
	if kb_dir.length_squared() > 0.001:
		_dummy_kb_vel = kb_dir.normalized() * ENEMY_KB_SPEED
		_dummy_fall_vel = ENEMY_KB_VERTICAL * 0.3
		_dummy_knocked_back = true
		_dummy_moving = false
	if _dummy_hp <= 0.0:
		_kill_dummy(true)


func _start_player_attack() -> void:
	_attack_start_bt = BeatClock.get_beat_time()
	_attack_active = true
	player.set_attack_charging(true)


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


func _show_parry_timing(dist: float) -> void:
	var effective_ok := _get_effective_ok_threshold()
	var abs_dist: float = absf(dist)
	if abs_dist <= PERFECT_THRESHOLD:
		hud.show_timing("Perfect!", Color(1.0, 0.9, 0.1))
		_ting_confirmed = true
		_clear_misses()
		_increment_combo()
		_play_parry_response(dist)
		_dummy_fall_vel = maxf(_dummy_fall_vel, ENEMY_PARRY_HOP)
		_accumulate_posture(1.5)
	elif abs_dist <= effective_ok:
		hud.show_timing("OK", Color(0.3, 1.0, 0.3))
		_ting_confirmed = true
		_clear_misses()
		_increment_combo()
		_play_parry_response(dist)
		_dummy_fall_vel = maxf(_dummy_fall_vel, ENEMY_PARRY_HOP)
		_accumulate_posture(1.0)
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
