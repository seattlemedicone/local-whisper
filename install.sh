#!/usr/bin/env bash
# install.sh — local-whisper installer
# Sets up everything needed for hold-to-dictate on macOS with whisper.cpp
# Architecture: Hammerspoon-only (no Karabiner, no bash scripts at runtime)
set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*"; }

# ─── Detect script location (repo root) ─────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Configurable paths ─────────────────────────────────────────────────────
WHISPER_CPP_DIR="$HOME/whisper.cpp"
WHISPER_MODEL="base.en"
WHISPER_PREVIEW_MODEL="tiny.en"
WHISPER_MODEL_MIN_BYTES=100000000
WHISPER_PREVIEW_MODEL_MIN_BYTES=50000000
OLLAMA_MODEL="gemma4:e2b"
HAMMERSPOON_DIR="$HOME/.hammerspoon"
CONFIG_DIR="$HOME/.local-whisper"

read_lua_string_setting() {
    local file="$1"
    local setting="$2"
    grep -m1 "local ${setting} =" "$file" 2>/dev/null | sed 's/.*"\(.*\)".*/\1/' || true
}

read_compact_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    tr -d '[:space:]' < "$file"
}

select_configured_whisper_model() {
    local default_model="$1"
    local configured_model=""
    configured_model="$(read_compact_file "$CONFIG_DIR/model")"
    if [[ "$configured_model" =~ ^[A-Za-z0-9._-]+$ ]] &&
       verify_whisper_model "$WHISPER_CPP_DIR/models/ggml-${configured_model}.bin" 1; then
        printf '%s\n' "$configured_model"
    else
        printf '%s\n' "$default_model"
    fi
}

valid_ollama_model_name() {
    [[ "$1" =~ ^[A-Za-z0-9._:/-]+$ ]]
}

ollama_model_installed() {
    local model="$1"
    valid_ollama_model_name "$model" && command -v ollama >/dev/null 2>&1 &&
        ollama list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -Fxq "$model"
}

select_configured_refine_state() {
    local configured_state=""
    configured_state="$(read_compact_file "$CONFIG_DIR/refine")"
    if [[ "$configured_state" == "on" || "$configured_state" == "off" ]]; then
        printf '%s\n' "$configured_state"
    else
        printf '%s\n' "on"
    fi
}

select_configured_refine_model() {
    local default_model="$1"
    local configured_model=""
    configured_model="$(read_compact_file "$CONFIG_DIR/refine_model")"
    if ollama_model_installed "$configured_model"; then
        printf '%s\n' "$configured_model"
    else
        printf '%s\n' "$default_model"
    fi
}

