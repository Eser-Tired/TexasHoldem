class_name PokerRules
extends RefCounted

const HAND_NAMES = ["高牌", "一对", "两对", "三条", "顺子", "同花", "葫芦", "四条", "同花顺"]
const SUITS = ["♠", "♥", "♣", "♦"]

static func rank_of(card: int) -> int:
	return card % 13 + 2

static func suit_of(card: int) -> int:
	return card / 13

static func rank_text(card: int) -> String:
	var rank = rank_of(card)
	return {11: "J", 12: "Q", 13: "K", 14: "A"}.get(rank, str(rank))

static func card_text(card: int) -> String:
	return rank_text(card) + SUITS[suit_of(card)]

static func _straight_high(ranks: Array) -> int:
	var unique = ranks.duplicate()
	if 14 in unique:
		unique.append(1)
	var run = 1
	for i in range(1, unique.size()):
		if unique[i - 1] - unique[i] == 1:
			run += 1
			if run >= 5:
				return unique[i - 4]
		else:
			run = 1
	return 0

static func _result(category: int, kickers: Array) -> Dictionary:
	var score = category
	for i in range(5):
		score = score * 15 + (int(kickers[i]) if i < kickers.size() else 0)
	var title = HAND_NAMES[category]
	if category == 8 and kickers[0] == 14:
		title = "皇家同花顺"
	return {"score": score, "category": category, "name": title, "kickers": kickers}

# Evaluates the best five-card hand out of five to seven distinct cards.
# Integer base-15 scoring preserves category and every relevant tie breaker.
static func evaluate(cards: Array) -> Dictionary:
	assert(cards.size() >= 5 and cards.size() <= 7)
	var counts = {}
	var suits = [[], [], [], []]
	for card in cards:
		var rank = rank_of(card)
		counts[rank] = counts.get(rank, 0) + 1
		suits[suit_of(card)].append(rank)
	var ranks = counts.keys()
	ranks.sort()
	ranks.reverse()
	var flush_ranks: Array = []
	for suited in suits:
		if suited.size() >= 5:
			suited.sort()
			suited.reverse()
			var sf = _straight_high(suited)
			if sf > 0:
				return _result(8, [sf])
			flush_ranks = suited
	var fours: Array = []
	var trips: Array = []
	var pairs: Array = []
	for rank in ranks:
		if counts[rank] == 4:
			fours.append(rank)
		elif counts[rank] == 3:
			trips.append(rank)
		elif counts[rank] == 2:
			pairs.append(rank)
	if not fours.is_empty():
		var rest = ranks.filter(func(r): return r != fours[0])
		return _result(7, [fours[0], rest[0]])
	if not trips.is_empty() and (not pairs.is_empty() or trips.size() > 1):
		var pair_rank = pairs[0] if not pairs.is_empty() else 0
		if trips.size() > 1:
			pair_rank = maxi(pair_rank, trips[1])
		return _result(6, [trips[0], pair_rank])
	if not flush_ranks.is_empty():
		return _result(5, flush_ranks.slice(0, 5))
	var straight = _straight_high(ranks)
	if straight > 0:
		return _result(4, [straight])
	if not trips.is_empty():
		var rest = ranks.filter(func(r): return r != trips[0])
		return _result(3, [trips[0], rest[0], rest[1]])
	if pairs.size() >= 2:
		var rest = ranks.filter(func(r): return r != pairs[0] and r != pairs[1])
		return _result(2, [pairs[0], pairs[1], rest[0]])
	if pairs.size() == 1:
		var rest = ranks.filter(func(r): return r != pairs[0])
		return _result(1, [pairs[0], rest[0], rest[1], rest[2]])
	return _result(0, ranks.slice(0, 5))

# Pure settlement function, also used by tests for side pots and odd chips.
# An unmatched top contribution is returned rather than awarded as a pot.
static func distribute(players: Array, board: Array, dealer: int) -> Dictionary:
	var levels: Array = []
	var payouts: Array = []
	var pots: Array = []
	for p in players:
		payouts.append(0)
		if p.total_bet > 0 and p.total_bet not in levels:
			levels.append(p.total_bet)
	levels.sort()
	var previous = 0
	for level in levels:
		var contributors: Array = []
		var eligible: Array = []
		for i in range(players.size()):
			if players[i].total_bet >= level:
				contributors.append(i)
				if not players[i].folded:
					eligible.append(i)
		var amount = (level - previous) * contributors.size()
		previous = level
		if contributors.size() == 1:
			payouts[contributors[0]] += amount
			pots.append({"amount": amount, "winners": contributors, "refund": true})
			continue
		assert(not eligible.is_empty(), "A contested pot must have an eligible player")
		var winners: Array = []
		var best = -1
		for i in eligible:
			var score = 0
			if eligible.size() > 1:
				score = evaluate(players[i].hole + board).score
			if score > best:
				best = score
				winners = [i]
			elif score == best:
				winners.append(i)
		# Award the remainder clockwise starting left of the dealer.
		winners.sort_custom(func(a, b): return (a - dealer - 1 + players.size()) % players.size() < (b - dealer - 1 + players.size()) % players.size())
		var share: int = amount / winners.size()
		var remainder: int = amount % winners.size()
		for j in range(winners.size()):
			payouts[winners[j]] += share + (1 if j < remainder else 0)
		pots.append({"amount": amount, "winners": winners, "refund": false})
	return {"payouts": payouts, "pots": pots}
