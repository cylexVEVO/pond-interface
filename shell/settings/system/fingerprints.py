"""Run fprintd tools for the real calling user, never an environment identity."""
import os
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


if __name__ == '__main__':
    try:
        argv = command(sys.argv[1:])
        os.execvpe(argv[0], argv, dict(os.environ, LC_ALL='C'))
    except (OSError, ValueError) as error:
        print(f'Fingerprint operation unavailable: {error}', flush=True)
        sys.exit(1)
