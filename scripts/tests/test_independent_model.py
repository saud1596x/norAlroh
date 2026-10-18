import hashlib
import importlib.util
import json
from pathlib import Path
from unittest.mock import patch
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('ctc_prepare',Path(__file__).parents[1]/'prepare-independent-ctc.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)


def package(folder):
    pins={}
    for name in module.PINS:
        file=folder/name;file.parent.mkdir(parents=True,exist_ok=True);file.write_bytes(name.encode())
        pins[name]=hashlib.sha256(file.read_bytes()).hexdigest()
    manifest={'fileFormatVersion':'1.0.0','rootModelIdentifier':'model',
        'itemInfoEntries':{'model':{'path':'com.apple.CoreML/model.mlmodel'},
                           'weights':{'path':'com.apple.CoreML/weights'}}}
    (folder/'Manifest.json').write_text(json.dumps(manifest))
    return pins,manifest


class IndependentModelIntegrityTests(unittest.TestCase):
    def setUp(self):
        folder=tempfile.TemporaryDirectory();self.addCleanup(folder.cleanup)
        self.folder=Path(folder.name)

    def test_editable_manifest_cannot_redirect_a_byte_pinned_graph(self):
        pins,manifest=package(self.folder)
        with patch.object(module,'PINS',pins):
            module.verify_source(self.folder)
            manifest['itemInfoEntries']['model']['path']='../../different/model.mlmodel'
            (self.folder/'Manifest.json').write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):module.verify_source(self.folder)

    def test_source_receipt_cannot_authorize_changed_weights_or_extra_graph(self):
        pins,_=package(self.folder)
        with patch.object(module,'PINS',pins):
            weights=self.folder/'Data/com.apple.CoreML/weights/weight.bin'
            weights.write_bytes(b'altered')
            with self.assertRaises(ValueError):module.verify_source(self.folder)
        pins,_=package(self.folder)
        (self.folder/'Data/other.mlmodel').write_bytes(b'extra')
        with patch.object(module,'PINS',pins),self.assertRaises(ValueError):module.verify_source(self.folder)


if __name__ == '__main__':
    unittest.main()
