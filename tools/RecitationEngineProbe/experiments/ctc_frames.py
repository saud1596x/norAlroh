"""Raw greedy CTC occurrences; never accepts expected Quran text as input."""
import math


def observed_words(ids, posteriors, vocabulary, samples, stride=320, receptive=400, finalized=False):
    if len(ids) != len(posteriors) or samples < receptive or stride <= 0 or receptive <= 0:
        raise ValueError('Invalid CTC acoustic extent')
    if any(not math.isfinite(p) or not 0 <= p <= 1 for p in posteriors):
        raise ValueError('Invalid CTC acoustic posterior')
    if (len(ids) - 1) * stride + receptive > samples:
        raise ValueError('CTC frames exceed original audio')
    inverse = {value: key for key, value in vocabulary.items()}
    if len(inverse) != len(vocabulary) or inverse.get(0) != '<pad>':
        raise ValueError('Unsupported CTC vocabulary')
    occurrences = []
    previous = None
    for frame, (token, posterior) in enumerate(zip(ids, posteriors)):
        if token not in inverse:
            raise ValueError('Unknown CTC output index')
        if token != 0 and token != previous:
            occurrences.append(dict(label=inverse[token], first=frame, last=frame, posterior=posterior))
        elif token != 0:
            occurrences[-1]['last'] = frame
            occurrences[-1]['posterior'] = max(occurrences[-1]['posterior'], posterior)
        previous = token
    result = []
    word = []

    def flush(complete):
        if not word:
            return
        text = ''.join(unit['label'] for unit in word)
        result.append(dict(text=text, start=word[0]['first'] * stride / 16000,
            end=(word[-1]['last'] * stride + receptive) / 16000,
            posterior=sum(unit['posterior'] for unit in word) / len(word),
            complete=complete and all(not unit['label'].startswith('<') for unit in word)))
        word.clear()

    for unit in occurrences:
        if unit['label'] == '|':
            flush(True)
        else:
            word.append(unit)
    # An overlapping window ending is not an utterance ending. Only an actual
    # closed input with at least 300 ms after its last acoustic character may
    # finalize that observed token group. This adds no letters, missing words,
    # reference matches or correctness claims; partial live prefixes abstain.
    tail = (samples - (word[-1]['last'] * stride + receptive)) / 16000 if word else 0
    flush(finalized and tail >= 0.3)
    return result
