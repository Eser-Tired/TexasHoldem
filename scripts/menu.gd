extends Control

const GOLD = Color("d8ba73")
const INK = Color("e9eee7")
const MUTED = Color("8aa4a5")
const GREEN = Color("8cd6b4")
const GAME_SCENE = preload("res://scenes/main.tscn")

var font: Font
var name_input: LineEdit
var ip_input: LineEdit
var port_input: SpinBox
var capacity_input: OptionButton
var menu_controls: Array[Control] = []
var lobby_controls: Array[Control] = []
var start_button: Button
var ready_button: Button
var status: Label
var address_label: Label
var game: Control
var touch_layout = false
var mobile_rect = Rect2()
var content_transform = Transform2D.IDENTITY
var control_rects: Dictionary = {}
var update_button: Button
var update_dialog: UpdateDialog

func _ready() -> void:
	get_tree().quit_on_go_back = false
	touch_layout = MobileLayout.enabled()
	font = GameFonts.ui()
	var palette = Theme.new()
	palette.default_font = font
	palette.default_font_size = 18
	palette.set_stylebox("normal", "LineEdit", _style(Color("0c222a"), Color("456368")))
	palette.set_stylebox("focus", "LineEdit", _style(Color("15343b"), GOLD))
	palette.set_color("font_color", "LineEdit", INK)
	palette.set_color("font_placeholder_color", "LineEdit", MUTED)
	palette.set_stylebox("normal", "Button", _style(Color("23434a"), Color("4d686c")))
	palette.set_stylebox("hover", "Button", _style(Color("365961"), GOLD))
	palette.set_stylebox("pressed", "Button", _style(Color("152d34"), GOLD))
	palette.set_stylebox("disabled", "Button", _style(Color("152d34"), Color("29474c")))
	palette.set_stylebox("focus", "Button", _style(Color.TRANSPARENT, GOLD))
	palette.set_color("font_color", "Button", INK)
	palette.set_color("font_disabled_color", "Button", Color("60797d"))
	theme = palette
	_build_updates()
	_build_menu()
	_build_lobby()
	status = Label.new()
	status.position = Vector2(280, 766)
	status.size = Vector2(880, 60)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 17)
	status.add_theme_color_override("font_color", GOLD)
	add_child(status)
	if touch_layout:
		for control in menu_controls + lobby_controls + [status]:
			control_rects[control] = Rect2(control.position, control.size)
			if control is Button or control is LineEdit or control is SpinBox or control is OptionButton:
				control.add_theme_font_size_override("font_size", 24)
				var rect: Rect2 = control_rects[control]
				rect.size.y = maxf(rect.size.y, 64)
				control_rects[control] = rect
		for input in [name_input, ip_input, port_input.get_line_edit()]:
			input.focus_exited.connect(func():
				position.y = 0
				DisplayServer.virtual_keyboard_hide())
	get_viewport().size_changed.connect(_layout_mobile)
	_layout_mobile()
	LanRoom.phase_changed.connect(_phase_changed)
	LanRoom.lobby_changed.connect(_refresh)
	LanRoom.notice.connect(func(message): status.text = message)
	_phase_changed()
	var args = OS.get_cmdline_user_args()
	if "--snapshot" in args and "--snapshot-state=updates" in args:
		_snapshot_updates()
	elif "--snapshot" in args and "--snapshot-state=menu" not in args and "--snapshot-state=lobby" not in args:
		_practice()
	elif "--snapshot-state=lobby" in args:
		LanRoom.host_room("房主", 4)
		_snapshot()
	elif "--snapshot" in args:
		_snapshot()

func _style(color: Color, border: Color) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.content_margin_left = 15
	box.content_margin_right = 15
	return box

func _build_updates() -> void:
	update_button = _button("检查更新", Rect2(950, 30, 185, 50), _show_updates)
	var layer = CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	update_dialog = UpdateDialog.new()
	layer.add_child(update_dialog)
	Updater.changed.connect(_update_notice)
	_update_notice()

func _show_updates() -> void:
	for field in [name_input, ip_input, port_input.get_line_edit()]:
		if field.has_focus():
			field.release_focus()
	update_dialog.present()

func _update_notice() -> void:
	update_button.text = "新版 " + str(Updater.release.get("tag", "")) if Updater.state in ["available", "unavailable", "browser"] else ("正在下载…" if Updater.state in ["downloading", "verifying"] else ("更新已下载" if Updater.state == "ready" else "检查更新"))
	update_button.tooltip_text = Updater.message

