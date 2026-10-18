# Live recitation in the Mushaf

The user explicitly requested permanent removal of recordings and the scope
picker, then requested professional and consented learner recordings for engine
evaluation. Evaluation fixtures are separate from private app recordings.

This change removes the unused scope, setup, recording browser, recording list
and legacy recording-controls views. The microphone remains in the original
Mushaf. It does not add a replacement workspace, score screen or history route.

Actual capture still writes protected temporary PCM for the current attempt.
Pause/background keeps that open reader's attempt resumable. Finish or closing
the reader drains capture, invalidates late recognition and deletes the session
under the journal's write lock. Late analysis must load an existing session and
therefore cannot recreate deleted files. A fresh launch starts a fresh attempt.
Previously shown ayahs remain visible during the same attempt, without becoming
permanent correctness evidence.

On upgrade/start, only the two legacy learner-recording roots and expired
live-recitation workspaces are removed. Bookmarks, khatmah, account data, Quran
resources and cached professional-reciter audio are outside these roots. This
code runs on the device after installation; it has not remotely deleted files
from an already installed TestFlight build. Files exported outside the app are
outside its control. Privacy text and export controls follow this retention.

Four native regression cases cover scoped migration, deletion against late
analysis, actual reference PCM teardown, and permission completion after close.
They have been written and parsed locally, not executed on Windows. The new
bounded GitHub workflow runs current-source Release checks on a standard public
repository runner, with separate result bundles for unit, microphone and privacy
journeys. No paid Codemagic run is authorized by this change.

The preceding09c1bae native run6ad531b77550aed8108ff045 failed:
twenty-page khatmah passed73.304s, walkthrough exceeded300s; background test never
reached capture because it expected an unmaterialized List row112; one-tap lost
the app connection at the elapsed assertion. That lost connection's cause is
unconfirmed. The helper now uses the actual public surah search. The preceding
failure is retained and cannot certify this new app source.

No claims of comparison superiority, natural-learner accuracy, Tajweed acoustic
assessment, full20-reciter word timing or full Release acceptance follow from
these changes. TestFlight24 is still the installed earlier app source.

## Matching native result and subsequent repair

GitHub39168566049 on f543ffe (app behavior26034dc) compiled Release with
project-accounts/Xcode26.3/iOS26.2. Twelve selected units passed, including real
reference PCM disposal, migration isolation, permission cancellation, source
revision visibility and input lifecycle. Actual one-tap microphone UI passed
47.340s; privacy UI passed24.832s. Overall FAILED: the long-capture case stopped
at2s before it could reach its background step. Original log and screenshots
are preserved in outputs/live-f543-evidence, outside the repository.

Failure hierarchy shows the actual tracking-update error and a paused2s take.
Both production no-speech branches constructed an empty observations array
without a recognition-window UUID. The strict journal requires identity even
for that empty array. This is an app defect, not evidence of unavailable sound
hardware or a background-resume failure. Both paths now share an identified
no-speech result factory. No word is invented, ASR is not prepared for silence,
and journal validation remains strict. A new controller silence/pause/resume
negative control and portable missing-identity regression cover the defect.
These newer changes require their own native run; the earlier pass is not theirs.

The new display-location frontier independently prevents an older overlapping
word interpretation from moving the viewport backward. Retracted word evidence
loses active highlighting while already shown text remains readable; a genuine
later rereading can move to an earlier verse. This is display history, not added
recitation correctness. Location reduction runs off the main actor alongside
alignment. Four portable regressions cover ordering, withdrawal, repeated/backward
recitation clocks and new-take isolation; native integration remains pending.
