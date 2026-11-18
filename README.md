# Retro TTS

Procedural text-to-speech for Godot 4.7 that sounds like a 16-bit console game: a formant synthesiser
fed through a console-style voice chain (low "recorded" sample rates, 4-bit BRR compression, Gaussian
interpolation, an 8-tap echo unit), with an output bit depth you can turn all the way down to 1 bit.

It is pure GDScript (no GDExtension, no native libraries), so it runs on every platform Godot exports to.

- **A `RetroTTS` node**: drop it in a scene, set a voice, call `speak("Hello")`.
- **17 voices** as `RetroTTSVoice` resources, from a calm narrator to a robot, a hive mind and a crackly radio,
  each with about 40 parameters you can edit in the inspector.
- **Bit depth** from 16 (the engine's native resolution) down to 8, 4, or a 1-bit beeper.
- **Signals for subtitle sync**: `word_spoken(word, index, char_start, char_length)`,
  `sentence_started`, `sentence_finished`, `speech_started`, `speech_finished`, `speech_stopped`. They fire
  when the listener hears the word, not when it renders.
- **Two voices in one line**: narration in one voice, "quoted speech" in another.
- **Background rendering** on the WorkerThreadPool, a sentence at a time, so long lines start quickly.
- **Bake to WAV** in the editor or at runtime with `render_wav()`.
- English pronunciation from a 125,000-word dictionary, with spelling rules for unknown words, numbers
  read aloud, and inline phoneme overrides like `[Z AO1 R G AE0 TH]`.

## Quick start

1. Copy `addons/retro_tts/` into your project's `addons/` folder.
2. **Project > Project Settings > Plugins**: enable **Retro TTS**. (This makes exports include the
   pronunciation dictionary.)
3. Add a **RetroTTS** node to a scene, and in the inspector drag `addons/retro_tts/voices/narrator.tres` onto
   **Voice** (or just leave Voice empty and pick a **Preset**).
4. Speak:

```gdscript
@onready var tts: RetroTTS = $RetroTTS

func _ready() -> void:
	tts.word_spoken.connect(func(word, index, char_start, char_length): print(word))
	tts.speak("Hold on to something.")
```

## Try the sample project

Open this repository's folder in Godot 4.7 and press **Play**. The playground scene
(`examples/playground/playground.tscn`) has a slider for every voice parameter, the bit depth slider,
a text box and a **PLAY** button, with live subtitles and a log of every signal. There is also
`examples/subtitles/subtitles.tscn`, a dialogue box that reveals its text as the voice speaks.

## Documentation

- [Tutorial](docs/TUTORIAL.md): step by step, from an empty scene to synced subtitles, custom voices,
  positional speech and baked WAVs.
- [API reference](docs/API.md): every property, method and signal of `RetroTTS`, `RetroTTSVoice` and
  `RetroTTSEngine`.
- [Voices](docs/VOICES.md): the 17 presets and what each voice parameter does.
- Sample code: [`examples/snippets/`](examples/snippets/).

## Bit depth

`RetroTTS.bit_depth` goes from **1 to 16**. 16 is the engine's native resolution (the BRR stage decodes to
16-bit samples), so it leaves the sound untouched. Lower values quantise the final output like a cheaper
DAC: 8 bits is a classic crunch, 4 bits is very lo-fi, and 1 bit is an on/off beeper speaker (near-silence
is kept silent so pauses stay quiet). The playground's slider spans 4 to 16, a useful range for speech;
set 1 to 3 from code or the inspector if you want to go further.

There is also `RetroTTSVoice.voice_bits`, which crushes the voice itself before it is "recorded" (the
Computer preset uses 8), and `RetroTTSVoice.sample_rate`, which lowers the recording rate for a muffled,
aliased sound.

## Performance

All the DSP runs in GDScript, sample by sample, so rendering costs real CPU time: a sentence takes a
noticeable fraction of a second on a desktop and longer on phones and the web. RetroTTS renders each
sentence on a worker thread while the previous one plays, so in practice a line starts after its first
sentence is ready. For lines you know ahead of time, bake them to WAV (see the tutorial).

Web exports need a threads-enabled build for background rendering. Without threads (or with
`use_threads` off), RetroTTS renders on the main thread, one sentence per frame, which will hitch.

## Requirements

- Godot 4.7.x (GDScript only; no GDExtension).
- English text. The dictionary and spelling rules are English; other languages will be read with
  English rules.

## Licence

The pronunciation dictionary (`addons/retro_tts/data/lexicon.txt`) is derived from the
[CMU Pronouncing Dictionary](http://www.speech.cs.cmu.edu/cgi-bin/cmudict) and keeps its BSD licence
(`addons/retro_tts/data/LICENSE-cmudict.txt`), which must ship with it.
