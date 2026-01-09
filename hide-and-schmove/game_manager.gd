extends Node


const SETTINGS_PATH = "HnS_settings.json"
const PORT = 55555
const CONNECT_TIMEOUT = 5000
const TEMP_RESULTS_FILE_NAME = "_HnS_RESULTS.json"
@onready var JSON_ARRAY_VIEWER_PATH = "deps/JSONArrayViewer" + ".exe" if (OS.get_name() == "Windows") else ""


enum PacketType {
	PLAYER_SYNC,
	PLAYER_SET_NAME,
	PLAYER_READY,
	PLAYER_HIDER_CAUGHT,
	PLAYER_STATS,
	PLAYER_DISCONNECTED,
	
	CONTROL_MAP_DATA,
	CONTROL_GAME_START,
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
}:
	set(x):
		settings = x
		FileAccess.open(
			SETTINGS_PATH,
			FileAccess.WRITE
		).store_string(JSON.stringify(settings, "\t"))

var client: ENetConnection
var server: ENetPacketPeer

var hider_spawn := Vector3(0.0, 0.0, 0.0)
var seeker_spawn := Vector3(0.0, 10.0, 0.0)

@onready var local_player := Player.new()
var map_loaded := false
var remote_players: Dictionary[int, Player] = {}


func LoadMap(map_json: String):
	var map_data = JSON.parse_string(map_json)
	if map_data == null:
		OS.alert("ERROR: Failed to load map")
		return
	for map_object in map_data:
		match map_object["type"].get_basename():
			"Box":
				var box_mesh := MeshInstance3D.new()
				box_mesh.mesh = BoxMesh.new()
				box_mesh.mesh.size = Vector3(
					map_object["scale"][0],
					map_object["scale"][1],
					map_object["scale"][2]
				)
				var material := StandardMaterial3D.new()
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
				material.albedo_color.r8 = int(map_object["data"]["Color R"]) # TODO
				material.albedo_color.g8 = int(map_object["data"]["Color G"])
				material.albedo_color.b8 = int(map_object["data"]["Color B"])
				material.albedo_color.a8 = int(map_object["data"]["Color A"])
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
				add_child(box)
			
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
				add_child(light)
			
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

#func StartGame() -> void:
	#%Players_Connected_Update_Timer.stop()
	#
	## Spawn local player
	#add_child(local_player)
	#
	## Spawn remote players
	#for player_id in sns.states.keys():
		#if player_id == sns.local_id: continue
		#players[player_id] = Player.new()
		#add_child(players[player_id])
	#
	#%Loading_Screen.visible = false
	#
	#get_tree().paused = false

func _ready() -> void:
	get_tree().paused = true
	
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
		OS.alert("USAGE: -- <SERVER_IP>")
		get_tree().quit(0)
	
	client = ENetConnection.new()
	if client.create_host(1, 1) != OK:
		OS.alert("Failed to create ENet host")
		get_tree().quit(1)
	server = client.connect_to_host(args[0], PORT, 1)
	if client.service(CONNECT_TIMEOUT)[0] != ENetConnection.EventType.EVENT_CONNECT:
		OS.alert("Failed to connect to server")
	
	var initial_sync_packet: PackedByteArray
	initial_sync_packet.resize(1 + 1 + 4*3 + 4 + 4 + 1 + 4*3)
	initial_sync_packet.encode_u8(0, PacketType.PLAYER_SYNC)
	initial_sync_packet.encode_u8(1, -1)
	initial_sync_packet.encode_float(2, local_player.position.x)
	initial_sync_packet.encode_float(6, local_player.position.y)
	initial_sync_packet.encode_float(10, local_player.position.z)
	initial_sync_packet.encode_float(14, local_player.yaw)
	initial_sync_packet.encode_float(18, local_player.pitch)
	var player_state_flags := 0
	player_state_flags |= (1 if local_player.alive else 0) << 0
	player_state_flags |= (1 if local_player.is_seeker else 0) << 1
	player_state_flags |= (1 if local_player.jumped else 0) << 2
	player_state_flags |= (1 if local_player.walljumped else 0) << 3
	player_state_flags |= (1 if local_player.sliding else 0) << 4
	player_state_flags |= (1 if local_player.flashlight else 0) << 5
	initial_sync_packet.encode_u8(22, player_state_flags)
	initial_sync_packet.encode_float(23, local_player.hook_point.x)
	initial_sync_packet.encode_float(27, local_player.hook_point.y)
	initial_sync_packet.encode_float(31, local_player.hook_point.z)
	server.send(0, initial_sync_packet, ENetPacketPeer.FLAG_RELIABLE)
	
	var set_name_packet: PackedByteArray
	set_name_packet.resize(1)
	set_name_packet.encode_u8(0, PacketType.PLAYER_SET_NAME)
	set_name_packet.append_array(local_player.name.to_ascii_buffer())
	server.send(0, set_name_packet, ENetPacketPeer.FLAG_RELIABLE)
	
	%Players_Connected_Update_Timer.start()

