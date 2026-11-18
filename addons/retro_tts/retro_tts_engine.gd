class_name RetroTTSEngine
extends RefCounted
## Retro TTS engine: procedural 16-bit era text-to-speech, in pure GDScript.
##
## Text -> words -> phonemes (CMU lexicon, custom words, spelling rules) -> durations and pitch (stress,
## phrase shape) -> a Klatt-style formant synthesiser (glottal pulse or buzz source, cascade vocal tract,
## parallel frication) -> a 16-bit console style voice chain: resample to the voice's "recorded" sample
## rate, a 4-bit BRR (ADPCM) round trip, Gaussian interpolation up to 32 kHz, echo with an 8-tap FIR,
## loudness to a target, and an optional output bit depth.
##
##   var r := RetroTTSEngine.say("Hold on to something.", "steady")
##   r.pcm (PackedFloat32Array, mono, 32 kHz), r.words [{text, at, len, start, end}] in seconds
##
## Pure static functions, and slow-ish (GDScript, per sample): run it off the main thread. The RetroTTS
## node does that for you. Every function here is safe to call from worker threads.

const RATE := 32000            ## output, like the music and SFX
const SR := 16000              ## synthesis rate
const FRAME := 32              ## parameter update period in samples (2 ms)
const LEXICON_PATH := "res://addons/retro_tts/data/lexicon.txt"
## The output bit depth: BRR decodes to 16-bit samples, so 16 means "no extra quantisation".
const MAX_BITS := 16
## global tuning, found by scoring with a speech recogniser
const TUNE := {"burst": 1.0, "finalRelease": 0.6, "finalAsp": 0.0, "asp": 48.0, "aspWeak": 30.0}
const M32 := 0xFFFFFFFF

# ---------------------------------------------------------------- phonemes

const PHONES := ["AA", "AE", "AH", "AO", "AW", "AY", "EH", "ER", "EY", "IH", "IY", "OW", "OY", "UH", "UW",
	"B", "CH", "D", "DH", "F", "G", "HH", "JH", "K", "L", "M", "N", "NG", "P", "R", "S", "SH", "T", "TH",
	"V", "W", "Y", "Z", "ZH"]
const CODES := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLM"

## Targets for an adult male tract; voices scale them.
## k: v vowel, g glide/liquid, n nasal, s stop, f fricative, h aspirate, a affricate
## f: F1..F3, b: B1..B3, e: diphthong end formants, d: [inherent, minimum] ms
## fr: parallel frication amps in dB [A2, A3, A4, A5, A6, AB] (60 dB = full); av: voicing amplitude
const PH := {
	"IY": {"k": "v", "f": [310, 2200, 2960], "b": [45, 200, 400], "d": [155, 55]},
	"IH": {"k": "v", "f": [400, 1800, 2570], "b": [50, 100, 140], "d": [135, 40]},
	"EY": {"k": "v", "f": [480, 1900, 2520], "b": [70, 100, 200], "e": [330, 2200, 2600], "d": [190, 100]},
	"EH": {"k": "v", "f": [530, 1680, 2500], "b": [60, 90, 200], "d": [150, 70]},
	"AE": {"k": "v", "f": [660, 1700, 2430], "b": [70, 150, 320], "d": [230, 80]},
	"AA": {"k": "v", "f": [720, 1150, 2600], "b": [130, 70, 160], "d": [240, 100]},
	"AO": {"k": "v", "f": [600, 920, 2570], "b": [90, 100, 80], "d": [240, 100]},
	"OW": {"k": "v", "f": [540, 1050, 2300], "b": [80, 70, 70], "e": [420, 850, 2300], "d": [220, 80]},
	"UH": {"k": "v", "f": [450, 1100, 2350], "b": [80, 100, 80], "d": [160, 60]},
	"UW": {"k": "v", "f": [350, 1250, 2200], "b": [65, 110, 140], "e": [320, 900, 2200], "d": [210, 70]},
	"AH": {"k": "v", "f": [620, 1220, 2550], "b": [80, 50, 140], "d": [140, 60]},
	"AX": {"k": "v", "f": [500, 1400, 2300], "b": [100, 100, 200], "d": [120, 50]},
	"ER": {"k": "v", "f": [470, 1270, 1540], "b": [100, 60, 110], "d": [180, 80]},
	"AY": {"k": "v", "f": [700, 1200, 2550], "b": [100, 70, 200], "e": [400, 1880, 2500], "d": [250, 150]},
	"AW": {"k": "v", "f": [680, 1230, 2550], "b": [80, 70, 140], "e": [420, 940, 2350], "d": [260, 100]},
	"OY": {"k": "v", "f": [550, 960, 2400], "b": [80, 50, 130], "e": [360, 1820, 2450], "d": [280, 150]},
	"W": {"k": "g", "f": [290, 610, 2150], "b": [50, 80, 60], "d": [80, 60], "av": 0.7},
	"Y": {"k": "g", "f": [260, 2070, 3020], "b": [40, 250, 500], "d": [80, 40], "av": 0.7},
	"R": {"k": "g", "f": [310, 1060, 1380], "b": [70, 100, 120], "d": [80, 30], "av": 0.72},
	"L": {"k": "g", "f": [310, 1050, 2880], "b": [50, 100, 280], "d": [80, 40], "av": 0.72},
	"M": {"k": "n", "f": [480, 1270, 2130], "b": [40, 200, 200], "d": [70, 60], "av": 0.42},
	"N": {"k": "n", "f": [480, 1340, 2470], "b": [40, 300, 300], "d": [60, 40], "av": 0.42},
	"NG": {"k": "n", "f": [480, 2000, 2900], "b": [160, 150, 100], "d": [95, 60], "av": 0.42},
	"B": {"k": "s", "f": [200, 1100, 2150], "b": [60, 110, 130], "d": [85, 60], "vd": true, "fr": [0, 0, 0, 0, 0, 50]},
	"D": {"k": "s", "f": [200, 1700, 2600], "b": [60, 100, 170], "d": [75, 50], "vd": true, "fr": [0, 42, 48, 54, 58, 0]},
	"G": {"k": "s", "f": [250, 1990, 2850], "b": [60, 150, 280], "d": [80, 60], "vd": true, "fr": [54, 52, 44, 42, 0, 0]},
	"P": {"k": "s", "f": [200, 1100, 2150], "b": [60, 110, 130], "d": [90, 50], "fr": [0, 0, 0, 0, 0, 52]},
	"T": {"k": "s", "f": [200, 1700, 2600], "b": [60, 100, 170], "d": [75, 50], "fr": [0, 40, 50, 60, 66, 0]},
	"K": {"k": "s", "f": [250, 1990, 2850], "b": [60, 150, 280], "d": [80, 60], "fr": [56, 54, 46, 44, 0, 0]},
	"DX": {"k": "s", "f": [250, 1600, 2600], "b": [60, 100, 170], "d": [25, 20], "vd": true, "flap": true},
	"F": {"k": "f", "f": [340, 1100, 2080], "b": [200, 120, 150], "d": [100, 80], "fr": [0, 0, 0, 0, 0, 40]},
	"V": {"k": "f", "f": [220, 1100, 2080], "b": [60, 90, 120], "d": [60, 40], "vd": true, "fr": [0, 0, 0, 0, 0, 38]},
	"TH": {"k": "f", "f": [320, 1290, 2540], "b": [200, 90, 200], "d": [100, 60], "fr": [0, 0, 0, 0, 30, 37]},
	"DH": {"k": "f", "f": [270, 1290, 2540], "b": [60, 80, 170], "d": [50, 30], "vd": true, "fr": [0, 0, 0, 0, 26, 33]},
	"S": {"k": "f", "f": [320, 1390, 2530], "b": [200, 80, 200], "d": [105, 60], "fr": [0, 0, 0, 52, 64, 0]},
	"Z": {"k": "f", "f": [240, 1390, 2530], "b": [70, 60, 180], "d": [75, 40], "vd": true, "fr": [0, 0, 0, 48, 59, 0]},
	"SH": {"k": "f", "f": [300, 1840, 2750], "b": [200, 100, 300], "d": [105, 80], "fr": [0, 58, 52, 48, 40, 0]},
	"ZH": {"k": "f", "f": [300, 1840, 2750], "b": [220, 60, 150], "d": [70, 40], "vd": true, "fr": [0, 54, 48, 44, 36, 0]},
	"HH": {"k": "h", "f": [500, 1500, 2500], "b": [300, 200, 300], "d": [80, 20]},
	"CH": {"k": "a", "d": [130, 90]},               # T closure + SH
	"JH": {"k": "a", "d": [110, 70], "vd": true},   # D closure + ZH
}

## Words that don't take a pitch accent and are said quickly.
const FUNCTION_WORDS := ("a an the of to and or but in on at by for from with as is are was were be been am " +
	"it its it's he him his she her they them their we us our you your i me my this that these those there " +
	"has have had do does did will would can could shall should may might must if so than then up out " +
	"into onto over about some any all each such what which who whom when where how just too very")

## Built-in extra pronunciations (contractions the tokenizer splits, common abbreviations). Stress marks
## as in CMU: 1 primary, 2 secondary, 0 none. Add your own with add_word().
const BUILTIN_WORDS := {
	"ok": "OW2 K EY1", "okay": "OW2 K EY1", "didn": "D IH1 D AH0 N", "doesn": "D AH1 Z AH0 N",
	"wasn": "W AA1 Z AH0 N", "isn": "IH1 Z AH0 N", "hp": "EY1 CH P IY1", "tts": "T IY1 T IY1 EH1 S",
}

