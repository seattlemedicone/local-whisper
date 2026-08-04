# local-whisper

A fast, fully-local speech-to-text dictation tool for macOS with voice commands, powered by [whisper.cpp](https://github.com/ggml-org/whisper.cpp). No subscriptions, no cloud — just local transcription optimized for Apple Silicon.

Hold **Right Cmd**, speak, release — text appears at your cursor.

## Features

- **Hold-to-dictate**: Hold a modifier key to record, release to transcribe and insert
- **Voice commands**: Say "voice command note buy coffee" to save a note, "voice command open app Safari" to launch apps, and more — fully customizable
- **Live preview**: Streaming overlay shows partial transcription while you speak
- **Recording indicator**: Pulsing red dot and elapsed timer in the overlay
- **English dictation**: English-only Whisper models keep setup simple and responsive
- **App-aware processing**: Auto-capitalizes in most apps, skips in terminals and code editors
- **Guarded LLM refinement** (optional): Clean up punctuation and approved filler words with a local Gemma model, then reject any response that changes clinical facts before deterministic formatting
- **Text post-processing**: Remove filler words (um, uh, hmm), clean whitespace
- **Custom vocabulary**: Provide a prompt file to improve recognition of domain-specific terms
- **Auto-stop on silence**: Automatically stops recording after 3 seconds of silence
- **Menu bar**: Waveform icon shows recording status (turns red), click for settings and recent dictations
- **Recent dictations**: View and re-paste your last 10 dictations from the menu bar
- **Fully local**: All processing on-device via whisper.cpp — nothing leaves your machine

## Voice Commands

Voice commands turn dictation into actions. All commands start with **"voice command"** to prevent false matches on normal speech.

| Say | What happens |
|-----|-------------|
| "voice command note buy coffee" | Saves to `~/whisper_notes.md` |
| "voice command remind call mom" | Creates a Reminder in the Reminders app |
| "voice command open app Safari" | Launches or focuses an app |
| "voice command copy" | Fires Cmd+C |
| "voice command paste" | Fires Cmd+V |
| "voice command select all" | Fires Cmd+A |
| "voice command undo" | Fires Cmd+Z |
| "voice command cancel" | Discards the current dictation (works mid-sentence) |

Voice commands are fully customizable — edit `~/.hammerspoon/local_whisper_actions.lua` to add your own. The config auto-reloads when you save.

For a full guide on writing custom commands, see **[docs/VOICE_COMMANDS.md](docs/VOICE_COMMANDS.md)**.

## Requirements

- macOS (Apple Silicon recommended — tested on M4)
- [Homebrew](https://brew.sh)
- About 10 GB of free disk space for Whisper, Ollama, and Gemma
- An internet connection during installation; transcription and refinement run locally afterward

## Install

```bash
git clone https://github.com/SeattleMedicOne/local-whisper.git && cd local-whisper && ./install.sh
```

The installer handles the technical work: Homebrew dependencies, building whisper.cpp, downloading and load-testing both English Whisper models, installing Ollama, downloading and test-running Gemma 4 E2B, starting Ollama automatically at login, enabling guarded refinement, and setting up Hammerspoon. It then walks you through choosing a trigger key, microphone, and granting macOS permissions. Interrupted model downloads are not accepted; re-running the installer safely retries them.

The Gemma download is approximately 7.2 GB and can take several minutes. When installation finishes, verify everything with:

```bash
./install.sh --verify
```

To change the trigger key or re-run setup later:

```bash
./setup.sh
```

<details>
<summary>Manual install (if you prefer)</summary>

```bash
# Keep the two repositories in known locations
git clone https://github.com/SeattleMedicOne/local-whisper.git ~/local-whisper

# 1. Dependencies
brew install ffmpeg cmake git ollama
brew install --cask hammerspoon

# 2. Build whisper.cpp
cd ~
git clone https://github.com/ggml-org/whisper.cpp
cd whisper.cpp
cmake -B build
cmake --build build -j --config Release

# 3. Download the English final and preview models (~217 MB total)
./models/download-ggml-model.sh base.en
./models/download-ggml-model.sh tiny.en

# 4. Start Ollama at login and download local Gemma (~7.2 GB)
brew services start ollama
ollama pull gemma4:e2b

# 5. Copy Hammerspoon config
mkdir -p ~/.hammerspoon
cp ~/local-whisper/hammerspoon/init.lua ~/.hammerspoon/init.lua

# 6. Enable guarded Gemma refinement
mkdir -p ~/.local-whisper
printf 'en\n' > ~/.local-whisper/lang
printf 'base.en\n' > ~/.local-whisper/model
printf 'on\n' > ~/.local-whisper/refine
printf 'gemma4:e2b\n' > ~/.local-whisper/refine_model
chmod 700 ~/.local-whisper
chmod 600 ~/.local-whisper/lang ~/.local-whisper/model ~/.local-whisper/refine ~/.local-whisper/refine_model

# 7. Choose the trigger/microphone, grant permissions, and verify
cd ~/local-whisper
./setup.sh
./install.sh --verify
```

</details>

## Uninstall

```bash
./uninstall.sh
```

Removes Hammerspoon config, `~/.local-whisper/` settings, and temp files. Optionally removes `~/whisper.cpp`. Does not uninstall Homebrew packages.

## Setup

### Permissions (System Settings > Privacy & Security)

| App | Permission |
|-----|-----------|
| Hammerspoon | Accessibility, Microphone |
| Terminal (or your terminal app) | Accessibility (for `hs` CLI) |

### Hammerspoon CLI

Open Hammerspoon console and run once:

```lua
hs.ipc.cliInstall()
```

This installs the `hs` command-line tool used for IPC.

### Audio device

The default `:default` uses your system input device — this is recommended as it survives dock/undock and audio device changes. To use a specific device, find its index:

```bash
ffmpeg -f avfoundation -list_devices true -i ""
```

Then update `AUDIO_DEVICE` in `~/.hammerspoon/init.lua` (e.g., `:0`, `:1`).

## Menu bar

A waveform icon in the menu bar shows recording status (turns red when recording). Click it to:

- See the English language lock, model, output mode, enter mode, and LLM refine status
- Click model, output, enter, or refinement settings to change them
- View and re-paste recent dictations
- Open the settings overlay
- Reload voice commands
- Emergency stop

All settings are accessible from the menu bar — no keyboard shortcuts needed.

## Custom vocabulary prompt

Create `~/.local-whisper/prompt` with terms whisper should recognize better:

```
Claude, Hammerspoon, whisper.cpp, ffmpeg, macOS, Lua, Anthropic
```

This is passed as `--prompt` to whisper-cli for both partial and final transcription. Adding your voice command trigger words here improves recognition.

## Local Gemma refinement

The installer enables local Gemma-powered punctuation cleanup through Ollama. Every response is validated against the deterministic baseline; changed numbers, percentage markers, protected symbols, words, or word order cause an automatic fallback. Clinical formatting then runs again after accepted cleanup.

Ollama runs as a Homebrew service and starts automatically when the user signs in. Refinement can still be toggled from the menu bar or by clicking **refine** in the overlay.

Refinement only runs on text longer than 50 characters. Short dictations are inserted as-is.

### Customizing refinement

| File | What it does |
|------|-------------|
| `~/.local-whisper/refine` | ON/OFF state (also togglable from menu bar / overlay) |
| `~/.local-whisper/refine_model` | Ollama model to use (default: `gemma4:e2b`) |
| `~/.local-whisper/refine_prompt` | Custom instructions for the LLM |

Complete vital signs are canonicalized after refinement as:

`BP 132/82 | P 88 | R 20 | SpO2 98% 2 L/min NC | EtCO2 35 mm Hg`

Omitted fields remain omitted. The formatter never invents a vital-sign value.

## Faster live preview

By default, partial transcription uses the same model as final transcription. For faster live preview, download a smaller model:

```bash
cd ~/whisper.cpp/models
./download-ggml-model.sh tiny.en
```

The system automatically prefers the smallest available English model (`tiny.en` before `base.en`) for partials while keeping `base.en` for the final transcription.

## Privacy and local data

Audio, transcripts, recent dictations, temporary model payloads, and machine-specific settings stay outside this repository. Do not commit patient information, recordings, runtime logs, local configuration, credentials, or screenshots containing clinical data. The repository `.gitignore` blocks common audio, transcript, runtime, environment, and local-configuration paths as a secondary safeguard.

Runtime data remains under `~/.local-whisper/` and `$TMPDIR/whisper-dictate/`; downloaded models remain under `~/whisper.cpp/models/` and `~/.ollama/`. These locations are not part of the Git checkout.

## App-aware text processing

Post-processing adapts to the frontmost application when you start recording:

- **Terminals** (Terminal, iTerm2, Warp): skips auto-capitalize (commands are lowercase)
- **Code editors** (VS Code, Xcode, Zed, Sublime Text): skips auto-capitalize
- **Everything else**: auto-capitalizes first letter, removes filler words

The active app is also available in voice command hooks as `ctx.appName` and `ctx.appBundleID`.

## Writing custom voice commands

Edit `~/.hammerspoon/local_whisper_actions.lua` to add your own commands. The file returns a table with hooks that run on each dictation:

```lua
return {
    beforeInsert = function(ctx)
        -- Match and handle commands here
    end,
    actions = { },
    afterInsert = function(ctx)
        -- Post-insertion logic (logging, etc.)
    end,
}
```

### Hook context

| Field / Method | Description |
|---------------|-------------|
| `ctx.text` | Current text (mutable via `ctx:setText()`) |
| `ctx.textLower` | Lowercase version for case-insensitive matching |
| `ctx.originalText` | Original transcription (immutable) |
| `ctx.appName` | App name where dictation started (e.g. "Safari") |
| `ctx.appBundleID` | Bundle ID (e.g. "com.apple.Safari") |
| `ctx:setText(text)` | Replace text before insertion |
| `ctx:disableInsert()` | Skip cursor insertion (for command-only actions) |
| `ctx:appendToFile(path, line)` | Append a line to a file (creates parent dirs) |
| `ctx:launchApp("Safari")` | Launch or focus an app |
| `ctx:runShell("cmd", input)` | Run a shell command with optional stdin |
| `ctx:keystroke({"cmd"}, "a")` | Fire a keystroke |
| `ctx:notify("msg")` | Show a notification |
| `ctx.handled` | Set to `true` to skip remaining actions |

The config auto-reloads when you save the file. For more patterns and examples, see **[docs/VOICE_COMMANDS.md](docs/VOICE_COMMANDS.md)**.

## How it works

```
Modifier key hold/release (detected by Hammerspoon eventtap)
  → ffmpeg records chunked WAV segments (1s each)
  → Partial transcription loop: concat latest chunks → whisper-cli (tiny model)
  → On release: concat all chunks → final whisper-cli transcription (chosen model)
  → Post-processing: remove fillers, capitalize, app-aware adjustments
  → Optional LLM refinement via Ollama (punctuation, formatting, cleanup)
  → Voice command hooks: beforeInsert → actions → text insertion → afterInsert
  → Text inserted at cursor via paste (Cmd+V) or keystroke
```

## Auto-stop on silence

Recording automatically stops after 3 consecutive seconds of silence (< -40 dB). This is useful for hands-free dictation. Configure thresholds in `init.lua`:

```lua
local AUTO_STOP_SILENCE_SECONDS = 3
local AUTO_STOP_THRESHOLD_DB = -40
```

## Troubleshooting

- **No transcription output**: Check `$TMPDIR/whisper-dictate/whisper-dictate.log` for errors (run `echo $TMPDIR` to find the path)
- **ffmpeg exits immediately (code 251)**: `AUDIO_DEVICE` is missing the colon prefix — use `:0` not `0`. The `:` tells avfoundation it's an audio device.
- **Wrong microphone**: Run `ffmpeg -f avfoundation -list_devices true -i ""` and update `AUDIO_DEVICE` in init.lua (or use `:default`)
- **Trigger key does nothing**: Accessibility permission may need toggling. Go to System Settings > Privacy & Security > Accessibility, toggle Hammerspoon **OFF then ON**, then run `hs.reload()` in the Hammerspoon console
- **External keyboard mapping**: Some keyboards (e.g., Logitech MX Keys) send non-standard modifier flags. Try different `TRIGGER_KEY` values (`rightAlt`, `rightCmd`, `rightCtrl`) in init.lua
- **`hs` command not found**: Run `hs.ipc.cliInstall()` in Hammerspoon console
- **Voice commands not triggering**: Check the log to see what whisper transcribed — add command words to `~/.local-whisper/prompt`
- **Overlay not appearing**: Hammerspoon may need Accessibility permission re-granted after updates

## Disclaimer

This project was **vibe-coded** — built quickly with AI assistance for personal use. It works on my machine (M4 MacBook Pro), it might work on yours. PRs and issues welcome.

## License

[MIT](LICENSE)
