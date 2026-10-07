"""Bounded retry behavior; no real network/font/version substitution."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock, patch
import urllib.error

spec = importlib.util.spec_from_file_location('font_download', Path(__file__).resolve().parents[1] / 'prepare-qcf-v2.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
URL = module.BASE + 'p1.ttf'

def response(url=URL):
    value = Mock(status=200, url=url)
    value.read.return_value = b'font-bytes'
    context = Mock()
    context.__enter__ = Mock(return_value=value)
    context.__exit__ = Mock(return_value=False)
    return context

class FontDownloadTests(unittest.TestCase):
    @patch.object(module.time, 'sleep')
    @patch.object(module.urllib.request, 'urlopen')
    def test_timeout_retries_then_returns_original_bytes(self, opened, sleep):
        opened.side_effect = [urllib.error.URLError(TimeoutError()), response()]
        self.assertEqual(module.download_font(URL), b'font-bytes')
        self.assertEqual(opened.call_count, 2)
        sleep.assert_called_once_with(1)

    @patch.object(module.time, 'sleep')
    @patch.object(module.urllib.request, 'urlopen')
    def test_exhausted_retries_fail(self, opened, sleep):
        opened.side_effect = TimeoutError()
        with self.assertRaises(TimeoutError): module.download_font(URL)
        self.assertEqual(opened.call_count, 4)
        self.assertEqual([x.args[0] for x in sleep.call_args_list], [1, 2, 4])

    @patch.object(module.time, 'sleep')
    @patch.object(module.urllib.request, 'urlopen')
    def test_access_denial_and_changed_source_are_not_retried(self, opened, sleep):
        opened.side_effect = urllib.error.HTTPError(URL, 403, 'Forbidden', None, None)
        with self.assertRaises(urllib.error.HTTPError): module.download_font(URL)
        opened.side_effect = None
        opened.return_value = response('https://example.org/other-font')
        with self.assertRaisesRegex(ValueError, 'Unexpected font source'): module.download_font(URL)
        sleep.assert_not_called()

if __name__ == '__main__': unittest.main()
