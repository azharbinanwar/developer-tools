"""Use the original make-a-build Bash menus and prompts, without duplicating them."""
import re
import os
import sys
import threading
from contextlib import contextmanager
import subprocess
from pathlib import Path

LAUNCHER = Path(__file__).resolve().parent.parent / 'deploy-it'


def clean(value):
    return re.sub(r'[\x00-\x1f\x7f-\x9f]', '', str(value))


def heading(text):
    print('\n  ▸ ' + clean(text))


def row(label, value):
    print('     {:12} {}'.format(label, clean(value)))


def ask(label, default=''):
    result = subprocess.run(['bash', str(LAUNCHER), '--prompt-bridge', clean(label), clean(default)], stdout=subprocess.PIPE, text=True)
    if result.returncode: raise KeyboardInterrupt
    return result.stdout.strip()


def confirm(label, default=False):
    return ask(label + ' (y/n)', 'yes' if default else 'no').lower() in ('y', 'yes')


def choose(title, items, default=0):
    if not items: raise ValueError('No choices available.')
    result = subprocess.run(['bash', str(LAUNCHER), '--menu-bridge', clean(title)] + [clean(item) for item in items], stdout=subprocess.PIPE, text=True, env=dict(os.environ, DEPLOY_IT_MENU_DEFAULT=str(default)))
    if result.returncode: raise KeyboardInterrupt
    try: index = int(result.stdout.strip())
    except ValueError: raise KeyboardInterrupt
    return None if index == len(items) else index

@contextmanager
def loading(label):
    stop = threading.Event()
    def animate():
        frames = '|/-\\'
        i = 0
        while not stop.is_set():
            print('\r    ' + frames[i % len(frames)] + ' ' + label, end='', file=sys.stderr, flush=True)
            i += 1
            stop.wait(0.15)
    thread = None
    if sys.stderr.isatty():
        thread = threading.Thread(target=animate, daemon=True)
        thread.start()
    else:
        print('    ' + label + '…', file=sys.stderr, flush=True)
    try:
        yield
    finally:
        stop.set()
        if thread:
            thread.join()
            print('\r\033[K', end='', file=sys.stderr, flush=True)
