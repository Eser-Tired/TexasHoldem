extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	var menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	var room = root.get_node("LanRoom")
	var create = menu.menu_controls.filter(func(control): return control is Button and control.text == "创建房间  →")[0]
	for count in range(2, 5):
		menu.name_input.text = "测试房主"
		menu.port_input.value = 24900 + count
		menu.capacity_input.select(count - 2)
		create.pressed.emit()
		assert(room.phase == "lobby" and room.capacity == count, "Create button uses selected capacity")
		assert(menu.start_button.visible and menu.start_button.disabled, "One host waits for another ready player")
		assert(not menu.name_input.visible, "Lobby replaces menu inputs")
		room.leave_room()
		assert(menu.name_input.visible and not menu.start_button.visible, "Leave lobby restores menu")
	menu.ip_input.text = "not-an-ip"
	menu._join()
	assert(room.phase == "menu" and "IP" in menu.status.text, "Invalid address shows feedback")
	menu._practice()
	assert(menu.game != null and not menu.game.online and not menu.name_input.visible, "Practice remains accessible")
	menu.game._leave_game()
	await process_frame
	assert(menu.game == null and menu.name_input.visible, "Practice returns to menu")
	assert(room.clean_name(" \n\t ") == "玩家", "Empty nickname defaults")
	assert(room.clean_name("123456789012345").length() == 10, "Nickname length bounded")
	print("PASS: menu buttons, room sizes, invalid address and practice navigation")
	quit(0)
