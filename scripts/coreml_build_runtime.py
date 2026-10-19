"""Reproduce the tested converter interpreter/dependencies, never new model pins."""
from pathlib import Path
import shutil
import subprocess
import sys


def prepare(root, destination):
    root, destination = Path(root), Path(destination)
    interpreter = sys.executable if sys.version_info[:2] == (3, 11) else shutil.which('python3.11')
    if not interpreter:
        raise ValueError('Tested CoreML converter requires Python3.11; install python@3.11 before native generation')
    version = subprocess.check_output([interpreter, '-c', 'import sys; print("%s.%s" % sys.version_info[:2])'], text=True).strip()
    if version != '3.11':
        raise ValueError('CoreML converter interpreter differs from tested Python3.11')
    subprocess.run([interpreter, '-m', 'venv', str(destination)], check=True)
    runtime = destination / 'bin/python'
    subprocess.run([str(runtime), '-m', 'pip', 'install', '--disable-pip-version-check',
                    '-r', str(root / 'scripts/coreml-build-constraints.txt')], check=True)
    # Package names/versions only; never dump environment variables or secrets.
    environment = subprocess.check_output([str(runtime), '-m', 'pip', 'freeze', '--all'], text=True)
    (root / 'release').mkdir(exist_ok=True)
    (root / 'release/independent-coreml-build-environment.txt').write_text(
        'interpreter=' + version + '\n' + environment, encoding='utf-8')
    return runtime
