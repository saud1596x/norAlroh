"""Bound a native test subprocess without changing its success/failure criteria."""
import os
import datetime
import json
import queue
import signal
import subprocess
import sys
import threading
import time

TERMINATION_GRACE_SECONDS = 5
REAP_SECONDS = 2
OUTPUT_DRAIN_SECONDS = 1
CHUNK_BYTES = 32 * 1024
_EOF = object()


class OutputRelay:
    """The child owns only an internal pipe, never the outer CI logger pipe.

    A daemon reads bounded chunks into a bounded queue. Only the calling thread
    writes stdout. A descendant retaining the internal pipe cannot make the
    wrapper wait forever for EOF or retain the outer collector's writer.
    """
    def __init__(self, stream):
        self.pending = queue.Queue(maxsize=8)
        self.eof = False
        self.last_newline = True
        # The reader uses a raw duplicate, so closing the Popen file object
        # cannot wait for a BufferedReader lock held by another thread.
        read_fd = os.dup(stream.fileno())
        stream.close()

        def read():
            try:
                while True:
                    chunk = os.read(read_fd, CHUNK_BYTES)
                    if not chunk:
                        break
                    self.pending.put(chunk)
            except OSError as error:
                self.pending.put(error)
            finally:
                try:
                    os.close(read_fd)
                except OSError:
                    pass
                self.pending.put(_EOF)
        self.reader = threading.Thread(target=read, name='native-output-relay', daemon=True)
        self.reader.start()

    def forward(self, timeout):
        if self.eof:
            return
        try:
            item = self.pending.get(timeout=max(0, timeout))
        except queue.Empty:
            return
        if item is _EOF:
            self.eof = True
        elif isinstance(item, OSError):
            raise item
        else:
            target = getattr(sys.stdout, 'buffer', None)
            if target is not None:
                target.write(item)
                target.flush()
            else:
                sys.stdout.write(item.decode('utf-8', errors='replace'))
                sys.stdout.flush()
            self.last_newline = item.endswith(b'\n')

    def separate_record(self):
        if not self.last_newline:
            print(flush=True)
            self.last_newline = True

    def drain_until(self, deadline):
        while not self.eof and time.monotonic() < deadline:
            self.forward(min(0.05, max(0, deadline - time.monotonic())))


def signal_process_group(process, *, force):
    """A group may disappear between poll, TERM, and KILL. That is harmless."""
    try:
        if os.name == 'posix':
            os.killpg(process.pid, signal.SIGKILL if force else signal.SIGTERM)
        elif process.poll() is None:
            process.kill() if force else process.terminate()
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        # Darwin may deny a signal to the old group after its direct root has
        # exited and an escaped child owns a different session. Do not retry
        # with broader privileges, claim a kill, or mask the original timeout.
        print('NOOR_NATIVE_GROUP_SIGNAL_DENIED signal=' + ('KILL' if force else 'TERM'),
              file=sys.stderr, flush=True)
        return False


def process_group_exists(process):
    if os.name != 'posix':
        return process.poll() is None
    try:
        os.killpg(process.pid, 0)
        return True
    except ProcessLookupError:
        return False


def stop_process_group(process, relay):
    signal_process_group(process, force=False)
    grace_deadline = time.monotonic() + TERMINATION_GRACE_SECONDS
    # The direct root can exit on TERM while a descendant ignores it and
    # retains stdout. The grace condition concerns the group, not root.wait().
    while time.monotonic() < grace_deadline:
        process.poll()  # Reap a completed direct child before checking its group.
        try:
            group_exists = process_group_exists(process)
        except PermissionError:
            # EPERM is not evidence that the group is absent or terminated.
            # We cannot observe it safely; still attempt the bounded final KILL
            # and reap, and retain exit 124 plus the explicit diagnostic.
            print('NOOR_NATIVE_GROUP_PROBE_DENIED; group termination NOT verified',
                  file=sys.stderr, flush=True)
            break
        if not group_exists:
            break
        relay.forward(min(0.05, max(0, grace_deadline - time.monotonic())))
        if relay.eof:
            time.sleep(min(0.01, max(0, grace_deadline - time.monotonic())))
    # Always attempt escalation independently of the root's return code.
    signal_process_group(process, force=True)
    reaped = True
    try:
        process.wait(timeout=REAP_SECONDS)
    except subprocess.TimeoutExpired:
        reaped = False
    relay.drain_until(time.monotonic() + OUTPUT_DRAIN_SECONDS)
    return reaped


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
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               start_new_session=(os.name == "posix"))
    try:
        relay = OutputRelay(process.stdout)
        deadline = started + seconds
        while time.monotonic() < deadline:
            result = process.poll()
            if result is not None and relay.eof:
                relay.separate_record()
                report('end', exitCode=result)
                return result
            relay.forward(min(0.05, max(0, deadline - time.monotonic())))
            if relay.eof and result is None:
                time.sleep(min(0.01, max(0, deadline - time.monotonic())))
        relay.separate_record()
        print(f"NOOR_NATIVE_{stage}_DEADLINE seconds={seconds} exit=124; tests NOT passed", flush=True)
        reaped = stop_process_group(process, relay)
        relay.separate_record()
        report('end', exitCode=124, rootReaped=reaped, outputEOF=relay.eof)
        return 124
    except BaseException:
        # A broken logger, Ctrl-C, or other wrapper failure must not strand an
        # isolated native command. Never replace the original error by success.
        signal_process_group(process, force=True)
        try:
            process.wait(timeout=REAP_SECONDS)
        except subprocess.TimeoutExpired:
            pass
        raise


if __name__ == "__main__":
    sys.exit(main())
