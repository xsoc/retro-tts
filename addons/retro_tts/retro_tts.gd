@icon("res://addons/retro_tts/icons/retro_tts.svg")
class_name RetroTTS
extends Node
## Speaks text aloud in procedural 16-bit era voices, and tells you as each word is heard.
##
## Add a RetroTTS node, pick a voice, then:
##
##   $RetroTTS.speak("Hold on to something.")
##   $RetroTTS.word_spoken.connect(func(word, index, at, length): print(word))
##
## A line is cut into sentences. Each sentence renders on a worker thread while the one before it plays,
## so long lines start quickly. The audio plays through an internal AudioStreamPlayer, or through the
## AudioStreamPlayer, AudioStreamPlayer2D or AudioStreamPlayer3D you set as `output`.
##
## The signals follow what the listener hears, not the renderer: word_spoken fires when the word starts
## coming out of the speakers, which is what you want for subtitles and lip flaps.

## A new line has been queued with speak(). Audio starts a moment later.
signal speech_started(text: String)
## A sentence (or quoted piece) starts to be heard. index counts from 0 within the line.
signal sentence_started(index: int, sentence: String)
## A word starts to be heard. word is the text as written ("250", not "two hundred and fifty"); index counts
## words from 0 within the line; char_start and char_length place it in the text given to speak().
signal word_spoken(word: String, index: int, char_start: int, char_length: int)
## A sentence has been heard to its end (its echo may still ring on).
signal sentence_finished(index: int, sentence: String)
## The whole line has been heard, echo included.
signal speech_finished()
## The line was cut short by stop() or by a new speak().
signal speech_stopped()

## The output sample rate.
const MIX_RATE := RetroTTSEngine.RATE
## The engine's native bit depth: BRR decodes to 16-bit samples.
const MAX_BIT_DEPTH := RetroTTSEngine.MAX_BITS

## The text speak() says when it is called with no argument (and what autoplay says).
@export_multiline var text := ""
## The voice. Leave it empty to use `preset`.
@export var voice: RetroTTSVoice
## The built-in voice used when `voice` is empty.
@export_enum("narrator", "hero", "computer", "warm", "bright", "steady", "fast_talker", "breathy", "brute",
	"insect", "robot", "ghost", "hive", "choir", "gruff", "radio", "dispatch") var preset := "narrator"
## If set, text inside "double quotes" is spoken in this voice and the rest in `voice`: one line can hold
## a narrator and a character.
@export var quote_voice: RetroTTSVoice
## Speaking speed, on top of the voice's own speed.
@export_range(0.25, 4.0, 0.01) var speed := 1.0
## Pitch multiplier, on top of the voice's own pitch.
@export_range(0.25, 4.0, 0.01) var pitch := 1.0
## Output resolution in bits. 16 is the engine's full resolution; 8 is a crunchy 8-bit DAC, 4 is very
## lo-fi and 1 is an on/off beeper speaker.
@export_range(1, 16, 1, "suffix:bits") var bit_depth := 16
## Round-trip the voice through 4-bit BRR (the ADPCM sample format of 16-bit era consoles). Turn it off
## for a cleaner sound.
@export var brr := true
## Loudness target for every line.
@export_range(-30.0, -6.0, 0.5, "suffix:LUFS") var loudness := -16.0
## Cut lines into sentences, so playback starts after the first sentence renders. Off: the whole line
## renders before any of it plays.
@export var split_sentences := true
## Speak `text` when the node is ready.
@export var autoplay := false
## Render on WorkerThreadPool threads. Off, or on a web export without threads, rendering runs on the
## main thread one sentence per frame (expect hitches).
@export var use_threads := true

@export_group("Output")
## An AudioStreamPlayer, AudioStreamPlayer2D or AudioStreamPlayer3D to play through (for positional
## speech). Empty: an internal AudioStreamPlayer is used, with the bus and volume below.
@export var output: Node
## The audio bus of the internal player.
@export var bus: StringName = &"Master":
	set(value):
		bus = value
		if _player and _owns_player:
			_player.set("bus", value)
## The volume of the internal player.
@export_range(-80.0, 24.0, 0.1, "suffix:dB") var volume_db := 0.0:
	set(value):
		volume_db = value
		if _player and _owns_player:
			_player.set("volume_db", value)

