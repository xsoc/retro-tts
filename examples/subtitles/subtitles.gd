extends Control
## Subtitle sync: a dialogue box whose text appears as the voice reaches each word.
##
## Narration is spoken by the RetroTTS node's voice; anything in "double quotes" by its quote_voice.
## Press Enter, Space or click to skip to the end of a line, then again for the next one.

const LINES := [
	"The ship drifts past the last beacon. \"Hold on to something,\" says the pilot.",
	"\"Reactor at 250 percent. Please remain calm.\" The lights flicker, then steady.",
	"Somewhere below, a door opens. Nobody is there.",
]

@onready var tts: RetroTTS = $RetroTTS
@onready var box: RichTextLabel = $Box/Text
@onready var hint: Label = $Box/Hint

var _line := -1


func _ready() -> void:
	tts.word_spoken.connect(_on_word)
	tts.speech_finished.connect(_on_finished)
	_next()


func _next() -> void:
	_line = (_line + 1) % LINES.size()
	box.text = LINES[_line]
	box.visible_characters = 0
	hint.visible = false
	tts.speak(LINES[_line])


## Reveal up to the end of the word being said.
func _on_word(_word: String, _index: int, char_start: int, char_length: int) -> void:
	box.visible_characters = char_start + char_length


func _on_finished() -> void:
	box.visible_characters = -1
	hint.visible = true


func _unhandled_input(event: InputEvent) -> void:
	var pressed := event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.is_pressed())
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if tts.is_speaking() and box.visible_characters != -1:
		# first press: show the whole line, let the voice finish
		box.visible_characters = -1
		hint.visible = true
	else:
		_next()
