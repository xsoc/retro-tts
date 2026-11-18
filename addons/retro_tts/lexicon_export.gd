@tool
extends EditorExportPlugin
## Adds the pronunciation dictionary and its licence to every export.

const FILES := ["res://addons/retro_tts/data/lexicon.txt", "res://addons/retro_tts/data/LICENSE-cmudict.txt"]


func _get_name() -> String:
	return "RetroTTSLexicon"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	for f in FILES:
		if FileAccess.file_exists(f):
			add_file(f, FileAccess.get_file_as_bytes(f), false)
