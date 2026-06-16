extends StaticBody3D
class_name MetronomeDummy

signal player_entered_range
signal player_exited_range

const RANGE_RADIUS := 2.0

@onready var audio: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var detection_zone: Area3D = $DetectionZone


func _ready() -> void:
	detection_zone.body_entered.connect(_on_body_entered)
	detection_zone.body_exited.connect(_on_body_exited)

	audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	audio.unit_size = 4.0
	audio.max_distance = 30.0

	audio.finished.connect(func(): audio.play())

	audio.play()
	BeatClock.music_player = audio

	_draw_range_circle()
	_draw_ground_instructions()
	await get_tree().physics_frame
	for body in detection_zone.get_overlapping_bodies():
		if body is Player:
			player_entered_range.emit()


func restart_audio() -> void:
	audio.stop()
	audio.play()


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		player_entered_range.emit()


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		player_exited_range.emit()


func _draw_ground_instructions() -> void:
	var label := Label3D.new()
	label.text = (
		"METRONOME CALIBRATION\n"
		+ "Hold  L2 / F  to enter Parry mode\n\n"
		+ "High click  (Beat 1)     →   Y button  /  T key\n"
		+ "Low clicks  (Beats 2-4)  →   A button  /  G key\n\n"
		+ "D-pad / [ ]  adjust latency"
	)
	label.font_size = 14
	label.pixel_size = 0.013
	label.outline_size = 5
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.modulate = Color(1.0, 0.95, 0.8, 1.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.rotation_degrees.x = -90.0
	label.position = Vector3(0.0, 0.02, RANGE_RADIUS + 1.0) # in front of player relative to spawn
	add_child(label)


func _draw_range_circle() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.1, 1.0)

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	var segments := 64
	for i in range(segments + 1):
		var angle := float(i) / segments * TAU
		mesh.surface_add_vertex(Vector3(cos(angle) * RANGE_RADIUS, 0.01, sin(angle) * RANGE_RADIUS))
	mesh.surface_end()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
