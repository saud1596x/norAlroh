#!/usr/bin/env python3
"""Sample only this CI simulator's Athar process; never synthesize audio/results."""
import json
import subprocess
import sys
import time
from pathlib import Path

device, output = sys.argv[1:]
out = Path(output)
out.mkdir(parents=True, exist_ok=True)
deadline = time.monotonic() + 120
while time.monotonic() < deadline:
    processes = subprocess.run(["pgrep", "-x", "Athar"], capture_output=True, text=True)
    for pid in processes.stdout.split():
        command = subprocess.run(["ps", "-p", pid, "-o", "command="], capture_output=True, text=True).stdout.strip()
        if f"/Devices/{device}/" not in command or "/Athar.app/Athar" not in command:
            continue
        # Two bounded snapshots distinguish a persistent wait from normal launch.
        for number in range(2):
            time.sleep(12)
            current = subprocess.run(["ps", "-p", pid, "-o", "command="], capture_output=True, text=True).stdout.strip()
            if current != command:
                break
            target = out / f"athar-hang-{number}.txt"
            result = subprocess.run(["/usr/bin/sample", pid, "2", "-file", str(target)],
                                    capture_output=True, text=True, timeout=15)
            print("AUDIO_STACK_SAMPLE", json.dumps({"file": target.name, "exit": result.returncode}), flush=True)
        sys.exit(0)
    time.sleep(0.5)
print("AUDIO_STACK_SAMPLE no matching simulator app process appeared", flush=True)
