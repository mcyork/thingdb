# Pi Serial Bridge + Agent

A small toolkit to interact with a Raspberry Pi over a serial console in a way that behaves like non-interactive SSH. It disables pagers and color noise, frames command output with clear start/end markers and exit codes, and is robust enough for LLMs and automation to parse reliably.

This is useful when network is broken or during early bring-up — you still have a dependable control plane over the serial port.

---

## Background

We built this after repeatedly “bricking” Pis while developing network interfaces. In early bring‑up and iterative testing, it’s common to lose SSH due to a bad config, an over‑ambitious update, or a half‑working driver. Traditional serial methods (screen/minicom + expect scripts) were flaky: pagers like `less` would capture output, prompts varied, colors/ANSI codes crept in, and parsing became brittle — especially for automation and LLM agents.

The goal was a serial path that behaves like `ssh host "cmd"` (no interactive PTY):
- No pagers or “(END)” prompts blocking output
- Deterministic, parseable framing with exit codes
- Minimal ANSI/TTY noise so tools can reason about results

This repo delivers that in two layers:
- A tiny agent that runs on the Pi’s serial console via systemd and executes one‑line commands with pager disabling, printing clear start/end markers and exit codes.
- A host CLI that auto‑detects the agent and falls back to a non‑interactive wrapper when needed.

The result is a dependable, automation‑friendly serial control plane that keeps you productive when networking isn’t.

---

## Components

- `scripts/serial_bridge`: CLI for issuing commands over a serial port using Python/pyserial.
- `serial_tool/serial_manager.py`: Core logic for login, command execution, and parsing.
- `scripts/serial_agent.py`: Tiny command runner that lives on the Pi serial console. Disables pagers, frames output.
- `pi_agent/serial-agent@.service`: systemd unit that runs the agent on a chosen serial TTY.
- `pi_agent/install.sh`: Installer script for the agent + systemd unit on the Pi.
- `scripts/build_pi_agent_tar.sh`: Builds `dist/pi-serial-agent.tar.gz` containing the agent + installer.
- `scripts/deploy_pi_agent.sh`: Uses your existing `pi` CLI to copy and install the agent on the Pi via SSH.
- `config.yml`: Serial port configuration (device path, baud, timeout, credentials, etc.).

---

## Requirements

- Host machine
  - Python 3.9+ (3.10+ recommended)
  - `pip install -r requirements.txt` (pyserial, PyYAML)
  - The `pi` CLI already installed in your environment (this repo assumes you have it)
- Pi side
  - A reachable SSH path for initial install (first-time push)
  - A serial console device (e.g., `/dev/ttyAMA0` via GPIO/UART, or USB serial adapter like `/dev/ttyUSB0` / macOS `tty.usbserial-*`)

---

## Configure Serial

Edit `config.yml` to match your environment. Example:

```yaml
serial_ports:
  default:
    port: /dev/tty.usbserial-1420   # macOS USB serial example
    baudrate: 9600
    timeout: 2
  pi_console:
    port: /dev/tty.usbserial-1420   # adjust for your host OS
    baudrate: 9600
    timeout: 5
    username: pi
    password: raspberry
```

Tips:
- macOS: list devices with `ls /dev/tty.*` or `ls /dev/cu.*`.
- Linux: list with `ls /dev/ttyUSB*` or `ls /dev/ttyACM*`.
- Start with `baudrate: 115200` for Pi UART console unless you know it differs.

---

## UART Basics (Pi)

- Enable UART: On Raspberry Pi OS, run `sudo raspi-config` → Interface Options → Serial → Disable login shell over serial, Enable serial hardware. Reboot.
- Device names:
  - `ttyAMA0` on many models for the primary PL011 UART
  - `ttyS0` on others (mini UART); Bluetooth overlays can swap them
  - Use `systemctl list-units 'serial-getty@*' --no-pager` to discover what’s active
- Baud rate: `115200` is the common console baud; set your USB adapter or terminal likewise.
- Serial-getty vs agent: The installer disables `serial-getty@%I` and starts `serial-agent@%I`, so the agent owns the console. You can revert via the Uninstall steps.

---

## Quickstart: Deploy Agent To A Fresh Pi (SSH path)

This makes the serial console behave like SSH-without-PTY: no pagers, no prompts. The agent runs as a systemd service bound to the serial TTY.

1) Build the package

```bash
scripts/build_pi_agent_tar.sh
```

2) Deploy using your `pi` CLI (example uses `pi1` at `ttyAMA0`)

```bash
scripts/deploy_pi_agent.sh --pi pi1 --tty ttyAMA0
```

What this does on the Pi:
- Installs `/usr/local/bin/serial_agent`
- Installs `/etc/systemd/system/serial-agent@.service`
- Disables `serial-getty@ttyAMA0.service` on the chosen TTY
- Enables and starts `serial-agent@ttyAMA0.service`

Verify on the Pi over SSH (optional):

```bash
pi run-stream --pi pi1 "systemctl status serial-agent@ttyAMA0 --no-pager"
```

---

## Quickstart: Use Serial Bridge (Host)

Run commands over serial using the agent. The client auto-detects the agent; if missing, it falls back to a non-PTY wrapper that disables pagers.

```bash
# Simple test
python3 scripts/serial_bridge run --port_name pi_console "whoami && hostname"

# Service status (non-paged)
python3 scripts/serial_bridge run --port_name pi_console "systemctl status ssh"

# Read all pending output (rarely needed now that agent frames output)
python3 scripts/serial_bridge read --port_name pi_console --timeout 10
```

