extends StaticBody3D
class_name BaseEnemy

signal died(with_ragdoll: bool)
signal posture_broke()
signal player_entered_range()
signal player_exited_range()
signal player_body_contact()

@export var max_hp: float = 20.0
@export var posture_threshold: float = 3.0
@export var posture_stun_beats: int = 4
@export var posture_min_factor: float = 0.25
@export var posture_decay_rate: float = 0.4
@export var floor_half_extent: float = 19.5
@export var kb_gravity: float = -20.0
@export var kb_friction: float = 4.0
@export var stun_ring_radius: float = 0.45
@export var hp_bar_height: float = 1.9
@export var overhead_label_height: float = 1.8
# Radius of the red attack indicator. Parry and damage range checks read it.
@export var attack_radius: float = 2.0
# Floating HP bar above the model. Off for enemies that use the static HUD bar (the boss).
@export var show_overhead_hp_bar: bool = true

const DAMAGE_NUM_LIFETIME: float = 1.6
const DAMAGE_NUM_RISE: float = 0.9
const HP_BAR_W: float = 1.2
const HP_BAR_H: float = 0.07
const LOCK_ON_SPIN_SPEED: float = 3.0
const LOCK_ON_MARGIN: float = 0.5

@onready var detection_zone: Area3D = $DetectionZone
@onready var body_zone: Area3D = $BodyZone

var hp: float = 0.0
var posture: float = 0.0
var posture_broken: bool = false
var last_posture_interaction_bt: float = -999.0
var dead: bool = false
var stun_beats: int = 0
var knocked_back: bool = false
var kb_vel: Vector3 = Vector3.ZERO
var fall_vel: float = 0.0
var base_pos: Vector3 = Vector3.ZERO
var tracked_position: Vector3 = Vector3.ZERO
var force_show_hp_bar: bool = false
# Damage still draining off the bar (sum of fading damage numbers); read by the HUD boss bar.
var pending_hp: float = 0.0

# Current attack telegraph. A half arc of PI means the attack covers a full circle.
var attack_dir: Vector3 = Vector3(0.0, 0.0, 1.0)
var attack_half_arc: float = PI / 2.0

var _spawn_pos: Vector3 = Vector3.ZERO
var _moving: bool = false
var _move_start: Vector3 = Vector3.ZERO
var _move_target: Vector3 = Vector3.ZERO
var _move_start_bt: float = -1.0
var _move_ease: float = 3.0
var _move_duration_beats: float = 1.0
var _stun_total_dur: float = 0.001
var _stun_end_bt: float = -1.0
var _stun_show_count: bool = true
var _ragdoll: RigidBody3D = null
var _show_lock_on: bool = false

var _stun_ring_mat: StandardMaterial3D = null
var _stun_ring_inst: MeshInstance3D = null
var _stun_indicator: Label3D = null
var _hp_bar_real_inst: MeshInstance3D = null
var _hp_bar_real_mat: StandardMaterial3D = null
var _hp_bar_pending_inst: MeshInstance3D = null
var _hp_bar_pending_mat: StandardMaterial3D = null
var _lock_on_ring_inst: MeshInstance3D = null
var _lock_on_ring_mat: StandardMaterial3D = null
var _lock_on_spin: float = 0.0
var _attack_ring_mat: StandardMaterial3D = null
var _attack_ring_inst: MeshInstance3D = null
var _attack_ring_outline_mat: StandardMaterial3D = null
var _attack_ring_outline_inst: MeshInstance3D = null
var _posture_break_stream: AudioStream = null
var _kill_stream: AudioStream = null
var _damage_numbers: Array = []


func _ready() -> void:
	hp = max_hp
	_spawn_pos = global_position
	base_pos = global_position
	_setup_visuals()
	_setup_attack_ring()
	_load_combat_sfx()
	_connect_zones()
	_announce_initial_overlap()


func _process(delta: float) -> void:
	if dead:
		return
	var bt := BeatClock.get_beat_time()
	if bt < 0.0:
		return
	_update_physics(delta, bt)
	global_position = base_pos
	if base_pos.y < -8.0:
		kill(false)
		return
	_update_visuals(delta, bt)


# Attack telegraph

func aim_attack(direction: Vector3, half_arc: float = PI / 2.0) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() > 0.001:
		attack_dir = flat.normalized()
	attack_half_arc = half_arc


