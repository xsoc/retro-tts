# Retro TTS addon

Procedural 16-bit era text-to-speech for Godot 4.7, in pure GDScript.

- `retro_tts.gd`: the **RetroTTS** node. `speak()`, `stop()`, signals for every word and sentence.
- `retro_tts_voice.gd`: the **RetroTTSVoice** resource. Every synthesiser knob, editable in the inspector.
- `retro_tts_engine.gd`: **RetroTTSEngine**, the synthesiser itself (static, thread-safe).
- `voices/`: 17 ready-made voices as `.tres` files.
- `data/lexicon.txt`: the pronunciation dictionary (CMUdict, BSD; keep `LICENSE-cmudict.txt` beside it).
- `plugin.gd`, `lexicon_export.gd`: an editor plugin that adds the dictionary to exports.

Full docs, tutorial and a sample project: see the repository's README.md and docs/ folder.
MIT licence (see LICENSE). Copyright (c) 2026 Shonagon Tech.
