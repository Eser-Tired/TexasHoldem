extends Node

signal phase_changed
signal lobby_changed
signal notice(message: String)
signal input_changed

const PROTOCOL = 1
const DEFAULT_PORT = 24680
const CONNECT_TIMEOUT = 8.0

var phase = "menu"
var members: Array = []
var capacity = 4
var port = DEFAULT_PORT
var address = ""
var nickname = "玩家"
var is_host = false
var engine: PokerTable
var view: PokerView
var revision = 0
var action_pending = false
var last_message = ""
var connect_remaining = 0.0
var seat_peers: Array = []

func _ready() -> void:
	MobileLayout.configure(get_tree().root)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): _failed("连接失败：请检查房主 IP、端口，或房间是否已满 / 开始。"))
	multiplayer.server_disconnected.connect(func(): _failed("房主已离开或连接中断，已返回大厅。"))
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)

func _process(delta: float) -> void:
	if phase == "connecting":
		connect_remaining -= delta
		if connect_remaining <= 0:
			_failed("连接超时（%s:%d / UDP）：请检查房主防火墙、IP、VPN 和路由器客户端隔离。" % [address, port])

func clean_name(value: String) -> String:
	var cleaned = value.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(10)
	return "玩家" if cleaned.is_empty() else cleaned

func host_room(player_name: String, room_capacity: int = 4, room_port: int = DEFAULT_PORT) -> Error:
	if phase != "menu" or room_capacity < 2 or room_capacity > 4 or room_port < 1024 or room_port > 65535:
		return ERR_INVALID_PARAMETER
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(room_port, 3)
	if error != OK:
		_message("无法创建房间：端口可能被占用，请换一个端口。")
		return error
	nickname = clean_name(player_name)
	capacity = room_capacity
	port = room_port
	is_host = true
	multiplayer.multiplayer_peer = peer
	members = [{"peer_id": 1, "name": nickname, "ready": true}]
	phase = "lobby"
	last_message = "房间已创建。把下方的局域网 IP 和端口告诉朋友。"
	phase_changed.emit()
	lobby_changed.emit()
	return OK

func join_room(player_name: String, host_address: String, room_port: int = DEFAULT_PORT) -> Error:
	if phase != "menu" or room_port < 1024 or room_port > 65535:
		return ERR_INVALID_PARAMETER
	var endpoint = parse_endpoint(host_address, room_port)
	var ip: String = endpoint.address
	room_port = endpoint.port
	if ip.to_lower() == "localhost":
		ip = "127.0.0.1"
	if not ip.is_valid_ip_address():
		_message("请输入房主的局域网 IP，例如 192.168.1.8。")
		return ERR_INVALID_PARAMETER
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, room_port)
	if error != OK:
		_message("无法建立连接，请检查 IP 和端口。")
		return error
	nickname = clean_name(player_name)
	address = ip
	port = room_port
	is_host = false
	phase = "connecting"
	connect_remaining = CONNECT_TIMEOUT
	last_message = "正在连接 %s:%d…" % [address, port]
	multiplayer.multiplayer_peer = peer
	phase_changed.emit()
	return OK

func parse_endpoint(value: String, fallback_port: int) -> Dictionary:
	var ip = value.strip_edges()
	var selected_port = fallback_port
	# Accept the IPv4:port string produced by the lobby's copy button.
	if ip.count(":") == 1:
		var parts = ip.split(":")
		if parts[0].is_valid_ip_address() and parts[1].is_valid_int():
			ip = parts[0]
			selected_port = int(parts[1])
	if selected_port < 1024 or selected_port > 65535:
		ip = ""
	return {"address": ip, "port": selected_port}

func leave_room() -> void:
	if phase != "menu" and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	phase = "menu"
	members.clear()
	seat_peers.clear()
	engine = null
	view = null
	is_host = false
	action_pending = false
	last_message = "已离开房间。"
	phase_changed.emit()
	lobby_changed.emit()

func _failed(message: String) -> void:
	leave_room()
	_message(message)

