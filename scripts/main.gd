extends Control

signal exit_requested

const INK = Color("e9eee7")
const MUTED = Color("849d9e")
const GOLD = Color("d8ba73")
const GREEN = Color("8cd6b4")
const BG = Color("09191f")
const SEATS = [Vector2(410, 682), Vector2(50, 347), Vector2(434, 110), Vector2(858, 347)]

var table
var online = false
var restart_button: Button
var ui_font: Font
var card_font: Font
var symbol_font: Font
var fold_button: Button
var call_button: Button
var raise_button: Button
var allin_button: Button
var next_button: Button
var reset_button: Button
var sound_button: Button
var slider: HSlider
var amount_input: LineEdit
var syncing_amount = false
var touch_layout = false
var quick_buttons: Array[Button] = []
var rules_panel: Panel
var result_panel: Panel
var result_label: Label
var status_label: Label
var ai_wait = 0.0
var deal_progress = 0.0
var previous_board_size = -1
var previous_hand = -1
var sound_enabled = true
var audio_player: AudioStreamPlayer
var snapshot_mode = false
var pulse = 0.0
var header_buttons: Array[Button] = []
var mobile_rect = Rect2()
var board_transform = Transform2D.IDENTITY
var sidebar_transform = Transform2D.IDENTITY
var show_sidebar = true
var actions_rect = Rect2()
var rules_heading: Label
var rules_body: RichTextLabel
var rules_close: Button

func _ready() -> void:
	online = LanRoom.phase == "playing" and LanRoom.view != null
	touch_layout = MobileLayout.enabled()
	ui_font = GameFonts.ui()
	if OS.has_feature("mobile"):
		card_font = ui_font
	else:
		var serif = SystemFont.new()
		serif.font_names = PackedStringArray(["Georgia", "DejaVu Serif", "serif"])
		card_font = serif
	symbol_font = ui_font
	var theme_resource = Theme.new()
	theme_resource.default_font = ui_font
	theme_resource.default_font_size = 17
	theme = theme_resource
	audio_player = AudioStreamPlayer.new()
	audio_player.volume_db = -19
	add_child(audio_player)
	_build_controls()
	get_viewport().size_changed.connect(_layout_mobile)
	_layout_mobile()
	table = LanRoom.view if online else PokerTable.new()
	table.changed.connect(_table_changed)
	if online:
		LanRoom.input_changed.connect(_table_changed)
		LanRoom.notice.connect(func(message): status_label.text = message)
	snapshot_mode = "--snapshot" in OS.get_cmdline_user_args()
	_table_changed()
	if snapshot_mode and not online:
		table.rng.seed = 20261003
		table.reset_match()
		if "--snapshot-state=flop" in OS.get_cmdline_user_args():
			while table.street == 0 or table.actor != 0:
				table.act("call")
		elif "--snapshot-state=showdown" in OS.get_cmdline_user_args():
			while not table.finished:
				table.act("call")
		elif "--snapshot-state=rules" in OS.get_cmdline_user_args():
			rules_panel.show()
		_capture_preview()
	elif snapshot_mode:
		_capture_preview()

func _style(color: Color, border: Color = Color.TRANSPARENT, radius: int = 12) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1 if border.a > 0 else 0)
	box.set_corner_radius_all(radius)
	return box

func _button(text: String, rect: Rect2, callback: Callable, accent: bool = false) -> Button:
	var b = Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", _style(GOLD if accent else Color("193037"), Color("33464a")))
	b.add_theme_stylebox_override("hover", _style(Color("eed299") if accent else Color("29464b"), GOLD))
	b.add_theme_stylebox_override("pressed", _style(Color("b79859") if accent else Color("122b30"), GOLD))
	b.add_theme_stylebox_override("disabled", _style(Color("10252b"), Color("1f3338")))
	b.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, GOLD))
	b.add_theme_color_override("font_color", Color("142b2d") if accent else INK)
	b.add_theme_color_override("font_hover_color", Color("142b2d") if accent else INK)
	b.add_theme_color_override("font_pressed_color", Color("142b2d") if accent else INK)
	b.add_theme_color_override("font_disabled_color", Color("4c656b"))
	b.pressed.connect(callback)
	add_child(b)
	return b

