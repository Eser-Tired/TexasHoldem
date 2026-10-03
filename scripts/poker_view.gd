class_name PokerView
extends RefCounted

signal changed

# Read-only client model. It contains only that player's redacted snapshot.
var players: Array = []
var board: Array = []
var dealer = 0
var small_blind_seat = 0
var big_blind_seat = 1
var actor = -1
var street = 0
var hand_number = 0
var current_bet = 0
var min_raise = 20
var finished = true
var showdown = false
var history: Array = []
var result_text = ""
var winning_seats: Array = []
var last_pot = 0
var hand_start_stacks: Array = []
var revision = -1
var raise_allowed = false
var game_over = false

func apply(snapshot: Dictionary) -> void:
	if int(snapshot.revision) <= revision:
		return
	for key in ["players", "board", "dealer", "small_blind_seat", "big_blind_seat", "actor", "street", "hand_number", "current_bet", "min_raise", "finished", "showdown", "history", "result_text", "winning_seats", "last_pot", "hand_start_stacks", "revision"]:
		set(key, snapshot[key])
	raise_allowed = snapshot.can_raise
	game_over = snapshot.match_over
	changed.emit()

func pot() -> int:
	if finished:
		return 0
	var amount = 0
	for p in players:
		amount += p.total_bet
	return amount

func to_call(seat: int) -> int:
	return maxi(0, current_bet - players[seat].street_bet)

func max_total(seat: int) -> int:
	return players[seat].street_bet + players[seat].stack

func can_raise(seat: int) -> bool:
	return seat == 0 and actor == 0 and not finished and raise_allowed

func match_over() -> bool:
	return game_over
