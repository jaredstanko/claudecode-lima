#!/bin/bash
# Claude Code Sandboxed VM — Install Script
# Run this INSIDE the Lima VM as the 'claude' user.
#
# Usage:
#   bash ~/install.sh
#
# This script installs:
#   1. System packages
#   2. Claude Code CLI
#   3. Playwright (browser automation)

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; }

echo -e "${BOLD}"
echo "============================================"
echo "  Claude Code Sandboxed VM Installer"
echo "============================================"
echo -e "${NC}"

# -----------------------------------------------------------
# Step 1: System packages
# -----------------------------------------------------------
log "Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y -qq curl git zip jq tree tmux wget python3-venv

# -----------------------------------------------------------
# Step 2: Claude Code
# -----------------------------------------------------------
if command -v claude &>/dev/null; then
    log "Claude Code already installed: $(claude --version 2>/dev/null || echo 'installed')"
else
    log "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
    export PATH="$HOME/.claude/bin:$PATH"
fi

echo ""
warn "After this script finishes, run 'claude' to authenticate with your Anthropic API key."
echo ""

# -----------------------------------------------------------
# Step 3: Create workspace
# -----------------------------------------------------------
log "Creating workspace directory..."
mkdir -p ~/work

# Initialize git tracking for work directory
cd ~/work && git init -q && git add -A && git commit -q -m "Initial work directory" 2>/dev/null || true

# -----------------------------------------------------------
# Step 4: Playwright (optional but recommended)
# -----------------------------------------------------------
log "Installing Playwright..."
if command -v npx &>/dev/null || command -v bunx &>/dev/null; then
    cd /tmp
    mkdir -p playwright-setup && cd playwright-setup

    if command -v bun &>/dev/null; then
        bun init -y 2>/dev/null || true
        bun add playwright 2>/dev/null || true
        bunx playwright install --with-deps chromium 2>/dev/null || warn "Playwright install may need manual completion."
    else
        npm init -y 2>/dev/null || true
        npm install playwright 2>/dev/null || true
        npx playwright install --with-deps chromium 2>/dev/null || warn "Playwright install may need manual completion."
    fi

    cd /tmp && rm -rf playwright-setup
else
    warn "No JS runtime found. Skipping Playwright."
    warn "Install Node.js or Bun, then run: npx playwright install --with-deps chromium"
fi

# -----------------------------------------------------------
# Done
# -----------------------------------------------------------
echo ""
echo -e "${BOLD}${GREEN}============================================${NC}"
echo -e "${BOLD}${GREEN}  Installation Complete${NC}"
echo -e "${BOLD}${GREEN}============================================${NC}"
echo ""
log "Claude Code: ~/.claude/"
log "Workspace:   ~/work/"
log "Home:        /home/claude (shared with macOS as ~/claude-workspace)"
echo ""
warn "Next steps:"
warn "  1. Run 'claude' to authenticate with your Anthropic API key"
warn "  2. Start working: cd ~/work && claude"
echo ""
