#!/usr/bin/env python3
"""
Ensure ~/.ssh/config's `mp157` host points to the board's current IP.

Flow:
  1. Try ssh mp157 — if it works, exit (nothing to do).
  2. Otherwise connect via USB serial, log in if needed, query wlan0 IP.
  3. Rewrite the HostName line under `Host mp157` in ~/.ssh/config.

Usage:  python3 scripts/refresh-mp157-ip.py
"""
import os, re, sys, time, termios, select, subprocess, shutil
from pathlib import Path

HOST_ALIAS  = "mp157"
SERIAL_PORT = "/dev/cu.usbserial-2130"
BAUD        = termios.B115200
SSH_CONFIG  = Path.home() / ".ssh" / "config"
SSH_TIMEOUT = 4   # seconds for the liveness probe
SERIAL_LOGIN_USER = "root"  # set to None to skip auto-login


def ssh_works() -> bool:
    """Return True if the board accepts TCP on :22 at the configured HostName."""
    ip = current_config_ip()
    if not ip:
        return False
    # Cheap TCP probe — avoids ssh auth/key complications.
    r = subprocess.run(
        ["nc", "-z", "-G", str(SSH_TIMEOUT), ip, "22"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    return r.returncode == 0


def current_config_ip() -> str | None:
    """Read HostName from the `Host mp157` block in ~/.ssh/config."""
    if not SSH_CONFIG.exists():
        return None
    m = HOST_RE.search(SSH_CONFIG.read_text())
    if not m:
        return None
    hn = re.search(r"(?m)^\s*HostName\s+(\S+)\s*$", m.group("body"))
    return hn.group(1) if hn else None


# ---------- serial helpers ----------
def open_serial(port: str) -> int:
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    attrs = termios.tcgetattr(fd)
    attrs[0] = 0                                  # iflag
    attrs[1] = 0                                  # oflag
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[3] = 0                                  # lflag (raw)
    attrs[4] = BAUD
    attrs[5] = BAUD
    attrs[6][termios.VMIN]  = 0
    attrs[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    termios.tcflush(fd, termios.TCIOFLUSH)
    return fd


def read_for(fd: int, seconds: float, echo: bool = False,
             until: bytes | None = None) -> bytes:
    """Read for `seconds`, or return early once `until` appears in the buffer."""
    buf, end = b"", time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.2)
        if r:
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                continue
            if chunk:
                buf += chunk
                if echo:
                    sys.stderr.write(chunk.decode("utf-8", "replace"))
                    sys.stderr.flush()
        if until and until in buf:
            return buf
    return buf


def send(fd: int, line: str) -> None:
    # `\r` is what the Enter key produces on a TTY; the line discipline maps
    # it to `\n` internally. Sending raw `\n` doesn't reliably submit input.
    os.write(fd, (line + "\r").encode())


def marker_line(marker: str) -> bytes:
    """Match a marker printed as its own line, not inside an echoed command."""
    return b"\r\n" + marker.encode() + b"\r\n"


def drain_until_quiet(fd: int, quiet_secs: float = 0.5,
                      max_total: float = 4.0) -> None:
    """Read & discard until the line has been silent for `quiet_secs`."""
    end_total = time.time() + max_total
    last_data = time.time()
    while time.time() < end_total:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try:
                if os.read(fd, 4096):
                    last_data = time.time()
            except OSError:
                pass
        elif time.time() - last_data >= quiet_secs:
            return


def query_ip_via_serial() -> str | None:
    if not os.path.exists(SERIAL_PORT):
        sys.exit(f"serial port {SERIAL_PORT} not present — board unplugged?")
    fd = open_serial(SERIAL_PORT)
    try:
        # 1) Abort any in-flight command, then drain *everything* stale —
        #    macOS USB-serial drivers retain unread data across opens.
        os.write(fd, b"\x03\r\n")      # Ctrl-C + newline
        drain_until_quiet(fd, quiet_secs=0.6, max_total=5.0)

        # 2) Synchronise on a unique marker — only proceed once we see it
        #    echoed back, so we know the shell is at a prompt and listening.
        ready = "__READY_%d__" % os.getpid()
        send(fd, f"echo {ready}")
        sync = read_for(fd, 3.0, until=marker_line(ready))

        # Handle login: prompt (rare — usually already root).
        if SERIAL_LOGIN_USER and b"login:" in sync.lower():
            send(fd, SERIAL_LOGIN_USER)
            drain_until_quiet(fd, quiet_secs=0.6, max_total=3.0)
            send(fd, f"echo {ready}")
            read_for(fd, 3.0, until=marker_line(ready))

        # 3) Real query, terminated by another sentinel.
        done = "__IP_DONE_%d__" % os.getpid()
        send(fd, f"/sbin/ip -4 addr show wlan0; echo {done}")
        out = read_for(fd, 6.0, echo=True, until=marker_line(done))
    finally:
        os.close(fd)

    m = re.search(rb"inet (\d+\.\d+\.\d+\.\d+)", out)
    if not m:
        sys.stderr.write("\n--- raw serial buffer ---\n")
        sys.stderr.write(repr(out) + "\n")
        sys.stderr.write("--- end raw ---\n")
    return m.group(1).decode() if m else None


# ---------- ssh config rewrite ----------
HOST_RE = re.compile(
    rf"^(?P<head>[ \t]*Host\s+{re.escape(HOST_ALIAS)}\s*$)"
    rf"(?P<body>(?:\n(?![ \t]*Host\s).*)*)",
    re.MULTILINE,
)


def update_ssh_config(new_ip: str) -> bool:
    """Rewrite the HostName line under `Host mp157`. Returns True if changed."""
    if not SSH_CONFIG.exists():
        sys.exit(f"{SSH_CONFIG} not found")
    text = SSH_CONFIG.read_text()
    m = HOST_RE.search(text)
    if not m:
        sys.exit(f"no `Host {HOST_ALIAS}` block in {SSH_CONFIG}")

    body = m.group("body")
    hn = re.search(r"(?m)^(\s*)HostName\s+\S+\s*$", body)
    if hn:
        old = hn.group(0)
        if hn.group(0).split()[-1] == new_ip:
            return False
        new_body = body.replace(old, f"{hn.group(1)}HostName {new_ip}", 1)
    else:
        new_body = "\n    HostName " + new_ip + body

    new_text = text[:m.start("body")] + new_body + text[m.end("body"):]
    backup = SSH_CONFIG.with_suffix(SSH_CONFIG.suffix + ".bak")
    shutil.copy2(SSH_CONFIG, backup)
    SSH_CONFIG.write_text(new_text)
    return True


def main() -> int:
    print(f"probing ssh {HOST_ALIAS} ...", flush=True)
    if ssh_works():
        print(f"ssh {HOST_ALIAS} OK — no change needed.")
        return 0

    print(f"ssh {HOST_ALIAS} failed; querying board over {SERIAL_PORT} ...",
          flush=True)
    ip = query_ip_via_serial()
    if not ip:
        sys.exit("could not parse wlan0 IPv4 address from serial output")
    print(f"\nboard reports IP: {ip}")

    changed = update_ssh_config(ip)
    if changed:
        print(f"updated {SSH_CONFIG}: HostName -> {ip} (backup at .bak)")
        # Any old host key for this IP belongs to a different machine — drop it.
        subprocess.run(["ssh-keygen", "-R", ip],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # Pre-seed the new host key so the first real ssh doesn't prompt.
        subprocess.run(f"ssh-keyscan -T 5 -H {ip} >> ~/.ssh/known_hosts 2>/dev/null",
                       shell=True)
    else:
        print(f"{SSH_CONFIG} already had {ip}; ssh was just refusing — try again.")

    # final verification
    print("re-probing ssh ...", flush=True)
    ok = ssh_works()
    print("OK" if ok else "still failing — check the board manually.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