## Voice presets as engine dictionaries. RetroTTSVoice wraps these as an editable Resource.
## f0 Hz; range: pitch movement; monotone 0..1; rate: speed; formant: tract scale (bigger = smaller head);
## bw: formant bandwidth scale; tilt 0..0.9 darker; oq open quotient; breath; jitter/shimmer/sub roughness;
## flutter: pitch wobble; source glottal|saw|pulse|tri (duty for pulse); whisper; vibrato {rate Hz, depth};
## hz: the "recorded" sample rate (lower = crunchier); echo {delay (x16 ms), fb, vol, fir};
## fx: character effects {drive, radio [lo, hi], bits, trem {rate, depth}, double {ms, mix}, ring {hz, mix},
## comb {ms, fb}, click}.
const VOICES := {
	"narrator": {"name": "Narrator", "who": "Calm storyteller", "f0": 102, "range": 0.9, "rate": 0.95, "formant": 1.0, "tilt": 0.35, "breath": 0.04, "hz": 16000, "echo": {"delay": 4, "fb": 0.25, "vol": 0.18, "fir": "soft"}},
	"hero": {"name": "Hero", "who": "Clear, friendly lead", "f0": 150, "range": 0.95, "rate": 1.0, "formant": 1.08, "bw": 1.1, "tilt": 0.3, "breath": 0.05, "oq": 0.62, "hz": 16000, "echo": {"delay": 2, "fb": 0.15, "vol": 0.12, "fir": "soft"}},
	"computer": {"name": "Computer", "who": "Alerts and callouts", "f0": 210, "range": 0.25, "monotone": 0.6, "rate": 1.05, "formant": 1.18, "bw": 1.25, "source": "pulse", "duty": 0.35, "hz": 16000, "fx": {"bits": 8}, "echo": {"delay": 2, "fb": 0.2, "vol": 0.22, "fir": "flat"}},
	"warm": {"name": "Warm", "who": "Soft, high voice", "f0": 240, "range": 1.0, "rate": 0.95, "formant": 1.22, "bw": 1.35, "tilt": 0.4, "breath": 0.08, "oq": 0.68, "hz": 16000, "echo": {"delay": 3, "fb": 0.2, "vol": 0.15, "fir": "soft"}},
	"bright": {"name": "Bright", "who": "Quick, high voice", "f0": 255, "range": 1.15, "rate": 1.12, "formant": 1.24, "bw": 1.2, "tilt": 0.28, "breath": 0.04, "oq": 0.6, "hz": 14000, "echo": {"delay": 2, "fb": 0.15, "vol": 0.12, "fir": "flat"}},
	"steady": {"name": "Steady", "who": "Even, low voice", "f0": 112, "range": 0.75, "rate": 0.98, "formant": 1.02, "tilt": 0.32, "breath": 0.03, "hz": 14000, "echo": {"delay": 3, "fb": 0.2, "vol": 0.15, "fir": "soft"}},
	"fast_talker": {"name": "Fast talker", "who": "Lively, wide pitch", "f0": 124, "range": 1.35, "rate": 1.2, "formant": 1.03, "tilt": 0.25, "breath": 0.05, "jitter": 0.01, "hz": 11025, "echo": {"delay": 2, "fb": 0.15, "vol": 0.12, "fir": "flat"}},
	"breathy": {"name": "Breathy", "who": "Slow, airy, distant", "f0": 205, "range": 0.55, "rate": 0.85, "formant": 1.16, "tilt": 0.55, "breath": 0.35, "oq": 0.75, "hz": 12000, "echo": {"delay": 6, "fb": 0.4, "vol": 0.3, "fir": "dark"}},
	"brute": {"name": "Brute", "who": "Deep, rough growl", "f0": 74, "range": 0.8, "rate": 0.85, "formant": 0.84, "bw": 1.15, "tilt": 0.3, "jitter": 0.03, "shimmer": 0.15, "sub": 0.35, "hz": 10000, "fx": {"drive": 0.35}, "echo": {"delay": 4, "fb": 0.3, "vol": 0.2, "fir": "dark"}},
	"insect": {"name": "Insect", "who": "Buzzing wings, clicks", "f0": 270, "range": 0.7, "rate": 1.0, "formant": 1.22, "tilt": 0.15, "oq": 0.45, "flutter": 0.06, "hz": 12000, "fx": {"trem": {"rate": 31, "depth": 0.3}, "double": {"ms": 9, "mix": 0.3}, "click": 0.6}, "echo": {"delay": 2, "fb": 0.25, "vol": 0.18, "fir": "flat"}},
	"robot": {"name": "Robot", "who": "Metallic monotone", "f0": 92, "range": 0.3, "monotone": 0.5, "rate": 0.9, "formant": 0.96, "source": "saw", "hz": 12000, "fx": {"comb": {"ms": 2.6, "fb": 0.55}, "ring": {"hz": 30, "mix": 0.15}}, "echo": {"delay": 5, "fb": 0.45, "vol": 0.32, "fir": "dark"}},
	"ghost": {"name": "Ghost", "who": "Whisper in a cave", "f0": 90, "range": 0.4, "rate": 0.85, "formant": 0.98, "whisper": true, "hz": 11025, "fx": {"double": {"ms": 23, "mix": 0.35}}, "echo": {"delay": 10, "fb": 0.55, "vol": 0.45, "fir": "dark"}},
	"hive": {"name": "Hive", "who": "Many voices at once", "f0": 182, "range": 0.4, "monotone": 0.3, "rate": 1.06, "formant": 1.12, "bw": 1.3, "source": "pulse", "duty": 0.22, "tilt": 0.1, "flutter": 0.08, "hz": 10000, "fx": {"double": {"ms": 17, "mix": 0.5}, "trem": {"rate": 47, "depth": 0.4}, "click": 0.9}, "echo": {"delay": 2, "fb": 0.3, "vol": 0.2, "fir": "flat"}},
	"choir": {"name": "Choir", "who": "Slow chant, big hall", "f0": 120, "range": 0.2, "monotone": 0.7, "rate": 0.8, "formant": 0.93, "source": "tri", "tilt": 0.5, "breath": 0.15, "hz": 11025, "fx": {"double": {"ms": 31, "mix": 0.55}}, "echo": {"delay": 9, "fb": 0.55, "vol": 0.4, "fir": "dark"}},
	"gruff": {"name": "Gruff", "who": "Low and weathered", "f0": 98, "range": 0.9, "rate": 0.95, "formant": 0.9, "tilt": 0.35, "jitter": 0.02, "shimmer": 0.08, "sub": 0.15, "hz": 11025, "fx": {"drive": 0.15}, "echo": {"delay": 3, "fb": 0.2, "vol": 0.15, "fir": "soft"}},
	"radio": {"name": "Radio", "who": "Over a crackly radio", "f0": 132, "range": 1.3, "rate": 1.1, "formant": 0.98, "jitter": 0.015, "hz": 11025, "fx": {"radio": [300, 3400], "drive": 0.25}, "echo": {"delay": 1, "fb": 0, "vol": 0, "fir": "flat"}},
	"dispatch": {"name": "Dispatch", "who": "Flat, 8 kHz comms", "f0": 108, "range": 0.5, "rate": 1.0, "formant": 1.0, "hz": 8000, "fx": {"radio": [400, 3200], "drive": 0.25}, "echo": {"delay": 1, "fb": 0, "vol": 0, "fir": "flat"}},
}

const ONES := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
	"twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
const TENS := ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
const PAUSE := {",": 170, ";": 260, "—": 220, ".": 420, "!": 420, "?": 420, "...": 560}

## Spelling rules for names the lexicon doesn't know (star names, made-up words). Tried longest first at each
## letter; context: '^' start of word, '$' end, 'V' any vowel letter, 'C' any consonant letter, '+' e/i/y.
## [left, letters, right, phonemes]
const LTS := [
	["", "tion", "", "SH AH N"], ["", "sion", "", "ZH AH N"], ["", "ough", "", "AO"], ["", "augh", "", "AO"],
	["", "igh", "", "AY"], ["", "tch", "", "CH"], ["", "ght", "", "T"],
	["^", "kn", "", "N"], ["^", "wr", "", "R"], ["^", "ps", "", "S"],
	["", "ch", "", "CH"], ["", "sh", "", "SH"], ["", "th", "", "TH"], ["", "ph", "", "F"], ["", "wh", "", "W"],
	["", "ck", "", "K"], ["", "ng", "$", "NG"], ["", "nk", "", "NG K"], ["", "qu", "", "K W"], ["", "gh", "", "G"],
	["", "ee", "", "IY"], ["", "ea", "", "IY"], ["", "ie", "$", "IY"], ["", "ei", "", "EY"], ["", "ey", "$", "IY"],
	["", "ai", "", "EY"], ["", "ay", "", "EY"], ["", "au", "", "AO"], ["", "aw", "", "AO"],
	["", "oo", "", "UW"], ["", "ou", "", "AW"], ["", "ow", "", "OW"], ["", "oi", "", "OY"], ["", "oy", "", "OY"],
	["", "oa", "", "OW"], ["", "ue", "$", "UW"], ["", "ew", "", "UW"],
	["", "ar", "", "AA R"], ["", "er", "", "ER"], ["", "ir", "", "ER"], ["", "ur", "", "ER"], ["", "or", "", "AO R"],
	["", "a", "C e$", "EY"], ["", "i", "C e$", "AY"], ["", "o", "C e$", "OW"], ["", "u", "C e$", "UW"],
	["C", "e", "$", ""], ["", "es", "$", "Z"], ["C", "ed", "$", "D"],
	["", "a", "$", "AH"], ["", "a", "CV", "AA"], ["", "a", "", "AE"],
	["", "e", "", "EH"], ["", "i", "$", "IY"], ["", "i", "", "IH"],
	["", "o", "$", "OW"], ["", "o", "", "AA"], ["", "u", "CV", "UW"], ["", "u", "", "AH"],
	["^", "y", "V", "Y"], ["", "y", "$", "IY"], ["", "y", "", "IH"],
	["", "c", "+", "S"], ["", "c", "", "K"], ["", "g", "e$", "JH"], ["", "g", "", "G"],
	["V", "s", "V", "Z"], ["", "x", "", "K S"], ["", "j", "", "JH"], ["", "q", "", "K"], ["", "z", "", "Z"],
	["", "b", "", "B"], ["", "d", "", "D"], ["", "f", "", "F"], ["", "h", "", "HH"], ["", "k", "", "K"],
	["", "l", "", "L"], ["", "m", "", "M"], ["", "n", "", "N"], ["", "p", "", "P"], ["", "r", "", "R"],
	["", "s", "", "S"], ["", "t", "", "T"], ["", "v", "", "V"], ["", "w", "", "W"],
]

