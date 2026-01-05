extends Node
class_name SimpleNetSync


var states: Dictionary = {}
var local_id: int = -1


var _peer: PacketPeerUDP
var _local_packet_seq_num := -1
var _server_packet_seq_num := -1


static func create(
	server_ip: String,
	server_port: int
) -> SimpleNetSync:
	var sns := SimpleNetSync.new()
	
	sns._peer = PacketPeerUDP.new()
	sns._peer.set_dest_address(server_ip, server_port)
	
	var _p := PackedByteArray()
	_p.append(0)
	sns._peer.put_packet(_p)
	while true:
		while sns._peer.get_available_packet_count() == 0: continue
		var data := sns._peer.get_packet()
		if len(data) < 8: continue
		sns.local_id = data.decode_s64(0)
		break
	
	var receive_timer := Timer.new()
	receive_timer.wait_time = 0.001
	receive_timer.autostart = true
	receive_timer.timeout.connect(func():
		while sns._peer.get_available_packet_count() > 0:
			var data := sns._peer.get_packet()
			if len(data) < 8: continue
			
			var seq_num := data.decode_s64(0)
			if seq_num <= sns._server_packet_seq_num: continue
			sns._server_packet_seq_num = seq_num
			
			var json := JSON.new()
			if json.parse(data.slice(8).get_string_from_ascii()) != OK: continue
			sns.states = json.data
	)
	Engine.get_main_loop().root.add_child.call_deferred(receive_timer)
	
	return sns

func send(data: String):
	_local_packet_seq_num += 1
	var packet_data := PackedByteArray()
	packet_data.resize(8)
	packet_data.encode_s64(0, _local_packet_seq_num)
	packet_data.append_array(data.to_ascii_buffer())
	_peer.put_packet(packet_data)
