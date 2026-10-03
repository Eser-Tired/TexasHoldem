extends SceneTree

var checks = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("FAIL: " + message)
		quit(1)
		assert(condition, message)
	checks += 1

func session(branch_name: String):
	var branch = Node.new()
	branch.name = branch_name
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var room = load("res://scripts/lan_room.gd").new()
	room.name = "LanRoom"
	branch.add_child(room)
	return room

func until(predicate: Callable, message: String, seconds: float = 3.0) -> void:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(predicate.call(), message)

func run() -> void:
	await process_frame
	var host = session("AdmissionHost")
	var first = session("AdmissionFirst")
	var extra = session("AdmissionExtra")
	check(host.host_room("Host", 2, 24802) == OK, "Create two-person room")
	check(not host.start_game(), "One seat cannot start a game")
	check(first.join_room("Host", "127.0.0.1", 24802) == OK, "Join valid address")
	await until(func(): return first.phase == "lobby", "Registration reaches lobby")
	check(host.members.size() == 2 and first.members.size() == 2, "Roster synchronized")
	check(host.members[0].name != host.members[1].name, "Duplicate nicknames disambiguated")
	check(not host.start_game(), "Unready client blocks start")
	extra.join_room("Extra", "127.0.0.1", 24802)
	await until(func(): return extra.phase == "menu", "Third player rejected from capacity-two room")
	check(host.members.size() == 2 and "房间已满" in extra.last_message, "Rejected player cannot occupy seat")
	first.set_ready(true)
	await until(func(): return host.can_start(), "Ready synchronized to host")
	first.set_ready(false)
	await until(func(): return not host.can_start(), "Unready synchronized to host")
	first.set_ready(true)
	await until(func(): return host.can_start(), "Ready again")
	check(host.start_game(), "Host starts ready room")
	await until(func(): return first.phase == "playing", "Client enters game")
	extra.join_room("Late", "127.0.0.1", 24802)
	await until(func(): return extra.phase == "menu", "In-progress room refuses late joins; connection times out", 9.0)
	check(host.engine.players.size() == 2, "Late join cannot change active seats")
	first.leave_room()
	await until(func(): return host.phase == "lobby", "Active disconnect aborts game to lobby")
	check(host.members.size() == 1 and host.view == null and not host.can_start(), "Disconnected game is cleared")
	extra.join_room("New", "127.0.0.1", 24802)
	await until(func(): return extra.phase == "lobby", "Room reopens for new players")
	extra._register.rpc_id(1, "New", 999)
	await until(func(): return extra.phase == "menu" and host.members.size() == 1, "Protocol mismatch rejected and seat removed")
	check("版本不一致" in extra.last_message, "Version mismatch explains rejection")
	first.join_room("Back", "127.0.0.1", 24802)
	await until(func(): return first.phase == "lobby", "Former player can rejoin after abort")
	first.set_ready(true)
	await until(func(): return host.can_start(), "New readiness required")
	check(host.start_game(), "Fresh match starts after recovery")
	await until(func(): return first.phase == "playing", "Recovered client receives new hand")
	check(first.view.hand_number == 1 and first.view.players[0].stack >= 980, "Recovery starts fresh stacks")
	host.leave_room()
	await until(func(): return first.phase == "menu", "Host closure returns client to menu")
	check(extra.join_room("Bad", "not-an-ip", 24802) == ERR_INVALID_PARAMETER and extra.phase == "menu", "Invalid address rejected before connecting")
	extra.join_room("Cancel", "127.0.0.1", 24818)
	extra.leave_room()
	check(extra.phase == "menu" and extra.view == null, "Pending connection can be cancelled")
	print("PASS: ", checks, " admission, capacity, readiness, late join, timeout, version, recovery and close checks")
	quit(0)