func _build_controls() -> void:
	var help_button = _button("玩法说明  ?", Rect2(1120, 37, 118, 40), func(): rules_panel.show())
	restart_button = _button("重新开局", Rect2(1250, 37, 156, 40), _ask_reset)
	restart_button.disabled = online and not LanRoom.is_host
	var leave_button = _button("离开房间" if online else "返回大厅", Rect2(843, 37, 130, 40), _leave_game)
	sound_button = _button("声音 · 开", Rect2(987, 37, 118, 40), func():
		sound_enabled = not sound_enabled
		sound_button.text = "声音 · 开" if sound_enabled else "声音 · 关")
	header_buttons.assign([leave_button, sound_button, help_button, restart_button])
	fold_button = _button("弃牌" if touch_layout else "弃牌  F", Rect2(266, 808, 122, 52), func(): _player_action("fold"))
	call_button = _button("过牌  SPACE", Rect2(398, 808, 157, 52), func(): _player_action("call"), true)
	raise_button = _button("加注" if touch_layout else "加注  R", Rect2(565, 808, 157, 52), _raise_from_input)
	allin_button = _button("全下", Rect2(732, 808, 112, 52), _all_in)
	next_button = _button("下一手  →", Rect2(846, 808, 196, 52), _next_hand, true)
	reset_button = _button("再玩一局", Rect2(1054, 808, 196, 52), _reset_match)
	slider = HSlider.new()
	slider.position = Vector2(882, 842)
	slider.size = Vector2(275, 20)
	slider.step = 10
	var rail = _style(Color("36565b"), Color.TRANSPARENT, 3)
	rail.content_margin_top = 3
	rail.content_margin_bottom = 3
	var fill = _style(GOLD, Color.TRANSPARENT, 3)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	slider.add_theme_stylebox_override("slider", rail)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.value_changed.connect(_slider_amount_changed)
	add_child(slider)
	amount_input = LineEdit.new()
	amount_input.position = Vector2(965, 798)
	amount_input.size = Vector2(192, 38)
	amount_input.max_length = 9
	amount_input.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_input.select_all_on_focus = true
	amount_input.placeholder_text = "输入筹码"
	amount_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	amount_input.add_theme_stylebox_override("normal", _style(Color("0c222a"), Color("456368"), 8))
	amount_input.add_theme_stylebox_override("focus", _style(Color("15343b"), GOLD, 8))
	amount_input.add_theme_stylebox_override("read_only", _style(Color("10252b"), Color("294047"), 8))
	amount_input.add_theme_color_override("font_color", GOLD)
	amount_input.add_theme_color_override("font_uneditable_color", MUTED)
	amount_input.add_theme_constant_override("outline_size", 0)
	amount_input.text_changed.connect(_amount_edited)
	amount_input.text_submitted.connect(_confirm_amount)
	amount_input.focus_exited.connect(func():
		position.y = 0
		DisplayServer.virtual_keyboard_hide())
	add_child(amount_input)
	for i in range(3):
		var index = i
		quick_buttons.append(_button(["最小", "½ 池", "满池"][i], Rect2(1182 + i * 70, 819, 62, 34), func(): _quick_raise(index)))
	status_label = Label.new()
	status_label.position = Vector2(282, 495)
	status_label.size = Vector2(556, 32)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", GREEN)
	add_child(status_label)
	result_panel = Panel.new()
	result_panel.position = Vector2(185, 282)
	result_panel.size = Vector2(750, 54)
	result_panel.add_theme_stylebox_override("panel", _style(Color("173e3e"), GOLD, 12))
	result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(result_panel)
	result_label = Label.new()
	result_label.position = Vector2(16, 5)
	result_label.size = Vector2(718, 44)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	result_label.clip_text = true
	result_label.add_theme_font_size_override("font_size", 17)
	result_label.add_theme_color_override("font_color", GOLD)
	result_panel.add_child(result_label)
	_build_rules()

func _build_rules() -> void:
	rules_panel = Panel.new()
	rules_panel.position = Vector2(260, 122)
	rules_panel.size = Vector2(920, 650)
	rules_panel.add_theme_stylebox_override("panel", _style(Color("10292f"), GOLD, 22))
	add_child(rules_panel)
	var heading = Label.new()
	heading.text = "牌桌指南 · 可滚动阅读"
	heading.position = Vector2(38, 24)
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", GOLD)
	rules_panel.add_child(heading)
	var body = RichTextLabel.new()
	body.position = Vector2(38, 91)
	body.size = Vector2(845, 460)
	body.scroll_active = true
	body.selection_enabled = true
	body.add_theme_font_size_override("normal_font_size", 19)
	body.add_theme_color_override("default_color", INK)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = "每人初始 1,000 筹码，小盲 10 / 大盲 20。局域网支持 2–4 人；全部准备后由房主开局、开始下一手或重置筹码。出局后可以观看。\n\n每手两张底牌，依次进行翻牌前、翻牌（3 张）、转牌、河牌四轮下注。从底牌与公共牌中任选五张组成最强牌型。\n\n弃牌退出本手；过牌无需投入；跟注补齐差额；全下投入剩余筹码。加注金额可直接输入整数，回车确认数值，再点击加注。金额是本轮下注总额，例如已下注 20，输入 125，加注后本轮总共投入 125（再扣 105）。桌面端也可用滑块与快捷按钮。\n\n不足最小加注的全下，不会单独重新开放已行动玩家的加注权。边池分别结算，同分平分，多出的零头按庄家左侧顺序分配。\n\n同花顺 > 四条 > 葫芦 > 同花 > 顺子 > 三条 > 两对 > 一对 > 高牌。A 可组成 A2345 最小顺子。\n\n玩家离线会结束本局并返回房间，重新准备开局；房主离开则关闭房间。\n\n空格 跟注/过牌/下一手 · F 弃牌 · R 加注 · F11 全屏 · Esc 关闭指南。输入金额时不触发下注快捷键。"
	rules_panel.add_child(body)
	var close_button = _button("回到牌桌", Rect2(630, 691, 180, 48), func(): rules_panel.hide(), true)
	remove_child(close_button)
	rules_panel.add_child(close_button)
	close_button.position = Vector2(370, 566)
	rules_heading = heading
	rules_body = body
	rules_close = close_button
	rules_panel.hide()

