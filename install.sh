#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# install.sh - Antigravity Bash Guard Installer
# Installs check_command.sh and configures ~/.gemini/config/hooks.json
# Usage: curl -fsSL https://raw.githubusercontent.com/adublanche/antigravity-bash-guard/main/install.sh | bash
# -----------------------------------------------------------------------------
set -euo pipefail

REPO_USER="${GITHUB_USER:-adublanche}"
REPO_NAME="antigravity-bash-guard"
BRANCH="${BRANCH:-main}"
RAW_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/check_command.sh"

HOOKS_DIR="${HOME}/.gemini/config/hooks"
HOOKS_CONFIG="${HOME}/.gemini/config/hooks.json"
TARGET_SCRIPT="${HOOKS_DIR}/check_command.sh"

echo "====================================================="
echo "🛡️  Installing Antigravity Bash Guard..."
echo "====================================================="

# Ensure target hooks directory exists
mkdir -p "${HOOKS_DIR}"

# Download or copy check_command.sh
if [[ -f "./check_command.sh" && "${REPO_USER}" == "adublanche" ]]; then
    echo "[+] Found local check_command.sh. Copying to ${TARGET_SCRIPT}..."
    cp "./check_command.sh" "${TARGET_SCRIPT}"
else
    echo "[+] Downloading check_command.sh from raw GitHub..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "${RAW_URL}" -o "${TARGET_SCRIPT}"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "${TARGET_SCRIPT}" "${RAW_URL}"
    else
        echo "[-] Error: curl or wget is required to download check_command.sh." >&2
        exit 1
    fi
fi

# Make the hook executable
echo "[+] Setting executable permissions on ${TARGET_SCRIPT}..."
chmod +x "${TARGET_SCRIPT}"

# Safely inject hook into hooks.json using Python
echo "[+] Safely configuring PreInvocation hook in ${HOOKS_CONFIG}..."
python3 - << 'PYEOF'
import json
import os
import sys

hooks_file = os.path.expanduser("~/.gemini/config/hooks.json")
script_path = os.path.expanduser("~/.gemini/config/hooks/check_command.sh")

data = {}
if os.path.exists(hooks_file):
    try:
        with open(hooks_file, "r", encoding="utf-8") as f:
            content = f.read().strip()
            if content:
                data = json.loads(content)
    except Exception as e:
        sys.stderr.write(f"[-] Warning: Failed to parse existing {hooks_file}: {e}\n")
        data = {}

if not isinstance(data, dict):
    data = {}

# Ensure PreInvocation is an array
if "PreInvocation" not in data or not isinstance(data["PreInvocation"], list):
    data["PreInvocation"] = []

hook_entry = {
    "type": "command",
    "command": script_path,
    "timeout": 15
}

# Safely update existing entry or append
entry_updated = False
for idx, entry in enumerate(data["PreInvocation"]):
    if isinstance(entry, dict) and entry.get("command") == script_path:
        data["PreInvocation"][idx] = hook_entry
        entry_updated = True
        break

if not entry_updated:
    data["PreInvocation"].append(hook_entry)

os.makedirs(os.path.dirname(hooks_file), exist_ok=True)
with open(hooks_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"[✔] Successfully registered PreInvocation hook in {hooks_file}")
PYEOF

echo "====================================================="
echo "✅ Antigravity Bash Guard successfully installed!"
echo "   Shell commands entered without '!' will now be blocked."
echo "====================================================="
