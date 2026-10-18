# Current recitation quality follow-up

Codemagic build6ad54ca97550aed8108ff5a7 at54b1ede finished in13m58s.
Its69selected Release native cases passed with0failures in58.564s on
iPhone17Pro/iOS26.2, Xcode26.3, accounts project. The actual rendered log
reported testExit0. The app/model/project trees matched595cab2; this was not a
full-product pass. Original evidence is held separately in
outputs/codemagic-54b-evidence/receipt.json and actual-test-lines.txt.

First-use OS permission is a distinct actual UI check at7089ea1:
build6ad553657550aed8108ff6d1. It resets the real microphone permission,
requires the OS prompt and permits only one original microphone tap. Result
was pending when this note was written. No accuracy claim follows from capture.

Code review then found an additional display ambiguity: if older accepted
words remained in the session, two conflicting latest acoustic bindings could
leave that older word highlighted. The display frontier now advances even on
conflict, clears the current highlight while retaining viewport history, and
allows coherent re-interpretation at the same source clock. A regression covers
this sequence and refusal to jump back to older audio. Native/Swift execution
of this new change is still required; the69case result predates it.

Professional-reciter development audit also had a retry preservation defect.
When a partial chapter needed a new negative-control excerpt, failed DNS on
refetch could replace an already measured recording checkpoint with a fetch
failure. Retries now archive exact prior report bytes, retain compatible
measured intervals with a separate failed source-check result, and stop the
batch on host DNS failure. A changed recording/hash is never inherited. Nine
audit/persistence policy cases passed locally; these are not acoustic results.

The local continuation encountered DNS failure, not an acoustic rejection.
Its pre-existing partial111 report was overwritten before this repair; seven
historical candidates need real remeasurement. The earlier177candidate
aggregate remains a historical receipt, not current verified coverage.
Reports produced under the previous tool fingerprint require a new review;
none are promoted into production by this maintenance change.

Natural learner accuracy/false-alert calibration, physical microphone latency,
all20readers/all114surahs production timings, acoustic Tajweed assessment,
complete Release acceptance and original reviewed publication gates remain
incomplete. Build24 is still the installed TestFlight build. No new upload is
claimed by these checks or this note.
