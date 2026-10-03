extends SceneTree

# Run multiple instances via Run-LanTests.ps1. Each instance uses a real ENet socket
# plus the actual lobby and game scenes, rather than a mocked transport.
var room
var menu
var host = false
var count = 2
var port = 24702
var client_index = 1
var checks = 0
var finished_hands = {}
var last_action_revision = -1
var forged_once = false
var attempted_host_validation = false
var ready_sent = false
var leave_at = -1.0
var close_at = -1.0
var elapsed = 0.0
var saw_exact_amount = false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--role=host":
			host = true
		elif arg.begins_with("--count="):
			count = int(arg.trim_prefix("--count="))
		elif arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--client="):
			client_index = int(arg.trim_prefix("--client="))
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("FAIL: " + message)
		quit(1)
		assert(condition, message)
	checks += 1

func run() -> void:
	await process_frame
	room = root.get_node("LanRoom")
	menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	if host:
		check(room.host_room("Host", count, port) == OK, "Host creates ENet room")
		check(not room.start_game(), "One person cannot start")
	else:
		check(room.join_room("Client%d" % client_index, "127.0.0.1", port) == OK, "Client initiates connection")
	var last_time = Time.get_ticks_msec()
	while elapsed < 30.0:
		await process_frame
		var now = Time.get_ticks_msec()
		elapsed += float(now - last_time) / 1000.0
		last_time = now
		if room.phase == "lobby":
			if finished_hands.size() >= 3:
				check(room.view == null and menu.game == null, "Disconnect closes table and returns to lobby")
				check(room.members.size() == count - 1, "Disconnected player removed from room")
				if host:
					check(room.members.all(func(member): return member.ready == (member.peer_id == 1)), "Readiness reset after disconnect")
					if close_at < 0:
						close_at = elapsed + 0.7
					if elapsed >= close_at:
						room.leave_room()
						_success("Host: %d seats, 3 hands, validation and disconnect recovery" % count)
						return
				continue
			if host:
				if room.members.size() == count and room.can_start():
					check(room.start_game(), "Start after all clients ready")
			else:
				if not ready_sent:
					check(menu.ready_button.visible, "Client sees ready control")
					menu.ready_button.pressed.emit()
					ready_sent = true
		elif room.phase == "playing":
			var view = room.view
			if view.hand_number == 1 and view.street == 0 and view.current_bet == 137:
				saw_exact_amount = true
			check(menu.game != null and menu.game.online, "Actual UI enters online game")
			check(view.players.size() == count, "Actual player count in network view")
			check(view.players[0].name == ("Host" if host else "Client%d" % client_index), "Personal seat maps to this peer")
			if not host:
				check(menu.game.restart_button.disabled, "Client cannot reset host's game")
			check(view.players[0].hole.size() == 2, "Recipient receives own hand")
			for offset in range(1, count):
				var p = view.players[offset]
				if not view.finished or p.folded:
					check(p.hole == [-1, -1], "Private opponent cards absent on wire")
			if host and not attempted_host_validation:
				var revision_before = room.revision
				var actor_peer = room.seat_peers[room.engine.actor]
				var wrong_peer = room.seat_peers.filter(func(peer): return peer != actor_peer)[0]
				room._handle_action(wrong_peer, "fold", 0, room.revision, room.engine.hand_number)
				room._handle_action(actor_peer, "call", 0, room.revision - 1, room.engine.hand_number)
				room._handle_action(actor_peer, "raise", room.engine.max_total(room.engine.actor) + 1, room.revision, room.engine.hand_number)
				room._handle_action(actor_peer, "hack", 0, room.revision, room.engine.hand_number)
				check(room.revision == revision_before, "Wrong actor, stale, oversized and invalid requests rejected without mutation")
				attempted_host_validation = true
			if not host and not forged_once:
				room._action.rpc_id(1, "raise", 2147483647, view.revision, view.hand_number)
				forged_once = true
			if view.finished:
				check(saw_exact_amount, "Exact 137-chip wager reached this peer without rounding")
				finished_hands[view.hand_number] = true
				var total = 0
				for p in view.players:
					total += p.stack
				check(total == count * 1000, "Network showdown conserves chips")
				if view.hand_number < 3:
					if host:
						# Allow clients to receive the final hand before beginning another.
						if close_at < 0:
							close_at = elapsed + 0.15
						if elapsed >= close_at:
							close_at = -1
							menu.game.next_button.pressed.emit()
				elif not host and client_index == count - 1:
					if leave_at < 0:
						leave_at = elapsed + 0.35
					if elapsed >= leave_at:
						room.leave_room()
						_success("Client%d: redacted snapshots, buttons, showdown and graceful leave" % client_index)
						return
			elif last_action_revision != view.revision and not room.action_pending:
				if view.actor == 0:
					last_action_revision = view.revision
					if view.hand_number == 2:
						menu.game.fold_button.pressed.emit()
					elif view.hand_number == 3 and view.can_raise(0):
						menu.game.allin_button.pressed.emit()
					elif view.hand_number == 1 and view.street == 0 and view.current_bet == 20 and view.can_raise(0):
						menu.game.amount_input.text = "137"
						menu.game.amount_input.text_changed.emit("137")
						check(not menu.game.raise_button.disabled, "Exact integer amount accepted by network UI")
						menu.game.raise_button.pressed.emit()
					else:
						menu.game.call_button.pressed.emit()
		elif room.phase == "menu" and finished_hands.size() >= 3:
			check(menu.game == null, "Host closure returns client to menu")
			_success("Client%d: host closure handled" % client_index)
			return
	push_error("FAIL: network test timed out, phase=%s, finished=%s, message=%s" % [room.phase, finished_hands.keys(), room.last_message])
	quit(1)

func _success(message: String) -> void:
	print("PASS: ", message, " (", checks, " checks)")
	quit(0)