func _layout_mobile() -> void:
	if not touch_layout or rules_panel == null:
		return
	mobile_rect = MobileLayout.safe_rect(get_viewport())
	var r = mobile_rect
	for i in range(header_buttons.size()):
		var button = header_buttons[i]
		button.position = Vector2(r.end.x - 584 + i * 148, r.position.y + 12)
		button.size = Vector2(140, 62)
		button.add_theme_font_size_override("font_size", 24)
	actions_rect = Rect2(r.position.x, r.end.y - 142, r.size.x, 142)
	var gap = 12.0
	var unit = (r.size.x - 32 - gap * 4) / 5.4
	var x = r.position.x + 16
	var buttons = [fold_button, call_button, raise_button, allin_button]
	var weights = [0.8, 1.2, 1.0, 0.8]
	for i in range(buttons.size()):
		buttons[i].position = Vector2(x, actions_rect.position.y + 53)
		buttons[i].size = Vector2(unit * weights[i], 76)
		buttons[i].add_theme_font_size_override("font_size", 28)
		x += unit * weights[i] + gap
	amount_input.position = Vector2(x, actions_rect.position.y + 53)
	amount_input.size = Vector2(unit * 1.6, 76)
	amount_input.add_theme_font_size_override("font_size", 30)
	for i in range(2):
		var button = next_button if i == 0 else reset_button
		button.position = Vector2(r.end.x - 510 + i * 250, actions_rect.position.y + 53)
		button.size = Vector2(238, 76)
		button.add_theme_font_size_override("font_size", 26)
	show_sidebar = r.size.x >= 1760
	var table_area = Rect2(r.position.x, r.position.y + 90, r.size.x - (330 if show_sidebar else 0), actions_rect.position.y - r.position.y - 102)
	var board_scale = minf(table_area.size.x / 1080, table_area.size.y / 675)
	board_transform = Transform2D(0, Vector2.ONE * board_scale, 0, table_area.get_center() - Vector2(560, 442.5) * board_scale)
	status_label.position = board_transform * Vector2(282, 495)
	status_label.size = Vector2(556, 36)
	status_label.scale = Vector2.ONE * board_scale
	status_label.add_theme_font_size_override("font_size", 23)
	result_panel.position = board_transform * Vector2(185, 282)
	result_panel.scale = Vector2.ONE * board_scale
	var sidebar_scale = minf(1, table_area.size.y / 653)
	sidebar_transform = Transform2D(0, Vector2.ONE * sidebar_scale, 0, Vector2(r.end.x - 294 * sidebar_scale, table_area.position.y) - Vector2(1112, 113) * sidebar_scale)
	rules_panel.size = Vector2(minf(1100, r.size.x - 32), minf(760, r.size.y - 32))
	rules_panel.position = r.get_center() - rules_panel.size / 2
	rules_heading.position = Vector2(30, 24)
	rules_heading.add_theme_font_size_override("font_size", 30)
	rules_body.position = Vector2(30, 85)
	rules_body.size = rules_panel.size - Vector2(60, 195)
	rules_body.add_theme_font_size_override("normal_font_size", 26)
	rules_close.size = Vector2(260, 72)
	rules_close.position = Vector2((rules_panel.size.x - 260) / 2, rules_panel.size.y - 92)
	rules_close.add_theme_font_size_override("font_size", 26)
	queue_redraw()

func _ask_reset() -> void:
	if _modal_open() or (online and not LanRoom.is_host):
		return
	var dialog = ConfirmationDialog.new()
	dialog.title = "重新开局"
	dialog.dialog_text = "重新开始会把所有人的筹码重置为 1,000。"
	dialog.ok_button_text = "重新开始"
	dialog.cancel_button_text = "继续本局"
	dialog.confirmed.connect(_reset_match)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(450, 160))

func _leave_game() -> void:
	if _modal_open():
		return
	if not online:
		exit_requested.emit()
		return
	var dialog = ConfirmationDialog.new()
	dialog.title = "离开房间"
	dialog.dialog_text = "你是房主，离开会关闭房间。" if LanRoom.is_host else "离开后，本局会结束，其他玩家返回房间。"
	dialog.ok_button_text = "离开"
	dialog.cancel_button_text = "继续游戏"
	dialog.confirmed.connect(LanRoom.leave_room)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:
			dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(450, 160))

