import hashlib
import importlib.util
import json
from pathlib import Path
from unittest.mock import patch

import pytest

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


def test_editable_manifest_cannot_redirect_a_byte_pinned_graph(tmp_path):
    pins,manifest=package(tmp_path)
    with patch.object(module,'PINS',pins):
        module.verify_source(tmp_path)
        manifest['itemInfoEntries']['model']['path']='../../different/model.mlmodel'
        (tmp_path/'Manifest.json').write_text(json.dumps(manifest))
        with pytest.raises(ValueError):module.verify_source(tmp_path)


def test_source_receipt_cannot_authorize_changed_weights_or_extra_graph(tmp_path):
    pins,_=package(tmp_path)
    with patch.object(module,'PINS',pins):
        weights=tmp_path/'Data/com.apple.CoreML/weights/weight.bin'
        weights.write_bytes(b'altered')
        with pytest.raises(ValueError):module.verify_source(tmp_path)
    pins,_=package(tmp_path)
    (tmp_path/'Data/other.mlmodel').write_bytes(b'extra')
    with patch.object(module,'PINS',pins),pytest.raises(ValueError):module.verify_source(tmp_path)
