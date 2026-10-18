"""Bound a native test subprocess without changing its success/failure criteria."""
import os
import signal
import subprocess
import sys


def validated_deadline(raw):
    seconds = float(raw)
    if not 0 < seconds <= 720:
        raise ValueError("Explicit positive test deadline and command required")
    return seconds


def main():
    if len(sys.argv) < 3:
        raise ValueError("Explicit positive test deadline and command required")
    if sys.argv[1] == '--check':
        validated_deadline(sys.argv[2])
        print('NOOR_NATIVE_DEADLINE_VALID')
        return 0
    seconds = validated_deadline(sys.argv[1])
    process = subprocess.Popen(sys.argv[2:], start_new_session=(os.name == "posix"))
    try:
        return process.wait(timeout=seconds)
    except subprocess.TimeoutExpired:
        print(f"NOOR_NATIVE_TEST_DEADLINE seconds={seconds} exit=124; tests NOT passed", flush=True)
        if os.name == "posix":
            os.killpg(process.pid, signal.SIGTERM)
        else:
            process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            if os.name == "posix":
                os.killpg(process.pid, signal.SIGKILL)
            else:
                process.kill()
            process.wait()
        return 124


if __name__ == "__main__":
    sys.exit(main())