find_hs_bin() {
    local candidate
    for candidate in \
        "/opt/homebrew/bin/hs" \
        "/usr/local/bin/hs" \
        "/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs" \
        "$HOME/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

model_file_meets_minimum_size() {
    local file="$1"
    local minimum_bytes="$2"
    local actual_bytes=""
    [[ -f "$file" ]] || return 1
    actual_bytes="$(stat -f '%z' "$file" 2>/dev/null || true)"
    [[ "$actual_bytes" =~ ^[0-9]+$ ]] && (( actual_bytes >= minimum_bytes ))
}

verify_whisper_model() {
    local file="$1"
    local minimum_bytes="$2"
    local sample="$WHISPER_CPP_DIR/samples/jfk.wav"
    model_file_meets_minimum_size "$file" "$minimum_bytes" &&
        [[ -x "$WHISPER_CPP_DIR/build/bin/whisper-cli" ]] &&
        [[ -f "$sample" ]] &&
        "$WHISPER_CPP_DIR/build/bin/whisper-cli" \
            -ng -m "$file" -f "$sample" -l en -nt --no-prints \
            >/dev/null 2>&1
}

move_to_trash() {
    local target="$1"
    local label="$2"
    local destination="$HOME/.Trash/${label}-$(date +%Y%m%d-%H%M%S)-$$"
    mkdir -p "$HOME/.Trash"
    mv "$target" "$destination"
    warn "Moved the unusable download to $destination"
}

download_model() {
    local model="$1"
    local purpose="$2"
    local approximate_size="$3"
    local minimum_bytes="$4"
    local model_file="$WHISPER_CPP_DIR/models/ggml-${model}.bin"
    local temporary_dir=""
    local temporary_file=""

    if verify_whisper_model "$model_file" "$minimum_bytes"; then
        ok "Model already downloaded and verified: ggml-${model}.bin"
        return 0
    fi

    if [[ -e "$model_file" ]]; then
        warn "Existing ggml-${model}.bin is incomplete or unreadable"
        move_to_trash "$model_file" "ggml-${model}.bin.invalid"
    fi

    temporary_dir="$(mktemp -d "$WHISPER_CPP_DIR/models/.local-whisper-download.XXXXXX")"
    temporary_file="$temporary_dir/ggml-${model}.bin"
    info "Downloading ggml-${model}.bin for ${purpose} (~${approximate_size})..."
    if ! (cd "$WHISPER_CPP_DIR" && bash ./models/download-ggml-model.sh "$model" "$temporary_dir"); then
        error "Model download failed: ${model}"
        move_to_trash "$temporary_dir" "local-whisper-${model}-failed"
        return 1
    fi

    if ! verify_whisper_model "$temporary_file" "$minimum_bytes"; then
        error "Downloaded model failed its CPU-only load test: ${model}"
        move_to_trash "$temporary_dir" "local-whisper-${model}-invalid"
        return 1
    fi

    mv "$temporary_file" "$model_file"
    rmdir "$temporary_dir"
    ok "Model downloaded and verified: ggml-${model}.bin"
}

ollama_inference_ready() {
    local model="${1:-$OLLAMA_MODEL}"
    valid_ollama_model_name "$model" || return 1
    curl -fsS --connect-timeout 3 --max-time 180 \
        -H 'Content-Type: application/json' \
        --data-binary "{\"model\":\"${model}\",\"prompt\":\"Reply OK.\",\"stream\":false,\"think\":false,\"keep_alive\":\"5m\",\"options\":{\"temperature\":0,\"num_predict\":1}}" \
        http://127.0.0.1:11434/api/generate 2>/dev/null |
        grep -Fq '"done":true'
}

restore_hammerspoon_choices() {
    local file="$1"
    local trigger_key="$2"
    local audio_device="$3"

    if [[ "$trigger_key" =~ ^(rightCmd|rightAlt|rightCtrl)$ ]]; then
        sed -i '' "s/local TRIGGER_KEY = \".*\"/local TRIGGER_KEY = \"${trigger_key}\"/" "$file"
    fi
    if [[ "$audio_device" == ":default" ]] || [[ "$audio_device" =~ ^:[0-9]+$ ]]; then
        sed -i '' "s/local AUDIO_DEVICE = \".*\"/local AUDIO_DEVICE = \"${audio_device}\"/" "$file"
    fi
}

install_hammerspoon_config() {
    local source_file="$1"
    local target_file="$2"
    local prior_trigger=""
    local prior_audio=""

    if [[ -f "$target_file" ]] && grep -q "local-whisper" "$target_file"; then
        prior_trigger="$(read_lua_string_setting "$target_file" "TRIGGER_KEY")"
        prior_audio="$(read_lua_string_setting "$target_file" "AUDIO_DEVICE")"
        cp "$source_file" "$target_file"
        restore_hammerspoon_choices "$target_file" "$prior_trigger" "$prior_audio"
        ok "Hammerspoon config updated; trigger key and microphone preserved"
    elif [[ -f "$target_file" ]]; then
        warn "Existing init.lua found — backing up to init.lua.backup"
        cp "$target_file" "${target_file}.backup"
        cp "$source_file" "$target_file"
        ok "Hammerspoon config installed (backup saved)"
    else
        cp "$source_file" "$target_file"
        ok "Hammerspoon config installed"
    fi
}

is_guarded_hammerspoon_config() {
    local file="$1"
    [[ -f "$file" ]] &&
        grep -Fq 'local-whisper' "$file" &&
        grep -Fq 'REFINE_DEFAULT_MODEL = "gemma4:e2b"' "$file" &&
        grep -Fq 'local function validateRefinement' "$file" &&
        grep -Fq 'WhisperTextProcessing.validateRefinement = validateRefinement' "$file"
}

verify_installation() {
    local failed=false
    local configured_model=""
    local ollama_bin=""
    local hs_bin=""
    local ffmpeg_bin=""
    local refine_model=""
    local refine_state=""

    echo -e "${BOLD}Verifying local-whisper installation${NC}"

    if [[ -x "$WHISPER_CPP_DIR/build/bin/whisper-cli" ]]; then
        ok "whisper-cli is installed"
    else
        error "whisper-cli is missing"
        failed=true
    fi

    if verify_whisper_model "$WHISPER_CPP_DIR/models/ggml-${WHISPER_MODEL}.bin" "$WHISPER_MODEL_MIN_BYTES"; then
        ok "Whisper model loaded successfully: ${WHISPER_MODEL}"
    else
        error "Whisper model is missing, incomplete, or unreadable: ${WHISPER_MODEL}"
        failed=true
    fi
    if verify_whisper_model "$WHISPER_CPP_DIR/models/ggml-${WHISPER_PREVIEW_MODEL}.bin" "$WHISPER_PREVIEW_MODEL_MIN_BYTES"; then
        ok "Whisper model loaded successfully: ${WHISPER_PREVIEW_MODEL}"
    else
        error "Whisper model is missing, incomplete, or unreadable: ${WHISPER_PREVIEW_MODEL}"
        failed=true
    fi

    if [[ -x "/opt/homebrew/bin/ffmpeg" ]]; then
        ffmpeg_bin="/opt/homebrew/bin/ffmpeg"
    elif [[ -x "/usr/local/bin/ffmpeg" ]]; then
        ffmpeg_bin="/usr/local/bin/ffmpeg"
    fi
    if [[ -n "$ffmpeg_bin" ]]; then
        ok "ffmpeg is installed"
    else
        error "ffmpeg is missing"
        failed=true
    fi

    if [[ -d "/Applications/Hammerspoon.app" || -d "$HOME/Applications/Hammerspoon.app" ]]; then
        ok "Hammerspoon is installed"
    else
        error "Hammerspoon application is missing"
        failed=true
    fi

    if is_guarded_hammerspoon_config "$HAMMERSPOON_DIR/init.lua"; then
        ok "Guarded Hammerspoon configuration is installed"
    else
        error "Guarded Hammerspoon configuration is missing or stale"
        failed=true
    fi

    hs_bin="$(find_hs_bin || true)"
    if [[ -n "$hs_bin" ]] && pgrep -q Hammerspoon &&
       "$hs_bin" -n -t 5 -c 'print(WhisperTextProcessing ~= nil and WhisperTextProcessing.validateRefinement ~= nil)' 2>/dev/null | grep -Fxq "true"; then
        ok "Guarded Hammerspoon runtime is loaded"
    else
        error "Guarded Hammerspoon runtime is not loaded"
        failed=true
    fi

    if [[ -n "$hs_bin" ]] &&
       "$hs_bin" -n -t 5 -c 'print(hs.accessibilityState())' 2>/dev/null | grep -Fxq "true"; then
        ok "Hammerspoon Accessibility permission is granted"
    else
        error "Hammerspoon Accessibility permission is missing"
        failed=true
    fi

    if [[ -n "$hs_bin" ]] &&
       "$hs_bin" -n -t 10 -c 'print(WhisperInstallationDiagnostics ~= nil and WhisperInstallationDiagnostics.microphone())' 2>/dev/null | grep -Fxq "true"; then
        ok "Hammerspoon can record from the configured microphone"
    else
        error "Hammerspoon cannot record from the configured microphone"
        failed=true
    fi

    configured_model="$(read_compact_file "$CONFIG_DIR/model")"
    if [[ "$(read_compact_file "$CONFIG_DIR/lang")" == "en" ]] &&
       [[ "$configured_model" =~ ^[A-Za-z0-9._-]+$ ]] &&
       verify_whisper_model "$WHISPER_CPP_DIR/models/ggml-${configured_model}.bin" 1; then
        ok "English Whisper configuration is active (${configured_model})"
    else
        error "Configured English Whisper model is missing or unreadable: ${configured_model:-unset}"
        failed=true
    fi

    if command -v ollama &>/dev/null; then
        ollama_bin="$(command -v ollama)"
        ok "Ollama is installed"
    else
        error "Ollama is missing"
        failed=true
    fi

    if curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
        ok "Ollama service is running"
    else
        error "Ollama service is not reachable"
        failed=true
    fi

    if command -v brew >/dev/null 2>&1 && brew services list 2>/dev/null |
       awk '$1 == "ollama" && $2 == "started" {found=1} END {exit !found}'; then
        ok "Ollama is registered to start automatically at login"
    else
        error "Ollama is not registered as a running login service"
        failed=true
    fi

    refine_state="$(read_compact_file "$CONFIG_DIR/refine")"
    refine_model="$(read_compact_file "$CONFIG_DIR/refine_model")"
    if [[ -n "$ollama_bin" ]] && ollama_model_installed "$refine_model"; then
        ok "Configured refinement model is installed: $refine_model"
    else
        error "Configured refinement model is missing: ${refine_model:-unset}"
        failed=true
    fi

    if [[ "$refine_state" == "off" ]] && ollama_model_installed "$refine_model"; then
        ok "Guarded local refinement is disabled by user preference (${refine_model})"
    elif [[ "$refine_state" == "on" ]] && ollama_model_installed "$refine_model" &&
         ollama_inference_ready "$refine_model"; then
        ok "Configured refinement model completed a local test inference (${refine_model})"
        ok "Guarded local refinement is enabled (${refine_model})"
    else
        error "Guarded refinement preference or configured model is invalid"
        failed=true
    fi

    if [[ "$failed" == true ]]; then
        error "Verification failed. Run ./install.sh to repair the installation."
        return 1
    fi

    ok "Installation verified"
}

if [[ "${1:-}" == "--verify" ]]; then
    verify_installation
    exit $?
fi

if [[ "${LOCAL_WHISPER_SOURCE_ONLY:-}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

# ─── Preflight ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}local-whisper installer${NC}"
echo -e "Hold a key → speak → release → text at cursor"
echo ""

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    error "This tool is macOS-only."
    exit 1
fi

# Check Apple Silicon
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    ok "Apple Silicon detected ($ARCH)"
else
    warn "Intel Mac detected ($ARCH) — will work but transcription will be slower"
fi

# Check Homebrew
if ! command -v brew &>/dev/null; then
    error "Homebrew not found. Install it first: https://brew.sh"
    exit 1
fi
ok "Homebrew found"

# ─── Step 1: Brew dependencies ──────────────────────────────────────────────
echo ""
info "Step 1/7: Installing dependencies via Homebrew..."

BREW_FORMULAE=(ffmpeg cmake git ollama)
for formula in "${BREW_FORMULAE[@]}"; do
    if brew list "$formula" &>/dev/null; then
        ok "$formula already installed"
    else
        info "Installing $formula..."
        brew install "$formula"
        ok "$formula installed"
    fi
done

if brew list --cask hammerspoon &>/dev/null; then
    ok "hammerspoon already installed"
else
    info "Installing hammerspoon..."
    brew install --cask hammerspoon
    ok "hammerspoon installed"
fi

# ─── Step 2: Build whisper.cpp ───────────────────────────────────────────────
echo ""
info "Step 2/7: Building whisper.cpp..."

if [[ -x "$WHISPER_CPP_DIR/build/bin/whisper-cli" ]]; then
    ok "whisper-cli already built at $WHISPER_CPP_DIR/build/bin/whisper-cli"
else
    if [[ ! -d "$WHISPER_CPP_DIR" ]]; then
        info "Cloning whisper.cpp..."
        git clone https://github.com/ggml-org/whisper.cpp "$WHISPER_CPP_DIR"
    else
        ok "whisper.cpp repo already at $WHISPER_CPP_DIR"
    fi

    info "Building with cmake (this may take a few minutes)..."
    cd "$WHISPER_CPP_DIR"
    cmake -B build
    cmake --build build -j --config Release
    cd "$SCRIPT_DIR"

    if [[ -x "$WHISPER_CPP_DIR/build/bin/whisper-cli" ]]; then
        ok "whisper-cli built successfully"
    else
        error "Build failed — check output above"
        exit 1
    fi
fi

# ─── Step 3: Download models ────────────────────────────────────────────────
echo ""
info "Step 3/7: Downloading English Whisper models..."

download_model "$WHISPER_MODEL" "final English dictation" "142 MB" "$WHISPER_MODEL_MIN_BYTES"
download_model "$WHISPER_PREVIEW_MODEL" "fast English live preview" "75 MB" "$WHISPER_PREVIEW_MODEL_MIN_BYTES"

# ─── Step 4: Install Hammerspoon config ─────────────────────────────────────
echo ""
info "Step 4/7: Setting up Hammerspoon and English defaults..."

mkdir -p "$HAMMERSPOON_DIR"

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
ok "Config directory: $CONFIG_DIR"

install_hammerspoon_config "$SCRIPT_DIR/hammerspoon/init.lua" "$HAMMERSPOON_DIR/init.lua"

SELECTED_WHISPER_MODEL="$(select_configured_whisper_model "$WHISPER_MODEL")"
if [[ "$SELECTED_WHISPER_MODEL" != "$WHISPER_MODEL" ]]; then
    ok "Preserving configured Whisper model: $SELECTED_WHISPER_MODEL"
fi
printf '%s\n' "en" > "$CONFIG_DIR/lang"
printf '%s\n' "$SELECTED_WHISPER_MODEL" > "$CONFIG_DIR/model"
chmod 600 "$CONFIG_DIR/lang" "$CONFIG_DIR/model"
ok "English dictation configured (${SELECTED_WHISPER_MODEL})"

# Install example voice commands if user doesn't have a config yet
if [[ ! -f "$HAMMERSPOON_DIR/local_whisper_actions.lua" ]]; then
    if [[ -f "$SCRIPT_DIR/hammerspoon/local_whisper_actions.example.lua" ]]; then
        cp "$SCRIPT_DIR/hammerspoon/local_whisper_actions.example.lua" "$HAMMERSPOON_DIR/local_whisper_actions.lua"
        ok "Voice commands config installed (edit ~/.hammerspoon/local_whisper_actions.lua to customize)"
    fi
fi

# ─── Step 5: Install and configure local Gemma refinement ─────────────────
echo ""
info "Step 5/7: Setting up local Gemma refinement..."
echo ""

info "Starting Ollama automatically at login..."
brew services start ollama

OLLAMA_READY=false
for _ in {1..30}; do
    if curl -fsS --connect-timeout 2 --max-time 3 http://127.0.0.1:11434/api/version >/dev/null 2>&1; then
        OLLAMA_READY=true
        break
    fi
    sleep 1
done

if [[ "$OLLAMA_READY" != true ]]; then
    error "Ollama did not start. Run 'brew services restart ollama', then re-run this installer."
    exit 1
fi
ok "Ollama service is running"

SELECTED_REFINE_STATE="$(select_configured_refine_state)"
SELECTED_REFINE_MODEL="$(select_configured_refine_model "$OLLAMA_MODEL")"
if [[ "$SELECTED_REFINE_STATE" != "on" ]]; then
    ok "Preserving disabled refinement preference"
fi
if [[ "$SELECTED_REFINE_MODEL" != "$OLLAMA_MODEL" ]]; then
    ok "Preserving configured refinement model: $SELECTED_REFINE_MODEL"
fi

if ollama_model_installed "$SELECTED_REFINE_MODEL"; then
    ok "Refinement model already downloaded: $SELECTED_REFINE_MODEL"
else
    if [[ "$SELECTED_REFINE_MODEL" == "$OLLAMA_MODEL" ]]; then
        info "Downloading $SELECTED_REFINE_MODEL (~7.2 GB). This can take several minutes..."
    else
        info "Downloading configured refinement model: $SELECTED_REFINE_MODEL"
    fi
    ollama pull "$SELECTED_REFINE_MODEL"
fi

if ! ollama_model_installed "$SELECTED_REFINE_MODEL"; then
    error "Refinement model verification failed. Re-run this installer to try again."
    exit 1
fi

if [[ "$SELECTED_REFINE_STATE" == "on" ]]; then
    info "Testing one local refinement response..."
    if ! ollama_inference_ready "$SELECTED_REFINE_MODEL"; then
        error "The configured refinement model could not run. Restart the Mac and re-run ./install.sh."
        exit 1
    fi
    ok "Configured refinement model completed a local test inference"
else
    ok "Refinement model installed; inference skipped while refinement is disabled"
fi

printf '%s\n' "$SELECTED_REFINE_STATE" > "$CONFIG_DIR/refine"
printf '%s\n' "$SELECTED_REFINE_MODEL" > "$CONFIG_DIR/refine_model"
chmod 600 "$CONFIG_DIR/refine" "$CONFIG_DIR/refine_model"
if [[ "$SELECTED_REFINE_STATE" == "on" ]]; then
    ok "Guarded local refinement enabled ($SELECTED_REFINE_MODEL)"
else
    ok "Guarded local refinement remains disabled"
fi

# ─── Step 6: Setup (permissions, trigger key, audio device, HS CLI) ─────────
echo ""
info "Step 6/7: Running setup (permissions, trigger key, audio device)..."
echo ""
bash "$SCRIPT_DIR/setup.sh"

# ─── Step 7: Optional — meeting recording mode ───────────────────────────────
echo ""
info "Step 7/7: Meeting recording mode (optional)"
echo ""
echo "  Adds 'Meeting Mode' to the menu bar — captures system audio during"
echo "  calls (Zoom, Meet, Teams, etc.), produces a live transcript and"
echo "  Ollama summary."
echo ""
echo "  Requires BlackHole 2ch (free virtual audio driver). On opt-in, this"
echo "  installer also builds a small Swift helper that creates a"
echo "  Multi-Output Device automatically — no Audio MIDI Setup needed."
echo ""
echo "  Skip if you only want hold-to-dictate. Re-run this installer later"
echo "  to enable it."
echo ""
read -r -p "  Enable meeting recording mode? [y/N]: " ENABLE_MEETING

if [[ "$ENABLE_MEETING" =~ ^[Yy]$ ]]; then
    if brew list --cask blackhole-2ch &>/dev/null; then
        ok "BlackHole 2ch already installed"
    else
        info "Installing BlackHole 2ch..."
        brew install --cask blackhole-2ch
        ok "BlackHole 2ch installed"
    fi

    HELPER_SRC="$SCRIPT_DIR/tools/aggregate-audio.swift"
    HELPER_BIN_DIR="$CONFIG_DIR/bin"
    HELPER_BIN="$HELPER_BIN_DIR/aggregate-audio"
    if [[ ! -f "$HELPER_SRC" ]]; then
        error "Missing $HELPER_SRC — meeting mode helper cannot be built."
        exit 1
    fi
    mkdir -p "$HELPER_BIN_DIR"
    info "Building audio helper (swiftc)..."
    if swiftc -O "$HELPER_SRC" -o "$HELPER_BIN"; then
        ok "Helper installed at $HELPER_BIN"
    else
        error "Failed to build audio helper. Is the Xcode Command Line Tools package installed?"
        error "  xcode-select --install"
        exit 1
    fi

    info "Creating 'local-whisper Output' Multi-Output Device..."
    if AGG_UID=$("$HELPER_BIN" create 2>&1); then
        ok "Aggregate device ready (UID: $AGG_UID)"
        echo ""
        echo "  Meeting mode will switch your system output to this device only"
        echo "  while a meeting is recording, then switch back when you stop."
        echo "  No further setup needed — start meetings from the menu bar."
    else
        warn "Could not create aggregate device automatically:"
        warn "  $AGG_UID"
        warn "If you just installed BlackHole, you may need to reboot first,"
        warn "then re-run this installer."
    fi
else
    ok "Skipped — meeting mode disabled. Re-run installer to enable."
fi

echo ""
echo -e "${BOLD}────────────────────────────────────────────────${NC}"
echo -e "${GREEN}${BOLD}Installation complete${NC}"
echo -e "${BOLD}────────────────────────────────────────────────${NC}"
echo ""
echo "English Whisper and guarded Gemma refinement are installed locally."
echo "Run ./install.sh --verify at any time to check the installation."
