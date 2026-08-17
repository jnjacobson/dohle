# hammerspoon-whisper

Press **⌥Space** → recording starts (floating pill at the bottom of the screen with a pulsing red dot, "Pop" sound). Press **⌥Space** again → recording stops ("Glass" sound), audio goes to OpenAI (`gpt-transcribe`), and the transcript is pasted at the current text caret. **Esc** aborts while recording or transcribing ("Basso" sound); at any other time Esc behaves normally.

## Setup

1. Compile the recorder (once, and after editing `recorder.swift`):

   ```sh
   swiftc -O recorder.swift -o recorder
   ```

2. Put your OpenAI API key in `~/.config/openai/api_key` (single line, `chmod 600`).

3. `~/.hammerspoon/init.lua` loads this file:

   ```lua
   dofile(os.getenv("HOME") .. "/Documents/GitHub/hammerspoon-whisper/init.lua")
   ```

4. Reload the Hammerspoon config (menu bar icon → *Reload Config*).

## Permissions

- **Accessibility** — Hammerspoon asks on first launch; needed for the synthetic ⌘V.
- **Microphone** — macOS prompts for Hammerspoon on the first recording.

## Glossary

Copy `glossary.dist.txt` to `glossary.txt` and add your names and technical terms (one per line, `#` for comments). They are sent to the API as `keywords[]` so the model spells them correctly. The file is read on every transcription — no reload needed. `glossary.txt` is gitignored, so everyone keeps their own list.

## Notes

- Audio is recorded to `/tmp/hammerspoon-whisper.m4a` (mono, 16 kHz AAC) and deleted after transcription.
- The clipboard is used for pasting and restored ~0.5 s afterwards.
- Change the model or hotkey at the top of `init.lua`.
