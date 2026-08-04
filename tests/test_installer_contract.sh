#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

require_text() {
    local file="$1"
    local text="$2"
    if ! grep -Fq -- "$text" "$file"; then
        echo "FAIL: expected '$text' in ${file#"$REPO_ROOT/"}" >&2
        exit 1
    fi
}

reject_text() {
    local file="$1"
    local text="$2"
    if grep -Fq -- "$text" "$file"; then
        echo "FAIL: unexpected '$text' in ${file#"$REPO_ROOT/"}" >&2
        exit 1
    fi
}

bash -n "$REPO_ROOT/install.sh"
bash -n "$REPO_ROOT/setup.sh"
bash -n "$REPO_ROOT/tests/test_refine.sh"

require_text "$REPO_ROOT/install.sh" 'WHISPER_MODEL="base.en"'
require_text "$REPO_ROOT/install.sh" 'WHISPER_PREVIEW_MODEL="tiny.en"'
require_text "$REPO_ROOT/install.sh" 'OLLAMA_MODEL="gemma4:e2b"'
require_text "$REPO_ROOT/install.sh" 'BREW_FORMULAE=(ffmpeg cmake git ollama)'
require_text "$REPO_ROOT/install.sh" 'brew services start ollama'
require_text "$REPO_ROOT/install.sh" 'ollama pull "$OLLAMA_MODEL"'
require_text "$REPO_ROOT/install.sh" 'printf '\''%s\n'\'' "on" > "$CONFIG_DIR/refine"'
require_text "$REPO_ROOT/install.sh" 'printf '\''%s\n'\'' "$OLLAMA_MODEL" > "$CONFIG_DIR/refine_model"'
require_text "$REPO_ROOT/install.sh" 'if [[ "${1:-}" == "--verify" ]]'
require_text "$REPO_ROOT/install.sh" 'install_hammerspoon_config "$SCRIPT_DIR/hammerspoon/init.lua" "$HAMMERSPOON_DIR/init.lua"'
require_text "$REPO_ROOT/install.sh" 'Guarded Hammerspoon runtime is loaded'
require_text "$REPO_ROOT/install.sh" 'verify_whisper_model "$temporary_file" "$minimum_bytes"'
require_text "$REPO_ROOT/install.sh" 'bash ./models/download-ggml-model.sh "$model" "$temporary_dir"'
require_text "$REPO_ROOT/install.sh" 'Gemma completed a local test inference'
require_text "$REPO_ROOT/install.sh" 'Ollama is registered to start automatically at login'
require_text "$REPO_ROOT/install.sh" 'WhisperInstallationDiagnostics.microphone()'
require_text "$REPO_ROOT/install.sh" 'configured_model="$(read_compact_file "$CONFIG_DIR/model")"'
require_text "$REPO_ROOT/install.sh" 'verify_whisper_model "$WHISPER_CPP_DIR/models/ggml-${configured_model}.bin" 1'
require_text "$REPO_ROOT/install.sh" 'SELECTED_WHISPER_MODEL="$(select_configured_whisper_model "$WHISPER_MODEL")"'
require_text "$REPO_ROOT/install.sh" 'printf '\''%s\n'\'' "$SELECTED_WHISPER_MODEL" > "$CONFIG_DIR/model"'
reject_text "$REPO_ROOT/install.sh" '[[ "$(read_compact_file "$CONFIG_DIR/model")" == "$WHISPER_MODEL" ]]'
reject_text "$REPO_ROOT/install.sh" 'WHISPER_MULTILINGUAL_MODEL'

require_text "$REPO_ROOT/hammerspoon/init.lua" 'SeattleMedicOne deployment is intentionally English-only.'
require_text "$REPO_ROOT/hammerspoon/init.lua" '"%s -m %s -f %s -otxt -of %s --no-prints -t 4 -l en'
require_text "$REPO_ROOT/hammerspoon/init.lua" 'WhisperInstallationDiagnostics.microphone = function()'
reject_text "$REPO_ROOT/hammerspoon/init.lua" 'local cycle = { en = "pt"'
reject_text "$REPO_ROOT/hammerspoon/init.lua" 'writeFile(PREFERRED_LANGS_FILE, "en,pt")'

require_text "$REPO_ROOT/setup.sh" 'Step 3: Start Hammerspoon and load local-whisper'
require_text "$REPO_ROOT/setup.sh" 'Step 4: macOS permissions'
require_text "$REPO_ROOT/setup.sh" 'WhisperInstallationDiagnostics.microphone()'
require_text "$REPO_ROOT/setup.sh" 'Setup is incomplete. Grant both permissions'
reject_text "$REPO_ROOT/setup.sh" 'run_with_timeout 5 "$FFMPEG_BIN"'

require_text "$REPO_ROOT/.gitignore" 'recordings/'
require_text "$REPO_ROOT/.gitignore" 'transcripts/'
require_text "$REPO_ROOT/.gitignore" 'refine_payload_*.json'
require_text "$REPO_ROOT/.gitignore" '.env.*'

