"""Bounded actual inference. No prompts containing the expected scripture."""
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
    def __init__(self, model_path, timeout=20, cpu_threads=2, device='cpu'):
        if device not in {'cpu', 'cuda'}: raise ValueError('unsupported inference device')
        self.path, self.timeout, self.cpu_threads = model_path, timeout, cpu_threads
        self.device = device
        self.compute_type = 'float16' if device == 'cuda' else 'int8'
        self.model = None
        self.pending = None
        self.pending_since = None
        self.overdue = False
        self.gate = asyncio.Lock()
        self.model_id = 'OdyAsh/faster-whisper-base-ar-quran'
        self.revision = '8578bafd427d122f671b187706650e76edf6f86f'
        self.completed = self.timeouts = 0
        self.total_seconds = 0.0

    @property
    def healthy(self):
        return self.model is not None and not self.overdue and (self.pending_since is None
            or time.monotonic()-self.pending_since <= self.timeout)

    def load(self):
        manifest = json.loads((Path(__file__).resolve().parents[1]/'model-manifest.json').read_text())
        for name, digest in manifest['files'].items():
            file = self.path/name
            if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest() != digest:
                raise ValueError('pinned inference asset unavailable')
        from faster_whisper import WhisperModel
        self.model = WhisperModel(str(self.path), device=self.device, compute_type=self.compute_type,
                                  cpu_threads=self.cpu_threads, num_workers=1, local_files_only=True)
        if self.device == 'cuda':
            # Compile/initialize kernels before readiness, not on a learner's
            # first window. Discard this artificial silent warmup completely;
            # it is not an acoustic test or recitation/progress evidence.
            warmup, _ = self.model.transcribe(np.zeros(16000,dtype=np.float32), language='ar',
                beam_size=1, temperature=0, condition_on_previous_text=False, vad_filter=False)
            for _ in warmup: pass

    async def recognize(self, samples):
        if self.model is None: raise RuntimeError('model unavailable')
        # SDK cancellation cannot release actual compute ownership prematurely.
        # One outstanding worker, no unbounded executor queue on timeout.
        if self.gate.locked() or self.pending is not None: raise Busy()
        await self.gate.acquire()
        task = asyncio.create_task(asyncio.to_thread(self._decode, samples.copy()))
        self.pending = task; self.pending_since = time.monotonic(); self.overdue = False
        def finished(done):
            try: done.exception()
            except (asyncio.CancelledError, Exception): pass
            self.pending = None; self.pending_since = None; self.overdue = False; self.gate.release()
        task.add_done_callback(finished)
        try:
            return await asyncio.wait_for(asyncio.shield(task), self.timeout)
        except asyncio.TimeoutError:
            # Record the actual deadline event; do not infer it solely from a
            # platform monotonic clock with coarser resolution than the timer.
            if self.pending is task: self.overdue = True
            self.timeouts += 1; raise InferenceDeadline() from None

    def _decode(self, original):
        start = time.monotonic()
        peak = float(np.max(np.abs(original)))
        rms = float(np.sqrt(np.mean(original.astype(np.float64)**2)))
        hardware = f'cpu-threads{self.cpu_threads}' if self.device == 'cpu' else 'cuda'
        configuration = f'faster-whisper1.2.1/{self.compute_type}/{hardware}/beam1/silero-v6/no-prompt/audio-gate1/run-evidence2/untimed-segment1'
        if peak == 0 or rms < 0.00001:
            return {'words': [], 'observations': [], 'unresolved': False, 'inference_ms': 0, 'processing_configuration':configuration}
        gain = max(1, min(256, 0.06/max(rms, 0.000001), 0.9/peak))
        samples = original * gain
        segments, _ = self.model.transcribe(samples, language='ar', beam_size=1, temperature=0,
            condition_on_previous_text=False, word_timestamps=True, vad_filter=True,
            vad_parameters={'min_speech_duration_ms': 100, 'min_silence_duration_ms': 300})
        words, observations, unresolved = [], [], False
        run_index, previous_end = 0, 0.0
        duration = len(samples)/16000
        for segment in segments:
            speech = math.isfinite(segment.no_speech_prob) and 0 <= segment.no_speech_prob < .6
            if not speech: unresolved = True
            if not segment.words:
                # A decoder may emit segment text but fail word timestamping.
                # Dropping that segment would falsely connect its neighbors.
                text = getattr(segment, 'text', '').strip()
                if text:
                    observations.append({'occurrence_index':len(observations), 'run_index':run_index,
                        'text':text[:128], 'start':None, 'end':None, 'confidence':None,
                        'recognition_state':'unassessable'})
                unresolved = True; run_index += 1
                continue
            for word in segment.words or []:
                timing = all(math.isfinite(v) for v in [word.start, word.end]) and 0 <= word.start < word.end <= duration
                confidence = word.probability if math.isfinite(word.probability) and 0 <= word.probability <= 1 else None
                text = word.word.strip()
                valid = speech and timing and word.start >= previous_end and confidence is not None and confidence >= .75
                if timing: previous_end = max(previous_end, word.end)
                if valid:
                    local = samples[int(word.start*16000):int(word.end*16000)]
                    valid = bool(len(local)) and float(np.sqrt(np.mean(local.astype(np.float64)**2))) >= .02
                valid = valid and len(text.split()) == 1 and len(text) <= 128
                if text and len(text) <= 128:
                    observations.append({'occurrence_index':len(observations), 'run_index':run_index,
                        'text':text, 'start':word.start if timing else None, 'end':word.end if timing else None,
                        'confidence':confidence, 'recognition_state':'accepted' if valid else 'unassessable'})
                if not valid:
                    # A discarded source token is an acoustic discontinuity,
                    # not permission to join its two neighbors into an anchor.
                    unresolved = True; run_index += 1; continue
                words.append({'text':text, 'start':word.start, 'end':word.end,
                              'confidence':confidence, 'run_index':run_index})
            if not speech: run_index += 1
        elapsed = time.monotonic()-start
        self.completed += 1; self.total_seconds += elapsed
        return {'words': words, 'observations':observations, 'unresolved': unresolved, 'inference_ms': round(elapsed*1000, 3),
                'processing_configuration':configuration}