func _modal_open() -> bool:
	if rules_panel.visible:
		return true
	for child in get_children():
		if child is ConfirmationDialog and child.visible:
			return true
	return false

func _reset_match() -> void:
	if online:
		LanRoom.reset_game()
	else:
		table.reset_match()
	_play_sound(460.0)

func _next_hand() -> void:
	if _modal_open():
		return
	if online:
		LanRoom.next_hand()
		return
	if table.match_over():
		_reset_match()
	else:
		table.start_hand()
		_play_sound(330.0)

func _quick_raise(index: int) -> void:
	var target = table.current_bet + table.min_raise
	if index > 0:
		target = table.current_bet + maxi(table.min_raise, int((table.pot() + table.to_call(0)) * (0.5 if index == 1 else 1.0)))
	slider.value = clampi(target, int(slider.min_value), int(slider.max_value))
	_slider_amount_changed(slider.value)

func _amount_error() -> String:
	var text = amount_input.text.strip_edges()
	if text.is_empty() or not text.is_valid_int() or text.begins_with("-") or text.begins_with("+"):
		return "请输入整数筹码。"
	var value = int(text)
	var minimum = mini(table.current_bet + table.min_raise, table.max_total(0))
	if value < minimum or value <= table.current_bet:
		return "最小加注总额为 %d 筹码。" % minimum
	if value > table.max_total(0):
		return "本轮最多可下注 %d 筹码。" % table.max_total(0)
	return ""

func _slider_amount_changed(value: float) -> void:
	if not syncing_amount and amount_input != null:
		amount_input.text = str(int(value))
		if table != null:
			_amount_edited(amount_input.text)
	queue_redraw()

func _amount_edited(_text: String) -> void:
	if syncing_amount or table == null:
		return
	var error = _amount_error()
	var allowed = table.can_raise(0) and (not online or not LanRoom.action_pending)
	raise_button.disabled = not allowed or not error.is_empty()
	if allowed:
		if error.is_empty():
			syncing_amount = true
			slider.value = int(amount_input.text.strip_edges())
			syncing_amount = false
			status_label.text = "加注总额 %d · 点击加注执行" % int(slider.value)
		else:
			status_label.text = error
	queue_redraw()

func _confirm_amount(_text: String) -> void:
	if _amount_error().is_empty():
		amount_input.text = str(int(amount_input.text.strip_edges()))
		amount_input.release_focus()
	else:
		status_label.text = _amount_error()

func _raise_from_input() -> void:
	if table.actor != 0 or _modal_open():
		return
	var error = _amount_error()
	if not error.is_empty():
		status_label.text = error
		return
	var target = int(amount_input.text.strip_edges())
	amount_input.release_focus()
	_player_action("raise", target)

func _all_in() -> void:
	if table.actor != 0 or _modal_open():
		return
	if table.max_total(0) > table.current_bet:
		_player_action("raise", table.max_total(0))
	else:
		_player_action("call")

func _player_action(kind: String, target: int = 0) -> void:
	if table.actor != 0 or _modal_open():
		return
	if online:
		LanRoom.request_action(kind, target)
		_play_sound(250.0 if kind == "fold" else 580.0)
	elif table.act(kind, target):
		_play_sound(250.0 if kind == "fold" else 580.0)

func _table_changed() -> void:
	if previous_hand != table.hand_number or previous_board_size != table.board.size():
		deal_progress = 0.0
		previous_hand = table.hand_number
		previous_board_size = table.board.size()
	ai_wait = 0.72 + randf() * 0.5
	var your_turn = table.actor == 0 and not table.finished and (not online or not LanRoom.action_pending)
	var raising = your_turn and table.can_raise(0)
	for button in [fold_button, call_button, raise_button, allin_button]:
		button.visible = not table.finished
		button.disabled = not your_turn
	raise_button.disabled = not raising
	allin_button.disabled = not your_turn or (table.max_total(0) > table.current_bet and not raising)
	var call_amount = mini(table.to_call(0), table.players[0].stack)
	call_button.text = ("过牌" if touch_layout else "过牌  SPACE") if call_amount == 0 else "跟注 %d" % call_amount
	if your_turn and call_amount == table.players[0].stack and call_amount > 0:
		call_button.text = "跟注全下 %d" % call_amount
	next_button.visible = table.finished
	next_button.text = "再来一局  →" if table.match_over() else "下一手  →"
	next_button.disabled = online and not LanRoom.is_host
	if next_button.disabled:
		next_button.text = "等待房主开始"
	reset_button.visible = table.finished and not table.match_over() and (not online or LanRoom.is_host)
	slider.visible = not table.finished and not touch_layout
	slider.editable = raising
	amount_input.visible = not table.finished
	amount_input.editable = raising
	if not raising and amount_input.has_focus():
		amount_input.release_focus()
	syncing_amount = true
	slider.step = 1
	slider.min_value = mini(table.current_bet + table.min_raise, table.max_total(0))
	slider.max_value = maxi(slider.min_value, table.max_total(0))
	slider.value = slider.min_value
	amount_input.text = str(int(slider.min_value))
	syncing_amount = false
	for b in quick_buttons:
		b.visible = not table.finished and not touch_layout
		b.disabled = not raising
	result_panel.visible = table.finished
	result_label.text = table.result_text
	if table.finished:
		status_label.text = "筹码已结算 · 等待房主开始下一手" if online and not LanRoom.is_host else "筹码已结算 · 点击下一手继续"
		if table.match_over():
			status_label.text = "本局结束 · %s 赢下了牌桌" % table.players.filter(func(p): return p.stack > 0)[0].name if online else ("你赢下了整张牌桌！" if table.players[0].stack > 0 else "本局结束 · 再来一局试试吧")
	elif your_turn:
		status_label.text = "轮到你了 · 选择下方操作"
	elif online and LanRoom.action_pending:
		status_label.text = "操作已发送 · 等待房主确认"
	elif online and table.players[0].hole.is_empty():
		status_label.text = "你已出局，可以继续观看牌局"
	else:
		status_label.text = "等待 %s 行动…" % table.players[table.actor].name if online else "%s 正在思考…" % table.players[table.actor].name
	queue_redraw()

