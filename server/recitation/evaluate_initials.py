"""Unprompted known-public initials on the actual eight-second ASR clock.

No forced alignment, expected-text prompts, generated PCM or learner grading.
The fixture manifest supplies identity only; recognition runs before comparison.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time

import numpy as np
from faster_whisper.audio import decode_audio
from noor_engine.corpus import Corpus, normalize
from noor_engine.inference import Recognizer
from noor_engine.initials import forms, OPENINGS


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--fixtures', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--verses', default='2:1,19:1,20:1,36:1')
    parser.add_argument('--max-minutes', type=int, default=3)
    args = parser.parse_args()
    if not 1 <= args.max_minutes <= 10:
        raise ValueError('Explicit local work deadline1..10minutes')
    root = Path(__file__).resolve().parents[2]
    corpus = Corpus(root)
    manifest = json.loads((args.fixtures/'sources.json').read_text(encoding='utf-8'))
    selected = set(args.verses.split(','))
    fixtures = [r for r in manifest['records'] if r['verse'] in selected]
    if len(fixtures) != len(selected) or any('sha256' not in r for r in fixtures):
        raise ValueError('Every selected source needs an actual complete hash receipt')
    model = Recognizer(args.model, cpu_threads=4)
    model.load()
    deadline = time.monotonic() + args.max_minutes*60
    result = {'scope':'KNOWN_PUBLIC_INITIALS_RAW_WINDOW_DIAGNOSTIC_NOT_LEARNER_ACCEPTANCE',
              'sourceRevision':corpus.version,'recognizerModel':model.model_id,'recognizerRevision':model.revision,
              'forcedAlignmentUsed':False,'productionApproved':False,'fixtures':[]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    def save():
        args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for fixture in fixtures:
        path = args.fixtures/fixture['file']
        if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != fixture['sha256']:
            raise ValueError('Public source bytes differ')
        pcm = decode_audio(str(path),sampling_rate=16000)
        record = {'source':fixture,'actualFrames':len(pcm),'windows':[],'complete':False}
        result['fixtures'].append(record)
        ends = list(range(32000,len(pcm),32000)) + [len(pcm)]
        for end in ends:
            if time.monotonic() >= deadline:
                result['stopReason']='LOCAL_TIME_LIMIT';save();return
            start = max(0,end-128000)
            samples = pcm[start:end]
            before = samples.copy()
            decoded = model._decode(samples)
            if not np.array_equal(samples,before):
                raise ValueError('Inference altered original public PCM')
            # Comparison is separate and never passed back into the recognizer.
            target = next(w for w in corpus.words if w.verse == fixture['verse'] and w.position == 1)
            initial_forms = forms(target.verse,1,(OPENINGS[target.verse],))
            runs = {}
            for word in decoded['words']:
                runs.setdefault(word.get('run_index',0),[]).append(word)
            heard_forms = [tuple(corpus_word['text'] for corpus_word in words) for words in runs.values()]
            found = any(any(tuple(normalize(x) for x in sequence[i:i+len(form)]) == form
                            for i in range(len(sequence)-len(form)+1))
                        for sequence in heard_forms for form in initial_forms)
            record['windows'].append({'startFrame':start,'endFrame':start+len(samples),
                'sourceEvidence':decoded,'completeSpokenAliasObserved':found,
                'independentGlobalAnchors':[a for words in runs.values() for a in corpus.align(words)]})
            save()
        record['complete']=True
        print(fixture['verse'],'windows',len(record['windows']),'completeAlias',any(w['completeSpokenAliasObserved'] for w in record['windows']),flush=True)
    result['stopReason']='REQUESTED_PASS_FINISHED';save()


if __name__ == '__main__':
    main()
