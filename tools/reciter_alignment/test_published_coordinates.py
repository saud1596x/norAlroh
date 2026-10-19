"""No approximate labels, source-clock interpolation or foreign word IDs."""
import pytest
from published_coordinates import map_words, bind_row, normalize


def group(imlaei, canonical=None):
    return [1, '', imlaei, canonical or imlaei]


def test_only_existing_authored_aliases_allow_edition_spellings():
    assert map_words([group(['في'], ['فِى'])], ['فِي']) == [0]
    assert map_words([group(['على'])], ['علي']) is None
    assert map_words([group(['مالك'])], ['ملك']) is None
    assert map_words([group(['كتاب'], ['كِتَٰب'])], ['كِتَاب']) == [0]
    assert normalize('صلى') != normalize('صلي')
    assert map_words([group(['يا بني'], ['يَٰبَنِىٓ'])], ['يَٰبَنِيٓ']) == [0]


def test_compound_native_groups_keep_exact_published_subword_spans_and_gaps():
    mapping = map_words([group(['بعد', 'ما']), group(['سمعه'])], ['بَعْدِ', 'مَا', 'سَمِعَهُ'])
    assert mapping == [0, 0, 1]
    assert map_words([group(['بعد ما']), group(['سمعه'])], ['بَعْدِ', 'مَا', 'سَمِعَهُ']) == mapping
    row = ['2:181', 100, 900, True, 0, [[1, 100, 200], [2, 400, 500], [3, 600, 800]]]
    assert bind_row(row, [10, 11], mapping) == [[10, 100, 200], [10, 400, 500], [11, 600, 800]]


def test_unspoken_or_ambiguous_coordinates_cannot_supply_missing_words():
    assert map_words([group(['قل']), group(['هو'])], ['قل']) is None
    assert map_words([group(['قل'])], ['قل', 'هو']) is None
    assert map_words([group(['قل'])], []) is None
    # Distinct exact segmentations into the same count of authored groups.
    ambiguous = [group(['ب', 'ب'], ['ب']), group(['ب', 'ب'], ['ب'])]
    assert map_words(ambiguous, ['ب', 'ب', 'ب']) is None


@pytest.mark.parametrize('words', [
    [[1, 0, 100]], [[1, 100, 500], [2, 400, 600]], [[0, 100, 200]],
    [[3, 100, 200]], [[1, 100, 1100]], [[True, 100, 200]], [[1, 200, 100]]])
def test_foreign_indices_overlap_and_outside_occurrence_clocks_fail(words):
    with pytest.raises(ValueError):
        bind_row(['1:1', 100, 1000, True, 0, words], [7, 8], [0, 1])


def test_repeated_partial_occurrence_uses_its_explicit_positions_only():
    row = ['1:1', 1500, 2000, False, 0, [[2, 1600, 1700]]]
    assert bind_row(row, [7, 8], [0, 1]) == [[8, 1600, 1700]]


def test_real_reciter_repetition_can_return_to_prior_words_without_rewriting_clocks():
    row = ['1:1', 100, 1000, True, 0, [[1, 100, 200], [2, 200, 400], [1, 500, 600], [2, 650, 800]]]
    assert bind_row(row, [7, 8], [0, 1]) == [[7, 100, 200], [8, 200, 400], [7, 500, 600], [8, 650, 800]]
