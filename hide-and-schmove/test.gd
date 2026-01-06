extends Node


var hider_spawn := Vector3(0.0, 0.0, 0.0)
var seeker_spawn := Vector3(0.0, 10.0, 0.0)

func _ready() -> void:
	var map_json = JSON.parse_string(FileAccess.get_file_as_string("TEST_MAP.json"))
	if map_json == null:
		print("ERROR: Failed to load map")
		return
	for map_object in map_json:
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
				material.albedo_color.r = map_object["data"]["Color R"]
				material.albedo_color.g = map_object["data"]["Color G"]
				material.albedo_color.b = map_object["data"]["Color B"]
				material.albedo_color.a = map_object["data"]["Color A"]
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
