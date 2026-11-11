#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# check_command.sh - Antigravity CLI PreInvocation Hook (Instant Hard Guard)
# Intercepts conversational prompts and guards against accidental local terminal
# command execution when the '!' prefix is omitted.
# -----------------------------------------------------------------------------
set -euo pipefail

# Read stdin JSON payload delivered by Antigravity PreInvocation hook
PAYLOAD=$(cat)

# Extract "lastUserInput" or "prompt" from hook JSON payload
PROMPT=""
if command -v python3 >/dev/null 2>&1; then
    PROMPT=$(printf "%s" "$PAYLOAD" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    p = data.get('lastUserInput')
    if not p:
        p = data.get('prompt', '')
    print(p if p is not None else '')
except Exception:
    print('')
" 2>/dev/null || true)
elif command -v jq >/dev/null 2>&1; then
    PROMPT=$(printf "%s" "$PAYLOAD" | jq -r '.lastUserInput // .prompt // empty' 2>/dev/null || true)
else
    PROMPT=$(printf "%s" "$PAYLOAD" | sed -n 's/.*"lastUserInput"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    if [[ -z "$PROMPT" ]]; then
        PROMPT=$(printf "%s" "$PAYLOAD" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    fi
fi

# Trim whitespace
PROMPT="$(echo -e "${PROMPT}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

# If prompt is empty or starts with '!', allow immediately
if [[ -z "$PROMPT" || "$PROMPT" =~ ^! ]]; then
    cat << 'EOF'
{
  "terminationBehavior": ""
}
EOF
    exit 0
fi

# Regex matching common terminal commands (with optional sudo) at start of prompt
CMD_REGEX="^(sudo[[:space:]]+)?(ls|cd|pwd|grep|find|cat|npm|npx|pnpm|yarn|git|python|python3|docker|docker-compose|agy|systemctl|service|journalctl|apt|apt-get|yum|dnf|pacman|curl|wget|ssh|scp|rsync|ping|netstat|ss|ip|ifconfig|kill|killall|ps|top|htop|df|du|free|chmod|chown|mkdir|rmdir|rm|cp|mv|touch|tar|zip|unzip|nano|vim|vi|echo|export|source)([[:space:]]|$)"

if [[ "$PROMPT" =~ $CMD_REGEX ]]; then
    MATCHED_CMD="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    # Strip any trailing whitespace from matched command token
    MATCHED_CMD="$(echo -e "${MATCHED_CMD}" | sed -e 's/[[:space:]]*$//')"

    # Escape JSON special characters safely
    if command -v python3 >/dev/null 2>&1; then
        SAFE_CMD=$(printf "%s" "$MATCHED_CMD" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null || printf "%s" "$MATCHED_CMD")
        SAFE_PROMPT=$(printf "%s" "$PROMPT" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null || printf "%s" "$PROMPT")
    else
        SAFE_CMD=$(printf "%s" "$MATCHED_CMD" | sed 's/\\/\\\\/g; s/"/\\"/g')
        SAFE_PROMPT=$(printf "%s" "$PROMPT" | head -n 1 | sed 's/\\/\\\\/g; s/"/\\"/g')
    fi

    cat << EOF
{
  "terminationBehavior": "terminate",
  "injectSteps": [
    {
      "errorMessage": {
        "userMessage": "Accidental terminal command detected ('${SAFE_CMD}'). Antigravity CLI requires shell commands to be prefixed with '!' (e.g. '!${SAFE_PROMPT}'). Prompt blocked to avoid wasting AI tokens."
      }
    }
  ]
}
EOF
    exit 0
fi

# Not a shell command: allow prompt to proceed to AI model
cat << 'EOF'
{
  "terminationBehavior": ""
}
EOF
exit 0
