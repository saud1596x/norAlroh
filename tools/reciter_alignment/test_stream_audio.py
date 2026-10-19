"""Source-clock/memory policy and actual public-byte decoder parity."""
from pathlib import Path
import numpy as np
import pytest
from unittest.mock import patch
from faster_whisper.audio import decode_audio
from stream_audio import pcm_blocks,windowed_pcm,bounded_pcm,control_prefix,AudioIntervalResourceLimit


def test_actual_public_pcm_matches_existing_decoder_without_dropped_or_generated_samples():
    root=Path(__file__).resolve().parents[2]
    for name in ['001002','002001']:
        file=root/'ios/AtharTests/RecitationFixtures'/f'{name}.mp3'
        assert np.array_equal(np.concatenate(list(pcm_blocks(file))),decode_audio(str(file)))


def test_long_unassessed_interval_does_not_prevent_later_exact_window_or_retain_whole_file():
    # Deterministic frame indices exercise offsets, not recitation accuracy.
    source=np.arange(200000,dtype=np.float32)
    chunks=(source[i:i+4000] for i in range(0,len(source),4000))
    delivered=[];unassessed=[]
    total,control,largest=windowed_pcm(chunks,[[1,0,5000],[2,8000,9000]],
        lambda ayah,start,pcm:delivered.append((ayah,start,pcm)),unassessed.append,maximum=32000)
    assert total==len(source) and unassessed==[1]
    assert delivered[0][0:2]==(2,121600)
    assert np.array_equal(delivered[0][2],source[121600:150400])
    assert np.array_equal(control,source)
    assert largest<=36000


def test_whole_decode_limit_fails_explicitly_instead_of_truncating_public_audio():
    root=Path(__file__).resolve().parents[2]
    with pytest.raises(AudioIntervalResourceLimit):bounded_pcm(root/'ios/AtharTests/RecitationFixtures/002001.mp3',32000)


def test_resumed_control_prefix_is_exact_public_pcm_and_not_whole_recording():
    root=Path(__file__).resolve().parents[2]
    source=root/'ios/AtharTests/RecitationFixtures/002001.mp3'
    actual=decode_audio(str(source))
    prefix=control_prefix(source,32000)
    assert len(prefix)==32000<len(actual) and np.array_equal(prefix,actual[:32000])


def test_final_context_can_end_at_real_eof_but_no_missing_ayah_is_fabricated():
    actual=np.zeros(16000,dtype=np.float32);seen=[]
    total,_,_=windowed_pcm([actual],[[1,0,1000]],lambda a,s,p:seen.append(p),lambda _:None)
    assert total==16000 and np.array_equal(seen[0],actual)
    with pytest.raises(ValueError):windowed_pcm([actual],[[1,2000,3000]],lambda *_:None,lambda _:None)


def test_resource_limited_ayah_keeps_later_measurement_without_claiming_whole_recording():
    from verify_catalog import align_streamed_recording
    class PolicyAligner:
        def align(self,pcm,words):
            return {'spans':[[words[0][0],10,100]],'minimumWordPosterior':.9}
    record={}
    blocks=(np.zeros(4000,dtype=np.float32) for _ in range(244))
    with patch('verify_catalog.pcm_blocks',return_value=blocks):
        _,state=align_streamed_recording(PolicyAligner(),Path('policy-only'),[[1,0,50000],[2,54000,55000]],
            {1:[(1,'a')],2:[(2,'b')]},record,lambda:None)
    assert state=='RESOURCE_LIMIT_NOT_ASSESSED'
    assert record['ayahResults']['1']['status']=='RESOURCE_LIMIT_NOT_ASSESSED'
    assert record['ayahResults']['2']['status']=='MEASURED_CANDIDATE_REQUIRES_REVIEW'
    assert record['acceptedNativeWords']==1 and 'spans' not in record
    assert record['sourceFrameCount']==976000


def test_streamed_and_whole_transport_deliver_identical_original_public_pcm_and_native_clock():
    # Transport-only fixture boundaries/outputs, not ayah annotations, inferred
    # words or an acoustic-accuracy claim. Decode actual public MP3 bytes and
    # compare every sample supplied to the unchanged per-interval aligner.
    from verify_catalog import align_windows,align_streamed_recording
    root=Path(__file__).resolve().parents[2]
    source=root/'ios/AtharTests/RecitationFixtures/001002.mp3'
    actual=decode_audio(str(source))
    windows=[[1,0,1500],[2,1900,3500]]
    words={1:[(101,'transport-only')],2:[(102,'transport-only')]}
    class TransportProbe:
        def __init__(self):self.inputs=[]
        def align(self,pcm,labels):
            self.inputs.append((pcm.copy(),labels))
            return {'spans':[[labels[0][0],10,100]],'minimumWordPosterior':.9}
    whole,stream=TransportProbe(),TransportProbe()
    original,streamed={},{}
    align_windows(whole,actual,windows,words,original,lambda:None)
    control,state=align_streamed_recording(stream,source,windows,words,streamed,lambda:None)
    assert len(whole.inputs)==len(stream.inputs)==2
    for (left,left_ids),(right,right_ids) in zip(whole.inputs,stream.inputs):
        assert left_ids==right_ids and np.array_equal(left,right)
    assert state=='MEASURED_CANDIDATE_REQUIRES_REVIEW'
    assert streamed['spans']==[[101,10,100],[102,1510,1600]]
    assert streamed['sourceFrameCount']==len(actual)
    assert np.array_equal(control,actual[:480000])
    assert streamed['maximumRetainedPCMFrames']<=720000
