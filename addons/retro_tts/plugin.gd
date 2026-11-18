@tool
extends EditorPlugin
## Retro TTS editor plugin. The RetroTTS node and RetroTTSVoice resource register themselves through
## class_name, so all this adds is an export step that ships the pronunciation dictionary
## (data/lexicon.txt is not a Godot resource, so exports would otherwise leave it out).

const LexiconExport := preload("res://addons/retro_tts/lexicon_export.gd")

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = LexiconExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	if _export:
		remove_export_plugin(_export)
		_export = null