const BRR_FILTERS := [[0.0, 0.0], [15.0 / 16, 0.0], [61.0 / 32, -15.0 / 16], [115.0 / 64, -13.0 / 16]]
const BRR_SCALE := 15000.0
const FIR := {
	"flat": [127, 0, 0, 0, 0, 0, 0, 0],
	"soft": [12, 33, 43, 43, 19, -2, -13, -7],
	"dark": [24, 32, 32, 24, 16, 8, -4, -4],
}

static var LEX := {}
static var _fn_words := {}
static var _gauss := PackedFloat32Array()
static var _re_tok: RegEx
static var _re_dbl: RegEx
static var _ready_ := false
static var _prep_lock := Mutex.new()
static var _custom := {}
static var _custom_lock := Mutex.new()


## Loads the lexicon and builds the tables. Slow the first time (the lexicon is 125k words), so the
## RetroTTS node calls it on a worker thread. Safe to call from several threads at once.
static func prepare() -> void:
	if _ready_:
		return
	_prep_lock.lock()
	if _ready_:
		_prep_lock.unlock()
		return
	_prepare_locked()
	_prep_lock.unlock()


## True once the lexicon is loaded.
static func is_prepared() -> bool:
	return _ready_


static func _prepare_locked() -> void:
	for w in FUNCTION_WORDS.split(" "):
		_fn_words[w] = true
	_re_tok = RegEx.create_from_string("\\[([A-Z][A-Z0-2 ]*)\\]|(\\d[\\d,]*(?:\\.\\d+)?%?)|([A-Za-z][A-Za-z']*)|(\\.\\.\\.|…|[.!?]+|[,;:]|—|--|\\s-\\s)")
	_re_dbl = RegEx.create_from_string("([bcdfgklmnprstvz])\\1")
	_gauss.resize(256 * 4)
	var sigma := 0.62
	for i in 256:
		var f := i / 256.0
		var w := []
		var s := 0.0
		for k in 4:
			var d := (k - 1) - f
			var v := exp(-(d * d) / (2 * sigma * sigma))
			w.append(v)
			s += v
		for k in 4:
			_gauss[i * 4 + k] = w[k] / s
	var fa := FileAccess.open(LEXICON_PATH, FileAccess.READ)
	if fa:
		load_lexicon(fa.get_as_text())
	else:
		push_warning("RetroTTS: no pronunciation dictionary at %s; words will be spelled out by rule. Enable the Retro TTS plugin so exports include it." % LEXICON_PATH)
	_ready_ = true


static func load_lexicon(text: String) -> int:
	var lex := {}
	for line in text.split("\n", false):
		var sp := line.find(" ")
		if sp > 0:
			lex[line.substr(0, sp)] = line.substr(sp + 1)
	LEX = lex
	return LEX.size()


## Teaches the engine a word: add_word("gorrak", "G AO1 R AE0 K"). ARPAbet phonemes (the CMU set),
## stress digits on vowels: 1 primary, 2 secondary, 0 none. Overrides the dictionary. Thread-safe.
static func add_word(word: String, arpabet: String) -> void:
	_custom_lock.lock()
	_custom[word.to_lower()] = arpabet.strip_edges().to_upper()
	_custom_lock.unlock()


## Forgets a word added with add_word().
static func remove_word(word: String) -> void:
	_custom_lock.lock()
	_custom.erase(word.to_lower())
	_custom_lock.unlock()


## Adds many words at once: {"word": "ARPABET", ...}.
static func add_words(words: Dictionary) -> void:
	for w in words:
		add_word(str(w), str(words[w]))


static func _custom_get(w: String) -> String:
	_custom_lock.lock()
	var v: String = _custom.get(w, "")
	_custom_lock.unlock()
	if v == "":
		v = BUILTIN_WORDS.get(w, "")
	return v


static func _custom_has(w: String) -> bool:
	return _custom_get(w) != ""


static func is_vowel(p: String) -> bool:
	return PH.has(p) and PH[p].k == "v"


static func is_voiced(p: String) -> bool:
	if not PH.has(p):
		return false
	var k: String = PH[p].k
	return k == "v" or k == "g" or k == "n" or PH[p].get("vd", false)


static func is_sonorant(p: String) -> bool:
	if not PH.has(p):
		return false
	var k: String = PH[p].k
	return k == "v" or k == "g" or k == "n"


# ---------------------------------------------------------------- lexicon

## "b1F" -> [["AE", 1], ["SH", 0]]
static func _decode_lex(code: String) -> Array:
	var out := []
	var i := 0
	while i < code.length():
		var p: String = PHONES[CODES.find(code[i])]
		var st := 0
		if i + 1 < code.length() and (code[i + 1] == "1" or code[i + 1] == "2"):
			st = int(code[i + 1])
			i += 1
		out.append([p, st])
		i += 1
	return out


static func _parse_arpa(s: String) -> Array:
	var out := []
	for t in s.split(" ", false):
		var digits := ""
		var letters := ""
		for c in t:
			if c >= "0" and c <= "9":
				digits += c
			else:
				letters += c
		out.append([letters, int(digits) if digits != "" else 0])
	return out


static func _is_v_letter(c: String) -> bool:
	return "aeiouy".contains(c)


static func _ctx_match(ctx: String, w: String, i: int, forward: bool) -> bool:
	if ctx == "":
		return true
	var toks := ctx.replace(" ", "")
	var k := i
	for n in toks.length():
		var t := toks[n] if forward else toks[toks.length() - 1 - n]
		if t == "$":
			if k != w.length():
				return false
			continue
		if t == "^":
			if k != -1:
				return false
			continue
		if k < 0 or k >= w.length():
			return false
		var c := w[k]
		if t == "V":
			if not _is_v_letter(c):
				return false
		elif t == "C":
			if _is_v_letter(c) or c < "a" or c > "z":
				return false
		elif t == "+":
			if not "eiy".contains(c):
				return false
		elif t != c:
			return false
		k += 1 if forward else -1
	return true


static func spell(word: String) -> Array:
	var w := ""
	for c in word:
		if c >= "a" and c <= "z":
			w += c
	w = _re_dbl.sub(w, "$1", true)
	var out := []
	var i := 0
	while i < w.length():
		var hit: Array = []
		for r in LTS:
			if w.substr(i, r[1].length()) != r[1]:
				continue
			if not _ctx_match(r[0], w, i - 1, false):
				continue
			if not _ctx_match(r[2], w, i + r[1].length(), true):
				continue
			hit = r
			break
		if hit.is_empty():
			i += 1
			continue
		if hit[3] != "":
			for p in hit[3].split(" "):
				out.append([p, 0])
		i += hit[1].length()
	# stress the first vowel
	var first := -1
	for k in out.size():
		if is_vowel(out[k][0]):
			first = k
			break
	if first >= 0:
		out[first][1] = 1
	elif out.size():
		out.append(["AH", 1])
	return out


static func _known(w: String) -> bool:
	return _custom_has(w) or LEX.has(w)


static func lookup(word: String) -> Array:
	var w := word.to_lower()
	var custom := _custom_get(w)
	if custom != "":
		return _parse_arpa(custom)
	if LEX.has(w):
		return _decode_lex(LEX[w])
	if w.ends_with("'s") and w.length() > 2:
		var b := lookup(w.substr(0, w.length() - 2))
		if b.is_empty():
			return b
		var last: String = b[b.size() - 1][0]
		if last in ["S", "Z", "SH", "CH", "JH", "ZH"]:
			b.append(["IH", 0])
		b.append(["Z" if is_voiced(last) else "S", 0])
		return b
	if not LEX.is_empty():
		# compounds: hiveship = hive + ship
		for k in range(w.length() - 3, 2, -1):
			var a := w.substr(0, k)
			var bb := w.substr(k)
			if _known(a) and _known(bb):
				var pb := []
				for x in lookup(bb):
					pb.append([x[0], 2 if x[1] == 1 else x[1]])
				return lookup(a) + pb
	return spell(w)


