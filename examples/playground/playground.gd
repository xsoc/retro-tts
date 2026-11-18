extends Control
## Retro TTS playground: pick a preset, move any slider, type a line and press PLAY.
##
## The voice sliders are built from RetroTTSVoice's exported properties, so every parameter the engine
## has is here. The subtitle box and the event log are driven by the RetroTTS signals.

## The playground's bit depth slider starts at 4 bits. The RetroTTS node itself accepts 1 to 16.
const MIN_BITS := 4

@onready var tts: RetroTTS = $RetroTTS

var _voice_controls := {}      ## property name -> [control, value label or null]
var _text: TextEdit
var _preset: OptionButton
var _subtitle: RichTextLabel
var _log: RichTextLabel
var _phonemes: Label
var _status: Label
var _play: Button


func _ready() -> void:
	# edit a copy, so the narrator.tres on disk stays as shipped
	tts.voice = (tts.voice if tts.voice else RetroTTSVoice.from_preset("narrator")).duplicate() as RetroTTSVoice
	_build_ui()
	tts.speech_started.connect(_on_speech_started)
	tts.sentence_started.connect(func(i: int, s: String) -> void: _event("sentence %d starts: %s" % [i, s]))
	tts.word_spoken.connect(_on_word_spoken)
	tts.sentence_finished.connect(func(i: int, _s: String) -> void: _event("sentence %d finished" % i))
	tts.speech_finished.connect(_on_speech_finished)
	tts.speech_stopped.connect(func() -> void: _event("[color=orange]stopped[/color]"))
	_play.grab_focus()


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1b1e2e")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := HBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	root.add_theme_constant_override("separation", 16)
	add_child(root)

	# left: every voice parameter
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 470
	root.add_child(left)
	var head := HBoxContainer.new()
	left.add_child(head)
	head.add_child(_label("Voice preset"))
	_preset = OptionButton.new()
	_preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in RetroTTSVoice.preset_ids():
		_preset.add_item("%s  (%s)" % [RetroTTSEngine.VOICES[id].name, RetroTTSEngine.VOICES[id].who])
		_preset.set_item_metadata(_preset.item_count - 1, id)
	_preset.item_selected.connect(_on_preset)
	head.add_child(_preset)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	_build_voice_sliders(grid)

	# right: line settings, text, play, subtitles, events
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
	var title := _label("RETRO TTS")
	title.add_theme_font_size_override("font_size", 28)
	right.add_child(title)

	var line_grid := GridContainer.new()
	line_grid.columns = 3
	right.add_child(line_grid)
	_node_slider(line_grid, "Bit depth", "bit_depth", MIN_BITS, RetroTTS.MAX_BIT_DEPTH, 1, "%d bits")
	_node_slider(line_grid, "Speed", "speed", 0.5, 2.5, 0.01, "%.2fx")
	_node_slider(line_grid, "Pitch", "pitch", 0.5, 2.0, 0.01, "%.2fx")
	_node_slider(line_grid, "Loudness", "loudness", -30.0, -6.0, 0.5, "%.1f LUFS")
	var checks := HBoxContainer.new()
	right.add_child(checks)
	_node_check(checks, "4-bit BRR round trip", "brr")
	_node_check(checks, "Split into sentences", "split_sentences")

	right.add_child(_label("Text (Ctrl+Enter plays). [AA1 R P AH0 B EH2 T] in brackets forces a pronunciation."))
	_text = TextEdit.new()
	_text.text = tts.text
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.custom_minimum_size.y = 110
	right.add_child(_text)

	var buttons := HBoxContainer.new()
	right.add_child(buttons)
	_play = Button.new()
	_play.text = "  PLAY  "
	_play.add_theme_font_size_override("font_size", 22)
	_play.pressed.connect(_on_play)
	buttons.add_child(_play)
	var stop := Button.new()
	stop.text = "STOP"
	stop.pressed.connect(tts.stop)
	buttons.add_child(stop)
	var show_ph := Button.new()
	show_ph.text = "Show phonemes"
	show_ph.pressed.connect(func() -> void: _phonemes.text = RetroTTS.phonemes(_text.text))
	buttons.add_child(show_ph)
	var save := Button.new()
	save.text = "Save WAV"
	save.tooltip_text = "Renders the line to user://retro_tts.wav (the window waits while it renders)."
	save.pressed.connect(_on_save)
	buttons.add_child(save)
	_status = _label("")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_status)

	_phonemes = _label("")
	_phonemes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_phonemes.add_theme_color_override("font_color", Color("8b93b8"))
	right.add_child(_phonemes)

	right.add_child(_label("Subtitles (driven by word_spoken)"))
	_subtitle = RichTextLabel.new()
	_subtitle.bbcode_enabled = true
	_subtitle.fit_content = true
	_subtitle.custom_minimum_size.y = 70
	_subtitle.add_theme_font_size_override("normal_font_size", 22)
	right.add_child(_subtitle)

	right.add_child(_label("Signals"))
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_log)


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