func _process(_delta: float) -> void:
	var packet_data = client.service()
	match packet_data[0]:
		ENetConnection.EventType.EVENT_DISCONNECT:
			OS.alert("Disconnected from server")
			get_tree().quit(0)
		
		ENetConnection.EventType.EVENT_RECEIVE:
			var received_data: PackedByteArray = packet_data[2]
			match received_data[0]:
				PacketType.PLAYER_SYNC:
					var player_id := received_data[1]
					
					if player_id not in remote_players.keys():
						remote_players[received_data[1]] = Player.new()
						add_child(remote_players[received_data[1]])
					
					remote_players[player_id].position.x = received_data.decode_float(2)
					remote_players[player_id].position.y = received_data.decode_float(6)
					remote_players[player_id].position.z = received_data.decode_float(10)
					remote_players[player_id].yaw = received_data.decode_float(14)
					remote_players[player_id].pitch = received_data.decode_float(18)
					var player_state_flags := received_data[22]
					remote_players[player_id].alive = (player_state_flags & PlayerStateFlags.ALIVE) > 0
					remote_players[player_id].is_seeker = (player_state_flags & PlayerStateFlags.IS_SEEKER) > 0
					remote_players[player_id].jumped = (player_state_flags & PlayerStateFlags.JUMPED) > 0
					remote_players[player_id].walljumped = (player_state_flags & PlayerStateFlags.WALLJUMPED) > 0
					remote_players[player_id].sliding = (player_state_flags & PlayerStateFlags.SLIDING) > 0
					remote_players[player_id].flashlight = (player_state_flags & PlayerStateFlags.FLASHLIGHT) > 0
					remote_players[player_id].hook_point.x = received_data.decode_float(23)
					remote_players[player_id].hook_point.y = received_data.decode_float(27)
					remote_players[player_id].hook_point.z = received_data.decode_float(31)
				
				PacketType.PLAYER_DISCONNECTED:
					var player_id := received_data[1]
					
					remote_players[player_id].queue_free()
					remote_players.erase(player_id)
				
				PacketType.PLAYER_STATS:
					var player_id := received_data[1]
					
					remote_players[player_id].name = ""
					for c in range(64):
						if received_data[2+c] == 0: break
						remote_players[player_id].name += char(received_data[2+c])
					remote_players[player_id].set_meta("seek_time", received_data.decode_float(66))
					remote_players[player_id].set_meta("last_alive_rounds", received_data.decode_float(70))
					remote_players[player_id].set_meta("points", received_data.decode_float(74))
				
				
				PacketType.CONTROL_MAP_DATA:
					pass # TODO
				
				PacketType.CONTROL_GAME_START:
					pass # TODO
				
				PacketType.CONTROL_GAME_END:
					pass # TODO

