extends Node

signal changed

const REPOSITORY_URL = "https://github.com/Eser-Tired/TexasHoldem"
const API_URL = "https://api.github.com/repos/Eser-Tired/TexasHoldem/releases/latest"
const MAX_ASSET_SIZE = 512 * 1024 * 1024

var current_version = ""
var state = "idle"
var message = ""
var release: Dictionary = {}
var asset: Dictionary = {}
var saved_path = ""
var download_directory = "user://updates"
var check_request: HTTPRequest
var download_request: HTTPRequest
var partial_path = ""
var progress = 0.0
var last_download_bytes = 0
var last_download_activity = 0
var platform = ""
var open_url: Callable = OS.shell_open

func _ready() -> void:
	current_version = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	platform = "Android" if OS.has_feature("android") else ("Windows" if OS.has_feature("windows") else "")
	check_request = HTTPRequest.new()
	check_request.timeout = 12
	check_request.body_size_limit = 2 * 1024 * 1024
	check_request.request_completed.connect(_check_completed)
	add_child(check_request)
	download_request = HTTPRequest.new()
	download_request.download_chunk_size = 256 * 1024
	download_request.timeout = 900
	download_request.body_size_limit = MAX_ASSET_SIZE
	download_request.accept_gzip = false
	download_request.request_completed.connect(_download_completed)
	add_child(download_request)
	_configure_proxies()
	var args = OS.get_cmdline_user_args()
	var automatic = not OS.has_feature("editor") or "--snapshot-auto-update" in args
	var capture_only = "--snapshot" in args and "--snapshot-auto-update" not in args
	if automatic and not Engine.is_editor_hint() and DisplayServer.get_name() != "headless" and not capture_only:
		check.call_deferred()

func _configure_proxies() -> void:
	# HTTPRequest does not automatically consume desktop proxy environment variables.
	var pattern = RegEx.new()
	pattern.compile("^http://([^/@:]+):([0-9]{1,5})/?$")
	for kind in ["HTTP", "HTTPS"]:
		var setting = OS.get_environment(kind + "_PROXY")
		if setting.is_empty():
			setting = OS.get_environment(kind.to_lower() + "_proxy")
		var found = pattern.search(setting)
		if found == null:
			continue
		var host = found.get_string(1)
		var port = int(found.get_string(2))
		if port <= 0 or port > 65535:
			continue
		for request in [check_request, download_request]:
			if kind == "HTTPS":
				request.set_https_proxy(host, port)
			else:
				request.set_http_proxy(host, port)

static func version_parts(value: String) -> Array:
	var pattern = RegEx.new()
	pattern.compile("^v?([0-9]{1,9})\\.([0-9]{1,9})\\.([0-9]{1,9})(?:\\+[0-9A-Za-z.-]+)?$")
	var found = pattern.search(value)
	if found == null:
		return []
	return [int(found.get_string(1)), int(found.get_string(2)), int(found.get_string(3))]

static func is_newer(remote: String, local: String) -> bool:
	var a = version_parts(remote)
	var b = version_parts(local)
	if a.is_empty() or b.is_empty():
		return false
	for i in range(3):
		if a[i] != b[i]:
			return a[i] > b[i]
	return false

func _set_state(value: String, text: String) -> void:
	state = value
	message = text
	changed.emit()

