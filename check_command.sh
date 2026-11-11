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

def output_terminate(message=None):
    """Halt the invocation, optionally injecting an error/notice message."""
    result = {
        "terminationBehavior": "terminate"
    }
    if message:
        result["injectSteps"] = [
            {
                "errorMessage": {
                    "userMessage": message
                }
            }
        ]
    sys.stdout.write(json.dumps(result) + "\n")
    sys.stdout.flush()
    sys.exit(0)

def read_raw_key(tty_fd):
    """Reads a single keypress or ANSI escape sequence from raw tty, waiting indefinitely."""
    try:
        select.select([tty_fd], [], [])
        b = os.read(tty_fd, 32)
    except Exception:
        return ''

    if not b:
        return ''

    # Handle Escape and escape sequences
    if b.startswith(b'\x1b'):
        if b in (b'\x1b[A', b'\x1bOA'):
            return 'UP'
        if b in (b'\x1b[B', b'\x1bOB'):
            return 'DOWN'
        if b in (b'\x1b[C', b'\x1bOC'):
            return 'RIGHT'
        if b in (b'\x1b[D', b'\x1bOD'):
            return 'LEFT'

        # If bare escape byte, check briefly for trailing arrow key bytes (WSL IPC buffer)
        if b == b'\x1b':
            r2, _, _ = select.select([tty_fd], [], [], 0.08)
            if r2:
                try:
                    more = os.read(tty_fd, 32)
                    b += more
                    if b in (b'\x1b[A', b'\x1bOA'):
                        return 'UP'
                    if b in (b'\x1b[B', b'\x1bOB'):
                        return 'DOWN'
                    if b in (b'\x1b[C', b'\x1bOC'):
                        return 'RIGHT'
                    if b in (b'\x1b[D', b'\x1bOD'):
                        return 'LEFT'
                except Exception:
                    pass

        # Any non-arrow escape sequence or bare escape registers as ESC
        return 'ESC'

    if b in (b'\r', b'\n'):
        return 'ENTER'
    if b == b'\x03':  # Ctrl+C
        return 'CTRL_C'
    if b == b'\t':
        return 'TAB'

    try:
        return b.decode('utf-8', errors='ignore')
    except Exception:
        return ''

def show_interactive_menu(cmd_name, full_prompt):
    """Presents a clean interactive selector on /dev/tty."""
    try:
        tty_fd = os.open('/dev/tty', os.O_RDWR)
    except Exception:
        # Non-interactive fallback
        output_terminate(
            f"Accidental terminal command detected ('{cmd_name}'). "
            f"Prefix with '!' (e.g., '!{full_prompt}') to execute directly in your shell."
        )

    old_settings = termios.tcgetattr(tty_fd)

    options = [
        ("CMD Command", f"Cancel prompt & run in shell with '!{full_prompt}'", "cmd"),
        ("AI Prompt", "Send to Antigravity as a conversational prompt", "prompt"),
        ("Cancel", "Abort and do nothing (Esc)", "cancel")
    ]
    selected = 0

    def tty_write(s):
        os.write(tty_fd, s.encode('utf-8'))

    try:
        tty.setcbreak(tty_fd)

        # Print header
        tty_write("\n")
        tty_write(f"\033[1;33m[Antigravity Bash Guard]\033[0m Detected shell command: '\033[1;37m{cmd_name}\033[0m'\n")
        tty_write("\033[1m? How would you like to handle this input?\033[0m \033[90m(↑/↓ arrows, Enter to select, Esc to cancel)\033[0m\n")

        # Print initial options
        for i, (label, desc, _) in enumerate(options):
            if i == selected:
                tty_write(f"  \033[1;36m❯ {label:<14}\033[0m \033[90m({desc})\033[0m\n")
            else:
                tty_write(f"    {label:<14} \033[90m({desc})\033[0m\n")

        action = "cancel"
        while True:
            key = read_raw_key(tty_fd)
            if key in ('UP', 'k', 'K'):
                selected = (selected - 1) % len(options)
            elif key in ('DOWN', 'j', 'J', 'TAB'):
                selected = (selected + 1) % len(options)
            elif key == 'ENTER':
                action = options[selected][2]
                break
            elif key in ('ESC', 'CTRL_C', 'q', 'Q'):
                action = "cancel"
                break
            elif key == '1':
                action = options[0][2]
                break
            elif key == '2':
                action = options[1][2]
                break
            elif key == '3':
                action = options[2][2]
                break
            elif key in ('c', 'C'):
                action = "cmd"
                break
            elif key in ('p', 'P'):
                action = "prompt"
                break
            else:
                continue

            # Redraw only the option rows
            tty_write(f"\033[{len(options)}A")
            for i, (label, desc, _) in enumerate(options):
                tty_write("\033[2K\r")
                if i == selected:
                    tty_write(f"  \033[1;36m❯ {label:<14}\033[0m \033[90m({desc})\033[0m\n")
                else:
                    tty_write(f"    {label:<14} \033[90m({desc})\033[0m\n")

        # Print outcome status cleanly
        if action == "cmd":
            tty_write(f"\033[1;36m[Antigravity Bash Guard]\033[0m Command cancelled. Run with: \033[1;37m!{full_prompt}\033[0m\n\n")
        elif action == "prompt":
            tty_write("\033[1;32m[Antigravity Bash Guard]\033[0m Proceeding to Antigravity as prompt...\n\n")
        else:
            tty_write("\033[90m[Antigravity Bash Guard] Cancelled (Esc).\033[0m\n\n")

        return action

    finally:
        termios.tcsetattr(tty_fd, termios.TCSADRAIN, old_settings)
        try:
            os.close(tty_fd)
        except Exception:
            pass

def main():
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
        # Cancel / Escape: abort cleanly without error block
        output_terminate()

if __name__ == '__main__':
    main()