func update_attack_ring(progress: float) -> void:
	var radius := clampf(progress, 0.0, 1.0) * attack_radius
	var angle := atan2(attack_dir.x, attack_dir.z)
	var full_circle := attack_half_arc >= PI

	var fill := ImmediateMesh.new()
	if full_circle:
		RingMesh.add_disc(fill, _attack_ring_mat, radius, 0.015)
	else:
		RingMesh.add_sector_fill(fill, _attack_ring_mat, radius, angle, attack_half_arc, 0.015)
	_attack_ring_inst.mesh = fill
	_attack_ring_inst.visible = radius > 0.01

	var outline := ImmediateMesh.new()
	if full_circle:
		RingMesh.add_circle_outline(outline, _attack_ring_outline_mat, attack_radius, 0.02)
	else:
		RingMesh.add_sector_outline(outline, _attack_ring_outline_mat, attack_radius, angle, attack_half_arc, 0.02)
	_attack_ring_outline_inst.mesh = outline
	_attack_ring_outline_inst.visible = true


func hide_attack_ring() -> void:
	_attack_ring_inst.visible = false
	_attack_ring_outline_inst.visible = false


# Combat state

func accumulate_posture(mult: float) -> void:
	last_posture_interaction_bt = BeatClock.get_beat_time()
	var hp_factor := maxf(1.0 - hp / max_hp, posture_min_factor)
	posture += mult * hp_factor
	if posture >= posture_threshold:
		posture = 0.0
		posture_broken = true
		apply_stun(posture_stun_beats)
		posture_broke.emit()


func apply_stun(beats: int) -> void:
	if beats > stun_beats:
		stun_beats = beats
		_stun_show_count = true
		_stun_total_dur = beats * BeatClock.beat_duration()
		_stun_end_bt = BeatClock.get_beat_time() + _stun_total_dur
		_update_stun_indicator()


# A stun held until the level calls end_stun() (used to align stuns to a measure downbeat).
# Never beat-ticked; the ring wipes to nothing across the whole window.
func stun_until(end_bt: float) -> void:
	posture_broken = true
	stun_beats = 1
	_moving = false
	_stun_show_count = false
	_stun_total_dur = maxf(end_bt - BeatClock.get_beat_time(), 0.001)
	_stun_end_bt = end_bt
	_update_stun_indicator()


func end_stun() -> void:
	stun_beats = 0
	posture_broken = false
	_update_stun_indicator()


func tick_stun() -> void:
	if stun_beats > 0:
		stun_beats -= 1
		_moving = false
		# Recompute the end time so the ring wipe self-corrects however often the level ticks.
		_stun_end_bt = BeatClock.get_beat_time() + stun_beats * BeatClock.beat_duration()
		_update_stun_indicator()
		if stun_beats == 0:
			posture_broken = false


func apply_knockback(vel: Vector3, fall_velocity: float) -> void:
	kb_vel = vel
	fall_vel = maxf(fall_vel, fall_velocity)
	knocked_back = true
	_moving = false


func start_move(from: Vector3, to: Vector3, start_bt: float, ease_factor: float = 3.0, duration_beats: float = 1.0) -> void:
	_move_start = from
	_move_target = to
	_move_start_bt = start_bt
	_move_ease = ease_factor
	_move_duration_beats = duration_beats
	_moving = true


func cancel_move() -> void:
	_moving = false


func set_lock_on_highlighted(highlighted: bool) -> void:
	_show_lock_on = highlighted


func spawn_damage_number(damage: float, is_crit: bool) -> void:
	var label := Label3D.new()
	label.text = "%d" % roundi(damage)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = clamp(int(40.0 + sqrt(damage) * 7.0), 40, 96)
	label.pixel_size = 0.01
	label.outline_size = 8
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.modulate = Color(1.0, 0.5, 0.1, 1.0) if is_crit else Color(1.0, 0.95, 0.6, 1.0)
	add_child(label)
	label.global_position = base_pos + Vector3(
		randf_range(-0.25, 0.25), 1.4 + randf_range(0.0, 0.2), randf_range(-0.1, 0.1)
	)
	_damage_numbers.append({ "label": label, "age": 0.0, "damage": damage })


