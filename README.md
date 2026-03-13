# ag-jail

A secure, isolated environment for running the Google Antigravity IDE on Linux.

ag-jail uses Podman to run the IDE inside a sandboxed Ubuntu container. It keeps your main
system clean, prevents background agents from persisting after exit, and ensures the IDE
cannot access your personal files (SSH keys, Documents, etc.) unless you explicitly allow it.

Demo:

https://github.com/user-attachments/assets/c92ac49b-d960-47ec-b1f3-ddc1bfe964cc

This tool was created out of frustration with Antigravity's persistent background processes.
Personally, I don't like things running in the background for no apparent reason — it feels
invasive, and it's hogging resources you could be using to compile Chromium for the 23rd time.

> The container uses **ungoogled-chromium** as its internal browser. It is completely sandboxed
> inside the jail — zero access to your host browser's history, cookies, or personal data.
> Links opened by the IDE stay inside the container.

## Features

- **True Isolation** — The IDE sees `~/Antigravity-Jail` as its home. Your real home is invisible.
- **Zero Persistence** — `ag-kill` stops the container and takes every background agent with it.
- **No Browser Escape** — D-Bus passthrough is blocked. The IDE cannot open your host browser.
- **ungoogled-chromium** — No Google telemetry. No Chrome updater daemon. Just a browser.
- **Clean Restart** — The container stops when you close the IDE and starts fresh every time.

## Prerequisites

Only **Podman** is required.

**Debian, Ubuntu, Linux Mint, Pop!_OS**
```bash
sudo apt update && sudo apt install -y podman
```

**Arch Linux, Manjaro, EndeavourOS**
```bash
sudo pacman -S podman
```

**Fedora, CentOS, AlmaLinux**
```bash
sudo dnf install -y podman
```

**openSUSE**
```bash
sudo zypper install -y podman
```

## Installation

1. Clone this repository

```bash
git clone https://github.com/M-Wham/ag-jail.git
cd ag-jail
```

2. Run the installer

```bash
chmod +x install.sh
./install.sh
```

The installer will set up the container, install ungoogled-chromium and Antigravity inside it,
and add four commands to `~/.local/bin`. The first run takes a few minutes.

## Usage

**ag-start** — Launch the IDE.
```bash
ag-start
```

**ag-kill** — Stop the container and all background agents.
```bash
ag-kill
```

**ag-update** — Update Antigravity and ungoogled-chromium.
```bash
ag-update
```

**ag-enter** — Open a shell inside the container. Use this to install extra tools or debug.
```bash
ag-enter
```

## Configuration

### Git & SSH

The jail starts with a clean slate and has no access to your host SSH keys by default.

Enter the jail shell:
```bash
ag-enter
```

Configure Git identity:
```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

Set up SSH keys — pick one:

**Option A — Copy from host** (run on your host, not inside the jail):
```bash
mkdir -p ~/Antigravity-Jail/.ssh
cp ~/.ssh/id_ed25519* ~/Antigravity-Jail/.ssh/
chmod 600 ~/Antigravity-Jail/.ssh/id_ed25519
```

**Option B — Generate new keys inside the jail**:
```bash
ssh-keygen -t ed25519 -C "ag-jail-key"
```

### Web Development

When running a dev server (e.g. `npm run dev`, `python -m http.server`), bind to `0.0.0.0`
or use the `--host` flag so the port is reachable from your host machine.

Links opened by the IDE go to ungoogled-chromium inside the jail, not your host browser.

## Installing Additional Software

The container does not see anything installed on your host. To add tools (Node.js, Python, Go,
etc.), install them inside the jail:

```bash
ag-enter
sudo apt update
sudo apt install -y python3 git nodejs
```

Packages persist between sessions. The next time you run `ag-start` they will be available.
