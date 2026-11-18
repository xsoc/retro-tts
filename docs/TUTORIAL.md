# Tutorial

This walks from an empty project to a talking dialogue box with synced subtitles, then covers custom
voices, crunchy bit depths, positional speech and baking lines to WAV files. It takes about fifteen
minutes. You need Godot 4.7.

## 1. Install the addon

1. Download this repository (Code > Download ZIP on GitHub, or `git clone`).
2. Copy the `addons/retro_tts/` folder into your project, so you have `res://addons/retro_tts/plugin.cfg`.
3. Open your project. Go to **Project > Project Settings > Plugins** and tick **Enabled** next to
   **Retro TTS**.

The plugin's only job is to add the pronunciation dictionary (`data/lexicon.txt`) to your exports. The
node and voice classes work as soon as the files are in the project, but without the plugin an exported
game would fall back to spelling rules for every word and sound much worse.

## 2. Say something

1. Make a new scene with a **Node** root and save it as `talk.tscn`.
2. Add a child node: search for **RetroTTS** in the Create New Node dialog (it has a speaker icon).
3. In the inspector, type a line into **Text**, for example `Hello. Can you hear me?`, and tick
   **Autoplay**.
4. Press **F6** to run the scene.

You should hear the Narrator voice. That's all it takes: the node creates its own audio player.

## 3. Speak from code

Remove the Autoplay tick, attach a script to the root node, and speak from code:

```gdscript
extends Node

@onready var tts: RetroTTS = $RetroTTS


func _ready() -> void:
	tts.speak("Hello. Can you hear me?")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		tts.speak("You pressed the button.")
```

`speak()` cuts off anything still playing, so pressing Enter repeatedly restarts the line. Call `stop()` to
silence it, and check `is_speaking()` to know whether a line is still going.

## 4. Pick a voice

There are two ways:

- **Preset** (quick): leave **Voice** empty and choose a **Preset** in the inspector, or set
  `tts.preset = "robot"` in code.
- **Voice resource** (editable): drag a file from `addons/retro_tts/voices/` onto the **Voice** slot.
  Click it to expand every parameter in the inspector.

Try `robot`, `hive`, `ghost` and `radio` to hear the range. [VOICES.md](VOICES.md) lists them all.

## 5. Listen to the signals

RetroTTS tells you what the listener is hearing as it happens:

```gdscript
func _ready() -> void:
	tts.speech_started.connect(func(line): print("started: ", line))
	tts.sentence_started.connect(func(i, sentence): print("sentence ", i, ": ", sentence))
	tts.word_spoken.connect(func(word, index, char_start, char_length): print("  word ", index, ": ", word))
	tts.sentence_finished.connect(func(i, _sentence): print("sentence ", i, " done"))
	tts.speech_finished.connect(func(): print("finished"))
	tts.speech_stopped.connect(func(): print("interrupted"))
	tts.speak("The door is open. Go inside.")
```

`word_spoken` fires as each word *starts to come out of the speakers*, not when it renders, so you can
drive mouth animation, subtitles or camera cuts from it directly.

## 6. Sync subtitles

The usual dialogue-box effect is text that types itself out. With RetroTTS the text keeps pace with the
voice: show everything up to the end of the word being said.

Add a **RichTextLabel** (call it `Subtitle`) next to the RetroTTS node, then:

```gdscript
extends Node

@onready var tts: RetroTTS = $RetroTTS
@onready var subtitle: RichTextLabel = $Subtitle


func _ready() -> void:
	tts.word_spoken.connect(_on_word_spoken)
	tts.speech_finished.connect(_on_speech_finished)
	say("Welcome aboard. The captain will see you now.")


func say(line: String) -> void:
	subtitle.text = line
	subtitle.visible_characters = 0
	tts.speak(line)


func _on_word_spoken(_word: String, _index: int, char_start: int, char_length: int) -> void:
	subtitle.visible_characters = char_start + char_length


func _on_speech_finished() -> void:
	subtitle.visible_characters = -1
```

`char_start` and `char_length` index into the exact string you passed to `speak()`, so this also works
for text with numbers ("250" is said as "two hundred and fifty" but reported as one word, `250`) and
punctuation.

A working version with three lines and skip-on-press is in `examples/subtitles/`.

**If your label uses BBCode**, `visible_characters` counts visible characters, not source characters, so
tags shift the count. Either keep spoken text free of tags, or speak a plain-text copy and map positions
yourself.

## 7. A narrator and a character in one line