func _process(delta: float) -> void:
	pulse += delta
	deal_progress = minf(1.0, deal_progress + delta * 3.0)
	if OS.has_feature("mobile"):
		var keyboard_height = DisplayServer.virtual_keyboard_get_height() if amount_input.has_focus() else 0
		position.y = MobileLayout.keyboard_shift(self, amount_input, keyboard_height)
	if touch_layout and mobile_rect != MobileLayout.safe_rect(get_viewport()):
		_layout_mobile()
	if not online and table != null and not table.finished and table.actor > 0 and not _modal_open() and not snapshot_mode:
		ai_wait -= delta
		if ai_wait <= 0:
			var choice = table.bot_action()
			table.act(choice.kind, choice.target)
			_play_sound(400.0)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F11:
		get_viewport().set_input_as_handled()
		var full = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if event.keycode == KEY_ESCAPE:
		if rules_panel.visible:
			get_viewport().set_input_as_handled()
			rules_panel.hide()
		elif amount_input.has_focus():
			get_viewport().set_input_as_handled()
			amount_input.release_focus()
		return
	if _modal_open():
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event.keycode in [KEY_SPACE, KEY_F, KEY_R]:
		get_viewport().set_input_as_handled()
	if event.keycode == KEY_SPACE:
		if table.finished:
			_next_hand()
		else:
			_player_action("call")
	elif event.keycode == KEY_F:
		_player_action("fold")
	elif event.keycode == KEY_R:
		_raise_from_input()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_node_ready():
		if rules_panel.visible:
			rules_panel.hide()
		elif amount_input.has_focus():
			amount_input.release_focus()
		else:
			_leave_game()

func _play_sound(frequency: float) -> void:
	if not sound_enabled or snapshot_mode:
		return
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var data = PackedByteArray()
	var count = 1764
	data.resize(count * 2)
	for i in range(count):
		var envelope = pow(1.0 - float(i) / count, 2.0)
		var value = int(sin(TAU * frequency * float(i) / 22050.0) * 9000 * envelope)
		data[i * 2] = value & 255
		data[i * 2 + 1] = (value >> 8) & 255
	stream.data = data
	audio_player.stream = stream
	audio_player.play()

func _text(value: String, point: Vector2, font_size: int = 18, color: Color = INK, center: bool = false, font: Font = null) -> void:
	var chosen = ui_font if font == null else font
	if center:
		point.x -= chosen.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / 2
	draw_string(chosen, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _box(rect: Rect2, color: Color, border: Color = Color.TRANSPARENT, radius: int = 12) -> void:
	draw_style_box(_style(color, border, radius), rect)

func _oval(center: Vector2, radius: Vector2, color: Color) -> void:
	var points = PackedVector2Array()
	for i in range(128):
		var angle = float(i) * TAU / 128
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, color)

func _chip(position: Vector2, color: Color, radius: float = 13.0) -> void:
	draw_circle(position + Vector2(0, 3), radius, Color("092227"))
	draw_circle(position, radius, color)
	draw_arc(position, radius - 4, 0, TAU, 32, Color("efe6ce"), 1.0, true)
	for i in range(6):
		var v = Vector2.from_angle(float(i) * TAU / 6)
		draw_line(position + v * (radius - 3), position + v * radius, Color("e6e6d8"), 3, true)

