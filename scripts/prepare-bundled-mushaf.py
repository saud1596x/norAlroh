"""Expand the approved Content Sync edition, verifying every lexical glyph."""
import gzip
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def verified_snapshot():
    manifest = json.loads((ROOT / "content-sources/mushaf-snapshot-manifest.json").read_text())
    compressed = (ROOT / "content-sources/mushaf-snapshot.json.gz").read_bytes()
    if hashlib.sha256(compressed).hexdigest() != manifest["compressedSHA256"]:
        raise ValueError("Compressed Mushaf checksum mismatch")
    data = gzip.decompress(compressed)
    if len(data) != manifest["bytes"] or hashlib.sha256(data).hexdigest() != manifest["sha256"]:
        raise ValueError("Mushaf payload checksum mismatch")
    snapshot = json.loads(data)
    if snapshot["resource_id"] != 1 or snapshot["resource_content_id"] != 382:
        raise ValueError("Mushaf edition mismatch")
    corpus = json.loads((ROOT / "ios/Athar/quran.json").read_text(encoding="utf-8"))
    keys = [f"{s['number']}:{a['number']}" for s in corpus for a in s["ayahs"]]
    script = json.loads((ROOT / "content-sources/recitation-word-script.json").read_text(encoding="utf-8"))
    by_verse = {}
    for word in snapshot["records"]:
        if word["record_type"] == "mushaf_word" and word["char_type_name"] == "word":
            by_verse.setdefault(keys[word["verse_id"]-1], []).append(word)
    if len(keys) != 6236 or set(by_verse) != set(script["groups"]):
        raise ValueError("Mushaf verse coverage mismatch")
    count = 0
    for key in keys:
        words = sorted(by_verse[key], key=lambda w: w["position_in_verse"])
        groups = script["groups"][key]
        if len(words) != len(groups):
            raise ValueError("Mushaf word count mismatch")
        for index, (word, group) in enumerate(zip(words, groups), 1):
            if (word["position_in_verse"], word["page_number"], word["text"]) != (index, group[0], group[1]):
                raise ValueError(f"Mushaf canonical glyph mismatch at {key}:{index}")
            count += 1
    if count != 77429:
        raise ValueError("Mushaf total word count mismatch")
    return data


if __name__ == "__main__":
    data = verified_snapshot()
    target = ROOT / "ios/Athar/mushaf-snapshot.json"
    target.write_bytes(data)
    print("Verified bundled Mushaf: 6236 verses, 77429 original lexical glyph records; no network required.")
