class_name UpdateDialog
extends Control

var panel: Panel
var heading: Label
var status: Label
var notes: RichTextLabel
var progress: ProgressBar
var actions: HBoxContainer
var primary: Button
var page: Button
var close_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var palette = Theme.new()
	palette.default_font = GameFonts.ui()
	palette.default_font_size = GameFonts.size(24) if MobileLayout.enabled() else 19
	theme = palette
	var shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	panel = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color("10292f")
	style.border_color = Color("d8ba73")
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	heading = Label.new()
	heading.text = "游戏更新 · v" + Updater.current_version
	heading.add_theme_font_size_override("font_size", GameFonts.size(30))
	heading.add_theme_color_override("font_color", Color("d8ba73"))
	column.add_child(heading)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color("e9eee7"))
	column.add_child(status)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 28
	progress.max_value = 1
	column.add_child(progress)
	notes = RichTextLabel.new()
	notes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	notes.custom_minimum_size.y = 120
	notes.bbcode_enabled = false
	notes.scroll_active = true
	notes.selection_enabled = true
	column.add_child(notes)
	actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	primary = _button("检查更新", _primary_action)
	var accent = StyleBoxFlat.new()
	accent.bg_color = Color("d8ba73")
	accent.set_corner_radius_all(10)
	primary.add_theme_stylebox_override("normal", accent)
	primary.add_theme_color_override("font_color", Color("173439"))
	page = _button("发布页面", Updater.show_release)
	close_button = _button("关闭", hide)
	Updater.changed.connect(_refresh)
	get_viewport().size_changed.connect(_layout)
	_refresh()
	_layout()
	hide()

func _button(text: String, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(180, 80 if MobileLayout.enabled() else 52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new()
	style.bg_color = Color("23434a")
	style.border_color = Color("4d686c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	button.add_theme_stylebox_override("normal", style)
	button.pressed.connect(callback)
	actions.add_child(button)
	return button

func _layout() -> void:
	if panel == null:
		return
	var safe = MobileLayout.safe_rect(get_viewport()) if MobileLayout.enabled() else get_viewport().get_visible_rect().grow(-32)
	panel.size = Vector2(minf(1000, safe.size.x - 32), minf(680, safe.size.y - 32))
	panel.position = safe.get_center() - panel.size / 2

func _refresh() -> void:
	status.text = Updater.message if not Updater.message.is_empty() else "启动时自动检查，也可以点击下方按钮手动检查。"
	var text = Updater.release.get("notes", "更新检查需要访问 GitHub，不影响局域网和单机游戏。\n\nWindows：在游戏内下载并校验 EXE，退出后替换或运行新版。\nAndroid：通过系统浏览器下载 APK，打开文件按系统提示升级。")
	if notes.text != text:
		notes.text = text
	progress.visible = Updater.state in ["downloading", "verifying"]
	progress.value = Updater.progress
	primary.disabled = Updater.state in ["checking", "verifying"]
	match Updater.state:
		"available": primary.text = "下载新版"
		"browser": primary.text = "重新打开下载"
		"downloading": primary.text = "取消下载"
		"ready": primary.text = "打开下载位置"
		"checking": primary.text = "检查中…"
		"verifying": primary.text = "校验中…"
		_: primary.text = "重新检查" if Updater.state != "idle" else "检查更新"

func _primary_action() -> void:
	match Updater.state:
		"available", "browser": Updater.download()
		"downloading": Updater.cancel_download()
		"ready": Updater.show_download()
		_: Updater.check()

func present() -> void:
	_layout()
	_refresh()
	show()
	close_button.grab_focus()
	if Updater.state == "idle":
		Updater.check()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
