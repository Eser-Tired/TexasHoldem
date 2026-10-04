extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func _inside(control: Control, bounds: Rect2) -> void:
	var rect = control.get_global_rect()
	assert(bounds.grow(1).encloses(rect), "%s stays within screen: %s / %s" % [control.name, rect, bounds])

func run() -> void:
	assert(MobileLayout.enabled(), "Run with -- --touch-layout")
	assert(GameFonts.size(24) == 36 and GameFonts.size(30) == 45, "Mobile font sizes increase by 1.5")
	assert(GameFonts.ui().variation_opentype[TextServerManager.get_primary_interface().name_to_tag("wght")] == 700.0, "Mobile uses bold bundled font")
	var menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	menu._practice()
	var game = menu.game
	assert(game.fold_button.get_theme_font_size("font_size") == 42, "Bet buttons use enlarged mobile text")
	assert(game.amount_input.get_theme_font_size("font_size") == 45, "Numeric input uses enlarged mobile text")
	assert(menu.name_input.get_theme_font_size("font_size") == 36, "Lobby inputs use enlarged mobile text")
	assert(menu.capacity_input.get_popup().get_theme_font_size("font_size") == 36, "Capacity popup uses enlarged mobile text")
	assert(game.rules_body.get_theme_font_size("normal_font_size") == 39, "Scrollable guide uses enlarged mobile text")
	assert(menu.update_dialog.theme.default_font_size == 36, "Updater uses enlarged mobile text")
	game.snapshot_mode = true
	var resolutions = [Vector2i(800, 480), Vector2i(960, 720), Vector2i(1280, 800), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2160, 1080), Vector2i(2400, 1080), Vector2i(2560, 1080)]
	for resolution in resolutions:
		root.size = resolution
		await process_frame
		await process_frame
		var safe = MobileLayout.safe_rect(root)
		_inside(menu.update_button, safe)
		for control in game.header_buttons + [game.fold_button, game.call_button, game.raise_button, game.allin_button, game.amount_input, game.next_button, game.reset_button]:
			_inside(control, safe)
		var actions = [game.fold_button, game.call_button, game.raise_button, game.allin_button, game.amount_input]
		for i in range(actions.size() - 1):
			assert(actions[i].get_global_rect().end.x <= actions[i + 1].get_global_rect().position.x, "Action controls do not overlap")
		for button in game.header_buttons + [game.fold_button, game.call_button, game.raise_button, game.allin_button]:
			assert(button.get_theme_font("font").get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x <= button.size.x, "Enlarged button text fits: " + button.text)
		assert(game.amount_input.size.x > 200, "Amount input stays usable")
		assert(is_equal_approx(game.board_transform.get_scale().x, game.board_transform.get_scale().y), "Cards keep their aspect ratio")
		var board = game.board_transform * Rect2(20, 105, 1080, 675)
		assert(safe.encloses(board) and board.end.y <= game.actions_rect.position.y, "Seats and cards fit above actions")
		_inside(game.status_label, safe)
		_inside(game.result_panel, safe)
		game.rules_panel.show()
		_inside(game.rules_panel, safe)
		_inside(game.rules_body, game.rules_panel.get_global_rect())
		_inside(game.rules_close, game.rules_panel.get_global_rect())
		assert(not game.rules_body.get_global_rect().intersects(game.rules_close.get_global_rect()), "Scrollable rules do not cover close button")
		game.rules_panel.hide()
		for control in menu.menu_controls + menu.lobby_controls + [menu.status]:
			_inside(control, safe)
		for control in menu.menu_controls:
			if control is Button and not control is OptionButton:
				assert(not control.get_global_rect().intersects(menu.capacity_input.get_global_rect()), "Capacity selector is not covered by menu buttons")
		assert(game.show_sidebar == (safe.size.x >= 1760), "Sidebar uses available-width breakpoint")
		if game.show_sidebar:
			var sidebar = game.sidebar_transform * Rect2(1112, 113, 294, 653)
			assert(safe.grow(1).encloses(sidebar) and sidebar.end.y <= game.actions_rect.position.y, "Sidebar fits between header and actions")
		var old_position = game.position
		game.position.y = MobileLayout.keyboard_shift(game, game.amount_input, resolution.y * 0.45)
		var transform = root.get_screen_transform()
		var field_bottom = (transform * game.amount_input.get_global_rect()).end.y
		assert(field_bottom <= resolution.y * 0.55 - 17, "Keyboard leaves numeric field visible")
		var second_shift = MobileLayout.keyboard_shift(game, game.amount_input, resolution.y * 0.45)
		assert(is_equal_approx(second_shift, game.position.y), "Keyboard offset is stable across frames")
		game.position = old_position
		print("PASS: responsive layout at ", resolution)
	# Verify resizing does not replace input text or change an exact bet.
	game.table.act("call")
	game.amount_input.text = "137"
	game.amount_input.text_changed.emit("137")
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	assert(game.amount_input.text == "137", "Resizing preserves numeric input")
	for pressed in [true, false]:
		var click = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = root.get_screen_transform() * game.raise_button.get_global_rect().get_center()
		click.global_position = click.position
		click.pressed = pressed
		Input.parse_input_event(click)
		await process_frame
	assert(game.table.current_bet == 137, "Responsive controls still submit exact totals")
	menu._end_practice()
	await process_frame
	var create = menu.menu_controls.filter(func(control): return control is Button and control.text == "创建房间  →")[0]
	create.pressed.emit()
	assert(root.get_node("LanRoom").phase == "lobby", "Responsive lobby creation works")
	_inside(menu.address_label, MobileLayout.safe_rect(root))
	root.get_node("LanRoom").leave_room()
	root.remove_child(menu)
	menu.free()
	print("PASS: mobile screen widths, touch controls, popup, keyboard, input preservation and room creation")
	quit(0)
