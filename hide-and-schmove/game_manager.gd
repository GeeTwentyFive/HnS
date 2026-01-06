extends Node


const SETTINGS_PATH = "HnS_settings.json"
const MAX_MAP_SIZE = 60000 # Since UDP packet limit is 65K
const PORT = 55555


var settings: Dictionary = {
	"name": "Player",
	"sensitivity": 0.01
}

var map_data
var hider_spawn := Vector3(0.0, 0.0, 0.0)
var seeker_spawn := Vector3(0.0, 10.0, 0.0)

var sns: SimpleNetSync
var local_state := {
	"name": "",
	"host": false,
	"host_data": {
		"map_data": "",
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


func start_game() -> void:
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
	
	# (if '[PATH/TO/MAP.json]' is set then you are host)
	if args.size() > 1: # Host:
		local_state["host"] = true
		host_id = sns.local_id
		var map_json := FileAccess.get_file_as_string(args[1])
		if map_json.is_empty():
			print("ERROR: Failed to load map at path " + args[1])
			print(FileAccess.get_open_error())
			get_tree().quit(1)
		map_data = JSON.parse_string(map_json)
		if map_data == null:
			print("ERROR: Failed to parse map json")
			get_tree().quit(1)
		var compressed_map_json = JSON.stringify(map_data)
		if compressed_map_json.length() > MAX_MAP_SIZE:
			print("ERROR: Map data is too large")
			get_tree().quit(1)
		local_state["host"]["map_data"] = compressed_map_json
		local_state["map_loaded"] = true
	else: # Client:
		pass
		# TODO:
		# - while no host: wait for host
		# - set `host_id`
		# - if sns.states[host_id]["game_started"]: exit
		# - wait until sns.states[host_id]["map_loaded"]
		# - load map from sns.states[host_id]["host_data"]["map_data"] -> map_loaded = true
		# - wait until sns.states[host_id]["host_data"]["game_started"]
		start_game()
	
	# TODO: On host start button pressed (host-only button):
		# - Wait until everyone's map_loaded == true
		# - clear map_data
		# - game_started = true

func _physics_process(_delta: float) -> void:
	pass # TODO: Game management & networked state sync

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

func _on_settings_sensitivity_value_changed(value: float) -> void:
	settings["sensitivity"] = value
	players[sns.local_id].sensitivity = value

func _on_exit_button_pressed() -> void:
	get_tree().quit()

#endregion CALLBACKS