func _button(text: String, rect: Rect2, callback: Callable, gold: bool = false) -> Button:
	var button = Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if gold:
		button.add_theme_stylebox_override("normal", _style(GOLD, GOLD))
		button.add_theme_stylebox_override("hover", _style(Color("eed299"), GOLD))
		button.add_theme_color_override("font_color", Color("173439"))
		button.add_theme_color_override("font_hover_color", Color("173439"))
	button.pressed.connect(callback)
	add_child(button)
	return button

func _line(rect: Rect2, placeholder: String, max_length: int) -> LineEdit:
	var input = LineEdit.new()
	input.position = rect.position
	input.size = rect.size
	input.placeholder_text = placeholder
	input.max_length = max_length
	add_child(input)
	return input

func _build_menu() -> void:
	name_input = _line(Rect2(400, 216, 324, 46), "你的昵称（最多 10 字）", 10)
	name_input.text = "玩家"
	menu_controls.append(name_input)
	port_input = SpinBox.new()
	port_input.position = Vector2(824, 216)
	port_input.size = Vector2(230, 46)
	port_input.min_value = 1024
	port_input.max_value = 65535
	port_input.value = LanRoom.DEFAULT_PORT
	port_input.allow_greater = false
	port_input.allow_lesser = false
	add_child(port_input)
	menu_controls.append(port_input)
	capacity_input = OptionButton.new()
	capacity_input.position = Vector2(522, 401)
	capacity_input.size = Vector2(154, 44)
	for count in range(2, 5):
		capacity_input.add_item("最多 %d 人" % count, count)
	capacity_input.select(2)
	add_child(capacity_input)
	menu_controls.append(capacity_input)
	menu_controls.append(_button("创建房间  →", Rect2(350, 484, 326, 54), func():
		LanRoom.host_room(name_input.text, capacity_input.get_selected_id(), int(port_input.value)), true))
	ip_input = _line(Rect2(764, 401, 326, 44), "房主 IP，例如 192.168.1.8", 45)
	ip_input.text_submitted.connect(func(_value): _join())
	menu_controls.append(ip_input)
	menu_controls.append(_button("加入房间  →", Rect2(764, 484, 326, 54), _join, true))
	menu_controls.append(_button("单机练习 · 对战三位电脑", Rect2(522, 655, 396, 54), _practice))

func _build_lobby() -> void:
	address_label = Label.new()
	address_label.position = Vector2(304, 252)
	address_label.size = Vector2(826, 64)
	address_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	address_label.add_theme_font_size_override("font_size", 17)
	address_label.add_theme_color_override("font_color", GREEN)
	add_child(address_label)
	lobby_controls.append(address_label)
	lobby_controls.append(_button("复制连接信息", Rect2(958, 192, 178, 42), func():
		var ips = LanRoom.local_addresses() if LanRoom.is_host else [LanRoom.address]
		DisplayServer.clipboard_set("%s:%d" % [ips[0] if not ips.is_empty() else "127.0.0.1", LanRoom.port])
		status.text = "已复制 IP:端口。朋友在加入房间时分别填写 IP 和端口。"))
	start_button = _button("开始对局  →", Rect2(814, 659, 250, 52), func(): LanRoom.start_game(), true)
	lobby_controls.append(start_button)
	ready_button = _button("准备", Rect2(814, 659, 250, 52), _toggle_ready, true)
	lobby_controls.append(ready_button)
	lobby_controls.append(_button("离开房间", Rect2(374, 659, 210, 52), LanRoom.leave_room))

func _join() -> void:
	if LanRoom.phase == "menu":
		LanRoom.join_room(name_input.text, ip_input.text, int(port_input.value))

func _toggle_ready() -> void:
	for member in LanRoom.members:
		if member.peer_id == multiplayer.get_unique_id():
			LanRoom.set_ready(not member.ready)
			return

func _practice() -> void:
	if game != null or LanRoom.phase != "menu":
		return
	_show_game()

func _show_game() -> void:
	if game == null:
		position.y = 0
		if OS.has_feature("mobile"):
			DisplayServer.virtual_keyboard_hide()
		game = GAME_SCENE.instantiate()
		game.name = "Game"
		game.exit_requested.connect(_end_practice)
		add_child(game)
	_refresh()

func _end_practice() -> void:
	_close_game()
	_refresh()

func _close_game() -> void:
	if game != null:
		remove_child(game)
		game.queue_free()
		game = null

func _phase_changed() -> void:
	if LanRoom.phase == "playing":
		_show_game()
	else:
		_close_game()
	_refresh()

