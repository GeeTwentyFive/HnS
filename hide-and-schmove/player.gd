class_name Player
extends RigidBody3D


const RUN_SPEED = 25.0
const WALK_SPEED = RUN_SPEED / 2
const JUMP_IMPULSE = 6.0
const LOCAL_PLAYER_BODY_TRANSPARENCY = 0.1


@export var is_local_player: bool = false
var is_seeker: bool = false:
	set(x):
		is_seeker = x
		var alpha := LOCAL_PLAYER_BODY_TRANSPARENCY if is_local_player else 1.0
		if is_seeker:
			%Body.get_surface_override_material(0).albedo_color = Color(1.0, 0.0, 0.0, alpha)
		else:
			%Body.get_surface_override_material(0).albedo_color = Color(0.0, 0.0, 1.0, alpha)
var sensitivity: float = 0.01
var pause_input: bool = false
var move_speed := RUN_SPEED
var yaw := 0.0:
	set(x):
		yaw = x
		# TODO
var pitch := 0.0:
	set(x):
		pitch = x
		# TODO
var flashlight: bool = false:
	set(x):
		%Flashlight.visible = x
		flashlight = x


signal died


func _ready() -> void:
	if not is_local_player: return
	
	Input.use_accumulated_input = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	var material: StandardMaterial3D = %Body.get_surface_override_material(0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	material.albedo_color.a = LOCAL_PLAYER_BODY_TRANSPARENCY


func _input(event: InputEvent) -> void:
	if not is_local_player or pause_input: return
	
	if event is InputEventMouseMotion:
		yaw += event.screen_relative.x * sensitivity
		yaw = fmod(yaw, TAU)
		%Body.transform.basis = Basis()
		%Body.rotate_object_local(Vector3.UP, -yaw)
		
		pitch += event.screen_relative.y * sensitivity
		pitch = clampf(pitch, -PI/2, PI/2)
		%Head.transform.basis = Basis()
		%Head.rotate_object_local(Vector3.RIGHT, -pitch)


func _physics_process(_delta: float) -> void:
	if not is_local_player: return
	
	if global_position.y < 0.0:
		died.emit()
	
	var is_on_ground: bool = false
	for body in %Floor_Collider.get_overlapping_bodies():
		if body == self: continue
		is_on_ground = true
	
	var is_at_wall: bool = false
	for body in %Wall_Collider.get_overlapping_bodies():
		if body == self: continue
		is_at_wall = true
	
	if pause_input: return
	
	var movement_direction := Input.get_vector(
		"Left",
		"Right",
		"Forward",
		"Back"
	)
	if movement_direction:
		movement_direction = movement_direction.rotated(yaw)
		apply_central_force(
			Vector3(movement_direction.x, 0.0, movement_direction.y) *
			move_speed
		)
	
	if Input.is_action_just_pressed("Jump"):
		if is_on_ground:
			if linear_velocity.y < 0.0:
				linear_velocity.y = 0.0
			apply_central_impulse(Vector3(0.0, JUMP_IMPULSE, 0.0))
		
		elif is_at_wall:
			apply_central_impulse(
				Vector3(movement_direction.x, JUMP_IMPULSE, movement_direction.y)
			)
	
	if Input.is_action_pressed("Slide"):
		physics_material_override.friction = 0.0
	else: physics_material_override.friction = 1.0
	
	if Input.is_action_just_pressed("Flashlight"):
		flashlight = not flashlight
