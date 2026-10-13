"""Run real PTY workflows with fixture AWS; never uses real AWS credentials."""
import fcntl
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time

binary = str(Path(sys.argv[1] if len(sys.argv) > 1 else "target/release/easytf").resolve())


def run(width, demo):
    with tempfile.TemporaryDirectory(prefix="easytf-tui-") as directory:
        directory = Path(directory)
        aws = directory / "aws"
        aws.write_text('''#!/bin/sh
case "$*" in
*describe-security-groups*) echo '{"SecurityGroups":[{"GroupId":"sg-11111111","GroupName":"application","VpcId":"vpc-11111111"}]}' ;;
*describe-subnets*) echo '{"Subnets":[{"SubnetId":"subnet-11111111","VpcId":"vpc-11111111","Tags":[{"Key":"Name","Value":"private"}]}]}' ;;
*) echo 'Unexpected AWS request' >&2; exit 1 ;;
esac
''')
        aws.chmod(0o755)
        env = dict(os.environ, TERM="xterm-256color", XDG_STATE_HOME=str(directory / "state"))
        env["PATH"] = f"{directory}:{env.get('PATH', '')}"
        root = directory / "project"
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24 if width == 80 else 40, width, 0, 0))
        args = [binary, "--output", str(root)] + (["--demo"] if demo else [])
        process = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave, env=env)
        os.close(slave)
        transcript = bytearray()

        def pump():
            end = time.monotonic() + 0.45
            while time.monotonic() < end:
                if select.select([master], [], [], 0.03)[0]:
                    try:
                        transcript.extend(os.read(master, 65536))
                    except OSError:
                        break

        def press(keys):
            os.write(master, keys)
            pump()

        try:
            pump()
            if demo:
                # Browse subnet and SG inside the real EC2 editor.
                press(b"\r")
                for _ in range(4):
                    press(b"\t")
                press(b"\x02")  # Ctrl+B
                press(b"private")
                press(b"\r")
                press(b"\t")
                press(b"\t")
                press(b"\x02")
                press(b"\x15")  # Ctrl+U clears old SG selection
                press(b"\r")
                press(b"\x0e")  # Ctrl+N saves form
            else:
                # Complete the wizard through visible actions, without F keys.
                for _ in range(4):
                    press(b"\r")
                for _ in range(4):
                    press(b"\x1b[B")
                press(b"\r")  # Continue to backend
                press(b"\t")
                press(b"\t")
                press(b"\r")  # Save & continue
            # Cycle narrow/wide previews, then review and publish.
            for _ in range(4 if width == 80 else 3):
                press(b"p")
            press(b"r")
            press(b"g")
            press(b"\r")
            press(b"q")
            press(b"\r")
            process.wait(timeout=3)
            assert process.returncode == 0
            assert (root / ".easytf.toml").is_file(), transcript[-2000:]
            if demo:
                tfvars = (root / "environments/dev/terraform.tfvars").read_text()
                assert "subnet-11111111" in tfvars
                assert "sg-11111111" in tfvars
                assert "sg-0123456789abcdef0" not in tfvars
            check = subprocess.run([binary, "check", "--project", str(root)], capture_output=True, env=env)
            assert check.returncode == 0, check.stderr
            print(f"PASS: {width} columns, {'AWS picker' if demo else 'wizard actions'}, review, generate, reopen/check")
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=3)
            os.close(master)


for columns in (80, 140):
    run(columns, False)
    run(columns, True)