func _physics_process(_delta: float) -> void:
	# Synchronize local player state
	var sync_packet: PackedByteArray
	sync_packet.resize(1 + 1 + 4*3 + 4 + 4 + 1 + 4*3)
	sync_packet.encode_u8(0, PacketType.PLAYER_SYNC)
	sync_packet.encode_u8(1, -1)
	sync_packet.encode_float(2, local_player.position.x)
	sync_packet.encode_float(6, local_player.position.y)
	sync_packet.encode_float(10, local_player.position.z)
	sync_packet.encode_float(14, local_player.yaw)
	sync_packet.encode_float(18, local_player.pitch)
	var player_state_flags := 0
	player_state_flags |= (1 if local_player.alive else 0) << 0
	player_state_flags |= (1 if local_player.is_seeker else 0) << 1
	player_state_flags |= (1 if local_player.jumped else 0) << 2
	player_state_flags |= (1 if local_player.walljumped else 0) << 3
	player_state_flags |= (1 if local_player.sliding else 0) << 4
	player_state_flags |= (1 if local_player.flashlight else 0) << 5
	sync_packet.encode_u8(22, player_state_flags)
	sync_packet.encode_float(23, local_player.hook_point.x)
	sync_packet.encode_float(27, local_player.hook_point.y)
	sync_packet.encode_float(31, local_player.hook_point.z)
	server.send(0, sync_packet, 0)
	
	# Synchronize remote players states
	for player_id in players.keys():
		if player_id == sns.local_id: continue
		var remote_player := players[player_id]
		var remote_player_state = JSON.parse_string(sns.states[player_id])
		if remote_player_state == null: continue
		remote_player.position.x = remote_player_state["pos"][0]
		remote_player.position.x = remote_player_state["pos"][1]
		remote_player.position.x = remote_player_state["pos"][2]
		remote_player.yaw = remote_player_state["yaw"]
		remote_player.pitch = remote_player_state["pitch"]
		remote_player.alive = remote_player_state["alive"]
		remote_player.is_seeker = remote_player_state["is_seeker"]
		remote_player.last_caught_hider = players[int(remote_player_state["last_caught_hider_id"])]
		remote_player.seek_time = remote_player_state["seek_time"]
		remote_player.last_alive_rounds = int(remote_player_state["last_alive_rounds"])
		remote_player.jumped = remote_player_state["jumped"]
		remote_player.walljumped = remote_player_state["walljumped"]
		remote_player.slide_sound_playing = remote_player_state["slide_sound_playing"]
		remote_player.hooked = remote_player_state["hooked"]
		remote_player.hook_point.x = remote_player_state["hook_point"][0]
		remote_player.hook_point.y = remote_player_state["hook_point"][1]
		remote_player.hook_point.z = remote_player_state["hook_point"][2]
		remote_player.flashlight = remote_player_state["flashlight"]
	
	# Handle game end
	if sns.states[host_id]["host_data"]["game_ended"]:
		var sorted_seek_times: Dictionary[float, int]
		for player_id in players:
			sorted_seek_times[players[player_id]["seek_time"]] = player_id
		sorted_seek_times.sort()
		
		var players_points: Dictionary[int, int]
		for i in range(sorted_seek_times.keys().size()):
			players_points[sorted_seek_times[sorted_seek_times.keys()[i]]] = (
				# player_count - seek_time_placement (starting from 1, not 0)
				(players.size() - i+1) +
				# + last_alive_rounds
				players[sorted_seek_times[sorted_seek_times.keys()[i]]].last_alive_rounds
			)
		
		var scoring_data: Array[Dictionary]
		for seek_time in sorted_seek_times.keys():
			scoring_data.append({
				"name": players[sorted_seek_times[seek_time]].name,
				"seek_time": seek_time,
				"last_alive_rounds": players[sorted_seek_times[seek_time]].last_alive_rounds,
				"points": players_points[sorted_seek_times[seek_time]]
			})
		var temp_results_file_path := OS.get_cache_dir().path_join(TEMP_RESULTS_FILE_NAME)
		FileAccess.open(
			temp_results_file_path,
			FileAccess.WRITE
		).store_string(JSON.stringify(scoring_data))
		OS.create_process(JSON_ARRAY_VIEWER_PATH, [temp_results_file_path])
		
		get_tree().quit(0)
	
	var alive_hiders := 0
	for player_id in players.keys():
		if players[player_id].is_seeker: continue
		if players[player_id].alive:
			alive_hiders += 1
	
	if int(sns.states[host_id]["current_seeker"]) != -1:
		if int(sns.states[host_id]["current_seeker"]) != current_seeker_id:
			# ^ new round
			if current_seeker_id == sns.local_id:
				players[sns.local_id].position = seeker_spawn
				players[sns.local_id].alive = true
				players[sns.local_id].is_seeker = true
			else:
				players[sns.local_id].position = hider_spawn
				players[sns.local_id].alive = true
				players[sns.local_id].is_seeker = false
		
		current_seeker_id = int(sns.states[host_id]["current_seeker"])
		
		if current_seeker_id != sns.local_id:
			var seeker := players[current_seeker_id]
			if seeker.last_caught_hider == players[sns.local_id]:
				if alive_hiders == 1:
					players[sns.local_id].last_alive_rounds += 1
				players[sns.local_id].alive = false
	
	# Host game management
	if local_state["host"]:
		if alive_hiders == 0:
			for i in range(players.keys().size()):
				if players.keys()[i] == current_seeker_id:
					if i == players.keys().size()-1:
						local_state["host_data"]["game_ended"] = true
					local_state["host_data"]["current_seeker"] = players.keys()[i+1]
	
	sns.send(JSON.stringify(local_state))

func _on_ready_button_pressed() -> void:
	pass # TODO

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if not %Settings_Popup.visible:
					local_player.pause_input = true
					%Settings_Name.text = local_player.name
					%Settings_Sensitivity.set_value_no_signal(local_player.sensitivity)
					%Settings_Popup.show()
				else:
					%Settings_Popup.hide()
					local_player.pause_input = false


#region CALLBACKS

func _on_players_connected_update_timer_timeout() -> void:
	%Players_Connected_Label.text = str(remote_players.keys().size())

func _on_settings_name_text_submitted(new_text: String) -> void:
	settings["name"] = new_text

func _on_settings_sensitivity_value_changed(value: float) -> void:
	settings["sensitivity"] = value
	local_player.sensitivity = value

func _on_exit_button_pressed() -> void:
	get_tree().quit(0)

#endregion CALLBACKS
