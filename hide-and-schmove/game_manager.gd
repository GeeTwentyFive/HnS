extends Node


const SETTINGS_PATH = "HnS_settings.json"
const MAX_MAP_SIZE = 60000 # Since UDP packet limit is 65K
const PORT = 55555
const TEMP_RESULTS_FILE_NAME = "_HnS_RESULTS.json"
@onready var JSON_ARRAY_VIEWER_PATH = "JSONArrayViewer" + ".exe" if (OS.get_name() == "Windows") else ""


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

var hider_spawn := Vector3(0.0, 0.0, 0.0)
var seeker_spawn := Vector3(0.0, 10.0, 0.0)

var sns: SimpleNetSync
var local_state := {
	"name": "",
	"host": false,
	"host_data": {
		"map_json": "",
		"current_seeker": -1.0,
		"game_started": false,
		"game_ended": false
	},
	"map_loaded": false,
	
	# Members of Player object:
	"pos": [0.0, 0.0, 0.0],
	"yaw": 0.0,
	"pitch": 0.0,
	"alive": true,
	"is_seeker": false,
	"last_caught_hider_id": 0.0,
	"seek_time": 0.0,
	"last_alive_rounds": 0.0,
	"jumped": false,
	"walljumped": false,
	"slide_sound_playing": false,
	"hooked": false,
	"hook_point": [0.0, 0.0, 0.0],
	"flashlight": false
}
var host_id := -1
var players: Dictionary[int, Player] = {}
var current_seeker_id := -1


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
				material.albedo_color.r8 = int(map_object["data"]["Color R"])
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

func StartGame() -> void:
	%Players_Connected_Update_Timer.stop()
	
	# Spawn local player
	players[sns.local_id] = Player.new()
	players[sns.local_id].is_local_player = true
	players[sns.local_id].sensitivity = settings["sensitivity"]
	players[sns.local_id].died.connect(func():
		players[sns.local_id].position = hider_spawn
	)
	add_child(players[sns.local_id])
	
	# Spawn remote players
	for player_id in sns.states.keys():
		if player_id == sns.local_id: continue
		players[player_id] = Player.new()
		add_child(players[player_id])
	
	if local_state["host"]:
		local_state["host_data"]["current_seeker"] = players.keys()[0]
		local_state["host_data"]["game_started"] = true
	
	%Loading_Screen.visible = false
	
	get_tree().paused = false

func _ready() -> void:
	get_tree().paused = true
	
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
	
	local_state["name"] = settings["name"]
	
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		OS.alert("USAGE: -- <SERVER_IP> [PATH/TO/MAP.json]")
		get_tree().quit()
	
	sns = SimpleNetSync.create(args[0], PORT)
	
	%Players_Connected_Update_Timer.start()
	
	# (if '[PATH/TO/MAP.json]' is set then you are host)
	if args.size() > 1: # Host:
		local_state["host"] = true
		host_id = sns.local_id
		
		var map_json := FileAccess.get_file_as_string(args[1])
		if map_json.is_empty():
			OS.alert(
				"ERROR: Failed to load map at path " + args[1] + "\n" +
				"^ FileAccess Error: " + str(FileAccess.get_open_error())
			)
			get_tree().quit(1)
		map_json = map_json.strip_escapes().remove_chars(" ")
		if map_json.length() > MAX_MAP_SIZE:
			OS.alert("ERROR: Map data is too large")
			get_tree().quit(1)
		local_state["host"]["map_json"] = map_json
		LoadMap(map_json)
		local_state["map_loaded"] = true
		
		%Host_Start.visible = true
	else: # Client:
		for player_id in sns.states.keys():
			if JSON.parse_string(sns.states[player_id])["host_data"]["game_started"]:
				OS.alert("Game already started")
				get_tree().quit()
		
		%Client_Wait_For_Host_Timer.start()

func _on_client_wait_for_host_timer_timeout() -> void:
	if host_id == -1:
		for player_id in sns.states.keys():
			var player_state = JSON.parse_string(sns.states[player_id])
			if player_state["host"]:
				host_id = player_id
	if host_id == -1: return
	
	var host_state = JSON.parse_string(sns.states[host_id])
	
	if not local_state["map_loaded"]:
		if not host_state["map_loaded"]: return
		LoadMap(host_state["host_data"]["map_json"])
		local_state["map_loaded"] = true
	
	if not host_state["host_data"]["game_started"]: return
	
	%Client_Wait_For_Host_Timer.stop()
	StartGame()

func _on_host_start_button_pressed() -> void:
	var players_count := sns.states.keys().size()
	var ready_players := 0
	for client_id in sns.states.keys():
		var client_state = JSON.parse_string(sns.states[client_id])
		if client_state["map_loaded"]:
			ready_players += 1
	if ready_players < players_count: return
	
	local_state["host_data"]["map_json"] = ""
	
	StartGame()

func _physics_process(_delta: float) -> void:
	# Synchronize local player state
	local_state["pos"] = [
		players[sns.local_id].position.x,
		players[sns.local_id].position.y,
		players[sns.local_id].position.z
	]
	local_state["yaw"] = players[sns.local_id].yaw
	local_state["pitch"] = players[sns.local_id].pitch
	local_state["alive"] = players[sns.local_id].alive
	local_state["is_seeker"] = players[sns.local_id].is_seeker
	local_state["last_caught_hider_id"] = players.find_key(players[sns.local_id].last_caught_hider)
	local_state["seek_time"] = players[sns.local_id].seek_time
	local_state["last_alive_rounds"] = players[sns.local_id].last_alive_rounds
	local_state["jumped"] = players[sns.local_id].jumped
	local_state["walljumped"] = players[sns.local_id].walljumped
	local_state["slide_sound_playing"] = players[sns.local_id].slide_sound_playing
	local_state["hooked"] = players[sns.local_id].hooked
	local_state["hook_point"] = [
		players[sns.local_id].hook_point.x,
		players[sns.local_id].hook_point.y,
		players[sns.local_id].hook_point.z
	]
	local_state["flashlight"] = players[sns.local_id].flashlight
	
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
		
		get_tree().quit()
	
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

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if not %Settings_Popup.visible:
					players[sns.local_id].pause_input = true
					%Settings_Name.text = local_state["name"]
					%Settings_Sensitivity.set_value_no_signal(players[sns.local_id].sensitivity)
					%Settings_Popup.show()
				else:
					%Settings_Popup.hide()
					players[sns.local_id].pause_input = false


#region CALLBACKS

func _on_players_connected_update_timer_timeout() -> void:
	%Players_Connected_Label.text = str(sns.states.keys().size())

func _on_settings_name_text_submitted(new_text: String) -> void:
	settings["name"] = new_text
	local_state["name"] = new_text

func _on_settings_sensitivity_value_changed(value: float) -> void:
	settings["sensitivity"] = value
	players[sns.local_id].sensitivity = value

func _on_exit_button_pressed() -> void:
	get_tree().quit()

#endregion CALLBACKS
