class_name MobileLayout
extends RefCounted

static func enabled() -> bool:
	return OS.has_feature("mobile") or "--touch-layout" in OS.get_cmdline_user_args()

static func configure(window: Window) -> void:
	if enabled():
		window.content_scale_size = Vector2i(1200, 900)
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

static func safe_rect(viewport: Viewport) -> Rect2:
	var rect = viewport.get_visible_rect()
	if OS.has_feature("android"):
		var safe = Rect2(DisplayServer.get_display_safe_area())
		safe.position -= Vector2(DisplayServer.window_get_position())
		safe = viewport.get_screen_transform().affine_inverse() * safe
		if safe.has_area() and rect.intersects(safe):
			rect = rect.intersection(safe)
	return rect.grow(-18)

static func keyboard_shift(control: Control, field: Control, keyboard_height: float) -> float:
	if keyboard_height <= 0:
		return 0
	var transform = control.get_viewport().get_screen_transform()
	var bottom = (transform * field.get_global_rect()).end.y
	# Measure from the unshifted layout, so repeated frames cannot oscillate.
	bottom -= control.position.y * transform.get_scale().y
	var visible_bottom = DisplayServer.window_get_size().y - keyboard_height - 18
	return -maxf(0, bottom - visible_bottom) / maxf(0.01, transform.get_scale().y)