# ---------------------------------------------------------------- text

static func number_words(n: int) -> String:
	if n < 20:
		return ONES[n]
	if n < 100:
		return TENS[n / 10] + (" " + ONES[n % 10] if n % 10 else "")
	if n < 1000:
		return ONES[n / 100] + " hundred" + (" and " + number_words(n % 100) if n % 100 else "")
	if n < 1000000:
		var rest := ""
		if n % 1000:
			rest = (" and " if n % 1000 < 100 else " ") + number_words(n % 1000)
		return number_words(n / 1000) + " thousand" + rest
	return number_words(n / 1000000) + " million" + (" " + number_words(n % 1000000) if n % 1000000 else "")


static func _blank(c: String) -> bool:
	return c == " " or c == "\t" or c == "\n" or c == "\r" or c == "\f"


## Text into tokens: words (with their place in the original text) and breaks.
static func tokenize(text: String) -> Array:
	var toks := []
	for m in _re_tok.search_all(text):
		var at := m.get_start(0)
		if m.get_start(1) >= 0:
			# [B R AE1 N AH0 K]: spell a word out in phonemes (ARPAbet)
			toks.append({"w": m.get_string(1), "ph": m.get_string(1).strip_edges(), "at": at, "len": m.get_string(0).length()})
		elif m.get_start(2) >= 0:
			var s2 := m.get_string(2)
			var pct := s2.ends_with("%")
			var num := s2.replace(",", "").replace("%", "")
			var parts := num.split(".")
			var words := number_words(int(parts[0]))
			if parts.size() > 1 and parts[1] != "":
				var ds := []
				for d in parts[1]:
					ds.append(ONES[int(d)])
				words += " point " + " ".join(ds)
			if pct:
				words += " percent"
			# "-5" reads "minus five" when it follows a space or starts the text
			if at > 0 and text[at - 1] == "-" and (at < 2 or _blank(text[at - 2])):
				words = "minus " + words
			var k := 0
			for w in words.split(" "):
				toks.append({"w": w, "at": at, "len": s2.length() if k == 0 else 0})
				k += 1
		elif m.get_start(3) >= 0:
			var w := m.get_string(3)
			while w.ends_with("'"):
				w = w.left(-1)
			toks.append({"w": w, "at": at, "len": m.get_string(3).length()})
		else:
			var p := m.get_string(4).strip_edges()
			var kind := ";"
			if p == "?" or p.ends_with("?"):
				kind = "?"
			elif p == "!" or p.ends_with("!"):
				kind = "!"
			elif p == "..." or p == "…":
				kind = "..."
			elif p.begins_with("."):
				kind = "."
			elif p == ",":
				kind = ","
			elif p == "—" or p == "--" or p == "-":
				kind = "—"
			toks.append({"brk": kind, "at": at})
	return toks


# ---------------------------------------------------------------- prosody

## Text into segments with durations (ms), word timings and phrases for the pitch contour.
static func plan(text: String, voice: Dictionary) -> Dictionary:
	var toks := tokenize(text)
	if toks.is_empty() or not toks[toks.size() - 1].has("brk"):
		toks.append({"brk": ".", "at": text.length()})
	var phrases := []
	var cur := {"words": []}
	for t in toks:
		if t.has("brk"):
			if cur.words.size():
				cur["brk"] = t.brk
				phrases.append(cur)
			cur = {"words": []}
		else:
			cur.words.append(t)
	var rate: float = voice.get("rate", 1.0)
	var segs := []
	var words := []
	var accents := []
	var t := 60.0          # lead-in ms
	for pi in phrases.size():
		var ph: Dictionary = phrases[pi]
		var ph_start := t
		var p_segs := []
		for wi in ph.words.size():
			var tok: Dictionary = ph.words[wi]
			var fn: bool = _fn_words.has(tok.w.to_lower())
			var raw := _parse_arpa(tok.ph) if tok.has("ph") else lookup(tok.w)
			var pr := []
			for x in raw:
				if PH.has(x[0]):
					# reduce unstressed AH to schwa, mark function words weak
					pr.append(["AX" if x[0] == "AH" and x[1] == 0 else x[0], 0 if fn else x[1]])
			if not fn:
				var has1 := false
				for x in pr:
					if x[1] == 1:
						has1 = true
				if not has1:
					for x in pr:
						if is_vowel(x[0]):
							x[1] = 1
							break
			var n_v := 0
			for x in pr:
				if is_vowel(x[0]):
					n_v += 1
			var wrec := {"text": tok.w, "at": tok.at, "len": tok.len, "segs": []}
			words.append(wrec)
			for k in pr.size():
				var seg := {"p": pr[k][0], "stress": pr[k][1], "fn": fn, "word": words.size() - 1, "nV": n_v,
					"phrase": pi, "post": 0.0}
				p_segs.append(seg)
				wrec.segs.append(seg)
		# flaps: T or D between a vowel and an unstressed vowel
		for k in range(1, p_segs.size() - 1):
			var s: Dictionary = p_segs[k]
			if (s.p == "T" or s.p == "D") and is_vowel(p_segs[k - 1].p) and is_vowel(p_segs[k + 1].p) and p_segs[k + 1].stress == 0 and voice.get("flap", true) != false:
				s.p = "DX"
		# last syllable of the phrase: from its vowel onward
		var last_v := -1
		for k in range(p_segs.size() - 1, -1, -1):
			if is_vowel(p_segs[k].p):
				last_v = k
				break
		# durations (Klatt-style rules, simplified)
		for k in p_segs.size():
			var s: Dictionary = p_segs[k]
			var d: Array = PH[s.p].d
			var pct := 1.0
			var nx: Variant = p_segs[k + 1] if k + 1 < p_segs.size() else null
			var pv: Variant = p_segs[k - 1] if k > 0 else null
			if is_vowel(s.p):
				if s.stress == 0:
					pct *= 0.55
				elif s.stress == 2:
					pct *= 0.8
				if s.nV > 1:
					pct *= 0.82
				if s.fn:
					pct *= 0.6
				if nx and nx.word == s.word:
					pct *= 1.1 if is_voiced(nx.p) else 0.8
				if nx and nx.word == s.word and not is_sonorant(nx.p) and not is_voiced(nx.p) and s.stress == 1:
					pct *= 0.9
			else:
				if (pv and not is_vowel(pv.p) and pv.word == s.word) or (nx and not is_vowel(nx.p) and nx.word == s.word):
					pct *= 0.75
				if s.fn:
					pct *= 0.8
			if k >= last_v and last_v >= 0:
				pct *= 1.35
			s["dur"] = (d[1] + (d[0] - d[1]) * pct) / rate
			if s.p == "DX":
				s.dur = 22.0 / rate
		# stops: aspirated release before a vowel/sonorant unless after S
		for k in p_segs.size():
			var s: Dictionary = p_segs[k]
			var def: Dictionary = PH[s.p]
			if def.k != "s" and def.k != "a":
				continue
			var nx: Variant = p_segs[k + 1] if k + 1 < p_segs.size() else null
			var pv: Variant = p_segs[k - 1] if k > 0 else null
			var vd: bool = def.get("vd", false)
			var release := 1.0 if (nx == null or is_sonorant(nx.p) or nx.p == "HH" or PH[nx.p].k == "f") else 0.4
			if nx == null:
				release = TUNE.finalRelease    # phrase final: softer release
			if def.get("flap", false):
				release = 0.0
			if nx and (PH[nx.p].k == "s" or PH[nx.p].k == "a") and nx.word == s.word:
				release = 0.0                  # "act": unreleased
			s["release"] = release
			var place := 0.0 if s.p == "CH" or s.p == "JH" else (18.0 if s.p == "K" or s.p == "G" else (11.0 if s.p == "T" or s.p == "D" else 7.0))
			s["burst"] = place if release > 0 else 0.0
			var asp := 0.0
			if not vd and nx and is_sonorant(nx.p) and not (pv and pv.p == "S" and pv.word == s.word):
				asp = (TUNE.asp if nx.stress == 1 else TUNE.aspWeak) / rate
			if nx == null and not vd:
				asp = TUNE.finalAsp
			if not vd and release > 0 and asp == 0.0:
				asp = 12.0
			s["aspirate"] = asp
			s.post = s.burst + asp
		for s in p_segs:
			s["start"] = t
			t += s.dur + s.post
			segs.append(s)
		for w in words:
			if w.segs.size() and not w.has("start"):
				w["start"] = w.segs[0].start
				var l: Dictionary = w.segs[w.segs.size() - 1]
				w["end"] = l.start + l.dur + l.post
		# pitch: accents on stressed syllables of content words
		var acc := []
		for s in p_segs:
			if is_vowel(s.p) and s.stress == 1 and not s.fn:
				acc.append(s)
		accents.append({"start": ph_start, "end": t, "brk": ph.brk, "acc": acc})
		t += PAUSE.get(ph.brk, 200) / sqrt(rate) * (0.4 if pi == phrases.size() - 1 else 1.0)
	return {"segs": segs, "words": words, "phrases": accents, "total": t + 80}


