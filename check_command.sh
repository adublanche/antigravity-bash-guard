#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# check_command.sh - Antigravity CLI PreInvocation Hook (Full-Screen Buffer Modal)
# Intercepts conversational prompts, checks for common shell commands, and
# presents a full-screen alternate buffer modal (arrow keys, Enter, Esc).
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

if [[ ! "$PROMPT" =~ $CMD_REGEX ]]; then
    # Not a shell command: allow prompt to proceed to AI model
    cat << 'EOF'
{
  "terminationBehavior": ""
}
EOF
    exit 0
fi

MATCHED_CMD="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
MATCHED_CMD="$(echo -e "${MATCHED_CMD}" | sed -e 's/[[:space:]]*$//')"

# Helper for JSON string escaping
json_escape() {
    if command -v python3 >/dev/null 2>&1; then
        printf "%s" "$1" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null || printf "%s" "$1"
    else
        printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
    fi
}

SAFE_CMD=$(json_escape "$MATCHED_CMD")
SAFE_PROMPT=$(json_escape "$PROMPT")

# If no interactive TTY is available, fall back to instant hard stop
if ! exec 3< /dev/tty 3> /dev/tty 2>/dev/null; then
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

# -----------------------------------------------------------------------------
# Interactive Full-Screen Buffer Modal
# -----------------------------------------------------------------------------
OLD_STTY=""
if OLD_STTY=$(stty -g <&3 2>/dev/null); then
    :
fi

cleanup_terminal() {
    # Restore cursor, exit alternate screen buffer, restore stty
    printf '\033[?25h\033[?1049l' >&3 2>/dev/null || true
    if [[ -n "$OLD_STTY" ]]; then
        stty "$OLD_STTY" <&3 2>/dev/null || true
    fi
    exec 3<&- 3>&- 2>/dev/null || true
}
trap cleanup_terminal EXIT INT TERM

# Enter alternate screen buffer, clear screen, hide cursor
printf '\033[?1049h\033[H\033[2J\033[?25l' >&3
stty raw -echo <&3 2>/dev/null || true

read_key() {
    local k1 k2 k3
    IFS= read -rsn1 -u 3 k1 || { echo "EOF"; return; }
    if [[ "$k1" == $'\x1b' ]]; then
        # Check if an escape sequence follows within 50ms
        if IFS= read -rsn1 -t 0.05 -u 3 k2; then
            if [[ "$k2" == "[" || "$k2" == "O" ]]; then
                if IFS= read -rsn1 -t 0.05 -u 3 k3; then
                    case "$k3" in
                        A) echo "UP"; return ;;
                        B) echo "DOWN"; return ;;
                        C) echo "RIGHT"; return ;;
                        D) echo "LEFT"; return ;;
                        *) echo "ESC"; return ;;
                    esac
                fi
            fi
            echo "ESC"
            return
        fi
        echo "ESC"
        return
    elif [[ "$k1" == "" || "$k1" == $'\r' || "$k1" == $'\n' ]]; then
        echo "ENTER"
        return
    elif [[ "$k1" == $'\x03' ]]; then
        echo "CTRL_C"
        return
    elif [[ "$k1" == $'\t' ]]; then
        echo "TAB"
        return
    fi
    echo "$k1"
}

SELECTED=0
TOTAL_OPTIONS=3

draw_menu() {
    # Move cursor home without clearing whole buffer to avoid flicker
    printf '\033[H\r' >&3
    printf '\033[K\r\n' >&3
    printf '\033[K  \033[1;33m🛡️  Antigravity Bash Guard\033[0m\r\n' >&3
    printf '\033[K  \033[90m─────────────────────────────────────────────────────────────\033[0m\r\n' >&3
    printf '\033[K  Detected shell command: \033[1;37m%s\033[0m\r\n' "$MATCHED_CMD" >&3
    printf '\033[K  Full prompt:            \033[36m%s\033[0m\r\n' "$PROMPT" >&3
    printf '\033[K\r\n' >&3
    printf '\033[K  \033[1mHow would you like to handle this input?\033[0m\r\n' >&3
    printf '\033[K  \033[90mUse ↑ / ↓ arrow keys (or 1-3), Enter to select, Esc to abort:\033[0m\r\n' >&3
    printf '\033[K\r\n' >&3

    if [[ "$SELECTED" -eq 0 ]]; then
        printf '\033[K  \033[1;36m❯ [1] CMD Command  \033[0m \033[90m- Cancel prompt & execute directly in shell (!%s)\033[0m\r\n' "$PROMPT" >&3
    else
        printf '\033[K    \033[0m[1] CMD Command  \033[0m \033[90m- Cancel prompt & execute directly in shell (!%s)\033[0m\r\n' "$PROMPT" >&3
    fi

    if [[ "$SELECTED" -eq 1 ]]; then
        printf '\033[K  \033[1;36m❯ [2] AI Prompt    \033[0m \033[90m- Send to Antigravity as a conversational prompt\033[0m\r\n' >&3
    else
        printf '\033[K    \033[0m[2] AI Prompt    \033[0m \033[90m- Send to Antigravity as a conversational prompt\033[0m\r\n' >&3
    fi

    if [[ "$SELECTED" -eq 2 ]]; then
        printf '\033[K  \033[1;36m❯ [3] Cancel (Esc) \033[0m \033[90m- Abort turn cleanly (0 AI tokens spent)\033[0m\r\n' >&3
    else
        printf '\033[K    \033[0m[3] Cancel (Esc) \033[0m \033[90m- Abort turn cleanly (0 AI tokens spent)\033[0m\r\n' >&3
    fi
    printf '\033[K\r\n' >&3
}

ACTION="cancel"
while true; do
    draw_menu
    KEY=$(read_key)
    case "$KEY" in
        UP|k|K)
            SELECTED=$(( (SELECTED - 1 + TOTAL_OPTIONS) % TOTAL_OPTIONS ))
            ;;
        DOWN|j|J|TAB)
            SELECTED=$(( (SELECTED + 1) % TOTAL_OPTIONS ))
            ;;
        ENTER)
            if [[ "$SELECTED" -eq 0 ]]; then ACTION="cmd"; fi
            if [[ "$SELECTED" -eq 1 ]]; then ACTION="prompt"; fi
            if [[ "$SELECTED" -eq 2 ]]; then ACTION="cancel"; fi
            break
            ;;
        1|c|C)
            ACTION="cmd"
            break
            ;;
        2|p|P)
            ACTION="prompt"
            break
            ;;
        3|q|Q|ESC|CTRL_C|EOF)
            ACTION="cancel"
            break
            ;;
        *)
            ;;
    esac
done

# Clean up alternate buffer immediately before outputting JSON response
cleanup_terminal
trap - EXIT INT TERM

if [[ "$ACTION" == "prompt" ]]; then
    cat << 'EOF'
{
  "terminationBehavior": ""
}
EOF
    exit 0
elif [[ "$ACTION" == "cmd" ]]; then
    cat << EOF
{
  "terminationBehavior": "terminate",
  "injectSteps": [
    {
      "errorMessage": {
        "userMessage": "Command cancelled. Prefix with '!' (e.g. '!${SAFE_PROMPT}') to execute directly in your shell."
      }
    }
  ]
}
EOF
    exit 0
else
    # Aborted / Cancelled with Esc: terminate turn cleanly without error or tokens
    cat << 'EOF'
{
  "terminationBehavior": "terminate"
}
EOF
    exit 0
fi
