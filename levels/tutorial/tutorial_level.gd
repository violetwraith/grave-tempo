extends BaseLevel
class_name TutorialLevel

const DUMMY_MOVE_SPEED := 3.0
const DUMMY_MOVE_EASE := 3.0
const ENEMY_WINDUP_BEATS := 1

@onready var metronome: MetronomeDummy = $MetronomeDummy

var _enemy_hit_time_bt: float = -1.0
var _dummy_move_arrow_inst: MeshInstance3D = null


func _ready() -> void:
	_register_enemy(metronome)
	super._ready()
	_enemy_move_enabled = false  # tutorial starts with the dummy stationary for practice
	_setup_move_arrow()
	_setup_floor()
	_draw_ground_instructions()


func _get_current_target() -> BaseEnemy:
	return metronome


func _get_lock_on_candidates() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	if not metronome.dead:
		candidates.append(metronome)
	return candidates


func _on_beat(beat_number: int) -> void:
	super._on_beat(beat_number)
	if player.is_dead() or metronome.dead:
		return

	if beat_number % 4 == 0:
		metronome.cancel_move()
	else:
		_step_on_move_beat()

	# Wind up an attack one beat before the downbeat it lands on.
	if beat_number % 4 == 3 and metronome.stun_beats == 0:
		metronome.aim_attack(player.global_position - metronome.base_pos)
		_enemy_hit_time_bt = BeatClock.get_beat_time() + float(ENEMY_WINDUP_BEATS) * BeatClock.beat_duration()


func _step_on_move_beat() -> void:
	if metronome.stun_beats > 0:
		metronome.tick_stun()
	elif _enemy_move_enabled and not metronome.knocked_back:
		var dir := player.global_position - metronome.base_pos
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			var from := metronome.base_pos
			var to := from + dir.normalized() * DUMMY_MOVE_SPEED * BeatClock.beat_duration()
			metronome.start_move(from, to, BeatClock.get_beat_time(), DUMMY_MOVE_EASE)
		else:
			metronome.cancel_move()
	else:
		metronome.cancel_move()


func _process(delta: float) -> void:
	super._process(delta)
	var bt := BeatClock.get_beat_time()
	if bt < 0.0:
		return

	# Fill the attack ring across the wind-up.
	if _enemy_hit_time_bt > 0.0:
		var total := float(ENEMY_WINDUP_BEATS) * BeatClock.beat_duration()
		var remaining := _enemy_hit_time_bt - bt
		metronome.update_attack_ring(1.0 - remaining / total)
		if remaining <= 0.0:
			_enemy_hit_time_bt = -1.0
			metronome.hide_attack_ring()

	_update_move_arrow(bt)


func _update_move_arrow(bt: float) -> void:
	var current_beat := int(bt / BeatClock.beat_duration())
	var show_arrow := _enemy_move_enabled and not metronome.dead \
		and not metronome.knocked_back and metronome.stun_beats == 0 \
		and current_beat % 4 != 3
	if not show_arrow:
		_dummy_move_arrow_inst.visible = false
		return
	var dir := player.global_position - metronome.base_pos
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		_dummy_move_arrow_inst.global_position = Vector3(metronome.base_pos.x, 0.02, metronome.base_pos.z)
		_dummy_move_arrow_inst.rotation.y = atan2(dir.x, dir.z)
		_dummy_move_arrow_inst.visible = true
	else:
		_dummy_move_arrow_inst.visible = false


func _on_enemy_posture_broke(enemy: BaseEnemy) -> void:
	super._on_enemy_posture_broke(enemy)
	_enemy_hit_time_bt = -1.0


func _on_enemy_died(with_ragdoll: bool, enemy: BaseEnemy) -> void:
	super._on_enemy_died(with_ragdoll, enemy)
	_enemy_hit_time_bt = -1.0
	_dummy_move_arrow_inst.visible = false
	hud.show_timing("Entering boss arena...", Color(0.9, 0.7, 0.3))
	get_tree().create_timer(3.0).timeout.connect(
		func(): get_tree().change_scene_to_file("res://levels/boss/boss_level.tscn")
	)


func _reset() -> void:
	super._reset()
	metronome.reset_state()
	_enemy_hit_time_bt = -1.0
	_dummy_move_arrow_inst.visible = false


func _setup_move_arrow() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.1, 0.9)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
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


func _draw_ground_instructions() -> void:
	var label := Label3D.new()
	label.text = (
		"Parry attacks and attack on beat to build posture break\n"
		+ "Posture break gauge filled = stun for a measure\n"
		+ "Hold & release R2 for critical attack\n"
		+ "Crits consume active combo for bonus damage"
	)
	label.font_size = 14
	label.pixel_size = 0.009
	label.outline_size = 5
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.modulate = Color(1.0, 0.95, 0.8, 1.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.rotation_degrees.x = -90.0
	label.position = metronome.global_position + Vector3(-0.9, 0.08, metronome.attack_radius + 1.0)
	add_child(label)


func _setup_floor() -> void:
	var floor_mesh: MeshInstance3D = $Floor/MeshInstance3D
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in range(64):
		for x in range(64):
			var dark: bool = ((x >> 5) + (y >> 5)) % 2 == 0
			img.set_pixel(x, y, Color(0.22, 0.22, 0.26) if dark else Color(0.34, 0.34, 0.40))
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(20.0, 20.0, 1.0)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_mesh.set_surface_override_material(0, mat)
