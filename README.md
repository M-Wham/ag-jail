# ag-jail

A sandboxed environment for running the Google Antigravity IDE on Linux.

ag-jail uses Podman to run the IDE inside an isolated Ubuntu container. It keeps your main system clean, prevents background agents from persisting after exit, and blocks the IDE from accessing your personal files unless you explicitly allow it.

This was made out of frustration with Antigravity's background processes. I don't like things running in the background for no reason, it's invasive and a waste of resources.

The container runs ungoogled-chromium as its browser. It has no access to your host browser's history, cookies, or personal data. Links opened by the IDE stay inside the container.

## Features

- The IDE sees `~/Antigravity-Jail` as its home directory, your real home is not visible
- Killing the container takes every background agent with it
- D-Bus passthrough is blocked so the IDE cannot open your host browser
- Uses ungoogled-chromium with no Google telemetry or updater daemon
- The container stops when you close the IDE and starts clean every time

## Prerequisites

Only Podman is required.

**Debian, Ubuntu, Linux Mint, Pop!_OS**
```bash
sudo apt update && sudo apt install -y podman x11-xserver-utils slirp4netns
```

**Arch Linux, Manjaro, EndeavourOS**
```bash
sudo pacman -S podman xorg-xhost slirp4netns
```

**Fedora, CentOS, AlmaLinux**
```bash
sudo dnf install -y podman xorg-x11-server-utils slirp4netns
```

**openSUSE**
```bash
sudo zypper install -y podman xhost slirp4netns
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

The installer sets up the container, installs ungoogled-chromium and Antigravity inside it, and adds four commands to `~/.local/bin`. The first run takes a few minutes.

## Usage

```bash
ag-start   # launch the IDE
ag-kill    # stop the container and all background agents
ag-update  # update Antigravity and ungoogled-chromium
ag-enter   # open a shell inside the container for installing tools or debugging
```

## Configuration

### Git and SSH

The jail has no access to your host SSH keys by default. To set it up, enter the jail first:

```bash
ag-enter
```

Configure Git:
```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

For SSH keys you have two options:

Copy from host (run this on your host, not inside the jail):
```bash
mkdir -p ~/Antigravity-Jail/.ssh
cp ~/.ssh/id_ed25519* ~/Antigravity-Jail/.ssh/
chmod 600 ~/Antigravity-Jail/.ssh/id_ed25519
```

Or generate new keys inside the jail:
```bash
ssh-keygen -t ed25519 -C "ag-jail-key"
```

### Web Development

When running a dev server, bind to `0.0.0.0` or use the `--host` flag so the port is reachable from your host machine.

## Installing Additional Software

The container does not see anything installed on your host. To add tools, install them inside the jail:

```bash
ag-enter
sudo apt update
sudo apt install -y python3 git nodejs
```

Packages persist between sessions.
