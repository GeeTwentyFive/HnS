extends Node


@onready var SETTINGS_PATH := OS.get_cache_dir().path_join("HnS_settings.json")
const PORT = 55555
const CONNECT_TIMEOUT = 5000
@onready var TEMP_RESULTS_FILE_PATH := OS.get_temp_dir().path_join("_HnS_RESULTS.json")
@onready var JSON_ARRAY_VIEWER_PATH := "deps/JSONArrayViewer" + ".exe" if (OS.get_name() == "Windows") else ""

const NAME_LENGTH_PACKET_MAX = 64


const PLAYER_SCENE = preload("res://Player.tscn")


enum PacketType {
	PLAYER_SYNC,
	PLAYER_SET_NAME,
	PLAYER_READY,
	PLAYER_HIDER_CAUGHT,
	PLAYER_STATS,
	PLAYER_DISCONNECTED,
	
	CONTROL_MAP_DATA,
	CONTROL_GAME_START,
	CONTROL_SET_PLAYER_STATE,
	CONTROL_GAME_END
}

enum PlayerStateFlags {
	ALIVE = 1 << 0,
	IS_SEEKER = 1 << 1,
	JUMPED = 1 << 2,
	WALLJUMPED = 1 << 3,
	SLIDING = 1 << 4,
	FLASHLIGHT = 1 << 5
}


var settings: Dictionary = {
	"name": "Player",
	"sensitivity": 0.01
}
func set_settings_value(key: String, val):
	settings[key] = val
	FileAccess.open(
		SETTINGS_PATH,
		FileAccess.WRITE
	).store_string(JSON.stringify(settings, "\t"))

@onready var zec = ZPLENetClient.new()

var hider_spawn := Vector3(0.0, 1.0, 0.0)
var seeker_spawn := Vector3(0.0, 10.0, 0.0)

@onready var local_player := PLAYER_SCENE.instantiate()
var remote_players: Dictionary[int, Player] = {}
var remote_players_stats: Dictionary[int, Dictionary] = {}


func LoadMap(map_json: String):
	var map_data = JSON.parse_string(map_json)
	if map_data == null:
		OS.alert("ERROR: Failed to load map")
		get_tree().quit(1)
		return
	for map_object in map_data:
		match map_object["type"]:
			"Box":
				var box_mesh := MeshInstance3D.new()
				box_mesh.mesh = BoxMesh.new()
				box_mesh.mesh.size = Vector3(
					map_object["scale"][0],
					map_object["scale"][1],
					map_object["scale"][2]
				)
				var material := StandardMaterial3D.new()
				material.albedo_color.r8 = int(map_object["data"]["Color_R"])
				material.albedo_color.g8 = int(map_object["data"]["Color_G"])
				material.albedo_color.b8 = int(map_object["data"]["Color_B"])
				box_mesh.set_surface_override_material(0, material)
				var collision_shape := CollisionShape3D.new()
				collision_shape.shape = BoxShape3D.new()
				collision_shape.shape.size = Vector3(
					map_object["scale"][0],
					map_object["scale"][1],
					map_object["scale"][2]
				)
				var box := StaticBody3D.new()
				box.add_child(collision_shape)
				box.add_child(box_mesh)
				box.position = Vector3(
					map_object["pos"][0],
					map_object["pos"][1],
					map_object["pos"][2]
				)
				box.rotation_degrees = Vector3(
					map_object["rot"][0],
					map_object["rot"][1],
					map_object["rot"][2]
				)
				%World.add_child(box)
			
			"Light":
				var light := OmniLight3D.new()
				light.omni_attenuation = 2.0
				light.shadow_enabled = true
				light.light_energy = map_object["data"]["Brightness"]
				light.omni_range = map_object["data"]["Range"]
				light.position = Vector3(
					map_object["pos"][0],
					map_object["pos"][1],
					map_object["pos"][2]
				)
				%World.add_child(light)
			
			"Spawn_Hider":
				hider_spawn = Vector3(
					map_object["pos"][0],
					map_object["pos"][1],
					map_object["pos"][2]
				)
			
			"Spawn_Seeker":
				seeker_spawn = Vector3(
					map_object["pos"][0],
					map_object["pos"][1],
					map_object["pos"][2]
				)

