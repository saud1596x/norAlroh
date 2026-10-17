import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
spec = importlib.util.spec_from_file_location('remote_ipa_gate',ROOT/'scripts/verify-release-ipa.py')
gate = importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)


class RemoteReleasePolicyTests(unittest.TestCase):
    def test_local_release_stays_local_and_remote_cannot_use_old_policy(self):
        self.assertFalse(gate.verify_remote_policy({},{}))
        with self.assertRaises(ValueError):
            gate.verify_remote_policy({'NoorRecitationServerURL':'https://staging.example.com',
                                       'NoorRemoteProcessingPolicyVersion':1},{})

    def test_declared_origin_consent_retention_and_notice_must_match(self):
        info = {'NoorRecitationServerURL':'https://staging.example.com','NoorRemoteProcessingPolicyVersion':1}
        declaration = {'policyVersion':1,'explicitConsent':True,'audioRetention':'none',
            'derivedRetentionSeconds':3600,'accountDeletionIncludesInference':True,'serverOrigin':'https://staging.example.com'}
        legal = {'remoteRecitation':declaration, 'documents':[{'id':'privacy','sections':[
            {'id':'remote-recitation','text':'Test-only policy fixture: audio is transient; derived recovery state is encrypted, expires within one hour and account deletion purges it.'}]}]}
        self.assertTrue(gate.verify_remote_policy(info,legal))
        for key, value in [('explicitConsent',False),('serverOrigin','https://other.example.com'),
                           ('audioRetention','forever'),('accountDeletionIncludesInference',False)]:
            wrong = dict(legal, remoteRecitation=dict(declaration,**{key:value}))
            with self.subTest(key=key), self.assertRaises(ValueError): gate.verify_remote_policy(info,wrong)
        for url in ['http://staging.example.com','https://user:secret@example.com','https://example.com?token=x']:
            with self.subTest(url=url), self.assertRaises(ValueError):
                gate.verify_remote_policy(dict(info,NoorRecitationServerURL=url),legal)
