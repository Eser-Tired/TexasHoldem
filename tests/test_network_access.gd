extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var room = root.get_node("LanRoom")
	assert(room.parse_endpoint(" 192.168.1.8:24789 ", 24680) == {"address": "192.168.1.8", "port": 24789})
	assert(room.parse_endpoint("192.168.1.8:65536", 24680).address.is_empty())
	assert(room.parse_endpoint("::1", 24680).address == "::1", "IPv6 stays intact")
	var interfaces = [{"name": "rmnet_data0", "addresses": ["10.1.2.3"]}, {"name": "tun0", "addresses": ["10.9.0.1"]}, {"name": "wlan0", "addresses": ["fe80::1", "192.168.8.20"]}]
	assert(room.preferred_addresses(interfaces, ["10.1.2.3", "192.168.8.20"]) == ["192.168.8.20"], "Android shares Wi-Fi rather than cellular or VPN IP")
	assert(room.preferred_addresses([{"name": "Ethernet", "addresses": ["10.20.159.155"]}], []) == ["10.20.159.155"])
	assert(room.preferred_addresses([], ["127.0.0.1", "169.254.1.1", "192.168.1.2"]) == ["192.168.1.2"])
	assert(room.join_room("Tester", "127.0.0.1:24999", 24680) == OK)
	assert(room.address == "127.0.0.1" and room.port == 24999, "Copied endpoint selects its own port")
	room.leave_room()
	var tricky = "C:\\Game's folder\\`$name;test.exe"
	var literal = NetworkAccess.powershell_literal(tricky)
	assert(not literal.contains("Game") and literal.ends_with("'))"), "Paths are safely encoded, not shell-interpolated")
	assert(Marshalls.base64_to_raw(NetworkAccess.encoded_command("夜色" )).get_string_from_utf16() == "夜色")
	var menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	menu._host()
	assert(not menu.network_access.busy, "Source/test hosting does not launch permission prompts")
	assert(menu.network_button.visible)
	menu.network_dialog.present()
	for resolution in [Vector2i(800, 480), Vector2i(960, 720), Vector2i(1280, 720), Vector2i(2400, 1080)]:
		root.size = resolution
		await process_frame
		await process_frame
		var dialog = menu.network_dialog
		var safe = MobileLayout.safe_rect(root) if MobileLayout.enabled() else root.get_visible_rect()
		assert(safe.encloses(dialog.panel.get_global_rect()), "Network dialog fits the screen")
		assert(dialog.panel.get_global_rect().encloses(dialog.primary.get_global_rect()), "Actions remain inside dialog")
	menu.network_access._complete(4)
	assert("拒绝" in menu.network_dialog.body.text and "网络检查" in menu.status.text)
	menu.network_access._complete(3)
	assert("取消" in menu.network_dialog.body.text and not menu.network_dialog.primary.disabled)
	menu.network_access._complete(0)
	assert("已配置" in menu.network_dialog.body.text)
	menu.network_dialog.hide()
	if OS.get_cmdline_user_args().has("--probe-firewall") and OS.get_name() == "Windows":
		menu.network_access.ensure_port(24680, false)
		var deadline = Time.get_ticks_msec() + 20000
		while menu.network_access.busy and Time.get_ticks_msec() < deadline:
			await process_frame
		assert(not menu.network_access.busy and menu.network_access.result_code in [0, 1, 4, 6], "Actual Windows PowerShell probe completes without UAC or mutation")
		print("PASS: actual Windows read-only firewall probe, code ", menu.network_access.result_code)
	room.leave_room()
	menu.free()
	print("PASS: copied endpoints, command encoding, permission-free tests, failure/retry feedback and responsive network dialog")
	quit(0)
