extends SceneTree

var checks = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("FAILED: " + message)
		quit(1)
		assert(condition, message)
	checks += 1

func cards(text: String) -> Array:
	var output: Array = []
	for token in text.split(" ", false):
		var rank = "23456789TJQKA".find(token[0])
		var suit = "shcd".find(token[1])
		check(rank >= 0 and suit >= 0, "Valid card fixture")
		output.append(suit * 13 + rank)
	return output

func score(text: String) -> int:
	return PokerRules.evaluate(cards(text)).score

func test_evaluation() -> void:
	var examples = [
		["As Kd 9c 7h 3s", 0], ["As Ad 9c 7h 3s", 1],
		["As Ad 9c 9h 3s", 2], ["As Ad Ac 7h 3s", 3],
		["As 2d 3c 4h 5s", 4], ["As Js 9s 7s 3s", 5],
		["As Ad Ac 7h 7s", 6], ["As Ad Ac Ah 3s", 7],
		["9s Ts Js Qs Ks", 8]
	]
	var last = -1
	for item in examples:
		var result = PokerRules.evaluate(cards(item[0]))
		check(result.category == item[1], "Hand category " + item[0])
		check(result.score > last, "Category ordering")
		last = result.score
	check(PokerRules.evaluate(cards("As Ks Qs Js Ts 2c 3d")).name == "皇家同花顺", "Royal flush label")
	check(score("2s 3h 4d 5c 6s") > score("As 2h 3d 4c 5s"), "Wheel is lowest straight")
	check(score("As Ad Kc Qh 9s") > score("Ah Ac Kd Jh Ts"), "Third pair kicker")
	check(score("As Ad Kc Kh 9s") > score("Ah Ac Qd Qh Ks"), "Second pair outranks kicker")
	check(score("As Ad Ac Kh Kd 2c 3h") > score("Ks Kd Kc Ah Ad 2h 3s"), "Full house trips lead")
	check(PokerRules.evaluate(cards("As Ah Ad Ks Kh Kd 2c")).kickers == [14, 13], "Two trips make a full house")
	check(PokerRules.evaluate(cards("As Ah Ks Kh Qs Qh 2c")).kickers == [14, 13, 12], "Three pairs use third as kicker")
	check(PokerRules.evaluate(cards("As 2s 3s 4s 5s Kh Kd")).category == 8, "Wheel straight flush")
	check(score("As Kd Qc Jh Ts 2c 3d") == score("Ah Kc Qd Js Th 4c 5d"), "Equal board straight ignores unused cards")
	check(PokerRules.evaluate(cards("2s 3s 4s 5s Ks 6h 7d")).category == 5, "Flush plus off-suit straight is not straight flush")
	# Cross-check direct seven-card evaluation against all 21 five-card subsets.
	var rng = RandomNumberGenerator.new()
	rng.seed = 311
	for _sample in range(600):
		var pool: Array = []
		for i in range(52):
			pool.append(i)
		var seven: Array = []
		for _i in range(7):
			var pick = rng.randi_range(0, pool.size() - 1)
			seven.append(pool[pick])
			pool.remove_at(pick)
		var best = -1
		for a in range(7):
			for b in range(a + 1, 7):
				var five = seven.duplicate()
				five.remove_at(b)
				five.remove_at(a)
				best = maxi(best, PokerRules.evaluate(five).score)
		check(PokerRules.evaluate(seven).score == best, "Seven-card exhaustive comparison")

func fixture(hole: String, bet: int, folded: bool = false) -> Dictionary:
	return {"hole": cards(hole), "total_bet": bet, "folded": folded}

func test_pots() -> void:
	var players = [fixture("As Ah", 100), fixture("Ks Kh", 200), fixture("Qs Qh", 300)]
	var settlement = PokerRules.distribute(players, cards("2c 3d 7h 9c Js"), 0)
	check(settlement.payouts == [300, 200, 100], "Main pot, side pot, unmatched refund")
	check(settlement.pots.size() == 3, "Three contribution tiers")
	check(settlement.pots[2].refund, "Uncalled bet marked as refund")
	players[0].folded = true
	settlement = PokerRules.distribute(players, cards("2c 3d 7h 9c Js"), 0)
	check(settlement.payouts == [0, 500, 100], "Folded money contributes but cannot win")
	players = [fixture("2c 3c", 51), fixture("4c 5c", 51), fixture("6c 7c", 51, true)]
	settlement = PokerRules.distribute(players, cards("As Ks Qs Js Ts"), 0)
	check(settlement.payouts == [76, 77, 0], "Board ties and odd chip clockwise after dealer")