Notes:
- Output is framed with `__START__`/`__END__:N` on the wire; the client returns just the content.
- Exit codes are captured; the CLI prints output. If you need the exit code programmatically, you can add a mode to print it as well.

---

## Minimal CI (What and Why)

The repo includes a minimalist GitHub Actions workflow (`.github/workflows/ci.yml`) that:
- Lints Python (`ruff`) and checks formatting (`black --check`)
- Compiles Python files to catch syntax errors (`py_compile`)
- Lints shell scripts with `shellcheck`

This gives basic quality gates for contributions without heavy setup. You can expand later with tests and packaging as the project matures.

---

## Typical Workflows

- New image bring-up
  - Use `pi list` / `pi status` to find an online Pi
  - `scripts/deploy_pi_agent.sh --pi <name> --tty ttyAMA0` to set up the serial agent
  - Plug serial cable, set `config.yml` port, test with `serial_bridge run`

- When networking is broken
  - Connect serial cable → adjust `config.yml` port
  - `serial_bridge run --port_name pi_console "dmesg | tail -n 100"`
  - `serial_bridge run --port_name pi_console "journalctl -b -n 200 --no-pager"`

- Reset a wedged console
  - Over SSH (if available): `pi run-stream --pi <name> "sudo systemctl restart serial-agent@ttyAMA0"`
  - Or power-cycle if SSH is unavailable

---

## Troubleshooting

- Stuck in pager: You should not see `(END)` with the agent. If you do, ensure the agent service is active and that `serial-getty@…` is disabled on that TTY.
- Stuck at `>` prompts: This is bash PS2 (continuation). Restart the unit: `pi run-stream --pi <name> "sudo systemctl restart serial-agent@ttyAMA0"`.
- Permission to serial device on host: Ensure your user can open the serial device (on Linux add user to `dialout`, on macOS grant device access).
- Wrong serial device: Re-check `/dev/tty*` listings and update `config.yml`.
- Baud mismatch: Common Pi UART baud is `115200`.
- Verify unit logs: `pi run-stream --pi <name> "journalctl -u serial-agent@ttyAMA0 -b --no-pager"`.

---

## Uninstall / Revert

On the Pi (over SSH):

```bash
sudo systemctl disable --now serial-agent@ttyAMA0.service
sudo rm -f /usr/local/bin/serial_agent
sudo rm -f /etc/systemd/system/serial-agent@.service
sudo systemctl daemon-reload

# Optionally restore the stock serial getty
sudo systemctl enable --now serial-getty@ttyAMA0.service
```

Alternatively, use the included uninstall script on the Pi:

```bash
# Disable agent on ttyAMA0 and restore serial-getty
sudo TTY=ttyAMA0 bash /tmp/pi-serial-agent/uninstall.sh

# Also remove agent binary and unit file
sudo TTY=ttyAMA0 REMOVE=1 bash /tmp/pi-serial-agent/uninstall.sh
```

---

## How It Works

- Agent path (recommended):
  - `serial_agent` runs as PID 1 of the serial console, reads one line, executes under `/bin/bash` with `TERM=dumb`, `PAGER=cat`, `SYSTEMD_PAGER=cat`, etc., and prints output framed by markers plus exit code.
  - Client auto-detects the agent by probing for `__PONG__/AGENT READY` and uses marker-based parsing.

- Fallback path (no agent):
  - Client wraps commands with the same no-pager env and `| cat`, prints start/end markers, and parses without relying on shell prompts.

This mirrors `ssh host "cmd"` (no TTY), so tools avoid pagers and print full output.

---

## Security Notes

- The agent runs as root on the serial console to reliably control the TTY. Physical access implies trust. If you prefer non-root, we can adjust permissions and drop privileges.
- The agent accepts one-line commands from the serial TTY only; it does not listen on the network.

---

## Contributing / Extending

- Add an interactive bridge: a `serial_bridge shell` subcommand to attach raw to the serial port for manual debugging.
- Print exit codes in the CLI: add an option to surface `__END__:N` to users.
- Multi-Pi orchestration: extend the `pi` CLI workflows to push to fleets.

Feel free to open PRs/issues with improvements or platform-specific tweaks.

---

## Release Checklist (Suggested)

- Bump version in docs (e.g., README one-liners) if applicable
- Build tarball: `scripts/build_pi_agent_tar.sh`
- Tag release: `git tag v0.1.0 && git push --tags`
- Create GitHub Release and upload `dist/pi-serial-agent.tar.gz`
- Verify CI is green on main
- Sanity-test:
  - Deploy to a Pi via `scripts/deploy_pi_agent.sh`
  - Run a few serial commands with `scripts/serial_bridge run`
- Draft follow-up issues (ideas in Contributing / Extending)

---

## Quick One-Liners

These assume you will publish the repo (replace `ORG`/`REPO`/`VERSION`).

- Host (macOS) bootstrap to get `serial_bridge` ready:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ORG/REPO/main/scripts/bootstrap_host_mac.sh)"
```

- Pi: install the serial agent on `ttyAMA0` directly (SSH is up on the Pi):

```bash
sudo rm -rf /tmp/pi-serial-agent && \
  sudo mkdir -p /tmp/pi-serial-agent && \
  curl -fsSL https://github.com/ORG/REPO/releases/download/VERSION/pi-serial-agent.tar.gz | \
  sudo tar -xz -C /tmp/pi-serial-agent && \
  cd /tmp/pi-serial-agent && \
  sudo TTY=ttyAMA0 bash ./install.sh
```

If you don’t know the TTY yet, omit `TTY=ttyAMA0` and the installer will try to detect an active serial getty.
