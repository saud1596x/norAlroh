"""Check the user-review channel cannot silently certify or change source."""
import copy
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('review', Path(__file__).parents[1] / 'check-user-testflight.py')
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)


class UserReviewTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        (self.root / 'source.swift').write_text('unchanged source')
        self.files = ['source.swift']
        self.value = dict(schema=1, channel='TESTFLIGHT_USER_REVIEW', authorization=review.REQUEST,
                          status='AUTHORIZED_FOR_USER_TESTING_ONLY', appleAppID='6819365625',
                          bundleID='com.saud1596x.nooralruh', submitToAppStore=False,
                          newExternalTesterInvitations=False, unverified=copy.deepcopy(review.UNVERIFIED),
                          sourceHashes={'source.swift': hashlib.sha256((self.root / 'source.swift').read_bytes()).hexdigest()})

    def test_exact_unverified_user_build_is_allowed(self):
        review.validate(self.value, self.root, self.files)

    def test_source_changes_or_inventory_omissions_are_rejected(self):
        with self.assertRaises(ValueError):
            review.validate(self.value, self.root, self.files + ['new.swift'])
        (self.root / 'source.swift').write_text('changed')
        with self.assertRaises(ValueError):
            review.validate(self.value, self.root, self.files)

    def test_no_production_or_false_pass_claim(self):
        for patch in [dict(submitToAppStore=True), dict(newExternalTesterInvitations=True),
                      dict(channel='APP_STORE'), dict(appleAppID='other'),
                      dict(status='SUCCESS'), dict(authorization=''),
                      dict(unverified={**review.UNVERIFIED, 'actualSimulatorAudio': 'PASSED'})]:
            with self.subTest(patch=patch), self.assertRaises(ValueError):
                review.validate({**self.value, **patch}, self.root, self.files)


if __name__ == '__main__':
    unittest.main()
