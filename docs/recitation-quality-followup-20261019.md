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

That first-use check subsequently failed: after the actual OS Allow action,
the app terminated before study.elapsed could be inspected. Original artifact
SHA256 is2981becb039775d2512e80b4c72c0ef3a0a519f16417cbb5223ed9d1f30919d6.
The ips report identifies SIGABRT/_ReportRPCTimeout/AURemoteIO.Initialize at
AVAudioEngine.inputNode in QuranMicrophoneCapture.init on the main thread.
This is not a proved ASR failure, absent microphone hardware, or proof that the
cloud provider alone caused the failure.

Capture now opens/starts/stops/destroys its engine on one serial hardware lane,
instead of constructing inputNode on MainActor. Start is asynchronous; closing
or pausing drains outstanding startup and rejects late listening publication
before removing working files. The first-use workflow also includes source
location, storage cancellation and input lifecycle cases after this change.
The original one-tap OS assertion is retained. Actual execution of this repair
is required; moving the call does not by itself prove the OS timeout resolved.

Build6ad558807550aed8108ff7ab on943e833 then compiled and passed15selected
native lifecycle/location/storage cases in12.275s, including closing while
hardware startup is pending. The actual first-allow UI still failed. Its ips
shows the same RemoteIO RPC abort, now on Noor.MicrophoneHardware, while the
main thread is in its ordinary run loop. Thus the UI-thread blockage was
removed, but this does not establish successful microphone input. Original
archive and extracted reports: outputs/hardware-943-evidence.

The next distinct change uses the input-only record/measurement audio category
instead of opening an unnecessary duplex speaker route during live recitation.
Reference playback is already excluded by audio focus. A native policy case
checks the category; only the unchanged real OS first-allow/captured-frame UI
can establish that this route actually works. That result remains pending.
The UI predicate also reads its real elapsed label once per poll, preserving
the same five-second capture requirement and no-second-tap rule.

A separate mixed-precision candidate experiment preserves normalization,
softmax and their sensitive reductions/division in FP32 while considering
other operations for FP16. The source weights,26actual public/control cases,
raw-word equality requirement and negative controls remain the same. The
production compiler still explicitly requests float32 and validates its
existing byte pins; no shipping model or pin is changed by adding this manual
experiment. Candidate speed/size/accuracy are unknown until actual execution.

Code review then found an additional display ambiguity: if older accepted
words remained in the session, two conflicting latest acoustic bindings could
leave that older word highlighted. The display frontier now advances even on
conflict, clears the current highlight while retaining viewport history, and
allows coherent re-interpretation at the same source clock. A regression covers
this sequence and refusal to jump back to older audio. Native/Swift execution
of this new change is still required; the69case result predates it.
An unlocated/silent current window also clears the active-word highlight,
even if earlier accepted audio remains elsewhere in the session. This does
not hide any previously shown ayah, create a wording error, or replace source
observations. Fresh actual matching evidence can resume the highlight.

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
