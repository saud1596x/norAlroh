# Linux recitation baseline

This is a separate evaluation tool, not a replacement for the iOS engine and
not a network service. It reads only ten public, hash-verified reciter clips.
Each clip is tested at original volume and 3% amplitude, alongside silence and
deterministic low-level noise. No expected Quran text is given to the decoder.

Use a fresh virtual environment in the isolated test directory:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r tools/LinuxRecitationBenchmark/requirements.txt
nice -n 10 timeout 900 .venv/bin/python tools/LinuxRecitationBenchmark/benchmark.py --output /tmp/noor-asr-evidence
```

The CPU model revision is pinned, uses one CPU thread, and is different from
the application's Core ML conversion. Compare ordinary/quiet word error rate,
false text on acoustic controls, and inference time before selecting a repair.
Results do not certify live microphone accuracy, word alignment, pronunciation,
Tajweed, or superiority to Tarteel. No production configuration is changed.