## One row per exported RetroTTSVoice property: a slider for ranges, a menu for enums, a box for bools.
func _build_voice_sliders(grid: GridContainer) -> void:
	for p in tts.voice.get_script().get_script_property_list():
		var usage: int = p.usage
		if usage & PROPERTY_USAGE_GROUP:
			var h := _label(str(p.name).to_upper())
			h.add_theme_color_override("font_color", Color("ff8ccc"))
			grid.add_child(h)
			grid.add_child(Control.new())
			grid.add_child(Control.new())
			continue
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (usage & PROPERTY_USAGE_EDITOR):
			continue
		var prop: String = p.name
		var type: int = p.type
		var hint: int = p.hint
		if type == TYPE_STRING:
			continue
		grid.add_child(_label(prop.capitalize()))
		if type == TYPE_BOOL:
			var cb := CheckBox.new()
			cb.toggled.connect(func(on: bool) -> void: tts.voice.set(prop, on))
			grid.add_child(cb)
			grid.add_child(Control.new())
			_voice_controls[prop] = [cb, null]
		elif hint == PROPERTY_HINT_ENUM:
			var ob := OptionButton.new()
			for item in str(p.hint_string).split(","):
				ob.add_item(item.get_slice(":", 0).capitalize())
			ob.item_selected.connect(func(i: int) -> void: tts.voice.set(prop, i))
			grid.add_child(ob)
			grid.add_child(Control.new())
			_voice_controls[prop] = [ob, null]
		elif hint == PROPERTY_HINT_RANGE:
			var r := str(p.hint_string).split(",")
			var s := HSlider.new()
			s.min_value = float(r[0])
			s.max_value = float(r[1])
			s.step = float(r[2]) if r.size() > 2 and r[2].is_valid_float() else (1.0 if type == TYPE_INT else 0.01)
			s.custom_minimum_size.x = 200
			s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var val := _label("")
			val.custom_minimum_size.x = 64
			var is_int := type == TYPE_INT
			s.value_changed.connect(func(v: float) -> void:
				tts.voice.set(prop, int(v) if is_int else v)
				val.text = _fmt(v, is_int))
			grid.add_child(s)
			grid.add_child(val)
			_voice_controls[prop] = [s, val]
	_refresh_voice()


func _fmt(v: float, is_int: bool) -> String:
	return str(int(v)) if is_int else ("%.3f" % v).rstrip("0").rstrip(".")


## Moves every voice control to the voice's current values (after a preset loads).
func _refresh_voice() -> void:
	for prop in _voice_controls:
		var c: Control = _voice_controls[prop][0]
		var v: Variant = tts.voice.get(prop)
		if c is HSlider:
			(c as HSlider).set_value_no_signal(float(v))
			var lbl: Label = _voice_controls[prop][1]
			lbl.text = _fmt(float(v), typeof(v) == TYPE_INT)
		elif c is OptionButton:
			(c as OptionButton).select(int(v))
		elif c is CheckBox:
			(c as CheckBox).set_pressed_no_signal(bool(v))


## A slider bound to a property of the RetroTTS node.
func _node_slider(grid: GridContainer, title: String, prop: String, lo: float, hi: float, step: float, fmt: String) -> void:
	grid.add_child(_label(title))
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size.x = 260
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := _label("")
	val.custom_minimum_size.x = 90
	var is_int := step >= 1.0
	s.value_changed.connect(func(v: float) -> void:
		tts.set(prop, int(v) if is_int else v)
		val.text = fmt % (int(v) if is_int else v))
	s.value = clampf(float(tts.get(prop)), lo, hi)
	val.text = fmt % (int(s.value) if is_int else s.value)
	grid.add_child(s)
	grid.add_child(val)


func _node_check(box: HBoxContainer, title: String, prop: String) -> void:
	var cb := CheckBox.new()
	cb.text = title
	cb.button_pressed = bool(tts.get(prop))
	cb.toggled.connect(func(on: bool) -> void: tts.set(prop, on))
	box.add_child(cb)


# ---------------------------------------------------------------- actions

func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and k.keycode == KEY_ENTER and k.ctrl_pressed:
		_on_play()
		get_viewport().set_input_as_handled()


func _on_preset(index: int) -> void:
	tts.voice.load_preset(str(_preset.get_item_metadata(index)))
	_refresh_voice()


func _on_play() -> void:
	_log.clear()
	_subtitle.text = ""
	_status.text = "Rendering..."
	tts.speak(_text.text)


func _on_save() -> void:
	var path := "user://retro_tts.wav"
	var wav := tts.render_wav(_text.text)
	var err := wav.save_to_wav(path)
	_status.text = ("Saved %s (%.1f s)" % [ProjectSettings.globalize_path(path), wav.get_length()]) if err == OK else "Could not save: %s" % error_string(err)


func _on_speech_started(line: String) -> void:
	_event("[color=lightgreen]speech_started[/color] (%d characters)" % line.length())


func _on_word_spoken(word: String, index: int, at: int, length: int) -> void:
	_status.text = "Speaking"
	var line := tts.get_line()
	# said so far, the word being said, and the rest dimmed
	_subtitle.text = "%s[color=#ffd75e]%s[/color][color=#5a6080]%s[/color]" % [
		_esc(line.substr(0, at)), _esc(line.substr(at, length)), _esc(line.substr(at + length))]
	_event("%.2fs  word %d: %s" % [tts.get_playback_position(), index, word])


func _on_speech_finished() -> void:
	_subtitle.text = _esc(tts.get_line())
	_status.text = "Done"
	_event("[color=lightgreen]speech_finished[/color]")


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _event(t: String) -> void:
	_log.append_text(t + "\n")
