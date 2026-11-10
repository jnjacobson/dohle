# sittich

> sittich (German for "parakeet", pronounced /ˈzɪtɪç/)

System-wide voice dictation for macOS, built on [Hammerspoon](https://www.hammerspoon.org): press a hotkey, speak, and the transcript is typed right where your cursor is — in any app. Audio is captured by a tiny bundled Swift recorder, transcribed by OpenAI's `gpt-transcribe`, and pasted via a synthetic ⌘V. No Xcode project, no signing, no app to install: a couple of Lua files and one compiled helper.

## Usage

Press **⌥Space** → recording starts (a floating pill with a live waveform appears in the center of the screen). Press **⌥Space** again → recording stops, the pill switches to a pulsing dot while the audio is transcribed, and the result is pasted at the current text caret. **Esc** aborts while recording or transcribing; at any other time Esc behaves normally. Each step is confirmed by a distinct sound.

## Setup

1. Compile the recorder (once, and after editing `recorder.swift`):

   ```sh
   swiftc -O recorder.swift -o recorder
   ```

2. Put your OpenAI API key in `~/.config/openai/api_key` (single line, `chmod 600`).

3. `~/.hammerspoon/init.lua` loads this file (adjust the path to wherever you cloned the repo):

   ```lua
   dofile(os.getenv("HOME") .. "/path/to/sittich/init.lua")
   ```

4. Reload the Hammerspoon config (menu bar icon → *Reload Config*).

## Permissions

- **Accessibility** — Hammerspoon asks on first launch; needed for the synthetic ⌘V.
- **Microphone** — macOS prompts for Hammerspoon on the first recording.

## Configuration

Copy `config.dist.json` to `config.json` and fill in:

- `microphone` — preferred input device for recording (case-insensitive substring of the device name; `./recorder --list` prints all input devices). Empty or missing = system default. If the default input is unusable (e.g. AirPods busy on another device), the recorder falls back to the built-in mic.
- `languages` — language codes sent as `languages[]` to hint what you speak (e.g. `["de", "en"]`).
- `glossary` — names and technical terms sent as `keywords[]` so the model spells them correctly.

The file is read on every transcription — no reload needed. `config.json` is gitignored, so everyone keeps their own settings.

## Notes

- Audio is recorded to `/tmp/sittich.m4a` (mono, 16 kHz AAC) and deleted after transcription.
- The clipboard is used for pasting and restored ~0.5 s afterwards.
- Change the model or hotkey at the top of `init.lua`.