func test_betting() -> void:
	var t = PokerTable.new()
	check(t.dealer == 0 and t.small_blind_seat == 1 and t.big_blind_seat == 2 and t.actor == 3, "Four-seat blind positions")
	check(not t.act("raise", 39) and t.actor == 3 and t.current_bet == 20, "Reject undersized raise without mutation")
	for _i in range(4):
		check(t.act("call"), "Call / check is legal")
	check(t.street == 1 and t.board.size() == 3 and t.actor == 1, "BB retains option and postflop starts after dealer")
	for _i in range(4):
		t.act("call")
	check(t.street == 2 and t.board.size() == 4, "Turn after four checks")
	for _i in range(8):
		t.act("call")
	check(t.finished and t.showdown and t.board.size() == 5, "River showdown")
	check(chip_total(t) == 4000, "Showdown conserves chips")
	t = PokerTable.new()
	t.act("raise", 100)
	check(t.min_raise == 80, "Minimum raise follows last full raise")
	check(not t.act("raise", 179), "Reject new raise below increment")
	check(t.act("raise", 180), "Full reraise accepted")
	t = PokerTable.new()
	t.players[1].stack = 25 # SB 10 + 25 remaining: all-in to 35.
	t.act("call") # Seat 3 to 20.
	t.act("call") # Hero to 20.
	check(t.act("raise", 35), "Short all-in accepted")
	check(t.min_raise == 20 and t.actor == 2 and t.can_raise(2), "Unacted BB may still raise")
	t.act("call")
	check(t.actor == 3 and not t.can_raise(3), "Short raise does not reopen action")
	t.act("call")
	check(t.actor == 0 and not t.can_raise(0), "Hero cannot reraise a short all-in")
	t = PokerTable.new()
	t.players[1].stack = 25
	t.players[2].stack = 25
	t.act("call")
	t.act("call")
	t.act("raise", 35)
	t.act("raise", 45)
	check(t.actor == 3 and t.can_raise(3), "Cumulative short raises reopen at a full increment")
	t = PokerTable.new()
	for _i in range(3):
		t.act("fold")
	check(t.finished and not t.showdown and t.players[2].stack == 1010, "Everyone folds; unmatched blind is refunded")
	check(chip_total(t) == 4000, "Fold win conserves chips")
	t = PokerTable.new()
	for _i in range(4):
		var kind = "raise" if t.can_raise(t.actor) else "call"
		t.act(kind, t.max_total(t.actor))
	check(t.finished and t.showdown and t.board.size() == 5, "All-in auto-runs all streets")
	check(chip_total(t) == 4000, "All-in settlement conserves chips")
	# A lone funded player cannot bet into only all-in opponents.
	t = PokerTable.new()
	t.players[0].stack = 1500
	t.players[1].stack = 0
	t.players[2].stack = 0
	t.players[3].stack = 500
	t.finished = true
	t.start_hand()
	check(t.dealer == 3 and t.small_blind_seat == 3 and t.big_blind_seat == 0 and t.actor == 3, "Heads-up dealer posts SB and acts first")
	t.act("call")
	t.act("call")
	check(t.street == 1 and t.actor == 0, "Heads-up BB first after flop")

func chip_total(t: PokerTable) -> int:
	var total = t.pot()
	for p in t.players:
		check(p.stack >= 0, "Stacks never negative")
		total += p.stack
	return total

func test_simulations() -> void:
	var t = PokerTable.new()
	t.rng.seed = 9138
	var actions = 0
	for hand in range(500):
		if t.match_over():
			t.reset_match()
		elif t.finished:
			t.start_hand()
		var steps = 0
		while not t.finished:
			check(chip_total(t) == 4000, "Chips conserved before every action")
			check(t.actor >= 0 and t.actor in t.pending, "Legal actor always present")
			var actor = t.actor
			var roll = t.rng.randf()
			var legal = false
			if roll < 0.16:
				legal = t.act("fold")
			elif roll < 0.46 and t.can_raise(actor):
				var minimum = mini(t.current_bet + t.min_raise, t.max_total(actor))
				var target = t.max_total(actor) if roll < 0.24 else minimum
				legal = t.act("raise", target)
			else:
				legal = t.act("call")
			check(legal, "Random policy produces legal action")
			steps += 1
			actions += 1
			check(steps < 300, "Hand terminates")
		check(chip_total(t) == 4000, "Chips conserved after settlement")
		var known: Array = t.board.duplicate()
		for p in t.players:
			known.append_array(p.hole)
		var unique = {}
		for card in known:
			unique[card] = true
		check(unique.size() == known.size(), "No duplicate dealt cards")
	print("Simulated 500 hands / ", actions, " legal actions")

func test_bot_matches() -> void:
	var t = PokerTable.new()
	t.rng.seed = 917
	var total_actions = 0
	for _hand in range(60):
		if t.match_over():
			t.reset_match()
		elif t.finished:
			t.start_hand()
		var steps = 0
		while not t.finished:
			var decision = t.bot_action()
			check(t.act(decision.kind, decision.target), "AI decisions are legal")
			check(chip_total(t) == 4000, "AI matches conserve chips")
			steps += 1
			total_actions += 1
			check(steps < 300, "AI hand terminates")
	print("Simulated 60 AI hands / ", total_actions, " decisions")

func run() -> void:
	test_evaluation()
	test_pots()
	test_betting()
	test_simulations()
	test_bot_matches()
	print("PASS: ", checks, " checks; evaluator, side pots, betting, 500 random + 60 AI hands")
	quit(0)
