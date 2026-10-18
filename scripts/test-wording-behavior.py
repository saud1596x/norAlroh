"""Execute the real portable production sources and iOS algorithm tests in Swift.
This checks decisions and persistence, not acoustic accuracy or device capture.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    "tools/RecitationEngineProbe/Sources/RecitationCapture/QuranInputQuality.swift",
    "tools/RecitationEngineProbe/Sources/RecitationAlignment/QuranWordAlignment.swift",
    "tools/RecitationEngineProbe/Sources/RecitationAlignment/QuranIndependentAgreement.swift",
    "tools/RecitationEngineProbe/Sources/RecitationSessions/QuranIndependentObservation.swift",
    "tools/RecitationEngineProbe/Sources/RecitationSessions/QuranRecitationJournal.swift",
    "tools/RecitationEngineProbe/Sources/RecitationSessions/QuranWordingAssessment.swift",
]
TESTS = ["ios/AtharTests/QuranWordingAssessmentTests.swift", "ios/AtharTests/QuranObservedSpeechTests.swift"]

with tempfile.TemporaryDirectory(prefix="noor-wording-") as directory:
    package = Path(directory)
    (package / "Sources/Athar").mkdir(parents=True)
    (package / "Tests/BehaviorTests").mkdir(parents=True)
    evidence = {}
    for name in SOURCES + TESTS:
        path = ROOT / name
        target = package / ("Tests/BehaviorTests" if name in TESTS else "Sources/Athar") / path.name
        shutil.copyfile(path, target)
        evidence[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        assert target.read_bytes() == path.read_bytes()
    (package / "Package.swift").write_text('''// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "NoorWordingBehavior", targets: [
    .target(name: "Athar"), .testTarget(name: "BehaviorTests", dependencies: ["Athar"])
])
''', encoding="utf-8")
    print(json.dumps({"productionSourceSHA256": evidence, "acousticValidation": False}), flush=True)
    subprocess.run(["swift", "test", "--package-path", str(package)], check=True)