func kill(with_ragdoll: bool) -> void:
	if dead:
		return
	dead = true
	stun_beats = 0
	knocked_back = false
	_moving = false
	_stun_indicator.hide()
	_stun_ring_inst.visible = false
	_hp_bar_real_inst.visible = false
	_hp_bar_pending_inst.visible = false
	_lock_on_ring_inst.visible = false
	_clear_damage_numbers()
	disable_collision()
	hide_attack_ring()
	visible = false
	if with_ragdoll:
		_do_spawn_ragdoll()
	if _kill_stream:
		_play_sfx(_kill_stream)
	_on_kill(with_ragdoll)
	died.emit(with_ragdoll)


func reset_state() -> void:
	hp = max_hp
	posture = 0.0
	posture_broken = false
	last_posture_interaction_bt = -999.0
	dead = false
	stun_beats = 0
	knocked_back = false
	kb_vel = Vector3.ZERO
	fall_vel = 0.0
	base_pos = _spawn_pos
	_moving = false
	force_show_hp_bar = false
	_show_lock_on = false
	attack_dir = Vector3(0.0, 0.0, 1.0)
	attack_half_arc = PI / 2.0
	if _ragdoll:
		_ragdoll.queue_free()
		_ragdoll = null
	_stun_indicator.hide()
	_stun_ring_inst.visible = false
	_hp_bar_real_inst.visible = false
	_hp_bar_pending_inst.visible = false
	_clear_damage_numbers()
	_lock_on_ring_inst.visible = false
	enable_collision()
	hide_attack_ring()
	global_position = _spawn_pos
	visible = true
	_on_reset()


func enable_collision() -> void:
	$CollisionShape3D.disabled = false
	$DetectionZone/CollisionShape3D.disabled = false
	$BodyZone/CollisionShape3D.disabled = false


func disable_collision() -> void:
	$CollisionShape3D.disabled = true
	$DetectionZone/CollisionShape3D.disabled = true
	$BodyZone/CollisionShape3D.disabled = true


# Subclass hooks

func _on_kill(_with_ragdoll: bool) -> void:
	pass


func _on_reset() -> void:
	pass


func _do_spawn_ragdoll() -> void:
	pass


# Internals

func _update_physics(delta: float, bt: float) -> void:
	fall_vel += kb_gravity * delta
	base_pos.y += fall_vel * delta
	if absf(base_pos.x) <= floor_half_extent and absf(base_pos.z) <= floor_half_extent:
		if base_pos.y < 0.0:
			base_pos.y = 0.0
			fall_vel = 0.0

	if knocked_back:
		kb_vel.x = lerpf(kb_vel.x, 0.0, kb_friction * delta)
		kb_vel.z = lerpf(kb_vel.z, 0.0, kb_friction * delta)
		base_pos.x += kb_vel.x * delta
		base_pos.z += kb_vel.z * delta
		if kb_vel.length_squared() < 0.01 and base_pos.y <= 0.001:
			kb_vel = Vector3.ZERO
			knocked_back = false
	elif _moving:
		var elapsed := bt - _move_start_bt
		var t := clampf(elapsed / (BeatClock.beat_duration() * _move_duration_beats), 0.0, 1.0)
		var t_ease := 1.0 - pow(1.0 - t, _move_ease)
		var new_pos := _move_start.lerp(_move_target, t_ease)
		base_pos.x = new_pos.x
		base_pos.z = new_pos.z


func _update_visuals(delta: float, bt: float) -> void:
	pending_hp = 0.0
	var i := _damage_numbers.size() - 1
	while i >= 0:
		var num: Dictionary = _damage_numbers[i]
		num.age += delta
		if num.age >= DAMAGE_NUM_LIFETIME:
			(num.label as Label3D).queue_free()
			_damage_numbers.remove_at(i)
		else:
			var frac: float = 1.0 - float(num.age) / DAMAGE_NUM_LIFETIME
			(num.label as Label3D).modulate.a = frac
			(num.label as Label3D).global_position.y += DAMAGE_NUM_RISE * delta
			pending_hp += (num.damage as float) * frac
		i -= 1

	var bar_pos := base_pos + Vector3(0.0, hp_bar_height, 0.0)
	_hp_bar_real_inst.global_position = bar_pos
	_hp_bar_pending_inst.global_position = bar_pos
	if show_overhead_hp_bar and (force_show_hp_bar or _damage_numbers.size() > 0):
		var real_frac := clampf(hp / max_hp, 0.0, 1.0)
		var pending_frac := clampf(pending_hp / max_hp, 0.0, 1.0 - real_frac)
		var x0 := -HP_BAR_W * 0.5
		_draw_hp_quad(_hp_bar_real_inst, _hp_bar_real_mat, x0, x0 + real_frac * HP_BAR_W)
		_draw_hp_quad(_hp_bar_pending_inst, _hp_bar_pending_mat,
			x0 + real_frac * HP_BAR_W, x0 + (real_frac + pending_frac) * HP_BAR_W)
	else:
		_hp_bar_real_inst.visible = false
		_hp_bar_pending_inst.visible = false

	if not posture_broken and posture > 0.0:
		var bd := BeatClock.beat_duration()
		if bt - last_posture_interaction_bt > bd:
			var decay_per_sec := posture_decay_rate * (hp / max_hp) / bd
			posture = maxf(posture - decay_per_sec * delta, 0.0)

	_update_stun_ring(bt)
	_update_lock_on_marker(delta)


