"""Typed public response contracts, shared with generated OpenAPI/WS schemas."""
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, JsonValue


class Contract(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)


class ErrorReply(Contract):
    detail: str


class WindowError(Contract):
    error: Literal['engine_busy', 'inference_timeout']
    retryable: Literal[True]
    sequence: int = Field(ge=0)


class CredentialReply(Contract):
    access_token: str
    refresh_token: str
    expires_in: int = Field(gt=0, le=900)
    token_type: Literal['Bearer']


class ChallengeReply(Contract):
    challenge: str
    nonce: str
    expires_in: Literal[300]


class ReadyReply(Contract):
    ready: Literal[True]
    model_id: str
    model_revision: str
    corpus_version: str
    wording_assessment: Literal['uncalibrated']
    tajweed_assessment: Literal['unsupported']
    word_evidence_version: Literal[2]


class CreatedReply(Contract):
    session_id: str
    next_sequence: Literal[0]
    websocket_path: str
    expires_in: int
    max_window_frames: Literal[128000]
    max_inflight: Literal[1]
    audio_retention: Literal['none']
    recovery_metadata_retention_seconds: int


class Event(Contract):
    schema_version: Literal[1]
    event_id: int = Field(gt=0)
    type: Literal['AUDIO_ACCEPTED','PARTIAL_RECOGNITION','WORD_CONFIRMED','ERROR_CANDIDATE',
                  'ERROR_RETRACTED','VERSE_LOCATION_CHANGED','SESSION_INTERRUPTED']
    session_id: str
    audio_sequence: int = Field(ge=0)
    audio_start_frame: int = Field(ge=0)
    audio_end_frame: int = Field(gt=0)
    created_at_ms: int = Field(gt=0)
    engine_version: str
    model_id: str
    model_revision: str
    corpus_version: str
    payload: dict[str, JsonValue]


class HeardWord(Contract):
    text: str = Field(min_length=1, max_length=128)
    start: float = Field(ge=0)
    end: float = Field(gt=0)
    confidence: float = Field(ge=.75, le=1)
    run_index: int = Field(default=0, ge=0, le=320)


class SourceWord(Contract):
    occurrence_index: int = Field(ge=0, le=319)
    run_index: int = Field(ge=0, le=320)
    text: str = Field(min_length=1, max_length=128)
    start: float | None = Field(default=None, ge=0)
    end: float | None = Field(default=None, gt=0)
    confidence: float | None = Field(default=None, ge=0, le=1)
    recognition_state: Literal['accepted', 'unassessable']


class WindowReply(Contract):
    sequence: int = Field(ge=0)
    events: list[Event] = Field(min_length=1, max_length=400)
    words: list[HeardWord] = Field(max_length=160)
    observations: list[SourceWord] = Field(default_factory=list, max_length=320)
    has_unresolved_speech: bool
    inference_ms: float = Field(ge=0)
    processing_configuration: str


class RecoveryReply(Contract):
    session_id: str
    next_sequence: int = Field(ge=0)
    end_frame: int = Field(ge=0)
    last_event_id: int = Field(ge=0)
    state: dict[str, JsonValue]