var _player: Node
var _owns_player := false
var _playback: AudioStreamGeneratorPlayback
var _cap := 0
var _threaded := true
var _gen := 0                  ## the current line; bumped by speak() and stop()
var _tasks: Array = []         ## [{task, job}] running on the WorkerThreadPool (waited on as they finish)
var _queue: Array = []         ## jobs waiting to render on the main thread (no threads)
var _prep_task := -1
var _ready_jobs := {}          ## piece index -> rendered job, waiting its turn
var _next_piece := 0
var _piece_count := 0
var _line := ""
var _active := false
var _pcm := PackedFloat32Array()
var _pushed := 0               ## samples handed to the generator
var _next_at := 0              ## where the next piece starts in _pcm
var _started := false
var _pushed_any := false
var _events: Array = []        ## [time, kind, ...] in the order they are heard
var _event_at := 0
var _words: Array = []
var _sentences := 0


func _ready() -> void:
	_threaded = use_threads and (not OS.has_feature("web") or OS.has_feature("threads"))
	_setup_output()
	if _threaded and not RetroTTSEngine.is_prepared():
		# load the 125k-word lexicon in the background so the first line starts sooner
		_prep_task = WorkerThreadPool.add_task(func() -> void: RetroTTSEngine.prepare(), false, "RetroTTS lexicon")
	if autoplay and text.strip_edges() != "":
		speak()


func _exit_tree() -> void:
	stop()
	_wait_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_wait_all()


# ---------------------------------------------------------------- public API

## Speaks a line (or `text` when called with none). Cuts off whatever was playing.
func speak(line := "") -> void:
	if line == "":
		line = text
	stop()
	if line.strip_edges() == "":
		return
	_ensure_playing()
	var vd: Dictionary = get_effective_voice().to_dict()
	var qd: Dictionary = quote_voice.to_dict() if quote_voice else {}
	var opts := {"rate": speed, "pitch": pitch, "bits": bit_depth, "brr": brr, "lufs": loudness}
	var pieces := split(line, split_sentences, quote_voice != null)
	_line = line
	_active = true
	_piece_count = pieces.size()
	for i in pieces.size():
		var p: Dictionary = pieces[i]
		var job := {"gen": _gen, "index": i, "text": p.text, "at": p.at, "opts": opts.duplicate(),
			"voice": qd if p.quoted and quote_voice else vd, "result": {}}
		if _threaded:
			var id := WorkerThreadPool.add_task(_render.bind(job), false, "RetroTTS line")
			_tasks.append({"task": id, "job": job})
		else:
			_queue.append(job)
	speech_started.emit(line)


## Stops the line now. Emits speech_stopped if something was playing.
func stop() -> void:
	var was := _active
	_gen += 1
	_queue.clear()
	_ready_jobs.clear()
	_next_piece = 0
	_piece_count = 0
	_active = false
	_pcm = PackedFloat32Array()
	_pushed = 0
	_next_at = 0
	_started = false
	_events = []
	_event_at = 0
	_words = []
	_sentences = 0
	if _player and _pushed_any:
		# restart the stream to drop what's queued (a generator's buffer can't be cleared while it plays)
		_player.call("stop")
		_player.call("play")
		_playback = _player.call("get_stream_playback")
		_pushed_any = false
	if was:
		speech_stopped.emit()


## True from speak() until the line has been heard to its end (or stopped).
func is_speaking() -> bool:
	return _active


## Seconds of the current line heard so far; -1 before its first sound.
func get_playback_position() -> float:
	if not _started or _playback == null:
		return -1.0
	var queued := _cap - _playback.get_frames_available()
	return maxf(0.0, float(_pushed - queued) / MIX_RATE)


## The words of the current line rendered so far: [{word, index, char_start, char_length, time}], time in
## seconds from the start of the line. Words of sentences still rendering are added as they arrive.
func get_words() -> Array:
	return _words


## The line being spoken.
func get_line() -> String:
	return _line


## The voice speak() would use now, as a resource (the preset when `voice` is empty).
func get_effective_voice() -> RetroTTSVoice:
	return voice if voice else RetroTTSVoice.from_preset(preset)


