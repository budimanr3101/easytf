"""Create linked ALB/NLB via the real TUI without calling AWS."""
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

def run(columns):
    with tempfile.TemporaryDirectory(prefix="easytf-lb-") as temp:
        root=Path(temp)/"project"
        master,slave=pty.openpty()
        fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack("HHHH",24 if columns==80 else 40,columns,0,0))
        env=dict(os.environ,TERM="xterm-256color",XDG_STATE_HOME=str(Path(temp)/"state"))
        process=subprocess.Popen([binary,"--demo","--output",str(root)],stdin=slave,stdout=slave,stderr=slave,env=env)
        os.close(slave)
        transcript=bytearray()
        def pump():
            until=time.monotonic()+.20
            while time.monotonic()<until:
                if select.select([master],[],[],.02)[0]:
                    try:transcript.extend(os.read(master,65536))
                    except OSError:break
        def press(keys):os.write(master,keys);pump()
        try:
            deadline=time.monotonic()+10
            while b"EASYTF" not in transcript and time.monotonic()<deadline:pump()
            assert b"EASYTF" in transcript
            for network in (False,True):
                press(b"b" if network else b"l")
                for _ in range(3):press(b"\t")
                press(b"\x15")
                press(b"subnet-0123456789abcdef0" if network else b"subnet-0123456789abcdef0, subnet-11111111111111111")
                if network:
                    for _ in range(4):press(b"\t")
                else:
                    press(b"\t");press(b"\t")
                    press(b"sg-0123456789abcdef0")
                    press(b"\t");press(b"\t")
                press(b"\r") # Target group list
                press(b"\r") # Default web target group
                for _ in range(3):press(b"\x1b[B")
                press(b"\r") # Project EC2 key list
                press(b"a");press(b"\r") # Choose web_primary without typing an ID
                press(b"\x13");press(b"\x13");press(b"\x13") # Done list/group/collection
                press(b"\x0e") # Save load balancer form
            press(b"r");press(b"g");press(b"\r")
            deadline=time.monotonic()+10
            while (not (root/".easytf.toml").exists() or (root/".easytf.lock").exists()) and time.monotonic()<deadline:pump()
            pump();press(b"q");press(b"\r")
            deadline=time.monotonic()+10
            while process.poll() is None and time.monotonic()<deadline:pump()
            assert process.poll()==0,transcript[-2000:]
            text=(root/"environments/dev/terraform.tfvars").read_text()
            assert '"load_balancers"' not in text or '"alb"' in text
            assert '"alb"' in text and '"nlb"' in text
            assert text.count('"web_primary"')>=3
            checked=subprocess.run([binary,"check","--project",str(root)],capture_output=True,env=env)
            assert checked.returncode==0,checked.stderr
            print(f"PASS: {columns} columns, ALB/NLB target selection, generate and reopen",flush=True)
        finally:
            if process.poll() is None:process.terminate();process.wait(timeout=3)
            os.close(master)

for width in (80,140):run(width)
