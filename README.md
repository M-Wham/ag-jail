ag-jail

A secure, isolated environment for running the Google Antigravity IDE and its browser on Linux.

ag-jail uses Podman and Distrobox to run the IDE in a restricted container. It keeps your main system clean, prevents background agents from persisting after exit, and ensures the IDE cannot access your personal files (SSH keys, Documents, etc.) unless explicitly allowed.

Demo:

https://github.com/user-attachments/assets/c92ac49b-d960-47ec-b1f3-ddc1bfe964cc

This tool was created as I tried to use Antigravity on my desktop but I was getting frustrated at the background processes and how they are persistent. Personally, I don't like things like this running in the background, seemingly for no reason. I find it invasive and suspicious, not to mention it is hogging resources you could be using to compile Chromium for the 23rd time.

Note: This setup does install a dedicated instance of Google Chrome, but it is completely sandboxed inside the container. It is used exclusively by the IDE and the Agent, meaning it has zero access to your host browser's history, cookies, or personal data.

FEATURES

- True Isolation: The IDE sees ~/Antigravity-Jail as its home folder.
- Zero Persistence: ag-kill instantly stops all background agents.
- Internal Browser: Automatically installs Chrome inside the jail for the AI Agent.
- Automated Install: Adds the official Google repositories and keys automatically.

PREREQUISITES

Before running the installer, you must have Podman and Distrobox installed.

Debian, Ubuntu, Linux Mint, Pop!_OS:

```bash
sudo apt update
sudo apt install -y podman distrobox
```

Arch Linux, Manjaro, EndeavourOS:

```bash
sudo pacman -S podman distrobox
```

Fedora, CentOS, AlmaLinux:

```bash
sudo dnf install -y podman distrobox
```

openSUSE:

```bash
sudo zypper install -y podman distrobox
```

INSTALLATION

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

USAGE

ag-start
Start Work. Launches the IDE.

```bash
ag-start
```

ag-kill
Stop Work. Instantly kills the container and all background agents.

```bash
ag-kill
```

ag-update
Update. Run this when the IDE notifies you of an update.

```bash
ag-update
```

CONFIGURATION

Git & SSH
The jail acts like a fresh computer and does not have access to your host SSH keys by default.

1. Enter the jail shell:

```bash
distrobox enter ag-safe
```

2. Configure Git identity:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

3. Set up SSH keys:

Option A (Copy from host):

```bash
mkdir -p ~/Antigravity-Jail/.ssh
cp ~/.ssh/id_ed25519* ~/Antigravity-Jail/.ssh/
```

Option B (Generate new):

```bash
ssh-keygen -t ed25519 -C "ag-jail-key"
```

Web Development

Servers:
When running servers (e.g., npm run dev or Python), use --host or bind to 0.0.0.0 to ensure the port is accessible.

Browser:
The environment uses an internal Chrome instance. Links clicked inside the IDE will open in the jail window.

INSTALLING ADDITIONAL SOFTWARE

Because ag-jail is a completely isolated environment, it does not see the software installed on your main system. If you need specific tools (like Python, Node.js, Go, or Vim) inside the IDE, you must install them inside the jail.

1. Enter the jail shell:

```bash
distrobox enter ag-safe
```

2. Install packages:
(This is an example installing Python and Git. Replace these with the packages you actually need.)

```bash
sudo apt update
sudo apt install -y python3 git
```

3. Done:
You can now exit the terminal. The next time you run ag-start, your tools will be available inside the IDE.
