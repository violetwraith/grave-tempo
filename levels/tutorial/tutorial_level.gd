extends BaseLevel
class_name TutorialLevel

const DUMMY_MOVE_SPEED := 3.0
const DUMMY_MOVE_EASE := 3.0

@onready var metronome: MetronomeDummy = $MetronomeDummy

var _dummy_move_enabled: bool = false
var _dummy_attack_dir: Vector3 = Vector3(0.0, 0.0, 1.0)
var _dummy_move_arrow_inst: MeshInstance3D = null


func _ready() -> void:
	metronome.player_entered_range.connect(func(): _in_range = true)
	metronome.player_exited_range.connect(func(): _in_range = false; _stop_ting())
	metronome.player_body_contact.connect(_on_player_body_contact)
	metronome.posture_broke.connect(_on_enemy_posture_broke)
	metronome.died.connect(_on_enemy_died)

	super._ready()

	_setup_move_arrow()
	_setup_floor()


func _get_current_target() -> BaseEnemy:
	return metronome


func _get_lock_on_candidates() -> Array[Node3D]:
	var candidates: Array[Node3D] = []
	if not metronome.dead:
		candidates.append(metronome)
	return candidates


func _get_attack_dir() -> Vector3:
	return _dummy_attack_dir


func _on_ting_expired_cleanup() -> void:
	metronome.hide_attack_ring()


func _on_beat(beat_number: int) -> void:
	super._on_beat(beat_number)
	if _player_dead or metronome.dead:
		return

	var is_attack_beat := beat_number % 4 == 0
	var is_move_beat := not is_attack_beat

	if is_attack_beat:
		metronome.cancel_move()

	if is_move_beat:
		if metronome.stun_beats > 0:
			metronome.tick_stun()
		elif _dummy_move_enabled and not metronome.knocked_back:
			var bd := BeatClock.beat_duration()
			var dir := player.global_position - metronome.base_pos
			dir.y = 0.0
			if dir.length_squared() > 0.001:
				dir = dir.normalized()
				var from := metronome.base_pos
				var to := from + dir * DUMMY_MOVE_SPEED * bd
				metronome.start_move(from, to, BeatClock.get_beat_time(), DUMMY_MOVE_EASE)
			else:
				metronome.cancel_move()
		else:
			metronome.cancel_move()

	if beat_number % 4 == 3 and metronome.stun_beats == 0:
		var atk_dir := player.global_position - metronome.base_pos
		atk_dir.y = 0.0
		_dummy_attack_dir = atk_dir.normalized() if atk_dir.length_squared() > 0.001 else Vector3(0.0, 0.0, 1.0)
		_enemy_hit_time_bt = BeatClock.get_beat_time() + float(ENEMY_WINDUP_BEATS) * BeatClock.beat_duration()


func _process(delta: float) -> void:
	super._process(delta)
	var bt := BeatClock.get_beat_time()
	if bt < 0.0:
		return

	# Attack ring countdown
	if _enemy_hit_time_bt > 0.0:
		var remaining := _enemy_hit_time_bt - bt
		var total := float(ENEMY_WINDUP_BEATS) * BeatClock.beat_duration()
		var progress := 1.0 - remaining / total
		metronome.update_attack_ring(progress, _dummy_attack_dir)
		if remaining <= 0.0:
			_enemy_hit_time_bt = -1.0
			metronome.hide_attack_ring()

	# Move arrow
	var current_beat_num := int(bt / BeatClock.beat_duration())
	var show_arrow := _dummy_move_enabled and not metronome.dead \
		and not metronome.knocked_back and metronome.stun_beats == 0 \
		and current_beat_num % 4 != 3
	if show_arrow:
		var dir_arr := player.global_position - metronome.base_pos
		dir_arr.y = 0.0
		if dir_arr.length_squared() > 0.01:
			_dummy_move_arrow_inst.global_position = Vector3(metronome.base_pos.x, 0.02, metronome.base_pos.z)
			_dummy_move_arrow_inst.rotation.y = atan2(dir_arr.x, dir_arr.z)
			_dummy_move_arrow_inst.visible = true
		else:
			_dummy_move_arrow_inst.visible = false
	else:
		_dummy_move_arrow_inst.visible = false


func _handle_extra_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_ting"):
		_ting_enabled = not _ting_enabled
		hud.set_ting_enabled(_ting_enabled)
	elif event.is_action_pressed("toggle_move"):
		_dummy_move_enabled = not _dummy_move_enabled
		if not _dummy_move_enabled:
			metronome.cancel_move()
		hud.show_timing("Move: %s" % ("ON" if _dummy_move_enabled else "OFF"), Color(0.8, 0.8, 0.8))


func _on_player_body_contact() -> void:
	if not _player_dead and not metronome.dead:
		var dir := player.global_position - metronome.base_pos
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			dir = dir.normalized()
		_take_damage(dir, PLAYER_CONTACT_KB)


func _on_enemy_posture_broke() -> void:
	_enemy_hit_time_bt = -1.0
	metronome.hide_attack_ring()
	_stop_ting()


func _on_enemy_died(_with_ragdoll: bool) -> void:
	BeatClock.detach_music()
	_stop_ting()
	_enemy_hit_time_bt = -1.0
	_quick_attack_pending = false
	player.set_attack_charging(false)
	_locked_on = false
	player.lock_on_target = null
	_dummy_move_arrow_inst.visible = false


func _reset() -> void:
	super._reset()
	metronome.reset_state()
	_dummy_attack_dir = Vector3(0.0, 0.0, 1.0)
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
