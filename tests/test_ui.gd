extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if not MobileLayout.enabled():
		assert(GameFonts.size(24) == 24 and GameFonts.ui().variation_opentype == {"wght": 450.0}, "Desktop typography stays unchanged")
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.snapshot_mode = true
	await process_frame
	assert(main.call_button.disabled, "Action buttons disabled while AI acts")
	main.table.act("call")
	assert(main.table.actor == 0 and not main.call_button.disabled, "Hero receives enabled action buttons")
	main.slider.value = 40
	assert(main.amount_input.text == "40", "Slider updates numeric input")
	for invalid in ["", "abc", "1.5", "-125", "+125", "39", "1001"]:
		main.amount_input.text = invalid
		main.amount_input.text_changed.emit(invalid)
		assert(main.raise_button.disabled, "Invalid amount disables Raise: " + invalid)
		main._raise_from_input()
		assert(main.table.current_bet == 20 and main.table.actor == 0, "Invalid input never spends chips")
	main.quick_buttons[0].pressed.emit()
	assert(main.amount_input.text == "40" and not main.raise_button.disabled, "Preset recovers invalid text even if slider value is unchanged")
	assert(main.status_label.text.contains("40") and not main.status_label.text.contains("最小加注"), "Preset clears stale validation error")
	main.amount_input.grab_focus()
	for key in [KEY_R, KEY_F, KEY_SPACE]:
		var typing = InputEventKey.new()
		typing.keycode = key
		typing.pressed = true
		Input.parse_input_event(typing)
		await process_frame
		assert(main.table.actor == 0 and main.table.current_bet == 20 and not main.table.players[0].folded, "Typing never triggers action shortcuts")
	main.amount_input.text = " 125 "
	main.amount_input.text_changed.emit(main.amount_input.text)
	assert(not main.raise_button.disabled and main.slider.value == 125, "Arbitrary integer syncs to slider without rounding")
	main.amount_input.text_submitted.emit(main.amount_input.text)
	assert(main.amount_input.text == "125" and not main.amount_input.has_focus() and main.table.current_bet == 20, "Enter confirms text without placing a bet")
	var stack_before = main.table.players[0].stack
	var contributed = main.table.players[0].street_bet
	main.raise_button.pressed.emit()
	assert(main.table.current_bet == 125 and main.table.actor == 1, "Raise button sends exact typed street total")
	assert(main.table.players[0].stack == stack_before - (125 - contributed), "Only difference from existing contribution is charged")
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
	assert(GameFonts.CJK.has_char(0x4e2d) and GameFonts.CJK.has_char(0x2660), "Bundled font supplies Chinese and suit glyphs")
	print("PASS: exact integer input, invalid amounts, slider/presets, Enter, typing focus, buttons, modal, next hand, all-in and bundled font")
	root.remove_child(main)
	main.free()
	quit(0)
