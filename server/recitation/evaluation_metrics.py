"""Independent ASR measurements, never a learner-facing correctness grade.

Reference labels are supplied only after recognition. They cannot affect model
decoding. Preserve substitutions, deletions, insertions, repetitions and silent
controls rather than summarizing every failure as one compatibility score.
"""
from importlib.metadata import version
from jiwer import process_words, process_characters


def measure(reference, hypothesis):
    if (not isinstance(reference, list) or not isinstance(hypothesis, list)
            or any(not isinstance(token, str) or not token or any(c.isspace() for c in token)
                   for token in reference+hypothesis)):
        raise ValueError('Supply explicit normalized acoustic/reference token arrays')
    words = process_words(' '.join(reference), ' '.join(hypothesis))
    characters = process_characters(''.join(reference), ''.join(hypothesis))
    return {'tool': 'JiWER', 'version': version('jiwer'),
            'normalization': 'Caller-provided Arabic lexical tokens; not diacritic/Tajweed grading',
            'word_error_rate': words.wer, 'character_error_rate': characters.cer,
            'hits': words.hits, 'substitutions': words.substitutions,
            'deletions': words.deletions, 'insertions': words.insertions,
            'word_edits': words.substitutions+words.deletions+words.insertions,
            'character_edits': characters.substitutions+characters.deletions+characters.insertions,
            'silent_control_insertions': words.insertions if not reference else None}
