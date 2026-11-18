# Voices

## Presets

Seventeen voices ship with the addon, as files in `addons/retro_tts/voices/` and as ids for
`RetroTTS.preset` and `RetroTTSVoice.from_preset()`.

| Id | Name | Character | Pitch | Recorded at | Effects |
|---|---|---|---|---|---|
| `narrator` | Narrator | Calm storyteller | 102 Hz | 16000 Hz | none |
| `hero` | Hero | Clear, friendly lead | 150 Hz | 16000 Hz | none |
| `computer` | Computer | Alerts and callouts | 210 Hz | 16000 Hz | pulse source, 8-bit voice |
| `warm` | Warm | Soft, high voice | 240 Hz | 16000 Hz | none |
| `bright` | Bright | Quick, high voice | 255 Hz | 14000 Hz | none |
| `steady` | Steady | Even, low voice | 112 Hz | 14000 Hz | none |
| `fast_talker` | Fast talker | Lively, wide pitch | 124 Hz | 11025 Hz | none |
| `breathy` | Breathy | Slow, airy, distant | 205 Hz | 12000 Hz | none |
| `brute` | Brute | Deep, rough growl | 74 Hz | 10000 Hz | drive |
| `insect` | Insect | Buzzing wings, clicks | 270 Hz | 12000 Hz | tremolo, double voice, clicks |
| `robot` | Robot | Metallic monotone | 92 Hz | 12000 Hz | saw source, ring mod, comb |
| `ghost` | Ghost | Whisper in a cave | 90 Hz | 11025 Hz | whisper, double voice |
| `hive` | Hive | Many voices at once | 182 Hz | 10000 Hz | pulse source, tremolo, double voice, clicks |
| `choir` | Choir | Slow chant, big hall | 120 Hz | 11025 Hz | triangle source, double voice |
| `gruff` | Gruff | Low and weathered | 98 Hz | 11025 Hz | drive |
| `radio` | Radio | Over a crackly radio | 132 Hz | 11025 Hz | drive, radio band |
| `dispatch` | Dispatch | Flat, 8 kHz comms | 108 Hz | 8000 Hz | drive, radio band |

The best way to hear them is the playground scene: pick a preset from the menu and press PLAY.

## Making your own

Start from the preset closest to what you want and change a few things. In the editor: in the
FileSystem dock, right-click a preset `.tres` and choose **Duplicate**, then edit the copy in the
inspector. In code:

```gdscript
var v := RetroTTSVoice.from_preset("steady")
v.pitch_hz = 90.0
v.echo_volume = 0.3
$RetroTTS.voice = v
```

Or create a new one from scratch: in the inspector, click the **Voice** slot of a RetroTTS node and choose
**New RetroTTSVoice**. It starts as the Narrator.

## Parameters

### Pitch

| Parameter | Range | What it does |
|---|---|---|
| `pitch_hz` | 40..400 Hz | Base pitch. About 70-130 for low voices, 180-280 for high ones. |
| `pitch_range` | 0..2 | How much the pitch moves on stressed words and at phrase ends. 0 is flat, 1 is natural, above 1 is animated. |
| `monotone` | 0..1 | Pulls the whole contour toward the base pitch. 1 is a dead monotone (robots, chants). |
| `flutter` | 0..0.2 | Random pitch wobble per pulse: buzzy and unstable. |
| `vibrato_rate`, `vibrato_depth` | Hz, 0..0.15 | A regular wobble. Depth 0 turns it off. |

### Timing

| Parameter | Range | What it does |
|---|---|---|
| `speed` | 0.4..2.5 | Speaking speed. Pauses at commas and full stops scale too. |

### Throat

| Parameter | Range | What it does |
|---|---|---|
| `formant_scale` | 0.7..1.4 | The size of the vocal tract. Below 1: a bigger head, deeper and darker. Above 1: smaller, younger, brighter. Move it with `pitch_hz` for a believable voice. |
| `bandwidth_scale` | 0.6..1.8 | Formant width. Higher is softer and muffled, lower is ringing and nasal. |
| `tilt` | 0..0.9 | Darkens the glottal source. |
| `open_quotient` | 0.3..0.9 | How long the glottis is open each cycle. Higher is breathier and softer, lower is pressed and buzzy. |
| `breath` | 0..0.6 | Breath noise mixed into voiced sounds. |
| `source` | Glottal, Saw, Pulse, Triangle | The sound source. Glottal is human. Saw, Pulse and Triangle are chip-style buzz: more robotic, still intelligible. |
| `pulse_duty` | 0.05..0.5 | Pulse width for the Pulse source. Narrow is thin and nasal. |
| `whisper` | on/off | Noise instead of a voice. |

### Roughness

| Parameter | Range | What it does |
|---|---|---|
| `jitter` | 0..0.06 | Random pitch error per pulse: a rough, old or nervous voice. |
| `shimmer` | 0..0.3 | Random loudness error per pulse: raspy. |
| `subharmonic` | 0..0.7 | Every other pulse quieter, giving a growl an octave down. |

### Recording

| Parameter | Range | What it does |
|---|---|---|
| `sample_rate` | 4000..16000 Hz | The rate the voice is "recorded" at before playback at 32 kHz. Game consoles stored speech samples at low rates to save memory: 16000 is clear, 11025 is a classic game voice, 8000 is a phone line, 4000 is mush. |

### Effects

Every effect is off at 0.

| Parameter | What it does |
|---|---|
| `drive` | Soft saturation: grit and loudness. |
| `radio`, `radio_low`, `radio_high` | Band-limits the voice like a radio or intercom. |
| `voice_bits` | Quantises the voice (relative to its own peak) before it is recorded. Unlike `RetroTTS.bit_depth`, this belongs to the voice, so one character can be crunchy while the rest stay clean. |
| `tremolo_rate`, `tremolo_depth` | Fast volume wobble: wings, engines, a failing speaker. |
| `double_ms`, `double_mix` | A second, slightly delayed and detuned copy of the voice: chorus, hive minds, choirs. |
| `ring_hz`, `ring_mix` | Ring modulation: classic sci-fi metal. |
| `comb_ms`, `comb_feedback` | A short resonant tube: the voice inside a helmet or a can. |
| `clicks` | The chance of a click at the start of each word (mandibles, static). |

### Echo

The echo is modelled on a 16-bit console's echo unit: a delay line, an 8-tap filter and feedback.

| Parameter | Range | What it does |
|---|---|---|
| `echo_delay` | 1..15 | Delay in 16 ms steps. 1-3 is a small room, 5-10 a hall or cave. |
| `echo_feedback` | 0..0.9 | How many repeats. |
| `echo_volume` | 0..0.8 | How loud the echo is. 0 turns it off. |
| `echo_filter` | Flat, Soft, Dark | The tone of the repeats. |

## Line settings on the node

These belong to the `RetroTTS` node, not the voice, so they apply to every voice it speaks with:
`speed` and `pitch` (multipliers), `bit_depth` (1..16), `brr` (the 4-bit BRR round trip) and `loudness`.