func _ready() -> void:
	local_player.is_local_player = true
	
	# Generate user settings if they don't exist
	if not FileAccess.file_exists(SETTINGS_PATH):
		FileAccess.open(
			SETTINGS_PATH,
			FileAccess.WRITE
		).store_string(JSON.stringify(settings, "\t"))
	
	# Load settings
	var settings_json := JSON.new()
	if settings_json.parse(
		FileAccess.get_file_as_string(SETTINGS_PATH)
	) == OK:
		settings = settings_json.data
	else:
		FileAccess.open(
			SETTINGS_PATH,
			FileAccess.WRITE
		).store_string(JSON.stringify(settings, "\t"))
	
	local_player.name = settings["name"]
	local_player.sensitivity = settings["sensitivity"]
	
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		OS.alert("USAGE: -- <SERVER_IP> [PORT]")
		get_tree().quit(0)
		return
	
	var port: int = int(args[1]) if (args.size() >= 2) else PORT
	if zec.connect_to(args[0], port) != OK:
		OS.alert("Failed to connect to server (game already in progress?)")
		get_tree().quit(1)
		return
	zec.disconnected.connect(func():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		OS.alert("Disconnected from server")
		get_tree().quit(0)
	)
	
	local_player.caught_hider.connect(func(caught_hider: Player):
		var hider_caught_packet: PackedByteArray
		hider_caught_packet.resize(3)
		hider_caught_packet.encode_u8(0, PacketType.PLAYER_HIDER_CAUGHT)
		hider_caught_packet.encode_u16(1, remote_players.find_key(caught_hider))
		zec.send(hider_caught_packet)
	)
	
	var initial_sync_packet: PackedByteArray
	initial_sync_packet.resize(1 + 2 + 4*3 + 4 + 4 + 1 + 4*3)
	initial_sync_packet.encode_u8(0, PacketType.PLAYER_SYNC)
	initial_sync_packet.encode_u16(1, -1)
	initial_sync_packet.encode_float(3, local_player.position.x)
	initial_sync_packet.encode_float(7, local_player.position.y)
	initial_sync_packet.encode_float(11, local_player.position.z)
	initial_sync_packet.encode_float(15, local_player.yaw)
	initial_sync_packet.encode_float(19, local_player.pitch)
	var player_state_flags := 0
	player_state_flags |= (1 if local_player.alive else 0) << 0
	player_state_flags |= (1 if local_player.is_seeker else 0) << 1
	player_state_flags |= (1 if local_player.jumped else 0) << 2
	player_state_flags |= (1 if local_player.walljumped else 0) << 3
	player_state_flags |= (1 if local_player.sliding else 0) << 4
	player_state_flags |= (1 if local_player.flashlight else 0) << 5
	initial_sync_packet.encode_u8(23, player_state_flags)
	initial_sync_packet.encode_float(24, local_player.hook_point.x)
	initial_sync_packet.encode_float(28, local_player.hook_point.y)
	initial_sync_packet.encode_float(32, local_player.hook_point.z)
	zec.send(initial_sync_packet)
	
	var set_name_packet: PackedByteArray
	set_name_packet.resize(1)
	set_name_packet.encode_u8(0, PacketType.PLAYER_SET_NAME)
	set_name_packet.append_array(local_player.name.to_ascii_buffer())
	set_name_packet.resize(65) # Has to meet max length to be accepted by server
	zec.send(set_name_packet)