func _card(card: int, rect: Rect2, face_up: bool = true, dimmed: bool = false) -> void:
	var anim_rect = rect
	anim_rect.position.y += 15 * pow(1.0 - deal_progress, 2)
	_box(Rect2(anim_rect.position + Vector2(0, 5), anim_rect.size), Color(0, 0, 0, 0.24), Color.TRANSPARENT, 8)
	if card < 0 and face_up:
		_box(anim_rect, Color("174a47"), Color("386560"), 8)
		_text("·", anim_rect.get_center() + Vector2(0, 10), 40, Color("467771"), true)
		return
	if not face_up:
		_box(anim_rect, Color("17373f"), Color("d4bc85"), 8)
		var inner = anim_rect.grow(-6)
		_box(inner, Color("20454c"), Color("63807b"), 4)
		for row in range(3, int(rect.size.y) - 12, 12):
			for col in range(3, int(rect.size.x) - 12, 12):
				var c = inner.position + Vector2(col + 3, row + 3)
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(3, 0), c + Vector2(0, 3), c + Vector2(-3, 0)]), Color("5a7c7b"))
		_text("♠", anim_rect.get_center() + Vector2(0, 9), int(rect.size.x * 0.48), GOLD, true, symbol_font)
		return
	var background = Color("a3aaa0") if dimmed else Color("f4f0e5")
	_box(anim_rect, background, Color("fcf9f0"), 8)
	var suit = PokerRules.suit_of(card)
	var color = Color("c05250") if suit == 1 or suit == 3 else Color("1c3a3a")
	var small = rect.size.x < 70
	var font_size = 18 if small else 25
	_text(PokerRules.rank_text(card), anim_rect.position + Vector2(9, font_size + 4), font_size, color, false, card_font)
	_text(PokerRules.SUITS[suit], anim_rect.position + Vector2(11, font_size + 23), 15 if small else 19, color, false, symbol_font)
	_text(PokerRules.SUITS[suit], anim_rect.get_center() + Vector2(4, 17 if not small else 11), 38 if not small else 23, color, true, symbol_font)
	_text(PokerRules.rank_text(card), anim_rect.end - Vector2(16, 9), 13 if small else 17, color, true, card_font)

