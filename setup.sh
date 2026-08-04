#!/usr/bin/env bash
# setup.sh — post-install setup for local-whisper
# Configures: trigger key, audio device, permissions, Hammerspoon CLI
# Architecture: Hammerspoon-only (everything runs in init.lua)
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

HAMMERSPOON_DIR="$HOME/.hammerspoon"
INIT_LUA="$HAMMERSPOON_DIR/init.lua"

echo ""
echo -e "${BOLD}local-whisper setup${NC}"
echo ""

if [[ ! -f "$INIT_LUA" ]]; then
    error "Hammerspoon config not found at $INIT_LUA"
    error "Run install.sh first."
    exit 1
fi

# ─── Step 1: Choose trigger key ─────────────────────────────────────────────
echo -e "${BOLD}Step 1: Choose your dictation trigger key${NC}"
echo ""

# Read current value
CURRENT_KEY=$(grep -m1 'local TRIGGER_KEY' "$INIT_LUA" | sed 's/.*"\(.*\)".*/\1/')
echo -e "  Current: ${BOLD}${CURRENT_KEY}${NC}"
echo ""
echo "  1) rightCmd     (Right Command)      — recommended"
echo "  2) rightAlt     (Right Option / Alt)"
echo "  3) rightCtrl    (Right Control)"
echo ""
read -r -p "Choice [keep current]: " KEY_CHOICE

case "$KEY_CHOICE" in
    1) NEW_KEY="rightCmd";  KEY_LABEL="Right Command" ;;
    2) NEW_KEY="rightAlt";  KEY_LABEL="Right Option" ;;
    3) NEW_KEY="rightCtrl"; KEY_LABEL="Right Control" ;;
    *) NEW_KEY="$CURRENT_KEY"; KEY_LABEL="$CURRENT_KEY (unchanged)" ;;
esac

if [[ "$NEW_KEY" != "$CURRENT_KEY" ]]; then
    sed -i '' "s/local TRIGGER_KEY = \".*\"/local TRIGGER_KEY = \"${NEW_KEY}\"/" "$INIT_LUA"
    ok "Trigger key set to: $KEY_LABEL"
else
    ok "Trigger key: $KEY_LABEL"
fi

# ─── Step 2: Choose audio device ────────────────────────────────────────────
echo ""
echo -e "${BOLD}Step 2: Choose your microphone${NC}"
echo ""

FFMPEG_BIN="$(brew --prefix 2>/dev/null)/bin/ffmpeg"
if [[ ! -x "$FFMPEG_BIN" ]]; then
    FFMPEG_BIN="$(which ffmpeg 2>/dev/null || echo "")"
fi

