# sittich

> sittich (German for "parakeet", pronounced /ˈzɪtɪç/)

Voice dictation for every macOS app. Press a hotkey, speak, press it again, and the transcript is pasted wherever your cursor is.

It runs on [Hammerspoon](https://www.hammerspoon.org) and OpenAI's `gpt-transcribe`. There's no app to install or sign, just two Lua files and a small Swift recorder you compile once.

## Usage

- **⌥Space** starts recording. Press it again to stop and transcribe.
- **Esc** aborts while recording or transcribing. The rest of the time it works as usual.

A floating pill in the middle of the screen shows the state: a live waveform while recording, a loader while transcribing. A sound plays at start, stop and abort. Errors appear as an alert; Esc dismisses it.

## Setup

You need macOS, Hammerspoon, the Xcode Command Line Tools (`xcode-select --install`) and an OpenAI API key.

1. Clone the repo and compile the recorder. Run `swiftc` again whenever you change `recorder.swift`.

   ```sh
   git clone https://github.com/jnjacobson/sittich.git
   cd sittich
   swiftc -O recorder.swift -o recorder
   ```

2. Save your API key, one line, readable only by you:

   ```sh
   mkdir -p ~/.config/openai
   pbpaste > ~/.config/openai/api_key   # with the key on the clipboard
   chmod 600 ~/.config/openai/api_key
   ```

   `OPENAI_API_KEY` works too and takes precedence, but Hammerspoon only sees it if it's set for GUI apps, not just in your shell.

3. Load sittich from `~/.hammerspoon/init.lua`:

   ```lua
   dofile(os.getenv("HOME") .. "/path/to/sittich/init.lua")
   ```

4. Reload Hammerspoon (menu bar icon → *Reload Config*).

5. Grant two permissions when macOS asks:
   - **Accessibility** for Hammerspoon, so it can paste with ⌘V.
   - **Microphone** for Hammerspoon, asked on the first recording.

## Configuration

Optional. Copy `config.dist.json` to `config.json` and fill in what you need:

```json
{
    "microphone": "MacBook Pro",
    "languages": ["de", "en"],
    "glossary": ["Hammerspoon", "Kubernetes", "PostgreSQL"]
}
```

- **`microphone`**: preferred input device, matched case-insensitively against part of the device name. `./recorder --list` prints all input devices. Leave it empty for the system default. If the chosen input can't record (AirPods busy on another device, say), the recorder falls back to the built-in mic.
- **`languages`**: language codes you speak, sent as hints.
- **`glossary`**: names and jargon the model should spell correctly.

sittich reads the file on every transcription, so changes apply without a reload. It's gitignored.

To change the model, edit `MODEL` at the top of `init.lua`. To change the hotkey, edit the `hs.hotkey.bind` call at the bottom.

## Privacy

Recordings are sent to OpenAI for transcription. Locally, audio is written to `/tmp/sittich.m4a` (mono, 16 kHz AAC) and deleted afterwards. Pasting borrows the clipboard and restores its previous contents about half a second later.
