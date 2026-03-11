# claudecode-lima

Sandboxed Claude Code environment running in a Lima VM (Ubuntu 24.04 ARM64) on macOS. One shared folder, nothing else.

## What This Sets Up

- **Lima VM** — Ubuntu 24.04 server on Apple's Virtualization.framework (VZ)
- **Claude Code** — Anthropic's CLI, installed inside the VM
- **Shared folder** — `/home/claude` in VM shared with Mac as `~/claude-workspace`
- **Isolation** — Claude Code runs inside a VM with access only to the shared folder

## Prerequisites

- macOS 13+ (Ventura or later)
- Apple Silicon (M1/M2/M3/M4)
- [Homebrew](https://brew.sh) (recommended)
- An Anthropic API key for Claude Code

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/quinn-pai/claudecode-lima.git
cd claudecode-lima

# 2. Install Lima
brew install lima

# 3. Create and start the VM
limactl create --name=linux linux.yaml
limactl start linux

# 4. Copy the install script into the VM and run it
limactl cp install.sh linux:~/install.sh
limactl shell linux
bash ~/install.sh
```

## How It Works

Lima creates a lightweight Linux VM using Apple's native Virtualization.framework. The VM:

- Has its own filesystem, network, and process space
- Shares exactly one folder with the host: `~/claude-workspace` on macOS maps to `/home/claude` in the VM
- Cannot access the rest of your Mac filesystem

Claude Code runs inside this VM, so all file reads, writes, and shell commands are contained within the VM boundary.

## VM Configuration

| Setting | Value |
|---------|-------|
| VM engine | VZ (Apple Virtualization.framework) |
| Image | Ubuntu 24.04 ARM64 cloud image |
| User | `claude` (uid 1000) |
| Hostname | `linux` |
| CPUs | 4 |
| Memory | 4 GiB |
| Disk | 40 GiB |
| Shared folder | `/home/claude` <-> `~/claude-workspace` |

Edit `linux.yaml` to adjust resources before creating the VM.

## VM Management

```bash
# Shell into the VM
limactl shell linux

# Stop the VM
limactl stop linux

# Start it again
limactl start linux

# Delete and recreate
limactl delete linux --force
limactl create --name=linux linux.yaml
limactl start linux

# List VMs
limactl list
```

## Directory Layout (inside VM)

```
~/           Home directory (/home/claude), shared with macOS as ~/claude-workspace
~/work/      Project workspace (git tracked)
~/.claude/   Claude Code configuration
```

## Troubleshooting

**VM won't start:** Make sure no other Lima instance named `linux` exists. Run `limactl delete linux --force` first.

**Shared folder not visible:** The VM's `/home/claude` is reverse-mounted to `~/claude-workspace` on macOS. Ensure the VM is running (`limactl list`).

**Claude Code not found after install:** Run `source ~/.bashrc` or start a new shell session.

## Credits

- [Lima](https://lima-vm.io/) — Linux VMs on macOS
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — Anthropic's CLI for Claude
