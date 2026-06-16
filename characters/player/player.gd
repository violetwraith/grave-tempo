extends CharacterBody3D
class_name Player

const MOVE_SPEED := 5.0
const JUMP_VELOCITY := 7.0
const GRAVITY := -20.0
const CAM_DISTANCE := 3.0
const CAM_HEIGHT_OFFSET := 1.5
const CONTROLLER_H_SENSITIVITY := 150.0
const CONTROLLER_V_SENSITIVITY := 100.0
const MOUSE_SENSITIVITY := 0.3
const CAMERA_PITCH_MIN := -50.0
const CAMERA_PITCH_MAX := 25.0
const ROTATION_SPEED := 10.0

@onready var camera: Camera3D = $Camera3D

var _camera_yaw: float = 0.0
var _camera_pitch: float = -15.0
var _target_yaw: float = 0.0
var _spawn_position: Vector3


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_spawn_position = global_position


func reset() -> void:
	global_position = _spawn_position
	velocity = Vector3.ZERO


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
	_handle_movement()
	_rotate_toward_movement(delta)
	move_and_slide()


func _process(_delta: float) -> void:
	_update_camera()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta


func _handle_jump() -> void:
	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY


func _handle_movement() -> void:
	var stick := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
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
	rotation.y = lerp_angle(rotation.y, _target_yaw, ROTATION_SPEED * delta)


func _handle_controller_camera(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length_squared() > 0.01:
		_camera_yaw -= look.x * CONTROLLER_H_SENSITIVITY * delta
		_camera_pitch -= look.y * CONTROLLER_V_SENSITIVITY * delta
		_camera_pitch = clamp(_camera_pitch, CAMERA_PITCH_MIN, CAMERA_PITCH_MAX)


func _update_camera() -> void:
	var offset := Vector3(0.0, 0.0, CAM_DISTANCE)
	offset = offset.rotated(Vector3.RIGHT, deg_to_rad(_camera_pitch))
	offset = offset.rotated(Vector3.UP, deg_to_rad(_camera_yaw))
	var look_target := global_position + Vector3(0.0, CAM_HEIGHT_OFFSET, 0.0)
	camera.global_position = look_target + offset
	camera.look_at(look_target, Vector3.UP)