if [[ -n "$FFMPEG_BIN" ]]; then
    info "Available audio devices:"
    echo ""
    # Parse audio device list from ffmpeg
    DEVICE_OUTPUT=$("$FFMPEG_BIN" -f avfoundation -list_devices true -i "" 2>&1 || true)
    DEVICE_LINES=$(printf '%s\n' "$DEVICE_OUTPUT" | awk '
        /AVFoundation audio devices:/ {in_audio=1; next}
        in_audio && /^\[AVFoundation/ {print; shown++; if (shown >= 10) exit}
    ' || true)
    if [[ -n "$DEVICE_LINES" ]]; then
        printf '%s\n' "$DEVICE_LINES"
    else
        warn "No microphone list was returned; keeping the current/default device is safest"
    fi
    echo ""
fi

CURRENT_DEVICE=$(grep -m1 'local AUDIO_DEVICE' "$INIT_LUA" | sed 's/.*"\(.*\)".*/\1/')
echo -e "  Current: ${BOLD}${CURRENT_DEVICE}${NC}"
echo ""
echo "  :default uses your system input device (recommended — survives dock/undock)"
echo "  Enter a device string (e.g. :default, :0, :1) or press Enter to keep current:"
read -r -p "  Device [${CURRENT_DEVICE}]: " NEW_DEVICE
NEW_DEVICE="${NEW_DEVICE:-$CURRENT_DEVICE}"

if [[ "$NEW_DEVICE" != "$CURRENT_DEVICE" ]]; then
    # Auto-fix missing colon prefix (common mistake: "0" instead of ":0")
    if [[ "$NEW_DEVICE" =~ ^[0-9]+$ ]]; then
        NEW_DEVICE=":${NEW_DEVICE}"
        warn "Added colon prefix → $NEW_DEVICE (avfoundation requires ':' for audio devices)"
    fi
    # Validate device format (colon + digits or :default)
    if [[ ! "$NEW_DEVICE" =~ ^:[0-9]+$ ]] && [[ "$NEW_DEVICE" != ":default" ]]; then
        warn "Unusual device format: $NEW_DEVICE (expected :default, :0, :1)"
    fi
    # Escape special chars for sed
    ESCAPED_DEVICE=$(printf '%s\n' "$NEW_DEVICE" | sed 's/[&/\]/\\&/g')
    sed -i '' "s/local AUDIO_DEVICE = \".*\"/local AUDIO_DEVICE = \"${ESCAPED_DEVICE}\"/" "$INIT_LUA"
    ok "Audio device set to: $NEW_DEVICE"
else
    ok "Audio device: $NEW_DEVICE (unchanged)"
fi

# ─── Step 3: Start Hammerspoon and load the installed config ────────────────
echo ""
echo -e "${BOLD}Step 3: Start Hammerspoon and load local-whisper${NC}"
echo ""

HS_BIN=""
for candidate in \
    "/opt/homebrew/bin/hs" \
    "/usr/local/bin/hs" \
    "/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs" \
    "$HOME/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs"; do
    if [[ -x "$candidate" ]]; then
        HS_BIN="$candidate"
        break
    fi
done

# Helper: run command with a timeout (macOS has no `timeout` by default)
run_with_timeout() {
    local secs="$1"; shift
    "$@" &
    local pid=$!
    ( sleep "$secs" && kill "$pid" 2>/dev/null ) &
    local watchdog=$!
    local rc=0
    if wait "$pid" 2>/dev/null; then
        rc=0
    else
        rc=$?
    fi
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
    return $rc
}

if ! pgrep -q Hammerspoon; then
    info "Launching Hammerspoon..."
    open -a "Hammerspoon"
    for _ in {1..10}; do
        pgrep -q Hammerspoon && break
        sleep 1
    done
fi

if ! pgrep -q Hammerspoon; then
    error "Hammerspoon did not launch. Open it from Applications, then re-run ./install.sh."
    exit 1
fi

if [[ -z "$HS_BIN" ]]; then
    error "Hammerspoon's command-line helper is missing from the application bundle."
    error "Reinstall Hammerspoon with: brew reinstall --cask hammerspoon"
    exit 1
fi

# Reloading intentionally invalidates the IPC request that triggered it, so the
# helper can report a transport error even when reload succeeded. The runtime
# probe below is the authoritative success check.
run_with_timeout 5 "$HS_BIN" -n -t 5 -c 'hs.reload()' >/dev/null 2>&1 || true
sleep 2

if run_with_timeout 5 "$HS_BIN" -n -t 5 -c \
   'print(WhisperTextProcessing ~= nil and WhisperInstallationDiagnostics ~= nil)' 2>/dev/null |
   grep -Fxq "true"; then
    ok "Hammerspoon config loaded; local-whisper runtime is active"
else
    error "local-whisper did not load. Open Hammerspoon > Console, then re-run ./install.sh."
    exit 1
fi

# ─── Step 4: Permissions ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Step 4: macOS permissions${NC}"
echo ""

check_accessibility() {
    run_with_timeout 5 "$HS_BIN" -n -t 5 -c 'print(hs.accessibilityState())' 2>/dev/null |
        grep -Fxq "true"
}

check_microphone() {
    run_with_timeout 10 "$HS_BIN" -n -t 10 -c \
        'print(WhisperInstallationDiagnostics ~= nil and WhisperInstallationDiagnostics.microphone())' \
        2>/dev/null | grep -Fxq "true"
}

PERMISSIONS_OK=true

# ── Accessibility (Hammerspoon) ──
if check_accessibility; then
    ok "Accessibility: granted (Hammerspoon)"
else
    warn "Accessibility: Hammerspoon needs Accessibility permission"
    echo -e "  Enable ${BOLD}Hammerspoon${NC} in System Settings > Privacy & Security > Accessibility"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
    read -r -p "  Press Enter when done..."

    if check_accessibility; then
        ok "Accessibility: granted"
    else
        error "Accessibility permission is still unavailable"
        PERMISSIONS_OK=false
    fi
fi

# ── Microphone ──
if check_microphone; then
    ok "Microphone: granted"
else
    warn "Microphone: Hammerspoon needs Microphone permission"
    echo -e "  Enable ${BOLD}Hammerspoon${NC} in System Settings > Privacy & Security > Microphone"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone" 2>/dev/null || true
    read -r -p "  Press Enter when done..."

    if check_microphone; then
        ok "Microphone: granted"
    else
        error "Microphone access is still unavailable to Hammerspoon"
        PERMISSIONS_OK=false
    fi
fi

if [[ "$PERMISSIONS_OK" != true ]]; then
    error "Setup is incomplete. Grant both permissions, then re-run ./install.sh."
    exit 1
fi
ok "Accessibility and Microphone permissions verified"

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}────────────────────────────────────────────────${NC}"
echo -e "${GREEN}${BOLD}Setup complete!${NC}"
echo -e "${BOLD}────────────────────────────────────────────────${NC}"
echo ""
echo -e "Hold ${BOLD}${KEY_LABEL}${NC}, speak, and release."
echo ""
echo "Click the waveform icon in the menu bar to change settings."
echo ""
echo -e "Voice commands (say these while recording):"
echo "  \"voice command note <text>\"      — save a note"
echo "  \"voice command remind <text>\"    — create a Reminder"
echo "  \"voice command open app <name>\"  — launch an app"
echo "  \"voice command copy\"             — Cmd+C"
echo "  \"voice command cancel\"           — discard dictation"
echo ""
echo -e "To change settings later, run: ${BOLD}./setup.sh${NC}"
echo ""
