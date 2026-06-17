extends BaseEnemy
class_name MetronomeDummy

@onready var audio: AudioStreamPlayer3D = $AudioStreamPlayer3D


func _ready() -> void:
	super._ready()
	audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	audio.unit_size = 4.0
	audio.max_distance = 30.0
	audio.finished.connect(func(): audio.play())
	audio.play()
	BeatClock.music_player = audio


func restart_audio() -> void:
	audio.stop()
	audio.play()


func stop_audio() -> void:
	audio.stop()


func _on_kill(_with_ragdoll: bool) -> void:
	stop_audio()


func _on_reset() -> void:
	restart_audio()
	BeatClock.music_player = audio


func _do_spawn_ragdoll() -> void:
	_spawn_ragdoll_body(
		base_pos,
		kb_vel + Vector3(0.0, fall_vel, 0.0),
		Vector3(0.8, 1.9, 0.8),
		Color(0.55, 0.35, 0.15)
	)
