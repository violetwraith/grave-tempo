extends BaseEnemy
class_name BossEnemy

signal phase_transition_pending # emitted instead of dying in phase 1
signal phase_transition_started
signal phase_two_ready

enum Phase {ONE, TRANSITIONING, TWO}

@onready var audio_phase1: AudioStreamPlayer = $AudioPhase1
@onready var audio_trans: AudioStreamPlayer = $AudioTrans
@onready var audio_phase2: AudioStreamPlayer = $AudioPhase2

var current_phase: Phase = Phase.ONE
var iframe: bool = false


func _ready() -> void:
	super._ready()
	audio_phase1.finished.connect(func(): audio_phase1.play())
	audio_phase2.finished.connect(func(): audio_phase2.play())
	audio_trans.finished.connect(_on_trans_finished)


func kill(with_ragdoll: bool) -> void:
	if current_phase == Phase.ONE and not iframe:
		iframe = true
		hp = 0.0
		phase_transition_pending.emit()
		return
	super.kill(with_ragdoll)


# ignore mini stagger
func apply_stun(_beats: int) -> void:
	pass


func start_phase_one() -> void:
	current_phase = Phase.ONE
	iframe = false
	BeatClock.bpm = 120.0
	BeatClock.music_player = audio_phase1
	audio_phase1.play()


func begin_transition() -> void:
	current_phase = Phase.TRANSITIONING
	iframe = true
	audio_phase1.stop()
	BeatClock.detach_music()
	BeatClock.music_player = audio_trans
	audio_trans.play()
	phase_transition_started.emit()


func _on_trans_finished() -> void:
	current_phase = Phase.TWO
	iframe = false
	BeatClock.bpm = 140.0
	BeatClock.music_player = audio_phase2
	audio_phase2.play()
	hp = max_hp
	posture = 0.0
	posture_broken = false
	force_show_hp_bar = true
	phase_two_ready.emit()


func _on_kill(_with_ragdoll: bool) -> void:
	audio_phase1.stop()
	audio_trans.stop()
	audio_phase2.stop()


func _on_reset() -> void:
	current_phase = Phase.ONE
	iframe = false
	audio_phase1.stop()
	audio_trans.stop()
	audio_phase2.stop()


func _do_spawn_ragdoll() -> void:
	_spawn_ragdoll_body(
		base_pos,
		kb_vel + Vector3(0.0, fall_vel, 0.0),
		Vector3(0.8, 2.1, 0.7),
		Color(0.6, 0.1, 0.1)
	)
