extends CharacterBody3D
class_name Player

signal died
signal hp_changed(hp: int, max_hp: int)

const MOVE_SPEED := 5.0
const JUMP_VELOCITY := 7.0
const GRAVITY := -20.0
const CAM_DISTANCE := 4
const CAM_HEIGHT_OFFSET := 2
const CONTROLLER_H_SENSITIVITY := 150.0
const CONTROLLER_V_SENSITIVITY := 100.0
const MOUSE_SENSITIVITY := 0.3
const CAMERA_PITCH_MIN := -50.0
const CAMERA_PITCH_MAX := 25.0
const ROTATION_SPEED := 10.0
const BLINK_INTERVAL := 0.07
const DASH_SPEED := 16.0
const DASH_DURATION := 0.22

# iframes granted on top of a hit's beat duration / the dash's duration.
const HIT_iframe_SECS := 0.25
const DASH_iframe_SECS := 0.06

@onready var camera: Camera3D = $Camera3D
@onready var _mesh: MeshInstance3D = $Mesh

var max_hp: int = 3
var hp: int = 3
var lock_on_target: Node3D = null

var _camera_yaw: float = 0.0
var _camera_pitch: float = -15.0
var _target_yaw: float = 0.0
var _spawn_position: Vector3
var _dead: bool = false
var _attack_charging: bool = false
var _dashing: bool = false
var _dash_timer: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO

# iframes run on wall-clock time so it survives the music detaching mid-fight.
var _iframe_until: float = -1.0
var _iframe_start: float = -1.0
var _iframe_from_dash: bool = false
var _blink_timer: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_spawn_position = global_position


func configure_max_hp(value: int) -> void:
	max_hp = maxi(value, 1)
	hp = max_hp
	hp_changed.emit(hp, max_hp)


func reset() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_dead = false
	_attack_charging = false
	_dashing = false
	_clear_iframe()
	_mesh.visible = true
	lock_on_target = null
	_camera_yaw = 0.0
	_camera_pitch = -15.0
	_target_yaw = 0.0
	hp = max_hp
	hp_changed.emit(hp, max_hp)


func is_dead() -> bool:
	return _dead


func is_iframe() -> bool:
	return _iframe_until >= 0.0 and _now() < _iframe_until


func is_dash_iframe() -> bool:
	return is_iframe() and _iframe_from_dash


func iframe_progress() -> float:
	if _iframe_until < 0.0:
		return 0.0
	var total := _iframe_until - _iframe_start
	return clampf(1.0 - (_now() - _iframe_start) / maxf(total, 0.001), 0.0, 1.0)


# Returns true if the hit landed (false when dead or iframes active).
func take_damage(knockback_dir: Vector3 = Vector3.ZERO, knockback_speed: float = 0.0) -> bool:
	if _dead or is_iframe():
		return false
	hp -= 1
	hp_changed.emit(hp, max_hp)
	if knockback_dir.length_squared() > 0.001 and knockback_speed > 0.0:
		apply_knockback(knockback_dir, knockback_speed)
	if hp <= 0:
		_dead = true
		_attack_charging = false
		_clear_iframe()
		_mesh.visible = false
		died.emit()
	else:
		grant_iframe(BeatClock.beat_duration() + HIT_iframe_SECS)
	return true


func grant_iframe(seconds: float, from_dash: bool = false) -> void:
	_iframe_start = _now()
	_iframe_until = _iframe_start + seconds
	_iframe_from_dash = from_dash
	_blink_timer = 0.0


func set_attack_charging(value: bool) -> void:
	_attack_charging = value


func start_dash(direction: Vector3) -> void:
	_dashing = true
	_dash_timer = 0.0
	var flat := Vector3(direction.x, 0.0, direction.z)
	_dash_dir = flat.normalized() if flat.length_squared() > 0.001 else \
		(global_transform.basis * Vector3(0.0, 0.0, -1.0)).normalized()
	grant_iframe(DASH_DURATION + DASH_iframe_SECS, true)


