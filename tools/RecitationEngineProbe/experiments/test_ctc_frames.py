import unittest
from ctc_frames import observed_words


class FrameEvidenceTests(unittest.TestCase):
    vocab = {'<pad>': 0, '|': 1, 'ل': 2, 'ه': 3, '<unk>': 4}

    def decode(self, ids, probabilities=None):
        return observed_words(ids, probabilities or [0.9]*len(ids), self.vocab, (len(ids)-1)*320+400)

    def test_blank_separates_actual_repeated_characters(self):
        words = self.decode([2, 2, 0, 2, 1, 3, 0])
        self.assertEqual([word['text'] for word in words], ['لل', 'ه'])
        self.assertTrue(words[0]['complete'])
        self.assertFalse(words[1]['complete'])
        self.assertEqual(words[0]['start'], 0)
        self.assertEqual(words[0]['end'], (3*320+400)/16000)

    def test_delimiter_occurrences_never_invent_empty_words(self):
        self.assertEqual([word['text'] for word in self.decode([1, 0, 1, 2, 1])], ['ل'])
        self.assertEqual(self.decode([0, 0, 0]), [])

    def test_unknown_source_is_preserved_but_unassessable(self):
        word = self.decode([2, 4, 1])[0]
        self.assertEqual(word['text'], 'ل<unk>')
        self.assertFalse(word['complete'])

    def test_nonfinite_or_out_of_audio_evidence_is_rejected(self):
        with self.assertRaises(ValueError):self.decode([2], [float('nan')])
        with self.assertRaises(ValueError):observed_words([2, 1], [0.9, 0.9], self.vocab, 400)
        with self.assertRaises(ValueError):self.decode([99])


if __name__ == '__main__':unittest.main()
