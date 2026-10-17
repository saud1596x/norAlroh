"""Bounded actual CPU inference. No prompts containing the expected scripture."""
import asyncio
import hashlib
import json
import math
import time
from pathlib import Path
import numpy as np


class Busy(Exception): pass
class InferenceDeadline(Exception): pass


class Recognizer:
    def __init__(self, model_path, timeout=20, cpu_threads=2):
        self.path, self.timeout, self.cpu_threads = model_path, timeout, cpu_threads
        self.model = None
        self.pending = None
        self.gate = asyncio.Lock()
        self.model_id = 'OdyAsh/faster-whisper-base-ar-quran'
        self.revision = '8578bafd427d122f671b187706650e76edf6f86f'
        self.completed = self.timeouts = 0
        self.total_seconds = 0.0

    def load(self):
        manifest = json.loads((Path(__file__).resolve().parents[1]/'model-manifest.json').read_text())
        for name, digest in manifest['files'].items():
            file = self.path/name
            if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest() != digest:
                raise ValueError('pinned inference asset unavailable')
        from faster_whisper import WhisperModel
        self.model = WhisperModel(str(self.path), device='cpu', compute_type='int8',
                                  cpu_threads=self.cpu_threads, num_workers=1, local_files_only=True)

    async def recognize(self, samples):
        if self.model is None: raise RuntimeError('model unavailable')
        # SDK cancellation cannot release actual compute ownership prematurely.
        # One outstanding worker, no unbounded executor queue on timeout.
        if self.gate.locked() or self.pending is not None: raise Busy()
        await self.gate.acquire()
        task = asyncio.create_task(asyncio.to_thread(self._decode, samples.copy()))
        self.pending = task
        def finished(done):
            try: done.exception()
            except (asyncio.CancelledError, Exception): pass
            self.pending = None; self.gate.release()
        task.add_done_callback(finished)
        try:
            return await asyncio.wait_for(asyncio.shield(task), self.timeout)
        except asyncio.TimeoutError:
            self.timeouts += 1; raise InferenceDeadline() from None

    def _decode(self, original):
        start = time.monotonic()
        peak = float(np.max(np.abs(original)))
        rms = float(np.sqrt(np.mean(original.astype(np.float64)**2)))
        configuration = f'faster-whisper1.2.1/int8/cpu-threads{self.cpu_threads}/beam1/silero-v6/no-prompt/audio-gate1'
        if peak == 0 or rms < 0.00001:
            return {'words': [], 'unresolved': False, 'inference_ms': 0, 'processing_configuration':configuration}
        gain = max(1, min(256, 0.06/max(rms, 0.000001), 0.9/peak))
        samples = original * gain
        segments, _ = self.model.transcribe(samples, language='ar', beam_size=1, temperature=0,
            condition_on_previous_text=False, word_timestamps=True, vad_filter=True,
            vad_parameters={'min_speech_duration_ms': 100, 'min_silence_duration_ms': 300})
        words, unresolved = [], False
        duration = len(samples)/16000
        for segment in segments:
            if not math.isfinite(segment.no_speech_prob) or not 0 <= segment.no_speech_prob < .6:
                unresolved = True; continue
            for word in segment.words or []:
                timing = all(math.isfinite(v) for v in [word.start, word.end, word.probability])
                valid = timing and 0 <= word.start < word.end <= duration and .75 <= word.probability <= 1
                if valid:
                    local = samples[int(word.start*16000):int(word.end*16000)]
                    valid = bool(len(local)) and float(np.sqrt(np.mean(local.astype(np.float64)**2))) >= .02
                if not valid or len(word.word.split()) != 1:
                    unresolved = True; continue
                words.append({'text': word.word.strip(), 'start': word.start, 'end': word.end,
                              'confidence': word.probability})
        elapsed = time.monotonic()-start
        self.completed += 1; self.total_seconds += elapsed
        return {'words': words, 'unresolved': unresolved, 'inference_ms': round(elapsed*1000, 3),
                'processing_configuration':configuration}
