class_name NetworkDialog
extends Control

var access: NetworkAccess
var panel: PanelContainer
var body: RichTextLabel
var primary: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Theme.new()
	theme.default_font = GameFonts.ui()
	theme.default_font_size = GameFonts.size(24) if MobileLayout.enabled() else 19
	var shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.75)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color("10292f")
	style.border_color = Color("d8ba73")
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var title = Label.new()
	title.text = "局域网连接检查"
	title.add_theme_font_size_override("font_size", GameFonts.size(30))
	column.add_child(title)
	body = RichTextLabel.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size.y = 100
	body.selection_enabled = true
	column.add_child(body)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	primary = _button(row, "放行端口", func():
		if OS.get_name() == "Windows" and LanRoom.is_host:
			access.ensure_port(LanRoom.port)
		else:
			DisplayServer.clipboard_set(body.text))
	var settings = _button(row, "防火墙", func(): OS.create_process("mmc.exe", ["wf.msc"]))
	settings.visible = OS.get_name() == "Windows"
	_button(row, "关闭", hide)
	access.changed.connect(_refresh)
	get_viewport().size_changed.connect(_layout)
	_refresh()
	_layout()
	hide()

func _button(row: HBoxContainer, text: String, action: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(180, 80 if MobileLayout.enabled() else 52)
	button.pressed.connect(action)
	row.add_child(button)
	return button

func _refresh() -> void:
	primary.disabled = access.busy
	primary.text = "检查中…" if access.busy else ("放行端口" if OS.get_name() == "Windows" and LanRoom.is_host else "复制诊断")
	var ips = LanRoom.local_addresses()
	body.text = access.message + "\n\n房主地址：%s\n本机 Wi-Fi / 网卡地址：%s\n房间端口：UDP %d\n\n" % [" / ".join(ips) if LanRoom.is_host else LanRoom.address, " / ".join(ips) if not ips.is_empty() else "未找到 IPv4 地址，请先连接 Wi-Fi", LanRoom.port]
	body.text += "1. 所有人连接同一 Wi-Fi / 局域网，使用相同端口；不要使用 127.0.0.1 连接另一台设备。房主应保持游戏在前台、停留在房间里。\n2. 安卓对安卓：先关闭双方 VPN / 加速器，在应用联网控制中允许本游戏使用 Wi-Fi。本游戏优先分享 Wi-Fi 地址，避免误用蜂窝或 VPN 地址。\n3. 同名 Wi-Fi 也可能开启设备隔离。请避开访客 Wi-Fi；如果仍超时，可由一台手机开启热点，另一台连入后使用房主的新 IP 重试。若热点可连、原 Wi-Fi 不可连，重点检查原路由器的 AP / 客户端隔离。\n4. 安卓 APK 已声明 INTERNET 权限；目前目标 SDK 36 的局域网连接不需要额外的运行时权限弹窗。部分厂商还有单独的应用联网控制，请在系统设置中检查。\n5. Windows 房主首次开房会请求管理员授权，放行当前程序和 UDP 端口，来源仅限本地子网，含专用和公用网络。已有拒绝规则优先，需要在高级防火墙的入站规则中处理。\n\n规则仅放行游戏。更换 EXE 位置或端口后会重新请求授权。"

func present() -> void:
	_refresh()
	_layout()
	show()

func _layout() -> void:
	if panel == null:
		return
	var safe = MobileLayout.safe_rect(get_viewport()) if MobileLayout.enabled() else get_viewport().get_visible_rect().grow(-24)
	panel.size = Vector2(minf(1000, safe.size.x - 24), minf(680, safe.size.y - 24))
	panel.position = safe.get_center() - panel.size / 2

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