## Renders a whole line right now, on this thread, with the node's settings: {pcm (mono
## PackedFloat32Array), rate, duration, words [{word, index, char_start, char_length, time}]}.
## Blocks for as long as rendering takes: call it from a thread, or at load time.
func render(line := "") -> Dictionary:
	if line == "":
		line = text
	var vd: Dictionary = get_effective_voice().to_dict()
	var qd: Dictionary = quote_voice.to_dict() if quote_voice else {}
	var opts := {"rate": speed, "pitch": pitch, "bits": bit_depth, "brr": brr, "lufs": loudness}
	var out := PackedFloat32Array()
	var words := []
	var next_at := 0
	for p in split(line, split_sentences, quote_voice != null):
		var job := {"text": p.text, "at": p.at, "opts": opts, "voice": qd if p.quoted and quote_voice else vd, "result": {}}
		_render(job)
		var pcm: PackedFloat32Array = job.result.pcm
		if out.size() < next_at + pcm.size():
			out.resize(next_at + pcm.size())
		for i in pcm.size():
			out[next_at + i] += pcm[i]
		for w in job.result.words:
			if w.len > 0:
				words.append({"word": line.substr(p.at + w.at, w.len), "index": words.size(), "char_start": p.at + w.at,
					"char_length": w.len, "time": float(next_at) / MIX_RATE + w.start})
		next_at += pcm.size() - int(job.result.tail)
	return {"pcm": out, "rate": MIX_RATE, "duration": out.size() / float(MIX_RATE), "words": words}


## Renders a line into an AudioStreamWAV (16-bit mono, 32 kHz) you can play anywhere or save with
## save_to_wav(). Blocks like render().
func render_wav(line := "") -> AudioStreamWAV:
	return to_wav(render(line).pcm)


## Mono float samples (-1..1) at MIX_RATE into a 16-bit AudioStreamWAV.
static func to_wav(pcm: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(pcm.size() * 2)
	for i in pcm.size():
		bytes.encode_s16(i * 2, int(roundf(clampf(pcm[i], -1.0, 1.0) * 32767.0)))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = bytes
	return w


## The phonemes the engine will use for some text, for checking pronunciations:
## "the ship" -> "DH AX | SH IH1 P". Loads the lexicon on first use (slow once).
static func phonemes(line: String) -> String:
	return RetroTTSEngine.phonemize(line)


## Teaches every RetroTTS node a pronunciation: add_word("gorrak", "G AO1 R AE0 K") (ARPAbet, stress
## digits on vowels). You can also write [G AO1 R AE0 K] inline in any line.
static func add_word(word: String, arpabet: String) -> void:
	RetroTTSEngine.add_word(word, arpabet)


## Cuts a line into pieces: [{text, at (its place in the line), quoted}]. sentences: split at . ! ? and
## line breaks. quotes: split at "double quotes" and mark the quoted pieces.
static func split(line: String, sentences := true, quotes := false) -> Array:
	var out := []
	var runs := []
	if quotes:
		var i := 0
		var inside := false
		while i < line.length():
			var j := i
			while j < line.length() and not (line[j] == "\"" or line[j] == "“" or line[j] == "”"):
				j += 1
			runs.append([i, line.substr(i, j - i), inside])
			inside = not inside
			i = j + 1
	else:
		runs.append([0, line, false])
	for r in runs:
		var at: int = r[0]
		var s: String = r[1]
		var start := 0
		var k := 0
		while sentences and k < s.length():
			var c := s[k]
			if c in [".", "!", "?", "…", "\n"]:
				# take the whole run of closing marks
				var e := k + 1
				while e < s.length() and s[e] in [".", "!", "?", "…"]:
					e += 1
				_piece(out, s.substr(start, e - start), at + start, r[2])
				start = e
				k = e
			else:
				k += 1
		_piece(out, s.substr(start), at + start, r[2])
	return out


static func _piece(out: Array, s: String, at: int, quoted: bool) -> void:
	var lead := s.length() - s.strip_edges(true, false).length()
	var t := s.strip_edges()
	for c in t:
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9"):
			out.append({"text": t, "at": at + lead, "quoted": quoted})
			return


# ---------------------------------------------------------------- playback

func _setup_output() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.25
	if output is AudioStreamPlayer or output is AudioStreamPlayer2D or output is AudioStreamPlayer3D:
		_player = output
		_owns_player = false
	else:
		if output:
			push_warning("RetroTTS: output must be an AudioStreamPlayer, AudioStreamPlayer2D or AudioStreamPlayer3D; using an internal player.")
		var p := AudioStreamPlayer.new()
		p.name = "Voice"
		p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else &"Master"
		p.volume_db = volume_db
		add_child(p, false, Node.INTERNAL_MODE_FRONT)
		_player = p
		_owns_player = true
	_player.set("stream", gen)
	# web exports play sounds as samples by default; a generator can only stream
	_player.set("playback_type", AudioServer.PLAYBACK_TYPE_STREAM)


func _ensure_playing() -> void:
	if _player == null or not _player.is_inside_tree():
		return
	if not bool(_player.get("playing")) or _playback == null:
		_player.call("play")
		_playback = _player.call("get_stream_playback")
		_cap = _playback.get_frames_available()
		_pushed_any = false


func _process(_delta: float) -> void:
	_collect()
	if not _active:
		return
	while _ready_jobs.has(_next_piece):
		_add(_ready_jobs[_next_piece])
		_ready_jobs.erase(_next_piece)
		_next_piece += 1
	_pump()
	_emit_events()


## Picks up finished renders (and renders one piece here when there are no threads).
func _collect() -> void:
	if _prep_task >= 0 and WorkerThreadPool.is_task_completed(_prep_task):
		WorkerThreadPool.wait_for_task_completion(_prep_task)
		_prep_task = -1
	var i := 0
	while i < _tasks.size():
		var t: Dictionary = _tasks[i]
		if WorkerThreadPool.is_task_completed(t.task):
			WorkerThreadPool.wait_for_task_completion(t.task)
			_tasks.remove_at(i)
			if t.job.gen == _gen:
				_ready_jobs[t.job.index] = t.job
		else:
			i += 1
	if not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		_render(job)
		if job.gen == _gen:
			_ready_jobs[job.index] = job


func _wait_all() -> void:
	if _prep_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_prep_task)
		_prep_task = -1
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t.task)
	_tasks.clear()


