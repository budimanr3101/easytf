"""Real PTY regression: tags, IAM role/key pair, multi-EBS and multi-rule SG."""
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time

binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else "target/release/easytf").resolve())

def run(width):
    with tempfile.TemporaryDirectory(prefix="easytf-collections-") as temp:
        root = Path(temp) / "project"
        env = dict(os.environ, TERM="xterm-256color", XDG_STATE_HOME=str(Path(temp) / "state"))
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24 if width == 80 else 40, width, 0, 0))
        process = subprocess.Popen([binary, "--demo", "--output", str(root)], stdin=slave, stdout=slave, stderr=slave, env=env)
        os.close(slave)
        transcript = bytearray()
        steps = []
        def pump():
            end = time.monotonic() + .20
            while time.monotonic() < end:
                if select.select([master], [], [], .02)[0]:
                    try: transcript.extend(os.read(master, 65536))
                    except OSError: break
        def press(value):
            before = len(transcript)
            os.write(master, value)
            pump()
            text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", transcript[before:].decode(errors="replace"))
            steps.append(repr(value) + " " + text[-900:])
            if os.environ.get("EASYTF_TEST_TRACE"):
                text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", transcript[before:].decode(errors="replace"))
                print(repr(value), text[-450:], flush=True)
        def down(count):
            for _ in range(count): press(b"\x1b[B")
        try:
            ready_deadline = time.monotonic() + 10
            while b"EASYTF" not in transcript and time.monotonic() < ready_deadline:
                pump()
            assert b"EASYTF" in transcript, "TUI did not finish entering raw mode"
            press(b"\r")  # EC2 form
            press(b"\x07")  # Ctrl+G optional sections
            press(b"\r")  # Access section
            down(2); press(b"\r"); press(b"ExistingApplicationRole"); press(b"\r")
            down(1); press(b"\r"); press(b"existing-team-key"); press(b"\r")
            press(b"\x13")  # Done access
            down(1); press(b"\r")  # Storage section
            press(b"\r")  # Additional EBS list
            for device in (b"/dev/sdf", b"/dev/sdg"):
                press(b"a"); press(b"\r"); press(device); press(b"\r"); press(b"\x13")
            press(b"\x13")  # Done EBS list
            press(b"\x13")  # Done storage
            press(b"\x13")  # Done optional sections
            press(b"\x1b[A"); press(b"\r")  # Tags (previous field)
            press(b"a"); press(b"Owner"); press(b"\r"); press(b"Platform"); press(b"\r")
            press(b"\x13")  # Done tags only, parent form remains
            press(b"\x0e")  # Save EC2 form
            press(b"s")  # Add SG
            for _ in range(3): press(b"\t")
            press(b"\x15"); press(b"subnet-0123456789abcdef0")
            press(b"\t"); press(b"\r")  # Ingress list
            press(b"a"); press(b"https"); press(b"\r"); press(b"\x13")
            press(b"a"); press(b"ssh_office"); press(b"\r")
            down(1); press(b"\r"); press(b"\x15"); press(b"22"); press(b"\r")
            down(1); press(b"\r"); press(b"\x15"); press(b"22"); press(b"\r")
            press(b"\x13"); press(b"\x13")  # Done rule and list
            press(b"\x0e")  # Save SG form
            press(b"r"); press(b"g"); press(b"\r"); press(b"q"); press(b"\r")
            deadline = time.monotonic() + 10
            while process.poll() is None and time.monotonic() < deadline:
                pump()
            assert process.poll() == 0, "TUI did not exit; see test-output/collection-failure.log"
            values = (root / "environments/dev/terraform.tfvars").read_text()
            for expected in ("ExistingApplicationRole", "existing-team-key", "/dev/sdf", "/dev/sdg", "Owner", "Platform", "https", "ssh_office"):
                assert expected in values, (expected, transcript[-3000:])
            check = subprocess.run([binary, "check", "--project", str(root)], capture_output=True, env=env)
            assert check.returncode == 0, check.stderr
            print(f"PASS: {width} columns, role/key pair, two EBS disks, tags, two SG rules, generate/reopen", flush=True)
        except Exception:
            Path("test-output").mkdir(exist_ok=True)
            Path("test-output/collection-failure.log").write_text("\n".join(steps))
            raise
        finally:
            if process.poll() is None:
                process.terminate(); process.wait(timeout=3)
            os.close(master)

for columns in ((int(os.environ["EASYTF_TEST_TRACE"]),) if os.environ.get("EASYTF_TEST_TRACE") else (80, 140)): run(columns)
