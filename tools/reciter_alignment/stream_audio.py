"""Bounded sequential decoding; no seek approximation, skipped frames or padding."""
import gc
from contextlib import closing
import av
import numpy as np
from faster_whisper.audio import _group_frames, _resample_frames


def pcm_blocks(path):
    resampler=av.audio.resampler.AudioResampler(format='s16',layout='mono',rate=16000)
    try:
        with av.open(str(path),mode='r',metadata_errors='ignore') as container:
            # Use the pinned decoder's grouping/resampling exactly, but do not
            # silently discard invalid decoded frames and shift the audio clock.
            frames=_group_frames(container.decode(audio=0),500000)
            for frame in _resample_frames(frames,resampler):
                values=frame.to_ndarray().reshape(-1)
                if values.dtype!=np.int16:raise ValueError('Unexpected actual decoder format')
                yield values.astype(np.float32)/32768.0
    finally:
        del resampler
        gc.collect()


def bounded_pcm(path,maximum=1_920_000):
    blocks=[];count=0
    for block in pcm_blocks(path):
        count+=len(block)
        if count>maximum:raise AudioIntervalResourceLimit('Whole recording requires separately evidenced bounded ayah windows')
        blocks.append(block)
    if not blocks:raise ValueError('No actual decoded audio')
    return np.concatenate(blocks)


def control_prefix(path,maximum=480000):
    """Recover only a bounded real prefix for a resumed negative-control run.

    This excerpt is never accepted as a complete source recording. Closing the
    decoder early releases its file/container without decoding the whole surah.
    """
    if maximum<1:raise ValueError('Invalid control prefix limit')
    blocks=[];count=0
    with closing(pcm_blocks(path)) as decoded:
        for block in decoded:
            kept=block[:maximum-count].copy();blocks.append(kept);count+=len(kept)
            if count==maximum:break
    if not count:raise ValueError('No actual control audio')
    return np.concatenate(blocks)


class AudioIntervalResourceLimit(RuntimeError):
    pass


def windowed_pcm(blocks,windows,on_window,on_resource,maximum=720000,check=lambda:None):
    """Deliver exact sample intervals while retaining only the next bounded ayah.

    Long ayahs are explicitly unassessed while later bounded ayahs can still be
    measured. Full-file decoding supplies the actual final duration. The first
    bounded real clip is retained for negative controls, never for acceptance.
    """
    requests=[(ayah,max(0,start*16-6400),end*16+6400) for ayah,start,end in windows]
    if (not requests or maximum<400 or any(end<=first for _,first,end in requests)
        or any(a[1]>b[1] or a[2]>b[2] for a,b in zip(requests,requests[1:]))):
        raise ValueError('Nonmonotone actual source windows')
    buffer=np.empty(0,dtype=np.float32);origin=total=index=0
    controls=[];control_count=0;largest=0
    def skip_large():
        nonlocal index
        while index<len(requests) and requests[index][2]-requests[index][1]>maximum:
            on_resource(requests[index][0]);index+=1
    def trim():
        nonlocal buffer,origin
        first=min(total,requests[index][1]) if index<len(requests) else total
        drop=max(0,first-origin)
        buffer=buffer[drop:].copy();origin+=drop
    skip_large()
    for block in blocks:
        check()
        block=np.asarray(block)
        if block.ndim!=1 or block.dtype!=np.float32 or not np.isfinite(block).all():raise ValueError('Invalid actual source block')
        if control_count<480000:
            kept=block[:480000-control_count].copy();controls.append(kept);control_count+=len(kept)
        buffer=np.concatenate((buffer,block));total+=len(block);largest=max(largest,len(buffer))
        while index<len(requests) and requests[index][2]<=total:
            ayah,first,end=requests[index]
            if first<origin:raise ValueError('Actual source context was discarded')
            on_window(ayah,first,buffer[first-origin:end-origin].copy())
            index+=1;skip_large();trim()
        trim()
        if len(buffer)>maximum:raise ValueError('Actual bounded source buffer exceeded its window')
    while index<len(requests):
        check();ayah,first,end=requests[index]
        if first>=total:raise ValueError('Publisher window begins after actual audio ended')
        if first<origin:raise ValueError('Missing actual final context')
        on_window(ayah,first,buffer[first-origin:min(end,total)-origin].copy())
        index+=1;skip_large();trim()
    return total,np.concatenate(controls) if controls else np.empty(0,dtype=np.float32),largest
