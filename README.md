# ag-jail

A secure, isolated environment for running the **Google Antigravity IDE** on Linux.

**ag-jail** uses **Podman** and **Distrobox** to run the IDE in a restricted container. It keeps your main system clean, prevents background agents from persisting after exit, and ensures the IDE cannot access your personal files (SSH keys, Documents, etc.) unless explicitly allowed.

## Features

- **True Isolation:** The IDE sees `~/Antigravity-Jail` as its home folder.
- **Zero Persistence:** `ag-kill` instantly stops all background agents.
- **Internal Browser:** Automatically installs Chrome inside the jail for the AI Agent.
- **Automated Install:** Adds the official Google repositories and keys automatically.

## Prerequisites

Before running the installer, you must have **Podman** and **Distrobox** installed on your system. Click your distribution below for instructions.

<details>
<summary><strong>Debian, Ubuntu, Linux Mint, Pop!_OS</strong></summary>

```bash
sudo apt update
sudo apt install podman distrobox
```

</details>

<details>
<summary><strong>Arch Linux, Manjaro, EndeavourOS</strong></summary>

```bash
sudo pacman -S podman distrobox
```

</details>

<details>
<summary><strong>Fedora, CentOS, AlmaLinux</strong></summary>

```bash
sudo dnf install podman distrobox
```

</details>

<details>
<summary><strong>openSUSE</strong></summary>

```bash
sudo zypper install podman distrobox
```

</details>

<details>
<summary><strong>SteamOS (Steam Deck)</strong></summary>

Distrobox is often pre-installed or available via Podman.

```bash
# If not installed:
distrobox-export --app podman
```

</details>

## Installation

1.  **Clone this repository**

    ```bash
    git clone [https://github.com/M-Wham/ag-jail.git](https://github.com/M-Wham/ag-jail.git)
    cd ag-jail
    ```

2.  **Run the installer**

    ```bash
    chmod +x install.sh
    ./install.sh
    ```

## Usage

| Command         | Action                                                                  |
| :-------------- | :---------------------------------------------------------------------- |
| **`ag-start`**  | **Start Work.** Launches the IDE.                                       |
| **`ag-kill`**   | **Stop Work.** Instantly kills the container and all background agents. |
| **`ag-update`** | **Update.** Run this when the IDE notifies you of an update.            |

## Configuration

### Git & SSH

The jail acts like a fresh computer and does not have access to your host SSH keys by default.

1.  **Enter the jail shell:**
    ```bash
    distrobox enter ag-safe
    ```
2.  **Configure Git identity:**
    ```bash
    git config --global user.name "Your Name"
    git config --global user.email "you@example.com"
    ```
3.  **Set up SSH keys:**
    - _Option A (Copy from host):_ `cp ~/.ssh/id_ed25519* ~/Antigravity-Jail/.ssh/`
    - _Option B (Generate new):_ `ssh-keygen -t ed25519 -C "ag-jail-key"`

### Web Development

- **Servers:** When running servers (e.g., `npm run dev` or Python), use `--host` or bind to `0.0.0.0` to ensure the port is accessible.
- **Browser:** The environment uses an internal Chrome instance. Links clicked inside the IDE will open in the jail window.
