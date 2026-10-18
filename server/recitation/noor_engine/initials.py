"""Exact position-bound spoken initials; never replace observed/display text.

Lexical names documented by the Quranic Arabic Corpus morphology, notably
2:1:1,19:1:1,20:1:1and36:1:1. No duration, pronunciation or Tajweed judgment.
"""
REVISION = 'spoken-initials1'
OPENINGS = {
    '2:1':'الم', '3:1':'الم', '7:1':'المص', '10:1':'الر', '11:1':'الر',
    '12:1':'الر', '13:1':'المر', '14:1':'الر', '15:1':'الر', '19:1':'كهيعص',
    '20:1':'طه', '26:1':'طسم', '27:1':'طس', '28:1':'طسم', '29:1':'الم',
    '30:1':'الم', '31:1':'الم', '32:1':'الم', '36:1':'يس', '38:1':'ص',
    '40:1':'حم', '41:1':'حم', '42:1':'حم', '42:2':'عسق', '43:1':'حم',
    '44:1':'حم', '45:1':'حم', '46:1':'حم', '50:1':'ق', '68:1':'ن',
}
NAMES = dict(zip('المصركهيعطسحقن',
    ['الف','لام','ميم','صاد','را','كاف','ها','يا','عين','طا','سين','حا','قاف','نون']))


def forms(verse, position, canonical_tokens):
    if position != 1 or verse not in OPENINGS:
        return set()
    opening = OPENINGS[verse]
    if tuple(canonical_tokens) != (opening,):
        raise ValueError('Spoken initials differ from their exact canonical location')
    result = {()}
    for letter in opening:
        name = NAMES[letter]
        next_forms = set()
        for previous in result:
            next_forms.add(previous+(name,))
            if previous:
                next_forms.add(previous[:-1]+(previous[-1]+name,))
        result = next_forms
    return result
