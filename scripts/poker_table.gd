class_name PokerTable
extends RefCounted

signal changed

const START_STACK = 1000
const SMALL_BLIND = 10
const BIG_BLIND = 20
const STREETS = ["翻牌前", "翻牌", "转牌", "河牌"]
const NAMES = ["你", "林 · 沉稳", "夏 · 灵动", "陆 · 果断"]

var players: Array = []
var board: Array = []
var deck: Array = []
var dealer = 3
var small_blind_seat = -1
var big_blind_seat = -1
var street = 0
var hand_number = 0
var current_bet = 0
var min_raise = BIG_BLIND
var actor = -1
var pending: Array = []
var acted_at: Array = [-1, -1, -1, -1]
var finished = true
var showdown = false
var history: Array = []
var result_text = ""
var payouts: Array = [0, 0, 0, 0]
var winning_seats: Array = []
var last_pot = 0
var hand_start_stacks: Array = []
var rng = RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()
	reset_match()

func reset_match() -> void:
	players.clear()
	for name in NAMES:
		players.append({"name": name, "stack": START_STACK, "hole": [], "folded": false, "in_hand": true, "street_bet": 0, "total_bet": 0, "action": "准备入座"})
	dealer = 3
	hand_number = 0
	history.clear()
	finished = true
	start_hand()

func log_line(message: String) -> void:
	history.append(message)
	if history.size() > 60:
		history.pop_front()

func active_seats() -> Array:
	var seats: Array = []
	for i in range(players.size()):
		if players[i].in_hand and not players[i].folded:
			seats.append(i)
	return seats

func actionable_seats() -> Array:
	return active_seats().filter(func(i): return players[i].stack > 0)

func next_live(from_seat: int) -> int:
	for offset in range(1, players.size() + 1):
		var seat = (from_seat + offset) % players.size()
		if players[seat].in_hand:
			return seat
	return -1

func _ordered(seats: Array, after: int) -> Array:
	var ordered: Array = []
	for offset in range(1, players.size() + 1):
		var seat = (after + offset) % players.size()
		if seat in seats:
			ordered.append(seat)
	return ordered

func pot() -> int:
	if finished:
		return 0
	var amount = 0
	for p in players:
		amount += p.total_bet
	return amount

func match_over() -> bool:
	var funded = 0
	for p in players:
		if p.stack > 0:
			funded += 1
	return players[0].stack == 0 or funded < 2