func _update_stun_ring(bt: float) -> void:
	# Three ring states around the enemy:
	#   posture building: orange, fills toward a break
	#   crit available (posture broken): yellow, wipes down across the stun
	#   crit spent but still stunned: gray, wipes down to the recovery
	var posture_progress: float
	var ring_color: Color
	if posture_broken:
		posture_progress = clampf((_stun_end_bt - bt) / maxf(_stun_total_dur, 0.001), 0.0, 1.0)
		ring_color = Color(1.0, 0.95, 0.3, 1.0)
	elif stun_beats > 0:
		posture_progress = clampf((_stun_end_bt - bt) / maxf(_stun_total_dur, 0.001), 0.0, 1.0)
		ring_color = Color(0.6, 0.6, 0.62, 0.9)
	elif posture > 0.0:
		posture_progress = clampf(posture / posture_threshold, 0.0, 1.0)
		ring_color = Color(1.0, 0.55, 0.1, 0.9)
	else:
		_stun_ring_inst.visible = false
		return
	_stun_ring_mat.albedo_color = ring_color

	# The remaining sliver collapses toward the player so it always points at them.
	var dir_sp := tracked_position - base_pos
	dir_sp.y = 0.0
	dir_sp = dir_sp.normalized() if dir_sp.length_squared() > 0.001 else Vector3(0.0, 0.0, 1.0)
	var angle_sp := atan2(dir_sp.x, dir_sp.z)
	var arc_span := posture_progress * TAU
	var mesh := ImmediateMesh.new()
	RingMesh.add_annulus_sweep(mesh, _stun_ring_mat,
		stun_ring_radius - 0.08, stun_ring_radius + 0.08, angle_sp, arc_span, 0.0, 64)
	_stun_ring_inst.mesh = mesh
	_stun_ring_inst.global_position = Vector3(base_pos.x, 0.02, base_pos.z)
	_stun_ring_inst.visible = arc_span > 0.01


# Two arcs spinning on the ground, sitting outside the stun ring so the posture meter
# reads comfortably inside it.
func _update_lock_on_marker(delta: float) -> void:
	if not _show_lock_on:
		_lock_on_ring_inst.visible = false
		return
	_lock_on_spin += delta * LOCK_ON_SPIN_SPEED
	var radius := stun_ring_radius + LOCK_ON_MARGIN
	var inner := radius - 0.06
	var outer := radius + 0.06
	var arc_half := deg_to_rad(50.0)
	var mesh := ImmediateMesh.new()
	RingMesh.add_annulus_sweep(mesh, _lock_on_ring_mat, inner, outer, _lock_on_spin + arc_half, arc_half * 2.0, 0.0, 24)
	RingMesh.add_annulus_sweep(mesh, _lock_on_ring_mat, inner, outer, _lock_on_spin + PI + arc_half, arc_half * 2.0, 0.0, 24)
	_lock_on_ring_inst.mesh = mesh
	_lock_on_ring_inst.global_position = Vector3(base_pos.x, 0.025, base_pos.z)
	_lock_on_ring_inst.visible = true


func _clear_damage_numbers() -> void:
	for num in _damage_numbers:
		(num.label as Label3D).queue_free()
	_damage_numbers.clear()


func _connect_zones() -> void:
	detection_zone.body_entered.connect(_on_body_entered)
	detection_zone.body_exited.connect(_on_body_exited)
	body_zone.body_entered.connect(_on_body_zone_entered)


func _announce_initial_overlap() -> void:
	await get_tree().physics_frame
	if not is_instance_valid(self):
		return
	for body in detection_zone.get_overlapping_bodies():
		if body is Player:
			player_entered_range.emit()


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		player_entered_range.emit()


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		player_exited_range.emit()


