"""Operator-run public-audio component probe, isolated from the service database.

No identity bypass in the running API, learner audio, public listener, service
restart, secret/environment export, dependency installation or paid service.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
import time
import urllib.request
import uuid

SOURCE = 'bb1dc5a4ad7175e165c5134037172006cc2f323bf6cc827e46e189058e3ba151'
ROOT = Path('/opt/noor-recitation-staging')
UPLOAD = Path('/home/noor-staging')
NAME = 'noor-recitation-staging-public-probe'

PROBE = '''import asyncio,hashlib,json,time
from pathlib import Path
import numpy as np
from faster_whisper.audio import decode_audio
from noor_engine.inference import Recognizer
from noor_engine.corpus import Corpus

async def main():
    files=json.loads(Path('/probe/fixtures.json').read_text())
    model=Recognizer(Path('/model'),timeout=30,cpu_threads=1)
    began=time.monotonic();model.load();load=time.monotonic()-began
    corpus=Corpus(Path('/app'));records=[]
    for source in files:
        path=Path('/probe')/source['file']
        if hashlib.sha256(path.read_bytes()).hexdigest()!=source['sha256']:
            raise ValueError('Public fixture digest differs')
        pcm=decode_audio(str(path),sampling_rate=16000)
        if not 400<=len(pcm)<=128000:raise ValueError('Unbounded public fixture')
        result=await model.recognize(pcm)
        bindings=corpus.align(result['words'])
        # Recorded professional speech, without an expected-text prompt.
        records.append({'publicFile':source['file'],'sha256':source['sha256'],
            'expectedVerse':source['verse'],'durationSeconds':len(pcm)/16000,
            'result':result,'bindings':bindings})
    silence=await model.recognize(np.zeros(16000,dtype=np.float32))
    print('NOOR_PUBLIC_PROBE_RESULT '+json.dumps({'scope':'PUBLIC_AUDIO_COMPONENT_PROBE_NOT_API_OR_LEARNER_ACCEPTANCE',
        'model':model.model_id,'revision':model.revision,'cpuThreads':1,'modelLoadSeconds':load,
        'records':records,'silence':silence},ensure_ascii=False),flush=True)
asyncio.run(main())
'''


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest-sha256',required=True)
    args=parser.parse_args()
    if os.name!='posix' or os.geteuid()!=0:raise SystemExit('Host operator must run as root')
    os.umask(0o077)
    installed=json.loads((ROOT/'installation.json').read_text())
    if installed.get('sourceArchiveSHA256')!=SOURCE:raise SystemExit('Unexpected pilot source')
    container=json.loads(subprocess.check_output(['docker','inspect','noor-recitation-staging-api']))[0]
    labels=container['Config'].get('Labels') or {}
    if labels.get('noor.scope')!='private-staging' or labels.get('noor.source-sha256')!=SOURCE:
        raise SystemExit('Unexpected running service identity')
    with urllib.request.urlopen('http://127.0.0.1:8080/health/ready',timeout=5) as reply:
        health=json.load(reply)
    if health.get('ready') is not True:raise SystemExit('Pilot is not ready')
    available=next(int(line.split()[1])*1024 for line in Path('/proc/meminfo').read_text().splitlines()
                   if line.startswith('MemAvailable:'))
    if available<1800*1024**2:raise SystemExit('Insufficient spare RAM; service untouched')
    existing=subprocess.run(['docker','inspect',NAME],capture_output=True)
    if existing.returncode==0:raise SystemExit('A prior probe exists; no duplicate started')
    manifest=UPLOAD/'public-fixtures.json'
    if manifest.is_symlink() or hashlib.sha256(manifest.read_bytes()).hexdigest()!=args.manifest_sha256:
        raise SystemExit('Fixture manifest differs')
    sources=json.loads(manifest.read_text())
    folder=ROOT/('public-probe-'+uuid.uuid4().hex);folder.mkdir(mode=0o700)
    folder.chmod(0o755)  # Explicit: operator umask077 must not hide mounted probe files.
    for source in sources:
        name=source['file']
        if Path(name).name!=name or name not in {'112001.mp3','112002.mp3','114001.mp3'}:
            raise SystemExit('Unexpected public fixture')
        uploaded=UPLOAD/name
        if uploaded.is_symlink():raise SystemExit('Fixture may not be linked')
        target=folder/name;shutil.copyfile(uploaded,target)
        if hashlib.sha256(target.read_bytes()).hexdigest()!=source['sha256']:
            raise SystemExit('Fixture digest differs')
        target.chmod(0o444)
    (folder/'fixtures.json').write_text(json.dumps(sources));(folder/'fixtures.json').chmod(0o444)
    (folder/'probe.py').write_text(PROBE);(folder/'probe.py').chmod(0o444)
    command=['docker','run','--rm','--name',NAME,'--label','noor.scope=public-audio-probe',
        '--network','none','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges:true',
        '--pids-limit','64','--memory','1024m','--cpus','1','--user','10001',
        '--tmpfs','/tmp:size=32m,noexec,nosuid',
        '--mount','type=bind,source='+str(ROOT/'model')+',target=/model,readonly',
        '--mount','type=bind,source='+str(folder)+',target=/probe,readonly',
        container['Config']['Image'],'python','/probe/probe.py']
    began=time.monotonic()
    try:
        result=subprocess.run(command,capture_output=True,text=True,timeout=120)
        output={'scope':'PRIVATE_CPU_PUBLIC_AUDIO_PROBE_ONLY','readyBefore':health,
                'exit':result.returncode,'elapsedSeconds':time.monotonic()-began,
                'stdout':result.stdout[-100000:],'stderr':result.stderr[-10000:]}
    except subprocess.TimeoutExpired:
        # Only this explicitly-created temporary probe is stopped, never API.
        subprocess.run(['docker','stop','--time','5',NAME],capture_output=True)
        output={'scope':'PRIVATE_CPU_PUBLIC_AUDIO_PROBE_ONLY','readyBefore':health,
                'exit':'TIMEOUT','elapsedSeconds':time.monotonic()-began}
    with urllib.request.urlopen('http://127.0.0.1:8080/health/ready',timeout=5) as reply:
        output['readyAfter']=json.load(reply)
    account=pwd.getpwnam('noor-staging')
    destination=UPLOAD/('noor-public-probe-'+uuid.uuid4().hex+'.json')
    fd=os.open(destination,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
    with os.fdopen(fd,'w') as handle:
        json.dump(output,handle,ensure_ascii=False,indent=2);handle.write('\n')
        os.fchown(handle.fileno(),account.pw_uid,account.pw_gid)
    print('NOOR_PUBLIC_PROBE_SAVED',destination.name,'exit='+str(output['exit']),flush=True)


if __name__=='__main__':main()