func _message(message: String) -> void:
	last_message = message
	notice.emit(message)

func _connected() -> void:
	if phase != "connecting":
		return
	multiplayer.multiplayer_peer.get_peer(1).set_timeout(8, 2000, 6000)
	_register.rpc_id(1, nickname, PROTOCOL)

func _peer_connected(peer_id: int) -> void:
	if is_host:
		multiplayer.multiplayer_peer.get_peer(peer_id).set_timeout(8, 2000, 6000)

func _member_index(peer_id: int) -> int:
	for i in range(members.size()):
		if members[i].peer_id == peer_id:
			return i
	return -1

@rpc("any_peer", "call_remote", "reliable")
func _register(player_name: String, protocol: int) -> void:
	if not is_host:
		return
	var peer_id = multiplayer.get_remote_sender_id()
	if phase != "lobby" or members.size() >= capacity or protocol != PROTOCOL:
		_denied.rpc_id(peer_id, "无法加入：房间已满、已开始，或游戏版本不一致。")
		return
	if _member_index(peer_id) >= 0:
		return
	var name_text = clean_name(player_name)
	# Disambiguate duplicate names without treating a client-chosen name as identity.
	for member in members:
		if member.name == name_text:
			name_text = name_text.left(7) + "·%d" % (members.size() + 1)
			break
	members.append({"peer_id": peer_id, "name": name_text, "ready": false})
	last_message = "%s 加入了房间。" % name_text
	_broadcast_lobby()

@rpc("authority", "call_remote", "reliable")
func _denied(message: String) -> void:
	_failed(message)

func set_ready(ready: bool) -> void:
	if phase != "lobby" or is_host:
		return
	_set_ready.rpc_id(1, ready)

@rpc("any_peer", "call_remote", "reliable")
func _set_ready(ready: bool) -> void:
	if not is_host or phase != "lobby":
		return
	var index = _member_index(multiplayer.get_remote_sender_id())
	if index <= 0:
		return
	members[index].ready = ready
	_broadcast_lobby()

func can_start() -> bool:
	return phase == "lobby" and members.size() >= 2 and members.all(func(member): return member.ready)

func start_game() -> bool:
	if not is_host or not can_start():
		return false
	seat_peers = members.map(func(member): return member.peer_id)
	engine = PokerTable.new(members.map(func(member): return member.name), false)
	engine.changed.connect(_broadcast_state)
	multiplayer.multiplayer_peer.refuse_new_connections = true
	_broadcast_state()
	return true

func _broadcast_lobby() -> void:
	var packet = {"members": members.duplicate(true), "capacity": capacity, "port": port, "message": last_message}
	for member in members:
		if member.peer_id != 1:
			_lobby.rpc_id(member.peer_id, packet)
	lobby_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _lobby(packet: Dictionary) -> void:
	members = packet.members
	capacity = packet.capacity
	port = packet.port
	last_message = packet.message
	engine = null
	view = null
	action_pending = false
	if phase != "lobby":
		phase = "lobby"
		phase_changed.emit()
	lobby_changed.emit()

func _broadcast_state() -> void:
	if engine == null:
		return
	revision += 1
	for seat in range(seat_peers.size()):
		var packet = engine.snapshot_for(seat, revision)
		if seat_peers[seat] == 1:
			_state(packet)
		else:
			_state.rpc_id(seat_peers[seat], packet)

@rpc("authority", "call_remote", "reliable")
func _state(packet: Dictionary) -> void:
	if view == null:
		view = PokerView.new()
	action_pending = false
	view.apply(packet)
	if phase != "playing":
		phase = "playing"
		phase_changed.emit()
	input_changed.emit()

func request_action(kind: String, target: int = 0) -> void:
	if phase != "playing" or view == null or action_pending or view.actor != 0:
		return
	action_pending = true
	input_changed.emit()
	if is_host:
		_handle_action(1, kind, target, view.revision, view.hand_number)
	else:
		_action.rpc_id(1, kind, target, view.revision, view.hand_number)

