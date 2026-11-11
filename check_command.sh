#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# check_command.sh - Antigravity CLI PreInvocation Hook
# Intercepts conversational prompts and guards against accidental local terminal
# command execution when the '!' prefix is omitted.
# -----------------------------------------------------------------------------
set -euo pipefail

# Read stdin JSON payload delivered by Antigravity PreInvocation hook
PAYLOAD=$(cat)

# Extract "prompt" string using python3 (with fallback to jq or regex)
PROMPT=""
if command -v python3 >/dev/null 2>&1; then
    PROMPT=$(python3 -c "
import sys, json
try:
    data = json.loads(sys.argv[1])
    p = data.get('prompt')
    if p is None:
        p = data.get('lastUserInput', '')
    print(p if p is not None else '')
except Exception:
    print('')
" "$PAYLOAD")
elif command -v jq >/dev/null 2>&1; then
    PROMPT=$(echo "$PAYLOAD" | jq -r '.prompt // .lastUserInput // empty')
else
    PROMPT=$(echo "$PAYLOAD" | sed -n 's/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
fi

# Regex matching common terminal commands at the start of the prompt:
# ls, cd, pwd, grep, find, cat, npm, git, python, docker, agy
# Accounts for optional leading whitespace and ensures the command is a discrete token
CMD_REGEX="^[[:space:]]*(ls|cd|pwd|grep|find|cat|npm|git|python|docker|agy)([[:space:]]|$)"

if [[ "$PROMPT" =~ $CMD_REGEX ]]; then
    MATCHED_CMD="${BASH_REMATCH[1]}"
    cat << EOF_JSON
{
  "allow_tool": false,
  "deny_reason": "Accidental terminal command detected ('${MATCHED_CMD}'). Antigravity requires shell commands to be prefixed with '!' (e.g., '!${MATCHED_CMD} ...').",
  "terminationBehavior": "terminate",
  "injectSteps": [
    {
      "errorMessage": {
        "userMessage": "Accidental terminal command detected ('${MATCHED_CMD}'). Antigravity requires shell commands to be prefixed with '!' (e.g., '!${MATCHED_CMD} ...')."
      }
    }
  ]
}
EOF_JSON
else
    cat << EOF_JSON
{
  "allow_tool": true,
  "terminationBehavior": ""
}
EOF_JSON
fi
