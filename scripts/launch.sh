#!/bin/bash
# Claude Code Lima -- launch Claude Code in a kitty terminal
# Opens a kitty window connected to the VM running Claude Code.
#
# Usage:
#   ./scripts/launch.sh                    # Open Claude Code session (default instance)
#   ./scripts/launch.sh --resume           # Resume a previous Claude Code session
#   ./scripts/launch.sh --shell            # Open a plain shell in the VM
#   ./scripts/launch.sh --name=v2          # Target a named instance
#   ./scripts/launch.sh --name=v2 --shell  # Shell into a named instance
#
# Prerequisites:
#   - kitty installed (brew install --cask kitty)
#   - Lima VM created and started (install.sh handles this)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source shared instance configuration
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# Check prerequisites
if ! command -v kitty &>/dev/null; then
  echo "kitty not found. Run ./install.sh first, or: brew install --cask kitty"
  exit 1
fi

if ! command -v limactl &>/dev/null; then
  echo "Lima not found. Run ./install.sh first, or: brew install lima"
  exit 1
fi

# Start the VM if it's not running
VM_STATUS=$(cc_vm_status)
if [ "$VM_STATUS" != "Running" ]; then
  echo "Starting ${VM_NAME} VM..."
  limactl start "$VM_NAME"
fi

# Determine action from remaining args
ACTION=""
for arg in ${_CC_REMAINING_ARGS[@]+"${_CC_REMAINING_ARGS[@]}"}; do
  case "$arg" in
    --resume|-r) ACTION="resume" ;;
    --shell|-s) ACTION="shell" ;;
    *) ;;
  esac
done

TITLE_PREFIX="${INSTANCE_NAME}"

# Detect the VM user's default shell
USER_SHELL=$(limactl shell "$VM_NAME" -- getent passwd claude 2>/dev/null | cut -d: -f7 || true)
USER_SHELL="${USER_SHELL:-/bin/bash}"

case "$ACTION" in
  resume)
    echo "Opening session picker..."
    cc_open_kitty_tab "${TITLE_PREFIX}: Resume" limactl shell --workdir /home/claude "$VM_NAME" -- "$USER_SHELL" -lc "claude -r"
    ;;
  shell)
    echo "Opening shell..."
    cc_open_kitty_tab "${TITLE_PREFIX}: Shell" limactl shell --workdir /home/claude "$VM_NAME" -- "$USER_SHELL" -l
    ;;
  *)
    echo "Launching Claude Code..."
    cc_open_kitty_tab "${TITLE_PREFIX}" limactl shell --workdir /home/claude "$VM_NAME" -- "$USER_SHELL" -lc "claude"
    ;;
esac

echo ""
echo "Portal: http://localhost:${PORTAL_PORT}"
