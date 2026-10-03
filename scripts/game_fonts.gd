class_name GameFonts
extends RefCounted

# Bundled under SIL OFL so Chinese text also renders on Android and fresh PCs.
const CJK = preload("res://assets/fonts/NotoSansSC.ttf")

static func ui() -> FontVariation:
	var font = FontVariation.new()
	font.base_font = CJK
	font.variation_opentype = {"wght": 450.0}
	return font
