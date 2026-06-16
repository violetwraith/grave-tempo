extends BaseEnemy
class_name MetronomeDummy

signal player_entered_range
signal player_exited_range
signal player_body_contact

const RANGE_RADIUS := 2.0

@onready var audio: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var detection_zone: Area3D = $DetectionZone
@onready var body_zone: Area3D = $BodyZone

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

	audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	audio.unit_size = 4.0
	audio.max_distance = 30.0
	audio.finished.connect(func(): audio.play())
	audio.play()
	BeatClock.music_player = audio

	_posture_break_stream = load("res://assets/audio/sfx/posture_break.mp3") \
		if ResourceLoader.exists("res://assets/audio/sfx/posture_break.mp3") else null
	_kill_stream = load("res://assets/audio/sfx/kill.mp3") \
		if ResourceLoader.exists("res://assets/audio/sfx/kill.mp3") else null

	posture_broke.connect(func():
		if _posture_break_stream:
			_play_sfx(_posture_break_stream, -10.0))

	_setup_attack_ring()
	_draw_ground_instructions()
	await get_tree().physics_frame
	for body in detection_zone.get_overlapping_bodies():
		if body is Player:
			player_entered_range.emit()


func _on_kill(_with_ragdoll: bool) -> void:
	stop_audio()
	disable_collision()
	hide_attack_ring()
	visible = false
	if _kill_stream:
		_play_sfx(_kill_stream)


func _on_reset() -> void:
	enable_collision()
	restart_audio()
	hide_attack_ring()
	BeatClock.music_player = audio


func _do_spawn_ragdoll() -> void:
	_spawn_ragdoll_body(
		base_pos,
		kb_vel + Vector3(0.0, fall_vel, 0.0),
		Vector3(0.5, 1.2, 0.5),
		Color(0.55, 0.35, 0.15)
	)


func restart_audio() -> void:
	audio.stop()
	audio.play()


func stop_audio() -> void:
	audio.stop()


func update_attack_ring(progress: float, direction: Vector3) -> void:
	var radius := clampf(progress, 0.0, 1.0) * RANGE_RADIUS
	var angle := atan2(direction.x, direction.z)
	var half_arc := PI / 2.0

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
	outline_mesh.surface_add_vertex(Vector3(0.0, 0.02, 0.0))
	for i in range(17):
		var a := angle - half_arc + float(i) / 16 * (half_arc * 2.0)
		outline_mesh.surface_add_vertex(Vector3(sin(a) * RANGE_RADIUS, 0.02, cos(a) * RANGE_RADIUS))
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


func _setup_attack_ring() -> void:
	_attack_ring_mat = StandardMaterial3D.new()
	_attack_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_attack_ring_mat.albedo_color = Color(1.0, 0.1, 0.1, 0.45)
	_attack_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_attack_ring_inst = MeshInstance3D.new()
	_attack_ring_inst.visible = false
	add_child(_attack_ring_inst)
	_attack_ring_outline_mat = StandardMaterial3D.new()
	_attack_ring_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_attack_ring_outline_mat.albedo_color = Color(1.0, 0.3, 0.3, 0.9)
	_attack_ring_outline_inst = MeshInstance3D.new()
	_attack_ring_outline_inst.visible = false
	add_child(_attack_ring_outline_inst)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		player_entered_range.emit()


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		player_exited_range.emit()


func _on_body_zone_entered(body: Node3D) -> void:
	if body is Player:
		player_body_contact.emit()


func _draw_ground_instructions() -> void:
	var label := Label3D.new()
	label.text = (
		"4-BEAT LOOP\n"
		+ "---------------\n"
		+ "1  Attack\n"
		+ "2  Move\n"
		+ "3  Move\n"
		+ "4  Windup + Move\n"
		+ "\n"
		+ "Parry beat 1 > posture\n"
		+ "Posture full > stun x4\n"
		+ "Hold & release = attack"
	)
	label.font_size = 11
	label.pixel_size = 0.009
	label.outline_size = 5
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.modulate = Color(1.0, 0.95, 0.8, 1.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.rotation_degrees.x = -90.0
	get_parent().add_child(label)
	label.global_position = global_position + Vector3(-0.9, 0.08, RANGE_RADIUS + 1.0)
