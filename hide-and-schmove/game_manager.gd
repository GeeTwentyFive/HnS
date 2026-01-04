extends Node


const SETTINGS_PATH = "HnS_settings.json"


var settings: Dictionary = {
	"name": "Player",
	"sensitivity": 0.01
}

var hider_spawn := Vector3(0.0, 0.0, 0.0)
var seeker_spawn := Vector3(0.0, 10.0, 0.0)

var local_player: Player = null
var remote_players: Array[Player] = []

# TODO: local_state


func _ready() -> void:
	get_tree().paused = true
	
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("USAGE: -- <SERVER_IP> [PATH/TO/MAP.json]")
		get_tree().quit()
	
	# TODO: Parse & validate CLI input
	
	# (if '[PATH/TO/MAP.json]' is set then you are host)
	# TODO: If host: load map
	
	# TODO: Connect to server
	
	# TODO: If not host:
		# - while no host: wait for host
		# - if host["game_started"]: exit
	
	# TODO: If host: Set map_data -> map_loaded = true
	# TODO: else: load map from host["map_data"] -> map_loaded = true
	
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
	
	local_player = Player.new()
	local_player.is_local_player = true
	local_player.name = settings["name"]
	local_player.sensitivity = settings["sensitivity"]
	add_child(local_player)
	
	# TODO: If host:
		# - Wait until everyone's map_loaded == true
		# - clear map_data
		# - game_started = true
	# TODO: else: wait until host["game_started"]
	
	# TODO: Spawn remote players
		# TODO: ^ .set_meta("net_id", sns.states.keys[x])
	
	get_tree().paused = false

func _physics_process(_delta: float) -> void:
	pass # TODO: Game management & networked state sync

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if not %Settings_Popup.visible:
					local_player.pause_input = true
					%Settings_Sensitivity.set_value_no_signal(local_player.sensitivity)
					%Settings_Popup.show()
				else:
					%Settings_Popup.hide()
					local_player.pause_input = false


#region CALLBACKS

func _on_settings_sensitivity_value_changed(value: float) -> void:
	settings["sensitivity"] = value
	local_player.sensitivity = value

func _on_exit_button_pressed() -> void:
	get_tree().quit()

#endregion CALLBACKS
