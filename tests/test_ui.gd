extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.snapshot_mode = true
	await process_frame
	assert(main.call_button.disabled, "Action buttons disabled while AI acts")
	main.table.act("call")
	assert(main.table.actor == 0 and not main.call_button.disabled, "Hero receives enabled action buttons")
	main.slider.value = 40
	main.raise_button.pressed.emit()
	assert(main.table.current_bet == 40 and main.table.actor == 1, "Raise button sends chosen street total")
	# Keyboard shortcuts must work even after a different button acquired focus.
	while main.table.actor != 0:
		main.table.act("call")
	main.fold_button.grab_focus()
	var space_event = InputEventKey.new()
	space_event.keycode = KEY_SPACE
	space_event.pressed = true
	Input.parse_input_event(space_event)
	await process_frame
	assert(not main.table.players[0].folded and main.table.actor != 0, "Space checks rather than activating focused Fold button")
	while not main.table.finished:
		if main.table.actor == 0:
			main.rules_panel.show()
			var street = main.table.street
			main.call_button.pressed.emit()
			assert(main.table.actor == 0 and main.table.street == street, "Modal pauses user action")
			main.rules_panel.hide()
			main.call_button.pressed.emit()
		else:
			main.table.act("call")
	assert(main.next_button.visible and not main.call_button.visible, "Showdown presents next-hand control")
	assert(main.result_panel.visible, "Showdown summary visible")
	main.next_button.pressed.emit()
	assert(main.table.hand_number == 2 and not main.result_panel.visible, "Next hand clears result")
	main.table.reset_match()
	main.table.act("call")
	main.allin_button.pressed.emit()
	assert(main.table.players[0].stack == 0, "All-in button commits all hero chips")
	while not main.table.finished:
		main.table.act("call")
	assert(main.table.board.size() == 5, "AI calls resolve hero all-in")
	print("PASS: UI button actions, raise slider, keyboard focus, modal pause, next hand, all-in")
	root.remove_child(main)
	main.free()
	quit(0)