func start_hand() -> void:
	if not finished or (hand_number > 0 and match_over()):
		return
	hand_number += 1
	board.clear()
	deck.clear()
	for i in range(52):
		deck.append(i)
	for i in range(51, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = deck[i]
		deck[i] = deck[j]
		deck[j] = temp
	hand_start_stacks.clear()
	for p in players:
		hand_start_stacks.append(p.stack)
		p.hole = []
		p.in_hand = p.stack > 0
		p.folded = not p.in_hand
		p.street_bet = 0
		p.total_bet = 0
		p.action = "等待行动" if p.in_hand else "已出局"
	dealer = next_live(dealer)
	var seats = active_seats()
	for _round in range(2):
		for i in _ordered(seats, dealer):
			players[i].hole.append(deck.pop_back())
	small_blind_seat = dealer if seats.size() == 2 else next_live(dealer)
	big_blind_seat = next_live(small_blind_seat)
	street = 0
	finished = false
	showdown = false
	payouts = [0, 0, 0, 0]
	winning_seats.clear()
	result_text = ""
	current_bet = BIG_BLIND
	min_raise = BIG_BLIND
	acted_at = [-1, -1, -1, -1]
	log_line("—— 第 %d 手 · %s 持庄 ——" % [hand_number, players[dealer].name])
	_commit(small_blind_seat, SMALL_BLIND)
	players[small_blind_seat].action = "小盲 %d" % players[small_blind_seat].street_bet
	_commit(big_blind_seat, BIG_BLIND)
	players[big_blind_seat].action = "大盲 %d" % players[big_blind_seat].street_bet
	pending = _ordered(actionable_seats(), big_blind_seat)
	_advance()
	changed.emit()

func _commit(seat: int, amount: int) -> void:
	var chips = clampi(amount, 0, players[seat].stack)
	players[seat].stack -= chips
	players[seat].street_bet += chips
	players[seat].total_bet += chips

func to_call(seat: int) -> int:
	return maxi(0, current_bet - players[seat].street_bet)

func max_total(seat: int) -> int:
	return players[seat].street_bet + players[seat].stack

func can_raise(seat: int) -> bool:
	if finished or seat != actor or max_total(seat) <= current_bet:
		return false
	if actionable_seats().size() <= 1:
		return false
	return acted_at[seat] < 0 or current_bet - acted_at[seat] >= min_raise

# Raises use the total contribution on THIS street, not an incremental amount.
func act(kind: String, target: int = 0) -> bool:
	if finished or actor < 0:
		return false
	var seat = actor
	var p = players[seat]
	var old_bet = current_bet
	if kind == "fold":
		p.folded = true
		p.action = "弃牌"
	elif kind == "call":
		var amount = mini(to_call(seat), p.stack)
		_commit(seat, amount)
		p.action = "过牌" if amount == 0 else "跟注 %d" % amount
		if p.stack == 0:
			p.action = "全下 · %d" % p.street_bet
	elif kind == "raise":
		if not can_raise(seat):
			return false
		target = mini(target, max_total(seat))
		if target <= current_bet:
			return false
		if target < current_bet + min_raise and target != max_total(seat):
			return false
		_commit(seat, target - p.street_bet)
		current_bet = target
		if target - old_bet >= min_raise:
			min_raise = target - old_bet
			for i in range(players.size()):
				if i != seat:
					acted_at[i] = -1
		p.action = "加注至 %d" % target
		if p.stack == 0:
			p.action = "全下 · %d" % target
	else:
		return false
	acted_at[seat] = current_bet
	log_line("%s：%s" % [p.name, p.action])
	pending.erase(seat)
	if current_bet > old_bet:
		pending = _ordered(actionable_seats().filter(func(i): return i != seat and players[i].street_bet < current_bet), seat)
	_advance()
	changed.emit()
	return true

func _advance() -> void:
	actor = -1
	if active_seats().size() <= 1:
		_finish(false)
		return
	pending = pending.filter(func(i): return not players[i].folded and players[i].stack > 0)
	var actionable = actionable_seats()
	# No further wager is possible if the only funded player has matched the bet.
	if actionable.size() <= 1 and (actionable.is_empty() or to_call(actionable[0]) == 0):
		_runout()
		return
	if pending.is_empty():
		if street == 3:
			_finish(true)
			return
		_deal_next_street()
		pending = _ordered(actionable_seats(), dealer)
		_advance()
		return
	actor = pending[0]

func _deal_next_street() -> void:
	street += 1
	deck.pop_back() # Burn one card before each street.
	for _i in range(3 if street == 1 else 1):
		board.append(deck.pop_back())
	current_bet = 0
	min_raise = BIG_BLIND
	acted_at = [-1, -1, -1, -1]
	for p in players:
		p.street_bet = 0
		if p.in_hand and not p.folded:
			p.action = "已全下" if p.stack == 0 else "等待行动"
	log_line("%s：%s" % [STREETS[street], " ".join(board.map(func(c): return PokerRules.card_text(c)))])

func _runout() -> void:
	while street < 3:
		_deal_next_street()
	_finish(true)

func _finish(reveal: bool) -> void:
	last_pot = pot()
	showdown = reveal
	var settlement = PokerRules.distribute(players, board, dealer)
	payouts = settlement.payouts
	winning_seats.clear()
	var details: Array[String] = []
	var pot_number = 0
	for layer in settlement.pots:
		if layer.refund:
			log_line("%s 收回未被跟注的 %d" % [players[layer.winners[0]].name, layer.amount])
			continue
		var names: Array[String] = []
		for i in layer.winners:
			names.append(players[i].name)
			if i not in winning_seats:
				winning_seats.append(i)
		var label = "底池" if pot_number == 0 else "边池 %d" % pot_number
		var line = "%s：%s %s %d" % [label, "、".join(names), "平分" if names.size() > 1 else "赢得", layer.amount]
		log_line(line)
		details.append(line)
		pot_number += 1
	for i in range(players.size()):
		players[i].stack += payouts[i]
		if reveal and players[i].in_hand and not players[i].folded:
			players[i].action = PokerRules.evaluate(players[i].hole + board).name
	var net = players[0].stack - hand_start_stacks[0]
	result_text = "本手 +%d 筹码" % net if net > 0 else ("本手 %d 筹码" % net if net < 0 else "本手持平")
	if not details.is_empty():
		result_text += "  ·  " + details[0]
	finished = true
	actor = -1
	pending.clear()

# Opponents sample unknown cards; they never inspect another player's hole cards.
func estimate_equity(seat: int, samples: int = 24) -> float:
	var known = players[seat].hole + board
	var unseen: Array = []
	for card in range(52):
		if card not in known:
			unseen.append(card)
	var opponents = active_seats().size() - 1
	var wins = 0.0
	for _sample in range(samples):
		var pool = unseen.duplicate()
		var simulated_board = board.duplicate()
		while simulated_board.size() < 5:
			var pick = rng.randi_range(0, pool.size() - 1)
			simulated_board.append(pool[pick])
			pool.remove_at(pick)
		var my_score = PokerRules.evaluate(players[seat].hole + simulated_board).score
		var beat = false
		var ties = 1
		for _opponent in range(opponents):
			var hole: Array = []
			for _card in range(2):
				var pick = rng.randi_range(0, pool.size() - 1)
				hole.append(pool[pick])
				pool.remove_at(pick)
			var score = PokerRules.evaluate(hole + simulated_board).score
			if score > my_score:
				beat = true
			elif score == my_score:
				ties += 1
		if not beat:
			wins += 1.0 / ties
	return wins / samples

func bot_action() -> Dictionary:
	var seat = actor
	var equity = estimate_equity(seat)
	var cost = mini(to_call(seat), players[seat].stack)
	var odds = float(cost) / maxi(1, pot() + cost)
	var personality = [0.0, -0.04, 0.04, 0.07][seat]
	var roll = rng.randf()
	if cost > 0 and equity + personality < odds + 0.05 and roll > 0.13:
		return {"kind": "fold", "target": 0}
	if can_raise(seat) and (equity + personality > 0.57 or (roll < 0.08 and cost == 0)):
		var target = current_bet + maxi(min_raise, int(pot() * (0.5 if seat != 3 else 0.75)))
		return {"kind": "raise", "target": mini(target, max_total(seat))}
	return {"kind": "call", "target": 0}
