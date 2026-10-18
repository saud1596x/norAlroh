"""Decoder-container policy only; generated samples are not acoustic acceptance."""
import struct
import numpy as np
import pytest
from export_coreml import read_float_wave


def wave(fmt, payload):
    body=b'WAVEfmt '+struct.pack('<I',len(fmt))+fmt+b'data'+struct.pack('<I',len(payload))+payload
    return b'RIFF'+struct.pack('<I',len(body))+body


def test_actual_float_container_does_not_reorder_or_pad_samples():
    pcm=np.array([.1,-.2,0,.3],dtype='<f4')
    fmt=struct.pack('<HHIIHH',3,1,16000,64000,4,32)
    assert np.array_equal(read_float_wave(wave(fmt,pcm.tobytes())),pcm)
    extended=struct.pack('<HHIIHHHHI',0xfffe,1,16000,64000,4,32,22,32,4)+bytes.fromhex('0300000000001000800000aa00389b71')
    assert np.array_equal(read_float_wave(wave(extended,pcm.tobytes())),pcm)


@pytest.mark.parametrize('format',[(1,1,16000,32000,2,16),(3,2,16000,128000,8,32),(3,1,48000,192000,4,32)])
def test_wrong_decoder_format_is_not_reinterpreted_as_valid_pcm(format):
    with pytest.raises(ValueError):read_float_wave(wave(struct.pack('<HHIIHH',*format),b'\0'*16))


def test_truncated_container_is_rejected():
    fmt=struct.pack('<HHIIHH',3,1,16000,64000,4,32)
    with pytest.raises(ValueError):read_float_wave(wave(fmt,b'\0'*16)[:-1])
