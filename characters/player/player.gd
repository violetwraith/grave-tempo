extends CharacterBody3D
class_name Player

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

@onready var camera: Camera3D = $Camera3D
@onready var _mesh: MeshInstance3D = $Mesh

var lock_on_target: Node3D = null

var _camera_yaw: float = 0.0
var _camera_pitch: float = -15.0
var _target_yaw: float = 0.0
var _spawn_position: Vector3
var _iframe: bool = false
var _blink_timer: float = 0.0
var _attack_charging: bool = false
var _dead: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_spawn_position = global_position


func reset() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_iframe = false
	_attack_charging = false
	_dead = false
	_mesh.visible = true
	lock_on_target = null


func set_attack_charging(value: bool) -> void:
	_attack_charging = value


func set_dead(value: bool) -> void:
	_dead = value


func hide_mesh() -> void:
	_mesh.visible = false


func apply_knockback(direction: Vector3, speed: float) -> void:
	var hop := clampf(speed * 0.76, 3.0, 8.0)
	velocity = direction.normalized() * speed + Vector3(0.0, hop, 0.0)


func start_iframe() -> void:
	_iframe = true
	_blink_timer = 0.0


func end_iframe() -> void:
	_iframe = false
	_mesh.visible = true


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
	_handle_movement(delta)
	_rotate_toward_movement(delta)
	move_and_slide()


func _process(delta: float) -> void:
	_update_camera()
	if _iframe:
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


func _handle_movement(_delta: float) -> void:
	if _dead:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var stick := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if _attack_charging:
		velocity.x = 0.0
		velocity.z = 0.0
		if stick.length_squared() > 0.01:
			var cam_basis := Basis(Vector3.UP, deg_to_rad(_camera_yaw))
			var direction := (cam_basis * Vector3(stick.x, 0.0, stick.y)).normalized()
			_target_yaw = atan2(-direction.x, -direction.z)
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
