import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('selectors', Path(__file__).parents[1] / 'check-native-test-selectors.py')
selectors = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selectors)


class NativeSelectorTests(unittest.TestCase):
    def test_two_suites_in_one_file_keep_their_own_methods(self):
        found = selectors.declarations('''
// class Removed: XCTestCase { func testGone() {} }
@MainActor final class First: XCTestCase {
 func testFirst() {}
}
final class Second: XCTestCase {
 func testSecond() {}
}
''')
        self.assertEqual(found, {'First': {'testFirst'}, 'Second': {'testSecond'}})

    def test_removed_or_renamed_method_cannot_silently_select_zero_tests(self):
        suites = {'AtharUITests': {'Current': {'testInlineReader'}}, 'AtharTests': {}}
        for text in ['-only-testing:AtharUITests/Removed',
                     '-only-testing:AtharUITests/Current/testOldWorkspace',
                     '-skip-testing:AtharUITests/Current/testOldWorkspace']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                selectors.validate(text, suites, 'real-script.sh')
        self.assertEqual(selectors.validate('-only-testing:AtharUITests/Current/testInlineReader', suites, 'script'), 1)

    def test_all_current_script_selectors_exist_in_the_real_project(self):
        suites = selectors.inventory()
        self.assertIn('QuranWordAlignmentTests', suites['AtharTests'])
        self.assertIn('QuranAudioBackendControlTests', suites['AtharTests'])
        for path in (selectors.ROOT / 'scripts').glob('*.sh'):
            selectors.validate(path.read_text(encoding='utf-8'), suites, path.name)


if __name__ == '__main__':
    unittest.main()