## Renders one piece (any thread). Touches only the job.
func _render(job: Dictionary) -> void:
	var r := RetroTTSEngine.say(job.text, job.voice, job.opts)
	var echo: Dictionary = job.voice.get("echo", {})
	var tail := 0
	if float(echo.get("vol", 0.0)) > 0.0:
		tail = int(float(echo.get("delay", 1)) * 512 * (1 + 6 * float(echo.get("fb", 0.0))))
	var pcm: PackedFloat32Array = r.pcm
	r["tail"] = mini(tail, pcm.size())
	job.result.merge(r, true)


## Lays a rendered piece into the line, over the echo tail of the one before, and schedules its events.
func _add(job: Dictionary) -> void:
	var r: Dictionary = job.result
	var pcm: PackedFloat32Array = r.pcm
	var at := maxi(_next_at, _pushed)
	if _pcm.size() < at + pcm.size():
		_pcm.resize(at + pcm.size())
	for i in pcm.size():
		_pcm[at + i] += pcm[i]
	var t0 := float(at) / MIX_RATE
	var t1 := float(at + pcm.size() - int(r.tail)) / MIX_RATE
	var idx: int = job.index
	var sentence: String = job.text
	_events.append([t0, "start", idx, sentence])
	for w in r.words:
		if w.len <= 0:
			continue   # the extra words of a spelled-out number ("two hundred AND FIFTY")
		var c0: int = job.at + w.at
		var info := {"word": _line.substr(c0, w.len), "index": _words.size(), "char_start": c0, "char_length": w.len,
			"time": t0 + w.start}
		_words.append(info)
		_events.append([info.time, "word", info])
	_events.append([t1, "end", idx, sentence])
	_next_at = at + pcm.size() - int(r.tail)
	_started = true


func _pump() -> void:
	if _playback == null:
		return
	var n := mini(_playback.get_frames_available(), _pcm.size() - _pushed)
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	for i in n:
		var v := _pcm[_pushed + i]
		buf[i] = Vector2(v, v)
	_playback.push_buffer(buf)
	_pushed += n
	_pushed_any = true


func _emit_events() -> void:
	var t := get_playback_position()
	if t < 0.0:
		return
	var gen := _gen
	var done := _next_piece >= _piece_count and _pushed >= _pcm.size() and t >= float(_pcm.size()) / MIX_RATE - 0.05
	while _event_at < _events.size() and (done or float(_events[_event_at][0]) <= t):
		var e: Array = _events[_event_at]
		_event_at += 1
		match e[1]:
			"start":
				sentence_started.emit(e[2], e[3])
			"word":
				var w: Dictionary = e[2]
				word_spoken.emit(w.word, w.index, w.char_start, w.char_length)
			"end":
				sentence_finished.emit(e[2], e[3])
		if gen != _gen:
			return     # a handler started a new line or stopped this one
	if done:
		_active = false
		speech_finished.emit()
