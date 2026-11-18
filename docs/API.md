# API reference

Three classes, all registered with `class_name` so you can use them anywhere once the addon is in your
project:

| Class | Kind | What it is |
|---|---|---|
| [`RetroTTS`](#retrotts) | `Node` | Speaks lines, plays them, emits word and sentence signals. |
| [`RetroTTSVoice`](#retrottsvoice) | `Resource` | One voice: every synthesiser parameter. |
| [`RetroTTSEngine`](#retrottsengine) | `RefCounted` (static) | The synthesiser. Text in, samples and word timings out. |

---

## RetroTTS

`extends Node`. Speaks text through an `AudioStreamGenerator`. Each sentence renders on the
`WorkerThreadPool` while the one before it plays.

### Signals

| Signal | When |
|---|---|
| `speech_started(text: String)` | `speak()` has queued a line. Audio starts a moment later, once the first sentence renders. |
| `sentence_started(index: int, sentence: String)` | A sentence (or quoted piece) starts to be heard. `index` counts from 0 within the line. |
| `word_spoken(word: String, index: int, char_start: int, char_length: int)` | A word starts to be heard. `word` is the text as written ("250", not "two hundred and fifty"). `index` counts words from 0 within the line. `char_start` and `char_length` place the word in the string given to `speak()`, so `char_start + char_length` is how many characters a subtitle should show. |
| `sentence_finished(index: int, sentence: String)` | A sentence has been heard to its end. Its echo may still ring on. |
| `speech_finished()` | The whole line has been heard, echo included. |
| `speech_stopped()` | The line was cut short by `stop()` or by a new `speak()`. |

All signals are emitted on the main thread, from `_process`, timed to what the audio device has played.
A handler may call `speak()` or `stop()`; the remaining events of the old line are then dropped.

When a whole frame's worth of events fall due at once they are emitted in order (sentence start, its
words, sentence end). At the end of a line any events not yet emitted are flushed before
`speech_finished`, so every word of a finished line is always reported.

### Properties

| Property | Type | Default | Description |
|---|---|---|---|
| `text` | `String` | `""` | What `speak()` says when called with no argument, and what `autoplay` says. |
| `voice` | `RetroTTSVoice` | `null` | The voice. Empty: `preset` is used. |
| `preset` | `String` (enum) | `"narrator"` | A built-in voice id, used when `voice` is empty. |
| `quote_voice` | `RetroTTSVoice` | `null` | If set, text inside "double quotes" (straight or curly) is spoken in this voice, the rest in `voice`. |
| `speed` | `float` 0.25..4 | `1.0` | Speaking speed, multiplied with the voice's own `speed`. |
| `pitch` | `float` 0.25..4 | `1.0` | Pitch multiplier, on top of the voice's `pitch_hz`. |
| `bit_depth` | `int` 1..16 | `16` | Output resolution. 16 is the engine's native resolution (no change). 2..15: 2^bits signed levels. 1: an on/off speaker, with near-silence kept silent. |
| `brr` | `bool` | `true` | Round-trip through 4-bit BRR, the ADPCM sample format of 16-bit era consoles. Off: cleaner. |
| `loudness` | `float` -30..-6 | `-16.0` | Loudness target in LUFS for every line. Peaks are soft-limited under -1 dBFS. |
| `split_sentences` | `bool` | `true` | Cut lines at `. ! ? …` and line breaks so playback starts after the first sentence. Off: the whole line renders first. |
| `autoplay` | `bool` | `false` | Speak `text` in `_ready()`. |
| `use_threads` | `bool` | `true` | Render on worker threads. Off (or on a web export without threads): render on the main thread, one sentence per frame. Read in `_ready()`. |
| `output` | `Node` | `null` | An `AudioStreamPlayer`, `AudioStreamPlayer2D` or `AudioStreamPlayer3D` to play through. Its `stream` is replaced with the node's generator. Empty: an internal `AudioStreamPlayer` is created. Read in `_ready()`. |
| `bus` | `StringName` | `&"Master"` | The internal player's audio bus. |
| `volume_db` | `float` | `0.0` | The internal player's volume. |

Changes to `voice`, `speed`, `pitch`, `bit_depth`, `brr` and `loudness` apply from the next `speak()`.

### Constants

| Constant | Value | |
|---|---|---|
| `MIX_RATE` | `32000` | The output sample rate. |
| `MAX_BIT_DEPTH` | `16` | The engine's native bit depth. |

### Methods

| Method | Description |
|---|---|
| `speak(line := "") -> void` | Speaks `line`, or `text` if `line` is empty. Stops whatever was playing first (emitting `speech_stopped` if a line was active). |
| `stop() -> void` | Stops now. Emits `speech_stopped` if a line was active. |
| `is_speaking() -> bool` | True from `speak()` until `speech_finished` or `stop()`. |
| `get_playback_position() -> float` | Seconds of the current line heard so far, or -1 before its first sound. |
| `get_words() -> Array` | The current line's words rendered so far: `[{word, index, char_start, char_length, time}]`, `time` in seconds from the start of the line. |
| `get_line() -> String` | The line being spoken. |
| `get_effective_voice() -> RetroTTSVoice` | `voice`, or a new voice from `preset` when `voice` is empty. |
| `render(line := "") -> Dictionary` | Renders a whole line now, on the calling thread, with the node's settings. Returns `{pcm: PackedFloat32Array (mono), rate: int, duration: float, words: Array}`. Blocks: call it from a thread or at load time. The node does not need to be in the tree. |
| `render_wav(line := "") -> AudioStreamWAV` | Like `render()`, as a 16-bit mono `AudioStreamWAV` you can play or `save_to_wav()`. |
| `static to_wav(pcm: PackedFloat32Array) -> AudioStreamWAV` | Mono samples at `MIX_RATE` into a 16-bit `AudioStreamWAV`. |
| `static phonemes(line: String) -> String` | The phonemes the engine will use: `"the ship"` gives `"DH AX \| SH IH1 P"`. Loads the dictionary on first use (slow once). |
| `static add_word(word: String, arpabet: String) -> void` | Teaches every RetroTTS node a pronunciation: `add_word("zorgath", "Z AO1 R G AE0 TH")`. |
| `static split(line: String, sentences := true, quotes := false) -> Array` | How a line is cut into pieces: `[{text, at, quoted}]`. |

### Inline pronunciation

Anywhere in a line, `[PHONEMES]` in square brackets is spoken exactly as written, in
[ARPAbet](https://en.wikipedia.org/wiki/ARPABET) with CMU stress digits on the vowels (1 primary,
2 secondary, 0 none): `"Welcome to [K EH1 L AH0 S]."`. The brackets count as one word in `word_spoken`.

### Numbers

Digits are read aloud: `250` is "two hundred and fifty", `3.5` is "three point five", `40%` is "forty
percent", ` -5` is "minus five". `word_spoken` reports the digits once, as written.

---

## RetroTTSVoice

`extends Resource`. One voice. The defaults are the Narrator preset. Every property is exported, grouped
in the inspector as below. See [VOICES.md](VOICES.md) for what each one does to the sound.

| Group | Properties |
|---|---|
| (top) | `display_name` |
| Pitch | `pitch_hz`, `pitch_range`, `monotone`, `flutter`, `vibrato_rate`, `vibrato_depth` |
| Timing | `speed` |
| Throat | `formant_scale`, `bandwidth_scale`, `tilt`, `open_quotient`, `breath`, `source` (`Source` enum), `pulse_duty`, `whisper` |
| Roughness | `jitter`, `shimmer`, `subharmonic` |
| Recording | `sample_rate` |
| Effects | `drive`, `radio`, `radio_low`, `radio_high`, `voice_bits`, `tremolo_rate`, `tremolo_depth`, `double_ms`, `double_mix`, `ring_hz`, `ring_mix`, `comb_ms`, `comb_feedback`, `clicks` |
| Echo | `echo_delay`, `echo_feedback`, `echo_volume`, `echo_filter` (`EchoFilter` enum) |

### Enums

- `Source { GLOTTAL, SAW, PULSE, TRIANGLE }`: the sound source. `GLOTTAL` is a natural voice; the others are
  chip-style buzz.
- `EchoFilter { FLAT, SOFT, DARK }`: the echo unit's 8-tap filter.

### Methods

| Method | Description |
|---|---|
| `static preset_ids() -> PackedStringArray` | The built-in preset ids. |
| `static from_preset(id: String) -> RetroTTSVoice` | A new voice from a preset. Unknown ids give the narrator. |
| `load_preset(id: String) -> void` | Sets every property from a preset. Emits `changed`. |
| `from_dict(d: Dictionary) -> void` | Sets every property from an engine voice dictionary. Emits `changed`. |
| `to_dict() -> Dictionary` | The voice as an engine dictionary, for `RetroTTSEngine.say()`. |

The same presets ship as files in `addons/retro_tts/voices/*.tres`.

---

## RetroTTSEngine

`extends RefCounted`, all static. The synthesiser behind `RetroTTS`. Use it directly for offline
rendering or your own playback. Every function is safe to call from worker threads.

| Member | Description |
|---|---|
| `const RATE := 32000` | Output sample rate. |
| `const SR := 16000` | Internal synthesis rate. |
| `const MAX_BITS := 16` | Native bit depth. |
| `const VOICES: Dictionary` | The presets as engine dictionaries: `{id: {name, who, f0, range, rate, formant, ...}}`. |
| `static say(text: String, voice: Variant, opts := {}) -> Dictionary` | Renders text in a voice (a preset id or a voice dictionary from `RetroTTSVoice.to_dict()`). `opts`: `rate`, `pitch` (multipliers), `seed` (int, default: a hash of the text, so the same line always sounds the same), `hz` (recording rate override), `brr` (bool), `lufs` (float), `bits` (1..16). Returns `{pcm: PackedFloat32Array (mono, 32 kHz), rate, duration, words: [{text, at, len, start, end}]}` with times in seconds. |
| `static prepare() -> void` | Loads the dictionary (about 125,000 words). Called automatically; call it early on a thread to avoid a pause. |
| `static is_prepared() -> bool` | True once the dictionary has loaded. |
| `static add_word(word, arpabet)`, `remove_word(word)`, `add_words(dict)` | Custom pronunciations, checked before the dictionary. |
| `static phonemize(text: String) -> String` | Phonemes for display. |
| `static lookup(word: String) -> Array` | Phonemes for one word: `[[phoneme, stress], ...]`. |
| `static crush(pcm: PackedFloat32Array, bits: int) -> void` | The bit depth stage, in place. |
| `static load_lexicon(text: String) -> int` | Replaces the dictionary with your own (same format as `data/lexicon.txt`). Returns the word count. |

### Pipeline

1. **Text**: tokens (words, numbers, punctuation, `[PHONEMES]`).
2. **Pronunciation**: custom words, then the dictionary, then possessives and compounds, then spelling rules.
3. **Prosody**: phoneme durations (Klatt-style rules), phrase breaks at punctuation, a pitch contour with
   accents on stressed syllables and a fall, rise or continuation at each phrase end.
4. **Synthesis** at 16 kHz: glottal, saw, pulse or triangle source; nasal pole/zero; five cascade formants;
   six parallel frication filters.
5. **Character effects**: chorus, tremolo, ring modulation, comb filter, drive, radio band, voice bit crush,
   clicks.
6. **Console voice chain**: resample to the voice's `sample_rate`, 4-bit BRR round trip, Gaussian
   interpolation up to 32 kHz, echo (delay line, 8-tap FIR, feedback).
7. **Mastering**: loudness to the target (BS.1770), soft limiting, output bit depth.