func _process(_delta: float) -> void:
	var _received_data: Array = zec.service()
	var received_data: Array[PackedByteArray]
	for data in _received_data:
		if data is PackedByteArray:
			received_data.append(data)
	for data in received_data:
		if (data.size() < 1): return
		
		match data.decode_u8(0):
			PacketType.PLAYER_SYNC:
				if (data.size() < 36): return
				
				var player_id := data.decode_u16(1)
				
				if player_id not in remote_players.keys():
					remote_players[player_id] = PLAYER_SCENE.instantiate()
					%World.add_child(remote_players[player_id])
					
					%Players_Connected_Label.text = str(1 + remote_players.size())
				
				remote_players[player_id].position.x = data.decode_float(3)
				remote_players[player_id].position.y = data.decode_float(7)
				remote_players[player_id].position.z = data.decode_float(11)
				remote_players[player_id].yaw = data.decode_float(15)
				remote_players[player_id].pitch = data.decode_float(19)
				var player_state_flags := data[23]
				remote_players[player_id].alive = (player_state_flags & PlayerStateFlags.ALIVE) > 0
				remote_players[player_id].is_seeker = (player_state_flags & PlayerStateFlags.IS_SEEKER) > 0
				remote_players[player_id].jumped = (player_state_flags & PlayerStateFlags.JUMPED) > 0
				remote_players[player_id].walljumped = (player_state_flags & PlayerStateFlags.WALLJUMPED) > 0
				remote_players[player_id].sliding = (player_state_flags & PlayerStateFlags.SLIDING) > 0
				remote_players[player_id].flashlight = (player_state_flags & PlayerStateFlags.FLASHLIGHT) > 0
				remote_players[player_id].hook_point.x = data.decode_float(24)
				remote_players[player_id].hook_point.y = data.decode_float(28)
				remote_players[player_id].hook_point.z = data.decode_float(32)
			
			PacketType.PLAYER_DISCONNECTED:
				if (data.size() < 3): return
				
				var player_id := data.decode_u16(1)
				
				if remote_players.has(player_id):
					remote_players[player_id].queue_free()
					remote_players.erase(player_id)
				
				%Players_Connected_Label.text = str(1 + remote_players.size())
			
			PacketType.PLAYER_STATS:
				if (data.size() < 73): return
				
				var player_id := data.decode_u16(1)
				
				var player_name := ""
				for c in range(NAME_LENGTH_PACKET_MAX):
					if data.decode_u8(3+c) == 0: break
					player_name += char(data.decode_u8(3+c))
				
				remote_players_stats[player_id] = {
					"name": player_name,
					"seek_time": data.decode_float(67),
					"last_alive_rounds": data.decode_u8(71),
					"points": data.decode_u8(72)
				}
			
			
			PacketType.CONTROL_MAP_DATA:
				data.remove_at(0)
				if (data.size() == 0): return
				LoadMap(data.get_string_from_ascii())
				%Ready_Button.disabled = false
			
			PacketType.CONTROL_GAME_START:
				%World.add_child(local_player)
				%Loading_Screen.visible = false
			
			PacketType.CONTROL_SET_PLAYER_STATE:
				if (data.size() < 34): return
				
				local_player.position.x = data.decode_float(1)
				local_player.position.y = data.decode_float(5)
				local_player.position.z = data.decode_float(9)
				local_player.yaw = data.decode_float(13)
				local_player.pitch = data.decode_float(17)
				var player_state_flags := data[21]
				local_player.alive = (player_state_flags & PlayerStateFlags.ALIVE) > 0
				local_player.is_seeker = (player_state_flags & PlayerStateFlags.IS_SEEKER) > 0
				local_player.jumped = (player_state_flags & PlayerStateFlags.JUMPED) > 0
				local_player.walljumped = (player_state_flags & PlayerStateFlags.WALLJUMPED) > 0
				local_player.sliding = (player_state_flags & PlayerStateFlags.SLIDING) > 0
				local_player.flashlight = (player_state_flags & PlayerStateFlags.FLASHLIGHT) > 0
				local_player.hook_point.x = data.decode_float(22)
				local_player.hook_point.y = data.decode_float(26)
				local_player.hook_point.z = data.decode_float(30)
			
			PacketType.CONTROL_GAME_END:
				FileAccess.open(
					TEMP_RESULTS_FILE_PATH,
					FileAccess.WRITE
				).store_string(JSON.stringify(remote_players_stats.values()))
				OS.create_process(JSON_ARRAY_VIEWER_PATH, [TEMP_RESULTS_FILE_PATH])
				
				get_tree().quit(0)
				return

func _physics_process(_delta: float) -> void:
	# Synchronize local player state
	var sync_packet: PackedByteArray
	sync_packet.resize(1 + 2 + 4*3 + 4 + 4 + 1 + 4*3)
	sync_packet.encode_u8(0, PacketType.PLAYER_SYNC)
	sync_packet.encode_u16(1, -1)
	sync_packet.encode_float(3, local_player.position.x)
	sync_packet.encode_float(7, local_player.position.y)
	sync_packet.encode_float(11, local_player.position.z)
	sync_packet.encode_float(15, local_player.yaw)
	sync_packet.encode_float(19, local_player.pitch)
	var player_state_flags := 0
	player_state_flags |= (1 if local_player.alive else 0) << 0
	player_state_flags |= (1 if local_player.is_seeker else 0) << 1
	player_state_flags |= (1 if local_player.jumped else 0) << 2
	player_state_flags |= (1 if local_player.walljumped else 0) << 3
	player_state_flags |= (1 if local_player.sliding else 0) << 4
	player_state_flags |= (1 if local_player.flashlight else 0) << 5
	sync_packet.encode_u8(23, player_state_flags)
	sync_packet.encode_float(24, local_player.hook_point.x)
	sync_packet.encode_float(28, local_player.hook_point.y)
	sync_packet.encode_float(32, local_player.hook_point.z)
	zec.send(sync_packet, false)

func _on_ready_button_pressed() -> void:
	var ready_packet: PackedByteArray
	ready_packet.resize(1)
	ready_packet.encode_u8(0, PacketType.PLAYER_READY)
	zec.send(ready_packet)
	%Ready_Button.disabled = true

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if not %Settings_Popup.visible:
					local_player.pause_input = true
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
					%Settings_Name.text = local_player.name
					%Settings_Sensitivity.set_value_no_signal(local_player.sensitivity)
					%Settings_Popup.show()


#region CALLBACKS

func _on_settings_name_text_submitted(new_text: String) -> void:
	set_settings_value("name", new_text)
	local_player.name = new_text

func _on_settings_sensitivity_value_changed(value: float) -> void:
	set_settings_value("sensitivity", value)
	local_player.sensitivity = value

func _on_exit_button_pressed() -> void:
	get_tree().quit(0)

func _on_settings_popup_popup_hide() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	local_player.pause_input = false

#endregion CALLBACKS