## f0 anchors [ms, Hz]: a declining line per phrase, accent peaks, then a fall (statement), rise
## (question) or small rise (more to come).
static func pitch_contour(P: Dictionary, voice: Dictionary) -> Array:
	var pts := []
	var base: float = voice.f0
	var rng: float = voice.get("range", 1.0)
	var mono: float = voice.get("monotone", 0.0)
	for ph in P.phrases:
		var T := maxf(1.0, ph.end - ph.start)
		var top := base * (1 + 0.1 * rng)
		var bot := base * (1 - 0.1 * rng)
		var line_at := func(tt: float) -> float: return top + (bot - top) * ((tt - ph.start) / T)
		pts.append([ph.start, line_at.call(ph.start)])
		for i in ph.acc.size():
			var s: Dictionary = ph.acc[i]
			var mid: float = s.start + s.dur * 0.5
			var h := 0.22 * rng * (1.15 if i == 0 else 0.9)
			if i == ph.acc.size() - 1 and (ph.brk == "." or ph.brk == "!"):
				h *= 1.5 if ph.brk == "!" else 1.2
			pts.append([s.start, line_at.call(s.start) * (1 + h * 0.4)])
			pts.append([mid, line_at.call(mid) * (1 + h)])
			pts.append([s.start + s.dur, line_at.call(s.start + s.dur) * (1 + h * 0.45)])
		var e: float = ph.end
		if ph.brk == "?":
			pts.append([e - 120, line_at.call(e - 120)])
			pts.append([e, base * (1 + 0.35 * rng)])
		elif ph.brk == "," or ph.brk == ";" or ph.brk == "—":
			pts.append([e - 80, line_at.call(e - 80)])
			pts.append([e, base * (1 + 0.08 * rng)])
		else:
			pts.append([e, base * (1 - 0.22 * rng)])
	pts = _stable_sort(pts)
	if mono:
		for p in pts:
			p[1] = base + (p[1] - base) * (1 - mono)
	return pts


## Sorts [t, ...] rows by t, keeping equal times in order (JS sort is stable; Godot's isn't).
static func _stable_sort(rows: Array) -> Array:
	var idx := []
	for i in rows.size():
		idx.append([rows[i][0], i])
	idx.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out := []
	for x in idx:
		out.append(rows[x[1]])
	return out


# ---------------------------------------------------------------- tracks

## A list of [ms, value] anchors, read by linear interpolation (reads must move forward in time).
class Track:
	var t := PackedFloat64Array()
	var v := PackedFloat64Array()
	var k := 0
	var _rows := []

	func add(tt: float, vv: float) -> void:
		_rows.append([tt, vv])

	func done() -> Track:
		var rows := RetroTTSEngine._stable_sort(_rows)
		t.resize(rows.size())
		v.resize(rows.size())
		for i in rows.size():
			t[i] = rows[i][0]
			v[i] = rows[i][1]
		_rows = []
		k = 0
		return self

	func empty() -> bool:
		return t.is_empty() and _rows.is_empty()

	func at(tt: float) -> float:
		var n := t.size()
		if n == 0:
			return 0.0
		if tt <= t[0]:
			return v[0]
		if tt >= t[n - 1]:
			return v[n - 1]
		while k > 0 and t[k] > tt:
			k -= 1
		while k < n - 2 and t[k + 1] <= tt:
			k += 1
		var a := t[k]
		var b := t[k + 1]
		return v[k] + (v[k + 1] - v[k]) * (tt - a) / (b - a) if b > a else v[k + 1]


static func _db(x: float) -> float:
	return pow(10.0, (x - 60) / 20.0) if x > 0 else 0.0


const AMPS := ["AV", "AH", "AF", "A2", "A3", "A4", "A5", "A6", "AB", "NZ", "NA"]
const FR_NAMES := ["A2", "A3", "A4", "A5", "A6", "AB"]


static func _vowel_after(segs: Array, k: int) -> Variant:
	for j in range(k + 1, segs.size()):
		if segs[j].phrase != segs[k].phrase:
			break
		if is_vowel(segs[j].p):
			return segs[j]
	return null


static func _vowel_before(segs: Array, k: int) -> Variant:
	for j in range(k - 1, -1, -1):
		if segs[j].phrase != segs[k].phrase:
			break
		if is_vowel(segs[j].p):
			return segs[j]
	return null


static func _fric(frs: Array, gain: float, extra: Dictionary) -> Dictionary:
	var v := {"AF": 1.0}
	v.merge(extra, true)
	for i in 6:
		if frs[i]:
			v[FR_NAMES[i]] = _db(frs[i]) * gain
	return v


## Every synthesis parameter track from the plan.
static func build_tracks(P: Dictionary, voice: Dictionary) -> Dictionary:
	var segs: Array = P.segs
	var tr := {}
	for n in ["F1", "F2", "F3", "B1", "B2", "B3"] + AMPS:
		tr[n] = Track.new()
	# formant targets per segment: start and end
	for k in segs.size():
		var s: Dictionary = segs[k]
		var p: String = s.p
		var def: Dictionary = PH[p]
		if def.k == "a":
			def = PH["SH" if p == "CH" else "ZH"]
		var f: Array = def.f.duplicate()
		var b: Array = def.b.duplicate()
		var e: Array = PH[p].get("e", def.f).duplicate()
		if p == "HH" or p == "DX":
			var nx: Variant = segs[k + 1] if k + 1 < segs.size() and segs[k + 1].phrase == s.phrase and is_sonorant(segs[k + 1].p) else null
			var v: Variant = nx if nx else _vowel_after(segs, k)
			if v == null:
				v = _vowel_before(segs, k)
			if v and p == "HH":
				f = PH[v.p].f.duplicate()
				b = []
				for x in PH[v.p].b:
					b.append(x * 2.5)
				e = f.duplicate()
		if p == "K" or p == "G" or p == "NG":
			# velar locus follows the neighbouring vowel
			var v: Variant = _vowel_after(segs, k)
			if v == null:
				v = _vowel_before(segs, k)
			var f2: float = PH[v.p].f[1] if v else 1600.0
			f[1] = maxf(1350, minf(2300, f2 + 250))
			e[1] = f[1]
			f[2] = maxf(f[1] + 400, def.f[2])
			e[2] = f[2]
		s["Fs"] = f
		s["Fe"] = e
		s["B"] = b
	# formant anchors: targets inside each segment, blended values at boundaries
	for k in segs.size():
		var s: Dictionary = segs[k]
		var is_diph: bool = PH[s.p].has("e")
		var obst := not is_sonorant(s.p)
		var tin := minf(15.0 if obst else (45.0 if is_vowel(s.p) else 30.0), s.dur * (0.3 if is_diph else 0.45))
		var tout := minf(15.0 if obst else (40.0 if is_vowel(s.p) else 30.0), s.dur * (0.12 if is_diph else 0.45))
		var a: float = s.start
		var z: float = s.start + s.dur
		for i in 3:
			var F: Track = tr["F%d" % (i + 1)]
			var B: Track = tr["B%d" % (i + 1)]
			F.add(a + tin, s.Fs[i])
			if is_diph:
				F.add(a + s.dur * 0.35, s.Fs[i])
				F.add(a + s.dur * 0.85, s.Fe[i])
			F.add(z - tout, s.Fe[i])
			B.add(a + tin, s.B[i])
			B.add(z - tout, s.B[i])
		if k + 1 < segs.size() and segs[k + 1].phrase == s.phrase:
			var nx: Dictionary = segs[k + 1]
			# boundary value: a locus blend when an obstruent meets a sonorant
			var s_obs: bool = not is_sonorant(s.p) and s.p != "HH"
			var n_obs: bool = not is_sonorant(nx.p) and nx.p != "HH"
			for i in 3:
				var A: float = s.Fe[i]
				var Bv: float = nx.Fs[i]
				var bv: float
				if s_obs and not n_obs:
					bv = A + (Bv - A) * (0.3 if i == 0 else 0.55)
				elif not s_obs and n_obs:
					bv = Bv + (A - Bv) * (0.3 if i == 0 else 0.55)
				else:
					bv = (A + Bv) / 2
				var bt: float = s.start + s.dur + s.post
				var F: Track = tr["F%d" % (i + 1)]
				if s.post:
					# formants move toward the vowel during burst and aspiration
					F.add(s.start + s.dur, bv)
					F.add(bt, Bv + (bv - Bv) * 0.4)
				else:
					F.add(bt, bv)

	# Source and frication amplitudes. Each segment is cut into parts (closure, burst, aspiration...)
	# holding constant values; neighbouring parts crossfade over their ramps. Unset values are zero.
	var vbar: float = voice.get("voicebar", 0.22)
	var parts := []
	var part := func(t0: float, t1: float, v: Dictionary, ramp: float) -> void:
		if t1 > t0:
			parts.append([t0, t1, v, ramp])
	for k in segs.size():
		var s: Dictionary = segs[k]
		var def: Dictionary = PH[s.p]
		var a: float = s.start
		var z: float = s.start + s.dur
		var nx: Variant = segs[k + 1] if k + 1 < segs.size() else null
		var pv: Variant = segs[k - 1] if k > 0 else null
		var pv_voiced: bool = pv != null and pv.phrase == s.phrase and is_voiced(pv.p)
		var stress_gain := 1.0
		if is_vowel(s.p):
			stress_gain = 1.0 if s.stress == 1 else (0.85 if s.stress == 2 else 0.7)
		var vd: bool = def.get("vd", false)
		match def.k:
			"v", "g", "n":
				var v := {"AV": def.get("av", 1.0) * stress_gain}
				if def.k == "n":
					v["NZ"] = 1.0
				elif is_vowel(s.p) and ((nx and PH[nx.p].k == "n") or (pv and PH[pv.p].k == "n")):
					v["NA"] = 0.25
				part.call(a, z, v, 10.0)
			"h":
				part.call(a, z, {"AH": 0.7}, 10.0)
			"f":
				part.call(a, z, _fric(def.fr, 1.0, {"AV": 0.28} if vd else {}), 12.0)
			"s", "a":
				if def.get("flap", false):
					part.call(a, z, {"AV": 0.45}, 6.0)
					continue
				var is_aff: bool = def.k == "a"
				var st: Dictionary = PH["T" if s.p == "CH" else "D"] if is_aff else def
				var clo: float = s.dur * 0.4 if is_aff else s.dur
				part.call(a, a + clo, {"AV": vbar} if vd and pv_voiced else {}, 6.0)
				if is_aff:
					part.call(a + clo, z + s.post, _fric(PH["SH"].fr, 0.8 if vd else 1.0, {"AV": 0.3} if vd else {}), 6.0)
				else:
					var b0 := z
					var b1: float = z + s.burst
					part.call(b0, b1, _fric(st.fr, TUNE.burst * s.release * (0.6 if vd else 1.0), {"AV": 0.25} if vd else {}), 1.5)
					if s.aspirate:
						part.call(b1, b1 + s.aspirate, {"AH": 1.1, "AF": 0.4, "AB": 0.03}, 5.0)
	parts = _stable_sort(parts)
	# silence in the gaps (pauses between phrases)
	var all := []
	var last := 0.0
	for p in parts:
		if p[0] > last + 1:
			all.append([last, p[0], {}, 8.0])
		all.append(p)
		last = maxf(last, p[1])
	all.append([last, last + 400, {}, 8.0])
	for row in all:
		var t0: float = row[0]
		var t1: float = row[1]
		var v: Dictionary = row[2]
		var r := minf(row[3], (t1 - t0) / 2 - 0.01)
		for n in AMPS:
			var val: float = v.get(n, 0.0)
			tr[n].add(t0 + r, val)
			tr[n].add(t1 - r, val)
	for n in tr:
		tr[n].done()
	# segments with no anchor on a track read as zero, so pad amplitude tracks
	for n in AMPS:
		if tr[n].t.is_empty():
			tr[n].add(0, 0)
			tr[n].done()
	return tr


