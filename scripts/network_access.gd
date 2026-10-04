class_name NetworkAccess
extends Node

signal changed

const SOURCE = "res://scripts/windows_firewall.ps1"
var message = "开房后可检查并放行房主的 UDP 端口。"
var busy = false
var checked_port = 0
var result_code = -1
var _pid = -1
var _result_path = ""
var _deadline = 0

static func powershell_literal(value: String) -> String:
	# No user-controlled text is interpolated as executable PowerShell syntax.
	return "[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s'))" % Marshalls.raw_to_base64(value.to_utf8_buffer())

static func encoded_command(source: String) -> String:
	return Marshalls.raw_to_base64(source.to_utf16_buffer())

func ensure_port(room_port: int, allow_prompt: bool = true) -> void:
	if busy:
		return
	checked_port = room_port
	if room_port < 1024 or room_port > 65535:
		_complete(2)
		return
	if OS.get_name() != "Windows":
		message = "安卓版已声明联网权限。请使用同一 Wi-Fi，关闭 VPN，并检查路由器的客户端隔离。"
		changed.emit()
		return
	# UI tests, snapshots and headless LAN tests never launch UAC or change the host.
	if allow_prompt and (OS.has_feature("editor") or DisplayServer.get_name() == "headless"):
		allow_prompt = false
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if arg == "--snapshot" or arg == "--touch-layout" or arg == "--script":
			allow_prompt = false
	_result_path = "user://firewall-%s.txt" % Crypto.new().generate_random_bytes(12).hex_encode()
	var source = FileAccess.get_file_as_string(SOURCE)
	if source.is_empty():
		_complete(2)
		return
	var command = "$GameExecutable=%s;$GamePort=%d;$Mode='%s';$NightfallSource=%s;" % [powershell_literal(OS.get_executable_path().replace("/", "\\")), room_port, "ensure" if allow_prompt else "probe", powershell_literal(source)]
	command += "Invoke-Expression $NightfallSource;try {$code=Invoke-NightfallFirewall} catch {$code=2};[IO.File]::WriteAllText(%s,[string]$code)" % powershell_literal(ProjectSettings.globalize_path(_result_path))
	var executable = OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	_pid = OS.create_process(executable, ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-EncodedCommand", encoded_command(command)])
	if _pid < 0:
		_complete(2)
		return
	busy = true
	result_code = -1
	_deadline = Time.get_ticks_msec() + 120000
	message = "正在检查 UDP %d；需要时请在 Windows 管理员授权窗口中选择“是”。" % room_port
	changed.emit()

func _process(_delta: float) -> void:
	if not busy:
		return
	if FileAccess.file_exists(_result_path):
		var result = FileAccess.get_file_as_string(_result_path).strip_edges()
		if result.is_valid_int():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_result_path))
			_complete(int(result))
	elif Time.get_ticks_msec() >= _deadline:
		OS.kill(_pid)
		_complete(5)
	elif not OS.is_process_running(_pid):
		_complete(2)

func _complete(code: int) -> void:
	busy = false
	_pid = -1
	result_code = code
	match code:
		0: message = "已配置当前游戏 UDP %d 的局域网入站规则（含公用网络）。请让朋友重新加入。" % checked_port
		1: message = "UDP %d 尚未配置限定的局域网放行规则；发布版开房时会自动请求管理员授权。" % checked_port
		3: message = "已取消管理员授权。房间仍可本机使用；点击“放行端口”可重试。"
		4: message = "检测到覆盖 UDP %d 的入站拒绝规则。请打开防火墙设置，检查当前游戏的拒绝规则，再重试。" % checked_port
		5: message = "防火墙授权或检查超时，请确认系统提示后重试。"
		6: message = "系统策略禁止本地放行规则或阻止全部入站，请联系网络管理员。"
		_: message = "无法完成防火墙检查。可在防火墙设置中手动允许当前游戏的 UDP %d。" % checked_port
	changed.emit()

func _exit_tree() -> void:
	if busy and _pid > 0:
		OS.kill(_pid)
	if not _result_path.is_empty() and FileAccess.file_exists(_result_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_result_path))
