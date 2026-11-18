@tool
@icon("res://addons/retro_tts/icons/retro_tts_voice.svg")
class_name RetroTTSVoice
extends Resource
## One voice for RetroTTS: every knob of the formant synthesiser and the retro voice chain.
##
## Make one in the inspector (New RetroTTSVoice), load a preset from addons/retro_tts/voices/, or in code:
##
##   var v := RetroTTSVoice.from_preset("robot")
##   v.pitch_hz = 70.0
##   $RetroTTS.voice = v
##
## The defaults are the "narrator" preset. Changing a property takes effect from the next speak().

enum Source { GLOTTAL, SAW, PULSE, TRIANGLE }
enum EchoFilter { FLAT, SOFT, DARK }

const _SOURCES := ["glottal", "saw", "pulse", "tri"]
const _FILTERS := ["flat", "soft", "dark"]

## Shown in menus; not used by the synthesiser.
@export var display_name := "Narrator"

@export_group("Pitch")
## Base pitch (f0) in Hz. Roughly 70-130 low voices, 180-280 high voices.
@export_range(40.0, 400.0, 1.0, "suffix:Hz") var pitch_hz := 102.0
## How far the pitch moves on stressed words and at the ends of phrases. 0 is flat.
@export_range(0.0, 2.0, 0.01) var pitch_range := 0.9
## Pulls the whole contour toward the base pitch: 1 is a dead monotone.
@export_range(0.0, 1.0, 0.01) var monotone := 0.0
## Random pitch wobble per glottal pulse (buzzy, insect-like).
@export_range(0.0, 0.2, 0.005) var flutter := 0.0
## Vibrato speed. Only used when vibrato_depth is above 0.
@export_range(0.0, 12.0, 0.1, "suffix:Hz") var vibrato_rate := 5.5
## Vibrato depth as a fraction of the pitch (0.03 is a gentle wobble).
@export_range(0.0, 0.15, 0.005) var vibrato_depth := 0.0

@export_group("Timing")
## Speaking speed. 1 is normal, 2 is twice as fast.
@export_range(0.4, 2.5, 0.01) var speed := 0.95

@export_group("Throat")
## Vocal tract scale: below 1 is a bigger head (deeper), above 1 is a smaller one (younger, brighter).
@export_range(0.7, 1.4, 0.01) var formant_scale := 1.0
## Formant bandwidth scale: higher is softer and muffled, lower is sharper and ringing.
@export_range(0.6, 1.8, 0.01) var bandwidth_scale := 1.0
## Spectral tilt of the glottal source: higher is darker.
@export_range(0.0, 0.9, 0.01) var tilt := 0.35
## How long the glottis stays open in each pulse: higher is breathier and softer.
@export_range(0.3, 0.9, 0.01) var open_quotient := 0.6
## Breath noise mixed into voiced sounds.
@export_range(0.0, 0.6, 0.01) var breath := 0.04
## The sound source: a natural glottal pulse, or a chip-style saw, pulse or triangle buzz.
@export var source: Source = Source.GLOTTAL
## Pulse width for the PULSE source.
@export_range(0.05, 0.5, 0.01) var pulse_duty := 0.3
## Whisper: noise instead of a voiced source.
@export var whisper := false

@export_group("Roughness")
## Random pitch error per pulse.
@export_range(0.0, 0.06, 0.001) var jitter := 0.0
## Random loudness error per pulse.
@export_range(0.0, 0.3, 0.01) var shimmer := 0.0
## Every other pulse quieter: a growl an octave down.
@export_range(0.0, 0.7, 0.01) var subharmonic := 0.0

@export_group("Recording")
## The rate the voice is "recorded" at before playback at 32 kHz. Lower is crunchier and more muffled.
@export_range(4000, 16000, 1, "suffix:Hz") var sample_rate := 16000

@export_group("Effects")
## Soft saturation. 0 is off.
@export_range(0.0, 1.0, 0.01) var drive := 0.0
## Band-limit like a radio or phone.
@export var radio := false
## Radio low cut.
@export_range(100.0, 1500.0, 10.0, "suffix:Hz") var radio_low := 300.0
## Radio high cut.
@export_range(1500.0, 7000.0, 10.0, "suffix:Hz") var radio_high := 3400.0
## Quantise the voice to this many bits before it is recorded (relative to its own peak). 0 is off.
## The RetroTTS node's bit_depth quantises the final output instead.
@export_range(0, 12, 1) var voice_bits := 0
## Tremolo (wing buzz) speed. Only used when tremolo_depth is above 0.
@export_range(0.0, 80.0, 0.5, "suffix:Hz") var tremolo_rate := 30.0
## Tremolo depth. 0 is off.
@export_range(0.0, 1.0, 0.01) var tremolo_depth := 0.0
## A second, delayed and detuned copy of the voice (chorus, hive). Delay in ms.
@export_range(1.0, 40.0, 0.5, "suffix:ms") var double_ms := 15.0
## Mix of the second voice. 0 is off.
@export_range(0.0, 1.0, 0.01) var double_mix := 0.0
## Ring modulator frequency.
@export_range(1.0, 400.0, 1.0, "suffix:Hz") var ring_hz := 30.0
## Ring modulator mix. 0 is off.
@export_range(0.0, 1.0, 0.01) var ring_mix := 0.0
## Comb filter (metal tube) delay in ms.
@export_range(0.5, 10.0, 0.1, "suffix:ms") var comb_ms := 2.6
## Comb filter feedback. 0 is off.
@export_range(0.0, 0.9, 0.01) var comb_feedback := 0.0
## Chance of a mandible click at the start of each word. 0 is off.
@export_range(0.0, 1.0, 0.01) var clicks := 0.0

