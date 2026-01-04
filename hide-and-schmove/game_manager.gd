extends Node


const SETTINGS_PATH = "user://hns_settings.json"


var settings: Dictionary = {
	"sensitivity": 0.01
}

var hider_spawn := Vector3(0.0, 0.0, 0.0)
var seeker_spawn := Vector3(0.0, 0.0, 0.0)

var local_player: Player = null
var remote_players: Array[Player] = []


func _ready() -> void:
	# TODO: Parse & validate CLI input
	
	# TODO: Load & validate map
	
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
	
	# TODO: Spawn local player
	
	# TODO: Spawn remote players

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
