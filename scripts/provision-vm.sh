#!/bin/bash
# Claude Code Provisioning Script -- VM Setup
# Run this INSIDE the Lima VM as the 'claude' user.
# Called automatically by install.sh on the Mac.
#
# This script is idempotent -- safe to re-run if interrupted.
#
# Usage:
#   bash ~/provision-vm.sh

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_FILE="$HOME/.provision.log"
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⊘${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; }
step() { echo -e "\n${CYAN}[$1]${NC} ${BOLD}$2${NC}"; }

# --- Retry helper ---
retry() {
  local max_attempts=3
  local delay=5
  local attempt=1
  local cmd="$*"

  while [ $attempt -le $max_attempts ]; do
    if eval "$cmd"; then
      return 0
    fi
    if [ $attempt -lt $max_attempts ]; then
      warn "Attempt $attempt/$max_attempts failed. Retrying in ${delay}s..."
      sleep $delay
      delay=$((delay * 2))
    fi
    attempt=$((attempt + 1))
  done
  err "Failed after $max_attempts attempts: $cmd"
  return 1
}

echo -e "${BOLD}"
echo "============================================"
echo "  Claude Code Provisioning"
echo "============================================"
echo -e "${NC}"

# Use a safe TERM for installation -- xterm-kitty can cause installers
# to hang when run via limactl shell (not a real kitty terminal).
# The shell env block below sets xterm-kitty for interactive use.
export TERM=xterm-256color

# --- Step 1: System packages ---
step "1/5" "Installing system packages..."

# Add NodeSource repo for Node.js 22 LTS before apt-get update (single update pass)
NODE_NEEDS_SETUP=false
if command -v node &>/dev/null && node --version 2>/dev/null | grep -q "^v2[2-9]"; then
  log "Node.js already installed: $(node --version)"
else
  NODE_NEEDS_SETUP=true
  log "Adding NodeSource repo for Node.js 22 LTS..."
  sudo mkdir -p /etc/apt/keyrings
  retry "curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg"
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
fi

retry "sudo apt-get update -qq"
# shellcheck disable=SC2086
retry "sudo apt-get install -y -qq jq fzf ripgrep fd-find sqlite3 tmux bat ffmpeg curl wget imagemagick nmap whois dnsutils net-tools traceroute mtr texlive-latex-base texlive-fonts-recommended pandoc golang-go python3 python3-pip python3-venv build-essential git zip unzip tree htop kitty-terminfo ca-certificates gnupg espeak-ng"
log "System packages installed"

if [ "$NODE_NEEDS_SETUP" = true ]; then
  retry "sudo apt-get install -y -qq nodejs"
  log "Node.js $(node --version) installed from NodeSource"
fi

# uv -- modern Python package runner (replaces pip for running scripts)
if command -v uv &>/dev/null; then
  log "uv already installed: $(uv --version 2>/dev/null || echo 'present')"
else
  retry "curl -LsSf https://astral.sh/uv/install.sh | sh"
  export PATH="$HOME/.local/bin:$PATH"
  log "uv installed: $(uv --version 2>/dev/null || echo 'installed')"
fi

# yt-dlp via uv tool (isolated install, apt version is years stale)
if command -v yt-dlp &>/dev/null; then
  log "yt-dlp already installed: $(yt-dlp --version 2>/dev/null || echo 'present')"
else
  uv tool install yt-dlp
  log "yt-dlp installed via uv: $(yt-dlp --version 2>/dev/null || echo 'installed')"
fi

# Install 'say' shim -- Linux replacement for macOS 'say' command.
# Fallback chain: Kokoro (if running) -> espeak-ng -> silence.
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/say" <<'SAYSHIM'
#!/bin/bash
# say -- Linux shim for macOS 'say' command
# Fallback: Kokoro TTS -> espeak-ng -> silence
TEXT="$*"
[ -z "$TEXT" ] && exit 0

# Try Kokoro TTS if running
if curl -sf http://localhost:7880/health >/dev/null 2>&1; then
  TMPFILE=$(mktemp /tmp/say-XXXXXX.mp3)
  if curl -s -X POST http://localhost:7880/tts \
    -H "Content-Type: application/json" \
    -d "{\"text\": \"$TEXT\"}" -o "$TMPFILE" 2>/dev/null && [ -s "$TMPFILE" ]; then
    PULSE_SERVER=unix:/run/pulse/native ffplay -nodisp -autoexit -loglevel quiet "$TMPFILE" 2>/dev/null
    rm -f "$TMPFILE"
    exit 0
  fi
  rm -f "$TMPFILE"
fi

