# Native TTS Studio (Flutter)

A Flutter app focused on **natural on-device text-to-speech** with accent presets and export to both **WAV** and **MP3**.

## Features

- On-device TTS playback (no cloud API required).
- Accent presets for:
  - Nigeria (`en-NG`)
  - US (`en-US`)
  - UK (`en-GB`)
  - South Africa (`en-ZA`)
  - Chinese (`zh-CN`)
- Voice picker for each locale (uses voices exposed by the Android TTS engine).
- Adjustable speed + pitch.
- Export to WAV from native TTS synthesis.
- Convert WAV to MP3 with FFmpeg and share generated files.

## Why this matches your Samsung S22 testing goal

Samsung S22 supports modern Android TTS engines (Samsung/Google). Naturalness depends heavily on installed voice packs. This app lets you pick available installed voices and export them.

## Setup

1. Install Flutter SDK.
2. Run:
   ```bash
   flutter pub get
   flutter run
   ```
3. On device, install or update **Speech Services by Google**.
4. Download offline voices in Android settings for the accents you want.

## Notes

- WAV export is generated directly by the native TTS engine.
- MP3 export is produced locally by converting WAV with FFmpeg.
- If a locale does not have a dedicated installed voice, Android falls back to a default voice.
