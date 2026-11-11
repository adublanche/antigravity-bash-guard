#!/usr/bin/env python3
"""
Antigravity CLI PreInvocation Hook - Bash Guard
Intercepts conversational prompts, checks for common shell commands, and
presents an interactive terminal dialog (arrow keys, Enter, Escape) to clarify intent.
"""
import sys
import json
import os
import re
import termios
import tty
import select

CMD_REGEX = re.compile(
    r'^\s*(sudo\s+)?(ls|cd|pwd|grep|find|cat|npm|npx|pnpm|yarn|git|python|python3|docker|docker-compose|agy|systemctl|service|journalctl|apt|apt-get|yum|dnf|pacman|curl|wget|ssh|scp|rsync|ping|netstat|ss|ip|ifconfig|kill|killall|ps|top|htop|df|du|free|chmod|chown|mkdir|rmdir|rm|cp|mv|touch|tar|zip|unzip|nano|vim|vi|echo|export|source)(\s+.*|$)',
    re.IGNORECASE
)

def output_allow():
    """Allow the invocation to proceed to the model."""
    sys.stdout.write(json.dumps({"terminationBehavior": ""}) + "\n")
    sys.stdout.flush()
    sys.exit(0)

def output_terminate(message):
    """Halt the invocation and display a notice to the user."""
    result = {
        "terminationBehavior": "terminate",
        "injectSteps": [
            {
                "errorMessage": {
                    "userMessage": message
                }
            }
        ]
    }
    sys.stdout.write(json.dumps(result) + "\n")
    sys.stdout.flush()
    sys.exit(0)

def show_interactive_menu(cmd_name, full_prompt):
    """Presents an interactive selector on /dev/tty matching CLI style."""
    try:
        tty_fd = os.open('/dev/tty', os.O_RDWR)
    except Exception:
        # Non-interactive fallback
        output_terminate(
            f"Accidental terminal command detected ('{cmd_name}'). "
            f"Prefix with '!' (e.g., '!{full_prompt}') to execute directly in your shell."
        )

    old_settings = termios.tcgetattr(tty_fd)
    tty_out = os.fdopen(tty_fd, 'w', encoding='utf-8', buffering=1)
    tty_in = os.fdopen(tty_fd, 'r', encoding='utf-8')

    options = [
        ("CMD Command", f"Cancel prompt & run in shell with '!{full_prompt}'", "cmd"),
        ("AI Prompt", "Send to Antigravity as a conversational prompt", "prompt"),
        ("Cancel", "Abort and do nothing (Esc)", "cancel")
    ]
    selected = 0

    def render(first=False):
        if not first:
            tty_out.write(f"\033[{len(options)}A")
        for i, (label, desc, _) in enumerate(options):
            tty_out.write("\033[2K\r")
            if i == selected:
                tty_out.write(f"  \033[1;36m❯ {label:<14}\033[0m \033[90m({desc})\033[0m\n")
            else:
                tty_out.write(f"    {label:<14} \033[90m({desc})\033[0m\n")
        tty_out.flush()

    try:
        tty.setcbreak(tty_fd)

        # Header display
        tty_out.write("\n\033[1;33m[Antigravity Bash Guard]\033[0m ")
        tty_out.write(f"Detected terminal command: '\033[1;37m{cmd_name}\033[0m'\n")
        tty_out.write("\033[1m? How would you like to handle this input?\033[0m \033[90m(↑/↓ arrows, Enter to select, Esc to cancel)\033[0m\n")
        render(first=True)

        while True:
            ch = tty_in.read(1)
            if ch == '\x1b':  # Escape sequence or Esc
                r, _, _ = select.select([tty_fd], [], [], 0.05)
                if r:
                    seq = tty_in.read(2)
                    if seq in ('[A', 'OA'):  # Up Arrow
                        selected = (selected - 1) % len(options)
                        render()
                    elif seq in ('[B', 'OB'):  # Down Arrow
                        selected = (selected + 1) % len(options)
                        render()
                else:
                    # Bare Esc key pressed -> cancel
                    tty_out.write("\033[90m[Cancelled]\033[0m\n")
                    tty_out.flush()
                    return "cancel"
            elif ch in ('\r', '\n'):  # Enter
                action = options[selected][2]
                tty_out.write(f"\033[90mSelected: {options[selected][0]}\033[0m\n")
                tty_out.flush()
                return action
            elif ch in ('k', 'K'):  # Vim Up
                selected = (selected - 1) % len(options)
                render()
            elif ch in ('j', 'J'):  # Vim Down
                selected = (selected + 1) % len(options)
                render()
            elif ch == '\t':  # Tab
                selected = (selected + 1) % len(options)
                render()
            elif ch == '1':
                return options[0][2]
            elif ch == '2':
                return options[1][2]
            elif ch == '3':
                return options[2][2]
            elif ch in ('c', 'C'):
                return "cmd"
            elif ch in ('p', 'P'):
                return "prompt"
            elif ch == '\x03':  # Ctrl+C
                return "cancel"
    finally:
        termios.tcsetattr(tty_fd, termios.TCSADRAIN, old_settings)
        try:
            os.close(tty_fd)
        except Exception:
            pass

def main():
    # Read stdin payload delivered by Antigravity hook
    try:
        raw_input_data = sys.stdin.read()
        payload = json.loads(raw_input_data) if raw_input_data.strip() else {}
    except Exception:
        payload = {}

    prompt = (payload.get('lastUserInput') or payload.get('prompt') or '').strip()
    if not prompt:
        output_allow()

    match = CMD_REGEX.match(prompt)
    if not match:
        output_allow()

    matched_cmd = ((match.group(1) or '') + match.group(2)).strip()

    choice = show_interactive_menu(matched_cmd, prompt)
    if choice == "prompt":
        output_allow()
    elif choice == "cmd":
        output_terminate(
            f"Command cancelled. Prefix with '!' to execute in local terminal: !{prompt}"
        )
    else:
        # Cancelled / Escape
        output_terminate("Prompt cancelled (Esc).")

if __name__ == '__main__':
    main()
