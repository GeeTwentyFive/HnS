extends Node


const SETTINGS_PATH = "HnS_settings.json"
const MAX_MAP_SIZE = 60000 # Since UDP packet limit is 65K
const PORT = 55555


var settings: Dictionary = {
	"name": "Player",
	"sensitivity": 0.01
}

var hider_spawn := Vector3(0.0, 0.0, 0.0)
var seeker_spawn := Vector3(0.0, 10.0, 0.0)

var sns: SimpleNetSync
var local_state := {
	"name": "",
	"host": false,
	"host_data": {
		"map_json": "",
		"players_count": 0,
		"game_started": false
	},
	"map_loaded": false,
	"pos": [0.0, 0.0, 0.0],
	"yaw": 0.0,
	"pitch": 0.0,
	"is_seeker": false,
	"alive": true,
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


func LoadMap(map_json: String):
	pass # TODO

func StartGame() -> void:
	%Players_Connected_Update_Timer.stop()
	
	# Spawn local player
	players[sns.local_id] = Player.new()
	players[sns.local_id].is_local_player = true
	players[sns.local_id].sensitivity = settings["sensitivity"]
	add_child(players[sns.local_id])
	
	# Spawn remote players
	for player_id in sns.states.keys():
		if player_id == sns.local_id: continue
		players[player_id] = Player.new()
		add_child(players[player_id])
	
	%Loading_Screen.visible = false
	
	get_tree().paused = false

func _ready() -> void:
	get_tree().paused = true
	
	# Generate user settings if they don't exist
	if not FileAccess.file_exists(SETTINGS_PATH):
		FileAccess.open(
			SETTINGS_PATH,
			FileAccess.WRITE
		).store_string(JSON.stringify(settings))
	
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
		).store_string(JSON.stringify(settings))
	
	local_state["name"] = settings["name"]
	
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("USAGE: -- <SERVER_IP> [PATH/TO/MAP.json]")
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
	local_state["host_data"]["players_count"] = sns.states.keys().size()
	var ready_players := 0
	for client_id in sns.states.keys():
		var client_state = JSON.parse_string(sns.states[client_id])
		if client_state["map_loaded"]:
			ready_players += 1
	if ready_players < local_state["host_data"]["players_count"]: return
	
	local_state["host_data"]["map_json"] = ""
	
	local_state["host_data"]["game_started"] = true
	StartGame()

func _physics_process(_delta: float) -> void:
	# TODO: Local Player -> local_state
	
	# TODO: sns.states -> players (exlcluding local)
	
	if local_state["host"]:
		pass # TODO: Game management
	
	sns.send(JSON.stringify(local_state))

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if not %Settings_Popup.visible:
					players[sns.local_id].pause_input = true
					%Settings_Sensitivity.set_value_no_signal(players[sns.local_id].sensitivity)
					%Settings_Popup.show()
				else:
					%Settings_Popup.hide()
					players[sns.local_id].pause_input = false


#region CALLBACKS

func _on_players_connected_update_timer_timeout() -> void:
	%Players_Connected_Label.text = str(sns.states.keys().size())

func _on_settings_sensitivity_value_changed(value: float) -> void:
	settings["sensitivity"] = value
	players[sns.local_id].sensitivity = value

func _on_exit_button_pressed() -> void:
	get_tree().quit()

#endregion CALLBACKS
