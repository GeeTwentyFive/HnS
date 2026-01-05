extends Node


func _ready() -> void:
	var map_json = JSON.parse_string(FileAccess.get_file_as_string("TEST_MAP.json"))
	if map_json == null:
		print("ERROR: Failed to load map")
		return
	for map_object in map_json:
		match map_object["type"]:
			"Box.gd":
				var box_mesh := MeshInstance3D.new()
				box_mesh.mesh = BoxMesh.new()
				box_mesh.mesh.size.x = map_object["scale_x"]
				box_mesh.mesh.size.y = map_object["scale_y"]
				box_mesh.mesh.size.z = map_object["scale_z"]
				var material := StandardMaterial3D.new()
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
				material.albedo_color.r = map_object["data"]["Color R"]
				material.albedo_color.g = map_object["data"]["Color G"]
				material.albedo_color.b = map_object["data"]["Color B"]
				material.albedo_color.a = map_object["data"]["Color A"]
				box_mesh.set_surface_override_material(0, material)
				var collision_shape := CollisionShape3D.new()
				collision_shape.shape = BoxShape3D.new()
				collision_shape.shape.size.x = map_object["scale_x"]
				collision_shape.shape.size.y = map_object["scale_y"]
				collision_shape.shape.size.z = map_object["scale_z"]
				var box := StaticBody3D.new()
				box.add_child(collision_shape)
				box.add_child(box_mesh)
				box.position.x = map_object["position_x"]
				box.position.y = map_object["position_y"]
				box.position.z = map_object["position_z"]
				box.rotation.x = map_object["rotation_x"]
				box.rotation.y = map_object["rotation_y"]
				box.rotation.z = map_object["rotation_z"]
				add_child(box)
			
			"Light.gd":
				var light := OmniLight3D.new()
				light.omni_attenuation = 2.0
				light.shadow_enabled = true
				light.light_energy = map_object["data"]["Brightness"]
				light.omni_range = map_object["data"]["Range"]
				light.position.x = map_object["position_x"]
				light.position.y = map_object["position_y"]
				light.position.z = map_object["position_z"]
				add_child(light)
			
			"Spawn_Hider.gd":
				pass # TODO
			
			"Spawn_Seeker.gd":
				pass # TODO