func _refresh() -> void:
	var in_game = game != null
	update_button.visible = not in_game
	var in_lobby = LanRoom.phase == "lobby"
	for control in menu_controls:
		control.visible = not in_game and not in_lobby
		if not control.visible:
			var input = control.get_line_edit() if control is SpinBox else control
			if input.has_focus():
				input.release_focus()
		if control is Button:
			control.disabled = LanRoom.phase == "connecting"
	for control in lobby_controls:
		control.visible = not in_game and in_lobby
	start_button.visible = not in_game and in_lobby and LanRoom.is_host
	ready_button.visible = not in_game and in_lobby and not LanRoom.is_host
	start_button.disabled = not LanRoom.can_start()
	for member in LanRoom.members:
		if member.peer_id == multiplayer.get_unique_id():
			ready_button.text = "取消准备" if member.ready else "准备  ✓"
	var ips = LanRoom.local_addresses() if LanRoom.is_host else [LanRoom.address]
	address_label.text = "房主 IP：%s    /    端口：%d (UDP)\n同一 Wi-Fi 或局域网的朋友，填写上述 IP 和相同端口加入。" % ["  /  ".join(ips) if not ips.is_empty() else "暂无局域网 IP（本机测试可用 127.0.0.1）", LanRoom.port]
	status.visible = not in_game
	status.text = LanRoom.last_message
	queue_redraw()

func _layout_mobile() -> void:
	if not touch_layout or status == null:
		return
	mobile_rect = MobileLayout.safe_rect(get_viewport())
	update_button.position = Vector2(mobile_rect.end.x - 540, mobile_rect.position.y + 12)
	update_button.size = Vector2(230, 62)
	update_button.add_theme_font_size_override("font_size", 24)
	var area = Rect2(mobile_rect.position + Vector2(16, 100), mobile_rect.size - Vector2(32, 100))
	var factor = minf(area.size.x / 900, area.size.y / 700)
	content_transform = Transform2D(0, Vector2.ONE * factor, 0, area.get_center() - Vector2(720, 480) * factor)
	for control in control_rects:
		var rect: Rect2 = control_rects[control]
		control.position = content_transform * rect.position
		control.size = rect.size
		control.scale = Vector2.ONE * factor
	queue_redraw()

func _process(_delta: float) -> void:
	if not touch_layout:
		return
	if mobile_rect != MobileLayout.safe_rect(get_viewport()):
		_layout_mobile()
	if OS.has_feature("mobile") and game == null:
		var field = get_viewport().gui_get_focus_owner()
		if field is LineEdit:
			position.y = MobileLayout.keyboard_shift(self, field, DisplayServer.virtual_keyboard_get_height())
		else:
			position.y = 0

func _text(value: String, point: Vector2, font_size: int = 18, color: Color = INK, centered: bool = false) -> void:
	if centered:
		point.x -= font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / 2
	draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw() -> void:
	if game != null or font == null:
		return
	if touch_layout:
		draw_rect(get_viewport().get_visible_rect(), Color("09191f"))
		var r = mobile_rect
		draw_circle(r.position + Vector2(26, 44), 21, GOLD)
		_text("♠", r.position + Vector2(26, 53), 28, Color("153236"), true)
		_text("夜色牌局", r.position + Vector2(65, 55), 34)
		_text("局域网 · 2–4 人房间", Vector2(r.end.x - 280, r.position.y + 53), 26, GREEN)
		draw_line(Vector2(r.position.x, r.position.y + 85), Vector2(r.end.x, r.position.y + 85), Color("294047"))
		draw_set_transform_matrix(content_transform)
		if LanRoom.phase == "lobby":
			_draw_lobby()
		else:
			_draw_menu()
		draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	draw_rect(Rect2(0, 0, 1440, 900), Color("09191f"))
	for y in range(900):
		draw_line(Vector2(0, y), Vector2(1440, y), Color(0.035 + y * 0.000007, 0.085 + y * 0.000017, 0.105 + y * 0.000012))
	for x in range(28, 1440, 64):
		draw_line(Vector2(x, 102), Vector2(x, 812), Color(0.2, 0.35, 0.35, 0.06))
	draw_circle(Vector2(58, 52), 18, GOLD)
	_text("♠", Vector2(58, 59), 23, Color("153236"), true)
	_text("夜色牌局", Vector2(91, 62), 30)
	_text("T E X A S   H O L D ’ E M", Vector2(257, 59), 14, MUTED)
	_text("局域网 · 2–4 人房间", Vector2(1175, 59), 17, GREEN)
	draw_line(Vector2(36, 99), Vector2(1404, 99), Color("294047"))
	if LanRoom.phase == "lobby":
		_draw_lobby()
	else:
		_draw_menu()
	_text("虚拟筹码 · 和朋友轻松开一桌", Vector2(720, 860), 14, MUTED, true)

