class_name Player
extends RigidBody3D


const RUN_SPEED = 25.0
const WALK_SPEED = RUN_SPEED / 2
const JUMP_IMPULSE = 6.0
const LOCAL_PLAYER_BODY_TRANSPARENCY = 0.1
const WALLJUMP_SOUND_PITCH_SCALE = 1.2
const HOOK_POINT_SOUND = preload("res://Audio/impactSoft_heavy_000.ogg")


@export var is_local_player: bool = false
var is_seeker: bool = false:
	set(x):
		is_seeker = x
		var alpha := LOCAL_PLAYER_BODY_TRANSPARENCY if is_local_player else 1.0
		if is_seeker:
			%Body.get_surface_override_material(0).albedo_color = Color(1.0, 0.0, 0.0, alpha)
		else:
			%Body.get_surface_override_material(0).albedo_color = Color(0.0, 0.0, 1.0, alpha)
var alive: bool = true:
	set(x):
		alive = x
		if alive: is_seeker = is_seeker
		else: # vvv (to maintain alpha) vvv
			%Body.get_surface_override_material(0).albedo_color.r = 1.0
			%Body.get_surface_override_material(0).albedo_color.g = 1.0
			%Body.get_surface_override_material(0).albedo_color.b = 1.0
var seek_time := 0.0
var last_alive_rounds := 0
var sensitivity: float = 0.01
var pause_input: bool = false
var move_speed := RUN_SPEED
var yaw := 0.0
var pitch := 0.0
var jumped := false
var walljumped := false
var slide_sound_playing := false
var hooked := false
var hook_point := Vector3.ZERO
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


var last_jumped := jumped
var last_walljumped := walljumped
@onready var hook_material = StandardMaterial3D.new()
var last_hooked := hooked
func _physics_process(delta: float) -> void:
	if is_seeker:
		seek_time += delta
	
	if jumped and not last_jumped:
		%Jump_Sound.pitch_scale = 1.0
		%Jump_Sound.play()
	last_jumped = jumped
	
	if walljumped and not last_walljumped:
		%Jump_Sound.pitch_scale = WALLJUMP_SOUND_PITCH_SCALE
		%Jump_Sound.play()
	last_walljumped = walljumped
	
	if slide_sound_playing:
		if not %Slide_Sound.playing:
			%Slide_Sound.play()
	else: %Slide_Sound.stop()
	
	%Hook.mesh.clear_surfaces()
	if hooked:
		if is_local_player:
			apply_central_force(
				(hook_point - %Hook.global_position).normalized() *
				move_speed
			)
		
		%Hook.mesh.surface_begin(Mesh.PRIMITIVE_LINES, hook_material)
		%Hook.mesh.surface_add_vertex(Vector3.ZERO)
		%Hook.mesh.surface_add_vertex(to_local(hook_point).rotated(Vector3.UP, yaw))
		%Hook.mesh.surface_end()
		
		if last_hooked == false:
			var hook_point_sound := AudioStreamPlayer3D.new()
			hook_point_sound.position = hook_point
			hook_point_sound.stream = HOOK_POINT_SOUND
			hook_point_sound.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
			hook_point_sound.autoplay = true
			hook_point_sound.finished.connect(
				func(): hook_point_sound.queue_free()
			)
			get_tree().root.add_child(hook_point_sound)
	last_hooked = hooked
	
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
	
	jumped = false
	walljumped = false
	if Input.is_action_just_pressed("Jump"):
		if is_on_ground:
			if linear_velocity.y < 0.0:
				linear_velocity.y = 0.0
			apply_central_impulse(Vector3(0.0, JUMP_IMPULSE, 0.0))
			jumped = true
		
		elif is_at_wall:
			apply_central_impulse(
				Vector3(movement_direction.x, 1.0, movement_direction.y) *
				JUMP_IMPULSE
			)
			walljumped = true
	
	if Input.is_action_pressed("Slide"):
		physics_material_override.friction = 0.0
		
		if is_on_ground and linear_velocity.length() > 0.1:
			slide_sound_playing = true
		else: slide_sound_playing = false
	else:
		physics_material_override.friction = 1.0
		slide_sound_playing = false
	
	if Input.is_action_pressed("Hook") and not hooked:
		%Camera_Raycast.force_raycast_update()
		if %Camera_Raycast.is_colliding():
			hook_point = %Camera_Raycast.get_collision_point()
			hooked = true
	elif not Input.is_action_pressed("Hook"): hooked = false
	
	if Input.is_action_just_pressed("Flashlight"):
		flashlight = not flashlight
