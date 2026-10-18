"""Operator-run, isolated CPU pilot on the existing host; never production.

No SSH/sudo grant to the upload account, public listener, proxy edit, DNS change,
subscription, existing-service stop or automatic deletion. Docker execution is
performed only when the host operator explicitly runs this reviewed installer.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import socket
import subprocess
import tarfile
import time
import urllib.request

DESTINATION = Path('/opt/noor-recitation-staging')
UPLOAD = Path('/home/noor-staging')
PROJECT = 'noor-recitation-staging'
DATA = 'noor_recitation_staging_data'
EXACT = {'.dockerignore', 'content-sources/recitation-word-script.json',
         'content-sources/mushaf-snapshot.json.gz', 'ios/Athar/quran.json'}


def unpack_verified(archive, digest, destination):
    if hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
        raise ValueError('Source archive digest differs; nothing extracted')
    with tarfile.open(archive, 'r:gz') as package:
        members = package.getmembers()
        if sum(m.size for m in members) > 32_000_000: raise ValueError('Oversized source package')
        seen = set()
        for member in members:
            path = PurePosixPath(member.name)
            allowed = member.name in EXACT or member.name.startswith('server/recitation/')
            if (path.is_absolute() or '..' in path.parts or not allowed or member.name in seen
                    or not member.isfile()):
                raise ValueError('Unsafe or unexpected source member')
            seen.add(member.name)
        if not EXACT.issubset(seen): raise ValueError('Required pinned corpus files missing')
        for member in members:
            target = destination.joinpath(*PurePosixPath(member.name).parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.is_symlink(): raise ValueError('Unexpected destination symlink')
            with package.extractfile(member) as source, target.open('wb') as output:
                shutil.copyfileobj(source, output)
            target.chmod(0o644)
    # The operator's umask protects credentials, but image source directories
    # must be traversable by the unprivileged image UID. COPY preserves modes.
    destination.chmod(0o755)
    for directory in destination.rglob('*'):
        if directory.is_symlink(): raise ValueError('Unexpected source symlink')
        if directory.is_dir(): directory.chmod(0o755)


def run(*args):
    subprocess.run(args,check=True)


def container_command(tag, digest, env, model, name):
    # No compose installation, host network, public listener or existing app
    # mount. Resource bounds and Docker's loopback binding are explicit.
    return ['docker','run','--detach','--name',name,
        '--label','noor.source-sha256='+digest,'--label','noor.scope=private-staging',
        '--env-file',str(env),'--env','NOOR_DATABASE_URL=sqlite:////data/noor.db',
        '--env','NOOR_ENVIRONMENT=local','--env','NOOR_FIREBASE_PROJECT_ID=noor-alruh',
        '--env','NOOR_INFERENCE_DEVICE=cpu','--env','NOOR_CPU_THREADS=2',
        '--env','NOOR_MAX_SESSIONS=2','--publish','127.0.0.1:8080:8080',
        '--mount','type=bind,source='+str(model)+',target=/model,readonly',
        '--mount','type=volume,source='+DATA+',target=/data',
        '--read-only','--tmpfs','/tmp:size=32m,noexec,nosuid','--cap-drop','ALL',
        '--security-opt','no-new-privileges:true','--pids-limit','96','--memory','1800m',
        '--cpus','1.5','--stop-timeout','45','--restart','unless-stopped',
        '--log-driver','local','--log-opt','max-size=5m','--log-opt','max-file=2',tag]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive-sha256',required=True)
    parser.add_argument('--repair-existing-import',action='store_true',
                        help='Rebuild the exact installed source and retain the stopped prior container')
    args = parser.parse_args()
    digest = args.archive_sha256
    if len(digest)!=64 or any(c not in '0123456789abcdef' for c in digest):
        raise SystemExit('Exact source SHA256 required')
    if os.name!='posix' or os.geteuid()!=0: raise SystemExit('Host operator must run this installer as root')
    os.umask(0o077)
    run('docker','version','--format','{{.Server.Version}}')
    marker = DESTINATION/'installation.json'
    if args.repair_existing_import and not marker.is_file():
        raise SystemExit('Import repair requires an existing matching pilot')
    if DESTINATION.exists():
        if DESTINATION.is_symlink() or not marker.is_file(): raise SystemExit('Existing destination not owned by this installer')
        if json.loads(marker.read_text()).get('sourceArchiveSHA256')!=digest:
            raise SystemExit('Different existing pilot; explicit upgrade/rollback review required')
    else:
        with socket.socket() as probe: probe.bind(('127.0.0.1',8080))
        if shutil.disk_usage('/opt').free < 4*1024**3: raise SystemExit('Insufficient free disk')
        available = next(int(line.split()[1])*1024 for line in Path('/proc/meminfo').read_text().splitlines()
                         if line.startswith('MemAvailable:'))
        if available < 2400*1024**2: raise SystemExit('Insufficient available RAM; no changes made')
        DESTINATION.mkdir(mode=0o700)
        marker.write_text(json.dumps({'sourceArchiveSHA256':digest,'scope':'PRIVATE_CPU_PILOT_NOT_PRODUCTION'})+'\n')
    # First copy into a root-owned directory, then hash/extract that copy.
    source = UPLOAD/'noor-source.tar.gz'
    if source.is_symlink(): raise SystemExit('Uploaded archive may not be a symlink')
    archive = DESTINATION/'source.tar.gz'
    shutil.copyfile(source,archive)
    app = DESTINATION/'app'; app.mkdir(exist_ok=True)
    unpack_verified(archive,digest,app)
    model = DESTINATION/'model';model.mkdir(exist_ok=True)
    pins = json.loads((app/'server/recitation/model-manifest.json').read_text())['files']
    for name, expected in pins.items():
        if Path(name).name!=name: raise SystemExit('Unsafe model filename')
        uploaded = UPLOAD/'model'/name
        if uploaded.is_symlink(): raise SystemExit('Model may not be a symlink')
        target = model/name
        shutil.copyfile(uploaded,target)
        if hashlib.sha256(target.read_bytes()).hexdigest()!=expected: raise SystemExit('Pinned model asset mismatch')
        target.chmod(0o444)
    # Allow the unprivileged image UID to traverse only its model directory.
    model.chmod(0o755)
    env = DESTINATION/'runtime.env'
    if not env.exists():
        with env.open('x') as output:
            output.write('NOOR_DATA_KEY='+base64.urlsafe_b64encode(os.urandom(32)).decode()+'\n')
        env.chmod(0o600)
    tag = PROJECT+':'+digest[:12]+('-importfix1' if args.repair_existing_import else '')
    run('docker','build','--pull','--tag',tag,'--file',str(app/'server/recitation/Dockerfile'),str(app))
    # Exercise Python imports as image UID 10001 before replacing any container.
    # No credentials, host mounts, network, model load or database writes.
    run('docker','run','--rm','--network','none','--read-only',
        '--cap-drop','ALL','--security-opt','no-new-privileges:true',
        '--memory','512m','--cpus','1',tag,'python','-c',
        'import noor_engine.api; print("NOOR_IMAGE_IMPORT_OK")')
    run('docker','volume','create',DATA)
    run('docker','run','--rm','--network','none','--user','0',
        '--mount','type=volume,source='+DATA+',target=/data',tag,'python','-c',
        'import os;os.chown("/data",10001,10001);os.chmod("/data",0o700)')
    name = PROJECT+'-api'
    found = subprocess.run(['docker','container','inspect',name],capture_output=True,text=True)
    if found.returncode==0:
        existing=json.loads(found.stdout)[0]
        labels=existing.get('Config',{}).get('Labels',{}) or {}
        if labels.get('noor.source-sha256')!=digest or labels.get('noor.scope')!='private-staging':
            raise SystemExit('Existing container identity differs; no container changed')
        if args.repair_existing_import:
            backup = name+'-before-importfix1'
            prior = subprocess.run(['docker','container','inspect',backup],capture_output=True)
            if prior.returncode==0:
                raise SystemExit('Prior repair container already exists; inspect it before retrying')
            run('docker','stop',name)
            run('docker','rename',name,backup)
            run(*container_command(tag,digest,env,model,name))
        else:
            run('docker','start',name)
    else:
        run(*container_command(tag,digest,env,model,name))
    deadline = time.monotonic()+120
    while time.monotonic()<deadline:
        try:
            with urllib.request.urlopen('http://127.0.0.1:8080/health/ready',timeout=3) as response:
                ready = json.load(response)
            if ready.get('ready') is True:
                print('NOOR_PRIVATE_STAGING_READY',json.dumps(ready),flush=True)
                print('Loopback pilot only. No public TLS route, iOS connection, PostgreSQL production or acceptance claim.')
                return
        except Exception: pass
        time.sleep(1)
    raise SystemExit('Noor pilot did not become ready; no existing application was stopped. Keep artifacts for diagnosis.')


if __name__=='__main__': main()
