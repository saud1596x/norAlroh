"""Fingerprint build inputs, including binary resources and licensed fonts."""
import hashlib
from pathlib import Path

def ios_source_hashes(root: Path) -> dict[str, str]:
    paths = [root / 'ios/project.yml']
    for folder in ['Athar', 'AtharTests', 'AtharUITests']:
        paths.extend(p for p in (root / 'ios' / folder).rglob('*') if p.is_file())
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(paths)}
