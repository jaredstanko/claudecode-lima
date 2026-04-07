# claudecode-lima

Sandboxed AI workspace that runs Claude Code in an isolated Ubuntu VM on your Mac, while keeping your files safe in `~/claudecode-workspace/` on your Mac itself.

## What This Sets Up

- **Lima VM** -- Ubuntu 24.04 server on Apple's Virtualization.framework (VZ)
- **Claude Code** -- Anthropic's CLI, installed inside the VM
- **Audio** -- VirtIO sound device passed through to macOS speakers
- **Shared workspace** -- 6 directories synced between Mac and VM
- **Menu bar app** -- One-click session launch, VM status, portal access
- **kitty terminal** -- Configured terminal emulator for VM sessions
- **Isolation** -- Claude Code runs inside a VM with access only to shared folders

## Prerequisites

- macOS 13+ (Ventura or later)
- Apple Silicon (M1/M2/M3/M4)
- Internet connection (for downloads)

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/jaredstanko/claudecode-lima.git
cd claudecode-lima

# 2. Run the installer (installs everything automatically)
./install.sh
```

The installer handles everything: Homebrew dependencies, Lima, kitty terminal, VM creation, provisioning, and menu bar app. Takes about 5-10 minutes on first run.

## How It Works

Your AI runs in a sandbox (a mini Linux computer inside your Mac). Your files stay on your Mac in `~/claudecode-workspace/`.

Lima creates a lightweight Linux VM using Apple's native Virtualization.framework. The VM:

- Has its own filesystem, network, and process space
- Shares exactly 6 directories with the host (see below)
- Cannot access the rest of your Mac filesystem

Claude Code runs inside this VM, so all file reads, writes, and shell commands are contained within the VM boundary.

## Shared Workspace

| Mac path | VM path | Purpose |
|----------|---------|---------|
| `~/claudecode-workspace/claude-home` | `~/.claude` | Claude Code config and settings |
| `~/claudecode-workspace/data` | `~/data` | Persistent data |
| `~/claudecode-workspace/exchange` | `~/exchange` | File exchange with Mac |
| `~/claudecode-workspace/portal` | `~/portal` | Web portal content |
| `~/claudecode-workspace/work` | `~/work` | Projects and work |
| `~/claudecode-workspace/upstream` | `~/upstream` | Reference repos |

Need to share more? Use the mount script:

```bash
./scripts/mount.sh ~/Projects/my-repo                    # Auto VM path
./scripts/mount.sh ~/Projects/my-repo /home/claude/code  # Custom VM path
./scripts/mount.sh --list                                # Show current mounts
```

## VM Configuration

| Setting | Value |
|---------|-------|
| VM engine | VZ (Apple Virtualization.framework) |
| Image | Ubuntu 24.04 ARM64 cloud image |
| User | `claude` (uid 1000) |
| Hostname | `claudecode` |
| CPUs | 4 |
| Memory | 4 GiB |
| Disk | 50 GiB |
| Audio | VirtIO sound (VZ) -> macOS speakers |
| Networking | vzNAT with port forwarding |
| Portal | http://localhost:8080 |

Edit `claudecode.yaml` to adjust resources before creating the VM.

## Menu Bar App

After installation, look for the ClaudeCode-Status icon in your menu bar. It provides:

- **VM status** -- Green/red/yellow dot shows VM state
- **New Claude Code Session** -- Launch Claude Code in a kitty terminal
- **Resume Session** -- Pick up where you left off
- **Open Portal** -- Quick access to localhost:8080
- **Open a Terminal** -- Plain shell access to the VM
- **Launch at Login** -- Auto-start when you open your Mac

## Session Management

```bash
./scripts/launch.sh                    # New Claude Code session
./scripts/launch.sh --resume           # Resume previous session
./scripts/launch.sh --shell            # Plain shell in VM
```

Or use the menu bar app for one-click access.

## Multiple Instances

Run parallel installations with custom names:

```bash
./install.sh --name=v2                  # Creates "claudecode-v2" instance
./install.sh --name=v2 --port=8082      # With specific portal port

# All scripts support --name
./scripts/launch.sh --name=v2
./scripts/upgrade.sh --name=v2
./scripts/verify.sh --name=v2
./scripts/uninstall.sh --name=v2
```

## Lifecycle Management

```bash
# Upgrade (preserves all data)
./scripts/upgrade.sh

# Verify installation
./scripts/verify.sh

# Backup and restore
./scripts/backup-restore.sh backup
./scripts/backup-restore.sh restore

# Uninstall (asks before removing data)
./scripts/uninstall.sh
```

## Verifying Audio

```bash
limactl shell claudecode

# Check sound card
sudo aplay -l
# Should show: card 1: SoundCard_1 [VirtIO SoundCard]

# Play a test tone (should come through your Mac speakers)
sudo speaker-test -D plughw:1,0 -t sine -f 440 -l 1 -p 2
```

> **Note:** The `audio.device` field is marked experimental in Lima 2.0.3. If `aplay -l` shows no devices, verify `linux-modules-extra` is installed and `virtio_snd` is loaded:
>
> ```bash
> sudo apt-get install -y linux-modules-extra-$(uname -r)
> sudo modprobe virtio_snd
> ```

## VM Management

```bash
# Shell into the VM
limactl shell claudecode

# Stop the VM
limactl stop claudecode

# Start it again
limactl start claudecode

# Delete and recreate
limactl delete claudecode --force
./install.sh

# List VMs
limactl list
```

## Troubleshooting

**VM won't start:** Make sure no other Lima instance named `claudecode` exists. Run `limactl delete claudecode --force` first.

**Shared folder not visible:** Ensure the VM is running (`limactl list`). The 6 workspace subdirectories are mounted individually, not as a single reverse mount.

**No audio:** The Ubuntu cloud image doesn't ship `linux-modules-extra`. The provisioning script installs it, but if it fails, run manually: `sudo apt-get install -y linux-modules-extra-$(uname -r) && sudo modprobe virtio_snd`

**aplay works with sudo but not as claude:** Log out and back in (`exit` then `limactl shell claudecode`) to refresh group membership after provisioning.

**Claude Code not found after install:** Run `source ~/.bashrc` or start a new shell session.

**kitty not opening tabs:** The menu bar app and launch script try to connect to an existing kitty instance via socket. If that fails, they open a new window instead.

## Credits

- [Lima](https://lima-vm.io/) -- Linux VMs on macOS
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) -- Anthropic's CLI for Claude
- [kitty](https://sw.kovidgoyal.net/kitty/) -- GPU-accelerated terminal emulator
