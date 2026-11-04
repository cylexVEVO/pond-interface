"""Run fprintd tools for the real calling user, never an environment identity."""
import os
import errno
import json
import pty
import re
import signal
import subprocess
import pwd
import sys

FINGERS = [f'{hand}-{finger}' for hand in ('left', 'right')
           for finger in ('thumb', 'index-finger', 'middle-finger', 'ring-finger', 'little-finger')]


def command(args):
    user = pwd.getpwuid(os.getuid()).pw_name
    if args == ['list'] or args == ['delete'] or args == ['verify']:
        return ['fprintd-' + args[0], user]
    if len(args) == 2 and args[0] == 'enroll' and args[1] in FINGERS:
        return ['fprintd-enroll', '-f', args[1], user]
    raise ValueError('Invalid fingerprint operation')


MESSAGES = {
    'enroll-stage-passed': ('accepted', 'Scan accepted. Lift your finger and touch again.'),
    'enroll-retry-scan': ('retry', 'Couldn’t read that scan. Try again.'),
    'enroll-swipe-too-short': ('retry', 'Swipe across the whole reader.'),
    'enroll-too-fast': ('retry', 'Hold your finger on the reader a little longer.'),
    'enroll-finger-not-centered': ('retry', 'Move your finger to the center of the reader.'),
    'enroll-remove-and-retry': ('retry', 'Lift your finger, then try again.'),
    'enroll-completed': ('complete', 'Fingerprint saved.'),
    'enroll-failed': ('failed', 'Enrollment failed. Try adding the finger again.'),
    'enroll-data-full': ('failed', 'Reader storage is full. Remove a saved fingerprint first.'),
    'enroll-duplicate': ('failed', 'This finger is already saved. Choose another finger.'),
    'enroll-disconnected': ('failed', 'Reader disconnected. Reconnect it and try again.'),
    'enroll-unknown-error': ('failed', 'The reader stopped responding. Try again.'),
}


def feedback(line):
    match = re.search(r'\b(enroll-[a-z-]+)\b', line)
    if not match:
        return {'kind': 'log', 'message': line}
    status = match.group(1)
    kind, message = MESSAGES.get(status, ('failed', 'The reader reported an unexpected result. Try again.'))
    return {'kind': kind, 'message': message, 'status': status}


def enroll(argv):
    # A terminal makes the CLI flush each scan immediately, even when Pond reads
    # from a pipe. Keep the child's lifetime tied to this process on cancellation.
    master, slave = pty.openpty()
    child = None
    previous = signal.getsignal(signal.SIGTERM)
    def cancel(signum, frame):
        raise SystemExit(128 + signum)
    try:
        signal.signal(signal.SIGTERM, cancel)
        child = subprocess.Popen(argv, stdout=slave, stderr=slave,
                                 env=dict(os.environ, LC_ALL='C'))
        os.close(slave)
        slave = None
        pending = b''
        while True:
            try:
                chunk = os.read(master, 4096)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                break
            if not chunk:
                break
            pending += chunk
            while b'\n' in pending:
                line, pending = pending.split(b'\n', 1)
                print(json.dumps(feedback(line.decode('utf-8', 'replace').strip())), flush=True)
        if pending:
            print(json.dumps(feedback(pending.decode('utf-8', 'replace').strip())), flush=True)
        return child.wait()
    finally:
        signal.signal(signal.SIGTERM, previous)
        if slave is not None:
            os.close(slave)
        os.close(master)
        if child and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()


if __name__ == '__main__':
    try:
        argv = command(sys.argv[1:])
        if sys.argv[1] == 'enroll':
            sys.exit(enroll(argv))
        os.execvpe(argv[0], argv, dict(os.environ, LC_ALL='C'))
    except (OSError, ValueError) as error:
        print(f'Fingerprint operation unavailable: {error}', flush=True)
        sys.exit(1)
