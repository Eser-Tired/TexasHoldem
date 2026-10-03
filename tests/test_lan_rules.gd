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

func run() -> void:
	for count in range(2, 5):
		var names: Array = []
		for i in range(count):
			names.append("Player%d" % i)
		var table = PokerTable.new(names, false)
		check(table.players.size() == count, "Actual table size")
		check(table.acted_at.size() == count and table.payouts.size() == count, "Per-seat arrays follow table size")
		check(table.actor == 0 if count == 2 else table.actor == 3 % count, "Preflop order for table size")
		for recipient in range(count):
			var packet = table.snapshot_for(recipient, 1)
			check(not packet.has("deck") and not packet.has("rng") and not packet.has("pending"), "No private engine data in packets")
			check(packet.players[0].hole == table.players[recipient].hole, "Recipient sees own two cards")
			check(packet.players[0].name == names[recipient], "Recipient always shown at seat zero")
			for i in range(1, count):
				check(packet.players[i].hole == [-1, -1], "Other hands are redacted before showdown")
			var model = PokerView.new()
			model.apply(packet)
			check(model.pot() == table.pot(), "Client pot matches authority")
			check(model.can_raise(0) == table.can_raise(recipient), "Raise permission matches authority")
			check(model.actor == ((table.actor - recipient + count) % count), "Actor correctly rotates")
			model.apply(table.snapshot_for(recipient, 0))
			check(model.revision == 1, "Older snapshots ignored")
		# One player folds; clients must not receive that player's cards at showdown.
		var folded_seat = table.actor
		if count > 2:
			table.act("fold")
		while not table.finished:
			table.act("call")
		var total = 0
		for p in table.players:
			total += p.stack
		check(total == count * 1000, "Settlement conserves table's starting chips")
		for recipient in range(count):
			var packet = table.snapshot_for(recipient, 2)
			for offset in range(count):
				var seat = (recipient + offset) % count
				var expected = table.players[seat].hole if seat == recipient or not table.players[seat].folded else [-1, -1]
				check(packet.players[offset].hole == expected, "Only surviving showdown hands revealed")
		# Elimination of seat zero must not end an online match with 2+ funded players.
		if count >= 3:
			table.players[0].stack = 0
			check(not table.match_over(), "Host can spectate after busting")
			table.start_hand()
			check(table.players[0].hole.is_empty(), "Busted player not dealt new cards")
			check(table.snapshot_for(0, 3).players[0].hole.is_empty(), "Spectator gets no phantom hand")
	print("PASS: ", checks, " LAN table-size, per-recipient privacy, rotation, showdown and spectator checks")
	quit(0)
