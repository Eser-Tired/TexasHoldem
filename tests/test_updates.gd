extends SceneTree

const Service = preload("res://scripts/update_service.gd")

class Fixture extends Node:
	var server = TCPServer.new()
	var peers: Array[StreamPeerTCP] = []
	var port = 0
	var payload = "test release binary".to_utf8_buffer()
	var hold = false
	func _ready() -> void:
		for candidate in range(25110, 25130):
			if server.listen(candidate, "127.0.0.1") == OK:
				port = candidate
				break
		assert(port > 0, "Local fixture starts")
	func _process(_delta: float) -> void:
		while server.is_connection_available():
			peers.append(server.take_connection())
		for peer in peers.duplicate():
			peer.poll()
			if peer.get_status() == StreamPeerTCP.STATUS_NONE:
				peers.erase(peer)
			elif peer.get_available_bytes() > 0 and not hold:
				peer.get_data(peer.get_available_bytes())
				peer.put_data(("HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % payload.size()).to_utf8_buffer())
				peer.put_data(payload)
				peer.disconnect_from_host()
				peers.erase(peer)
	func stop() -> void:
		for peer in peers:
			peer.disconnect_from_host()
		peers.clear()
		server.stop()

func _initialize() -> void:
	call_deferred("run")

func fixture_release(platform: String, hash: String, file_size: int) -> Dictionary:
	var tag = "v1.0.3"
	var name = "NightfallPoker-" + tag + ("-Android.apk" if platform == "Android" else "-Windows-x64.exe")
	return {"tag_name": tag, "draft": false, "prerelease": false, "body": "新版说明\n更好的牌局", "assets": [{"name": name, "state": "uploaded", "size": file_size, "digest": "sha256:" + hash, "browser_download_url": Service.REPOSITORY_URL + "/releases/download/" + tag + "/" + name}]}

func wait_download(service: Node) -> void:
	var deadline = Time.get_ticks_msec() + 5000
	while service.state in ["downloading", "verifying"] and Time.get_ticks_msec() < deadline:
		await process_frame
	assert(service.state not in ["downloading", "verifying"], "Download completes within fixture timeout")

func run() -> void:
	assert(Service.is_newer("v1.10.0", "1.9.9"), "Versions compare numerically")
	assert(Service.is_newer("v2.0.0", "1.99.99"), "Major takes precedence")
	assert(not Service.is_newer("v1.0.2", "1.0.2") and not Service.is_newer("v1.0.1", "1.0.2"), "No same-version update or rollback")
	for invalid in ["latest", "v1.2", "v1.0.3-beta", "1.2.3.4", "../1.2.3", "1.2.9999999999"]:
		assert(Service.version_parts(invalid).is_empty(), "Reject malformed version: " + invalid)
	assert(Service.version_parts("v1.2.3+build") == [1, 2, 3], "Build metadata does not affect precedence")
	var updater = root.get_node("Updater")
	var fixture = Fixture.new()
	root.add_child(fixture)
	var hashing = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(fixture.payload)
	var hash = hashing.finish().hex_encode()
	updater.platform = "Windows"
	updater.current_version = "1.0.2"
	updater.download_directory = "res://test-results/updater"
	updater.download_request.set_http_proxy("", -1)
	updater.download_request.set_https_proxy("", -1)
	var valid = fixture_release("Windows", hash, fixture.payload.size())
	updater.accept_release(valid)
	assert(updater.state == "available" and updater.asset.name.ends_with("-Windows-x64.exe"), "Select Windows artifact")
	for invalid in [null, [], {"tag_name": "v1.0.3"}, {"tag_name": "v1.0.3", "draft": true, "prerelease": false}]:
		updater.accept_release(invalid)
		assert(updater.state == "error" and updater.asset.is_empty(), "Reject bad release metadata")
	for field in ["browser_download_url", "digest", "size", "name", "state"]:
		var bad = valid.duplicate(true)
		bad.assets[0][field] = {"browser_download_url": "https://github.com.attacker.invalid/file.exe", "digest": "sha256:bad", "size": -10, "name": "../evil.exe", "state": "new"}[field]
		updater.accept_release(bad)
		assert(updater.state == "unavailable" and updater.asset.is_empty(), "Reject unsafe or incomplete asset: " + field)
	var old = valid.duplicate(true)
	old.tag_name = "v1.0.1"
	updater.accept_release(old)
	assert(updater.state == "current", "Older latest release never downgrades")
	updater._check_completed(HTTPRequest.RESULT_SUCCESS, 429, [], "{}".to_utf8_buffer())
	assert(updater.state == "error" and updater.message.contains("受限"), "Rate limits are recoverable")
	updater._check_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, [], [])
	assert(updater.state == "error", "Offline failure is recoverable")
	updater.accept_release(valid)
	updater.asset.url = "http://127.0.0.1:%d/binary" % fixture.port
	updater.download()
	await wait_download(updater)
	assert(updater.state == "ready" and FileAccess.file_exists(updater.saved_path), "Streamed download verified and saved")
	assert(FileAccess.get_file_as_bytes(updater.saved_path) == fixture.payload, "Saved binary matches fixture")
	assert(not FileAccess.file_exists(updater.partial_path), "No partial file after success")
	updater.accept_release(valid)
	updater.asset.url = "http://127.0.0.1:%d/binary" % fixture.port
	updater.download()
	await wait_download(updater)
	assert(updater.state == "ready", "Repeated download replaces cached file successfully")
	DirAccess.remove_absolute(updater.saved_path)
	updater.accept_release(valid)
	updater.asset.url = "http://127.0.0.1:%d/binary" % fixture.port
	updater.asset.hash = "0".repeat(64)
	updater.download()
	await wait_download(updater)
	assert(updater.state == "available" and not FileAccess.file_exists(updater.partial_path) and not FileAccess.file_exists(updater.saved_path), "Hash mismatch is discarded")
	updater.accept_release(valid)
	updater.asset.url = "http://127.0.0.1:%d/binary" % fixture.port
	updater.asset.size += 1
	updater.download()
	await wait_download(updater)
	assert(updater.state == "available" and not FileAccess.file_exists(updater.saved_path), "Size mismatch is discarded")
	fixture.hold = true
	updater.accept_release(valid)
	updater.asset.url = "http://127.0.0.1:%d/hold" % fixture.port
	updater.download()
	await process_frame
	updater.cancel_download()
	assert(updater.state == "available" and not FileAccess.file_exists(updater.partial_path), "Cancel removes partial download")
	updater.download()
	updater.last_download_activity = Time.get_ticks_msec() - 60001
	updater._process(0)
	assert(updater.state == "available" and updater.message.contains("超时"), "Stalled download times out without blocking gameplay")
	var opened: Array = []
	updater.open_url = func(url): opened.append(url); return OK
	updater.platform = "Android"
	updater.accept_release(fixture_release("Android", hash, fixture.payload.size()))
	updater.download()
	assert(updater.state == "browser" and opened[0].ends_with("-Android.apk"), "Android opens exact latest APK download")
	updater.show_release()
	assert(opened[1] == Service.REPOSITORY_URL + "/releases/tag/v1.0.3", "Release link stays in repository")
	var menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	menu.update_button.pressed.emit()
	await process_frame
	assert(menu.update_dialog.visible and menu.update_dialog.primary.text == "重新打开下载", "Update dialog reflects Android download")
	var dialog = menu.update_dialog
	await process_frame
	assert(root.get_visible_rect().encloses(dialog.panel.get_global_rect()), "Dialog initially fits screen without resizing")
	assert(dialog.panel.get_global_rect().encloses(dialog.primary.get_global_rect()), "Initial buttons stay inside dialog")
	if MobileLayout.enabled():
		for resolution in [Vector2i(960, 720), Vector2i(1280, 720), Vector2i(2400, 1080)]:
			root.size = resolution
			await process_frame
			await process_frame
			assert(MobileLayout.safe_rect(root).encloses(dialog.panel.get_global_rect()), "Update dialog fits mobile safe area")
			assert(dialog.panel.get_global_rect().encloses(dialog.primary.get_global_rect()), "Download button stays in dialog")
			assert(MobileLayout.safe_rect(root).encloses(menu.update_button.get_global_rect()), "Update entry stays on screen")
	dialog.close_button.pressed.emit()
	assert(not dialog.visible, "Closing update dialog returns to game")
	menu._practice()
	assert(menu.game != null and not menu.update_button.visible, "Updater does not block practice")
	menu._end_practice()
	fixture.stop()
	root.remove_child(fixture)
	fixture.free()
	root.remove_child(menu)
	menu.free()
	print("PASS: version ordering, platform assets, unsafe metadata, offline/rate limits, streamed downloads, hashes, cancellation, Android handoff and update dialog")
	quit(0)