func _draw_menu() -> void:
	_text("和朋友开一桌", Vector2(720, 157), 36, INK, true)
	_text("创建房间，分享 IP，等大家准备后一起入局。", Vector2(720, 192), 17, MUTED, true)
	_text("昵称", Vector2(336, 245), 19)
	_text("端口", Vector2(759, 245), 19)
	draw_style_box(_style(Color("132d34"), Color("385157")), Rect2(318, 300, 390, 315))
	draw_style_box(_style(Color("132d34"), Color("385157")), Rect2(732, 300, 390, 315))
	_text("做一回房主", Vector2(350, 347), 26, GOLD)
	_text("邀请 1–3 位朋友，无需外部服务器。", Vector2(350, 378), 16, MUTED)
	_text("人数上限", Vector2(350, 430), 18)
	_text("2 人即可开局，无电脑补位。", Vector2(350, 583), 16, MUTED)
	_text("加入朋友的牌桌", Vector2(764, 347), 26, GOLD)
	_text("输入房主显示的 IP，使用相同端口。", Vector2(764, 378), 16, MUTED)
	_text("请连接同一 Wi-Fi / 局域网。", Vector2(764, 583), 16, MUTED)
	_text("也可以先用单机模式熟悉下注与牌型。", Vector2(720, 740), 16, MUTED, true)
	if LanRoom.phase == "connecting":
		_text("正在连接…  Esc 取消", Vector2(720, 841), 17, GOLD, true)

func _draw_lobby() -> void:
	draw_style_box(_style(Color("122b33"), Color("385157")), Rect2(270, 169, 900, 575))
	_text("%s的房间" % LanRoom.members[0].name, Vector2(304, 217), 28, GOLD)
	_text("%d / %d 人 · 所有人准备后开始" % [LanRoom.members.size(), LanRoom.capacity], Vector2(304, 245), 16, MUTED)
	for i in range(4):
		var row = Rect2(304, 330 + i * 69, 832, 55)
		draw_style_box(_style(Color("1a373e"), Color("2c4c51")), row)
		if i >= LanRoom.members.size():
			_text("等待朋友加入…" if i < LanRoom.capacity else "此座位未开放", row.position + Vector2(25, 35), 17, MUTED)
			continue
		var member = LanRoom.members[i]
		draw_circle(row.position + Vector2(28, 28), 16, Color("3f7668"))
		_text(str(i + 1), row.position + Vector2(28, 34), 18, INK, true)
		_text(member.name, row.position + Vector2(58, 35), 20)
		if member.peer_id == 1:
			_text("房主", row.position + Vector2(270, 34), 16, GOLD)
		if member.peer_id == multiplayer.get_unique_id():
			_text("你", row.position + Vector2(354, 34), 16, GREEN)
		_text("已准备  ✓" if member.ready else "等待准备", row.position + Vector2(701, 35), 17, GREEN if member.ready else MUTED)
	_text("开局后关闭新玩家加入；离线会返回房间。", Vector2(720, 635), 16, MUTED, true)

func _input(event: InputEvent) -> void:
	if update_dialog.visible:
		return
	if game != null or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE and LanRoom.phase == "connecting":
		get_viewport().set_input_as_handled()
		LanRoom.leave_room()
	elif event.keycode == KEY_F11:
		get_viewport().set_input_as_handled()
		var full = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and game == null and is_node_ready():
		if update_dialog.visible:
			update_dialog.hide()
			return
		if LanRoom.phase in ["connecting", "lobby"]:
			LanRoom.leave_room()

func _snapshot() -> void:
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var path = "res://test-results/menu.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot-path="):
			path = arg.trim_prefix("--snapshot-path=")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error = get_viewport().get_texture().get_image().save_png(path)
	if "--snapshot-auto-update" in OS.get_cmdline_user_args():
		var diagnostic = FileAccess.open(path + ".update.txt", FileAccess.WRITE)
		if diagnostic != null:
			diagnostic.store_string(Updater.state + "\n" + Updater.message)
			diagnostic.close()
	print("Snapshot saved: ", path, " (", error, ")")
	get_tree().quit(error)

func _snapshot_updates() -> void:
	var deadline = Time.get_ticks_msec() + 18000
	if "--snapshot-auto-update" in OS.get_cmdline_user_args():
		while Updater.state in ["idle", "checking"] and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
	_show_updates()
	_snapshot()
