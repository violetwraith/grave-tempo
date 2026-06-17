extends BaseEnemy
class_name BossEnemy

signal player_entered_range
signal player_exited_range
signal player_body_contact
signal phase_transition_pending  # emitted instead of dying in phase 1
signal phase_transition_started
signal phase_two_ready

const RANGE_RADIUS := 8.0

enum Phase { ONE, TRANSITIONING, TWO }

@onready var detection_zone: Area3D = $DetectionZone
@onready var body_zone: Area3D = $BodyZone
@onready var audio_phase1: AudioStreamPlayer = $AudioPhase1
@onready var audio_trans: AudioStreamPlayer = $AudioTrans
@onready var audio_phase2: AudioStreamPlayer = $AudioPhase2

var current_phase: Phase = Phase.ONE
var invincible: bool = false

var _attack_ring_mat: StandardMaterial3D = null
var _attack_ring_inst: MeshInstance3D = null
var _attack_ring_outline_mat: StandardMaterial3D = null
var _attack_ring_outline_inst: MeshInstance3D = null
var _posture_break_stream: AudioStream = null
var _kill_stream: AudioStream = null


func _ready() -> void:
	super._ready()
	detection_zone.body_entered.connect(_on_body_entered)
	detection_zone.body_exited.connect(_on_body_exited)
	body_zone.body_entered.connect(_on_body_zone_entered)

	_posture_break_stream = load("res://assets/audio/sfx/posture_break.mp3") \
		if ResourceLoader.exists("res://assets/audio/sfx/posture_break.mp3") else null
	_kill_stream = load("res://assets/audio/sfx/kill.mp3") \
		if ResourceLoader.exists("res://assets/audio/sfx/kill.mp3") else null

	posture_broke.connect(func():
		if _posture_break_stream:
			_play_sfx(_posture_break_stream, -10.0))

	_setup_attack_ring()

	# Adjust indicator heights for taller boss model (3.2 m body)
	_stun_indicator.position = Vector3(0.0, 3.5, 0.0)
	_lock_on_indicator.position = Vector3(0.0, 3.5, 0.0)

	# Phase 1 and 2 loop; trans plays once then triggers transition
	audio_phase1.finished.connect(func(): audio_phase1.play())
	audio_phase2.finished.connect(func(): audio_phase2.play())
	audio_trans.finished.connect(_on_trans_finished)

	await get_tree().physics_frame
	for body in detection_zone.get_overlapping_bodies():
		if body is Player:
			player_entered_range.emit()


func kill(with_ragdoll: bool) -> void:
	if current_phase == Phase.ONE and not invincible:
		invincible = true
		hp = 0.0
		phase_transition_pending.emit()
		return
	super.kill(with_ragdoll)


func start_phase_one() -> void:
	current_phase = Phase.ONE
	invincible = false
	BeatClock.bpm = 120.0
	BeatClock.music_player = audio_phase1
	audio_phase1.play()
	_update_phase_label()


func begin_transition() -> void:
	current_phase = Phase.TRANSITIONING
	invincible = true
	_update_phase_label()
	audio_phase1.stop()
	BeatClock.detach_music()
	BeatClock.music_player = audio_trans
	audio_trans.play()
	phase_transition_started.emit()


func _on_trans_finished() -> void:
	current_phase = Phase.TWO
	invincible = false
	BeatClock.bpm = 140.0
	BeatClock.music_player = audio_phase2
	audio_phase2.play()
	hp = max_hp
	posture = 0.0
	posture_broken = false
	force_show_hp_bar = true
	_update_phase_label()
	phase_two_ready.emit()


func get_attack_radius() -> float:
	return RANGE_RADIUS


