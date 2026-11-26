#!/usr/bin/env python3
"""Run from a Linux terminal: python3 ecorouter-screenshots.py TASK ROLE USER@HOST."""

import argparse
import os
import re
import sys
from contextlib import contextmanager
from select import select
from time import monotonic


PROMPT = re.compile(rb"(?:^|\n)([A-Za-z0-9_.:@()/-]+[>#])[ \t]*$")
ANSI = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]")
PAGER = re.compile(rb"(?:--\s*more\s*--|press (?:the )?space(?:bar)?)[^\n]*$", re.I)
ERROR = re.compile(r"(?im)^\s*(?:%|(?:error|unknown|invalid|incomplete|ambiguous)\b)")
AUTH_KEY = re.compile(r"(?i)^(\s*(?:ip ospf )?(?:message-digest-key\s+\d+\s+md5|authentication-key))\b.*$")
CONFIG_LINE = re.compile(
    r"^\s*(?:interface\b|service-instance\b|encapsulation\b|connect\b|ip address\b|"
    r"tunnel\b|ip ospf\b|ospf authentication\b|message-digest-key\b|"
    r"authentication-key\b|router ospf\b|ip pool\b|dhcp-server\b|pool\b|"
    r"gateway\b|mask\b|dns\b|domain-name\b|ip nat\b|ntp (?:timezone|server)\b)",
    re.I,
)


def command_list(task, role, dhcp_interface):
    if task == "2":
        commands = ["show ip nat static"]
        if role == "br-rtr":
            commands.append("show ntp status")
        commands.append("show running-config")
        return commands

    commands = [
        "show ip interface brief",
        "show ip route",
        "show ip ospf neighbor",
        "show ip ospf interface",
        "show ip nat translations",
        "show users localdb",
    ]
    if role == "hq-rtr":
        commands.append(f"show dhcp-server clients {dhcp_interface}")
    commands.append("show running-config")
    return commands


@contextmanager
def raw_input(enabled):
    if not enabled:
        yield
        return
    import termios
    import tty

    terminal = sys.stdin.fileno()
    original = termios.tcgetattr(terminal)
    try:
        tty.setraw(terminal)
        yield
    finally:
        termios.tcsetattr(terminal, termios.TCSANOW, original)


def wait_for_prompt(fd, *, interactive=False, timeout=40):
    deadline = monotonic() + timeout
    saved = []
    current = b""
    terminal = sys.stdin.fileno()
    readers = [fd, terminal] if interactive else [fd]
    with raw_input(interactive):
        while True:
            ready, _, _ = select(readers, [], [], max(0, deadline - monotonic()))
            if not ready or monotonic() >= deadline:
                raise TimeoutError("EcoRouter не вернул приглашение командной строки.")
            if terminal in ready:
                typed = os.read(terminal, 1024)
                if not typed or b"\x03" in typed:
                    raise KeyboardInterrupt
                os.write(fd, typed)
            if fd not in ready:
                continue
            try:
                chunk = os.read(fd, 16384)
            except OSError as error:
                raise ConnectionError("SSH-сеанс завершился до приглашения EcoRouter.") from error
            if not chunk:
                raise ConnectionError("SSH-сеанс завершился до приглашения EcoRouter.")
            if interactive:
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()
            current += chunk
            clean = ANSI.sub(b"", current).replace(b"\r", b"").replace(b"\x08", b"")
            prompt = PROMPT.search(clean)
            if prompt:
                saved.append(clean[:prompt.start()])
                return prompt.group(1).decode(), b"\n".join(saved).decode("utf-8", "replace")
            pager = PAGER.search(clean)
            if pager:
                saved.append(clean[:pager.start()])
                current = b""
                os.write(fd, b" ")


def display_output(output, command, task):
    lines = output.strip("\n").splitlines()
    if lines and lines[0].strip() == command:
        lines.pop(0)
    if command != "show running-config":
        return lines
    if task == "2":
        lines = [line for line in lines if line.lstrip().startswith(("ip nat ", "ntp server ", "ntp timezone "))]
    else:
        lines = [AUTH_KEY.sub(r"\1 [скрыто]", line) for line in lines if CONFIG_LINE.match(line)]
    return lines


def show_frames(prompt, command, lines, page_lines):
    for start in range(0, max(1, len(lines)), page_lines):
        if sys.stdout.isatty() and os.environ.get("TERM", "dumb") != "dumb":
            print("\033[2J\033[H", end="")
        print(f"{prompt}{command}")
        page = lines[start:start + page_lines]
        if page:
            print("\n".join(page))
        if input(f"{prompt} ").strip().lower() == "q":
            return False
    return True


def main():
    parser = argparse.ArgumentParser(description="Проверки EcoRouter с паузами для скриншотов.")
    parser.add_argument("task", choices=("1", "2"), help="номер задания")
    parser.add_argument("role", choices=("hq-rtr", "br-rtr"), help="роль маршрутизатора")
    parser.add_argument("target", help="пользователь@IP маршрутизатора")
    parser.add_argument("--port", type=int, default=22, help="SSH-порт")
    parser.add_argument("--dhcp-interface", default="vl200", help="интерфейс DHCP для HQ-RTR")
    parser.add_argument("--page-lines", type=int, default=18, help="строк вывода в одном кадре")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.:/-]+", args.dhcp_interface):
        parser.error("некорректное имя DHCP-интерфейса")
    if args.page_lines < 1 or not 1 <= args.port <= 65535:
        parser.error("проверь SSH-порт и число строк на кадр")
    if os.name != "posix" or not sys.stdin.isatty() or not sys.stdout.isatty():
        parser.error("выполни команду в интерактивном терминале Linux")

    import pty

    print(f"Подключение к {args.target}. Введи пароль, если запросит SSH.", flush=True)
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.execvp("ssh", ["ssh", "-tt", "-o", "ConnectTimeout=10", "-p", str(args.port), "--", args.target])
        except OSError as error:
            print(f"Не удалось запустить SSH: {error}", file=sys.stderr, flush=True)
            os._exit(127)

    try:
        prompt, _ = wait_for_prompt(fd, interactive=True, timeout=120)
        if prompt.endswith(">"):
            os.write(fd, b"enable\r")
            prompt, _ = wait_for_prompt(fd, interactive=True, timeout=120)
        if not prompt.endswith("#") or "(" in prompt:
            raise RuntimeError("Для проверок нужен административный режим EcoRouter с приглашением #.")

        for command in command_list(args.task, args.role, args.dhcp_interface):
            os.write(fd, (command + "\r").encode())
            prompt, output = wait_for_prompt(fd)
            lines = display_output(output, command, args.task)
            if not show_frames(prompt, command, lines, args.page_lines):
                return 0
            if command == "show ip nat static" and ERROR.search(output):
                fallback = "show ip nat translations"
                os.write(fd, (fallback + "\r").encode())
                prompt, output = wait_for_prompt(fd)
                lines = display_output(output, fallback, args.task)
                if not show_frames(prompt, fallback, lines, args.page_lines):
                    return 0
        print("\nГотово. Проверки маршрутизатора закончены.")
        return 0
    except (ConnectionError, TimeoutError, RuntimeError) as error:
        print(f"\n{error}", file=sys.stderr)
        return 1
    except (EOFError, KeyboardInterrupt):
        print("\nПроверка остановлена.")
        return 130
    finally:
        os.close(fd)
        os.waitpid(pid, 0)


if __name__ == "__main__":
    sys.exit(main())
