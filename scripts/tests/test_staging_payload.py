import hashlib
import importlib.util
import io
from pathlib import Path, PurePosixPath
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('noor_staging_installer',ROOT/'server/recitation/install_private_staging.py')
installer = importlib.util.module_from_spec(spec);spec.loader.exec_module(installer)


class StagingPayloadTests(unittest.TestCase):
    def test_pilot_exposes_only_loopback_and_cannot_mount_another_application(self):
        command=installer.container_command('noor:test','a'*64,PurePosixPath('/opt/noor/runtime.env'),
                                            PurePosixPath('/opt/noor/model'),'noor-test')
        self.assertEqual(command[command.index('--publish')+1],'127.0.0.1:8080:8080')
        mounts=[command[i+1] for i,x in enumerate(command) if x=='--mount']
        self.assertEqual(mounts,['type=bind,source=/opt/noor/model,target=/model,readonly',
                                'type=volume,source=noor_recitation_staging_data,target=/data'])
        self.assertNotIn('--privileged',command)
        self.assertNotIn('--network=host',command)
        self.assertIn('--read-only',command)
        self.assertEqual(command[command.index('--memory')+1],'1800m')

    def archive(self,path,extra=None):
        with tarfile.open(path,'w:gz') as package:
            for name in sorted(installer.EXACT):
                info=tarfile.TarInfo(name);info.size=4;package.addfile(info,io.BytesIO(b'test'))
            if extra is not None: package.addfile(extra,io.BytesIO(b''))
        return hashlib.sha256(path.read_bytes()).hexdigest()

    def test_hash_mismatch_does_not_extract_any_file(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);archive=root/'source.tar.gz';self.archive(archive);target=root/'target';target.mkdir()
            with self.assertRaises(ValueError):installer.unpack_verified(archive,'0'*64,target)
            self.assertEqual(list(target.iterdir()),[])

    def test_parent_traversal_or_links_cannot_escape_the_private_project(self):
        for name,kind in [('server/recitation/../../outside',tarfile.REGTYPE),
                          ('server/recitation/linked',tarfile.SYMTYPE)]:
            with self.subTest(name=name),tempfile.TemporaryDirectory() as folder:
                root=Path(folder);extra=tarfile.TarInfo(name);extra.type=kind;extra.linkname='/etc/passwd'
                archive=root/'source.tar.gz';digest=self.archive(archive,extra);target=root/'target';target.mkdir()
                with self.assertRaises(ValueError):installer.unpack_verified(archive,digest,target)
                self.assertEqual(list(target.iterdir()),[])

    def test_only_the_pinned_payload_is_extracted(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);archive=root/'source.tar.gz';digest=self.archive(archive);target=root/'target';target.mkdir()
            installer.unpack_verified(archive,digest,target)
            self.assertEqual({p.relative_to(target).as_posix() for p in target.rglob('*') if p.is_file()},installer.EXACT)
