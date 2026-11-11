# 🛡️ Antigravity Bash Guard

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Release](https://img.shields.io/badge/release-v1.0.0-green.svg)](https://github.com/adublanche/antigravity-bash-guard/releases)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20WSL%20%7C%20macOS-lightgrey.svg)](#requirements)
[![Antigravity CLI](https://img.shields.io/badge/Antigravity-CLI%20Compatible-orange.svg)](https://github.com/adublanche/antigravity-bash-guard)

A lightweight `PreInvocation` lifecycle guard for the **Google Antigravity CLI (`agy`)**. It prevents you from accidentally sending local shell commands (like `git status`, `ls -la`, or `docker ps`) as LLM conversational prompts when you forget to prepend them with an exclamation mark (`!`).

---

## 🎯 The Problem

In the Antigravity CLI, prepending commands with an exclamation mark (`!`) executes them directly in your local shell:

```bash
# Correct: Runs instantly in your local bash shell
!git status
!ls -la
```

However, muscle memory often leads developers to type raw terminal commands directly into the prompt:

```bash
# Mistake: Accidentally sent as an LLM prompt!
git status
```

Without a guard, this triggers a round-trip to the model, wasting time, tokens, and quota while returning a conversational explanation of git instead of executing the command.

---

## 💡 The Solution (Full-Screen Buffer Modal)

**Antigravity Bash Guard** registers a `PreInvocation` lifecycle hook in `~/.gemini/config/hooks.json`. Before any prompt is sent to the LLM:

1. It inspects the prompt payload (`lastUserInput`).
2. It detects common local shell commands (with optional `sudo`), such as `git`, `systemctl`, `docker`, `npm`, `apt`, `ls`, etc.
3. If detected, it opens a clean **Full-Screen Alternate Buffer modal** (`\033[?1049h`):
   ```text
     🛡️  Antigravity Bash Guard
     ─────────────────────────────────────────────────────────────
     Detected shell command: git
     Full prompt:            git status

     How would you like to handle this input?
     Use ↑ / ↓ arrow keys (or 1-3), Enter to select, Esc to abort:

     ❯ [1] CMD Command   - Cancel prompt & execute directly in shell (!git status)
       [2] AI Prompt     - Send to Antigravity as a conversational prompt
       [3] Cancel (Esc)  - Abort turn cleanly (0 AI tokens spent)
   ```
4. **Interactive Controls**:
   - **`↑` / `↓` Arrow Keys** (or `k` / `j`): Navigate options
   - **`Enter`**: Confirm highlighted selection
   - **`1` / `2` / `3`**: Quick numerical selection
   - **`c` / `p`**: Instant select `CMD` or `Prompt`
   - **`Esc` / `q`**: Abort turn cleanly without sending anything or wasting tokens
5. Upon exit, the alternate screen buffer is restored byte-for-byte (`\033[?1049l`), leaving the original terminal output completely intact.

```mermaid
flowchart TD
    A[User enters prompt] --> B{Starts with terminal command?}
    B -- "No / Prefixed with '!'" --> C["Allow (terminationBehavior: '')"] --> D[Proceed to Model / Shell Execution]
    B -- "Yes (e.g., 'git status')" --> E["Full-Screen Alternate Buffer Modal"]
    E -- "[2 / p] AI Prompt" --> C
    E -- "[1 / c] CMD Command" --> F["Cancel (terminationBehavior: 'terminate')"] --> G["Remind: Run '!<cmd>'"]
    E -- "[3 / Esc] Cancel" --> H["Abort Turn cleanly (0 tokens spent)"]
```

---

## ⚡ Quick Start (One-Line Install)

Run the following command directly in your WSL or Linux terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/adublanche/antigravity-bash-guard/main/install.sh | bash
```

---

## 📦 Manual Installation

If you prefer to install manually from source:

1. **Clone the repository:**
   ```bash
   git clone https://github.com/adublanche/antigravity-bash-guard.git
   cd antigravity-bash-guard
   ```

2. **Run the local installer:**
   ```bash
   bash install.sh
   ```

---

## ⚙️ How It Works & Configuration

The installer deploys `check_command.sh` to `~/.gemini/config/hooks/` and safely updates `~/.gemini/config/hooks.json`:

```json
{
  "bash-guard": {
    "PreInvocation": [
      {
        "type": "command",
        "command": "/home/YOUR_USER/.gemini/config/hooks/check_command.sh",
        "timeout": 30
      }
    ]
  }
}
```

### Monitored Commands

By default, the hook intercepts commands starting with optional `sudo`, including:
- **Development & Version Control**: `git`, `npm`, `npx`, `pnpm`, `yarn`, `python`, `python3`, `docker`, `docker-compose`, `agy`
- **System Administration**: `systemctl`, `service`, `journalctl`, `apt`, `apt-get`, `yum`, `dnf`, `pacman`
- **Filesystem & Utilities**: `ls`, `cd`, `pwd`, `grep`, `find`, `cat`, `mkdir`, `rmdir`, `rm`, `cp`, `mv`, `touch`, `chmod`, `chown`, `tar`, `zip`, `unzip`
- **Networking & Process**: `curl`, `wget`, `ssh`, `scp`, `rsync`, `ping`, `netstat`, `ss`, `ip`, `ifconfig`, `kill`, `killall`, `ps`, `top`, `htop`, `df`, `du`, `free`
- **Shell & Editors**: `nano`, `vim`, `vi`, `echo`, `export`, `source`

To customize the list of intercepted commands, edit `~/.gemini/config/hooks/check_command.sh` and update the `CMD_REGEX` variable.

---

## 🗑️ Uninstallation

To remove Antigravity Bash Guard:

1. **Remove the script:**
   ```bash
   rm -f ~/.gemini/config/hooks/check_command.sh
   ```

2. **Remove the hook from `hooks.json`:**
   ```bash
   python3 -c "
   import json, os
   p = os.path.expanduser('~/.gemini/config/hooks.json')
   if os.path.exists(p):
       with open(p, 'r') as f: d = json.load(f)
       d.pop('bash-guard', None)
       with open(p, 'w') as f: json.dump(d, f, indent=2); f.write('\n')
       print('Hook removed successfully.')
   "
   ```

---

## 📋 Requirements

- Linux or Windows Subsystem for Linux (WSL) / macOS
- Bash 4+
- Python 3.6+ (for safe JSON handling)
- Antigravity CLI (`agy`)

---

## 🤝 Contributing

Contributions, feature suggestions, and pull requests are welcome!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 📄 License

Distributed under the MIT License. See `LICENSE` for more information.
