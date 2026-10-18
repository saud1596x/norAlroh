"""Versioned PCM windows and deterministic, source-bound recitation events."""
import hashlib
import struct
import time
from itertools import groupby
import numpy as np
from pydantic import BaseModel, ConfigDict, Field, StrictInt, model_validator
from .observations import candidates


class AudioHeader(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)
    schema_version: StrictInt = 1
    sequence: StrictInt = Field(ge=0, le=10000)
    start_frame: StrictInt = Field(ge=0, le=28_800_000)
    end_frame: StrictInt = Field(gt=0, le=28_800_000)
    sample_rate: StrictInt = 16000
    format: str = 'f32le'

    @model_validator(mode='after')
    def boundaries(self):
        if self.schema_version != 1 or self.sample_rate != 16000 or self.format != 'f32le':
            raise ValueError('unsupported format')
        if not 1 <= self.end_frame-self.start_frame <= 128000: raise ValueError('invalid window')
        return self

    def decode(self, raw):
        if len(raw) != (self.end_frame-self.start_frame)*4: raise ValueError('PCM size mismatch')
        samples = np.frombuffer(raw, dtype='<f4')
        if not np.isfinite(samples).all() or np.any(np.abs(samples) > 1): raise ValueError('invalid PCM')
        return samples

    def digest(self, raw):
        return hashlib.sha256(struct.pack('<QQQ', self.sequence, self.start_frame, self.end_frame)+raw).hexdigest()


class SessionIntelligence:
    def __init__(self, corpus, model_id, model_revision):
        self.corpus, self.model_id, self.model_revision = corpus, model_id, model_revision
        self.source = {'engine':'noor-session-1', 'model_id':model_id, 'model_revision':model_revision,
                       'corpus_version':corpus.version}

    def process(self, session_id, row, header, decoded):
        previous = row['decoded_state']
        if previous.get('source') != self.source: raise ValueError('session source version changed')
        offset = header.start_frame/16000
        heard = [dict(w, start=w['start']+offset, end=w['end']+offset) for w in decoded['words']]
        # Revisions remove only evidence fully contained in this exact audio
        # interval; a previous interpretation is never permanent merely because
        # one earlier window recognized it.
        first, last = header.start_frame/16000, header.end_frame/16000
        retained = [e for e in previous.get('evidence', []) if not (e['start'] >= first and e['end'] <= last)]
        surviving_cursor = self.corpus.by_id[retained[-1]['native_id']]+1 if retained else None
        aligned = []
        cursor = surviving_cursor
        for _, run in groupby(heard, key=lambda w:w.get('run_index', 0)):
            anchor = self.corpus.align(list(run), expected_cursor=cursor)
            aligned.extend(anchor)
            if anchor: cursor = self.corpus.by_id[anchor[-1]['native_id']]+1
        observations = candidates(self.corpus, heard, aligned) if not decoded['unresolved'] else []
        retained_observations = [e for e in previous.get('observations', []) if not (e['start'] >= first and e['end'] <= last)]
        state = {'evidence': (retained + aligned)[-200:], 'verse':retained[-1]['verse'] if retained else None,
                 'observations':(retained_observations + observations)[-100:], 'cursor':surviving_cursor,
                 'source':self.source}
        counter = row['event_id']
        events = []
        def emit(kind, payload):
            nonlocal counter
            counter += 1
            events.append({'schema_version':1, 'event_id':counter, 'type':kind, 'session_id':session_id,
                'audio_sequence':header.sequence, 'audio_start_frame':header.start_frame, 'audio_end_frame':header.end_frame,
                'created_at_ms':int(time.time()*1000), 'engine_version':'noor-session-1', 'model_id':self.model_id,
                'model_revision':self.model_revision, 'corpus_version':self.corpus.version, 'payload':payload})
        emit('AUDIO_ACCEPTED', {'next_sequence':header.sequence+1})
        # A complete replacement is sent before increments, allowing deterministic
        # client retraction after overlapping-window changes and reconnect.
        emit('PARTIAL_RECOGNITION', {'uncertain':decoded['unresolved'] or not bool(aligned),
             'evidence':state['evidence'], 'wording_assessment':'uncalibrated', 'tajweed_assessment':'unsupported'})
        old = {(e['native_id'], e['start'], e['end']) for e in previous.get('evidence', [])}
        for evidence in aligned:
            if (evidence['native_id'], evidence['start'], evidence['end']) not in old:
                emit('WORD_CONFIRMED', evidence)
        old_notes = {v['observation_id']:v for v in previous.get('observations', [])}
        new_notes = {v['observation_id']:v for v in state['observations']}
        for identity in old_notes.keys()-new_notes.keys():
            emit('ERROR_RETRACTED', {'observation_id':identity, 'reason':'audio_window_revised_or_corrected'})
        for identity in new_notes.keys()-old_notes.keys():
            emit('ERROR_CANDIDATE', new_notes[identity])
        if aligned:
            verse = aligned[-1]['verse']
            if verse != previous.get('verse'):
                emit('VERSE_LOCATION_CHANGED', {'verse':verse, 'page':aligned[-1]['page'], 'basis':'exact-acoustic-token-anchor'})
            state['verse'] = verse
            state['cursor'] = self.corpus.by_id[aligned[-1]['native_id']]+1
        elif not heard:
            emit('SESSION_INTERRUPTED', {'reason':'silence_or_unresolved_audio', 'is_recitation_error':False})
        source_observations = [dict(w, start=w['start']+offset if w['start'] is not None else None,
            end=w['end']+offset if w['end'] is not None else None) for w in decoded.get('observations', [])]
        return state, {'sequence':header.sequence, 'events':events, 'words':heard, 'observations':source_observations,
                       'has_unresolved_speech':decoded['unresolved'], 'inference_ms':decoded['inference_ms'],
                       'processing_configuration':decoded.get('processing_configuration','unavailable')}, counter