require_text "$REPO_ROOT/README.md" 'https://github.com/SeattleMedicOne/local-whisper.git'
require_text "$REPO_ROOT/README.md" './install.sh --verify'
require_text "$REPO_ROOT/README.md" 'Do not commit patient information'

TEST_ROOT="$(mktemp -d)"
USER_TRASH="$HOME/.Trash"
trap 'mv "$TEST_ROOT" "$USER_TRASH/" 2>/dev/null || true' EXIT
SOURCE_CONFIG="$REPO_ROOT/hammerspoon/init.lua"
EXISTING_CONFIG="$TEST_ROOT/init.lua"
cp "$SOURCE_CONFIG" "$EXISTING_CONFIG"
sed -i '' 's/local TRIGGER_KEY = ".*"/local TRIGGER_KEY = "rightAlt"/' "$EXISTING_CONFIG"
sed -i '' 's/local AUDIO_DEVICE = ".*"/local AUDIO_DEVICE = ":7"/' "$EXISTING_CONFIG"

LOCAL_WHISPER_SOURCE_ONLY=1 source "$REPO_ROOT/install.sh"
install_hammerspoon_config "$SOURCE_CONFIG" "$EXISTING_CONFIG" >/dev/null
require_text "$EXISTING_CONFIG" 'local TRIGGER_KEY = "rightAlt"'
require_text "$EXISTING_CONFIG" 'local AUDIO_DEVICE = ":7"'

DUMMY_CONFIG="$TEST_ROOT/dummy.lua"
printf '%s\n' '-- unrelated Hammerspoon config' > "$DUMMY_CONFIG"
if is_guarded_hammerspoon_config "$DUMMY_CONFIG"; then
    echo "FAIL: dummy Hammerspoon config passed guarded verification" >&2
    exit 1
fi
if ! is_guarded_hammerspoon_config "$SOURCE_CONFIG"; then
    echo "FAIL: guarded repository config failed verification" >&2
    exit 1
fi

SMALL_MODEL="$TEST_ROOT/truncated-model.bin"
printf 'tiny' > "$SMALL_MODEL"
if model_file_meets_minimum_size "$SMALL_MODEL" 5; then
    echo "FAIL: truncated model passed the minimum-size guard" >&2
    exit 1
fi
if ! model_file_meets_minimum_size "$SMALL_MODEL" 4; then
    echo "FAIL: minimum-size guard rejected an exact-size file" >&2
    exit 1
fi

if [[ -n "$(read_compact_file "$TEST_ROOT/missing-setting")" ]]; then
    echo "FAIL: missing compact setting did not return empty text" >&2
    exit 1
fi

FAKE_HOME="$TEST_ROOT/home"
FAKE_WHISPER="$TEST_ROOT/whisper.cpp"
mkdir -p "$FAKE_HOME/.Trash" "$FAKE_WHISPER/build/bin" "$FAKE_WHISPER/models" "$FAKE_WHISPER/samples"
printf 'sample' > "$FAKE_WHISPER/samples/jfk.wav"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$FAKE_WHISPER/build/bin/whisper-cli"
chmod +x "$FAKE_WHISPER/build/bin/whisper-cli"
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'model="$1"' \
    'destination="$2"' \
    'printf '\''complete-model-payload'\'' > "$destination/ggml-${model}.bin"' \
    > "$FAKE_WHISPER/models/download-ggml-model.sh"
printf 'bad' > "$FAKE_WHISPER/models/ggml-test.en.bin"

HOME="$FAKE_HOME" WHISPER_CPP_DIR="$FAKE_WHISPER" \
    download_model "test.en" "atomic installer test" "small" 10 >/dev/null

mkdir -p "$FAKE_HOME/.local-whisper"
printf '%s\n' "test.en" > "$FAKE_HOME/.local-whisper/model"
SELECTED_MODEL="$(
    CONFIG_DIR="$FAKE_HOME/.local-whisper" WHISPER_CPP_DIR="$FAKE_WHISPER" \
        select_configured_whisper_model "base.en"
)"
if [[ "$SELECTED_MODEL" != "test.en" ]]; then
    echo "FAIL: valid configured Whisper model was not preserved" >&2
    exit 1
fi

if [[ "$(cat "$FAKE_WHISPER/models/ggml-test.en.bin")" != "complete-model-payload" ]]; then
    echo "FAIL: atomic model download did not install the verified replacement" >&2
    exit 1
fi
if ! find "$FAKE_HOME/.Trash" -maxdepth 1 -name 'ggml-test.en.bin.invalid-*' -print -quit | grep -q .; then
    echo "FAIL: invalid existing model was not moved aside before replacement" >&2
    exit 1
fi

echo "PASS: installer provisions English Whisper, local Gemma, persistent Ollama, and privacy safeguards"
