extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var service = root.get_node("Updater")
	service.current_version = "0.0.0"
	service.platform = "Windows"
	service.download_directory = "res://test-results/updater-live"
	service.check()
	var deadline = Time.get_ticks_msec() + 20000
	while service.state == "checking" and Time.get_ticks_msec() < deadline:
		await process_frame
	if service.state != "available":
		printerr("FAIL: real GitHub check: ", service.message)
		quit(1)
		return
	print("PASS: real GitHub API and Windows artifact: ", service.release.tag)
	if "--download" in OS.get_cmdline_user_args():
		service.download()
		deadline = Time.get_ticks_msec() + 240000
		while service.state in ["downloading", "verifying"] and Time.get_ticks_msec() < deadline:
			await process_frame
		if service.state != "ready":
			printerr("FAIL: real GitHub download: ", service.message)
			quit(1)
			return
		print("PASS: real GitHub streamed Windows download and SHA-256 verification")
		DirAccess.remove_absolute(service.saved_path)
	service.platform = "Android"
	service.check()
	deadline = Time.get_ticks_msec() + 20000
	while service.state == "checking" and Time.get_ticks_msec() < deadline:
		await process_frame
	if service.state != "available" or not str(service.asset.get("name", "")).ends_with("-Android.apk"):
		printerr("FAIL: real Android artifact lookup: ", service.message)
		quit(1)
		return
	print("PASS: real GitHub Android APK selection: ", service.asset.name)
	quit(0)
