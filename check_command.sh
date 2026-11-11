#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# check_command.sh - Antigravity CLI PreInvocation Hook
# Intercepts conversational prompts and guards against accidental local terminal
# command execution when the '!' prefix is omitted.
# -----------------------------------------------------------------------------
set -euo pipefail

# Read stdin JSON payload delivered by Antigravity PreInvocation hook
PAYLOAD=$(cat)

# Extract "prompt" / "lastUserInput" string using python3 (with fallback to jq or regex)
PROMPT=""
if command -v python3 >/dev/null 2>&1; then
    PROMPT=$(python3 -c "
import sys, json
try:
    data = json.loads(sys.argv[1])
    # Antigravity hook payload delivers 'lastUserInput' (with 'prompt' fallback)
    p = data.get('lastUserInput')
    if not p:
        p = data.get('prompt', '')
    print(p if p is not None else '')
except Exception:
    print('')
" "$PAYLOAD")
elif command -v jq >/dev/null 2>&1; then
    PROMPT=$(echo "$PAYLOAD" | jq -r '.lastUserInput // .prompt // empty')
else
    PROMPT=$(echo "$PAYLOAD" | sed -n 's/.*"lastUserInput"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    if [[ -z "$PROMPT" ]]; then
        PROMPT=$(echo "$PAYLOAD" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    fi
fi

# Regex matching common terminal commands (with optional sudo) at start of prompt
CMD_REGEX="^[[:space:]]*(sudo[[:space:]]+)?(ls|cd|pwd|grep|find|cat|npm|npx|pnpm|yarn|git|python|python3|docker|docker-compose|agy|systemctl|service|journalctl|apt|apt-get|yum|dnf|pacman|curl|wget|ssh|scp|rsync|ping|netstat|ss|ip|ifconfig|kill|killall|ps|top|htop|df|du|free|chmod|chown|mkdir|rmdir|rm|cp|mv|touch|tar|zip|unzip|nano|vim|vi|echo|export|source)([[:space:]]|$)"

if [[ "$PROMPT" =~ $CMD_REGEX ]]; then
    MATCHED_CMD="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    
    # Check if an interactive TTY is available to ask the user
    if exec 3< /dev/tty 3> /dev/tty 2>/dev/null; then
        printf "\n\033[1;33m[Antigravity Bash Guard]\033[0m Detected command: '\033[1m%s\033[0m'\n" "$MATCHED_CMD" >&3
        printf "Do you mean it as a prompt or as a cmd command?\n" >&3
        printf "  [p] Prompt      (send to Antigravity AI)\n" >&3
        printf "  [c] CMD command (cancel & prepend with '!')\n" >&3
        printf "Choose [p/C]: " >&3
        
        CHOICE=""
        read -r CHOICE <&3 || CHOICE="c"
        exec 3<&- 3>&-
        CHOICE=$(echo "$CHOICE" | tr -d '\r' | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [[ "$CHOICE" == "p" || "$CHOICE" == "prompt" ]]; then
            cat << EOF_JSON
{
  "terminationBehavior": ""
}
EOF_JSON
            exit 0
        fi
    fi

    # If chosen 'c' or non-interactive fallback: block and remind to use '!'
    cat << EOF_JSON
{
  "terminationBehavior": "terminate",
  "injectSteps": [
    {
      "errorMessage": {
        "userMessage": "Command cancelled. Prefix with '!' (e.g., '!${PROMPT}') to execute directly in your shell."
      }
    }
  ]
}
EOF_JSON
else
    cat << EOF_JSON
{
  "terminationBehavior": ""
}
EOF_JSON
fi
