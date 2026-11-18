@tool
extends EditorScript
## Bakes lines to .wav files in the editor (File > Run, or Ctrl+Shift+X with this script open), so a
## game can ship pre-rendered speech instead of rendering at runtime.

const OUT_DIR := "res://baked_speech"
const LINES := {
	"intro": "Welcome to the station.",
	"warning": "Warning. Hull breach detected.",
}


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var tts := RetroTTS.new()
	tts.voice = RetroTTSVoice.from_preset("computer")
	tts.bit_depth = 8
	for key in LINES:
		var wav := tts.render_wav(LINES[key])
		var path := "%s/%s.wav" % [OUT_DIR, key]
		wav.save_to_wav(path)
		print("Baked %s (%.1f s)" % [path, wav.get_length()])
	tts.free()
