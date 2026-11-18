extends Node
## The smallest use: make a RetroTTS node in code, pick a preset, speak, and listen to the signals.
## Attach to any node in a scene and run it.


func _ready() -> void:
	var tts := RetroTTS.new()
	tts.preset = "robot"
	add_child(tts)
	tts.word_spoken.connect(func(word: String, index: int, _at: int, _len: int) -> void:
		print("word %d: %s" % [index, word]))
	tts.speech_finished.connect(func() -> void: print("done"))
	tts.speak("Greetings. I am a robot. Beep boop.")