@rpc("any_peer", "call_remote", "reliable")
func _action(kind: String, target: int, expected_revision: int, expected_hand: int) -> void:
	if is_host:
		_handle_action(multiplayer.get_remote_sender_id(), kind, target, expected_revision, expected_hand)

func _handle_action(peer_id: int, kind: String, target: int, expected_revision: int, expected_hand: int) -> void:
	if phase != "playing" or engine == null or engine.finished:
		_reject_action(peer_id, "当前不能下注。")
		return
	if expected_revision != revision or expected_hand != engine.hand_number or seat_peers[engine.actor] != peer_id:
		_reject_action(peer_id, "牌局已更新，或尚未轮到你。")
		return
	if kind not in ["fold", "call", "raise"] or target < 0 or target > engine.max_total(engine.actor):
		_reject_action(peer_id, "无效操作或下注金额。")
		return
	if not engine.act(kind, target):
		_reject_action(peer_id, "下注未生效，请检查最小加注或全下规则。")

func _reject_action(peer_id: int, message: String) -> void:
	if peer_id == 1:
		_feedback(message)
	elif peer_id in seat_peers:
		_feedback.rpc_id(peer_id, message)

@rpc("authority", "call_remote", "reliable")
func _feedback(message: String) -> void:
	action_pending = false
	_message(message)
	input_changed.emit()

func next_hand() -> void:
	if not is_host or engine == null or not engine.finished:
		return
	if engine.match_over():
		engine.reset_match()
	else:
		engine.start_hand()

func reset_game() -> void:
	if is_host and engine != null:
		engine.reset_match()

func _peer_disconnected(peer_id: int) -> void:
	if not is_host:
		return
	var index = _member_index(peer_id)
	if index < 0:
		return
	var name_text = members[index].name
	members.remove_at(index)
	last_message = "%s 已离开。" % name_text
	if phase == "playing":
		engine = null
		view = null
		seat_peers.clear()
		phase = "lobby"
		action_pending = false
		multiplayer.multiplayer_peer.refuse_new_connections = false
		last_message += " 本局已结束，准备后可重新开局（筹码重置）。"
		for member in members:
			member.ready = member.peer_id == 1
		phase_changed.emit()
	_broadcast_lobby()

func local_addresses() -> Array:
	return preferred_addresses(IP.get_local_interfaces(), IP.get_local_addresses())

func preferred_addresses(interfaces: Array, fallback: Array) -> Array:
	var wifi: Array = []
	var wired: Array = []
	for interface in interfaces:
		var label = (str(interface.get("name", "")) + " " + str(interface.get("friendly", ""))).to_lower()
		# Phones often enumerate rmnet (cellular) or tun (VPN) before wlan0.
		# Sharing those addresses makes a same-Wi-Fi room unreachable.
		if label.contains("tun") or label.contains("tap") or label.contains("vpn") or label.contains("rmnet") or label.contains("pdp") or label.contains("clash"):
			continue
		if label.contains("virtual") or label.contains("vethernet") or label.contains("vmware") or label.contains("vbox") or label.contains("docker"):
			continue
		var is_wifi = label.contains("wlan") or label.contains("wi-fi") or label.contains("wifi") or label.contains("ap0")
		var bucket: Array = wifi if is_wifi else wired
		if not is_wifi and not (label.contains("eth") or label.contains("以太网") or label.begins_with("en0") or label.begins_with("en1")):
			continue
		for ip in interface.get("addresses", []):
			if _usable_lan_ip(ip) and not bucket.has(ip):
				bucket.append(ip)
	if not wifi.is_empty():
		return wifi
	if not wired.is_empty():
		return wired
	var addresses: Array = []
	for ip in fallback:
		if _usable_lan_ip(ip) and not addresses.has(ip):
			addresses.append(ip)
	return addresses

func _usable_lan_ip(ip: String) -> bool:
	return ip.is_valid_ip_address() and ":" not in ip and not ip.begins_with("127.") and not ip.begins_with("169.254.") and ip != "0.0.0.0"