func update_attack_ring(progress: float, direction: Vector3, range_radius: float = RANGE_RADIUS, full_360: bool = false) -> void:
	var radius := clampf(progress, 0.0, 1.0) * range_radius
	var angle := atan2(direction.x, direction.z)
	var half_arc := PI if full_360 else PI / 2.0

	var fill_mesh := ImmediateMesh.new()
	fill_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _attack_ring_mat)
	for i in range(48):
		var a1 := angle - half_arc + float(i) / 48 * (half_arc * 2.0)
		var a2 := angle - half_arc + float(i + 1) / 48 * (half_arc * 2.0)
		fill_mesh.surface_add_vertex(Vector3(0.0, 0.015, 0.0))
		fill_mesh.surface_add_vertex(Vector3(sin(a2) * radius, 0.015, cos(a2) * radius))
		fill_mesh.surface_add_vertex(Vector3(sin(a1) * radius, 0.015, cos(a1) * radius))
	fill_mesh.surface_end()
	_attack_ring_inst.mesh = fill_mesh
	_attack_ring_inst.visible = radius > 0.01

	var outline_mesh := ImmediateMesh.new()
	outline_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _attack_ring_outline_mat)
	if full_360:
		for i in range(33):
			var a := float(i) / 32.0 * TAU
			outline_mesh.surface_add_vertex(Vector3(sin(a) * range_radius, 0.02, cos(a) * range_radius))
	else:
		outline_mesh.surface_add_vertex(Vector3(0.0, 0.02, 0.0))
		for i in range(17):
			var a := angle - half_arc + float(i) / 16 * (half_arc * 2.0)
			outline_mesh.surface_add_vertex(Vector3(sin(a) * range_radius, 0.02, cos(a) * range_radius))
		outline_mesh.surface_add_vertex(Vector3(0.0, 0.02, 0.0))
	outline_mesh.surface_end()
	_attack_ring_outline_inst.mesh = outline_mesh
	_attack_ring_outline_inst.visible = true


func hide_attack_ring() -> void:
	_attack_ring_inst.visible = false
	_attack_ring_outline_inst.visible = false


func disable_collision() -> void:
	$CollisionShape3D.disabled = true
	$DetectionZone/CollisionShape3D.disabled = true
	$BodyZone/CollisionShape3D.disabled = true


func enable_collision() -> void:
	$CollisionShape3D.disabled = false
	$DetectionZone/CollisionShape3D.disabled = false
	$BodyZone/CollisionShape3D.disabled = false


func _on_kill(_with_ragdoll: bool) -> void:
	disable_collision()
	hide_attack_ring()
	audio_phase1.stop()
	audio_trans.stop()
	audio_phase2.stop()
	if _kill_stream:
		_play_sfx(_kill_stream)
	visible = false


func _on_reset() -> void:
	enable_collision()
	hide_attack_ring()
	current_phase = Phase.ONE
	invincible = false
	audio_phase1.stop()
	audio_trans.stop()
	audio_phase2.stop()
	_update_phase_label()


func _do_spawn_ragdoll() -> void:
	_spawn_ragdoll_body(
		base_pos,
		kb_vel + Vector3(0.0, fall_vel, 0.0),
		Vector3(0.6, 1.6, 0.5),
		Color(0.6, 0.1, 0.1)
	)


func _setup_attack_ring() -> void:
	_attack_ring_mat = StandardMaterial3D.new()
	_attack_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_attack_ring_mat.albedo_color = Color(0.9, 0.2, 0.05, 0.35)
	_attack_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_attack_ring_inst = MeshInstance3D.new()
	_attack_ring_inst.visible = false
	add_child(_attack_ring_inst)
	_attack_ring_outline_mat = StandardMaterial3D.new()
	_attack_ring_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_attack_ring_outline_mat.albedo_color = Color(1.0, 0.35, 0.1, 0.9)
	_attack_ring_outline_inst = MeshInstance3D.new()
	_attack_ring_outline_inst.visible = false
	add_child(_attack_ring_outline_inst)


func _setup_phase_label() -> void:
	# Phase text is intentionally not displayed; keep the hook for state changes.
	pass


func _update_phase_label() -> void:
	pass


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		player_entered_range.emit()


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		player_exited_range.emit()


func _on_body_zone_entered(body: Node3D) -> void:
	if body is Player:
		player_body_contact.emit()
