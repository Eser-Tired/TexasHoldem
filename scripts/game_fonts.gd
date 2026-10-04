class_name GameFonts
extends RefCounted

# Bundled under SIL OFL so Chinese text also renders on Android and fresh PCs.
const CJK = preload("res://assets/fonts/NotoSansSC.ttf")
const MOBILE_SCALE = 1.5

static func ui() -> FontVariation:
	var font = FontVariation.new()
	font.base_font = CJK
	# Numeric OpenType tags work even on engines that ignore the "wght" alias.
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700.0} if MobileLayout.enabled() else {"wght": 450.0}
	return font

static func size(base_size: int) -> int:
	return roundi(base_size * MOBILE_SCALE) if MobileLayout.enabled() else base_size
