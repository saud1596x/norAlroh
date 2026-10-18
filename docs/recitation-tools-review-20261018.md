# Tools for the user's microphone engine

The user requested stronger tools for live learner recitation, not another
screen or professional-reciter timing alone. The recording stays original and
local unless the separate existing remote consent/verified endpoint permits
otherwise. No new third-party audio upload or subscription was enabled.

## Added and exercised

[JiWER](https://github.com/jitsi/jiwer)4.0.0 with RapidFuzz3.14.6 is now integrated
into the local real HTTP/WebSocket evaluation. Wheel SHA256 pins are in
`server/recitation/requirements-evaluation.txt` (CPython3.12/Windows). This is
offline measurement tooling, not a replacement recognizer or an app download.
It separately reports omissions, substitutions, insertions/repetitions and
false words on silence, alongside source-word identity and recovery checks.
Three arithmetic/input-boundary cases passed. Existing Arabic lexical
normalization is explicit; these metrics cannot measure diacritic/Tajweed
quality or adjudicate a learner. Known professional clips are not an unseen
learner benchmark. The corresponding actual-audio run must be reported from
its saved result, not inferred from these three policy cases.

Actual local GPU/loopback evaluation then completed22cases with identical
committed reconnect replay22/22 and no recognized words on silence/noise.
JiWER counted60hits/6substitutions/0deletions/0insertions across66reference
words; accepted-word WER0.0909/CER0.02326. These are lexical diagnostic counts,
not six proven learner mistakes. Warm median0.281s/p950.391s excludes network
distance and phone capture. It is the existing local RTX5060, not a cloud GPU
or an iPhone. Exact current engine hashes match the run receipt. None of these
numbers establishes accuracy on unseen natural learners.

The shipping offline inference path already uses the pinned
[WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) and WebRTC VAD; the
private CPU pilot uses faster-whisper and
[Silero VAD](https://github.com/snakers4/silero-vad). These were not newly added
by this research. The follow-up native run expands actual-PCM coverage to
quiet speech, very weak speech/noise and an edited omission diagnostic, while
retaining the source boundary, cancellation, take identity and clock checks.
Their status remains pending until the real native result.

## Evaluated from publisher information, not installed

[RNNoise](https://github.com/xiph/rnnoise) is BSD3 noise suppression, but its
48kHz processing requires measured resampling/delay and Quran speech-preservation
tests before use in the16kHz inference path. It is not enabled merely because
general speech sounds cleaner. Original recorded PCM must never be rewritten.

[FastConformer Quran CoreML streaming](https://huggingface.co/Muno459/fastconformer-quran-coreml-streaming)
and [Quran-Lab Zipformer v3](https://huggingface.co/Quran-Lab/zipformer_p-arabic-v3)
are relevant streaming candidates. Their current publisher pages require
gated access/contact sharing and no-profit license conditions. No agreement,
account access, contact disclosure or model-file access was performed.
Publisher benchmark numbers are not Noor measurements. Zipformer's publisher
also documents missed incorrect-ikhfaa behavior, so its output cannot be
silently promoted to verified Tajweed grading.

## Still required

Representative human-adjudicated learner audio (different devices, voices,
environments, real word mistakes), unbiased held-out quality measurements,
device latency/thermal behavior and false-correction rates remain unverified.
The cloud GPU trial is still blocked by quota; neither a new GPU resource nor
a public iPhone inference route exists. No claim of full-engine completion.

The publisher's [TLOG dataset card](https://huggingface.co/datasets/tarteel-ai/tlog)
explicitly says labels are inferred from file names and not further validated.
It also gates access/contact sharing. It was not downloaded, and its canonical
labels must not silently become ground truth for real learner mistakes.