Set **Quote Voice** to a second voice. Text inside double quotes is spoken in that voice, the rest in
**Voice**:

```gdscript
tts.voice = RetroTTSVoice.from_preset("narrator")
tts.quote_voice = RetroTTSVoice.from_preset("brute")
tts.speak("The guard steps forward. \"Nobody passes.\" He crosses his arms.")
```

The signals keep counting words and sentences across the whole line.

## 8. Make your own voice

Start from a preset and change a few parameters:

```gdscript
var v := RetroTTSVoice.from_preset("gruff")
v.pitch_hz = 70.0        # deeper
v.formant_scale = 0.88   # bigger head
v.speed = 0.85           # slower
v.drive = 0.4            # grit
v.echo_volume = 0.35     # bigger room
v.echo_filter = RetroTTSVoice.EchoFilter.DARK
tts.voice = v
```

To keep it, save it as a file: `ResourceSaver.save(v, "res://voices/ogre.tres")`, or build it in the
inspector (New RetroTTSVoice) and save it from there. The quickest way to find a voice is the playground
scene: move the sliders until it sounds right, then copy the numbers.

## 9. Crunch it: bit depth and sample rate

Three settings make speech sound older:

```gdscript
tts.bit_depth = 8            # output resolution: 16 (clean) down to 1 (beeper)
tts.voice.sample_rate = 8000 # the voice's recording rate: lower is more muffled and aliased
tts.brr = true               # 4-bit BRR compression, on by default
```

`bit_depth` is on the node, so it applies to every voice the node speaks. Good values for speech are 8
(classic), 6 (gritty) and 4 (barely holding together). 1 to 3 are there if you want them.

## 10. Positional speech

To make a character's voice come from their position, give RetroTTS an **AudioStreamPlayer2D** or
**AudioStreamPlayer3D** as its **Output**:

1. Add an AudioStreamPlayer3D as a child of the character.
2. Select the RetroTTS node and drag the AudioStreamPlayer3D onto **Output**.

RetroTTS replaces that player's stream with its own and plays through it, so attenuation, doppler and
buses all come from the player. `bus` and `volume_db` on RetroTTS only apply to its internal player.

## 11. Pronunciation

Check how something will be said:

```gdscript
print(RetroTTS.phonemes("Zorgath awakens"))
```

For names the dictionary doesn't know, the engine guesses from the spelling. Teach it the right
pronunciation once, for every node:

```gdscript
RetroTTS.add_word("zorgath", "Z AO1 R G AE0 TH")
```

Or write the phonemes inline, in square brackets, for a single use:

```gdscript
tts.speak("Bow before [K R IY1 L AH0 K S].")
```

Phonemes are [ARPAbet](https://en.wikipedia.org/wiki/ARPABET), the set used by the CMU dictionary, with
a stress digit on each vowel: 1 primary, 2 secondary, 0 none. The quickest way to write one is to print
`phonemes()` for a real word that sounds close, and edit that.

## 12. Bake lines to WAV

Rendering happens in GDScript and costs CPU time. For lines you know ahead of time (menus, tutorials,
announcements) you can render them once in the editor and ship them as normal audio files. See
`examples/snippets/bake_wav.gd`: open it in the script editor and choose **File > Run**. It writes
`res://baked_speech/*.wav`.

At runtime the same call gives you an `AudioStreamWAV` you can play anywhere:

```gdscript
var wav := tts.render_wav("Warning. Hull breach detected.")
$AlarmPlayer.stream = wav
$AlarmPlayer.play()
```

`render_wav()` blocks until it finishes. Baked lines don't emit word signals, but `render()` returns the
word timings (`words[i].time`) if you want to drive subtitles from a baked line yourself.

## 13. Shipping

- Keep the plugin enabled so exports include `data/lexicon.txt`.
- Keep `data/LICENSE-cmudict.txt` with the dictionary (the plugin exports it too), and credit the CMU
  Pronouncing Dictionary somewhere players can see, as its licence asks.
- On the web, use a threads-enabled export for background rendering.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Every word sounds misspelled in an export | The plugin wasn't enabled when exporting, so the dictionary was left out. A warning in the log says so. |
| A pause before the first line | The dictionary loads the first time (about 125,000 words). RetroTTS starts loading it in the background in `_ready()`; you can also call `RetroTTSEngine.prepare()` from a thread during a loading screen. |
| The game hitches while speaking | `use_threads` is off, or a web export without threads. Rendering then runs on the main thread. |
| No sound | Check the node's `bus` exists, and the `output` player (if any) isn't muted or too far away. |
