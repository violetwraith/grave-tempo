extends StaticBody3D
class_name BaseEnemy

signal died(with_ragdoll: bool)
signal posture_broke()

@export var max_hp: float = 20.0
@export var posture_threshold: float = 3.0
@export var posture_stun_beats: int = 4
@export var posture_min_factor: float = 0.25
@export var posture_decay_rate: float = 0.4
@export var floor_half_extent: float = 19.5
@export var kb_gravity: float = -20.0
@export var kb_friction: float = 4.0
@export var stun_ring_radius: float = 0.45

const DAMAGE_NUM_LIFETIME: float = 1.6
const DAMAGE_NUM_RISE: float = 0.9
const HP_BAR_W: float = 1.2
const HP_BAR_H: float = 0.07

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

var _spawn_pos: Vector3 = Vector3.ZERO
var _moving: bool = false
var _move_start: Vector3 = Vector3.ZERO
var _move_target: Vector3 = Vector3.ZERO
var _move_start_bt: float = -1.0
var _move_ease: float = 3.0
var _ragdoll: RigidBody3D = null
var _show_lock_on: bool = false

var _stun_ring_mat: StandardMaterial3D = null
var _stun_ring_inst: MeshInstance3D = null
var _stun_indicator: Label3D = null
var _hp_bar_real_inst: MeshInstance3D = null
var _hp_bar_real_mat: StandardMaterial3D = null
var _hp_bar_pending_inst: MeshInstance3D = null
var _hp_bar_pending_mat: StandardMaterial3D = null
var _lock_on_indicator: Label3D = null
var _damage_numbers: Array = []


func _ready() -> void:
	hp = max_hp
	_spawn_pos = global_position
	base_pos = global_position
	_setup_visuals()


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
		var t := clampf(elapsed / BeatClock.beat_duration(), 0.0, 1.0)
		var t_ease := 1.0 - pow(1.0 - t, _move_ease)
		var new_pos := _move_start.lerp(_move_target, t_ease)
		base_pos.x = new_pos.x
		base_pos.z = new_pos.z


func _update_visuals(delta: float, bt: float) -> void:
	var pending_hp := 0.0
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

	var bar_pos := base_pos + Vector3(0.0, 1.9, 0.0)
	_hp_bar_real_inst.global_position = bar_pos
	_hp_bar_pending_inst.global_position = bar_pos
	if force_show_hp_bar or _damage_numbers.size() > 0:
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

	if posture > 0.0 or posture_broken:
		var posture_progress := 1.0 if posture_broken else clampf(posture / posture_threshold, 0.0, 1.0)
		_stun_ring_mat.albedo_color = Color(1.0, 0.95, 0.3, 1.0) if posture_broken else Color(1.0, 0.55, 0.1, 0.9)
		var dir_sp := tracked_position - base_pos
		dir_sp.y = 0.0
		dir_sp = dir_sp.normalized() if dir_sp.length_squared() > 0.001 else Vector3(0.0, 0.0, 1.0)
		var angle_sp := atan2(dir_sp.x, dir_sp.z)
		var arc_span := posture_progress * TAU
		var inner := stun_ring_radius - 0.08
		var outer := stun_ring_radius + 0.08
		var mesh := ImmediateMesh.new()
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _stun_ring_mat)
		for j in range(64):
			var a1 := angle_sp - float(j) / 64 * arc_span
			var a2 := angle_sp - float(j + 1) / 64 * arc_span
			mesh.surface_add_vertex(Vector3(sin(a1) * outer, 0.0, cos(a1) * outer))
			mesh.surface_add_vertex(Vector3(sin(a2) * outer, 0.0, cos(a2) * outer))
			mesh.surface_add_vertex(Vector3(sin(a2) * inner, 0.0, cos(a2) * inner))
			mesh.surface_add_vertex(Vector3(sin(a1) * outer, 0.0, cos(a1) * outer))
			mesh.surface_add_vertex(Vector3(sin(a2) * inner, 0.0, cos(a2) * inner))
			mesh.surface_add_vertex(Vector3(sin(a1) * inner, 0.0, cos(a1) * inner))
		mesh.surface_end()
		_stun_ring_inst.mesh = mesh
		_stun_ring_inst.global_position = Vector3(base_pos.x, 0.02, base_pos.z)
		_stun_ring_inst.visible = arc_span > 0.01
	else:
		_stun_ring_inst.visible = false

	if _show_lock_on:
		_lock_on_indicator.position = Vector3(0.0, 1.8, 0.0)
		_lock_on_indicator.show()
	else:
		_lock_on_indicator.hide()


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
		_update_stun_indicator()


func tick_stun() -> void:
	if stun_beats > 0:
		stun_beats -= 1
		_moving = false
		_update_stun_indicator()
		if stun_beats == 0:
			posture_broken = false


func apply_knockback(vel: Vector3, fall_velocity: float) -> void:
	kb_vel = vel
	fall_vel = maxf(fall_vel, fall_velocity)
	knocked_back = true
	_moving = false


func start_move(from: Vector3, to: Vector3, start_bt: float, ease: float = 3.0) -> void:
	_move_start = from
	_move_target = to
	_move_start_bt = start_bt
	_move_ease = ease
	_moving = true


func cancel_move() -> void:
	_moving = false


func set_lock_on_highlighted(show: bool) -> void:
	_show_lock_on = show


func spawn_damage_number(damage: float, is_crit: bool) -> void:
	var label := Label3D.new()
	label.text = "%d" % roundi(damage)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = clamp(int(24.0 + sqrt(damage) * 5.0), 24, 60)
	label.pixel_size = 0.007
	label.outline_size = 6
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
	_lock_on_indicator.hide()
	for num in _damage_numbers:
		(num.label as Label3D).queue_free()
	_damage_numbers.clear()
	if with_ragdoll:
		_do_spawn_ragdoll()
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
	if _ragdoll:
		_ragdoll.queue_free()
		_ragdoll = null
	_stun_indicator.hide()
	_stun_ring_inst.visible = false
	_hp_bar_real_inst.visible = false
	_hp_bar_pending_inst.visible = false
	for num in _damage_numbers:
		(num.label as Label3D).queue_free()
	_damage_numbers.clear()
	_lock_on_indicator.hide()
	global_position = _spawn_pos
	visible = true
	_on_reset()


func _on_kill(_with_ragdoll: bool) -> void:
	pass


func _on_reset() -> void:
	pass


func _do_spawn_ragdoll() -> void:
	pass


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
		_stun_indicator.text = "STUN x%d" % stun_beats
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
	_stun_indicator.position = Vector3(0.0, 1.8, 0.0)
	_stun_indicator.hide()
	add_child(_stun_indicator)

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

	_lock_on_indicator = Label3D.new()
	_lock_on_indicator.text = "◈"
	_lock_on_indicator.font_size = 36
	_lock_on_indicator.pixel_size = 0.007
	_lock_on_indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_lock_on_indicator.modulate = Color(1.0, 0.85, 0.1, 1.0)
	_lock_on_indicator.outline_size = 6
	_lock_on_indicator.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_lock_on_indicator.position = Vector3(0.0, 1.8, 0.0)
	_lock_on_indicator.hide()
	add_child(_lock_on_indicator)
