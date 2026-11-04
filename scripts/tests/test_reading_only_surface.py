"""Source/packaging guardrails; these do not execute the iOS application."""
import pathlib
import plistlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
APP = ROOT / 'ios' / 'Athar'

class ReadingOnlySurfaceTests(unittest.TestCase):
    def test_shipping_app_does_not_advertise_capture_permissions(self):
        info = plistlib.loads((APP / 'Info.plist').read_bytes())
        self.assertNotIn('NSMicrophoneUsageDescription', info)
        self.assertNotIn('NSSpeechRecognitionUsageDescription', info)

    def test_launch_does_not_construct_retired_capture_service(self):
        source = (APP / 'AtharApp.swift').read_text(encoding='utf-8')
        self.assertNotRegex(source, r'LocalRecitationRecorder\s*\(')
        self.assertNotRegex(source, r'QuranRecitationController\s*\(')

    def test_reader_and_navigation_have_no_capture_entry(self):
        for name in ('InteractiveMushafReader.swift', 'MushafReader.swift', 'NoorTodayView.swift', 'NoorWelcome.swift'):
            source = (APP / name).read_text(encoding='utf-8')
            with self.subTest(file=name):
                self.assertNotRegex(source, r'QuranRecitationController\s*\(')
                self.assertNotRegex(source, r'SpeechRecitationView\s*\(')
                self.assertNotRegex(source, r'(?:Button|Label|Text)\("[^"\n]*تسميع')
        reader = (APP / 'InteractiveMushafReader.swift').read_text(encoding='utf-8')
        values = re.findall(r'tajweedEnabled:\s*([^,\n]+)', reader)
        self.assertTrue(values)
        self.assertEqual(set(values), {'false'})

if __name__ == '__main__':
    unittest.main()
