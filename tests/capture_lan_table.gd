extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	var room = root.get_node("LanRoom")
	var count = 4
	var spectator = "--spectator" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			count = int(arg.trim_prefix("--count="))
	if count < 2 or count > 4 or (spectator and count < 3):
		quit(1)
		return
	var names: Array = ["月光", "林", "夏", "陆"].slice(0, count)
	var authority = PokerTable.new(names, false)
	authority.rng.seed = 20261004
	authority.reset_match()
	if spectator:
		authority.players[0].stack = 0
		authority.finished = true
		authority.start_hand()
	while authority.street == 0:
		authority.act("call")
	var recipient = 0 if spectator else count - 1
	room.view = PokerView.new()
	room.view.apply(authority.snapshot_for(recipient, 1))
	room.phase = "playing"
	room.is_host = false
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.snapshot_mode = true
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var path = "res://test-results/lan-table-%d%s.png" % [count, "-spectator" if spectator else ""]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error = root.get_texture().get_image().save_png(path)
	print("Snapshot saved: ", path, " (", error, ")")
	quit(error)