func _draw() -> void:
	if table == null:
		return
	if touch_layout:
		_draw_mobile()
		return
	draw_rect(Rect2(0, 0, 1440, 900), BG)
	for y in range(900):
		draw_line(Vector2(0, y), Vector2(1440, y), Color(0.035 + y * 0.000007, 0.085 + y * 0.000017, 0.105 + y * 0.000012))
	# Subtle architectural grid around the felt.
	for x in range(20, 1440, 52):
		draw_line(Vector2(x, 96), Vector2(x, 775), Color(0.2, 0.35, 0.35, 0.045))
	draw_line(Vector2(34, 95), Vector2(1406, 95), Color("294047"))
	_chip(Vector2(51, 49), GOLD, 17)
	_text("夜色牌局", Vector2(82, 59), 30)
	_text("T E X A S   H O L D ’ E M", Vector2(244, 56), 13, MUTED)
	_box(Rect2(464, 35, 154, 36), Color("163a3c"), Color("315354"), 18)
	_text("局域网 · %d 人桌" % table.players.size() if online else "单人练习 · 四人桌", Vector2(541, 59), 14, GREEN, true)
	_draw_felt()
	_draw_board()
	for seat in range(table.players.size()):
		_draw_seat(seat)
	_draw_sidebar()
	_draw_actions()
	_text("局域网联机 · 虚拟筹码" if online else "离线练习 · 虚拟筹码", Vector2(35, 887), 13, MUTED)
	# Right-aligned footer.
	var footer = "F11 全屏    /    空格 过牌或跟注"
	_text(footer, Vector2(1404 - ui_font.get_string_size(footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, 887), 13, MUTED)

func _draw_mobile() -> void:
	draw_rect(get_viewport().get_visible_rect(), BG)
	var r = mobile_rect
	_chip(r.position + Vector2(24, 41), GOLD, 19)
	_text("夜色牌局", r.position + Vector2(55, 51), 32)
	_text("局域网 · %d 人桌" % table.players.size() if online else "单机练习", r.position + Vector2(234, 50), 23, GREEN)
	draw_line(Vector2(r.position.x, r.position.y + 85), Vector2(r.end.x, r.position.y + 85), Color("294047"))
	draw_set_transform_matrix(board_transform)
	_draw_felt()
	_draw_board()
	for seat in range(table.players.size()):
		_draw_seat(seat)
	if show_sidebar:
		draw_set_transform_matrix(sidebar_transform)
		_draw_sidebar()
	draw_set_transform_matrix(Transform2D.IDENTITY)
	_box(actions_rect, Color("122930"), Color("30444a"), 16)
	var info = "本手结束 · 筹码已结算" if table.finished else ("轮到你 · " if table.actor == 0 else "等待对手 · ") + "需跟注 %d · 已下注 %d" % [table.to_call(0), table.players[0].street_bet]
	_text(info, actions_rect.position + Vector2(18, 35), 24, GOLD)
	if not table.finished:
		_text("加注总额", Vector2(amount_input.position.x, actions_rect.position.y + 35), 24, GOLD if table.can_raise(0) else MUTED)

func _draw_felt() -> void:
	_oval(Vector2(560, 426), Vector2(500, 258), Color(0, 0, 0, 0.22))
	_oval(Vector2(560, 410), Vector2(497, 255), Color("122a30"))
	_oval(Vector2(560, 409), Vector2(482, 241), Color("3e4840"))
	_oval(Vector2(560, 408), Vector2(477, 237), Color("ab9467"))
	_oval(Vector2(560, 407), Vector2(473, 233), Color("102e32"))
	_oval(Vector2(560, 407), Vector2(455, 216), Color("20564e"))
	_oval(Vector2(560, 398), Vector2(435, 196), Color("235d53"))
	var points = PackedVector2Array()
	for i in range(129):
		var angle = float(i) * TAU / 128
		points.append(Vector2(560, 407) + Vector2(cos(angle) * 440, sin(angle) * 201))
	draw_polyline(points, Color("6a8c6e"), 1.0, true)
	_text("N I G H T F A L L   P O K E R   C L U B", Vector2(560, 537), 11, Color("62957f"), true)

func _draw_board() -> void:
	var pot_amount = table.last_pot if table.finished else table.pot()
	if not table.finished:
		_box(Rect2(427, 279, 266, 55), Color("19413b"), Color("55826b"), 28)
		_chip(Vector2(454, 305), GOLD, 11)
		_text("底池", Vector2(477, 310), 16, Color("b2cfb8"))
		_text(str(pot_amount), Vector2(570, 313), 27, INK, true)
	for i in range(5):
		_card(table.board[i] if i < table.board.size() else -1, Rect2(313 + i * 102, 354, 88, 124))
	if table.board.is_empty():
		_text("公共牌即将发出", Vector2(560, 394), 16, Color("79a191"), true)
	for i in range(4):
		var color = GOLD if table.street == i else Color("557d71")
		draw_circle(Vector2(446 + i * 60, 342), 2.0, color)
		_text(PokerTable.STREETS[i], Vector2(469 + i * 60, 347), 13, color, true)

func _draw_seat(seat: int) -> void:
	var p = table.players[seat]
	var slot = seat
	if table.players.size() == 2 and seat == 1:
		slot = 2
	elif table.players.size() == 3 and seat == 2:
		slot = 3
	var rect = Rect2(SEATS[slot], Vector2(300, 75) if seat == 0 else Vector2(210, 80))
	if slot == 2:
		rect.size = Vector2(252, 78)
	var active = table.actor == seat
	var border = GOLD if active else (GREEN if seat in table.winning_seats and table.finished else Color("355057"))
	if active:
		_box(rect.grow(4), Color(0.8, 0.67, 0.37, 0.08 + 0.035 * sin(pulse * 3.0)), Color.TRANSPARENT, 18)
	_box(rect, Color("122b32"), border, 14)
	var avatar = rect.position + Vector2(31, 31)
	draw_circle(avatar, 18, [Color("417f6c"), Color("435c78"), Color("77597a"), Color("8b6e47")][seat])
	_text("你" if seat == 0 else p.name.left(1), avatar + Vector2(0, 7), 17, INK, true)
	var displayed_name: String = p.name
	while ui_font.get_string_size(displayed_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x > rect.size.x - 105:
		displayed_name = displayed_name.left(displayed_name.length() - 2) + "…"
	_text(displayed_name, rect.position + Vector2(61, 29), 17, MUTED if p.folded else INK)
	_text("%s 筹码" % p.stack, rect.position + Vector2(61, 53), 18, GOLD if seat == 0 else INK)
	if seat != 0:
		_text(p.action, rect.position + Vector2(15, 72), 13, GOLD if active else MUTED)
	else:
		_text(p.action, Vector2(560, 777), 13, MUTED, true)
	if seat == table.dealer:
		draw_circle(rect.position + Vector2(-15, 13), 13, Color("efe9d9"))
		_text("D", rect.position + Vector2(-15, 18), 14, Color("244540"), true, card_font)
	var reveal = seat == 0 or (table.showdown and not p.folded)
	var origin: Vector2
	var card_size: Vector2
	if seat == 0:
		origin = Vector2(460, 544)
		card_size = Vector2(92, 128)
	elif slot == 2:
		origin = Vector2(499, 196)
		card_size = Vector2(55, 77)
	else:
		origin = rect.position + Vector2(39, 94)
		card_size = Vector2(55, 77)
	for i in range(p.hole.size()):
		_card(p.hole[i], Rect2(origin + Vector2(i * (card_size.x + 12), 0), card_size), reveal, p.folded)
	if p.folded and not p.hole.is_empty():
		_box(Rect2(origin.x - 3, origin.y + card_size.y / 2 - 15, card_size.x * 2 + 18, 30), Color("182e33"), Color("40575a"), 6)
		_text("已弃牌", Vector2(origin.x + card_size.x + 6, origin.y + card_size.y / 2 + 6), 14, MUTED, true)
	var bet_positions = [Vector2(760, 591), Vector2(272, 392), Vector2(694, 229), Vector2(801, 393)]
	if p.street_bet > 0 and not table.finished:
		var pos = bet_positions[slot]
		_chip(pos, Color("ad645f"), 11)
		_text(str(p.street_bet), pos + Vector2(0, 30), 14, Color("d1deca"), true)
	if seat == table.small_blind_seat or seat == table.big_blind_seat:
		var tag = "SB" if seat == table.small_blind_seat else "BB"
		_box(Rect2(rect.end.x - 35, rect.position.y + 7, 28, 20), Color("29474a"), Color.TRANSPARENT, 5)
		_text(tag, Vector2(rect.end.x - 21, rect.position.y + 22), 11, GOLD, true)

func _draw_sidebar() -> void:
	_box(Rect2(1112, 113, 294, 653), Color("11262e"), Color("2a4048"), 18)
	_text("牌局概览", Vector2(1136, 149), 20)
	_box(Rect2(1135, 168, 246, 91), Color("173038"), Color.TRANSPARENT, 12)
	_text("当前手数", Vector2(1151, 193), 13, MUTED)
	_text("%02d" % table.hand_number, Vector2(1151, 236), 32, GOLD)
	_text("小盲 / 大盲", Vector2(1260, 193), 13, MUTED)
	_text("10 / 20", Vector2(1260, 230), 23)
	_text("你的牌力", Vector2(1136, 298), 15, MUTED)
	var hand_name = "等待公共牌"
	if table.players[0].hole.size() != 2:
		hand_name = "已出局 · 观战中"
	elif table.board.size() >= 3:
		hand_name = PokerRules.evaluate(table.players[0].hole + table.board).name
	elif table.players[0].hole.size() == 2:
		var a = table.players[0].hole[0]
		var b = table.players[0].hole[1]
		hand_name = "口袋对子" if PokerRules.rank_of(a) == PokerRules.rank_of(b) else ("同花底牌" if PokerRules.suit_of(a) == PokerRules.suit_of(b) else "非同花底牌")
	_text(hand_name, Vector2(1136, 333), 23, GREEN)
	_text("筹码变化", Vector2(1136, 365), 14, MUTED)
	var net = table.players[0].stack - PokerTable.START_STACK
	_text(("+" if net >= 0 else "") + str(net), Vector2(1365, 365), 18, GREEN if net >= 0 else Color("d68f80"), true)
	draw_line(Vector2(1136, 386), Vector2(1381, 386), Color("2c444a"))
	_text("牌桌动态", Vector2(1136, 420), 18)
	var start = maxi(0, table.history.size() - 6)
	for i in range(start, table.history.size()):
		var line: String = table.history[i]
		var color = GOLD if i == table.history.size() - 1 else MUTED
		var baseline = 452 + (i - start) * 37
		draw_circle(Vector2(1140, baseline - 5), 2, color)
		# Keep the history column inside its bounds, including side-pot names.
		var display = line
		while ui_font.get_string_size(display, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x > 231:
			display = display.left(display.length() - 2) + "…"
		_text(display, Vector2(1151, baseline), 13, color)
	_box(Rect2(1135, 685, 247, 58), Color("173038"), Color.TRANSPARENT, 10)
	_text("任意五张，组成你的最佳牌型。", Vector2(1148, 709), 13, MUTED)
	_text("沉稳下注，也给运气一点空间。", Vector2(1148, 730), 13, MUTED)

func _draw_actions() -> void:
	_box(Rect2(34, 790, 1372, 82), Color("122930"), Color("30444a"), 16)
	if table.finished:
		_text("整局结束" if table.match_over() else "本手结束", Vector2(56, 823), 18, GOLD)
		_text("赢得全部筹码即可获胜" if not table.match_over() else "点击右侧按钮重新入座", Vector2(56, 850), 14, MUTED)
		var net = table.players[0].stack - table.hand_start_stacks[0]
		var message = "你赢得了 %d 筹码" % net if net > 0 else ("你投入了 %d 筹码" % -net if net < 0 else "本手筹码持平")
		_text(message, Vector2(385, 843), 22, GREEN if net > 0 else INK)
	else:
		_text("轮到你行动" if table.actor == 0 else "等待对手行动", Vector2(56, 823), 18, GOLD if table.actor == 0 else MUTED)
		_text("需跟注 %d · 已下注 %d" % [table.to_call(0), table.players[0].street_bet], Vector2(56, 850), 13, MUTED)
		_text("加注总额" if touch_layout else "加注至", Vector2(882, 833 if touch_layout else 824), 15, GOLD if table.can_raise(0) else MUTED)

func _capture_preview() -> void:
	await get_tree().create_timer(0.55).timeout
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	var args = OS.get_cmdline_user_args()
	var path = "res://test-results/preview.png"
	for arg in args:
		if arg.begins_with("--snapshot-path="):
			path = arg.trim_prefix("--snapshot-path=")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error = image.save_png(path)
	print("Snapshot saved: ", path, " (", error, ")")
	get_tree().quit(error)