func _on_body_zone_entered(body: Node3D) -> void:
	if body is Player:
		player_body_contact.emit()


func _load_combat_sfx() -> void:
	_posture_break_stream = load("res://assets/audio/sfx/posture_break.mp3") \
		if ResourceLoader.exists("res://assets/audio/sfx/posture_break.mp3") else null
	_kill_stream = load("res://assets/audio/sfx/kill.mp3") \
		if ResourceLoader.exists("res://assets/audio/sfx/kill.mp3") else null
	posture_broke.connect(func():
		if _posture_break_stream:
			_play_sfx(_posture_break_stream, -10.0))


func _spawn_ragdoll_body(pos: Vector3, vel: Vector3, box_size: Vector3, color: Color) -> void:
	var rb := RigidBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	col.shape = shape
	col.position = Vector3(0.0, box_size.y * 0.5, 0.0)
	rb.add_child(col)
	var mi := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.mesh = box_mesh
	mi.position = Vector3(0.0, box_size.y * 0.5, 0.0)
	rb.add_child(mi)
	rb.collision_layer = 0
	rb.collision_mask = 1
	get_parent().add_child(rb)
	rb.global_position = pos
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-8.0, 8.0), randf_range(-3.0, 3.0), randf_range(-8.0, 8.0))
	_ragdoll = rb


func _play_sfx(stream: AudioStream, vol_db: float = -20.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _update_stun_indicator() -> void:
	if stun_beats > 0 and not dead:
		_stun_indicator.text = ("STUN x%d" % stun_beats) if _stun_show_count else "STUN"
		_stun_indicator.show()
	else:
		_stun_indicator.hide()


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


func _setup_attack_ring() -> void:
	_attack_ring_mat = StandardMaterial3D.new()
	_attack_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_attack_ring_mat.albedo_color = Color(0.95, 0.15, 0.1, 0.4)
	_attack_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_attack_ring_inst = MeshInstance3D.new()
	_attack_ring_inst.visible = false
	add_child(_attack_ring_inst)
	_attack_ring_outline_mat = StandardMaterial3D.new()
	_attack_ring_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_attack_ring_outline_mat.albedo_color = Color(1.0, 0.35, 0.2, 0.9)
	_attack_ring_outline_inst = MeshInstance3D.new()
	_attack_ring_outline_inst.visible = false
	add_child(_attack_ring_outline_inst)


func _setup_visuals() -> void:
	_stun_ring_mat = StandardMaterial3D.new()
	_stun_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_stun_ring_mat.albedo_color = Color(1.0, 0.55, 0.1, 0.9)
	_stun_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_stun_ring_inst = MeshInstance3D.new()
	_stun_ring_inst.visible = false
	add_child(_stun_ring_inst)

	_stun_indicator = Label3D.new()
	_stun_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_stun_indicator.font_size = 20
	_stun_indicator.pixel_size = 0.008
	_stun_indicator.outline_size = 5
	_stun_indicator.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_stun_indicator.modulate = Color(1.0, 0.85, 0.1, 1.0)
	_stun_indicator.position = Vector3(0.0, overhead_label_height, 0.0)
	_stun_indicator.hide()
	add_child(_stun_indicator)

	_hp_bar_real_mat = StandardMaterial3D.new()
	_hp_bar_real_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_bar_real_mat.albedo_color = Color(0.85, 0.12, 0.12, 1.0)
	_hp_bar_real_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hp_bar_real_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar_real_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hp_bar_real_inst = MeshInstance3D.new()
	_hp_bar_real_inst.visible = false
	add_child(_hp_bar_real_inst)

	_hp_bar_pending_mat = StandardMaterial3D.new()
	_hp_bar_pending_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hp_bar_pending_mat.albedo_color = Color(0.95, 0.95, 0.95, 1.0)
	_hp_bar_pending_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hp_bar_pending_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar_pending_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hp_bar_pending_inst = MeshInstance3D.new()
	_hp_bar_pending_inst.visible = false
	add_child(_hp_bar_pending_inst)

	_lock_on_ring_mat = StandardMaterial3D.new()
	_lock_on_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lock_on_ring_mat.albedo_color = Color(0.35, 0.7, 1.0, 0.95)
	_lock_on_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lock_on_ring_inst = MeshInstance3D.new()
	_lock_on_ring_inst.visible = false
	add_child(_lock_on_ring_inst)