@export_group("Echo")
## Echo delay in 16 ms steps, like a 16-bit console's echo unit.
@export_range(1, 15, 1) var echo_delay := 4
## Echo feedback.
@export_range(0.0, 0.9, 0.01) var echo_feedback := 0.25
## Echo volume. 0 is off.
@export_range(0.0, 0.8, 0.01) var echo_volume := 0.18
## The echo's 8-tap filter: flat, soft or dark.
@export var echo_filter: EchoFilter = EchoFilter.SOFT


## The ids of the built-in presets: narrator, hero, computer, warm, bright, ...
static func preset_ids() -> PackedStringArray:
	return PackedStringArray(RetroTTSEngine.VOICES.keys())


## A new voice from a built-in preset id (see preset_ids()). An unknown id gives the narrator.
static func from_preset(id: String) -> RetroTTSVoice:
	var v := RetroTTSVoice.new()
	v.load_preset(id)
	return v


## Sets every property from a built-in preset.
func load_preset(id: String) -> void:
	var d: Dictionary = RetroTTSEngine.VOICES.get(id, RetroTTSEngine.VOICES["narrator"])
	from_dict(d)


## Sets every property from an engine voice dictionary (the format of RetroTTSEngine.VOICES).
func from_dict(d: Dictionary) -> void:
	var fx: Dictionary = d.get("fx", {})
	var echo: Dictionary = d.get("echo", {})
	display_name = str(d.get("name", "Voice"))
	pitch_hz = float(d.get("f0", 102.0))
	pitch_range = float(d.get("range", 1.0))
	monotone = float(d.get("monotone", 0.0))
	flutter = float(d.get("flutter", 0.0))
	var vib: Dictionary = d.get("vibrato", {})
	vibrato_rate = float(vib.get("rate", 5.5))
	vibrato_depth = float(vib.get("depth", 0.0))
	speed = float(d.get("rate", 1.0))
	formant_scale = float(d.get("formant", 1.0))
	bandwidth_scale = float(d.get("bw", 1.0))
	tilt = float(d.get("tilt", 0.25))
	open_quotient = float(d.get("oq", 0.6))
	breath = float(d.get("breath", 0.0))
	source = maxi(0, _SOURCES.find(str(d.get("source", "glottal")))) as Source
	pulse_duty = float(d.get("duty", 0.3))
	whisper = bool(d.get("whisper", false))
	jitter = float(d.get("jitter", 0.0))
	shimmer = float(d.get("shimmer", 0.0))
	subharmonic = float(d.get("sub", 0.0))
	sample_rate = int(d.get("hz", 16000))
	drive = float(fx.get("drive", 0.0))
	radio = fx.has("radio")
	var band: Array = fx.get("radio", [300.0, 3400.0])
	radio_low = float(band[0])
	radio_high = float(band[1])
	voice_bits = int(fx.get("bits", 0))
	var trem: Dictionary = fx.get("trem", {})
	tremolo_rate = float(trem.get("rate", 30.0))
	tremolo_depth = float(trem.get("depth", 0.0))
	var dbl: Dictionary = fx.get("double", {})
	double_ms = float(dbl.get("ms", 15.0))
	double_mix = float(dbl.get("mix", 0.0))
	var ring: Dictionary = fx.get("ring", {})
	ring_hz = float(ring.get("hz", 30.0))
	ring_mix = float(ring.get("mix", 0.0))
	var comb: Dictionary = fx.get("comb", {})
	comb_ms = float(comb.get("ms", 2.6))
	comb_feedback = float(comb.get("fb", 0.0))
	clicks = float(fx.get("click", 0.0))
	echo_delay = int(echo.get("delay", 1))
	echo_feedback = float(echo.get("fb", 0.0))
	echo_volume = float(echo.get("vol", 0.0))
	echo_filter = maxi(0, _FILTERS.find(str(echo.get("fir", "flat")))) as EchoFilter
	emit_changed()


## The voice as an engine dictionary, for RetroTTSEngine.say().
func to_dict() -> Dictionary:
	var fx := {}
	if drive > 0.0:
		fx["drive"] = drive
	if radio:
		fx["radio"] = [radio_low, maxf(radio_high, radio_low + 100.0)]
	if voice_bits > 0:
		fx["bits"] = voice_bits
	if tremolo_depth > 0.0:
		fx["trem"] = {"rate": tremolo_rate, "depth": tremolo_depth}
	if double_mix > 0.0:
		fx["double"] = {"ms": double_ms, "mix": double_mix}
	if ring_mix > 0.0:
		fx["ring"] = {"hz": ring_hz, "mix": ring_mix}
	if comb_feedback > 0.0:
		fx["comb"] = {"ms": comb_ms, "fb": comb_feedback}
	if clicks > 0.0:
		fx["click"] = clicks
	var d := {
		"name": display_name, "f0": pitch_hz, "range": pitch_range, "monotone": monotone, "flutter": flutter,
		"rate": speed, "formant": formant_scale, "bw": bandwidth_scale, "tilt": tilt, "oq": open_quotient,
		"breath": breath, "source": _SOURCES[source], "duty": pulse_duty, "whisper": whisper,
		"jitter": jitter, "shimmer": shimmer, "sub": subharmonic, "hz": sample_rate, "fx": fx,
		"echo": {"delay": echo_delay, "fb": echo_feedback, "vol": echo_volume, "fir": _FILTERS[echo_filter]},
	}
	if vibrato_depth > 0.0:
		d["vibrato"] = {"rate": vibrato_rate, "depth": vibrato_depth}
	return d
