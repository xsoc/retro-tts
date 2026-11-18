extends Node
## Building a voice in code: start from a preset, change it, crush it to 6 bits, and teach the engine a
## made-up word. Attach to any node in a scene and run it.


func _ready() -> void:
	var tts := RetroTTS.new()
	add_child(tts)
	var v := RetroTTSVoice.from_preset("gruff")
	v.pitch_hz = 70.0          # deeper
	v.speed = 0.85             # slower
	v.drive = 0.4              # more grit
	v.echo_volume = 0.35       # bigger room
	v.echo_filter = RetroTTSVoice.EchoFilter.DARK
	tts.voice = v
	tts.bit_depth = 6          # crunchy 6-bit output

	# names the dictionary doesn't know: teach them once, for every RetroTTS node
	RetroTTS.add_word("zorgath", "Z AO1 R G AE0 TH")
	print(RetroTTS.phonemes("Zorgath awakens"))   # Z AO1 R G AE TH | AH W EY1 K AH N Z

	# or spell one word out inline, in square brackets
	tts.speak("Zorgath awakens. Bow before [K R IY1 L AH0 K S]!")
