"""Bound a native test subprocess without changing its success/failure criteria."""
import os
import datetime
import json
import signal
import subprocess
import sys
import time


def validated_deadline(raw, *, build=False):
    seconds = float(raw)
    if not 0 < seconds <= (1200 if build else 720):
        raise ValueError("Explicit positive test deadline and command required")
    return seconds


def main():
    if len(sys.argv) < 3:
        raise ValueError("Explicit positive test deadline and command required")
    args = sys.argv[1:]
    if args[0] in ('--check', '--check-build'):
        validated_deadline(args[1], build=args[0] == '--check-build')
        print('NOOR_NATIVE_DEADLINE_VALID')
        return 0
    build = args[0] == '--build'
    if build:
        args = args[1:]
    seconds = validated_deadline(args[0], build=build)
    command = args[1:]
    # The longer cold-build budget cannot be used to extend a test timeout.
    # This lane only compiles the original Release test product; it runs none.
    if build and (len(command) < 2 or os.path.basename(command[0]) != 'xcodebuild'
                  or command[1] != 'build-for-testing'):
        raise ValueError('Build deadline requires xcodebuild build-for-testing')
    stage = 'BUILD' if build else 'TEST'
    started = time.monotonic()
    def report(event, **details):
        # No command arguments, audio or app data. Separate cold test-host
        # launch time from actual XCTest execution in the original CI log.
        print('NOOR_NATIVE_PROCESS ' + json.dumps(dict(
            stage=stage, event=event, utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
            elapsedSeconds=round(time.monotonic() - started, 3), deadlineSeconds=seconds,
            **details)), flush=True)
    report('start')
    process = subprocess.Popen(command, start_new_session=(os.name == "posix"))
    try:
        result = process.wait(timeout=seconds)
        report('end', exitCode=result)
        return result
    except subprocess.TimeoutExpired:
        print(f"NOOR_NATIVE_{stage}_DEADLINE seconds={seconds} exit=124; tests NOT passed", flush=True)
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
        report('end', exitCode=124)
        return 124


if __name__ == "__main__":
    sys.exit(main())