# Fall back to espeak-ng
if command -v espeak-ng >/dev/null 2>&1; then
  PULSE_SERVER=unix:/run/pulse/native espeak-ng "$TEXT" 2>/dev/null
  exit 0
fi
SAYSHIM
chmod +x "$HOME/.local/bin/say"
log "Linux 'say' shim installed (Kokoro -> espeak-ng fallback)"

# Install 'afplay' shim -- Linux replacement for macOS audio player.
# Wraps ffplay with PulseAudio socket so any code calling afplay just works.
cat > "$HOME/.local/bin/afplay" <<'AFSHIM'
#!/bin/bash
# afplay -- Linux shim for macOS afplay command
# Routes audio through ffplay -> PulseAudio -> VM audio device -> Mac speakers
FILE=""
VOLUME="1.0"
while [ $# -gt 0 ]; do
  case "$1" in
    -v) VOLUME="$2"; shift 2 ;;
    -*) shift ;;
    *) FILE="$1"; shift ;;
  esac
done
[ -z "$FILE" ] || [ ! -f "$FILE" ] && exit 1
SDL_VOL=$(awk "BEGIN {printf \"%d\", $VOLUME * 100}")
PULSE_SERVER=unix:/run/pulse/native ffplay -nodisp -autoexit -volume "$SDL_VOL" -loglevel quiet "$FILE" 2>/dev/null
AFSHIM
chmod +x "$HOME/.local/bin/afplay"
log "Linux 'afplay' shim installed (ffplay + PulseAudio)"

# --- Step 2: Bun ---
step "2/5" "Installing Bun..."

if command -v bun &>/dev/null; then
  log "Bun already installed: $(bun --version)"
else
  retry "curl -fsSL https://bun.sh/install | bash"
  source ~/.bashrc 2>/dev/null || true
  log "Bun installed"
fi

# Ensure bun is on PATH for the rest of this script
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# --- Step 3: Claude Code ---
step "3/5" "Installing Claude Code..."

# Detect and remove old npm-based installs
CLAUDE_NEEDS_INSTALL=false
if command -v claude &>/dev/null; then
  CLAUDE_PATH=$(command -v claude)
  if [[ "$CLAUDE_PATH" == *"node_modules"* ]] || [[ "$CLAUDE_PATH" == *"npm"* ]] || [[ "$CLAUDE_PATH" == *"lib/node_modules"* ]]; then
    warn "Removing old npm-based Claude Code install: $CLAUDE_PATH"
    npm uninstall -g @anthropic-ai/claude-code 2>/dev/null || true
    bun remove -g @anthropic-ai/claude-code 2>/dev/null || true
    CLAUDE_NEEDS_INSTALL=true
  else
    log "Claude Code already installed (native): $(claude --version 2>/dev/null || echo 'installed')"
  fi
else
  CLAUDE_NEEDS_INSTALL=true
fi

if [ "$CLAUDE_NEEDS_INSTALL" = true ]; then
  retry "curl -fsSL https://claude.ai/install.sh | bash"
  log "Claude Code installed"
fi

# Claude Code may install to ~/.claude/bin or ~/.local/bin depending on version
export PATH="$HOME/.claude/bin:$HOME/.local/bin:$PATH"

# Verify
if command -v claude &>/dev/null; then
  log "Claude Code verified: $(claude --version 2>/dev/null | grep -oE '[0-9.]+' | head -1 || echo 'present')"
else
  err "Claude Code not found after install"
  exit 1
fi

echo ""
warn "After setup completes, run 'claude' and sign in with your Anthropic account."
echo ""

# Disable telemetry and crash reporting
mkdir -p "$HOME/.claude"
SETTINGS_FILE="$HOME/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
  # Merge env block into existing settings
  TMP_SETTINGS=$(mktemp)
  jq '. + {"env": ((.env // {}) + {"DISABLE_TELEMETRY": "1", "DISABLE_ERROR_REPORTING": "1", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"})}' "$SETTINGS_FILE" > "$TMP_SETTINGS" && mv "$TMP_SETTINGS" "$SETTINGS_FILE"
else
  cat > "$SETTINGS_FILE" <<'SETTINGSEOF'
{
  "env": {
    "DISABLE_TELEMETRY": "1",
    "DISABLE_ERROR_REPORTING": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  }
}
SETTINGSEOF
fi
log "Claude Code telemetry and crash reporting disabled"

# --- Step 3b: Shell environment ---
step "3b" "Configuring shell environment..."

SENTINEL="# --- Claude Code environment (managed by provision-vm.sh) ---"
ENV_BLOCK='
# --- Claude Code environment (managed by provision-vm.sh) ---

# Bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Claude Code
export PATH="$HOME/.claude/bin:$PATH"

# Local binaries (pip --user, etc.)
export PATH="$HOME/.local/bin:$PATH"

# Go
export PATH="$HOME/go/bin:$PATH"

# Node global (npm install -g)
export PATH="$HOME/.npm-global/bin:$PATH"

# Terminal -- kitty-terminfo is installed in the VM
export TERM=xterm-kitty

# Audio -- PulseAudio system-wide socket
export PULSE_SERVER=unix:/run/pulse/native

# Default editor
export EDITOR=nano

# --- end Claude Code environment ---
'

for rcfile in ~/.bashrc ~/.zshrc; do
  touch "$rcfile"
  if grep -qF "$SENTINEL" "$rcfile" 2>/dev/null; then
    sed -i "/$SENTINEL/,/# --- end Claude Code environment ---/d" "$rcfile"
  fi
  echo "$ENV_BLOCK" >> "$rcfile"
done
log "Claude Code environment block written to .bashrc and .zshrc"

# Configure npm global prefix
mkdir -p "$HOME/.npm-global"
if ! npm config get prefix 2>/dev/null | grep -q '.npm-global'; then
  npm config set prefix "$HOME/.npm-global"
  log "npm global prefix set to ~/.npm-global"
fi

export PATH="$HOME/.claude/bin:$HOME/.local/bin:$HOME/go/bin:$HOME/.npm-global/bin:$PATH"

# --- Step 3c: VM IP and .env ---
VM_IP="localhost"
echo "$VM_IP" > ~/.vm-ip
log "VM IP: $VM_IP (Lima port-forwards to host)"

if [ -d "$HOME/.claude" ] && touch "$HOME/.claude/.env-test" 2>/dev/null; then
  rm -f "$HOME/.claude/.env-test"
  if [ -f ~/.claude/.env ]; then
    sed -i '/^VM_IP=/d; /^PORTAL_PORT=/d' ~/.claude/.env
  fi
  cat >> ~/.claude/.env <<ENVEOF
VM_IP=$VM_IP
PORTAL_PORT=8080
ENVEOF
  log "VM_IP and PORTAL_PORT written to ~/.claude/.env"

  # Pre-trust common workspaces so Claude Code doesn't prompt on first run
  CLAUDE_JSON="$HOME/.claude.json"
  if [ ! -f "$CLAUDE_JSON" ]; then
    cat > "$CLAUDE_JSON" <<TRUSTEOF
{
  "projects": {
    "$HOME/.claude": {
      "allowedTools": [],
      "hasTrustDialogAccepted": true
    },
    "$HOME": {
      "allowedTools": [],
      "hasTrustDialogAccepted": true
    }
  }
}
TRUSTEOF
    log "Claude Code workspaces pre-trusted"
  else
    log "Claude Code config already exists -- skipping trust setup"
  fi
else
  warn "$HOME/.claude mount not writable -- skipping .env write"
fi

# --- Step 4: Playwright ---
step "4/5" "Installing Playwright..."

if command -v bun &>/dev/null; then
  cd /tmp
  mkdir -p playwright-setup && cd playwright-setup
  bun init -y 2>/dev/null || true
  bun add playwright 2>/dev/null || true
  retry "bunx playwright install --with-deps chromium" || warn "Playwright install may need manual completion."
  cd /tmp && rm -rf playwright-setup
  log "Playwright installed"
else
  warn "Bun not found. Skipping Playwright."
fi

# --- Step 5: Sanity check ---
step "5/5" "Quick sanity check..."

echo ""
echo -e "${BOLD}  Quick sanity check...${NC}"

FAIL=0
for check_cmd in \
  "command -v bun" \
  "command -v claude" \
  "grep -qF '# --- Claude Code environment' ~/.bashrc" \
  "test -s $HOME/.vm-ip"; do
  if ! eval "$check_cmd" &>/dev/null; then
    err "Sanity check failed: $check_cmd"
    FAIL=$((FAIL + 1))
  fi
done

if [ $FAIL -gt 0 ]; then
  err "Provisioning completed with $FAIL failures. Check output above."
  exit 1
fi
log "All sanity checks passed"

# --- Done ---
echo ""
echo -e "${BOLD}${GREEN}============================================${NC}"
echo -e "${BOLD}${GREEN}  Provisioning Complete${NC}"
echo -e "${BOLD}${GREEN}============================================${NC}"
echo ""
log "Claude Code:  ~/.claude/"
log "Log:          $LOG_FILE"
echo ""
warn "Next steps -- follow the instructions shown by the installer on your Mac."
echo ""