func check() -> void:
	if state in ["checking", "downloading", "verifying"]:
		return
	release = {}
	asset = {}
	saved_path = ""
	_set_state("checking", "正在检查 GitHub 最新正式版…")
	var error = check_request.request(API_URL, PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: NightfallPoker/" + current_version, "X-GitHub-Api-Version: 2022-11-28"]))
	if error != OK:
		_set_state("error", "无法发起检查，请稍后重试。游戏仍可正常游玩。")

func _check_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_state("error", "更新检查失败，请检查网络后重试。")
		return
	if code != 200:
		_set_state("error", "GitHub 请求受限，请稍后重试。" if code in [403, 429] else "暂时无法获取最新版，请稍后重试（HTTP %d）。" % code)
		return
	accept_release(JSON.parse_string(body.get_string_from_utf8()))

func accept_release(data: Variant) -> void:
	release = {}
	asset = {}
	if not data is Dictionary or typeof(data.get("draft")) != TYPE_BOOL or typeof(data.get("prerelease")) != TYPE_BOOL or data.draft or data.prerelease:
		_set_state("error", "GitHub 返回的正式版信息无效。")
		return
	var tag = str(data.get("tag_name", ""))
	if version_parts(tag).is_empty():
		_set_state("error", "无法识别最新版本号。")
		return
	if not is_newer(tag, current_version):
		_set_state("current", "当前 v%s 已是最新版本。" % current_version)
		return
	release = {"tag": tag, "url": REPOSITORY_URL + "/releases/tag/" + tag.uri_encode(), "notes": str(data.get("body", "")).left(6000)}
	var suffix = "-Android.apk" if platform == "Android" else "-Windows-x64.exe"
	var expected = "NightfallPoker-%s%s" % [tag if tag.begins_with("v") else "v" + tag, suffix]
	var expected_url = REPOSITORY_URL + "/releases/download/" + tag.uri_encode() + "/" + expected.uri_encode()
	var assets: Variant = data.get("assets", [])
	if not assets is Array:
		assets = []
	for candidate in assets:
		if not candidate is Dictionary or candidate.get("name") != expected or candidate.get("state") != "uploaded" or candidate.get("browser_download_url") != expected_url:
			continue
		var digest = str(candidate.get("digest", ""))
		var hash_pattern = RegEx.new()
		hash_pattern.compile("^sha256:[0-9a-fA-F]{64}$")
		var file_size: Variant = candidate.get("size", 0)
		if hash_pattern.search(digest) == null or typeof(file_size) not in [TYPE_INT, TYPE_FLOAT] or int(file_size) <= 0 or int(file_size) > MAX_ASSET_SIZE:
			continue
		asset = {"name": expected, "url": expected_url, "size": int(file_size), "hash": digest.trim_prefix("sha256:").to_lower()}
		break
	if asset.is_empty() or platform.is_empty():
		_set_state("unavailable", "发现 %s，但对应平台文件尚未就绪，请稍后重新检查。" % tag)
	else:
		_set_state("available", "发现新版本 %s，当前版本 v%s。" % [tag, current_version])

func download() -> void:
	if state not in ["available", "browser"] or asset.is_empty():
		return
	if platform == "Android":
		if open_url.call(asset.url) == OK:
			_set_state("browser", "已打开系统浏览器下载 APK。下载完成后打开文件，按系统提示安装更新。")
		else:
			_set_state("available", "无法打开浏览器，请使用“发布页面”下载。")
		return
	if DirAccess.make_dir_recursive_absolute(download_directory) != OK:
		_set_state("available", "无法创建下载目录，请检查磁盘空间或使用发布页面。")
		return
	saved_path = ProjectSettings.globalize_path(download_directory.path_join(asset.name))
	partial_path = saved_path + ".part"
	download_request.download_file = partial_path
	progress = 0
	last_download_bytes = 0
	last_download_activity = Time.get_ticks_msec()
	_set_state("downloading", "正在下载 %s…" % asset.name)
	var error = download_request.request(asset.url, PackedStringArray(["User-Agent: NightfallPoker/" + current_version]))
	if error != OK:
		_discard_partial()
		_set_state("available", "无法开始下载，请重试。")

func cancel_download() -> void:
	if state != "downloading":
		return
	download_request.cancel_request()
	_discard_partial()
	progress = 0
	_set_state("available", "下载已取消，可重新下载。")

func _discard_partial() -> void:
	if not partial_path.is_empty() and FileAccess.file_exists(partial_path):
		DirAccess.remove_absolute(partial_path)

func _download_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if state != "downloading":
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_discard_partial()
		_set_state("available", "下载失败，请检查网络或磁盘空间后重试。")
		return
	_set_state("verifying", "下载完成，正在校验文件…")
	var file = FileAccess.open(partial_path, FileAccess.READ)
	if file == null:
		_discard_partial()
		_set_state("available", "无法读取下载文件，请重新下载。")
		return
	var valid_size = file.get_length() == int(asset.size)
	var hashing = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	while valid_size and file.get_position() < file.get_length():
		hashing.update(file.get_buffer(2 * 1024 * 1024))
		await get_tree().process_frame
	file.close()
	var digest = hashing.finish().hex_encode()
	if not valid_size or digest != asset.hash:
		_discard_partial()
		_set_state("available", "下载文件校验失败，已丢弃文件，请重新下载。")
		return
	if DirAccess.rename_absolute(partial_path, saved_path) != OK:
		_discard_partial()
		_set_state("available", "无法保存更新文件，请检查目录权限。")
		return
	progress = 1
	_set_state("ready", "下载及 SHA-256 校验完成。打开下载位置，退出游戏后用新 EXE 替换旧文件，或直接运行新文件。")

func show_download() -> void:
	if state == "ready" and FileAccess.file_exists(saved_path):
		OS.shell_show_in_file_manager(saved_path)

func show_release() -> void:
	open_url.call(release.get("url", REPOSITORY_URL + "/releases/latest"))

func _process(_delta: float) -> void:
	if state == "downloading":
		var downloaded = download_request.get_downloaded_bytes()
		if downloaded != last_download_bytes:
			last_download_bytes = downloaded
			last_download_activity = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - last_download_activity > 60000:
			cancel_download()
			_set_state("available", "下载连接超时，可重试或使用发布页面下载。")
			return
		var next_progress = clampf(float(downloaded) / float(asset.size), 0, 1)
		if absf(next_progress - progress) >= 0.005:
			progress = next_progress
			changed.emit()

func _exit_tree() -> void:
	check_request.cancel_request()
	download_request.cancel_request()
	if state == "downloading":
		_discard_partial()
