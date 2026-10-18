"""Read-only edition binding. Display text is never normalized or rewritten."""
from dataclasses import dataclass
import gzip
import hashlib
import json
import unicodedata
from .initials import forms as spoken_initials


def normalize(text, expand=False):
    if expand: text = text.replace('\u0670', 'ا')
    text = unicodedata.normalize('NFKD', text.replace('ٱ', 'ا'))
    return ''.join(c for c in text if c.isalpha() and c not in 'ـۥۦ')


@dataclass(frozen=True)
class Word:
    native_id: int
    verse: str
    page: int
    position: int
    aliases: tuple


class Corpus:
    def __init__(self, root):
        raw = (root/'content-sources/recitation-word-script.json').read_bytes()
        script = json.loads(raw)
        if script['schema_version'] != 2 or script['source_sha256'] != '60b5341ecf04b6dbcdd2c42cc9b377003d9185ac6a76ad104a109ed669b0cf3c':
            raise ValueError('unsupported lexical source')
        # The exact complete script and snapshot are pinned independently by
        # the service manifest; a count alone is not integrity verification.
        pins = json.loads((root/'server/recitation/corpus-manifest.json').read_text())
        for name, digest in pins.items():
            if hashlib.sha256((root/name).read_bytes()).hexdigest() != digest:
                raise ValueError('corpus integrity mismatch')
        quran = json.loads((root/'ios/Athar/quran.json').read_bytes())
        keys = [f"{s['number']}:{a['number']}" for s in quran for a in s['ayahs']]
        if len(keys) != 6236 or len(set(keys)) != 6236: raise ValueError('invalid corpus')
        records = json.loads(gzip.decompress((root/'content-sources/mushaf-snapshot.json.gz').read_bytes()))['records']
        words = [r for r in records if r['record_type'] == 'mushaf_word' and r['char_type_name'] == 'word']
        if len(words) != 77429 or len({r['id'] for r in words}) != 77429: raise ValueError('invalid native edition')
        by_verse = {}
        for r in words: by_verse.setdefault(keys[r['verse_id']-1], []).append(r)
        if set(script['groups']) != set(keys) or set(by_verse) != set(keys): raise ValueError('invalid coverage')
        self.words = []
        self.by_id = {}
        self.starts = {}
        for key in keys:
            native, groups = sorted(by_verse[key], key=lambda r:r['position_in_verse']), script['groups'][key]
            if len(native) != len(groups): raise ValueError('invalid binding')
            for position, (r, group) in enumerate(zip(native, groups), 1):
                page, glyph, lexical, canonical = group
                if r['position_in_verse'] != position or r['page_number'] != page or r['text'] != glyph:
                    raise ValueError('invalid native correspondence')
                def tokens(parts, expand=False):
                    return tuple(v for t in parts for w in t.split() if (v := normalize(w, expand)))
                aliases = {tokens(lexical), tokens(canonical), tokens(canonical, True)}
                aliases.update(spoken_initials(key, position, tokens(canonical)))
                if not aliases or any(not a or not all(a) for a in aliases): raise ValueError('empty form')
                word = Word(r['id'], key, page, position, tuple(sorted(aliases)))
                self.by_id[word.native_id] = len(self.words)
                for alias in aliases: self.starts.setdefault(alias[0], set()).add(len(self.words))
                self.words.append(word)
        self.version = hashlib.sha256(raw).hexdigest()

    def align(self, heard, expected_cursor=None):
        """Conservative exact multiword anchors across the entire corpus.

        Only bindings shared by every equally long interpretation survive.
        No visible-page bias, fuzzy rewrite, inferred missing word or Tajweed.
        A repeated/shared phrase waits for further acoustic context.
        """
        tokens = [normalize(v['text']) for v in heard]
        candidates = []
        eligible = set()
        adjacent_verses = {self.words[i].verse for i in [expected_cursor-1, expected_cursor]
            if 0 <= i < len(self.words)} if expected_cursor is not None else set()
        for h, token in enumerate(tokens):
            for first in self.starts.get(token, ()):
                cursor, audio = first, h
                bound = []
                while cursor < len(self.words) and audio < len(tokens):
                    forms = [a for a in self.words[cursor].aliases if tuple(tokens[audio:audio+len(a)]) == a]
                    if len(forms) != 1: break
                    form = forms[0]; end = audio+len(form)
                    if any(heard[j]['start'] - heard[j-1]['end'] > 2 for j in range(audio+1, end)): break
                    if audio > h and heard[audio]['start']-heard[audio-1]['end'] > 2: break
                    bound.append((audio, end, cursor)); audio=end; cursor+=1
                near = expected_cursor is not None and max(0, expected_cursor-12) <= first <= expected_cursor+12 \
                    and self.words[first].verse in adjacent_verses
                minimum = 2 if near else 3
                # Outside-scope short matches still compete for ambiguity;
                # they never become eligible merely because they are unique.
                if len(bound) >= 2: candidates.append(tuple(bound))
                if len(bound) >= minimum: eligible.add(tuple(bound))
        # Match the native engine's non-overlapping optimal-anchor policy. A
        # cross-surah suffix bridge must not erase two stronger independent
        # passages. Keep only bindings shared by EVERY optimal interpretation.
        candidates = set(candidates)
        by_start = {}
        for candidate in candidates: by_start.setdefault(candidate[0][0], []).append(candidate)
        def weight(candidate): return (candidate[-1][1]-candidate[0][0])**2
        n = len(heard); prefix = [0]*(n+1); suffix = [0]*(n+1)
        for position in range(n):
            prefix[position+1] = max(prefix[position+1], prefix[position])
            for candidate in by_start.get(position, []):
                end = candidate[-1][1]
                prefix[end] = max(prefix[end], prefix[position]+weight(candidate))
        for position in range(n-1,-1,-1):
            suffix[position] = suffix[position+1]
            for candidate in by_start.get(position, []):
                suffix[position] = max(suffix[position], weight(candidate)+suffix[candidate[-1][1]])
        score = suffix[0]
        alternatives = [set() for _ in heard]
        unmatched = [prefix[p]+suffix[p+1] == score for p in range(n)]
        optimal = [c for c in candidates if prefix[c[0][0]]+weight(c)+suffix[c[-1][1]] == score]
        for candidate in optimal:
            for binding in candidate:
                for p in range(binding[0],binding[1]): alternatives[p].add(binding)
        certain = set()
        for candidate in optimal:
            if candidate not in eligible: continue
            if all(all(not unmatched[p] and alternatives[p] == {binding}
                       for p in range(binding[0],binding[1])) for binding in candidate):
                certain.update(candidate)
        result = []
        for start, end, index in sorted(certain):
            word = self.words[index]
            result.append({'native_id': word.native_id, 'verse': word.verse, 'page': word.page,
                           'position': word.position, 'start': heard[start]['start'], 'end': heard[end-1]['end'],
                           'confidence': min(w['confidence'] for w in heard[start:end])})
        return result
