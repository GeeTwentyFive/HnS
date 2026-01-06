extends Node
class_name SimpleNetSync


const TIMEOUT = 10.0
const KEEPALIVE_INTERVAL = 1.0


var states: Dictionary = {}
var local_id: int = -1


var _peer: PacketPeerUDP
var _on_disconnect: Callable
var _disconnected := false
var _local_packet_seq_num := -1
var _last_server_state_packet_receive_time: float
var _server_packet_seq_num := -1


static func create(
	server_ip: String,
	server_port: int,
	on_disconnect: Callable = func(): return
) -> SimpleNetSync:
	var sns := SimpleNetSync.new()
	
	sns._on_disconnect = on_disconnect
	
	sns._peer = PacketPeerUDP.new()
	sns._peer.set_dest_address(server_ip, server_port)
	
	var id_request_packet := PackedByteArray()
	id_request_packet.resize(8)
	id_request_packet.encode_s64(0, -1)
	# Resend ID request packet until receive ID
	while true:
		sns._peer.put_packet(id_request_packet)
		if sns._peer.get_available_packet_count() == 0:
			OS.delay_msec(200)
			continue
		var data := sns._peer.get_packet()
		if len(data) < 8: continue
		if data.decode_s64(0) == -1:
			sns.local_id = data.decode_s64(0)
			break
		OS.delay_msec(200)
	
	var receive_timer := Timer.new()
	receive_timer.wait_time = 0.001
	receive_timer.autostart = true
	sns._last_server_state_packet_receive_time = Time.get_unix_time_from_system() # Init
	receive_timer.timeout.connect(func():
		if sns._peer.get_available_packet_count() > 0:
			sns._last_server_state_packet_receive_time = Time.get_unix_time_from_system()
		else:
			if (Time.get_unix_time_from_system() - sns._last_server_state_packet_receive_time) > TIMEOUT:
				sns._disconnected = true
				sns._on_disconnect.call()
				receive_timer.stop()
				receive_timer.queue_free()
				return
		
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
	
	var keepalive_timer := Timer.new()
	keepalive_timer.wait_time = KEEPALIVE_INTERVAL
	keepalive_timer.autostart = true
	var keepalive_packet := PackedByteArray()
	keepalive_packet.resize(8)
	keepalive_packet.encode_s64(0, -1)
	keepalive_timer.timeout.connect(func():
		if sns._disconnected:
			keepalive_timer.stop()
			keepalive_timer.queue_free()
			return
		
		sns._peer.put_packet(keepalive_packet)
	)
	Engine.get_main_loop().root.add_child.call_deferred(keepalive_timer)
	
	return sns

func send(data: String) -> Error:
	if data.length() > 65535-8:
		printerr("data size exceeds max UDP packet size")
		return FAILED
	
	_local_packet_seq_num += 1
	var packet_data := PackedByteArray()
	packet_data.resize(8)
	packet_data.encode_s64(0, _local_packet_seq_num)
	packet_data.append_array(data.to_ascii_buffer())
	_peer.put_packet(packet_data)
	
	return OK