func apply_knockback(direction: Vector3, speed: float) -> void:
	var hop := clampf(speed * 0.76, 3.0, 8.0)
	velocity = direction.normalized() * speed + Vector3(0.0, hop, 0.0)


func _clear_iframe() -> void:
	_iframe_until = -1.0
	_iframe_start = -1.0
	_iframe_from_dash = false


func _now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_camera_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_camera_pitch -= event.relative.y * MOUSE_SENSITIVITY
		_camera_pitch = clamp(_camera_pitch, CAMERA_PITCH_MIN, CAMERA_PITCH_MAX)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_jump()
	_handle_controller_camera(delta)
	_update_dash(delta)
	_handle_movement(delta)
	_rotate_toward_movement(delta)
	move_and_slide()


func _process(delta: float) -> void:
	_update_camera()
	_update_iframe_blink(delta)


func _update_iframe_blink(delta: float) -> void:
	if _iframe_until < 0.0:
		return
	if _now() >= _iframe_until:
		_clear_iframe()
		_mesh.visible = not _dead
		return
	_blink_timer += delta
	_mesh.visible = fmod(_blink_timer, BLINK_INTERVAL * 2.0) < BLINK_INTERVAL


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta


func _handle_jump() -> void:
	if _dead:
		return
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY


func _update_dash(delta: float) -> void:
	if not _dashing:
		return
	_dash_timer += delta
	if _dash_timer >= DASH_DURATION:
		_dashing = false


func _handle_movement(_delta: float) -> void:
	if _dead:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	if _dashing:
		velocity.x = _dash_dir.x * DASH_SPEED
		velocity.z = _dash_dir.z * DASH_SPEED
		return
	var stick := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if _attack_charging:
		velocity.x = 0.0
		velocity.z = 0.0
		if stick.length_squared() > 0.01:
			var cb := Basis(Vector3.UP, deg_to_rad(_camera_yaw))
			var fwd := (cb * Vector3(stick.x, 0.0, stick.y)).normalized()
			_target_yaw = atan2(-fwd.x, -fwd.z)
		return
	if stick.length_squared() < 0.01:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var cam_basis := Basis(Vector3.UP, deg_to_rad(_camera_yaw))
	var direction := (cam_basis * Vector3(stick.x, 0.0, stick.y)).normalized()
	velocity.x = direction.x * MOVE_SPEED
	velocity.z = direction.z * MOVE_SPEED
	_target_yaw = atan2(-direction.x, -direction.z)


func _rotate_toward_movement(delta: float) -> void:
	if lock_on_target != null and is_instance_valid(lock_on_target):
		var to_target := lock_on_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.001:
			_target_yaw = atan2(-to_target.x, -to_target.z)
	rotation.y = lerp_angle(rotation.y, _target_yaw, ROTATION_SPEED * delta)


func _handle_controller_camera(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length_squared() > 0.01:
		if lock_on_target == null:
			_camera_yaw -= look.x * CONTROLLER_H_SENSITIVITY * delta
		_camera_pitch -= look.y * CONTROLLER_V_SENSITIVITY * delta
		_camera_pitch = clamp(_camera_pitch, CAMERA_PITCH_MIN, CAMERA_PITCH_MAX)


func _update_camera() -> void:
	if lock_on_target != null and is_instance_valid(lock_on_target):
		var to_target := lock_on_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.001:
			_camera_yaw = rad_to_deg(atan2(-to_target.x, -to_target.z))
	var offset := Vector3(0.0, 0.0, CAM_DISTANCE)
	offset = offset.rotated(Vector3.RIGHT, deg_to_rad(_camera_pitch))
	offset = offset.rotated(Vector3.UP, deg_to_rad(_camera_yaw))
	var look_target := global_position + Vector3(0.0, CAM_HEIGHT_OFFSET, 0.0)
	camera.global_position = look_target + offset
	camera.look_at(look_target, Vector3.UP)
