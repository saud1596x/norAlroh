"""Run the real Swift lexical paths on the exact bundled edition, no audio/model.

The full native/ASR gates remain necessary. Never turn this injected-observation
CPU measurement into a learner quality score or a measured iPhone speedup.
"""
import ast
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def native_input(root=ROOT):
    snapshot = json.loads(gzip.decompress((root / 'content-sources/mushaf-snapshot.json.gz').read_bytes()))
    script = json.loads((root / 'content-sources/recitation-word-script.json').read_text(encoding='utf-8'))
    keys = sorted(script['groups'], key=lambda key: tuple(map(int, key.split(':'))))
    words = [{'id': row['id'], 'verse': keys[row['verse_id'] - 1],
              'position': row['position_in_verse'], 'page': row['page_number'], 'glyph': row['text']}
             for row in snapshot['records']
             if row['record_type'] == 'mushaf_word' and row.get('char_type_name') == 'word']
    if len(keys) != 6236 or len(words) != 77429 or len({word['id'] for word in words}) != 77429:
        raise ValueError('Unexpected installed edition; never benchmark a substituted corpus')
    return {'keys': keys, 'words': words}


def main():
    definition = ast.parse((ROOT / 'scripts/test-wording-behavior.py').read_text(encoding='utf-8'))
    sources = next(ast.literal_eval(node.value) for node in definition.body
                   if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'SOURCES' for t in node.targets))
    harness = 'tools/RecitationEngineProbe/experiments/WordingReferenceBenchmark.swift'
    evidence = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                for name in sources + [harness, 'content-sources/mushaf-snapshot.json.gz',
                                       'content-sources/recitation-word-script.json']}
    print(json.dumps({'productionSourceSHA256': evidence, 'acousticValidation': False}), flush=True)
    with tempfile.TemporaryDirectory(prefix='noor-wording-bench-') as directory:
        workspace = Path(directory)
        source = workspace / 'native.json'
        source.write_text(json.dumps(native_input(), ensure_ascii=False), encoding='utf-8')
        program = workspace / 'wording-benchmark'
        subprocess.run(['swiftc', '-O', '-swift-version', '5', '-o', str(program)] +
                       [str(ROOT / name) for name in sources + [harness]], check=True, timeout=120)
        subprocess.run([str(program), str(source), str(ROOT / 'content-sources/recitation-word-script.json')],
                       check=True, timeout=120)


if __name__ == '__main__':
    main()