# ---------------------------------------------------------------- synthesiser

## xorshift32, the engine.js generator (same sequence for the same seed)
class Rng:
	var s := 1

	func _init(seed_: int) -> void:
		s = seed_ & M32
		if s == 0:
			s = 1

	func next() -> float:
		s ^= (s << 13) & M32
		s ^= s >> 17
		s ^= (s << 5) & M32
		s &= M32
		return s / 4294967296.0


static func hash_str(str_: String) -> int:
	var h := 2166136261
	for i in str_.length():
		h ^= str_.unicode_at(i)
		h = (h * 16777619) & M32
	return h


## A 2-pole resonator's coefficients [a, b, c].
static func _reso(f: float, bw: float) -> Array:
	var r := exp(-PI * bw / SR)
	var c := -r * r
	var b := 2 * r * cos(TAU * f / SR)
	return [1 - b - c, b, c]


## Constant-peak band-pass coefficients [b0, a1, a2].
static func _bp(f: float, bw: float) -> Array:
	f = minf(f, SR * 0.47)
	var w := TAU * f / SR
	var al := sin(w) * bw / (2 * f)
	var a0 := 1 + al
	return [al / a0, -2 * cos(w) / a0, (1 - al) / a0]


static func synth(P: Dictionary, voice: Dictionary, seed_: int) -> PackedFloat32Array:
	var tr := build_tracks(P, voice)
	var f0 := Track.new()
	for p in pitch_contour(P, voice):
		f0.add(p[0], p[1])
	f0.done()
	var n := ceili(P.total / 1000.0 * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var rnd := Rng.new(seed_)
	var fs: float = voice.get("formant", 1.0)
	var bs: float = voice.get("bw", 1.0)
	var F4 := 3300 * fs
	var F5 := 3850 * fs
	var F6 := 5400 * sqrt(fs)
	# cascade: R0..R4 (R3, R4 fixed), nasal pole NP and zero NZ
	var c3 := _reso(minf(F4, SR * 0.45), 250 * bs)
	var c4 := _reso(minf(F5, SR * 0.46), 300 * bs)
	var np := _reso(270, 100)
	var r0a := 0.0; var r0b := 0.0; var r0c := 0.0; var r0y1 := 0.0; var r0y2 := 0.0
	var r1a := 0.0; var r1b := 0.0; var r1c := 0.0; var r1y1 := 0.0; var r1y2 := 0.0
	var r2a := 0.0; var r2b := 0.0; var r2c := 0.0; var r2y1 := 0.0; var r2y2 := 0.0
	var r3a: float = c3[0]; var r3b: float = c3[1]; var r3c: float = c3[2]; var r3y1 := 0.0; var r3y2 := 0.0
	var r4a: float = c4[0]; var r4b: float = c4[1]; var r4c: float = c4[2]; var r4y1 := 0.0; var r4y2 := 0.0
	var npa: float = np[0]; var npb: float = np[1]; var npc: float = np[2]; var npy1 := 0.0; var npy2 := 0.0
	var nza := 1.0; var nzb := 0.0; var nzc := 0.0; var nzx1 := 0.0; var nzx2 := 0.0
	# parallel band-passes: [b0, a1, a2, x1, x2, y1, y2] x 5
	var pb := PackedFloat64Array()
	pb.resize(35)
	var oq: float = voice.get("oq", 0.6)
	var tilt: float = voice.get("tilt", 0.25)
	var breath: float = voice.get("breath", 0.0)
	var jit: float = voice.get("jitter", 0.0)
	var shim: float = voice.get("shimmer", 0.0)
	var sub: float = voice.get("sub", 0.0)
	var src: String = voice.get("source", "glottal")
	var duty: float = voice.get("duty", 0.3)
	var whisper: bool = voice.get("whisper", false)
	var vib: Dictionary = voice.get("vibrato", {})
	var flutter: float = voice.get("flutter", 0.0)
	var asp_g := 0.3
	var fric_g := 2.5
	var phase := 0.0
	var period := 0.0
	var cur_f0: float = voice.f0
	var pulse_amp := 1.0
	var pulse_n := 0
	var tilt_y := 0.0
	var AV := 0.0; var AH := 0.0; var AF := 0.0
	var A0 := 0.0; var A1 := 0.0; var A2 := 0.0; var A3 := 0.0; var A4 := 0.0; var A5 := 0.0
	var tF1: Track = tr.F1; var tF2: Track = tr.F2; var tF3: Track = tr.F3
	var tB1: Track = tr.B1; var tB2: Track = tr.B2; var tB3: Track = tr.B3
	var tAV: Track = tr.AV; var tAH: Track = tr.AH; var tAF: Track = tr.AF
	var tA2: Track = tr.A2; var tA3: Track = tr.A3; var tA4: Track = tr.A4; var tA5: Track = tr.A5
	var tA6: Track = tr.A6; var tAB: Track = tr.AB; var tNZ: Track = tr.NZ; var tNA: Track = tr.NA
	for i in n:
		if i % FRAME == 0:
			var t := i / float(SR) * 1000.0
			var f1 := tF1.at(t) * fs
			var f2 := tF2.at(t) * fs
			var f3 := tF3.at(t) * fs
			var nasal := tNZ.at(t)
			var nas_a := tNA.at(t)
			var n1 := maxf(nasal, nas_a)
			# nasal murmur: low F1 with a pole/zero pair; the zero sits on the pole when oral
			var c := _reso(f1 * (1 - 0.35 * nasal), tB1.at(t) * bs * (1 + n1))
			r0a = c[0]; r0b = c[1]; r0c = c[2]
			c = _reso(f2, tB2.at(t) * bs)
			r1a = c[0]; r1b = c[1]; r1c = c[2]
			c = _reso(f3, tB3.at(t) * bs)
			r2a = c[0]; r2b = c[1]; r2c = c[2]
			c = _reso(270 + 180 * n1 * fs + 200 * nasal, 100)
			nza = 1.0 / c[0]; nzb = -c[1] / c[0]; nzc = -c[2] / c[0]
			AV = tAV.at(t); AH = tAH.at(t); AF = tAF.at(t)
			A0 = tA2.at(t); A1 = tA3.at(t); A2 = tA4.at(t); A3 = tA5.at(t); A4 = tA6.at(t); A5 = tAB.at(t)
			var fb := [[f2, 250.0], [f3, 320.0], [F4, 350.0], [minf(F5 * 1.05, 4300 * fs), 600.0], [F6, 1800.0]]
			for q in 5:
				var bc := _bp(fb[q][0], fb[q][1])
				pb[q * 7] = bc[0]; pb[q * 7 + 1] = bc[1]; pb[q * 7 + 2] = bc[2]
			var fz := f0.at(t)
			if not vib.is_empty():
				fz *= 1 + vib.depth * sin(TAU * vib.rate * t / 1000)
			cur_f0 = fz
		# glottal source
		var g := 0.0
		if period <= 0 or phase >= 1:
			phase = phase - 1 if phase >= 1 else 0.0
			var f := cur_f0 * (1 + ((rnd.next() - 0.5) * 2 * jit if jit else 0.0))
			if flutter:
				f *= 1 + flutter * (rnd.next() - 0.5)
			period = SR / maxf(30, f)
			pulse_n += 1
			pulse_amp = 1 + ((rnd.next() - 0.5) * 2 * shim if shim else 0.0)
			if sub and pulse_n % 2:
				pulse_amp *= 1 - sub
		if src == "glottal":
			if phase < oq:
				var x := phase / oq
				g = (2 * x - 3 * x * x) * 3
			tilt_y += (g - tilt_y) * (1 - tilt)
			g = tilt_y
		elif src == "saw":
			g = (1 - 2 * phase) * 0.9
		elif src == "pulse":
			g = (1.0 if phase < duty else -duty / (1 - duty)) * 0.9
		elif src == "tri":
			g = (4 * phase - 1 if phase < 0.5 else 3 - 4 * phase) * 0.8
		g *= pulse_amp
		phase += 1 / period
		var nz := rnd.next() * 2 - 1
		var open := 1.0 if phase < oq else 0.35
		var exc: float
		if whisper:
			exc = nz * (AV * 0.9 + AH) * asp_g * 2.2
		else:
			exc = g * AV + nz * asp_g * (AH + AV * breath * open)
		# nasal pole, nasal zero, then the five cascade formants
		var y := npa * exc + npb * npy1 + npc * npy2
		npy2 = npy1; npy1 = y
		var yz := nza * y + nzb * nzx1 + nzc * nzx2
		nzx2 = nzx1; nzx1 = y; y = yz
		var y0 := r0a * y + r0b * r0y1 + r0c * r0y2
		r0y2 = r0y1; r0y1 = y0
		var y1 := r1a * y0 + r1b * r1y1 + r1c * r1y2
		r1y2 = r1y1; r1y1 = y1
		var y2 := r2a * y1 + r2b * r2y1 + r2c * r2y2
		r2y2 = r2y1; r2y1 = y2
		var y3 := r3a * y2 + r3b * r3y1 + r3c * r3y2
		r3y2 = r3y1; r3y1 = y3
		var y4 := r4a * y3 + r4b * r4y1 + r4c * r4y2
		r4y2 = r4y1; r4y1 = y4
		# parallel frication
		var p := 0.0
		if AF > 0.001:
			var fnz := nz * fric_g * AF
			var amps := [A0, -A1, A2, -A3, A4]
			for q in 5:
				var o := q * 7
				var yq := pb[o] * (fnz - pb[o + 4]) - pb[o + 1] * pb[o + 5] - pb[o + 2] * pb[o + 6]
				pb[o + 4] = pb[o + 3]; pb[o + 3] = fnz; pb[o + 6] = pb[o + 5]; pb[o + 5] = yq
				p += amps[q] * yq
			p += A5 * fnz * 0.5
		elif pb[5] != 0:
			for q in 5:
				var o := q * 7
				pb[o + 3] = 0; pb[o + 4] = 0; pb[o + 5] = 0; pb[o + 6] = 0
		out[i] = y4 * 0.5 + p
	return out


# ---------------------------------------------------------------- SNES voice chain

static func _jround(x: float) -> float:
	return floorf(x + 0.5)


## A 4-bit BRR round trip: each 16-sample block takes the filter and shift with the least error. The
## search tries the shifts around the one the block's open-loop residual needs (the prototype tries all
## 13; the result is the same or within a step, and it's several times faster in GDScript).
static func brr(pcm: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(pcm.size())
	var p1 := 0.0
	var p2 := 0.0
	var dec := PackedFloat32Array()
	dec.resize(16)
	var best := PackedFloat32Array()
	best.resize(16)
	var x := PackedFloat32Array()
	x.resize(16)
	var b := 0
	while b < pcm.size():
		for i in 16:
			x[i] = pcm[b + i] * BRR_SCALE if b + i < pcm.size() else 0.0
		var best_err := INF
		var b1 := 0.0
		var b2 := 0.0
		for f in 4:
			var c1: float = BRR_FILTERS[f][0]
			var c2: float = BRR_FILTERS[f][1]
			# open-loop residual size picks the shift to start from
			var q1 := p1
			var q2 := p2
			var m := 0.0
			for i in 16:
				m = maxf(m, absf(x[i] - (q1 * c1 + q2 * c2)))
				q2 = q1
				q1 = x[i]
			var sh0 := 0
			while sh0 < 12 and (1 << sh0) / 2.0 * 7.5 < m:
				sh0 += 1
			for sh in range(maxi(0, sh0 - 1), mini(12, sh0 + 1) + 1):
				var step := (1 << sh) / 2.0
				q1 = p1
				q2 = p2
				var err := 0.0
				for i in 16:
					var pred := q1 * c1 + q2 * c2
					var nn := _jround((x[i] - pred) / step)
					nn = clampf(nn, -8, 7)
					var yv := clampf(pred + nn * step, -32768, 32767)
					yv = float(int(yv))
					err += (x[i] - yv) * (x[i] - yv)
					if err >= best_err:
						break
					dec[i] = yv
					q2 = q1
					q1 = yv
				if err < best_err:
					best_err = err
					for i in 16:
						best[i] = dec[i]
					b1 = q1
					b2 = q2
		for i in 16:
			if b + i < pcm.size():
				out[b + i] = best[i] / BRR_SCALE
		p1 = b1
		p2 = b2
		b += 16
	return out


## Windowed-sinc resample (used once, to make the "recorded" sample). The kernel is tabulated at 64
## phases per input sample.
static func resample(x: PackedFloat32Array, from: int, to: int) -> PackedFloat32Array:
	if from == to:
		return x
	var ratio := float(to) / from
	var n := int(floorf(x.size() * ratio))
	var out := PackedFloat32Array()
	out.resize(n)
	var fc := minf(1.0, ratio) * 0.92
	var half := 8
	var PHS := 64
	var tab := PackedFloat32Array()
	tab.resize(PHS * 2 * half)
	for ph in PHS:
		var sum := 0.0
		for j in 2 * half:
			var d := float(ph) / PHS + half - 1 - j
			var v := (1.0 if d == 0 else sin(PI * fc * d) / (PI * fc * d)) * (0.5 + 0.5 * cos(PI * d / half))
			tab[ph * 2 * half + j] = v
			sum += v
		for j in 2 * half:
			tab[ph * 2 * half + j] /= sum
	var xn := x.size()
	for i in n:
		var c := i / ratio
		var c0 := int(floorf(c))
		var base := int(floorf((c - c0) * PHS)) * 2 * half
		var s := 0.0
		for j in 2 * half:
			var k := c0 - half + 1 + j
			if k >= 0 and k < xn:
				s += x[k] * tab[base + j]
		out[i] = s
	return out


static func _one_pole_hp(buf: PackedFloat32Array, cutoff: float, fs: float) -> void:
	var a := exp(-TAU * cutoff / fs)
	var y := 0.0
	var x1 := 0.0
	for i in buf.size():
		y = a * (y + buf[i] - x1)
		x1 = buf[i]
		buf[i] = y


static func _bandpass(buf: PackedFloat32Array, f: float, q: float, fs: float) -> void:
	var w := TAU * f / fs
	var al := sin(w) / (2 * q)
	var a0 := 1 + al
	var b0 := al / a0
	var a1 := -2 * cos(w) / a0
	var a2 := (1 - al) / a0
	var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
	for i in buf.size():
		var x := buf[i]
		var y := b0 * (x - x2) - a1 * y1 - a2 * y2
		x2 = x1; x1 = x; y2 = y1; y1 = y
		buf[i] = y


static func peak(buf: PackedFloat32Array, from := 0, to := -1) -> float:
	var m := 0.0
	var e := buf.size() if to < 0 else mini(to, buf.size())
	for i in range(maxi(from, 0), e):
		m = maxf(m, absf(buf[i]))
	return m


## Character effects at the synthesis rate, before the sample is "recorded".
static func colour(x: PackedFloat32Array, voice: Dictionary, seed_: int, click_at: Array) -> PackedFloat32Array:
	var fx: Dictionary = voice.get("fx", {})
	if fx.has("double"):
		# a second, detuned voice: hive chorus
		var d: Dictionary = fx.double
		var o := PackedFloat32Array()
		o.resize(x.size())
		var lag := int(_jround(d.ms * SR / 1000.0))
		for i in x.size():
			var j := i - lag - int(_jround(lag * 0.5 * sin(TAU * 0.7 * i / SR)))
			o[i] = x[i] + (x[j] * d.mix if j >= 0 else 0.0)
		x = o
	if fx.has("trem"):
		# wing buzz
		for i in x.size():
			x[i] *= 1 - fx.trem.depth * (0.5 + 0.5 * sin(TAU * fx.trem.rate * i / SR))
	if fx.has("ring"):
		for i in x.size():
			x[i] = x[i] * (1 - fx.ring.mix) + x[i] * sin(TAU * fx.ring.hz * i / SR) * fx.ring.mix * 1.4
	if fx.has("comb"):
		# short resonant tube: metallic, keeps the words
		var d := int(_jround(fx.comb.ms * SR / 1000.0))
		var o := PackedFloat32Array()
		o.resize(x.size())
		for i in x.size():
			o[i] = x[i] + (o[i - d] * fx.comb.fb if i >= d else 0.0)
		x = o
	if fx.has("drive"):
		var m := peak(x)
		if m == 0:
			m = 1
		var k: float = fx.drive
		var norm := tanh(1 + k * 6)
		for i in x.size():
			x[i] = tanh(x[i] / m * (1 + k * 6)) * m / norm
	if fx.has("radio"):
		_one_pole_hp(x, fx.radio[0], SR)
		_bandpass(x, sqrt(fx.radio[0] * fx.radio[1]), 0.5, SR)
	if fx.has("bits"):
		var m := peak(x)
		if m == 0:
			m = 1
		var q := pow(2.0, fx.bits - 1)
		for i in x.size():
			x[i] = _jround(x[i] / m * q) / q * m
	if fx.has("click"):
		# mandible clicks at word starts
		var rnd := Rng.new(seed_ ^ 0x9e37)
		for at in click_at:
			var s0 := int(_jround(at / 1000.0 * SR)) - 160
			if rnd.next() > fx.click:
				continue
			var pk := peak(x, s0 - 400, s0 + 490)
			for i in 90:
				var k := s0 + i
				if k >= 0 and k < x.size():
					x[k] += (rnd.next() * 2 - 1) * exp(-i / 14.0) * 0.5 * pk
	return x


# ---------------------------------------------------------------- loudness (BS.1770, mono into both channels)

static func _biquad(buf: PackedFloat32Array, b0: float, b1: float, b2: float, a1: float, a2: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(buf.size())
	var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
	for i in buf.size():
		var x := buf[i]
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1; x1 = x; y2 = y1; y1 = y
		out[i] = y
	return out


static func _lufs(m: float) -> float:
	return -0.691 + 10 * log(m + 1e-12) / log(10.0)


static func loudness(x: PackedFloat32Array, fs: float) -> float:
	var G := 3.99984385397
	var Q := 0.7071752369554193
	var fc := 1681.9744509555319
	var K := tan(PI * fc / fs)
	var Vh := pow(10.0, G / 20)
	var Vb := pow(Vh, 0.499666774155)
	var a0 := 1 + K / Q + K * K
	var s1 := _biquad(x, (Vh + Vb * K / Q + K * K) / a0, 2 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0)
	Q = 0.5003270373253953
	fc = 38.13547087613982
	K = tan(PI * fc / fs)
	a0 = 1 + K / Q + K * K
	var k := _biquad(s1, 1, -2, 1, 2 * (K * K - 1) / a0, (1 - K / Q + K * K) / a0)
	# block energies from a running sum
	var cum := PackedFloat64Array()
	cum.resize(k.size() + 1)
	for i in k.size():
		cum[i + 1] = cum[i] + k[i] * k[i]
	var blk := int(_jround(0.4 * fs))
	var hop := int(_jround(0.1 * fs))
	var z := []
	var s0 := 0
	while s0 + blk <= k.size():
		z.append(2 * (cum[s0 + blk] - cum[s0]) / blk)
		s0 += hop
	if z.is_empty():
		z.append(2 * cum[k.size()] / maxi(1, k.size()))
	var abs_ := z.filter(func(m): return _lufs(m) > -70)
	if abs_.is_empty():
		return -70.0
	var mean := 0.0
	for m in abs_:
		mean += m
	mean /= abs_.size()
	var rel := abs_.filter(func(m): return _lufs(m) > _lufs(mean) - 10)
	var sum := 0.0
	for m in rel:
		sum += m
	return _lufs(sum / rel.size())


# ---------------------------------------------------------------- public API

## Speaks text in a voice (an id from VOICES or a voice Dictionary). Returns {pcm (mono, 32 kHz), rate,
## words [{text, at, len, start, end}] in seconds, duration}.
## opts: rate and pitch (multipliers), seed (int), hz (recorded sample rate), brr (bool, default true),
## lufs (loudness target, default -16), bits (output bit depth 1..16, default 16 = untouched).
static func say(text: String, voice_id: Variant, opts := {}) -> Dictionary:
	prepare()
	var voice: Dictionary = (VOICES.get(voice_id, VOICES.narrator) if voice_id is String else voice_id).duplicate(true)
	if opts.has("rate"):
		voice["rate"] = voice.get("rate", 1.0) * opts.rate
	if opts.has("pitch"):
		voice["f0"] = voice.f0 * opts.pitch
	var seed_: int = opts.get("seed", hash_str(text))
	var P := plan(text, voice)
	var x := synth(P, voice, seed_)
	var click_at := []
	if voice.has("fx") and voice.fx.has("click"):
		for w in P.words:
			click_at.append(w.get("start", 0.0))
	x = colour(x, voice, seed_, click_at)
	_one_pole_hp(x, 70, SR)
	# "record" the line as a BRR sample at the voice's rate, then play it back through the DSP's
	# Gaussian interpolation at 32 kHz
	var hz: int = opts.get("hz", voice.get("hz", 16000))
	var m := peak(x)
	if m == 0:
		m = 1
	for i in x.size():
		x[i] *= 0.9 / m
	var s := resample(x, SR, hz)
	if opts.get("brr", true):
		s = brr(s)
	var step := float(hz) / RATE
	var n := int(floorf(s.size() / step))
	var echo: Dictionary = voice.get("echo", {"delay": 1, "fb": 0, "vol": 0, "fir": "flat"})
	var tail := int(_jround(echo.delay * 512 * (1 + 6 * echo.fb))) if echo.vol > 0 else 0
	var out := PackedFloat32Array()
	out.resize(n + tail)
	var pos := 0.0
	var sn := s.size()
	for i in n:
		var ip := int(floorf(pos))
		var fr := int(floorf((pos - ip) * 256)) * 4
		var a0 := s[ip - 1] if ip - 1 >= 0 and ip - 1 < sn else 0.0
		var a1 := s[ip] if ip < sn else 0.0
		var a2 := s[ip + 1] if ip + 1 < sn else 0.0
		var a3 := s[ip + 2] if ip + 2 < sn else 0.0
		out[i] = a0 * _gauss[fr] + a1 * _gauss[fr + 1] + a2 * _gauss[fr + 2] + a3 * _gauss[fr + 3]
		pos += step
	# echo unit: delay line, 8-tap FIR, feedback
	if echo.vol > 0:
		var len_ := maxi(1, echo.delay) * 512
		var buf := PackedFloat32Array()
		buf.resize(len_)
		var hist := PackedFloat32Array()
		hist.resize(8)
		var fir := []
		for c in FIR[echo.get("fir", "soft")]:
			fir.append(c / 128.0)
		var e := 0
		var h := 0
		var fb: float = echo.fb
		var vol: float = echo.vol
		for i in out.size():
			var d := buf[e]
			hist[h] = d
			var f := 0.0
			for k in 8:
				f += hist[(h - k + 8) & 7] * fir[k]
			h = (h + 1) & 7
			buf[e] = clampf(out[i] * 0.6 + f * fb, -1, 1)
			e = (e + 1) % len_
			out[i] += f * vol
	# loudness to the shared target, peaks under -1 dBFS
	var target: float = opts.get("lufs", -16.0)
	var g := pow(10.0, (target - loudness(out, RATE)) / 20)
	var pk := peak(out) * g
	var ceil_ := pow(10.0, -1 / 20.0)
	if pk > ceil_:
		# soft-knee limiting on the loud bits rather than turning the whole line down
		for i in out.size():
			var v := out[i] * g
			if absf(v) > 0.7 * ceil_:
				v = signf(v) * (0.7 * ceil_ + 0.3 * ceil_ * tanh((absf(v) - 0.7 * ceil_) / (0.3 * ceil_)))
			out[i] = v
		g = 1.0
	if g != 1.0:
		for i in out.size():
			out[i] *= g
	crush(out, int(opts.get("bits", MAX_BITS)))
	var words := []
	for w in P.words:
		words.append({"text": w.text, "at": w.at, "len": w.len, "start": w.get("start", 0.0) / 1000.0, "end": w.get("end", 0.0) / 1000.0})
	return {"pcm": out, "rate": RATE, "words": words, "duration": out.size() / float(RATE)}


## Quantises samples (full scale -1..1) to a bit depth, in place, like a DAC with fewer bits.
## 16 or more: unchanged. 2..15: 2^bits signed levels, rounded. 1: a one-bit speaker (full on in one
## direction or the other), with near-silence kept silent so pauses stay quiet.
static func crush(pcm: PackedFloat32Array, bits: int) -> void:
	if bits >= MAX_BITS:
		return
	if bits <= 1:
		for i in pcm.size():
			var v := pcm[i]
			pcm[i] = 0.0 if absf(v) < 1.0 / 64 else signf(v) * 0.5
		return
	var q := float(1 << (bits - 1))
	for i in pcm.size():
		pcm[i] = clampf(_jround(pcm[i] * q), -q, q - 1) / q


## Phonemes for display and debugging: "the ship" -> "DH AX | SH IH1 P"
static func phonemize(text: String) -> String:
	prepare()
	var parts := []
	for t in tokenize(text):
		if t.has("brk"):
			parts.append(t.brk)
			continue
		var ps := []
		for x in (_parse_arpa(t.ph) if t.has("ph") else lookup(t.w)):
			ps.append(x[0] + (str(x[1]) if is_vowel(x[0]) and x[1] else ""))
		parts.append(" ".join(ps))
	return " | ".join(parts)
